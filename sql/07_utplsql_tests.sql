-- =====================================================================
-- Proyecto 1 (pivote): Motor de pipeline de reclutamiento (ATS)
-- Archivo 07: Suite utPLSQL — PKG_RECLUTAMIENTO
-- =====================================================================
-- Requiere : utPLSQL v3.x instalado (esquema ut3, rol ut_user_role).
-- Conexión : system/Oracle23ai@//localhost:1521/FREEPDB1
-- Ejecutar DESPUÉS de 01–06.
-- =====================================================================

SET DEFINE     OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK   OFF

-- =====================================================================
-- ESPECIFICACIÓN DEL PAQUETE DE PRUEBAS
-- =====================================================================

CREATE OR REPLACE PACKAGE ut_pkg_reclutamiento AS

  --%suite(PKG_RECLUTAMIENTO)
  --%rollback(manual)

  --%beforeall
  PROCEDURE setup_fixtures;

  --%test(registrar_postulacion: happy path crea postulacion en POSTULADO)
  PROCEDURE test_registrar_happy;

  --%test(registrar_postulacion: duplicado lanza e_postulacion_duplicada)
  PROCEDURE test_registrar_duplicado;

  --%test(mover_candidato: transicion valida POSTULADO a PRESELECCION)
  PROCEDURE test_mover_valido;

  --%test(mover_candidato: salto ilegal POSTULADO a CONTRATADO lanza e_transicion_invalida)
  PROCEDURE test_mover_invalido;

  --%test(rechazar: es atajo valido a RECHAZADO desde cualquier etapa intermedia)
  PROCEDURE test_rechazar;

  --%test(contratar: atomico incrementa plazas y cierra vacante al cubrirlas todas)
  PROCEDURE test_contratar_atomico;

  --%test(contratar: sin plazas disponibles lanza e_sin_plazas)
  PROCEDURE test_contratar_sin_plazas;

  --%test(candidatos_en_etapa: cuenta correctamente por etapa dentro de una vacante)
  PROCEDURE test_candidatos_en_etapa;

  --%afterall
  PROCEDURE teardown;

END ut_pkg_reclutamiento;
/

SHOW ERRORS PACKAGE ut_pkg_reclutamiento;

-- =====================================================================
-- CUERPO DEL PAQUETE DE PRUEBAS
-- =====================================================================

