## Phoenixd Docker (custom hardened build)

Imagen auto-construida de `phoenixd` (v0.6.2) desde código fuente con enfoque en:
1. Reproducibilidad (pin tag mediante `ARG PHOENIXD_BRANCH`).
2. Endurecimiento (usuario no root, FS de solo lectura, eliminación de capacidades, `no-new-privileges`).
3. Inicialización no interactiva (se auto-confirman los avisos en primer arranque).
4. Persistencia explícita (volumen nombrado) y sin secret externo para la seed por defecto.

Estado actual alineado con el `Dockerfile` y `docker-compose.yml` de este repositorio, NO con la carpeta `.docker` oficial de ACINQ. Abajo se detalla cada diferencia y su razón.

---
## Diferencias clave respecto a `ACINQ/phoenixd` (`v0.6.2` / `.docker` oficial)

| Área | Upstream típico | Esta variante | Motivo del cambio |
|------|-----------------|---------------|-------------------|
| Origen binarios | Pre‑compilados (o build script simple) | Build desde fuente (`gradlew link...`) | Control de versión exacta y posibilidad de reproducir parches/hardening. |
| Pin de versión | A menudo `latest` / imagen publicada | `ARG PHOENIXD_BRANCH=v0.6.2` | Evitar drift silencioso. |
| Usuario | Puede ejecutar como root en algunos ejemplos | Usuario sistema `phoenix` UID/GID 1000 | Principio de mínimo privilegio. |
| Directorio de datos | `$HOME/.phoenix` variable (ej. `/home/phoenix/.phoenix`) | `/phoenix/.phoenix` | Home explícito (`/phoenix`) simplifica paths y COPY chown. |
| Seed vía secret | Usada (ej. `--seed-path` con `secrets:`) | Eliminada por defecto (autogenerada) | Reducir fallos de arranque y riesgo de reuso accidental de semilla. |
| Flags de inicio | Mínimos / por defecto | `--http-bind-ip=0.0.0.0`, `--auto-liquidity=10m` | Acceso inter‑contenedor y monto de auto‑liquidez explícito. |
| Confirmaciones interactivas | Requiere input manual primera vez | Entrada automática de "I understand" en entrypoint | Permite orquestación no interactiva (CI / infra). |
| Persistencia | A veces bind host ad‑hoc | Volumen nombrado `phoenixd_datadir` | Evitar permisos inconsistentes (WSL/NTFS) y commits accidentales. |
| Hardening | Básico / ninguno | `cap_drop: ALL`, `read_only: true`, `no-new-privileges`, `tmpfs /tmp` | Reducir superficie de ataque en runtime. |
| Exposición HTTP | Puede mapear puerto públicamente | Solo `expose:` interno | Evitar exposición involuntaria; se añade puerto manual si se necesita. |
| Dependencias runtime | Puede incluir libs extra | Solo `bash` y `ca-certificates` | Binarios Kotlin/Native estáticos; reducir tamaño/ataque. |

---
## Arquitectura del build

Multi-stage:
1. Stage `build`: Imagen base `eclipse-temurin:21-jdk-jammy`, clona repo en tag (`PHOENIXD_BRANCH`), ejecuta Gradle para generar ejecutables nativos `phoenixd` y `phoenix-cli` según `TARGETPLATFORM`.
2. Stage `final`: `debian:bookworm-slim`, instala mínimos (`bash` `ca-certificates`), crea usuario, copia binarios, crea directorio de datos y entrypoint.

El entrypoint detecta primera ejecución (ausencia de `seed.dat`) y suministra automáticamente las dos confirmaciones requeridas, luego arranca el daemon con los flags provenientes de `docker-compose.yml`.

---
## docker-compose (estado actual)

Características destacadas:
* Build local desde fuente (asegura versión esperada).
* Volumen nombrado `phoenixd_datadir` en `/phoenix/.phoenix`.
* Red externa `backend` para descubrimiento DNS de otros servicios.
* API HTTP ligada a `0.0.0.0:9740` pero no publicada (solo `expose:`); otros contenedores acceden vía `http://phoenixd:9740`.
* Hardening: sin capacidades, FS de solo lectura, `tmpfs` efímero para `/tmp` (noexec, nosuid, nodev), no escalado de privilegios.
* Auto-liquidez configurada a `10m` sats.

---
## Datos y estructura en `/phoenix/.phoenix`

| Archivo | Descripción |
|---------|-------------|
| `seed.dat` | Seed (12 palabras) – Respaldar offline inmediatamente. |
| `phoenix.conf` | Config con contraseñas HTTP generadas. |
| `phoenix.log` | Log principal del daemon. |
| `phoenix.mainnet.*` | Base de datos sqlite (estado de canales / pagos). |

