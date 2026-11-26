#!/usr/bin/env bash
# find-board.sh
#
# Laeuft auf dem Rechner, an dem das TI-Board per USB haengt (Linux oder macOS).
# Sucht das Board ueber USB, serielle Schnittstellen und das USB-Netzwerk
# der BeagleBoard-Images und fuehrt optional check-board.sh per SSH aus.
#
# Nutzung:
#   scripts/find-board.sh                       # nur suchen
#   scripts/find-board.sh --check               # suchen und Spezifikationen pruefen
#   scripts/find-board.sh --check --host 192.168.1.50 --user debian

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SSH_USER="debian"
SSH_HOST=""
RUN_CHECK=0

while [ $# -gt 0 ]; do
    case "$1" in
        --check) RUN_CHECK=1 ;;
        --host)  SSH_HOST="$2"; shift ;;
        --user)  SSH_USER="$2"; shift ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
    shift
done

section() { printf '\n== %s ==\n' "$*"; }

# TCP-Port mit 3 s Timeout pruefen, ohne nc/timeout vorauszusetzen.
port_open() {
    local host=$1 port=$2 pid watchdog rc
    ( exec 3<>"/dev/tcp/$host/$port" ) >/dev/null 2>&1 &
    pid=$!
    ( sleep 3; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid" 2>/dev/null
    rc=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
    return $rc
}

# ---------------------------------------------------------------------------
section "USB-Geraete"
# ---------------------------------------------------------------------------
# 0451 = Texas Instruments, 2047 = Texas Instruments (MSP430-Tools),
# 1d6b:0104 = USB-Gadget der BeagleBoard-Debian-Images
usb_pattern='Texas Instruments|0451:|2047:|1d6b:0104|Beagle|XDS110|LaunchPad'
found_usb=""
case "$(uname -s)" in
    Linux)
        if command -v lsusb >/dev/null 2>&1; then
            found_usb=$(lsusb | grep -Ei "$usb_pattern")
        else
            echo "  lsusb fehlt (Paket usbutils)"
        fi
        ;;
    Darwin)
        found_usb=$(system_profiler SPUSBDataType 2>/dev/null | grep -Ei -B2 -A6 "$usb_pattern")
        ;;
esac
if [ -n "$found_usb" ]; then
    echo "$found_usb" | sed 's/^/  /'
else
    echo "  Kein TI-/Beagle-USB-Geraet gefunden"
fi

# ---------------------------------------------------------------------------
section "Serielle Schnittstellen"
# ---------------------------------------------------------------------------
serials=$(ls /dev/ttyACM* /dev/ttyUSB* /dev/cu.usbmodem* /dev/cu.usbserial* 2>/dev/null)
if [ -n "$serials" ]; then
    echo "$serials" | sed 's/^/  /'
    echo "  Serielle Konsole z. B.: screen <geraet> 115200"
else
    echo "  Keine gefunden"
fi

# ---------------------------------------------------------------------------
section "Netzwerk (SSH)"
# ---------------------------------------------------------------------------
# BeagleBoard-Images stellen ueber USB ein Netzwerk bereit:
#   192.168.7.2 (RNDIS, Windows) und 192.168.6.2 (ECM/NCM, Linux/macOS)
candidates="192.168.7.2 192.168.6.2 beaglebone.local beagleplay.local beagley-ai.local"
[ -n "$SSH_HOST" ] && candidates="$SSH_HOST"
reachable=""
for host in $candidates; do
    if port_open "$host" 22; then
        echo "  $host: SSH erreichbar"
        [ -z "$reachable" ] && reachable=$host
    else
        echo "  $host: nicht erreichbar"
    fi
done

if [ -z "$reachable" ]; then
    echo
    echo "Kein Board per SSH erreichbar. Pruefen:"
    echo "  - Board per USB-Datenkabel (nicht nur Ladekabel) verbunden und gebootet?"
    echo "  - Board im LAN? Dann: scripts/find-board.sh --check --host <IP-des-Boards>"
    exit 1
fi

if [ "$RUN_CHECK" -eq 1 ]; then
    section "Spezifikationen von $SSH_USER@$reachable"
    ssh -o ConnectTimeout=10 "$SSH_USER@$reachable" 'bash -s' < "$SCRIPT_DIR/check-board.sh"
    exit $?
fi

echo
echo "Board gefunden: $reachable"
echo "Spezifikationen pruefen: scripts/find-board.sh --check --host $reachable --user $SSH_USER"
