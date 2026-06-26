# Contexto del proyecto — para continuar en un nuevo chat

Pega este documento (o súbelo) al inicio del nuevo chat junto con los archivos de la carpeta `sql/`. Te da todo el contexto para seguir sin repetir nada.

---

## 1. Qué estoy construyendo y por qué

Un **motor de pipeline de reclutamiento (ATS) en Oracle PL/SQL**, como pieza de portafolio para postular a vacantes de tecnología con especialidad en bases de datos. El detonante fue una vacante de **Desarrollador PL/SQL en Involve** (empresa de reclutamiento), por eso el dominio es reclutamiento: le habla directo a ese tipo de empresa.

Pero el valor es más amplio: por debajo es una **máquina de estados con transiciones validadas y operaciones multi-paso atómicas**, un patrón que aparece en casi todo software de datos (suscripciones, órdenes, aprobaciones, tickets). Sirve para muchas vacantes del sector, no solo una.

Este es el **Proyecto 1** de un set de 3 pensado para cubrir el 100% de lo que pide ese tipo de vacante:
- **Proyecto 1 (este):** núcleo PL/SQL — procedimientos, transacciones, integridad, triggers.
- **Proyecto 2:** laboratorio de optimización de rendimiento (dataset público grande, EXPLAIN PLAN, índices, BULK COLLECT/FORALL, benchmarks documentados).
- **Proyecto 3:** capa de integración (exponer el paquete vía Oracle REST Data Services + un frontend ligero en React).

## 2. Estado actual (lo que ya está hecho)

Archivos creados y listos:
- `sql/01_esquema.sql` — DDL completo (6 tablas + índices).
- `sql/02_catalogo.sql` — etapas y transiciones permitidas (la máquina de estados).
- `sql/03_paquete_reclutamiento_spec.sql` — **especificación** del paquete `pkg_reclutamiento` (el contrato).

## 3. Lo que sigue (en este orden)

1. **Implementar el BODY** de `pkg_reclutamiento` según la especificación. Subprogramas:
   - `registrar_postulacion` — valida vacante abierta + candidato activo + no duplicado; crea postulación en etapa `POSTULADO`; escribe historial inicial.
   - `mover_candidato` — valida el salto contra `transiciones_permitidas`; si no existe, lanza `e_transicion_invalida`; actualiza `etapa_actual_id`; escribe historial (con usuario y motivo).
   - `rechazar` — reutiliza `mover_candidato` hacia `RECHAZADO`.
   - `contratar` — **atómico** (`SAVEPOINT`/`ROLLBACK`): mueve a `CONTRATADO`, inserta en `contrataciones`, suma 1 a `plazas_cubiertas` y cierra la vacante si se llenó. Rechaza si la vacante no está abierta o no hay plazas.
   - `candidatos_en_etapa` — cuenta candidatos por etapa (reporte).
   - Helpers privados sugeridos: `fn_etapa_id(codigo)`, `fn_etapa_codigo(id)`, `fn_transicion_permitida(origen, destino)`.
2. **Trigger de auditoría** `trg_auditar_postulacion`: `AFTER UPDATE OF etapa_actual_id ON postulaciones`, registra de→a + usuario de BD en una tabla `auditoria_postulaciones`. (Capa técnica automática, distinta del historial de negocio que escribe el paquete.)
3. **Datos de demo y pruebas manuales**: avance válido por el pipeline, una transición inválida que debe bloquearse, y una contratación que cierra la vacante.
4. **Pruebas automatizadas con utPLSQL**.
5. **Migraciones versionadas con Liquibase**.

## 4. Decisiones de diseño ya tomadas

- **IDs**: columnas `GENERATED ALWAYS AS IDENTITY`.
- **Dos capas de trazabilidad**: `historial_postulacion` (negocio, con usuario y motivo, lo escribe el paquete) + `auditoria_postulaciones` (técnico, automático vía trigger).
- **La contratación es la transición a `CONTRATADO`**: pasa por la misma validación de la máquina de estados (requiere etapa previa `OFERTA`).
- **Errores de negocio** con `RAISE_APPLICATION_ERROR` en el rango `-20101..-20106`, ligados a excepciones con nombre vía `PRAGMA EXCEPTION_INIT`.

## 5. Infraestructura

- **Oracle Database 23ai Free** corriendo en Docker en mi laptop. (Plan B si la RAM sufre: Oracle Cloud Always Free / Autonomous Database.)
- Cliente: **SQLcl** o SQL Developer. Control de versiones: Git → GitHub.

## 6. Cómo trabajo (preferencias)

- En **español**, con explicaciones **concretas, directas y con ejemplos**. Si algo no queda claro, lo digo y pido una re-explicación más limpia.
- Suelo dar mi primer instinto y luego pedir la regla o el marco detrás.
- Prefiero resúmenes tipo regla-de-oro sobre teoría larga.
- **Honestidad ante todo**: soy un *builder* que usa herramientas de IA de punta a punta; no inflo credenciales ni tecnologías. Mi experiencia real de base de datos es **PostgreSQL/Supabase**, y estoy haciendo la transición a Oracle. Quiero que seas honesto sobre qué es estándar/idiomático en Oracle para no aprender vicios.

## 7. Prompt de arranque sugerido para el nuevo chat

> Hola. Continúo un proyecto de portafolio en Oracle PL/SQL: un motor de pipeline de reclutamiento (ATS). Te subo el contexto completo (este `CONTEXTO_HANDOFF.md`) y los scripts ya creados: `01_esquema.sql`, `02_catalogo.sql` y `03_paquete_reclutamiento_spec.sql`. Quiero que me ayudes a implementar el **cuerpo (BODY)** del paquete `pkg_reclutamiento` según la especificación, paso a paso y en español, con explicaciones concretas. Soy builder en transición de PostgreSQL/Supabase a Oracle, así que sé honesto sobre lo idiomático en Oracle. Empecemos por el BODY del paquete.
