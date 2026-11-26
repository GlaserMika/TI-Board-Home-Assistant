# find-board.ps1
#
# Prueft unter Windows, ob ein TI-Board per USB angeschlossen ist, ob der
# Treiber geladen ist und unter welchem COM-Port die virtuelle serielle
# Schnittstelle liegt.
#
# Aufruf in PowerShell im Repository-Ordner:
#   powershell -ExecutionPolicy Bypass -File scripts\find-board.ps1

$known = @(
    @{ Id = 'VID_1CBE&PID_00FD'; Mcu = $true;  Name = 'Stellaris/Tiva In-Circuit Debug Interface (ICDI), z. B. EK-TM4C123GXL' },
    @{ Id = 'VID_0451&PID_BEF3'; Mcu = $true;  Name = 'TI XDS110 Debug Probe (LaunchPads, z. B. CC2652R, CC1352P)' },
    @{ Id = 'VID_2047';          Mcu = $true;  Name = 'TI MSP430-Debugger (eZ-FET / MSP-FET)' },
    @{ Id = 'VID_1D6B&PID_0104'; Mcu = $false; Name = 'BeagleBoard USB-Gadget (Netzwerk + seriell)' },
    @{ Id = 'VID_0451';          Mcu = $false; Name = 'Texas Instruments USB-Geraet' }
)

Write-Host "`n== USB-Geraete =="
$devices = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like 'USB\*' }

$hits = @()
foreach ($dev in $devices) {
    foreach ($k in $known) {
        if ($dev.InstanceId -like "*$($k.Id)*") {
            $hits += [pscustomobject]@{
                Board  = $k.Name
                Mcu    = $k.Mcu
                Geraet = $dev.FriendlyName
                Klasse = $dev.Class
                Status = $dev.Status
                Id     = $dev.InstanceId
            }
            break
        }
    }
}

if ($hits.Count -eq 0) {
    Write-Host "  Kein TI-Board gefunden."
    Write-Host "  - Datenkabel (nicht nur Ladekabel) am Debug-USB-Anschluss?"
    Write-Host "  - Beim EK-TM4C123GXL: Schalter 'PWR SELECT' auf DEBUG, Kabel an der Buchse 'DEBUG'?"
    exit 1
}

$hits | Format-Table Board, Geraet, Klasse, Status -AutoSize | Out-String | Write-Host

$broken = $hits | Where-Object { $_.Status -ne 'OK' }
if ($broken) {
    Write-Host "  [WARN] Mindestens eine Schnittstelle hat keinen funktionierenden Treiber (Status ungleich OK)."
    Write-Host "         Fuer das EK-TM4C123GXL die 'Stellaris ICDI Drivers' von ti.com installieren"
    Write-Host "         (enthalten in Code Composer Studio bzw. als Einzeldownload)."
}

Write-Host "`n== Serielle Schnittstellen (COM-Ports) =="
$ports = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like '*VID_1CBE*' -or $_.InstanceId -like '*VID_0451*' -or $_.InstanceId -like '*VID_2047*' -or $_.InstanceId -like '*VID_1D6B*' }
if ($ports) {
    $ports | ForEach-Object { Write-Host "  $($_.FriendlyName)  [$($_.Status)]" }
} else {
    Write-Host "  Kein COM-Port eines TI-Boards gefunden"
}

Write-Host "`n== Ergebnis =="
if ($hits | Where-Object { $_.Mcu }) {
    Write-Host "  Verbindung OK: Mikrocontroller-LaunchPad ueber die Debug-Schnittstelle erkannt."
    Write-Host "  Auf einem Mikrocontroller laeuft kein Linux, also auch kein Home Assistant."
    Write-Host "  Abgleich und Alternativen: docs\anforderungen.md"
} else {
    Write-Host "  Linux-faehiges Board erkannt. Spezifikationen pruefen:"
    Write-Host "    scp scripts/check-board.sh debian@192.168.7.2:"
    Write-Host "    ssh debian@192.168.7.2 bash check-board.sh"
}
