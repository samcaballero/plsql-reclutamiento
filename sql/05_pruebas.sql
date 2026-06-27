-- =====================================================================
-- Proyecto 1 (pivote): Motor de pipeline de reclutamiento (ATS)
-- Archivo 05: Suite de pruebas — PKG_RECLUTAMIENTO
-- =====================================================================
-- Ejecutar DESPUÉS de 01–04.
-- No emite COMMIT; finaliza con ROLLBACK para no alterar el catálogo.
-- Cambiar el ROLLBACK final a COMMIT si desea conservar los datos.
-- Compatible con SQL*Plus, SQLcl y SQL Developer.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET VERIFY   OFF
SET DEFINE   OFF   -- evita que & se interprete como variable de sustitución

-- NOTA ORACLE vs PostgreSQL:
--   En PL/SQL NO se puede pasar (SELECT ... FROM ...) como argumento
--   directo a un procedimiento o función.  Oracle lanza PLS-00103.
--   La forma correcta es SELECT INTO una variable local y luego pasar
--   la variable.  Los bloques de abajo siguen este patrón.

PROMPT
PROMPT ============================================================
PROMPT   SUITE DE PRUEBAS  —  PKG_RECLUTAMIENTO
PROMPT ============================================================

-- =====================================================================
-- [1] DATOS DE PRUEBA
-- =====================================================================
PROMPT
PROMPT [1/5] Insertando datos de prueba...

BEGIN
  -- V-TEST-01: 2 plazas  → prueba cierre automático al cubrir la segunda
  INSERT INTO vacantes(codigo, titulo, cliente, plazas_total)
  VALUES ('V-TEST-01', 'Backend Senior',  'Acme Corp', 2);

  INSERT INTO vacantes(codigo, titulo, cliente, plazas_total)
  VALUES ('V-TEST-02', 'Frontend Junior', 'Acme Corp', 1);

  -- V-TEST-03: 1 plaza, se manipula directamente para provocar e_sin_plazas
  INSERT INTO vacantes(codigo, titulo, cliente, plazas_total)
  VALUES ('V-TEST-03', 'QA Analyst',      'Acme Corp', 1);

  INSERT INTO candidatos(nombre, email) VALUES ('Ana Garcia',    'ana@test.io');
  INSERT INTO candidatos(nombre, email) VALUES ('Beatriz Lopez', 'bea@test.io');
  INSERT INTO candidatos(nombre, email) VALUES ('Carlos Ruiz',   'carlos@test.io');
  INSERT INTO candidatos(nombre, email) VALUES ('David Mora',    'david@test.io');
  INSERT INTO candidatos(nombre, email) VALUES ('Elena Vega',    'elena@test.io');

  DBMS_OUTPUT.PUT_LINE('  OK  3 vacantes + 5 candidatos.');
END;
/

-- =====================================================================
-- [2] HAPPY PATH — postulaciones y avance por el pipeline
-- =====================================================================
PROMPT
PROMPT [2/5] Happy path...

-- ----- Registrar las 5 postulaciones ---------------------------------
DECLARE
  v_vac1 NUMBER;
  v_vac2 NUMBER;
  v_vac3 NUMBER;
  v_ana  NUMBER;
  v_bea  NUMBER;
  v_car  NUMBER;
  v_dav  NUMBER;
  v_ele  NUMBER;
