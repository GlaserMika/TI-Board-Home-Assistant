# TI-Board als Home Assistant Server

Werkzeuge, um ein angeschlossenes Texas-Instruments-Board (BeagleBoard,
TI Starter Kit, LaunchPad) zu erkennen, seine Spezifikationen mit den
Anforderungen von Home Assistant abzugleichen und, wenn es geeignet ist,
Home Assistant darauf einzurichten.

| Datei | Läuft auf | Zweck |
|---|---|---|
| [`scripts/find-board.sh`](scripts/find-board.sh) | Rechner, an dem das Board hängt | Board über USB, serielle Schnittstelle und Netzwerk finden; Prüfung per SSH starten |
| [`scripts/check-board.sh`](scripts/check-board.sh) | Board | Spezifikationen auslesen und mit den Anforderungen abgleichen |
| [`scripts/install-ha-container.sh`](scripts/install-ha-container.sh) | Board | Docker und Home Assistant Container Schritt für Schritt installieren |
| [`homeassistant/docker-compose.yml`](homeassistant/docker-compose.yml) | Board | Compose-Definition des Home-Assistant-Containers |
| [`docs/anforderungen.md`](docs/anforderungen.md) | – | Anforderungen, Übersicht der TI-Boards, Empfehlung als Alternative |

## Kurzfassung der Anforderungen

Home Assistant läuft seit Release 2025.12 nur noch auf **64-bit-Systemen**
(ARM64 oder x86-64) und braucht mindestens **2 GB RAM** und **32 GB Speicher**.
Für TI-Boards gibt es kein Home-Assistant-OS-Image, daher wird
**Home Assistant Container** (Docker) auf Debian installiert.
Details und Quellen: [`docs/anforderungen.md`](docs/anforderungen.md).

## Schritt für Schritt

### 1. Board vorbereiten

1. Wenn der Onboard-Speicher kleiner als 32 GB ist: 64-bit-Debian-Image von
   [BeagleBoard.org](https://www.beagleboard.org/distros) bzw. das TI-SDK auf
   eine microSD-Karte **>= 32 GB** schreiben und davon booten.
2. Board per USB-Datenkabel oder per LAN mit dem Rechner verbinden und booten.

Die BeagleBoard-Images stellen über USB ein Netzwerk bereit, das Board ist
dann unter `192.168.7.2` (Windows) bzw. `192.168.6.2` (Linux/macOS) per SSH
erreichbar. Standardbenutzer ist `debian`; das Passwort wird beim Erstellen
der Karte festgelegt (bei älteren Images ist es `temppwd`).

### 2. Board finden und prüfen (auf dem Rechner)

```bash
git clone https://github.com/GlaserMika/TI-Board-Home-Assistant.git
```

```bash
cd TI-Board-Home-Assistant
```

```bash
scripts/find-board.sh --check
```

Hängt das Board im LAN, die IP-Adresse angeben:

```bash
scripts/find-board.sh --check --host 192.168.1.50 --user debian
```

Unter Windows (PowerShell) das Skript aufs Board kopieren und dort ausführen:

```bash
scp scripts/check-board.sh debian@192.168.7.2:
```

```bash
ssh debian@192.168.7.2 bash check-board.sh
```

Das Ergebnis endet mit einer klaren Aussage: Anforderungen erfüllt oder
nicht erfüllt. Bei *nicht erfüllt* steht die Empfehlung für passende Hardware
in [`docs/anforderungen.md`](docs/anforderungen.md#3-empfehlung-falls-das-board-nicht-geeignet-ist).

### 3. Home Assistant installieren (auf dem Board)

Repository auf das Board holen, per `git clone` (wenn das Board Internet hat)
oder per `scp -r` vom Rechner, dann:

```bash
cd TI-Board-Home-Assistant
```

```bash
sudo ./scripts/install-ha-container.sh
```

Das Skript führt diese Schritte aus und bricht bei einem Fehler mit einer
Meldung ab:

1. Hardware prüfen (`check-board.sh`), bei nicht erfüllten Anforderungen Abbruch
2. Systempakete aktualisieren
3. Docker Engine aus dem offiziellen Docker-Repository installieren (>= 23.0.0)
4. `/opt/homeassistant` mit Compose-Datei, `.env` und `config/` anlegen
5. Image `ghcr.io/home-assistant/home-assistant:stable` laden und starten
6. Warten, bis die Weboberfläche auf Port 8123 antwortet

Optionen:

| Option | Wirkung |
|---|---|
| `--data-dir DIR` | Ablage für Konfiguration (Standard `/opt/homeassistant`) |
| `--docker-root DIR` | Docker-Daten auf ein anderes Laufwerk legen, z. B. die microSD-Karte, wenn der eMMC zu klein ist |
| `--tz ZONE` | Zeitzone, Standard ist die Systemzeitzone, sonst `Europe/Berlin` |
| `--force` | Hardware-Prüfung überspringen |

### 4. Einrichten

Im Browser `http://<IP-des-Boards>:8123` öffnen und das Onboarding
abschließen (Benutzerkonto, Standort, Geräte).

### Betrieb

Logs anzeigen:

```bash
sudo docker logs -f homeassistant
```

Auf die neueste Version aktualisieren (Konfiguration bleibt erhalten):

```bash
sudo ./scripts/install-ha-container.sh
```

## Status

- [x] Prüf- und Installationsskripte erstellt (getestet: Syntax, Shellcheck,
      Prüflauf auf einem x86-64-Linux)
- [ ] Verbindung zum Board herstellen
- [ ] Spezifikationen des Boards prüfen
- [ ] Home Assistant installieren oder Alternative wählen
