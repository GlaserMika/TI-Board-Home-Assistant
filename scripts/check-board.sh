#!/usr/bin/env bash
# check-board.sh
#
# Liest die Hardware- und System-Spezifikationen eines (TI-)Boards aus und
# gleicht sie mit den Mindestanforderungen fuer einen Home Assistant Server ab.
#
# Laeuft direkt auf dem Board:
#   bash check-board.sh
# oder vom Host-Rechner aus per SSH:
#   ssh debian@192.168.7.2 'bash -s' < scripts/check-board.sh
#
# Exit-Code: 0 = alle Pflichtanforderungen erfuellt
#            1 = mindestens eine Pflichtanforderung nicht erfuellt

set -u

# ---------------------------------------------------------------------------
# Mindestanforderungen (Stand: Home Assistant ab Release 2025.12)
#   - 64-bit-System (aarch64 oder x86_64). 32-bit (armv7, armhf, i386) wird
#     seit 2025.12 nicht mehr gebaut oder unterstuetzt.
#   - mind. 2 GB RAM
#   - mind. 32 GB Speicher
#   - Fuer Home Assistant Container: Docker Engine >= 23.0.0
# ---------------------------------------------------------------------------
MIN_RAM_KB=1700000          # "2 GB" nominal; der Kernel meldet wegen reserviertem Speicher etwas weniger
MIN_DISK_BYTES=28000000000  # "32 GB" nominal; 32-GB-Karten/eMMC melden ca. 29,7 GiB
MIN_FREE_ROOT_BYTES=8000000000
REC_CORES=2
MIN_DOCKER_MAJOR=23

fails=0
warns=0

ok()   { printf '  [OK]    %s\n' "$*"; }
warn() { printf '  [WARN]  %s\n' "$*"; warns=$((warns + 1)); }
fail() { printf '  [FEHLT] %s\n' "$*"; fails=$((fails + 1)); }
info() { printf '  [INFO]  %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
gb() { awk -v b="$1" 'BEGIN { printf "%.1f GB", b / 1e9 }'; }

# ---------------------------------------------------------------------------
section "Board"
# ---------------------------------------------------------------------------
model=""
compat=""
if [ -r /proc/device-tree/model ]; then
    model=$(tr -d '\0' < /proc/device-tree/model)
fi
if [ -r /proc/device-tree/compatible ]; then
    compat=$(tr '\0' ' ' < /proc/device-tree/compatible)
fi
if [ -z "$model" ] && [ -r /sys/class/dmi/id/product_name ]; then
    model=$(cat /sys/class/dmi/id/product_name)
fi

soc=""
case "$compat" in
    *ti,am33xx*)          soc="TI AM335x (ARM Cortex-A8, 32-bit)" ;;
    *ti,am43*)            soc="TI AM437x (ARM Cortex-A9, 32-bit)" ;;
    *ti,dra7*|*ti,am57*)  soc="TI AM57xx (ARM Cortex-A15, 32-bit)" ;;
    *ti,j721e*)           soc="TI TDA4VM / J721E (ARM Cortex-A72, 64-bit)" ;;
    *ti,j722s*)           soc="TI AM67A / J722S (ARM Cortex-A53, 64-bit)" ;;
    *ti,j784s4*)          soc="TI AM69 / J784S4 (ARM Cortex-A72, 64-bit)" ;;
    *ti,am62a*)           soc="TI AM62A (ARM Cortex-A53, 64-bit)" ;;
    *ti,am62p*)           soc="TI AM62P (ARM Cortex-A53, 64-bit)" ;;
    *ti,am62*)            soc="TI AM62x (ARM Cortex-A53, 64-bit)" ;;
    *ti,am64*)            soc="TI AM64x (ARM Cortex-A53, 64-bit)" ;;
    *ti,*)                soc="TI SoC (nicht naeher bekannt)" ;;
esac

info "Modell:      ${model:-unbekannt}"
[ -n "$soc" ]    && info "SoC:         $soc"
[ -n "$compat" ] && info "Compatible:  $compat"

# ---------------------------------------------------------------------------
section "Betriebssystem"
# ---------------------------------------------------------------------------
os_id=""
os_name="unbekannt"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_name="${PRETTY_NAME:-$os_id}"
fi
info "OS:          $os_name"
info "Kernel:      $(uname -r)"
case "$os_id" in
    debian|ubuntu) ok "Debian/Ubuntu erkannt, wird vom Installationsskript unterstuetzt" ;;
    *)             warn "OS '$os_id' wird vom Installationsskript nicht unterstuetzt (nur Debian/Ubuntu)" ;;