BEGIN
  SELECT id INTO v_vac1 FROM vacantes   WHERE codigo = 'V-TEST-01';
  SELECT id INTO v_vac2 FROM vacantes   WHERE codigo = 'V-TEST-02';
  SELECT id INTO v_vac3 FROM vacantes   WHERE codigo = 'V-TEST-03';
  SELECT id INTO v_ana  FROM candidatos WHERE email  = 'ana@test.io';
  SELECT id INTO v_bea  FROM candidatos WHERE email  = 'bea@test.io';
  SELECT id INTO v_car  FROM candidatos WHERE email  = 'carlos@test.io';
  SELECT id INTO v_dav  FROM candidatos WHERE email  = 'david@test.io';
  SELECT id INTO v_ele  FROM candidatos WHERE email  = 'elena@test.io';

  -- Ana, Beatriz, Carlos → V-TEST-01 (2 plazas)
  pkg_reclutamiento.registrar_postulacion(v_vac1, v_ana, 'reclutador01');
  pkg_reclutamiento.registrar_postulacion(v_vac1, v_bea, 'reclutador01');
  pkg_reclutamiento.registrar_postulacion(v_vac1, v_car, 'reclutador01');
  -- David → V-TEST-02
  pkg_reclutamiento.registrar_postulacion(v_vac2, v_dav, 'reclutador01');
  -- Elena → V-TEST-03
  pkg_reclutamiento.registrar_postulacion(v_vac3, v_ele, 'reclutador01');

  DBMS_OUTPUT.PUT_LINE('  OK  5 postulaciones en POSTULADO.');
  DBMS_OUTPUT.PUT_LINE('      candidatos_en_etapa(V-TEST-01, POSTULADO) = ' ||
    pkg_reclutamiento.candidatos_en_etapa(v_vac1, 'POSTULADO'));
END;
/

-- ----- Ana: POSTULADO → PRESELECCION → ENTREVISTA → OFERTA ----------
DECLARE
  v_pid NUMBER;
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'ana@test.io' AND v.codigo = 'V-TEST-01';

  pkg_reclutamiento.mover_candidato(v_pid, 'PRESELECCION', 'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'ENTREVISTA',   'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'OFERTA',       'reclutador01', 'Excelente perfil');
  DBMS_OUTPUT.PUT_LINE('  OK  Ana    POSTULADO -> PRESEL -> ENTREVISTA -> OFERTA');
END;
/

-- ----- Beatriz: POSTULADO → PRESELECCION → RECHAZADO (via rechazar) -
DECLARE
  v_pid NUMBER;
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'bea@test.io' AND v.codigo = 'V-TEST-01';

  pkg_reclutamiento.mover_candidato(v_pid, 'PRESELECCION', 'reclutador01');
  pkg_reclutamiento.rechazar(v_pid, 'reclutador01', 'No cumple experiencia minima');
  DBMS_OUTPUT.PUT_LINE('  OK  Beatriz POSTULADO -> PRESEL -> RECHAZADO');
END;
/

-- ----- Carlos: POSTULADO → PRESELECCION → ENTREVISTA → OFERTA -------
DECLARE
  v_pid NUMBER;
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'carlos@test.io' AND v.codigo = 'V-TEST-01';

  pkg_reclutamiento.mover_candidato(v_pid, 'PRESELECCION', 'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'ENTREVISTA',   'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'OFERTA',       'reclutador01');
  DBMS_OUTPUT.PUT_LINE('  OK  Carlos  POSTULADO -> PRESEL -> ENTREVISTA -> OFERTA');
END;
/

-- ----- David: pipeline completo (V-TEST-02) --------------------------
DECLARE
  v_pid NUMBER;
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'david@test.io' AND v.codigo = 'V-TEST-02';

  pkg_reclutamiento.mover_candidato(v_pid, 'PRESELECCION', 'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'ENTREVISTA',   'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'OFERTA',       'reclutador01');
  DBMS_OUTPUT.PUT_LINE('  OK  David   POSTULADO -> PRESEL -> ENTREVISTA -> OFERTA');
END;
/

-- ----- Contratar Ana: V-TEST-01 queda 1/2, sigue ABIERTA ------------
DECLARE
  v_pid NUMBER;
  v_cub NUMBER;
  v_tot NUMBER;
  v_est VARCHAR2(12);
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'ana@test.io' AND v.codigo = 'V-TEST-01';

  pkg_reclutamiento.contratar(v_pid, 85000, 'reclutador01');

  SELECT plazas_cubiertas, plazas_total, estatus
    INTO v_cub, v_tot, v_est
    FROM vacantes WHERE codigo = 'V-TEST-01';
  DBMS_OUTPUT.PUT_LINE('  OK  Ana contratada.    V-TEST-01: ' ||
    v_cub || '/' || v_tot || ' — ' || v_est);
END;
/

