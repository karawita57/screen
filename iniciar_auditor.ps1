# ==============================================================================
# AUDITOR DE PRIVACIDAD - NICE SCREEN AGENT
# ==============================================================================
# Este script monitorea en tiempo real las llamadas grabadas por ScreenAgent en tu PC
# personal. Captura la clave de cifrado al vuelo, preserva los archivos antes de que
# sean eliminados del disco y genera una copia desencriptada lista para reproducir.
# ==============================================================================

[CmdletBinding()]
param(
    [string]$OutputDir = "",
    [string]$FFmpegPath = "C:\Program Files\NICE-InContact\ScreenAgent\ffmpeg.exe"
)

# Configurar codificacion de consola
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Auditor de Privacidad - ScreenAgent"

# Si OutputDir no fue especificado, usar la carpeta 'auditoria' en el directorio del script
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $PSScriptRoot "auditoria"
}

# Validar existencia de FFmpeg
if (-not (Test-Path $FFmpegPath)) {
    $fallbackFfmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($fallbackFfmpeg) {
        $FFmpegPath = $fallbackFfmpeg.Source
    } else {
        Write-Host "`n[ERROR] No se encontro el motor FFmpeg en: $FFmpegPath" -ForegroundColor Red
        Write-Host "NICE ScreenAgent instala FFmpeg en esa ruta por defecto. Verifica la instalacion." -ForegroundColor Red
        return
    }
}

# Advertir si el proyecto no esta en el disco C: (HardLinks de NTFS no cruzan discos)
$resolvedPath = if (Test-Path $OutputDir) { (Resolve-Path $OutputDir).Path } else { $OutputDir }
$outputDrive = [System.IO.Path]::GetPathRoot($resolvedPath)
if ($outputDrive -notmatch "^[Cc]:") {
    Write-Host "`n[ADVERTENCIA] El repositorio esta en la unidad $outputDrive." -ForegroundColor Yellow
    Write-Host "ScreenAgent guarda sus grabaciones temporales en el disco C: (AppData)." -ForegroundColor Yellow
    Write-Host "Los enlaces duros (HardLinks) de Windows no funcionan entre diferentes discos." -ForegroundColor Yellow
    Write-Host "Por favor, clona y ejecuta este repositorio exclusivamente en el disco C:\`n" -ForegroundColor Yellow
}

# Asegurar directorios
$tempDir = Join-Path $OutputDir "temp"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "           AUDITOR DE PRIVACIDAD - NICE SCREEN AGENT             " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Directorio de auditoria : $OutputDir" -ForegroundColor Yellow
Write-Host "Motor FFmpeg local      : $FFmpegPath" -ForegroundColor Yellow
Write-Host "Estado                  : ESCUCHANDO (Esperando inicio de llamada...)" -ForegroundColor Green
Write-Host "Presiona Ctrl + C para detener el auditor en cualquier momento." -ForegroundColor Gray
Write-Host "=================================================================`n" -ForegroundColor Cyan

# Tabla para rastrear sesiones activas
# Key: ProcessId, Value: Hashtable con metadatos
$activeSessions = @{}

function Log-Message([string]$msg, [string]$color = "White") {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $msg" -ForegroundColor $color
}

