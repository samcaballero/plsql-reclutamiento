-- =====================================================================
-- Proyecto 1 (pivote): Motor de pipeline de reclutamiento (ATS)
-- Archivo 06: Trigger de auditoría técnica — trg_auditar_postulacion
-- =====================================================================
-- DOS CAPAS DE AUDITORÍA (diseño intencional, complementarias):
--
--   historial_postulacion    — capa de NEGOCIO
--     Escrita EXPLÍCITAMENTE por el paquete.
--     Captura: usuario de aplicación + motivo del cambio.
--     Solo se registra si el cambio pasó por pkg_reclutamiento.
--
--   auditoria_postulaciones  — capa TÉCNICA (este archivo)
--     Escrita AUTOMÁTICAMENTE por el trigger.
--     Captura: usuario de BD, sin importar cómo llegó el UPDATE.
--     Si alguien bypasea el paquete con un UPDATE directo, el trigger
--     igual registra el movimiento pero historial quedará vacío.
--     Esa DIVERGENCIA entre ambas tablas es en sí misma una señal.
--
-- NOTA ORACLE — transacción del trigger:
--   La INSERT que hace el trigger vive en la MISMA transacción que el
--   UPDATE disparador. Si esa transacción hace ROLLBACK, el registro
--   de auditoría también se revierte — no quedan rastros de cambios
--   que nunca ocurrieron. Para un audit inmutable (que sobreviva al
--   ROLLBACK) se usaría PRAGMA AUTONOMOUS_TRANSACTION + COMMIT dentro
--   del trigger. Aquí preferimos coherencia transaccional sobre
--   inmutabilidad absoluta; ese trade-off es una decisión de diseño.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED

-- =====================================================================
-- 1. TABLA DE AUDITORÍA TÉCNICA
-- =====================================================================
-- Sin FK hacia etapas ni postulaciones: los registros de auditoría
-- deben sobrevivir cualquier limpieza de datos operacionales.
--
-- IF NOT EXISTS: sintaxis disponible a partir de Oracle 23ai (23c).
-- En versiones anteriores se usa EXECUTE IMMEDIATE + captura de ORA-00955.

CREATE TABLE IF NOT EXISTS auditoria_postulaciones (
  id                NUMBER       GENERATED ALWAYS AS IDENTITY,
  postulacion_id    NUMBER       NOT NULL,
  etapa_anterior_id NUMBER       NOT NULL,
  etapa_nueva_id    NUMBER       NOT NULL,
  usuario_bd        VARCHAR2(60) NOT NULL,
  fecha             TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_aud_post PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS ix_aud_post_pid
  ON auditoria_postulaciones(postulacion_id);

-- =====================================================================
-- 2. TRIGGER
-- =====================================================================
-- Por qué AFTER y no BEFORE:
--   AFTER garantiza que el UPDATE ya pasó todas las validaciones de
--   constraint de Oracle. Un BEFORE podría auditar un cambio que luego
--   Oracle revierte por FK violation u otro error — falso positivo.
--
-- WHEN (OLD.etapa_actual_id <> NEW.etapa_actual_id):
--   UPDATE OF etapa_actual_id dispara el trigger siempre que esa columna
--   aparezca en el SET, aunque el valor no cambie. La cláusula WHEN
--   filtra ese ruido. Ojo: en WHEN no se usan los dos puntos (:OLD, :NEW);
--   en el BODY sí son obligatorios.

CREATE OR REPLACE TRIGGER trg_auditar_postulacion
AFTER UPDATE OF etapa_actual_id ON postulaciones
FOR EACH ROW
WHEN (OLD.etapa_actual_id <> NEW.etapa_actual_id)
BEGIN
  INSERT INTO auditoria_postulaciones
         (postulacion_id, etapa_anterior_id, etapa_nueva_id, usuario_bd)
  VALUES (:OLD.id,
          :OLD.etapa_actual_id,
          :NEW.etapa_actual_id,
          SYS_CONTEXT('USERENV', 'SESSION_USER'));
END trg_auditar_postulacion;
/

SHOW ERRORS TRIGGER trg_auditar_postulacion

-- =====================================================================
-- 3. VERIFICACIÓN: trigger existe, está habilitado y compiló sin errores
-- =====================================================================

DECLARE
  v_status VARCHAR2(10);
  v_type   VARCHAR2(20);
  v_errors NUMBER;
BEGIN
  -- Estado en el diccionario
  SELECT status, trigger_type
    INTO v_status, v_type
    FROM user_triggers
   WHERE trigger_name = 'TRG_AUDITAR_POSTULACION';

  -- Errores de compilación pendientes
  SELECT COUNT(*) INTO v_errors
    FROM user_errors
   WHERE name = 'TRG_AUDITAR_POSTULACION'
     AND type = 'TRIGGER';

  IF v_errors > 0 THEN
    DBMS_OUTPUT.PUT_LINE('FAIL trg_auditar_postulacion tiene ' ||
      v_errors || ' error(es) de compilacion — ver SHOW ERRORS arriba.');
  ELSIF v_status = 'ENABLED' THEN
    DBMS_OUTPUT.PUT_LINE('OK   trg_auditar_postulacion ' ||
      v_type || ' — ' || v_status);
  ELSE
    DBMS_OUTPUT.PUT_LINE('WARN trg_auditar_postulacion existe pero esta ' || v_status);
  END IF;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('FAIL trg_auditar_postulacion no encontrado en USER_TRIGGERS');
END;
/

-- Vista rápida del diccionario para confirmar los detalles
SELECT trigger_name,
       trigger_type,
       triggering_event,
       table_name,
       status
  FROM user_triggers
 WHERE trigger_name = 'TRG_AUDITAR_POSTULACION';
