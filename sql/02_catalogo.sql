-- =====================================================================
-- Proyecto 1 (pivote): Motor de pipeline de reclutamiento (ATS)
-- Archivo 02: Catálogo / datos de referencia (define la máquina de estados)
-- =====================================================================
-- Ejecutar DESPUÉS de 01_esquema.sql y ANTES de cargar el paquete.
-- Estas son las "reglas del juego": las etapas y los saltos válidos.
-- =====================================================================

-- ----- Etapas del pipeline ------------------------------------------
INSERT INTO etapas(codigo, nombre, orden, es_final) VALUES ('POSTULADO',    'Postulado',    1, 'N');
INSERT INTO etapas(codigo, nombre, orden, es_final) VALUES ('PRESELECCION', 'Preselección', 2, 'N');
INSERT INTO etapas(codigo, nombre, orden, es_final) VALUES ('ENTREVISTA',   'Entrevista',   3, 'N');
INSERT INTO etapas(codigo, nombre, orden, es_final) VALUES ('OFERTA',       'Oferta',       4, 'N');
INSERT INTO etapas(codigo, nombre, orden, es_final) VALUES ('CONTRATADO',   'Contratado',   5, 'S');
INSERT INTO etapas(codigo, nombre, orden, es_final) VALUES ('RECHAZADO',    'Rechazado',    9, 'S');

-- ----- Transiciones permitidas (la máquina de estados) ---------------
-- Sólo se puede avanzar por estos saltos; cualquier otro será rechazado.
-- Desde CONTRATADO y RECHAZADO no sale ninguna arista: son terminales.
INSERT INTO transiciones_permitidas(etapa_origen_id, etapa_destino_id)
SELECT o.id, d.id
  FROM etapas o, etapas d
 WHERE (o.codigo, d.codigo) IN (
        ('POSTULADO',    'PRESELECCION'),
        ('POSTULADO',    'RECHAZADO'),
        ('PRESELECCION', 'ENTREVISTA'),
        ('PRESELECCION', 'RECHAZADO'),
        ('ENTREVISTA',   'OFERTA'),
        ('ENTREVISTA',   'RECHAZADO'),
        ('OFERTA',       'CONTRATADO'),
        ('OFERTA',       'RECHAZADO')
       );

COMMIT;

-- Verificación rápida del grafo de estados
PROMPT === Transiciones cargadas ===
SELECT o.codigo AS de, d.codigo AS a
  FROM transiciones_permitidas t
  JOIN etapas o ON o.id = t.etapa_origen_id
  JOIN etapas d ON d.id = t.etapa_destino_id
 ORDER BY o.orden, d.orden;
