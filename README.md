# plsql-reclutamiento

Motor de pipeline de selección de personal implementado íntegramente en Oracle PL/SQL — máquina de estados, transacciones atómicas y trazabilidad completa de cada movimiento.

---

## Qué demuestra técnicamente

- **Máquina de estados con grafo de transiciones** — las etapas y los saltos válidos viven en tablas; agregar o quitar una transición es un `INSERT`/`DELETE`, no un cambio de código.
- **Transacciones atómicas con `SAVEPOINT`** — `contratar` mueve el candidato, registra la contratación e incrementa plazas en un único bloque atómico; cualquier fallo revierte solo esa operación sin afectar la sesión.
- **Excepciones de negocio con nombre** — seis excepciones tipadas (`e_vacante_invalida`, `e_transicion_invalida`, etc.) capturables por nombre desde el cliente, nunca por número de error.
- **Dos capas de auditoría complementarias** — `historial_postulacion` (escrita explícitamente por el paquete, captura el usuario de aplicación) y `auditoria_postulaciones` (escrita por trigger, captura el usuario de BD aunque se bypasee el paquete).
- **Suite de pruebas utPLSQL** — ocho tests formales con anotaciones `%suite`/`%test`/`%beforeall`/`%afterall` y aserciones `ut3.ut.expect()`.
- **Versionado con Liquibase** — changelog XML que registra los siete scripts como changesets; workflow `changelogSync` para marcar migraciones ya aplicadas.

---

## Estructura del repositorio

```
plsql-reclutamiento/
├── sql/
│   ├── 01_esquema.sql                      DDL: tablas, índices, constraints
│   ├── 02_catalogo.sql                     Etapas del pipeline y transiciones permitidas
│   ├── 03_paquete_reclutamiento_spec.sql   Especificación pública del paquete (contrato)
│   ├── 04_paquete_reclutamiento_body.sql   Implementación del paquete
│   ├── 05_pruebas.sql                      Suite de pruebas manual (SQL*Plus)
│   ├── 06_trigger_auditoria.sql            Tabla de auditoría técnica + trigger
│   └── 07_utplsql_tests.sql               Suite formal utPLSQL (8 tests)
├── changelog-master.xml                    Changelog Liquibase (referencia los 7 scripts)
├── liquibase.properties.example            Plantilla de conexión Liquibase
├── liquibase.properties                    Credenciales locales (en .gitignore)
├── login.sql                               SET DEFINE OFF para SQL*Plus/SQLcl
└── .gitignore
```

---

## Reproducir desde cero

### Requisitos previos

| Herramienta | Versión probada | Notas |
|---|---|---|
| Docker Desktop | ≥ 4.x | Para el contenedor Oracle |
| Oracle 23ai Free | 23.x | Imagen oficial `container-registry.oracle.com/database/free:latest` |
| SQLcl o SQL*Plus | cualquiera | Para ejecutar los scripts |
| utPLSQL | v3.1.14 | Ver instrucciones de instalación más abajo |
| Liquibase Community | ≥ 4.x | Solo si se usa el changelog |

### 1. Levantar el contenedor

```bash
docker run -d --name oracle23ai \
  -p 1521:1521 \
  -e ORACLE_PWD=Oracle23ai \
  container-registry.oracle.com/database/free:latest
```

Esperar hasta que `docker logs oracle23ai | tail -5` muestre `DATABASE IS READY TO USE`.

### 2. Ejecutar los scripts en orden

Conectar como `system/Oracle23ai` en la PDB `FREEPDB1` y correr en orden:

```sql
@sql/01_esquema.sql
@sql/02_catalogo.sql
@sql/03_paquete_reclutamiento_spec.sql
@sql/04_paquete_reclutamiento_body.sql
@sql/06_trigger_auditoria.sql
```

El script `05_pruebas.sql` es opcional y termina con `ROLLBACK` — no deja datos permanentes:

```sql
@sql/05_pruebas.sql
```

### 3. Instalar utPLSQL y ejecutar la suite formal

```powershell
# Descargar e instalar utPLSQL en el contenedor
$ver = "3.1.14"
Invoke-WebRequest "https://github.com/utPLSQL/utPLSQL/releases/download/v$ver/utPLSQL.zip" `
  -OutFile "$env:TEMP\utPLSQL.zip"
Expand-Archive "$env:TEMP\utPLSQL.zip" -DestinationPath "$env:TEMP\utPLSQL_install" -Force
docker cp "$env:TEMP\utPLSQL_install\utPLSQL" oracle23ai:/tmp/utplsql

docker exec oracle23ai bash -c @'
cd /tmp/utplsql/source && \
sqlplus "sys/Oracle23ai@//localhost:1521/FREEPDB1 as sysdba" \
  @install_headless.sql ut3 ut3 users
'@

# Dar acceso al usuario de la sesión
docker exec oracle23ai bash -c @'
sqlplus -s "sys/Oracle23ai@//localhost:1521/FREEPDB1 as sysdba" << 'SQL'
GRANT ut_user_role TO system;
SQL
'@
```

Ejecutar la suite:

```sql
@sql/07_utplsql_tests.sql
```

Los 8 tests deben terminar en verde. El paquete `ut_pkg_reclutamiento` se limpia solo con el `ROLLBACK` del `%afterall`.

### 4. Configurar Liquibase (opcional)

```powershell
# Copiar driver JDBC desde el contenedor
docker cp oracle23ai:/opt/oracle/product/23ai/dbhomeFree/jdbc/lib/ojdbc11.jar `
  C:\liquibase\lib\ojdbc11.jar

# Configurar credenciales
Copy-Item liquibase.properties.example liquibase.properties
# editar liquibase.properties y poner la contraseña

# Registrar los 7 scripts como ya aplicados (no los re-ejecuta)
liquibase changelogSync

# Verificar
liquibase history
```

---

## Tecnologías

| | |
|---|---|
| **Oracle Database 23ai Free** | Motor de base de datos. Se usa la sintaxis `IF NOT EXISTS` (23ai), identidades y PL/SQL estándar. |
| **Docker** | El contenedor oficial elimina cualquier instalación local de Oracle. |
| **SQLcl / SQL*Plus** | Ejecución de scripts. `login.sql` en la raíz configura `SET DEFINE OFF` automáticamente al conectar. |
| **utPLSQL v3** | Framework de unit testing para PL/SQL. Anotaciones en comentarios, aserciones fluidas, integración con CI. |
| **Liquibase Community** | Versionado de migraciones. El driver JDBC de Oracle no viene incluido — se obtiene del propio contenedor. |

---

## El patrón detrás del proyecto

La piel es reclutamiento pero el motor es genérico: **cualquier entidad que deba avanzar por etapas con reglas de transición** puede reutilizar este esquema sin cambiar una línea del paquete.

Casos de uso directos: aprobación de gastos, ciclo de vida de tickets de soporte, estados de un pedido e-commerce, onboarding de empleados, flujo de contratos. El grafo de transiciones vive en `transiciones_permitidas` — cambiar el flujo es cambiar datos, no código.
