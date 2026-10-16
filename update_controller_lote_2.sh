#!/bin/bash

set -e

echo "=== 1. Integración Alias POPOYOS ==="
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


echo "=== 3. Instalación Completa de Admin Network (Horus HAS Admin) ==="

# 1. Validar ejecución como root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Este script debe ejecutarse con permisos de superusuario (root o sudo)." >&2
    exit 1
fi

# 2. Determinar ruta de origen de admin_network
SRC_DIR="${1:-.}"
if [ ! -f "$SRC_DIR/manifest.json" ] && [ ! -d "$SRC_DIR/host" ]; then
    if [ -d "integrations/admin_network" ]; then
        SRC_DIR="integrations/admin_network"
    elif [ -d "admin_network" ]; then
        SRC_DIR="admin_network"
    elif [ -d "/tmp/admin_network" ]; then
        SRC_DIR="/tmp/admin_network"
    else
        echo "❌ No se encontró la carpeta admin_network en: $SRC_DIR" >&2
        echo "Asegúrate de haber subido la carpeta a /tmp/admin_network o al directorio actual." >&2
        exit 1
    fi
fi

HOST_DIR="$SRC_DIR/host"
if [ ! -f "$HOST_DIR/install.sh" ]; then
    echo "❌ No se encontró $HOST_DIR/install.sh" >&2
    exit 1
fi

echo "📂 Directorio origen: $(realpath "$SRC_DIR")"

# FASE 3.1: INSTALACIÓN DEL SERVICIO HOST (OS / SYSTEMD)
echo ""
echo "▶ [1/4] Instalando servicio Host en el sistema operativo..."

find "$HOST_DIR" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.service" -o -name "*.txt" \) -exec sed -i 's/\r$//' {} +
chmod +x "$HOST_DIR/install.sh"

APT_CONF="/etc/apt/apt.conf.d/99horus-admin-network-apt"
echo 'Acquire::Check-Valid-Until "false";' > "$APT_CONF"
echo 'Acquire::Check-Date "false";' >> "$APT_CONF"

export DEBIAN_FRONTEND=noninteractive
(cd "$HOST_DIR" && bash install.sh)
rm -f "$APT_CONF"

if ! systemctl is-active --quiet admin_network; then
    echo "❌ El servicio admin_network no inició correctamente." >&2
    journalctl -u admin_network -n 20 --no-pager
    exit 1
fi

ENV_FILE="/etc/admin_network.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ No se encontró el archivo de entorno $ENV_FILE" >&2
    exit 1
fi

API_KEY=$(grep -E '^ADMIN_NETWORK_API_KEY=' "$ENV_FILE" | cut -d '=' -f2- | tr -d "'\" \r")
PORT=$(grep -E '^ADMIN_NETWORK_PORT=' "$ENV_FILE" | cut -d '=' -f2- | tr -d "'\" \r")
PORT="${PORT:-8765}"

if [ -z "$API_KEY" ]; then
    echo "❌ No se encontró ADMIN_NETWORK_API_KEY en $ENV_FILE" >&2
    exit 1
fi

echo "✔ Servicio host activo."
echo "✔ API Key obtenida: ${API_KEY:0:4}...${API_KEY: -4} (Puerto: $PORT)"

curl -sS --max-time 3 "http://127.0.0.1:${PORT}/health" > /dev/null || echo "⚠ Advertencia: /health tardó en responder."

# FASE 3.2: INSTALACIÓN DE LA INTEGRACIÓN EN HOME ASSISTANT
echo ""
echo "▶ [2/4] Desplegando custom_component en Home Assistant..."

HA_CONTAINER=$(docker ps --format '{{.Names}}' | grep -iE 'homeassistant|home-assistant' | head -n 1 || true)
HA_CONFIG_DIR=""

