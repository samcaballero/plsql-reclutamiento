-- =====================================================================
-- Proyecto 1 (pivote): Motor de pipeline de reclutamiento (ATS)
-- Archivo 03: ESPECIFICACIÓN del paquete  PKG_RECLUTAMIENTO
-- =====================================================================
-- Esto es el CONTRATO (la interfaz pública). El CUERPO (BODY) con la
-- implementación se construye en el siguiente chat. Esta especificación
-- compila por sí sola y sirve como guía de lo que hay que implementar.
-- =====================================================================

CREATE OR REPLACE PACKAGE pkg_reclutamiento AS

  -- ----- Excepciones de negocio (capturables por nombre) -------------
  e_vacante_invalida      EXCEPTION;
  e_candidato_invalido    EXCEPTION;
  e_postulacion_invalida  EXCEPTION;
  e_transicion_invalida   EXCEPTION;
  e_sin_plazas            EXCEPTION;
  e_postulacion_duplicada EXCEPTION;

  PRAGMA EXCEPTION_INIT(e_vacante_invalida,      -20101);
  PRAGMA EXCEPTION_INIT(e_candidato_invalido,    -20102);
  PRAGMA EXCEPTION_INIT(e_postulacion_invalida,  -20103);
  PRAGMA EXCEPTION_INIT(e_transicion_invalida,   -20104);
  PRAGMA EXCEPTION_INIT(e_sin_plazas,            -20105);
  PRAGMA EXCEPTION_INIT(e_postulacion_duplicada, -20106);

  -- ----- Reporte: cuántos candidatos hay en una etapa de una vacante --
  FUNCTION candidatos_en_etapa(
    p_vacante_id   IN NUMBER,
    p_etapa_codigo IN VARCHAR2
  ) RETURN NUMBER;

  -- ----- Registrar la postulación de un candidato a una vacante ------
  -- Valida vacante abierta, candidato activo y no duplicado.
  -- Crea la postulación en la etapa inicial 'POSTULADO'.
  PROCEDURE registrar_postulacion(
    p_vacante_id   IN NUMBER,
    p_candidato_id IN NUMBER,
    p_usuario      IN VARCHAR2 DEFAULT NULL
  );

  -- ----- Mover un candidato a otra etapa (transición validada) -------
  -- Verifica contra transiciones_permitidas; si el salto no existe,
  -- lanza e_transicion_invalida. Registra el cambio en el historial.
  PROCEDURE mover_candidato(
    p_postulacion_id IN NUMBER,
    p_etapa_destino  IN VARCHAR2,             -- código de etapa destino
    p_usuario        IN VARCHAR2 DEFAULT NULL,
    p_motivo         IN VARCHAR2 DEFAULT NULL
  );

  -- ----- Atajo: rechazar una postulación -----------------------------
  -- Reutiliza mover_candidato hacia la etapa 'RECHAZADO'.
  PROCEDURE rechazar(
    p_postulacion_id IN NUMBER,
    p_usuario        IN VARCHAR2 DEFAULT NULL,
    p_motivo         IN VARCHAR2 DEFAULT NULL
  );

  -- ----- Contratación ATÓMICA ----------------------------------------
  -- Estas tres cosas ocurren juntas o no ocurre ninguna (SAVEPOINT/ROLLBACK):
  --   1) mover la postulación a 'CONTRATADO' (transición validada)
  --   2) registrar la fila en contrataciones
  --   3) sumar 1 a plazas_cubiertas y cerrar la vacante si se llenó
  -- Rechaza si la vacante no está abierta o no hay plazas disponibles.
  PROCEDURE contratar(
    p_postulacion_id IN NUMBER,
    p_honorarios     IN NUMBER   DEFAULT 0,
    p_usuario        IN VARCHAR2 DEFAULT NULL
  );

END pkg_reclutamiento;
/