-- ----- Contratar Carlos: V-TEST-01 queda 2/2, debe cerrarse ---------
DECLARE
  v_pid NUMBER;
  v_cub NUMBER;
  v_tot NUMBER;
  v_est VARCHAR2(12);
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'carlos@test.io' AND v.codigo = 'V-TEST-01';

  pkg_reclutamiento.contratar(v_pid, 72000, 'reclutador01');

  SELECT plazas_cubiertas, plazas_total, estatus
    INTO v_cub, v_tot, v_est
    FROM vacantes WHERE codigo = 'V-TEST-01';
  DBMS_OUTPUT.PUT_LINE('  OK  Carlos contratado.  V-TEST-01: ' ||
    v_cub || '/' || v_tot || ' — ' || v_est);
END;
/

-- ----- Contratar David: V-TEST-02 queda 1/1, debe cerrarse ----------
DECLARE
  v_pid NUMBER;
  v_cub NUMBER;
  v_tot NUMBER;
  v_est VARCHAR2(12);
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'david@test.io' AND v.codigo = 'V-TEST-02';

  pkg_reclutamiento.contratar(v_pid, 60000, 'reclutador01');

  SELECT plazas_cubiertas, plazas_total, estatus
    INTO v_cub, v_tot, v_est
    FROM vacantes WHERE codigo = 'V-TEST-02';
  DBMS_OUTPUT.PUT_LINE('  OK  David contratado.   V-TEST-02: ' ||
    v_cub || '/' || v_tot || ' — ' || v_est);
END;
/

-- =====================================================================
-- [3] EXCEPCIONES DE NEGOCIO — las 6 definidas en el spec
-- =====================================================================
-- OK   = excepcion esperada capturada   → comportamiento correcto
-- FAIL = no se lanzo nada, o se lanzo algo distinto → bug
-- =====================================================================
PROMPT
PROMPT [3/5] Excepciones de negocio...

-- ----- e_vacante_invalida (-20101) -----------------------------------
-- Vacante 99999 no existe; los literales numericos son validos como args.
BEGIN
  pkg_reclutamiento.registrar_postulacion(99999, 1, 'test');
  DBMS_OUTPUT.PUT_LINE('  FAIL  e_vacante_invalida: no se lanzo excepcion');
EXCEPTION
  WHEN pkg_reclutamiento.e_vacante_invalida THEN
    DBMS_OUTPUT.PUT_LINE('  OK   [e_vacante_invalida]      ' || SQLERRM);
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  FAIL [OTHERS]                  ' || SQLERRM);
END;
/

-- ----- e_candidato_invalido (-20102) ---------------------------------
-- V-TEST-03 sigue ABIERTA; candidato 99999 no existe.
DECLARE
  v_vac NUMBER;
BEGIN
  SELECT id INTO v_vac FROM vacantes WHERE codigo = 'V-TEST-03';
  pkg_reclutamiento.registrar_postulacion(v_vac, 99999, 'test');
  DBMS_OUTPUT.PUT_LINE('  FAIL  e_candidato_invalido: no se lanzo excepcion');
EXCEPTION
  WHEN pkg_reclutamiento.e_candidato_invalido THEN
    DBMS_OUTPUT.PUT_LINE('  OK   [e_candidato_invalido]    ' || SQLERRM);
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  FAIL [OTHERS]                  ' || SQLERRM);
END;
/

-- ----- e_postulacion_duplicada (-20106) ------------------------------
-- Elena ya esta registrada en V-TEST-03.
DECLARE
  v_vac  NUMBER;
  v_cand NUMBER;
BEGIN
  SELECT id INTO v_vac  FROM vacantes   WHERE codigo = 'V-TEST-03';
  SELECT id INTO v_cand FROM candidatos WHERE email  = 'elena@test.io';
  pkg_reclutamiento.registrar_postulacion(v_vac, v_cand, 'test');
  DBMS_OUTPUT.PUT_LINE('  FAIL  e_postulacion_duplicada: no se lanzo excepcion');
EXCEPTION
  WHEN pkg_reclutamiento.e_postulacion_duplicada THEN
    DBMS_OUTPUT.PUT_LINE('  OK   [e_postulacion_duplicada] ' || SQLERRM);
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  FAIL [OTHERS]                  ' || SQLERRM);
END;
/

