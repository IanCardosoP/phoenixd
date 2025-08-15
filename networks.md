# Red externa Docker: backend

Este proyecto usa una red externa Docker llamada `backend` para permitir que otros servicios (en otros docker-compose) consuman la API interna de `phoenixd` sin exponer el puerto públicamente.

## 1. Crear la red (una sola vez)

Linux / macOS:
```bash
docker network create backend || echo "Ya existe"
```

Windows PowerShell:
```powershell
docker network create backend 2>$null ; if ($LASTEXITCODE -ne 0) { "Ya existe" }
```

Verificar:
```bash
docker network inspect backend --format '{{.Name}}'
```

## 2. Usar la red en este proyecto

Ya está configurado en `docker-compose.yml`:
```yaml
networks:
  backend:
    external: true
    name: backend
```

Levantar:
```bash
docker compose up -d
```

## 3. Conectar otro servicio (en OTRO docker-compose)

Ejemplo en otro proyecto:
```yaml
services:
  miapp:
    image: alpine:3.19
    command: sleep 3600
    networks:
      - backend

networks:
  backend:
    external: true
    name: backend
```

Dentro de `miapp` podrás llamar:
```
curl -H "Authorization: Bearer <TOKEN>" http://phoenixd:9740/v1/invoices
```

Nota: No uses `localhost` dentro de otro contenedor; usa el nombre `phoenixd`.

## 4. Exposición controlada

Mientras NO descomentes `ports:` en phoenixd:
- API accesible solo desde contenedores en la red `backend`.
- El host no puede hacer `curl localhost:9740` (si necesitas ambos, descomenta `127.0.0.1:9740:9740`).

## 5. Seguridad

- Cualquier contenedor unido a `backend` podrá alcanzar la API; limita qué servicios agregas.
- Rotar `http-password` si sospechas filtración.
- No expongas 9740 a Internet directamente; usa proxy con TLS si necesitas acceso remoto.

## 6. Añadir contenedor puntual ya creado

Para anexar uno existente:
```bash
docker network connect backend <nombre_contenedor>
```

Para retirarlo:
```bash
docker network disconnect backend <nombre_contenedor>
```

## 7. Depuración

Listar contenedores en la red:
```bash
docker network inspect backend | grep Name
```

Probar resolución DNS (desde otro servicio):
```bash
apk add --no-cache curl # si es Alpine
curl http://phoenixd:9740/version
```

## 8. Eliminar la red (solo si ya no la usa nada)

```bash
docker network rm backend
```

(No eliminar si otros proyectos aún dependen.)

## 9. Resumen rápido

1. Crear red: `docker network create backend`
2. Cada compose: declarar red externa `backend`
3. Acceso interno: `http://phoenixd:9740`
4. Sin puertos publicados = aislado del exterior

Fin.