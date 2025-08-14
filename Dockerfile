# Etapa 1: descarga y preparación
FROM debian:bullseye-slim AS downloader

RUN apt-get update && apt-get install -y curl unzip && \
    curl -L https://github.com/ACINQ/phoenixd/releases/download/v0.3.3/phoenix-0.3.3-linux-x64.zip -o phoenix.zip && \
    unzip phoenix.zip && \
    mv phoenix-0.3.3-linux-x64/phoenixd /phoenixd && \
    mv phoenix-0.3.3-linux-x64/phoenix-cli /phoenix-cli && \
    rm -rf phoenix.zip phoenix-0.3.3-linux-x64


# Etapa 2: imagen final ligera y segura
FROM debian:bullseye-slim

# Crear usuario no root
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} phoenix && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash phoenix

# Instalar dependencias mínimas (incluye libsqlite3-0 requerida en runtime)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        libsqlite3-0 \
        libcurl4 \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Copiar binarios desde etapa anterior (daemon y CLI)
COPY --from=downloader /phoenixd /usr/local/bin/phoenixd
COPY --from=downloader /phoenix-cli /usr/local/bin/phoenix-cli

# Script de rotación de passwords HTTP (shebang y generación segura)
COPY rotate-phoenix-http-passwords.sh /usr/local/bin/rotate-phoenix-http-passwords
RUN sed -i '1{/^\/\//d}' /usr/local/bin/rotate-phoenix-http-passwords && \
        chmod 0755 /usr/local/bin/rotate-phoenix-http-passwords

# Wrapper de entrypoint para asegurar permisos seguros del directorio de datos
COPY --chmod=0755 <<'EOF' /usr/local/bin/docker-entrypoint.sh
#!/usr/bin/env bash
set -e
# Asegura permisos estrictos en el directorio de datos (si existe)
if [ -n "$HOME" ] && [ -d "$HOME/.phoenix" ]; then
    chmod 700 "$HOME/.phoenix" 2>/dev/null || true
fi
exec phoenixd "$@"
EOF

USER phoenix
WORKDIR /home/phoenix
ENV HOME=/home/phoenix

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