-- ----- e_postulacion_invalida (-20103) --------------------------------
-- Postulacion 99999 no existe; el literal numerico es valido como arg.
BEGIN
  pkg_reclutamiento.mover_candidato(99999, 'PRESELECCION', 'test');
  DBMS_OUTPUT.PUT_LINE('  FAIL  e_postulacion_invalida: no se lanzo excepcion');
EXCEPTION
  WHEN pkg_reclutamiento.e_postulacion_invalida THEN
    DBMS_OUTPUT.PUT_LINE('  OK   [e_postulacion_invalida]  ' || SQLERRM);
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  FAIL [OTHERS]                  ' || SQLERRM);
END;
/

-- ----- e_transicion_invalida (a): salto ilegal en el pipeline --------
-- Elena esta en POSTULADO; POSTULADO->CONTRATADO no existe en el grafo.
DECLARE
  v_pid NUMBER;
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'elena@test.io' AND v.codigo = 'V-TEST-03';

  pkg_reclutamiento.mover_candidato(v_pid, 'CONTRATADO', 'test');
  DBMS_OUTPUT.PUT_LINE('  FAIL  e_transicion_invalida(salto): no se lanzo excepcion');
EXCEPTION
  WHEN pkg_reclutamiento.e_transicion_invalida THEN
    DBMS_OUTPUT.PUT_LINE('  OK   [e_transicion_invalida]   POSTULADO->CONTRATADO bloqueado');
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  FAIL [OTHERS]                  ' || SQLERRM);
END;
/

-- ----- e_transicion_invalida (b): desde un estado terminal -----------
-- Beatriz llego a RECHAZADO; ninguna arista sale de ese nodo.
DECLARE
  v_pid NUMBER;
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'bea@test.io' AND v.codigo = 'V-TEST-01';

  pkg_reclutamiento.mover_candidato(v_pid, 'ENTREVISTA', 'test');
  DBMS_OUTPUT.PUT_LINE('  FAIL  e_transicion_invalida(terminal): no se lanzo excepcion');
EXCEPTION
  WHEN pkg_reclutamiento.e_transicion_invalida THEN
    DBMS_OUTPUT.PUT_LINE('  OK   [e_transicion_invalida]   RECHAZADO->ENTREVISTA bloqueado');
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  FAIL [OTHERS]                  ' || SQLERRM);
END;
/

-- ----- e_sin_plazas (-20105) -----------------------------------------
-- Avanzamos a Elena hasta OFERTA (transiciones validas), luego forzamos
-- plazas_cubiertas = plazas_total sin cerrar la vacante.
-- Esto replica la condicion de carrera que el IF en contratar protege:
-- dos sesiones concurrentes pasan el bloqueo; la segunda choca aqui.
-- El SAVEPOINT en contratar revierte el intento sin afectar lo demas.
DECLARE
  v_pid NUMBER;