if [ -n "$HA_CONTAINER" ]; then
    HA_CONFIG_DIR=$(docker inspect "$HA_CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}')
fi

if [ -z "$HA_CONFIG_DIR" ] || [ ! -d "$HA_CONFIG_DIR" ]; then
    if [ -d "/home/cat/config" ]; then
        HA_CONFIG_DIR="/home/cat/config"
    elif [ -d "/config" ]; then
        HA_CONFIG_DIR="/config"
    else
        echo "❌ No se pudo localizar la carpeta de configuración de Home Assistant." >&2
        exit 1
    fi
fi

TARGET_COMPONENTS="$HA_CONFIG_DIR/custom_components"
TARGET_ADMIN="$TARGET_COMPONENTS/admin_network"

mkdir -p "$TARGET_COMPONENTS"
rm -rf "$TARGET_ADMIN"
mkdir -p "$TARGET_ADMIN"

rsync -av \
    --exclude="host/" \
    --exclude="__pycache__" \
    --exclude="*.pyc" \
    --exclude=".git" \
    --exclude="venv" \
    --exclude=".venv" \
    "$SRC_DIR/" "$TARGET_ADMIN/" > /dev/null

chown -R --reference="$HA_CONFIG_DIR" "$TARGET_ADMIN"
chmod -R 755 "$TARGET_ADMIN"

echo "✔ Integración copiada en: $TARGET_ADMIN"

# FASE 3.3: INYECCIÓN DE CONFIG ENTRY (core.config_entries)
echo ""
echo "▶ [3/4] Inyectando credenciales y configuración en Home Assistant..."

python3 - <<EOF
import json
import os
import uuid
from datetime import datetime, timezone

path = "${HA_CONFIG_DIR}/.storage/core.config_entries"
host = "127.0.0.1"
port = int("${PORT}")
api_key = "${API_KEY}"
title = f"Admin Network ({host})"

def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f+00:00")

def normalize_entry(entry):
    if not isinstance(entry, dict):
        return False
    changed = False
    if "discovery_keys" not in entry or not isinstance(entry.get("discovery_keys"), dict):
        entry["discovery_keys"] = {}
        changed = True
    if "subentries" not in entry or entry.get("subentries") is None:
        entry["subentries"] = []
        changed = True
    entry.setdefault("options", {})
    entry.setdefault("pref_disable_new_entities", False)
    entry.setdefault("pref_disable_polling", False)
    entry.setdefault("unique_id", None)
    entry.setdefault("disabled_by", None)
    entry.setdefault("minor_version", 1)
    if "created_at" not in entry:
        entry["created_at"] = now()
        changed = True
    if "modified_at" not in entry:
        entry["modified_at"] = now()
        changed = True
    return changed

os.makedirs(os.path.dirname(path), exist_ok=True)
doc = {}
if os.path.isfile(path):
    with open(path, "r", encoding="utf-8") as fh:
        try:
            doc = json.load(fh)
        except Exception:
            doc = {}

if not isinstance(doc, dict):
    doc = {"version": 1, "minor_version": 5, "key": "core.config_entries", "data": {"entries": []}}

doc.setdefault("version", 1)
doc["minor_version"] = max(int(doc.get("minor_version") or 1), 5)
doc["key"] = "core.config_entries"
data = doc.setdefault("data", {})
entries = data.setdefault("entries", [])

repaired = sum(1 for e in entries if normalize_entry(e))

match = None
for entry in entries:
    if entry.get("domain") == "admin_network":
        match = entry
        break

if match:
    match["title"] = title
    match["data"] = {"host": host, "port": port, "api_key": api_key}
    match["version"] = int(match.get("version") or 1)
    match["modified_at"] = now()
    normalize_entry(match)
    match.setdefault("source", "user")
    action = "ACTUALIZADA"
else:
    new_entry = {
        "entry_id": uuid.uuid4().hex,
        "version": 1,
        "minor_version": 1,
        "domain": "admin_network",
        "title": title,
        "data": {"host": host, "port": port, "api_key": api_key},
        "options": {},
        "pref_disable_new_entities": False,
        "pref_disable_polling": False,
        "source": "user",
        "unique_id": None,
        "disabled_by": None,
        "created_at": now(),
        "modified_at": now(),
        "discovery_keys": {},
        "subentries": []
    }
    entries.append(new_entry)
    action = "CREADA"

tmp = path + ".tmp_admin_network"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)

print(f"✔ Entrada {action} en core.config_entries (normalizadas {repaired} entradas).")
EOF

AUTH_FILE="${HA_CONFIG_DIR}/.storage/auth"
CONFIG_ENTRIES="${HA_CONFIG_DIR}/.storage/core.config_entries"
if [ -f "$AUTH_FILE" ]; then
    chown --reference="$AUTH_FILE" "$CONFIG_ENTRIES"
    chmod --reference="$AUTH_FILE" "$CONFIG_ENTRIES"
fi


echo "=== 4. Limpieza de componentes antiguos e Instalación de Custom Components ==="
mkdir -p /home/cat/config/custom_components

# Borrado de carpetas específicas en custom_components
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc

# Reinicio final de Home Assistant para aplicar todos los cambios
if [ -n "$HA_CONTAINER" ]; then
    docker restart "$HA_CONTAINER" || true
else
    docker restart homeassistant || true
fi


echo "--- Versiones e Instalación Finalizadas ---"
cloudflared --version || true
docker exec homeassistant hass --version || true
npm list -g zwave-js-ui || true
cd ~