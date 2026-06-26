# Motor de pipeline de reclutamiento (ATS) — Oracle PL/SQL

Motor de datos para un proceso de selección: candidatos que se postulan a vacantes y avanzan por etapas (Postulado → Preselección → Entrevista → Oferta → Contratado), con **reglas de transición que impiden saltos inválidos**, **contratación atómica** y **trazabilidad completa** de cada cambio.

Toda la lógica vive dentro de la base de datos. Construido sobre **Oracle Database 23ai Free** con PL/SQL.

> El patrón es reutilizable: una máquina de estados con transiciones validadas y operaciones multi-paso atómicas describe también suscripciones, órdenes, aprobaciones o tickets. La piel es reclutamiento; el motor sirve para casi cualquier flujo de estados en software.

## Qué demuestra

- **Máquina de estados en PL/SQL** — transiciones validadas contra una tabla de reglas
- **Gestión de transacciones** — contratación atómica con `SAVEPOINT` / `ROLLBACK`
- **Integridad de datos** — constraints, FKs, y la regla "plazas cubiertas ≤ total"
- **Manejo de excepciones** — errores de negocio con nombre
- **Triggers** — auditoría técnica automática de cada cambio de etapa
- **Modelado de datos** — esquema normalizado (vacantes, candidatos, postulaciones, etapas, historial, contrataciones)

## Estructura

```
sql/
├── 01_esquema.sql                      Tablas, constraints, índices (DDL)
├── 02_catalogo.sql                     Etapas + transiciones (la máquina de estados)
└── 03_paquete_reclutamiento_spec.sql   Especificación del paquete (contrato a implementar)
```

## Orden de ejecución (lo construido hasta ahora)

```sql
@sql/01_esquema.sql
@sql/02_catalogo.sql
@sql/03_paquete_reclutamiento_spec.sql
```

## Pendiente (continúa en el siguiente chat)

1. **Cuerpo (BODY)** del paquete `pkg_reclutamiento` según la especificación
2. **Trigger de auditoría** sobre cambios de etapa
3. **Datos de demostración** y casos de prueba (transición válida, transición inválida bloqueada, contratación que cierra la vacante)
4. **Pruebas automatizadas** con utPLSQL
5. **Migraciones versionadas** con Liquibase

Ver `CONTEXTO_HANDOFF.md` para el contexto completo y el prompt de arranque del nuevo chat.
