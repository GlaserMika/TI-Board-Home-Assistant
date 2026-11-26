#!/usr/bin/env bash
# install-ha-container.sh
#
# Richtet Home Assistant Container (Docker) auf einem 64-bit Debian/Ubuntu-Board ein.
# Auf dem Board als root ausfuehren:
#
#   sudo ./scripts/install-ha-container.sh [Optionen]
#
# Optionen:
#   --data-dir DIR     Ablage fuer Compose-Datei und Konfiguration (Standard: /opt/homeassistant)
#   --docker-root DIR  Docker-Daten (Images, Container) auf ein anderes Laufwerk legen,
#                      z. B. eine microSD-Karte, wenn der interne eMMC zu klein ist
#   --tz ZONE          Zeitzone (Standard: Systemzeitzone, sonst Europe/Berlin)
#   --force            Hardware-Pruefung ueberspringen
#
# Die Schritte sind wiederholbar: ein erneuter Aufruf aktualisiert das Image
# und startet den Container neu, die Konfiguration bleibt erhalten.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DATA_DIR="/opt/homeassistant"
DOCKER_ROOT=""
TZ_VALUE=""
FORCE=0
MIN_DOCKER_MAJOR=23
MIN_FREE_DOCKER_BYTES=5000000000

step=0
step() { step=$((step + 1)); printf '\n[Schritt %d] %s\n' "$step" "$*"; }
die()  { printf '\nFEHLER: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --data-dir)    DATA_DIR="$2"; shift ;;
        --docker-root) DOCKER_ROOT="$2"; shift ;;
        --tz)          TZ_VALUE="$2"; shift ;;
        --force)       FORCE=1 ;;
        -h|--help)     sed -n '2,19p' "$0"; exit 0 ;;
        *)             die "Unbekannte Option: $1" ;;
    esac
    shift
done

[ "$(id -u)" -eq 0 ] || die "Bitte als root ausfuehren: sudo $0"

if [ -z "$TZ_VALUE" ]; then
    TZ_VALUE=$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true)
    [ -n "$TZ_VALUE" ] && [ "$TZ_VALUE" != "Etc/UTC" ] || TZ_VALUE="Europe/Berlin"
fi

# ---------------------------------------------------------------------------
step "Hardware und System pruefen"
# ---------------------------------------------------------------------------
if [ "$FORCE" -eq 1 ]; then
    echo "  uebersprungen (--force)"
elif ! bash "$SCRIPT_DIR/check-board.sh"; then
    die "Das Board erfuellt die Mindestanforderungen nicht. Siehe docs/anforderungen.md."
fi

# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-}" in
    debian) DOCKER_DISTRO=debian; CODENAME="${VERSION_CODENAME:-}" ;;
    ubuntu) DOCKER_DISTRO=ubuntu; CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}" ;;
    *) die "Nicht unterstuetztes OS '${ID:-?}'. Unterstuetzt werden Debian und Ubuntu." ;;
esac
[ -n "$CODENAME" ] || die "Versions-Codename des OS nicht ermittelbar."

# ---------------------------------------------------------------------------
step "Systempakete aktualisieren und Voraussetzungen installieren"
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl gnupg

# ---------------------------------------------------------------------------
step "Docker Engine einrichten (mind. ${MIN_DOCKER_MAJOR}.0.0)"
# ---------------------------------------------------------------------------
if [ -n "$DOCKER_ROOT" ]; then
    mkdir -p "$DOCKER_ROOT" /etc/docker
    if [ -f /etc/docker/daemon.json ] && ! grep -q '"data-root"' /etc/docker/daemon.json; then
        die "/etc/docker/daemon.json existiert bereits; bitte \"data-root\": \"$DOCKER_ROOT\" dort selbst eintragen."
    fi
    printf '{\n  "data-root": "%s"\n}\n' "$DOCKER_ROOT" > /etc/docker/daemon.json
    echo "  Docker-Daten liegen unter $DOCKER_ROOT"
