#!/bin/bash

set -e

echo "=== 1. Instalación de Nexxo LED Manager ==="
curl -sSL https://raw.githubusercontent.com/jse-che/actualizacion-cortina/refs/heads/main/actualizar.sh | bash


echo "=== 2. Instalación de Cloudflare ==="
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg>/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

# Se ignora la comprobación de vigencia de firmas/fechas de los repositorios
sudo apt-get update -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false && sudo apt-get install -y cloudflared

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


echo "=== 3. Limpieza de componentes antiguos e Instalación de Custom Components ==="
mkdir -p /home/cat/config/custom_components

# Borrado de carpetas específicas en custom_components
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc

# URLs de los componentes en GitHub
URLS=(
    "https://raw.githubusercontent.com/auxinvestigacion-lang/update_ha_zwave/main/plugin_service_energy.zip"
    "https://raw.githubusercontent.com/auxinvestigacion-lang/update_ha_zwave/main/admin_network.zip"
)

# Directorio de destino de Home Assistant
DESTINO="/home/cat/config/custom_components/"

for url in "${URLS[@]}"; do
    echo "Procesando: $url..."
    curl -sSL "$url" -o /tmp/componente.zip

    if unzip -t /tmp/componente.zip >/dev/null 2>&1; then
        unzip -o /tmp/componente.zip -d "$DESTINO"
        rm -f /tmp/componente.zip
        echo " -> Instalado exitosamente."
    else
        echo " -> ERROR: No se pudo descargar un ZIP válido desde $url"
        rm -f /tmp/componente.zip
        exit 1
    fi
done

echo "Todos los componentes se instalaron correctamente."

docker restart homeassistant || true


-- Versiones e Instalación Finalizadas ---"
cloudflared --version
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~