Si pierdes `seed.dat` pierdes acceso a los fondos: prioriza backup seguro.

---
## Flujo de uso rápido

```bash
docker compose build
docker compose up -d
docker logs -f phoenixd  # ver confirmación de arranque y nodeid

# Obtener contraseñas HTTP
docker exec phoenixd grep http-password /phoenix/.phoenix/phoenix.conf

# Info general
docker exec phoenixd /phoenix/phoenix-cli getinfo
```

Para acceder desde otro contenedor en la misma red:
```bash
curl -s -o /dev/null -w '%{http_code}\n' http://phoenixd:9740/  # devolverá 404 si vivo
```

Publicar externamente (solo si entiendes los riesgos):
```yaml
  ports:
    - "9740:9740"
```
Recomendado: usar un reverse proxy TLS y limitar IPs.

---
## Ajustes frecuentes

| Objetivo | Acción |
|----------|--------|
| Cambiar versión | Editar `PHOENIXD_BRANCH` en compose, rebuild `--no-cache`. |
| Forzar testnet | Añadir a `command`: `--chain=testnet`. |
| Cambiar auto-liquidez | Ajustar flag `--auto-liquidity=<m|2m|5m|10m|off>`. |
| Importar seed existente | (Ocasional) añadir `--seed-path=/phoenix/.phoenix/seed.dat` tras copiar el archivo ANTES del primer arranque. |
| Reemplazar seed (no recomendado) | Detener, borrar volumen, montar nuevo, reiniciar (generará seed nueva). |
| Exponer HTTP solo a proxy | Mantener sin `ports:` y crear contenedor proxy en red `backend`. |

---
## Seguridad

Buenas prácticas mínimas:
1. Backup inmediato (seed + snapshot directorio) y almacenarlo cifrado.
2. No compartir logs completos (pueden contener metadatos de canales). 
3. Mantener la imagen reconstruida periódicamente para incorporar parches aguas arriba.
4. Revisar que el volumen no se suba a control de versiones (agregar a `.gitignore`).
5. Añadir firewall / ACL si publicas el puerto.

Posibles mejoras futuras (no implementadas aún):
* Verificación de integridad (pin de commit + checksum de tarball).
* Healthcheck activo (actualmente se puede añadir manualmente si se desea).
* Rotación automática de contraseñas (script externo / job). 

---
## Razonamiento de cambios frente a upstream

Resumidamente: la versión oficial prioriza simplicidad general; esta variante prioriza reproducibilidad y hardening para despliegues controlados. Algunos flags que fallaban al principio (por versión anterior en cache) llevaron a limpiar argumentos y hacer el build directo desde fuente para asegurar correspondencia entre código y opciones esperadas. Eliminar el secret de seed reduce puntos de error y evita reuso accidental; si la comunidad prefiere semilla gestionada externamente se puede reintroducir documentando muy claramente la unicidad de la seed.

---
## Actualizar a nueva versión
```bash
sed -i 's/PHOENIXD_BRANCH: v0.6.2/PHOENIXD_BRANCH: v0.X.Y/' docker-compose.yml
docker compose build --no-cache
docker compose up -d
docker exec phoenixd /phoenix/phoenix-cli --version || docker logs phoenixd | grep -i version
```

---
## Troubleshooting breve

| Síntoma | Causa probable | Acción |
|---------|----------------|--------|
| Loop con Usage | Flag no soportado / versión errónea | Rebuild con tag correcto; revisar `docker image ls`. |
| 404 en raíz | Respuesta normal (endpoint no existe) | Usar endpoints documentados (`/v1/...`). |
| Conexión rechazada desde otro contenedor | Bind en 127.0.0.1 | Añadir `--http-bind-ip=0.0.0.0`. |
| Falta `seed.dat` tras reinicio | Volumen recreado | Restaurar backup; sin seed fondos perdidos. |
| Permisos raros en host (WSL/NTFS) | Montaje sobre FS no POSIX | Usar volumen nombrado (ya adoptado). |

---
## Aviso
El uso de esta imagen implica responsabilidad completa sobre la custodia. Comprueba siempre tus backups antes de usar con fondos reales.

---
## Licencia
Respeta la licencia original de Phoenix. Este repositorio sólo aporta empaquetado y hardening.

---
## Resumen inmediato
```bash
docker compose up -d
docker exec phoenixd grep http-password /phoenix/.phoenix/phoenix.conf
docker exec phoenixd /phoenix/phoenix-cli getinfo
```

Listo. Ajusta seguridad y monitoreo antes de producción.
