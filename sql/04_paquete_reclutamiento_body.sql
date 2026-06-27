-- =====================================================================
-- Proyecto 1 (pivote): Motor de pipeline de reclutamiento (ATS)
-- Archivo 04: CUERPO del paquete  PKG_RECLUTAMIENTO
-- =====================================================================
-- REGLAS ORACLE que difieren de PostgreSQL:
--   • SELECT INTO lanza NO_DATA_FOUND si no hay filas (en PG devuelve NULL).
--   • El procedimiento NO hace COMMIT; el control de transacción queda en
--     el caller (excepto la cancelación parcial con SAVEPOINT en contratar).
--   • SYS_CONTEXT('USERENV','SESSION_USER') es el equivalente de current_user.
--   • RETURNING id INTO v_var es equivalente a RETURNING id en PG, pero
--     requiere variable local (no set returning).
--   • FOR UPDATE NOWAIT bloquea la fila o lanza ORA-00054 de inmediato
--     en vez de esperar (defensivo ante concurrencia en contratar).
-- =====================================================================

CREATE OR REPLACE PACKAGE BODY pkg_reclutamiento AS

  -- ----- Excepción interna: fila bloqueada por otra sesión (ORA-00054) --
  e_resource_busy EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_resource_busy, -54);

  -- ----- Helper privado: usuario de auditoría con fallback a sesión ------
  FUNCTION f_usuario(p_usuario IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN COALESCE(p_usuario, SYS_CONTEXT('USERENV', 'SESSION_USER'));
  END f_usuario;


  -- =====================================================================
  -- FUNCIÓN: candidatos_en_etapa
  -- =====================================================================
  FUNCTION candidatos_en_etapa(
    p_vacante_id   IN NUMBER,
    p_etapa_codigo IN VARCHAR2
  ) RETURN NUMBER IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*)
      INTO v_count
      FROM postulaciones p
      JOIN etapas        e ON e.id = p.etapa_actual_id
     WHERE p.vacante_id = p_vacante_id
       AND e.codigo     = p_etapa_codigo
       AND p.activo     = 'S';
    RETURN v_count;
  END candidatos_en_etapa;


  -- =====================================================================
  -- PROCEDIMIENTO: registrar_postulacion
  -- =====================================================================
  PROCEDURE registrar_postulacion(
    p_vacante_id   IN NUMBER,
    p_candidato_id IN NUMBER,
    p_usuario      IN VARCHAR2 DEFAULT NULL
  ) IS
    v_etapa_id NUMBER;
    v_post_id  NUMBER;
    v_dummy    NUMBER;
    v_usuario  VARCHAR2(60) := f_usuario(p_usuario);
  BEGIN
    -- 1) Vacante existe y está abierta
    BEGIN
      SELECT id INTO v_dummy
        FROM vacantes
       WHERE id = p_vacante_id AND estatus = 'ABIERTA';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20101,
          'Vacante ' || p_vacante_id || ' no existe o no está abierta.');
    END;

    -- 2) Candidato existe y está activo
    BEGIN
      SELECT id INTO v_dummy
        FROM candidatos
       WHERE id = p_candidato_id AND activo = 'S';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20102,
          'Candidato ' || p_candidato_id || ' no existe o no está activo.');
    END;

    -- 3) Sin postulación duplicada
    --    La UNIQUE constraint es la red de seguridad ante concurrencia;
    --    este SELECT evita el error críptico de ORA-00001 en el caso feliz.
    BEGIN
      SELECT id INTO v_dummy
        FROM postulaciones
       WHERE vacante_id   = p_vacante_id
         AND candidato_id = p_candidato_id;
      -- Llegamos aquí → ya existe → duplicado
      RAISE_APPLICATION_ERROR(-20106,
        'El candidato ya tiene una postulación para esta vacante.');
    EXCEPTION
      WHEN NO_DATA_FOUND THEN NULL;  -- correcto, podemos continuar
    END;

    -- 4) Recuperar ID de la etapa inicial (siempre debe existir en catálogo)
    SELECT id INTO v_etapa_id FROM etapas WHERE codigo = 'POSTULADO';

    -- 5) Insertar postulación
    INSERT INTO postulaciones(vacante_id, candidato_id, etapa_actual_id)
    VALUES (p_vacante_id, p_candidato_id, v_etapa_id)
    RETURNING id INTO v_post_id;

    -- 6) Bitácora (etapa_anterior_id NULL = entrada al pipeline)
    INSERT INTO historial_postulacion
           (postulacion_id, etapa_anterior_id, etapa_nueva_id, usuario, motivo)
    VALUES (v_post_id, NULL, v_etapa_id, v_usuario, 'Postulación inicial');

  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      -- Race-condition: dos sesiones pasaron la verificación simultáneamente
      RAISE_APPLICATION_ERROR(-20106,
        'El candidato ya tiene una postulación para esta vacante.');
  END registrar_postulacion;


  -- =====================================================================
  -- PROCEDIMIENTO: mover_candidato
  -- =====================================================================
  PROCEDURE mover_candidato(
    p_postulacion_id IN NUMBER,
    p_etapa_destino  IN VARCHAR2,
    p_usuario        IN VARCHAR2 DEFAULT NULL,
    p_motivo         IN VARCHAR2 DEFAULT NULL
  ) IS
    v_etapa_actual_id  NUMBER;
    v_etapa_destino_id NUMBER;
    v_es_final         CHAR(1);
    v_usuario          VARCHAR2(60) := f_usuario(p_usuario);
    v_count            NUMBER;
  BEGIN
    -- 1) Bloquear la postulación (NOWAIT: falla rápido si hay contención)
    BEGIN
      SELECT etapa_actual_id INTO v_etapa_actual_id
        FROM postulaciones
       WHERE id = p_postulacion_id AND activo = 'S'
         FOR UPDATE NOWAIT;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20103,
          'Postulación ' || p_postulacion_id || ' no existe o no está activa.');
      WHEN e_resource_busy THEN
        RAISE_APPLICATION_ERROR(-20103,
          'Postulación ' || p_postulacion_id || ' en uso. Intente de nuevo.');
    END;

    -- 2) Etapa destino válida en el catálogo
    BEGIN
      SELECT id, es_final INTO v_etapa_destino_id, v_es_final
        FROM etapas
       WHERE codigo = p_etapa_destino AND activo = 'S';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20104,
          'Etapa destino "' || p_etapa_destino || '" no existe o no está activa.');
    END;

    -- 3) El salto debe existir en la tabla de transiciones_permitidas
    SELECT COUNT(*) INTO v_count
      FROM transiciones_permitidas
     WHERE etapa_origen_id  = v_etapa_actual_id
       AND etapa_destino_id = v_etapa_destino_id;

    IF v_count = 0 THEN
      RAISE_APPLICATION_ERROR(-20104,
        'Transición no permitida hacia "' || p_etapa_destino || '" desde la etapa actual.');
    END IF;

    -- 4) Actualizar la etapa actual de la postulación
    UPDATE postulaciones
       SET etapa_actual_id = v_etapa_destino_id
     WHERE id = p_postulacion_id;

    -- 5) Registrar en la bitácora de negocio
    INSERT INTO historial_postulacion
           (postulacion_id, etapa_anterior_id, etapa_nueva_id, usuario, motivo)
    VALUES (p_postulacion_id, v_etapa_actual_id, v_etapa_destino_id, v_usuario, p_motivo);

  END mover_candidato;


  -- =====================================================================
  -- PROCEDIMIENTO: rechazar  (atajo semántico sobre mover_candidato)
  -- =====================================================================
  PROCEDURE rechazar(
    p_postulacion_id IN NUMBER,
    p_usuario        IN VARCHAR2 DEFAULT NULL,
    p_motivo         IN VARCHAR2 DEFAULT NULL
  ) IS
  BEGIN
    mover_candidato(
      p_postulacion_id => p_postulacion_id,
      p_etapa_destino  => 'RECHAZADO',
      p_usuario        => p_usuario,
      p_motivo         => p_motivo
    );
  END rechazar;


  -- =====================================================================
  -- PROCEDIMIENTO: contratar  (operación atómica con SAVEPOINT)
  -- =====================================================================
  -- Patrón SAVEPOINT en Oracle:
  --   A diferencia de un bloque EXCEPTION que hace rollback implícito de
  --   todo el bloque (PL/pgSQL), aquí el SAVEPOINT sólo deshace el trabajo
  --   de ESTE procedimiento, preservando cualquier trabajo previo del caller.
  --   El RAISE final propaga la excepción para que el caller pueda reaccionar.
  -- =====================================================================
  PROCEDURE contratar(
    p_postulacion_id IN NUMBER,
    p_honorarios     IN NUMBER   DEFAULT 0,
    p_usuario        IN VARCHAR2 DEFAULT NULL
  ) IS
    v_vacante_id   NUMBER;
    v_candidato_id NUMBER;
    v_plazas_tot   NUMBER;
    v_plazas_cub   NUMBER;
    v_usuario      VARCHAR2(60) := f_usuario(p_usuario);
  BEGIN
    SAVEPOINT sp_contratar;

    -- 1) Obtener datos de la postulación (sin bloqueo; mover_candidato la bloqueará)
    BEGIN
      SELECT vacante_id, candidato_id
        INTO v_vacante_id, v_candidato_id
        FROM postulaciones
       WHERE id = p_postulacion_id AND activo = 'S';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20103,
          'Postulación ' || p_postulacion_id || ' no existe o no está activa.');
    END;

    -- 2) Bloquear la vacante para serializar contrataciones concurrentes
    BEGIN
      SELECT plazas_total, plazas_cubiertas
        INTO v_plazas_tot, v_plazas_cub
        FROM vacantes
       WHERE id = v_vacante_id AND estatus = 'ABIERTA'
         FOR UPDATE NOWAIT;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20101,
          'La vacante asociada no está disponible para contratación.');
      WHEN e_resource_busy THEN
        RAISE_APPLICATION_ERROR(-20101,
          'Vacante en uso por otra operación. Intente de nuevo.');
    END;

    -- 3) Verificar que quedan plazas
    IF v_plazas_cub >= v_plazas_tot THEN
      RAISE_APPLICATION_ERROR(-20105,
        'No hay plazas disponibles: ' || v_plazas_cub || '/' || v_plazas_tot || ' cubiertas.');
    END IF;

    -- 4a) Mover la postulación a CONTRATADO (valida la transición)
    mover_candidato(
      p_postulacion_id => p_postulacion_id,
      p_etapa_destino  => 'CONTRATADO',
      p_usuario        => v_usuario,
      p_motivo         => 'Contratación registrada'
    );

    -- 4b) Insertar el registro de contratación
    INSERT INTO contrataciones
           (postulacion_id, vacante_id, candidato_id, honorarios, usuario)
    VALUES (p_postulacion_id, v_vacante_id, v_candidato_id, NVL(p_honorarios, 0), v_usuario);

    -- 4c) Incrementar plazas cubiertas; cerrar vacante si ya está completa
    UPDATE vacantes
       SET plazas_cubiertas = v_plazas_cub + 1,
           estatus          = CASE WHEN v_plazas_cub + 1 >= v_plazas_tot
                                   THEN 'CERRADA' ELSE estatus      END,
           fecha_cierre     = CASE WHEN v_plazas_cub + 1 >= v_plazas_tot
                                   THEN SYSTIMESTAMP ELSE fecha_cierre END
     WHERE id = v_vacante_id;

  EXCEPTION
    WHEN OTHERS THEN
      -- Deshacer únicamente el trabajo de este procedimiento
      ROLLBACK TO SAVEPOINT sp_contratar;
      RAISE;
  END contratar;


END pkg_reclutamiento;
/
