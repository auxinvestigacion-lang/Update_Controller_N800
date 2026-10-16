#!/bin/bash

set -e

echo "=== 1. Integracion Alias POPOYOS ==="
curl -sSL https://raw.githubusercontent.com/jse-che/actualizacion-cortina/refs/heads/main/actualizar.sh | bash


echo "=== 2. Instalación de Cloudflare ==="

# --- Solicitud e Instalación de Cloudflare ---
echo "=== Configuración e Instalación del Servicio de Cloudflare ==="
read -p "Pega el comando de instalación de Cloudflare (o presiona Enter para omitir): " CLOUDFLARE_INPUT </dev/tty

# Extrae únicamente el token largo en Base64 si pegaste el comando completo
CLOUDFLARE_TOKEN=$(echo "$CLOUDFLARE_INPUT" | grep -oE 'eyJ[A-Za-z0-9+/=_-]+' | head -n 1)

# Si no es un comando con 'eyJ', toma la entrada limpia por si se ingresó el token directo
if [ -z "$CLOUDFLARE_TOKEN" ]; then
    CLOUDFLARE_TOKEN=$(echo "$CLOUDFLARE_INPUT" | tr -d "[:space:]'\"")
fi

if [ -n "$CLOUDFLARE_TOKEN" ]; then
    echo "Instalando servicio de Cloudflare con el token detectado..."
    sudo cloudflared service install "$CLOUDFLARE_TOKEN" || true
else
    echo "No se ingresó un comando/token válido. Omitiendo vinculación de Cloudflare."
fi


echo "=== 3. Limpieza de componentes antiguos ==="
mkdir -p /home/cat/config/custom_components

# Borrado de carpetas específicas en custom_components
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc


echo "--- Versiones e Instalación Finalizadas ---"
cloudflared --version
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~

echo "=== 5. Reinicio de Home Assistant ==="
docker restart homeassistant || true