esac

# ---------------------------------------------------------------------------
section "CPU / Architektur (Pflicht: 64-bit)"
# ---------------------------------------------------------------------------
arch=$(uname -m)
cores=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo)
cpu_model=""
if command -v lscpu >/dev/null 2>&1; then
    cpu_model=$(lscpu | awk -F: '/^Model name/ { sub(/^[ \t]+/, "", $2); print $2; exit }')
fi
if [ -z "$cpu_model" ]; then
    cpu_model=$(awk -F: '/^(model name|Hardware|Processor)/ { sub(/^[ \t]+/, "", $2); print $2; exit }' /proc/cpuinfo)
fi
info "CPU:         ${cpu_model:-unbekannt}"
info "Kerne:       $cores"

case "$arch" in
    aarch64|arm64|x86_64|amd64) ok "Kernel-Architektur $arch (64-bit)" ;;
    *) fail "Kernel-Architektur $arch ist 32-bit, Home Assistant unterstuetzt seit 2025.12 nur noch 64-bit (aarch64/x86_64)" ;;
esac

# Ein 64-bit-Kernel mit 32-bit-Userland wuerde trotzdem 32-bit-Container ziehen.
if command -v dpkg >/dev/null 2>&1; then
    userland=$(dpkg --print-architecture)
    case "$userland" in
        arm64|amd64) ok "Userland-Architektur $userland (64-bit)" ;;
        *) fail "Userland-Architektur $userland ist 32-bit, ein 64-bit-Betriebssystem ist erforderlich" ;;
    esac
fi

if [ "$cores" -ge "$REC_CORES" ]; then
    ok "$cores CPU-Kerne (empfohlen: mind. $REC_CORES)"
else
    warn "$cores CPU-Kern(e), empfohlen sind mind. $REC_CORES"
fi

# ---------------------------------------------------------------------------
section "Arbeitsspeicher (Pflicht: mind. 2 GB)"
# ---------------------------------------------------------------------------
mem_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
mem_bytes=$((mem_kb * 1024))
if [ "$mem_kb" -ge "$MIN_RAM_KB" ]; then
    ok "RAM: $(gb "$mem_bytes")"
else
    fail "RAM: $(gb "$mem_bytes"), mind. 2 GB erforderlich"
fi