fi

docker_major=0
if command -v docker >/dev/null 2>&1; then
    systemctl start docker 2>/dev/null || true
    docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null | tr -d '[:space:]' || true)
    docker_major=${docker_ver%%.*}
    [[ "$docker_major" =~ ^[0-9]+$ ]] || docker_major=0
fi

if [ "$docker_major" -ge "$MIN_DOCKER_MAJOR" ] && docker compose version >/dev/null 2>&1; then
    echo "  Docker $docker_ver mit Compose-Plugin ist bereits installiert"
    [ -n "$DOCKER_ROOT" ] && systemctl restart docker
else
    # Alte Distributionspakete entfernen, die mit docker-ce kollidieren
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            apt-get remove -y "$pkg"
        fi
    done

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$DOCKER_DISTRO/gpg" -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$DOCKER_DISTRO $CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    [ -n "$DOCKER_ROOT" ] && systemctl restart docker

    docker_ver=$(docker version --format '{{.Server.Version}}')
    docker_major=${docker_ver%%.*}
    [ "$docker_major" -ge "$MIN_DOCKER_MAJOR" ] || die "Docker $docker_ver ist zu alt (mind. ${MIN_DOCKER_MAJOR}.0.0)."
    echo "  Docker $docker_ver installiert"
fi

docker_root_dir=$(docker info --format '{{.DockerRootDir}}')
free_bytes=$(( $(df -P -k "$docker_root_dir" | awk 'NR == 2 { print $4 }') * 1024 ))
if [ "$free_bytes" -lt "$MIN_FREE_DOCKER_BYTES" ]; then
    die "Nur $((free_bytes / 1000000)) MB frei unter $docker_root_dir. Das Home-Assistant-Image braucht mehrere GB. Mit --docker-root auf ein groesseres Laufwerk legen."
fi

# ---------------------------------------------------------------------------
step "Konfigurationsverzeichnis und Compose-Datei anlegen ($DATA_DIR)"
# ---------------------------------------------------------------------------
mkdir -p "$DATA_DIR/config"
install -m 0644 "$REPO_DIR/homeassistant/docker-compose.yml" "$DATA_DIR/docker-compose.yml"
cat > "$DATA_DIR/.env" <<EOF
HA_CONFIG_DIR=$DATA_DIR/config
TZ=$TZ_VALUE
EOF
echo "  Compose-Datei: $DATA_DIR/docker-compose.yml"
echo "  Konfiguration: $DATA_DIR/config"
echo "  Zeitzone:      $TZ_VALUE"

# ---------------------------------------------------------------------------
step "Home-Assistant-Image laden und Container starten"
# ---------------------------------------------------------------------------
cd "$DATA_DIR"
docker compose pull
docker compose up -d

# ---------------------------------------------------------------------------
step "Auf die Weboberflaeche warten (Port 8123, max. 10 Minuten)"
# ---------------------------------------------------------------------------
# Der erste Start dauert auf ARM-Boards einige Minuten.
for _ in $(seq 1 120); do
    if curl -fs -o /dev/null http://127.0.0.1:8123/; then
        ready=1
        break
    fi
    printf '.'
    sleep 5
done
echo

if [ "${ready:-0}" -ne 1 ]; then
    docker logs --tail 50 homeassistant || true
    die "Home Assistant antwortet nach 10 Minuten nicht. Logs oben pruefen: docker logs -f homeassistant"
fi

ip_addr=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')
printf '\nHome Assistant laeuft.\n'
printf '  Weboberflaeche: http://%s:8123\n' "${ip_addr:-<IP-des-Boards>}"
printf '  Dort das Onboarding (Benutzerkonto, Standort) abschliessen.\n'
printf '  Logs:           docker logs -f homeassistant\n'
printf '  Update:         sudo %s/install-ha-container.sh\n' "$SCRIPT_DIR"
