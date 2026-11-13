#!/bin/bash

set -e

echo "=== 1. Configuration.yaml file (For HA 2026.8+) ==="
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



echo "=== 2. Cleaning of old components and installation of custom components ==="
mkdir -p /home/cat/config/custom_components

# Borrado de carpetas específicas en custom_components
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc



echo "=== 3. Cleaning and Decluttering Space ==="
sudo apt-get clean
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache /home/cat/*.zip /home/cat/config/config
sudo journalctl --vacuum-time=1d
docker image prune -f
df -h /



echo "=== 4. Backup and Removal of the Old Version ==="
# 1. Crear respaldo comprimido con fecha y hora actual
BACKUP_NAME="ha_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
echo "Creating a compressed backup in /home/cat/${BACKUP_NAME}..."
tar -czf "/home/cat/${BACKUP_NAME}" -C /home/cat config

echo "Backup created successfully."

# 2. Detener y remover contenedor existente
docker stop homeassistant || true
docker rm homeassistant || true

# 3. Eliminar la imagen previa de Home Assistant
echo "Removing the Home Assistant preview image..."
docker images
sudo docker image prune -a

# 4. Limpieza de imágenes huérfanas y caché de Docker
docker image prune -af
docker system prune -f
docker builder prune -af
df -h /



echo "=== 4. Dowload Version of Home Assistant 2026.9.3 ==="
sudo docker pull ghcr.io/home-assistant/home-assistant:2026.9.3
sudo docker run -d \
  --name homeassistant \
  --privileged \
  --restart unless-stopped \
  -e TZ=America/Bogota \
  -v /home/cat/config:/config \
  -v /home/cat/media:/media \
  -v /etc/localtime:/etc/localtime:ro \
  -v /run/dbus:/run/dbus:ro \
  --network host \
  ghcr.io/home-assistant/home-assistant:2026.9.3



echo "=== 5. Configuration.yaml file (For HA 2026.8+) ==="
cat << 'EOF'> /home/cat/config/configuration.yaml
http:
  use_x_forwarded_for: true

  trusted_proxies:
    - 127.0.0.1
    - ::1

  cors_allowed_origins:
    - https://www.horussmartenergyapp.com
    - https://staging.horussmartenergyapp.com
    - https://develop.horussmartenergyapp.com

  use_x_frame_options: false

# Loads default set of integrations. Do not remove.
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

# Z-Wave JS UI control panel embedded as a sidebar entry (served by zwave-js-ui on :8091).
# panel_iframe was removed in HA 2024.11; the replacement is a YAML dashboard with an iframe card.
lovelace:
  dashboards:
    zwave-panel:
      mode: yaml
      filename: zwave-panel.yaml
      title: "Z-Wave"
      icon: mdi:z-wave
      show_in_sidebar: true
      require_admin: true

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF



echo "=== 6. Installation of integrations Jose Charris ==="
wget -qO- https://raw.githubusercontent.com/jse-che/nexxo-led-manager/main/install.sh | sh
curl -sSL https://raw.githubusercontent.com/jse-che/actualizacion-cortina/refs/heads/main/actualizar.sh | bash

docker restart homeassistant || true



echo "=== 8. Z-Wave UI Update ==="
sudo systemctl stop zwave-ui.service
sudo npm install -g zwave-js-ui@latest
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache
sudo systemctl restart zwave-ui.service
sudo systemctl status zwave-ui.service



echo "=== 9. Final Verification and Home Assistant Restart ==="
docker restart homeassistant || true
df -h /
docker ps
sudo systemctl is-active zwave-ui.service
du -m /home/cat/config/home-assistant_v2.db || true
cloudflared --version
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~
echo "--- Versions and Installation Completed ---"