CREATE OR REPLACE PACKAGE BODY ut_pkg_reclutamiento AS

  -- ----------------------------------------------------------------
  -- Estado compartido entre tests (asignado en setup_fixtures)
  -- ----------------------------------------------------------------
  g_v1_id  NUMBER;   -- V-UT-01  (2 plazas — mover / rechazar / contar)
  g_v2_id  NUMBER;   -- V-UT-02  (2 plazas — contratar atomico)
  g_v3_id  NUMBER;   -- V-UT-03  (1 plaza  — sin plazas)
  g_ana    NUMBER;   -- candidata Ana
  g_bea    NUMBER;   -- candidata Beatriz
  g_car    NUMBER;   -- candidato Carlos
  g_dav    NUMBER;   -- candidato David
  g_ele    NUMBER;   -- candidata Elena

  -- ----------------------------------------------------------------
  -- %beforeall — fixtures base: 3 vacantes + 5 candidatos
  -- ----------------------------------------------------------------
  PROCEDURE setup_fixtures IS
  BEGIN
    INSERT INTO vacantes(codigo, titulo, cliente, plazas_total)
    VALUES ('V-UT-01', 'PL/SQL Developer', 'UT Corp', 2)
    RETURNING id INTO g_v1_id;

    INSERT INTO vacantes(codigo, titulo, cliente, plazas_total)
    VALUES ('V-UT-02', 'DBA Junior', 'UT Corp', 2)
    RETURNING id INTO g_v2_id;

    INSERT INTO vacantes(codigo, titulo, cliente, plazas_total)
    VALUES ('V-UT-03', 'QA Analyst', 'UT Corp', 1)
    RETURNING id INTO g_v3_id;

    INSERT INTO candidatos(nombre, email) VALUES ('Ana UT',    'ana@ut.test')    RETURNING id INTO g_ana;
    INSERT INTO candidatos(nombre, email) VALUES ('Bea UT',    'bea@ut.test')    RETURNING id INTO g_bea;
    INSERT INTO candidatos(nombre, email) VALUES ('Carlos UT', 'carlos@ut.test') RETURNING id INTO g_car;
    INSERT INTO candidatos(nombre, email) VALUES ('David UT',  'david@ut.test')  RETURNING id INTO g_dav;
    INSERT INTO candidatos(nombre, email) VALUES ('Elena UT',  'elena@ut.test')  RETURNING id INTO g_ele;
  END setup_fixtures;

  -- ----------------------------------------------------------------
  -- TEST 1 — registrar_postulacion: happy path
  --
  -- Dado:  Ana no tiene postulacion en V-UT-01
  -- Cuando: se llama registrar_postulacion
  -- Entonces: candidatos_en_etapa devuelve 1 en POSTULADO
  -- ----------------------------------------------------------------
  PROCEDURE test_registrar_happy IS
    l_count NUMBER;
  BEGIN
    pkg_reclutamiento.registrar_postulacion(g_v1_id, g_ana, 'ut_user');

    l_count := pkg_reclutamiento.candidatos_en_etapa(g_v1_id, 'POSTULADO');
    ut3.ut.expect(l_count).to_equal(1);
  END test_registrar_happy;

  -- ----------------------------------------------------------------
  -- TEST 2 — registrar_postulacion: duplicado
  --
  -- Dado:  Ana ya esta en V-UT-01 (test anterior)
  -- Cuando: se intenta registrar de nuevo
  -- Entonces: se lanza e_postulacion_duplicada (-20106)
  -- ----------------------------------------------------------------
  PROCEDURE test_registrar_duplicado IS
    l_raised BOOLEAN := FALSE;
  BEGIN
    BEGIN
      pkg_reclutamiento.registrar_postulacion(g_v1_id, g_ana, 'ut_user');
    EXCEPTION
      WHEN pkg_reclutamiento.e_postulacion_duplicada THEN
        l_raised := TRUE;
    END;
    ut3.ut.expect(l_raised).to_be_true();
  END test_registrar_duplicado;

  -- ----------------------------------------------------------------
  -- TEST 3 — mover_candidato: transicion valida
  --
  -- Dado:  Ana esta en POSTULADO en V-UT-01
  -- Cuando: se mueve a PRESELECCION (arista existente en el grafo)
  -- Entonces: etapa_actual_id refleja PRESELECCION
  -- ----------------------------------------------------------------
  PROCEDURE test_mover_valido IS
    l_pid       NUMBER;
    l_etapa_cod VARCHAR2(20);
  BEGIN
    SELECT p.id INTO l_pid
      FROM postulaciones p
     WHERE p.vacante_id   = g_v1_id
       AND p.candidato_id = g_ana;

    pkg_reclutamiento.mover_candidato(l_pid, 'PRESELECCION', 'ut_user');

    SELECT e.codigo INTO l_etapa_cod
      FROM postulaciones p
      JOIN etapas        e ON e.id = p.etapa_actual_id
     WHERE p.id = l_pid;

    ut3.ut.expect(l_etapa_cod).to_equal('PRESELECCION');
  END test_mover_valido;

  -- ----------------------------------------------------------------
  -- TEST 4 — mover_candidato: salto ilegal
  --
  -- Dado:  Bea se registra en V-UT-01 (POSTULADO)
  -- Cuando: se intenta saltar directo a CONTRATADO (sin arista)
  -- Entonces: se lanza e_transicion_invalida (-20104)
  --           y el estado de Bea permanece en POSTULADO
  -- ----------------------------------------------------------------
  PROCEDURE test_mover_invalido IS
    l_raised    BOOLEAN := FALSE;
    l_pid       NUMBER;
    l_etapa_cod VARCHAR2(20);
  BEGIN
    pkg_reclutamiento.registrar_postulacion(g_v1_id, g_bea, 'ut_user');

    SELECT p.id INTO l_pid
      FROM postulaciones p
     WHERE p.vacante_id   = g_v1_id
       AND p.candidato_id = g_bea;

    BEGIN
      pkg_reclutamiento.mover_candidato(l_pid, 'CONTRATADO', 'ut_user');
    EXCEPTION
      WHEN pkg_reclutamiento.e_transicion_invalida THEN
        l_raised := TRUE;
    END;

    SELECT e.codigo INTO l_etapa_cod
      FROM postulaciones p
      JOIN etapas        e ON e.id = p.etapa_actual_id
     WHERE p.id = l_pid;

    ut3.ut.expect(l_raised).to_be_true();
    ut3.ut.expect(l_etapa_cod).to_equal('POSTULADO');  -- estado no cambio
  END test_mover_invalido;

  -- ----------------------------------------------------------------
  -- TEST 5 — rechazar
  --
  -- Dado:  Carlos se registra en V-UT-01 y avanza a PRESELECCION
  -- Cuando: se llama rechazar
  -- Entonces: etapa_actual_id es RECHAZADO (atajo valido)
  -- ----------------------------------------------------------------
  PROCEDURE test_rechazar IS
    l_pid       NUMBER;
    l_etapa_cod VARCHAR2(20);
  BEGIN
    pkg_reclutamiento.registrar_postulacion(g_v1_id, g_car, 'ut_user');

    SELECT p.id INTO l_pid
      FROM postulaciones p
     WHERE p.vacante_id   = g_v1_id
       AND p.candidato_id = g_car;

    pkg_reclutamiento.mover_candidato(l_pid, 'PRESELECCION', 'ut_user');
    pkg_reclutamiento.rechazar(l_pid, 'ut_user', 'No cumple requisitos');

    SELECT e.codigo INTO l_etapa_cod
      FROM postulaciones p
      JOIN etapas        e ON e.id = p.etapa_actual_id
     WHERE p.id = l_pid;

    ut3.ut.expect(l_etapa_cod).to_equal('RECHAZADO');
  END test_rechazar;

  -- ----------------------------------------------------------------
  -- TEST 6 — contratar: atomico con cierre de vacante
  --
  -- Dado:  V-UT-02 tiene 2 plazas; David y Elena avanzan hasta OFERTA
  -- Cuando: se contrata a David (1.ª plaza) y luego a Elena (2.ª plaza)
  -- Entonces (1.ª contratacion): plazas_cubiertas = 1, estatus = ABIERTA
  -- Entonces (2.ª contratacion): plazas_cubiertas = 2, estatus = CERRADA
  --                               y existen 2 filas en contrataciones
  -- ----------------------------------------------------------------
  PROCEDURE test_contratar_atomico IS
    l_pid1  NUMBER;
    l_pid2  NUMBER;
    l_cub   NUMBER;
    l_est   VARCHAR2(12);
    l_nhire NUMBER;

    PROCEDURE avanzar_a_oferta(p_pid IN NUMBER) IS
    BEGIN
      pkg_reclutamiento.mover_candidato(p_pid, 'PRESELECCION', 'ut_user');
      pkg_reclutamiento.mover_candidato(p_pid, 'ENTREVISTA',   'ut_user');
      pkg_reclutamiento.mover_candidato(p_pid, 'OFERTA',       'ut_user');
    END avanzar_a_oferta;
  BEGIN
    -- David: 1.a plaza
    pkg_reclutamiento.registrar_postulacion(g_v2_id, g_dav, 'ut_user');
    SELECT p.id INTO l_pid1
      FROM postulaciones p
     WHERE p.vacante_id = g_v2_id AND p.candidato_id = g_dav;

    avanzar_a_oferta(l_pid1);
    pkg_reclutamiento.contratar(l_pid1, 75000, 'ut_user');

    SELECT plazas_cubiertas, estatus INTO l_cub, l_est
      FROM vacantes WHERE id = g_v2_id;

    ut3.ut.expect(l_cub).to_equal(1);
    ut3.ut.expect(l_est).to_equal('ABIERTA');  -- aun no se lleno

    -- Elena: 2.a plaza — debe cerrar la vacante
    pkg_reclutamiento.registrar_postulacion(g_v2_id, g_ele, 'ut_user');
    SELECT p.id INTO l_pid2
      FROM postulaciones p
     WHERE p.vacante_id = g_v2_id AND p.candidato_id = g_ele;

    avanzar_a_oferta(l_pid2);
    pkg_reclutamiento.contratar(l_pid2, 68000, 'ut_user');

    SELECT plazas_cubiertas, estatus INTO l_cub, l_est
      FROM vacantes WHERE id = g_v2_id;
    SELECT COUNT(*) INTO l_nhire
      FROM contrataciones WHERE vacante_id = g_v2_id;

    ut3.ut.expect(l_cub).to_equal(2);           -- 2/2 plazas cubiertas
    ut3.ut.expect(l_est).to_equal('CERRADA');   -- vacante cerrada
    ut3.ut.expect(l_nhire).to_equal(2);         -- 2 registros atomicos
  END test_contratar_atomico;

  -- ----------------------------------------------------------------
  -- TEST 7 — contratar: sin plazas disponibles
  --
  -- Dado:  Bea avanza hasta OFERTA en V-UT-03 (1 plaza)
  --        se fuerza plazas_cubiertas = plazas_total sin cerrar vacante
  --        (simula condicion de carrera entre dos sesiones concurrentes)
  -- Cuando: se intenta contratar
  -- Entonces: se lanza e_sin_plazas (-20105)
  -- ----------------------------------------------------------------
  PROCEDURE test_contratar_sin_plazas IS
    l_raised BOOLEAN := FALSE;
    l_pid    NUMBER;
  BEGIN
    pkg_reclutamiento.registrar_postulacion(g_v3_id, g_bea, 'ut_user');

    SELECT p.id INTO l_pid
      FROM postulaciones p
     WHERE p.vacante_id = g_v3_id AND p.candidato_id = g_bea;

    pkg_reclutamiento.mover_candidato(l_pid, 'PRESELECCION', 'ut_user');
    pkg_reclutamiento.mover_candidato(l_pid, 'ENTREVISTA',   'ut_user');
    pkg_reclutamiento.mover_candidato(l_pid, 'OFERTA',       'ut_user');

    UPDATE vacantes
       SET plazas_cubiertas = plazas_total
     WHERE id = g_v3_id;

    BEGIN
      pkg_reclutamiento.contratar(l_pid, 50000, 'ut_user');
    EXCEPTION
      WHEN pkg_reclutamiento.e_sin_plazas THEN
        l_raised := TRUE;
    END;

    ut3.ut.expect(l_raised).to_be_true();

    UPDATE vacantes SET plazas_cubiertas = 0 WHERE id = g_v3_id;
  END test_contratar_sin_plazas;

  -- ----------------------------------------------------------------
  -- TEST 8 — candidatos_en_etapa: cuenta por etapa
  --
  -- Dado:  Estado de V-UT-01 al llegar a este test:
  --          Ana    → PRESELECCION  (test_mover_valido)
  --          Bea    → POSTULADO     (test_mover_invalido: transicion fallo)
  --          Carlos → RECHAZADO     (test_rechazar)
  -- Entonces: cada etapa reporta exactamente 1 candidato
  -- ----------------------------------------------------------------
  PROCEDURE test_candidatos_en_etapa IS
    l_n_post NUMBER;
    l_n_pres NUMBER;
    l_n_rech NUMBER;
  BEGIN
    l_n_post := pkg_reclutamiento.candidatos_en_etapa(g_v1_id, 'POSTULADO');
    l_n_pres := pkg_reclutamiento.candidatos_en_etapa(g_v1_id, 'PRESELECCION');
    l_n_rech := pkg_reclutamiento.candidatos_en_etapa(g_v1_id, 'RECHAZADO');

    ut3.ut.expect(l_n_post).to_equal(1);   -- Bea
    ut3.ut.expect(l_n_pres).to_equal(1);   -- Ana
    ut3.ut.expect(l_n_rech).to_equal(1);   -- Carlos
  END test_candidatos_en_etapa;

  -- ----------------------------------------------------------------
  -- %afterall — revertir todos los datos generados por la suite
  -- ----------------------------------------------------------------
  PROCEDURE teardown IS
  BEGIN
    ROLLBACK;
  END teardown;

END ut_pkg_reclutamiento;
/

SHOW ERRORS PACKAGE BODY ut_pkg_reclutamiento;

-- =====================================================================
-- Ejecutar la suite
-- =====================================================================
EXEC ut3.ut.run('ut_pkg_reclutamiento');
