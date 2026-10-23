#!/bin/bash

set -e


echo "=== 3. Configuración de configuration.yaml (Limpio para HA 2026.8+) ==="
cat << 'EOF'> /home/cat/config/configuration.yaml
# Loads default set of integrations. Do not remove.
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF

docker restart homeassistant || true



echo "=== 4. Limpieza de componentes antiguos e Instalación de Custom Components ==="
mkdir -p /home/cat/config/custom_components

# Borrado de carpetas específicas en custom_components
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc


echo "=== 5. Limpieza y Liberación de Espacio ==="
sudo apt-get clean
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache /home/cat/*.zip /home/cat/config/config
sudo journalctl --vacuum-time=1d
docker image prune -f
df -h /



echo "=== 6. Remoción de la Versión Antigua ==="
docker stop homeassistant || true
docker rm homeassistant || true

# Mostrar las imágenes disponibles para que el usuario elija
echo "Imágenes de Docker disponibles:"
docker images

# Pedir el ID de la imagen de forma interactiva
read -p "Ingresa el ID de la imagen que deseas eliminar: " IMAGE_ID

# Validar que el usuario no haya presionado Enter sin escribir nada
if [ -n "$IMAGE_ID" ]; then
    echo "Eliminando la imagen con ID: $IMAGE_ID..."
    docker rmi -f "$IMAGE_ID" || true
else
    echo "No se ingresó ningún ID. Se omite la eliminación de la imagen."
fi

docker system prune -f
docker builder prune -af
df -h /



echo "=== 7. Instalación integraciones Jose Charris ==="
wget -qO- https://raw.githubusercontent.com/jse-che/nexxo-led-manager/main/install.sh | sh
curl -sSL https://raw.githubusercontent.com/jse-che/actualizacion-cortina/refs/heads/main/actualizar.sh | bash



echo "=== 8. Despliegue de la Versión Nueva ==="
cd /home/cat
docker compose up -d --pull always
docker ps
docker exec homeassistant hass --version
cd ~



echo "=== 9. Actualización de Z-Wave UI ==="
sudo systemctl stop zwave-ui.service
sudo npm install -g zwave-js-ui@latest
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache
sudo systemctl restart zwave-ui.service
sudo systemctl status zwave-ui.service



echo "=== 10. Verificación Final y Reinicio de Home Assistant ==="
docker restart homeassistant || true
df -h /
docker ps
sudo systemctl is-active zwave-ui.service
du -m /home/cat/config/home-assistant_v2.db || true

echo "--- Versiones e Instalación Finalizadas ---"
cloudflared --version
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~