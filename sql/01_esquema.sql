-- =====================================================================
-- Proyecto 1 (pivote): Motor de pipeline de reclutamiento (ATS) en PL/SQL
-- Archivo 01: Esquema de datos (DDL)
-- Motor objetivo: Oracle Database 23ai Free
-- =====================================================================
-- Dominio: candidatos que avanzan por etapas de un proceso de selección,
-- con reglas de transición (máquina de estados), contratación atómica y
-- trazabilidad completa. Patrón reutilizable para cualquier flujo de
-- estados (suscripciones, órdenes, aprobaciones, tickets...).
-- ---------------------------------------------------------------------
-- Para recrear desde cero (orden inverso por las FK):
-- DROP TABLE contrataciones        CASCADE CONSTRAINTS;
-- DROP TABLE historial_postulacion CASCADE CONSTRAINTS;
-- DROP TABLE postulaciones         CASCADE CONSTRAINTS;
-- DROP TABLE transiciones_permitidas CASCADE CONSTRAINTS;
-- DROP TABLE etapas                CASCADE CONSTRAINTS;
-- DROP TABLE candidatos            CASCADE CONSTRAINTS;
-- DROP TABLE vacantes              CASCADE CONSTRAINTS;

-- ---------------------------------------------------------------------
-- Etapas del pipeline (los "estados" de la máquina)
-- ---------------------------------------------------------------------
CREATE TABLE etapas (
  id        NUMBER       GENERATED ALWAYS AS IDENTITY,
  codigo    VARCHAR2(20) NOT NULL,
  nombre    VARCHAR2(80) NOT NULL,
  orden     NUMBER       NOT NULL,
  es_final  CHAR(1)      DEFAULT 'N' NOT NULL,
  activo    CHAR(1)      DEFAULT 'S' NOT NULL,
  CONSTRAINT pk_etapas        PRIMARY KEY (id),
  CONSTRAINT uq_etapas_codigo UNIQUE (codigo),
  CONSTRAINT ck_etapas_final  CHECK (es_final IN ('S','N')),
  CONSTRAINT ck_etapas_activo CHECK (activo   IN ('S','N'))
);

-- ---------------------------------------------------------------------
-- Transiciones permitidas (las "aristas" de la máquina de estados)
-- Define qué saltos de etapa son válidos. El corazón de la integridad.
-- ---------------------------------------------------------------------
CREATE TABLE transiciones_permitidas (
  etapa_origen_id  NUMBER NOT NULL,
  etapa_destino_id NUMBER NOT NULL,
  CONSTRAINT pk_transiciones    PRIMARY KEY (etapa_origen_id, etapa_destino_id),
  CONSTRAINT fk_trans_origen    FOREIGN KEY (etapa_origen_id)  REFERENCES etapas(id),
  CONSTRAINT fk_trans_destino   FOREIGN KEY (etapa_destino_id) REFERENCES etapas(id),
  CONSTRAINT ck_trans_distintas CHECK (etapa_origen_id <> etapa_destino_id)
);

-- ---------------------------------------------------------------------
-- Vacantes (las posiciones a cubrir)
-- ---------------------------------------------------------------------
CREATE TABLE vacantes (
  id               NUMBER        GENERATED ALWAYS AS IDENTITY,
  codigo           VARCHAR2(20)  NOT NULL,
  titulo           VARCHAR2(200) NOT NULL,
  cliente          VARCHAR2(150),
  plazas_total     NUMBER        DEFAULT 1 NOT NULL,
  plazas_cubiertas NUMBER        DEFAULT 0 NOT NULL,
  estatus          VARCHAR2(12)  DEFAULT 'ABIERTA' NOT NULL,
  fecha_apertura   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  fecha_cierre     TIMESTAMP,
  CONSTRAINT pk_vacantes        PRIMARY KEY (id),
  CONSTRAINT uq_vacantes_codigo UNIQUE (codigo),
  CONSTRAINT ck_vac_estatus     CHECK (estatus IN ('ABIERTA','CERRADA','CANCELADA')),
  CONSTRAINT ck_vac_plazas_tot  CHECK (plazas_total >= 1),
  -- REGLA DE ORO: las plazas cubiertas nunca exceden el total (ni bajan de 0)
  CONSTRAINT ck_vac_plazas_cub  CHECK (plazas_cubiertas >= 0 AND plazas_cubiertas <= plazas_total)
);

