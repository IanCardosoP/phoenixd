# Phoenixd Docker

Contenedor listo para ejecutar `phoenixd` (daemon de Phoenix Server) junto con la utilidad `phoenix-cli`.

## 🧱 Características
- Multi-stage build (descarga -> runtime minimal Debian slim)
- Ejecuta como usuario no root (`phoenix` UID/GID configurables)
- Persistencia de datos fuera de la imagen: ahora se monta `./data` directamente como `/home/phoenix/.phoenix`
- Incluye binarios: `phoenixd` y `phoenix-cli`
- Dependencias runtime añadidas: `libsqlite3-0`, `libcurl4`, `ca-certificates`

## 📂 Estructura interna de datos
Al primer arranque se genera el siguiente contenido en `/home/phoenix/.phoenix` (home del usuario):

| Archivo | Descripción |
|---------|-------------|
| `seed.dat` | Semilla BIP39 (12 palabras) en formato cifrado/propietario. Debe respaldarse de forma segura. |
| `phoenix.conf` | Configuración generada. Contiene credenciales HTTP (`http-password`, `http-password-limited-access`). |
| `phoenix.log` | Log del daemon. |
| `phoenix.mainnet.*` | Base de datos sqlite (con WAL y SHM) con el estado de canales y pagos. |

Nota: El directorio de estado del daemon es `/home/phoenix/.phoenix` y se vincula directamente a `./data` en el host para persistencia real.

## 🔐 Autenticación y contraseñas
Phoenixd expone una API HTTP en `127.0.0.1:9740` (por defecto). Las contraseñas se leen de `phoenix.conf`:

```
http-password=<token_full_access>
http-password-limited-access=<token_limited>
```

No se crea `auth.dat`; los tokens están directamente en `phoenix.conf`.

### Acceso completo vs limitado
- `http-password`: operaciones completas (crear invoices, consultar pagos, etc.)
- `http-password-limited-access`: acceso restringido (normalmente lectura / endpoints limitados). Ver documentación oficial de Phoenix para matices.

## 🚀 Construir

```pwsh
docker compose build
```
O manual:
```pwsh
docker build -t phoenixd:latest .
```

Variables de build opcionales (ARG):
- `UID` / `GID` (por defecto 1000) para alinear ownership con tu host.

## ▶️ Ejecutar (desarrollo)

```pwsh
docker compose up -d
```
Logs:
```pwsh
docker logs -f phoenixd
```

Primer arranque: verás prompts informativos (backup seed, liquidity). Tras ese inicio, el daemon continúa y escucha en `127.0.0.1:9740`.

## 🌐 Exponer API fuera del host
Modificar en `docker-compose.yml`:
```yaml
    ports:
      - "9740:9740"
```
Esto ya existe, pero la app liga a `127.0.0.1` dentro del contenedor. Para aceptar conexiones externas, deberás usar `--http-bind-ip=0.0.0.0` (ver sección CLI) o variable/env según soporte futuro. Puedes crear un override:

```pwsh
docker exec phoenixd bash -lc 'phoenixd --http-bind-ip=0.0.0.0'
```

Mejor práctica: colocar un reverse proxy (Nginx / Caddy) con TLS delante y dejar phoenixd escuchando sólo en loopback.

## 🧪 Uso de phoenix-cli
Ejemplos dentro del contenedor:
```pwsh
docker exec -it phoenixd bash -lc 'phoenix-cli getinfo'
```
Crear invoice (1,000 sats):
```pwsh
docker exec -it phoenixd bash -lc 'phoenix-cli createinvoice --amountSat=1000 --description="Pago test"'
```

Pasar parámetros de red o bind:
```pwsh
docker exec -it phoenixd bash -lc 'phoenixd --http-bind-ip=0.0.0.0'
```

## 📡 API REST (desde host)
Primero extrae el token:
```pwsh
docker exec phoenixd bash -lc 'grep http-password /home/phoenix/.phoenix/phoenix.conf'
```
Crear invoice:
```pwsh
curl -X POST http://localhost:9740/v1/invoices ^
  -H "Authorization: Bearer <token_full_access>" ^
  -H "Content-Type: application/json" ^
  -d '{"amount":1000,"description":"Pago"}'
```
Consultar invoice:
```pwsh
curl http://localhost:9740/v1/invoices/<paymentHash> -H "Authorization: Bearer <token_full_access>"
```

## 💾 Persistencia
La aplicación guarda todo en `/home/phoenix/.phoenix`. El `docker-compose.yml` ya monta:
```yaml
    volumes:
      - ./data:/home/phoenix/.phoenix
```
Si `./data` no existe, créalo antes o Docker lo generará.
Verifica contenido tras primer arranque:
```pwsh
docker exec phoenixd bash -lc 'ls -1 /home/phoenix/.phoenix'
```
Debe reflejarse en tu host en `./data`.

