# Home Assistant: Anforderungen und TI-Boards im Abgleich

Stand: November 2026

## 1. Mindestanforderungen an einen Home Assistant Server

| Kriterium | Anforderung | Pflicht | Quelle |
|---|---|---|---|
| CPU-Architektur | 64-bit: `aarch64` (ARM64) oder `x86_64` | ja | [Deprecation-Blogpost][deprecation], [System architecture][arch] |
| Arbeitsspeicher | mind. 2 GB, 4 GB empfohlen | ja | [Installation][install] |
| Speicher | mind. 32 GB (eMMC, SSD oder hochwertige microSD) | ja | [Installation][install] |
| CPU-Kerne | mind. 2 | empfohlen | [Installation][install] |
| Betriebssystem | Home Assistant OS **oder** ein Linux mit Docker | ja | [Installation][install] |
| Docker (nur Container) | Docker Engine >= 23.0.0, kein Docker Desktop | ja | [Docker-Installation][docker] |
| Netzwerk | LAN (empfohlen) oder WLAN, Internet für Installation und Updates | ja | – |

Seit Release **2025.12** baut Home Assistant keine Images mehr für
32-bit-Plattformen (`armv7`, `armhf`, `i386`), und die Installationsarten
*Core* und *Supervised* werden nicht mehr unterstützt. Offiziell unterstützt
werden nur noch:

- **Home Assistant OS**: komplettes Betriebssystem mit Supervisor und Apps
  (früher Add-ons), nur für die offiziell unterstützten Boards bzw. als
  generisches x86-64-/ARM64-UEFI-Image.
- **Home Assistant Container**: Docker-Container auf einem vorhandenen
  64-bit-Linux. Ohne Supervisor, also ohne Apps. Zusatzdienste wie MQTT oder
  Zigbee2MQTT laufen dann als eigene Container.

## 2. Was das für TI-Boards bedeutet

Für TI-basierte Boards gibt es **kein** offizielles Home-Assistant-OS-Image.
Der unterstützte Weg ist daher **Home Assistant Container** auf dem
64-bit-Debian, das BeagleBoard.org bzw. TI für die Boards bereitstellt.
Genau das richtet `scripts/install-ha-container.sh` ein.

### Übersicht verbreiteter TI-Boards

| Board | SoC / CPU | Arch | RAM | Onboard-Speicher | Eignung |
|---|---|---|---|---|---|
| BeagleBone Black / Green | AM3358, 1x Cortex-A8 1 GHz | 32-bit | 512 MB | 4 GB eMMC | **nein**: 32-bit, zu wenig RAM |
| BeagleBone AI | AM5729, 2x Cortex-A15 1,5 GHz | 32-bit | 1 GB | 16 GB eMMC | **nein**: 32-bit, zu wenig RAM |
| BeagleBone AI-64 | TDA4VM, 2x Cortex-A72 2 GHz | 64-bit | 4 GB | 16 GB eMMC + microSD | **ja**, mit microSD >= 32 GB |
| BeaglePlay | AM6254, 4x Cortex-A53 1,4 GHz | 64-bit | 2 GB | 16 GB eMMC + microSD | **ja (knapp)**, mit microSD >= 32 GB; hat CC1352P7 für Zigbee/Thread |
| BeagleY-AI | AM67A, 4x Cortex-A53 1,4 GHz | 64-bit | 4 GB | microSD | **ja**, mit microSD >= 32 GB |
| SK-AM62B (Starter Kit) | AM625, 4x Cortex-A53 | 64-bit | 2 GB | microSD | **ja (knapp)** |
| SK-AM64B (Starter Kit) | AM6442, 2x Cortex-A53 1 GHz | 64-bit | 2 GB | microSD | **grenzwertig**: Mindestwerte erfüllt, wenig CPU-Leistung |
| SK-TDA4VM | TDA4VM, 2x Cortex-A72 | 64-bit | 4 GB | microSD | **ja** |
| **EK-TM4C123GXL** (Tiva C LaunchPad) | TM4C123GH6PM, 1x Cortex-M4F 80 MHz | 32-bit MCU | 32 KB SRAM | 256 KB Flash | **nein**: Mikrocontroller, kein Linux möglich |
| Weitere LaunchPads (MSP430, MSP432, C2000, CC13xx/CC26xx) | Mikrocontroller | – | wenige KB | wenige KB–MB Flash | **nein**: kein Linux möglich |

Hinweis zu LaunchPads: Ein **CC2652R- oder CC1352P-LaunchPad** kann Home
Assistant nicht selbst ausführen, eignet sich aber mit Z-Stack-Coordinator-Firmware
sehr gut als **Zigbee-Coordinator** für ZHA oder Zigbee2MQTT auf einem anderen
Home-Assistant-Server.