BEGIN
  SELECT p.id INTO v_pid
    FROM postulaciones p
    JOIN candidatos    c ON c.id = p.candidato_id
    JOIN vacantes      v ON v.id = p.vacante_id
   WHERE c.email = 'elena@test.io' AND v.codigo = 'V-TEST-03';

  -- Avanzar Elena por transiciones validas
  pkg_reclutamiento.mover_candidato(v_pid, 'PRESELECCION', 'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'ENTREVISTA',   'reclutador01');
  pkg_reclutamiento.mover_candidato(v_pid, 'OFERTA',       'reclutador01');

  -- Forzar plazas llenas sin cambiar estatus (simula postconcurrencia)
  UPDATE vacantes SET plazas_cubiertas = plazas_total
   WHERE codigo = 'V-TEST-03';

  -- Intento de contratacion: debe fallar
  BEGIN
    pkg_reclutamiento.contratar(v_pid, 55000, 'reclutador01');
    DBMS_OUTPUT.PUT_LINE('  FAIL  e_sin_plazas: no se lanzo excepcion');
  EXCEPTION
    WHEN pkg_reclutamiento.e_sin_plazas THEN
      DBMS_OUTPUT.PUT_LINE('  OK   [e_sin_plazas]            ' || SQLERRM);
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('  FAIL [OTHERS]                  ' || SQLERRM);
  END;

  -- Restaurar antes del ROLLBACK final para no dejar datos inconsistentes
  UPDATE vacantes SET plazas_cubiertas = 0 WHERE codigo = 'V-TEST-03';
END;
/

-- =====================================================================
-- [4] VERIFICACION FINAL
-- =====================================================================
PROMPT
PROMPT [4/5] Estado final del pipeline...

DECLARE
  CURSOR c_pipeline IS
    SELECT v.codigo  AS vacante,
           c.nombre  AS candidato,
           e.codigo  AS etapa,
           v.plazas_cubiertas || '/' || v.plazas_total AS plazas,
           v.estatus
      FROM postulaciones p
      JOIN vacantes   v ON v.id = p.vacante_id
      JOIN candidatos c ON c.id = p.candidato_id
      JOIN etapas     e ON e.id = p.etapa_actual_id
     WHERE v.codigo LIKE 'V-TEST-%'
     ORDER BY v.codigo, e.orden, c.nombre;
BEGIN
  DBMS_OUTPUT.PUT_LINE(
    RPAD('Vacante',11)  || RPAD('Candidato',17) ||
    RPAD('Etapa',14)    || RPAD('Plazas',8)     || 'Estatus');
  DBMS_OUTPUT.PUT_LINE(RPAD('-',58,'-'));
  FOR r IN c_pipeline LOOP
    DBMS_OUTPUT.PUT_LINE(
      RPAD(r.vacante,11)  || RPAD(r.candidato,17) ||
      RPAD(r.etapa,14)    || RPAD(r.plazas,8)      || r.estatus);
  END LOOP;
END;
/

PROMPT
PROMPT Historial de Ana Garcia en V-TEST-01:

DECLARE
  CURSOR c_hist IS
    SELECT NVL(ea.codigo, '(inicio)') AS de,
           en_.codigo                  AS a,
           NVL(h.motivo, '-')          AS motivo,
           TO_CHAR(h.fecha, 'HH24:MI:SS') AS hora
      FROM historial_postulacion h
      JOIN postulaciones  p   ON p.id   = h.postulacion_id
      JOIN candidatos     c   ON c.id   = p.candidato_id
      JOIN vacantes       v   ON v.id   = p.vacante_id
      JOIN etapas         en_ ON en_.id = h.etapa_nueva_id
 LEFT JOIN etapas         ea  ON ea.id  = h.etapa_anterior_id
     WHERE c.email = 'ana@test.io' AND v.codigo = 'V-TEST-01'
     ORDER BY h.id;
BEGIN
  FOR r IN c_hist LOOP
    DBMS_OUTPUT.PUT_LINE(
      '  ' || r.hora || '  ' ||
      RPAD(r.de, 12) || ' -> ' ||
      RPAD(r.a,  12) || r.motivo);
  END LOOP;
END;
/

PROMPT
PROMPT Contrataciones:

DECLARE
  CURSOR c_cont IS
    SELECT v.codigo  AS vacante,
           c.nombre  AS candidato,
           cn.honorarios,
           TO_CHAR(cn.fecha_contratacion, 'HH24:MI:SS') AS hora
      FROM contrataciones cn
      JOIN vacantes   v ON v.id = cn.vacante_id
      JOIN candidatos c ON c.id = cn.candidato_id
     WHERE v.codigo LIKE 'V-TEST-%'
     ORDER BY cn.id;
BEGIN
  FOR r IN c_cont LOOP
    DBMS_OUTPUT.PUT_LINE(
      '  ' || r.hora || '  ' ||
      RPAD(r.vacante,11)   ||
      RPAD(r.candidato,17) ||
      TO_CHAR(r.honorarios, '$999,990'));
  END LOOP;
END;
/

-- =====================================================================
-- [5] LIMPIEZA
-- =====================================================================
PROMPT
PROMPT [5/5] ROLLBACK — datos de prueba revertidos.
PROMPT        Cambiar a COMMIT para conservar el estado final.

ROLLBACK;