function Create-HardLink([string]$linkPath, [string]$targetPath) {
    if (Test-Path $linkPath) { return $true }
    try {
        New-Item -ItemType HardLink -Path $linkPath -Target $targetPath -Force -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

try {
    while ($true) {
        # 1. Buscar instancias activas de ffmpeg.exe
        $ffmpegProcesses = Get-CimInstance Win32_Process -Filter "Name = 'ffmpeg.exe'" -ErrorAction SilentlyContinue

        foreach ($proc in $ffmpegProcesses) {
            $pid = $proc.ProcessId
            $cmd = $proc.CommandLine

            if (-not $cmd) { continue }

            # Verificar si es una instancia lanzada por ScreenAgent (gdigrab + cenc-aes-ctr)
            if ($cmd -match "gdigrab" -and $cmd -match "encryption_key=([a-fA-F0-9]+)") {
                if (-not $activeSessions.ContainsKey($pid)) {
                    $encKey = $Matches[1]
                    
                    # Extraer KID si esta presente
                    $encKid = ""
                    if ($cmd -match "encryption_kid=([a-fA-F0-9]+)") {
                        $encKid = $Matches[1]
                    }

                    # Extraer carpeta de destino de la grabacion (soporta rutas con espacios y comillas)
                    $targetFolder = ""
                    if ($cmd -match '([A-Za-z]:\\[^"\r\n]+?\\recordings\\[a-fA-F0-9-]+)') {
                        $targetFolder = $Matches[1].Trim()
                    }

                    $sessionTime = Get-Date
                    $sessionTimestamp = $sessionTime.ToString("yyyy-MM-dd_HH-mm-ss")

                    $activeSessions[$pid] = @{
                        PID           = $pid
                        Key           = $encKey
                        Kid           = $encKid
                        TargetFolder  = $targetFolder
                        Timestamp     = $sessionTimestamp
                        StartTime     = $sessionTime
                        LinkedFiles   = [System.Collections.Generic.List[string]]::new()
                    }

                    Log-Message "-> NUEVA LLAMADA DETECTADA (PID: $pid)" "Cyan"
                    Log-Message "   Clave de cifrado capturada: $encKey" "Yellow"
                    if ($targetFolder) {
                        Log-Message "   Carpeta temporal: $targetFolder" "Gray"
                    }
                }
            }
        }

        # 2. Para cada sesion activa, escanear y crear Hard Links de los segmentos .mp4 generados
        foreach ($pid in @($activeSessions.Keys)) {
            $session = $activeSessions[$pid]
            $folder = $session.TargetFolder

            if ($folder -and (Test-Path $folder)) {
                $mp4Files = Get-ChildItem -Path $folder -Filter "*.mp4" -ErrorAction SilentlyContinue
                foreach ($file in $mp4Files) {
                    $fileName = $file.Name
                    $hardLinkName = "$($session.Timestamp)_$fileName"
                    $hardLinkPath = Join-Path $tempDir $hardLinkName

                    if (-not $session.LinkedFiles.Contains($hardLinkPath)) {
                        if (Create-HardLink $hardLinkPath $file.FullName) {
                            $session.LinkedFiles.Add($hardLinkPath)
                            Log-Message "   [LINK] Segmento vinculado instantaneamente: $fileName" "DarkYellow"
                        }
                    }
                }
            }

            # 3. Comprobar si el proceso ffmpeg.exe correspondiente a la sesion ya finalizo (Llamada colgada)
            $isAlive = $ffmpegProcesses | Where-Object { $_.ProcessId -eq $pid }
            if (-not $isAlive) {
                Log-Message "<- LLAMADA FINALIZADA (PID: $pid)" "Cyan"
                Log-Message "   Iniciando desencriptacion y consolidacion del video..." "Green"

                # Dar un breve respiro para que el sistema termine de cerrar descriptores
                Start-Sleep -Milliseconds 800

                # Obtener la lista de segmentos vinculados
                $linkedSegments = @($session.LinkedFiles) | Where-Object { Test-Path $_ } | Sort-Object

                if ($linkedSegments.Count -eq 0) {
                    Log-Message "   [AVISO] No se encontraron segmentos para desencriptar en esta llamada." "Magenta"
                } else {
                    $decryptedSegments = [System.Collections.Generic.List[string]]::new()
                    $key = $session.Key

                    # Desencriptar cada segmento
                    for ($i = 0; $i -lt $linkedSegments.Count; $i++) {
                        $encPath = $linkedSegments[$i]
                        $decPath = [System.IO.Path]::ChangeExtension($encPath, ".dec.mp4")

                        # Ejecutar ffmpeg para desencriptar sin perdida de calidad (-c copy)
                        $procArgs = "-y -decryption_key $key -i `"$encPath`" -c copy `"$decPath`""
                        $p = Start-Process -FilePath $FFmpegPath -ArgumentList $procArgs -NoNewWindow -PassThru -Wait

                        if ($p.ExitCode -eq 0 -and (Test-Path $decPath)) {
                            $decryptedSegments.Add($decPath)
                            # Eliminar enlace temporal cifrado
                            Remove-Item $encPath -Force -ErrorAction SilentlyContinue
                        } else {
                            Log-Message "   [ERROR] Fallo al desencriptar el segmento: $encPath" "Red"
                        }
                    }

                    # Consolidar segmentos si hay mas de uno, o mover el archivo final
                    $finalVideoName = "Llamada_$($session.Timestamp).mp4"
                    $finalVideoPath = Join-Path $OutputDir $finalVideoName

                    if ($decryptedSegments.Count -eq 1) {
                        Move-Item -Path $decryptedSegments[0] -Destination $finalVideoPath -Force
                        $sizeKB = [math]::Round((Get-Item $finalVideoPath).Length / 1KB, 1)
                        Log-Message "   [EXITO] Video guardado: $finalVideoName ($sizeKB KB)" "Green"
                        Log-Message "   Ubicacion: $finalVideoPath`n" "White"
                    } elseif ($decryptedSegments.Count -gt 1) {
                        # Crear lista para FFmpeg concat demuxer
                        $concatListFile = Join-Path $tempDir "concat_$($session.Timestamp).txt"
                        $lines = $decryptedSegments | ForEach-Object { "file '$_'" }
                        Set-Content -Path $concatListFile -Value $lines -Encoding ASCII

                        $concatArgs = "-y -f concat -safe 0 -i `"$concatListFile`" -c copy `"$finalVideoPath`""
                        $pConcat = Start-Process -FilePath $FFmpegPath -ArgumentList $concatArgs -NoNewWindow -PassThru -Wait

                        if ($pConcat.ExitCode -eq 0 -and (Test-Path $finalVideoPath)) {
                            $sizeKB = [math]::Round((Get-Item $finalVideoPath).Length / 1KB, 1)
                            Log-Message "   [EXITO] Video unificado guardado: $finalVideoName ($sizeKB KB, $($decryptedSegments.Count) partes)" "Green"
                            Log-Message "   Ubicacion: $finalVideoPath`n" "White"
                        } else {
                            Log-Message "   [ERROR] No se pudo unir los segmentos. Se conservan partes individuales." "Red"
                        }

                        # Limpiar archivos temporales
                        Remove-Item $concatListFile -Force -ErrorAction SilentlyContinue
                        $decryptedSegments | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
                    }
                }

                # Remover sesion activa
                $activeSessions.Remove($pid)
                Log-Message "Estado: ESCUCHANDO (Esperando siguiente llamada...)" "Green"
            }
        }

        # Pequena pausa para no consumir CPU (1 segundo)
        Start-Sleep -Seconds 1
    }
} finally {
    Log-Message "Auditor detenido por el usuario." "Yellow"
}