Die Angaben oben sind die Nennwerte der Boards. Welches Board tatsächlich
angeschlossen ist, und ob es die Anforderungen erfüllt, ermittelt
`scripts/check-board.sh` direkt auf dem Board.

## 3. Ergebnis für das angeschlossene Board: EK-TM4C123GXL

Das angeschlossene Board ist das **Tiva C Series TM4C123G LaunchPad
(EK-TM4C123GXL)**. Es ist über die Debug-USB-Buchse angeschlossen
(Schalter `PWR SELECT` auf `DEBUG`). Auf dem PC meldet es sich als
*In-Circuit Debug Interface* (ICDI, USB-ID `1cbe:00fd`) mit einem virtuellen
COM-Port ([TI][ti-ek]).

| Kriterium | Anforderung | EK-TM4C123GXL | Erfüllt |
|---|---|---|---|
| CPU | 64-bit-Anwendungsprozessor (aarch64/x86_64) | ARM Cortex-M4F, 80 MHz, 32-bit-Mikrocontroller ohne MMU | nein |
| Arbeitsspeicher | mind. 2 GB | 32 KB SRAM (ca. 65.000-mal zu wenig) | nein |
| Speicher | mind. 32 GB | 256 KB Flash, 2 KB EEPROM | nein |
| Betriebssystem | Linux mit Docker oder Home Assistant OS | kein Linux möglich (nur Bare-Metal oder RTOS) | nein |
| Netzwerk | LAN oder WLAN | keines | nein |

**Ergebnis: Die Anforderungen werden nicht erfüllt.** Home Assistant lässt sich
auf diesem Board nicht installieren, auch nicht in abgespeckter Form.
`check-board.sh` kann dort ebenfalls nicht laufen, da es kein Betriebssystem
mit Shell gibt; der Abgleich beruht auf den Herstellerdaten.

Sinnvoll nutzbar bleibt das LaunchPad als **Sensor- oder Aktor-Knoten** an
einem Home-Assistant-Server: Eine eigene Firmware schickt Messwerte über den
virtuellen COM-Port (UART0) per USB an den Server, der sie z. B. mit der
Integration *Serial* einliest.

## 4. Empfehlung, falls das Board nicht geeignet ist

**Empfehlung: Home Assistant Green**, UVP **179 €** (199 USD) seit Januar 2026
([Nabu Casa][green-price]).

- 4x Cortex-A55 (Rockchip RK3566), 4 GB RAM, 32 GB eMMC, Gigabit-LAN, 2x USB
- Home Assistant OS vorinstalliert: volle Unterstützung inklusive Apps,
  Backups und automatischer Updates
- Kein Zubehör nötig: Netzteil und Gehäuse sind dabei
- Kein Funk eingebaut: für Zigbee/Thread einen USB-Coordinator ergänzen
  (z. B. ein vorhandenes CC2652/CC1352-LaunchPad, siehe oben)

Warum nicht ein Raspberry Pi 5? Die Preise für Raspberry Pi 4 und 5 sind seit
Oktober 2025 wegen der Speicherknappheit mehrfach gestiegen, am stärksten bei
den Modellen mit viel RAM ([Raspberry Pi][rpi-price], [Tom's Hardware][toms]).
Mit Netzteil, Gehäuse und Speicher liegt ein Pi 5 mit 4 oder 8 GB inzwischen
auf dem Preisniveau des Green oder darüber ([Notebookcheck][notebookcheck],
[itechguides][itechguides]), bei mehr Aufwand und ohne Herstellersupport für
die Kombination. Ein Pi lohnt sich nur, wenn er schon vorhanden ist.

Wenn eines der als geeignet markierten TI-Boards bereits vorhanden ist (z. B.
BeaglePlay oder BeagleY-AI), ist das die günstigste Lösung: Kosten nur für
eine microSD-Karte >= 32 GB.

[ti-ek]: https://www.ti.com/tool/EK-TM4C123GXL
[install]: https://www.home-assistant.io/installation/
[docker]: https://www.home-assistant.io/installation/docker/
[deprecation]: https://www.home-assistant.io/blog/2025/05/22/deprecating-core-and-supervised-installation-methods-and-32-bit-systems/
[arch]: https://www.home-assistant.io/more-info/unsupported/system_architecture/
[green-price]: https://www.nabucasa.com/news/2026-01-08-green-pricing-change/
[rpi-price]: https://raspberrypi.com/news/more-memory-driven-price-rises
[toms]: https://www.tomshardware.com/raspberry-pi/component-shortages-drive-raspberry-pi-prices-up-by-up-to-23-percent-escalating-lpddr4-lpddr5-costs-trigger-the-third-price-hike-of-the-year
[notebookcheck]: https://www.notebookcheck.net/Rising-costs-in-the-Smart-Home-The-impact-of-the-chip-and-RAM-shortage.1338441.0.html
[itechguides]: https://www.itechguides.com/how-much-does-it-cost-to-run-home-assistant-yourself-in-2026/
