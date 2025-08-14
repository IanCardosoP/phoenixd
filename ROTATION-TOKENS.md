# Rotación de Tokens HTTP de phoenixd

Este documento describe el proceso completo para rotar de forma segura los tokens HTTP (`http-password` y `http-password-limited-access`) usados por la API de `phoenixd`, cómo verificar la rotación y cómo automatizarla mediante `cron` (o `systemd timer`).

## 1. ¿Por qué rotar?
Rotar reduce el riesgo de uso indebido si un token se filtra (logs, scripts, memoria, repositorios, insiders). También aplica principio de *menor tiempo de exposición*.

## 2. Componentes involucrados
- Archivo de configuración: `/home/phoenix/.phoenix/phoenix.conf`
- Script incluido en la imagen: `rotate-phoenix-http-passwords`
- Servicio (contenedor): `phoenixd`

## 3. Qué hace el script
1. Verifica existencia de `phoenix.conf`.
2. Crea un backup con timestamp: `phoenix.conf.bak.YYYYMMDDHHMMSS` en el mismo directorio.
3. Genera dos nuevos valores pseudo-aleatorios (base64 -> filtrado -> 48 chars).
4. Reemplaza (o añade si faltan) líneas:
   - `http-password=...`
   - `http-password-limited-access=...`
5. Muestra los nuevos tokens en stdout.
6. Indica que es necesario reiniciar el daemon para que los use.

## 4. Rotación manual (paso a paso)
```bash
# 1. Ejecutar el script dentro del contenedor
docker exec phoenixd rotate-phoenix-http-passwords

# 2. (Opcional) Verifica el diff (desde host)
#   cat ./data/phoenix.conf | grep http-password

# 3. Reiniciar el contenedor para cargar los nuevos tokens
docker restart phoenixd

# 4. Probar un endpoint con el nuevo token full:
NEW_TOKEN=<copiar_salida_script>
curl -H "Authorization: Bearer $NEW_TOKEN" http://localhost:9740/v1/getinfo
```

Si falla el endpoint, valida que:
- Reinicio fue exitoso: `docker logs phoenixd`.
- El token se copió correctamente (sin espacios extra).

## 5. Rollback (si algo sale mal)
- Localiza el backup más reciente: `ls -1 ./data/phoenix.conf.bak.*`
- Restaura:
```bash
cp ./data/phoenix.conf.bak.<TIMESTAMP> ./data/phoenix.conf
docker restart phoenixd
```

## 6. Frecuencia recomendada
- Entornos críticos / con múltiples integraciones: semanal o quincenal.
- Uso interno controlado: mensual.
- Tras cualquier sospecha de fuga: inmediata.

## 7. Automatización con cron (host Linux)
Asegúrate de que el usuario que programa cron tenga permisos para ejecutar `docker exec` y `docker restart`.

### 7.1 Script wrapper en host
Crea `/usr/local/sbin/phoenix-rotate-http.sh` (host):
```bash
#!/usr/bin/env bash
set -euo pipefail
CONTAINER=${CONTAINER:-phoenixd}
LOGFILE=${LOGFILE:-/var/log/phoenix-rotate-http.log}
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
  echo "[$STAMP] Rotación iniciada"
  docker exec "$CONTAINER" rotate-phoenix-http-passwords | sed 's/http-password=.*/http-password=REDACTED/' | sed 's/http-password-limited-access=.*/http-password-limited-access=REDACTED/'
  docker restart "$CONTAINER" >/dev/null
  echo "[$STAMP] Reinicio completado"
  echo
} >> "$LOGFILE" 2>&1
```
Dar permisos:
```bash
sudo chmod 750 /usr/local/sbin/phoenix-rotate-http.sh
sudo chown root:root /usr/local/sbin/phoenix-rotate-http.sh
```

### 7.2 Entrada cron (ejemplo mensual el día 1 a las 02:17 UTC)
Editar cron:
```bash
sudo crontab -e
```
Agregar línea:
```
17 2 1 * * /usr/local/sbin/phoenix-rotate-http.sh
```

### 7.3 Frecuencia semanal (domingo 03:05)
```
5 3 * * 0 /usr/local/sbin/phoenix-rotate-http.sh
```

### 7.4 Validación post-rotación
Revisar log:
```bash
sudo tail -n 50 /var/log/phoenix-rotate-http.log
```

## 9. Seguridad operacional
- NO almacenar tokens nuevos en logs sin redacción si los logs son centralizados.
- Proteger backups y log de rotación (permisos restrictivos, no world-readable).
- Integrar alerta si el script falla (monitoring de exit code / log scraping).
- Si usas un proxy (Nginx/Traefik) limpia caches o variables que pudieron contener tokens anteriores.

## 10. Integración con aplicaciones
Tras rotar tokens:
1. Regenera secreto en tu gestor (Vault, AWS Secrets Manager, etc.).
2. Recarga apps dependientes (deploy rolling) para que adopten el nuevo token.
3. Verifica que no hay solicitudes fallidas con 401/403 en logs.

## 11. Checklist rápida de rotación manual
- [ ] Ejecutar script rotación
- [ ] Anotar nuevos tokens en gestor seguro
- [ ] Reiniciar contenedor
- [ ] Probar endpoint con nuevo token
- [ ] Eliminar tokens antiguos de scripts/configs
- [ ] Agendar próxima rotación

## 12. Preguntas frecuentes
**¿Puedo rotar sin reiniciar?** No, phoenixd lee el archivo en arranque. 
**¿Puedo mantener dos tokens activos?** No soportado de forma nativa; debes coordinar despliegues rápido.
**¿Qué pasa si pierdo el backup y edité mal el archivo?** Recupera desde un snapshot/backup de filesystem; el script crea backups precisamente para revertir.

---
Fin.