### Persistencia real (qué significa)
"Persistencia real" = los archivos críticos se almacenan fuera del FS efímero del contenedor. Si reconstruyes o eliminas el contenedor, los datos siguen en tu host.

### Qué se persiste con `./data:/home/phoenix/.phoenix`
- `seed.dat` (semilla BIP39) – CRÍTICO
- `phoenix.mainnet.*` (estado de canales/pagos)
- `phoenix.conf` (tokens API)
- `phoenix.log` (auditoría / debugging)

### Qué pasa si NO montas esa ruta
- Se genera una nueva semilla ⇒ pérdida de acceso a fondos previos.
- Tokens HTTP cambian.
- Historial de pagos y canales se pierde.

### Cómo montar correctamente (resumen)
```pwsh
New-Item -ItemType Directory data  # si no existe
docker compose up -d
```
Verifica luego que `./data` contiene `seed.dat`, `phoenix.conf`, etc.

### Migración desde un contenedor previo (antiguo montaje phoenix-home)
```pwsh
docker compose down
mkdir data
Copy-Item phoenix-home\* data -Recurse -Force  # PowerShell
# o en Linux:
# cp -a phoenix-home/* data/
docker compose up -d
```

### Riesgos y recomendaciones
| Riesgo | Mitigación |
|--------|------------|
| Pérdida de seed.dat | Backup offline cifrado y prueba de restauración. |
| Commit accidental de semilla | `.gitignore` incluye `data/`; nunca usar `git add -f`. |
| Exposición de tokens | Restringir permisos del directorio; usar proxy seguro. |
| Exposición directa puerto 9740 | Reverse proxy + TLS + firewall. |
| Corrupción DB (crash/power loss) | Backups periódicos del directorio; snapshots antes de updates. |
| Logs con datos sensibles | Rutina de rotación/limpieza y no compartir logs completos públicamente. |

### Backups sugeridos
Evento mínimo: tras recibir fondos significativos o abrir canal.
Contenido: `seed.dat` + snapshot completo `.phoenix`.
Almacenamiento: cifrado, redundante, geográficamente separado.
Pruebas: Restauración en entorno aislado para validar integridad.

## ♻️ Restart policy
Añadir si deseas resiliencia:
```yaml
    restart: unless-stopped
```
Ya se añadió en el `docker-compose.yml` actual.

## 🩺 Healthcheck opcional
Puedes agregar (requiere `curl` en runtime si lo instalas):
```yaml
    healthcheck:
      test: ["CMD", "bash", "-lc", "exec 3<>/dev/tcp/127.0.0.1/9740 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
```
El `docker-compose.yml` ya incluye un healthcheck TCP sin `curl`.

## 🔐 Seguridad y buenas prácticas
- Respaldar `seed.dat` inmediatamente (almacenar offline / cifrado)
- Rotar tokens (editar `phoenix.conf` y reiniciar)  `docker exec phoenixd rotate-phoenix-http-passwords && docker restart phoenixd` 
- No exponer directo el puerto 9740 a Internet sin proxy/TLS
- Usar firewall para limitar IPs confiables
- Mantener la imagen actualizada (rebuild periódico)

## 🧽 Actualizar versión de phoenixd
1. Cambiar la URL y la versión en el Dockerfile (dos lugares: nombre del zip y carpeta) 
2. `docker compose build --no-cache && docker compose up -d`
3. Verificar con: `docker exec phoenixd phoenix-cli --version` (si soporta `--version`) o revisar logs.

## 🛠 Troubleshooting
| Problema | Causa común | Solución |
|----------|-------------|----------|
| `libcurl.so.4 not found` | Faltaba `libcurl4` | Ya incluido en Dockerfile |
| Tokens vacíos | Archivo no generado aún | Esperar primer arranque / revisar logs |
| No persisten datos tras reinicio | No se montó home | Montar `./data:/home/phoenix/.phoenix` |
| API inaccesible externamente | Bind 127.0.0.1 | Ejecutar con `--http-bind-ip=0.0.0.0` detrás de proxy |

## 📜 Licencia
Consulta la licencia oficial del proyecto Phoenix. Este wrapper Docker no altera la licencia original.

## ✅ Resumen rápido
```pwsh
git clone <este-repo>
cd phoenixd
docker compose up -d
docker exec phoenixd bash -lc 'grep http-password /home/phoenix/.phoenix/phoenix.conf'
docker exec -it phoenixd bash -lc 'phoenix-cli getinfo'
```

Listo. Ajusta persistencia y seguridad antes de usar en producción.