# ---------------------------------------------------------------------------
section "Speicher (Pflicht: mind. 32 GB)"
# ---------------------------------------------------------------------------
largest_bytes=0
largest_name=""
for dev in /sys/block/*; do
    name=$(basename "$dev")
    case "$name" in
        loop*|ram*|zram*|mtdblock*|*boot[0-9]|*rpmb|sr*|dm-*|md*) continue ;;
    esac
    [ -r "$dev/size" ] || continue
    sectors=$(cat "$dev/size")
    bytes=$((sectors * 512))
    [ "$bytes" -ge 1000000000 ] || continue  # Laufwerke unter 1 GB sind keine Datenablage
    removable=$(cat "$dev/removable" 2>/dev/null || echo 0)
    kind="intern"
    case "$name" in
        mmcblk*)
            mmc_type=$(cat "$dev/device/type" 2>/dev/null || echo "")
            case "$mmc_type" in
                MMC) kind="eMMC" ;;
                SD)  kind="microSD" ;;
            esac
            ;;
        nvme*) kind="NVMe" ;;
        sd*)   [ "$removable" = "1" ] && kind="USB/wechselbar" || kind="SATA/USB" ;;
    esac
    info "Laufwerk /dev/$name ($kind): $(gb "$bytes")"
    if [ "$bytes" -gt "$largest_bytes" ]; then
        largest_bytes=$bytes
        largest_name=$name
    fi
done

if [ "$largest_bytes" -ge "$MIN_DISK_BYTES" ]; then
    ok "Groesstes Laufwerk /dev/$largest_name: $(gb "$largest_bytes")"
elif [ "$largest_bytes" -gt 0 ]; then
    fail "Groesstes Laufwerk /dev/$largest_name: $(gb "$largest_bytes"), mind. 32 GB erforderlich (z. B. microSD-Karte >= 32 GB einsetzen)"
else
    fail "Kein Laufwerk gefunden"
fi

root_line=$(df -P -k / | awk 'NR == 2')
root_dev=$(echo "$root_line" | awk '{ print $1 }')
root_size=$(( $(echo "$root_line" | awk '{ print $2 }') * 1024 ))
root_free=$(( $(echo "$root_line" | awk '{ print $4 }') * 1024 ))
info "Root-Dateisystem $root_dev: $(gb "$root_size") gesamt, $(gb "$root_free") frei"
if [ "$root_free" -lt "$MIN_FREE_ROOT_BYTES" ]; then
    warn "Weniger als $(gb "$MIN_FREE_ROOT_BYTES") frei auf /, Docker-Daten sollten auf das groessere Laufwerk (Option --docker-root im Installationsskript)"
fi

# ---------------------------------------------------------------------------
section "Container-Unterstuetzung"
# ---------------------------------------------------------------------------
if [ -r /sys/fs/cgroup/cgroup.controllers ]; then
    ok "cgroup v2 aktiv"
elif [ -d /sys/fs/cgroup/memory ]; then
    info "cgroup v1 aktiv (Docker funktioniert, v2 empfohlen)"
else
    warn "Keine cgroup-Hierarchie gefunden, Docker funktioniert eventuell nicht"
fi

if grep -qw overlay /proc/filesystems 2>/dev/null || modinfo overlay >/dev/null 2>&1; then
    ok "OverlayFS verfuegbar (Docker-Storage-Treiber overlay2)"
else
    warn "OverlayFS nicht gefunden, Docker nutzt dann einen langsameren Storage-Treiber"
fi

if command -v docker >/dev/null 2>&1; then
    # Server-Version braucht einen laufenden Dienst, sonst Client-Version nehmen
    docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null | tr -d '[:space:]')
    if [ -z "$docker_ver" ]; then
        docker_ver=$(docker --version 2>/dev/null | sed -E 's/[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    fi
    docker_major=${docker_ver%%.*}
    if [ -n "$docker_major" ] && [ "$docker_major" -ge "$MIN_DOCKER_MAJOR" ] 2>/dev/null; then
        ok "Docker $docker_ver installiert (mind. $MIN_DOCKER_MAJOR.0.0)"
    else
        warn "Docker ${docker_ver:-unbekannt} installiert, mind. $MIN_DOCKER_MAJOR.0.0 noetig (Installationsskript aktualisiert)"
    fi
else
    info "Docker nicht installiert (wird vom Installationsskript installiert)"
fi

# ---------------------------------------------------------------------------
section "Netzwerk"
# ---------------------------------------------------------------------------
if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show scope global 2>/dev/null | awk '{ printf "  [INFO]  %-12s %s\n", $2, $4 }'
fi
if command -v curl >/dev/null 2>&1; then
    # Die Registry antwortet ohne Login mit 401, jeder HTTP-Code ausser 000 heisst "erreichbar".
    http_code=$(curl -sS -m 8 -o /dev/null -w '%{http_code}' https://ghcr.io/v2/ 2>/dev/null)
    if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
        ok "Internetzugang (ghcr.io erreichbar, Container-Image kann geladen werden)"
    else
        warn "ghcr.io nicht erreichbar, fuer die Installation ist Internetzugang noetig"
    fi
else
    info "curl nicht installiert, Internetzugang nicht geprueft"
fi

# ---------------------------------------------------------------------------
section "Funk-Schnittstellen (optional)"
# ---------------------------------------------------------------------------
if [ -d /sys/class/bluetooth ] && [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
    info "Bluetooth-Adapter: $(ls /sys/class/bluetooth | tr '\n' ' ')"
else
    info "Kein Bluetooth-Adapter gefunden"
fi
serials=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null | tr '\n' ' ')
[ -n "$serials" ] && info "Serielle USB-Geraete (z. B. Zigbee-Stick): $serials"
case "$model" in
    *BeaglePlay*) info "BeaglePlay hat einen TI CC1352P7 (Zigbee/Thread), nutzbar mit passender Firmware" ;;
esac

# ---------------------------------------------------------------------------
section "Ergebnis"
# ---------------------------------------------------------------------------
if [ "$fails" -eq 0 ]; then
    printf '  Das Board erfuellt die Mindestanforderungen (%d Warnung(en)).\n' "$warns"
    printf '  Naechster Schritt: sudo ./scripts/install-ha-container.sh\n'
    exit 0
else
    printf '  Das Board erfuellt %d Pflichtanforderung(en) NICHT (%d Warnung(en)).\n' "$fails" "$warns"
    printf '  Home Assistant ist auf diesem Board nicht sinnvoll betreibbar.\n'
    printf '  Alternativen: siehe docs/anforderungen.md, Abschnitt "Empfehlung"\n'
    exit 1
fi
