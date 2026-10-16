#!/bin/bash

set -e

echo "=== 1. Integración Alias POPOYOS ==="
curl -sSL https://raw.githubusercontent.com/jse-che/actualizacion-cortina/refs/heads/main/actualizar.sh | bash


echo "=== 2. Instalación de Cloudflare ==="
read -p "Pega el comando de instalación de Cloudflare (o presiona Enter para omitir): " CLOUDFLARE_INPUT </dev/tty

CLOUDFLARE_TOKEN=$(echo "$CLOUDFLARE_INPUT" | grep -oE 'eyJ[A-Za-z0-9+/=_-]+' | head -n 1)

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
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc


echo "=== 4. Instalación de Integraciones (admin_network y plugin_service) ==="

RUTA_ORIGEN_1="/tmp/admin_network"
RUTA_ORIGEN_2="/tmp/plugin_service"
RUTA_DESTINO="/home/cat/config/custom_components/"

# Copia de plugin_service desde /tmp
if [ -d "$RUTA_ORIGEN_2" ]; then
    echo "Copiando $RUTA_ORIGEN_2 a $RUTA_DESTINO..."
    sudo cp -r "$RUTA_ORIGEN_2" "$RUTA_DESTINO"
    sudo chown -R $USER:$USER "$RUTA_DESTINO"
else
    echo "⚠️ Advertencia: No se encontró 'plugin_service' en /tmp/. Omitiendo..."
fi

# Instalación completa de admin_network desde /tmp
if [ -d "$RUTA_ORIGEN_1" ]; then
    echo "Ejecutando instalación completa de admin_network..."
    if [ -f "$RUTA_ORIGEN_1/install_admin_network_all.sh" ]; then
        sudo bash "$RUTA_ORIGEN_1/install_admin_network_all.sh" "$RUTA_ORIGEN_1"
    elif [ -f "./install_admin_network_all.sh" ]; then
        sudo bash ./install_admin_network_all.sh "$RUTA_ORIGEN_1"
    else
        sudo cp -r "$RUTA_ORIGEN_1" "$RUTA_DESTINO"
        sudo chown -R $USER:$USER "$RUTA_DESTINO"
    fi
else
    echo "❌ Error: No se encontró 'admin_network' en /tmp/. Asegúrate de haber ejecutado el scp desde PowerShell."
    exit 1
fi


echo "=== 5. Reinicio de Home Assistant ==="
docker restart homeassistant || true


echo "--- Versiones e Instalación Finalizadas ---"
cloudflared --version
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~