-- ---------------------------------------------------------------------
-- Candidatos
-- ---------------------------------------------------------------------
CREATE TABLE candidatos (
  id         NUMBER        GENERATED ALWAYS AS IDENTITY,
  nombre     VARCHAR2(200) NOT NULL,
  email      VARCHAR2(150) NOT NULL,
  telefono   VARCHAR2(30),
  activo     CHAR(1)       DEFAULT 'S' NOT NULL,
  fecha_alta TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_candidatos        PRIMARY KEY (id),
  CONSTRAINT uq_candidatos_email  UNIQUE (email),
  CONSTRAINT ck_candidatos_activo CHECK (activo IN ('S','N'))
);

-- ---------------------------------------------------------------------
-- Postulaciones: candidato + vacante + etapa actual (el ESTADO ACTUAL)
-- Un candidato sólo puede postularse una vez a la misma vacante.
-- ---------------------------------------------------------------------
CREATE TABLE postulaciones (
  id                NUMBER     GENERATED ALWAYS AS IDENTITY,
  vacante_id        NUMBER     NOT NULL,
  candidato_id      NUMBER     NOT NULL,
  etapa_actual_id   NUMBER     NOT NULL,
  activo            CHAR(1)    DEFAULT 'S' NOT NULL,
  fecha_postulacion TIMESTAMP  DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_postulaciones  PRIMARY KEY (id),
  CONSTRAINT uq_post_vac_cand  UNIQUE (vacante_id, candidato_id),
  CONSTRAINT fk_post_vacante   FOREIGN KEY (vacante_id)      REFERENCES vacantes(id),
  CONSTRAINT fk_post_candidato FOREIGN KEY (candidato_id)    REFERENCES candidatos(id),
  CONSTRAINT fk_post_etapa     FOREIGN KEY (etapa_actual_id) REFERENCES etapas(id),
  CONSTRAINT ck_post_activo    CHECK (activo IN ('S','N'))
);

CREATE INDEX ix_post_vacante ON postulaciones(vacante_id);
CREATE INDEX ix_post_etapa   ON postulaciones(etapa_actual_id);

-- ---------------------------------------------------------------------
-- Historial de la postulación: bitácora de negocio (quién, cuándo, por qué)
-- La escribe el paquete explícitamente para capturar usuario y motivo.
-- ---------------------------------------------------------------------
CREATE TABLE historial_postulacion (
  id                NUMBER       GENERATED ALWAYS AS IDENTITY,
  postulacion_id    NUMBER       NOT NULL,
  etapa_anterior_id NUMBER,
  etapa_nueva_id    NUMBER       NOT NULL,
  usuario           VARCHAR2(60) NOT NULL,
  motivo            VARCHAR2(300),
  fecha             TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_hist_post      PRIMARY KEY (id),
  CONSTRAINT fk_hist_post      FOREIGN KEY (postulacion_id)    REFERENCES postulaciones(id),
  CONSTRAINT fk_hist_etapa_ant FOREIGN KEY (etapa_anterior_id) REFERENCES etapas(id),
  CONSTRAINT fk_hist_etapa_new FOREIGN KEY (etapa_nueva_id)    REFERENCES etapas(id)
);

CREATE INDEX ix_hist_postulacion ON historial_postulacion(postulacion_id);

-- ---------------------------------------------------------------------
-- Contrataciones (resultado de una contratación atómica)
-- ---------------------------------------------------------------------
CREATE TABLE contrataciones (
  id                 NUMBER       GENERATED ALWAYS AS IDENTITY,
  postulacion_id     NUMBER       NOT NULL,
  vacante_id         NUMBER       NOT NULL,
  candidato_id       NUMBER       NOT NULL,
  honorarios         NUMBER(12,2) DEFAULT 0 NOT NULL,
  usuario            VARCHAR2(60) NOT NULL,
  fecha_contratacion TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_contrataciones    PRIMARY KEY (id),
  CONSTRAINT uq_contra_postulacion UNIQUE (postulacion_id),
  CONSTRAINT fk_contra_post       FOREIGN KEY (postulacion_id) REFERENCES postulaciones(id),
  CONSTRAINT fk_contra_vac        FOREIGN KEY (vacante_id)     REFERENCES vacantes(id),
  CONSTRAINT fk_contra_cand       FOREIGN KEY (candidato_id)   REFERENCES candidatos(id),
  CONSTRAINT ck_contra_honorarios CHECK (honorarios >= 0)
);
