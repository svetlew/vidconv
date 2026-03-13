<#
.SYNOPSIS
    vidconv - Screen recording converter for Windows

.DESCRIPTION
    Converts video files to optimized MP4, GIF, WebM, or MOV using native
    Windows GUI dialogs and ffmpeg. Dependencies are auto-installed via winget.

.NOTES
    Usage:  .\vidconv.ps1
    Requires: PowerShell 5.1+, Windows 10/11
    Dependencies: ffmpeg (auto-installed via winget), gifsicle (auto-installed via Chocolatey)
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load WinForms and enable DPI awareness for sharp dialogs on high-DPI displays
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
if (-not ([System.Management.Automation.PSTypeName]'DPI').Type) {
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class DPI {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
}
[DPI]::SetProcessDPIAware() | Out-Null

# ── Configuration ──────────────────────────────────────────────────────────────
$script:FPS           = 15
$script:HEIGHT        = 720
$script:SPEED_FACTOR  = "1/1.2"
$script:MP4_CRF       = 28
$script:GIF_MAX_COLORS = 256
$script:GIF_LOSSY     = 80
$script:FILTERS       = "setpts=$($script:SPEED_FACTOR)*PTS,fps=$($script:FPS),scale=-2:$($script:HEIGHT):flags=lanczos"

# ── Logging ────────────────────────────────────────────────────────────────────
function Write-InfoLog  { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-WarnLog  { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrorLog { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

# ── Dependencies ───────────────────────────────────────────────────────────────
function Install-Dependency {
    param([string]$Command, [string]$WingetId)

    if (Get-Command $Command -ErrorAction SilentlyContinue) { return $true }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-ErrorLog "winget is not available. Install 'App Installer' from the Microsoft Store."
        return $false
    }

    Write-WarnLog "$Command not found. Installing via winget..."
    $result = winget install --id $WingetId --accept-source-agreements --accept-package-agreements -e 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog "Failed to install $Command. Please install it manually."
        Write-ErrorLog $result
        return $false
    }

    # Refresh PATH so the newly installed command is found
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Write-ErrorLog "$Command installed but not found in PATH. Restart your terminal and try again."
        return $false
    }
    return $true
}

# ── GUI: Pick input file ──────────────────────────────────────────────────────
function Select-InputFile {
    Write-InfoLog "Opening file picker..."
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "SELECT VIDEO FILE"
    $dialog.Filter = "Video files (*.mp4;*.mov;*.mkv;*.avi)|*.mp4;*.mov;*.mkv;*.avi|All files (*.*)|*.*"
    $dialog.RestoreDirectory = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

# ── GUI: Pick output format ───────────────────────────────────────────────────
function Select-OutputFormat {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Video Converter"
    $form.Size = New-Object System.Drawing.Size(360, 260)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "CHOOSE OUTPUT FORMAT"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $label.Location = New-Object System.Drawing.Point(20, 15)
    $label.AutoSize = $true
    $form.Controls.Add($label)

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(20, 50)
    $listBox.Size = New-Object System.Drawing.Size(305, 110)
    $listBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $listBox.Items.AddRange(@(
        "MP4  -  Sharp, tiny, universal",
        "GIF  -  Animated, 256 colors",
        "WebM -  Small, web-optimized",
        "MOV  -  QuickTime video"
    ))
    $listBox.SelectedIndex = 0
    $form.Controls.Add($listBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Location = New-Object System.Drawing.Point(160, 175)
    $okButton.Size = New-Object System.Drawing.Size(75, 30)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    $form.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point(245, 175)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 30)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $listBox.SelectedItem) {
        return ($listBox.SelectedItem.ToString().Trim() -split "\s+-\s+")[0].Trim()
    }
    return $null
}

# ── GUI: Pick output file ─────────────────────────────────────────────────────
function Select-OutputFile {
    param([string]$InputPath, [string]$Format)

    $extMap = @{ "MP4" = "mp4"; "GIF" = "gif"; "WebM" = "webm"; "MOV" = "mov" }
    $ext = if ($extMap.ContainsKey($Format)) { $extMap[$Format] } else { "mp4" }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)

    Write-InfoLog "Opening save dialog..."
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = "SAVE $Format AS"
    $dialog.FileName = "$stem.$ext"
    $dialog.Filter = "$Format files (*.$ext)|*.$ext|All files (*.*)|*.*"
    $dialog.DefaultExt = $ext
    $dialog.RestoreDirectory = $true
    $dialog.OverwritePrompt = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $output = $dialog.FileName
        if (-not $output.EndsWith(".$ext")) { $output = "$output.$ext" }
        return $output
    }
    return $null
}

# ── Safe output (in-place conversion support) ─────────────────────────────────
function Get-SafeOutputPath {
    param([string]$InputPath, [string]$OutputPath)

    $realInput = (Resolve-Path $InputPath -ErrorAction SilentlyContinue).Path
    $realOutput = $OutputPath
    if (Test-Path $OutputPath) {
        $realOutput = (Resolve-Path $OutputPath -ErrorAction SilentlyContinue).Path
    }
    if ($realInput -and $realOutput -and ($realInput -eq $realOutput)) {
        $ext = [System.IO.Path]::GetExtension($OutputPath)
        return "${OutputPath}.vidconv_tmp${ext}"
    }
    return $OutputPath
}

# ── Invoke ffmpeg with error handling ─────────────────────────────────────────
function Invoke-FFmpeg {
    param([string]$Arguments, [string]$ErrorMessage)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "ffmpeg"
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        Write-ErrorLog $ErrorMessage
        if ($stderr) { Write-ErrorLog $stderr }
        return $false
    }
    return $true
}

# ── Converters ─────────────────────────────────────────────────────────────────
function ConvertTo-Video {
    param([string]$InputPath, [string]$OutputPath, [string]$Format)

    $codecOpts = switch ($Format) {
        "MP4"  { "-c:v libx264 -crf $($script:MP4_CRF) -preset slow -movflags +faststart" }
        "WebM" { "-c:v libvpx-vp9 -crf 30 -b:v 0 -deadline good" }
        "MOV"  { "-c:v libx264 -crf $($script:MP4_CRF) -preset slow" }
    }

    Write-InfoLog "Converting to $Format..."
    $ffmpegArgs = "-v error -i `"$InputPath`" -vf `"$($script:FILTERS)`" $codecOpts -an -y `"$OutputPath`""
    $ok = Invoke-FFmpeg -Arguments $ffmpegArgs -ErrorMessage "$Format conversion failed."
    if (-not $ok) { exit 1 }
}

function ConvertTo-Gif {
    param([string]$InputPath, [string]$OutputPath)

    $palette = Join-Path $env:TEMP "vidconv_palette_$([guid]::NewGuid().ToString('N').Substring(0,8)).png"

    try {
        Write-InfoLog "Step 1/3: Generating color palette..."
        $a1 = "-v error -i `"$InputPath`" -vf `"$($script:FILTERS),palettegen=max_colors=$($script:GIF_MAX_COLORS):stats_mode=diff`" -y `"$palette`""
        if (-not (Invoke-FFmpeg -Arguments $a1 -ErrorMessage "Palette generation failed.")) { exit 1 }

        Write-InfoLog "Step 2/3: Converting to GIF..."
        $a2 = "-v error -i `"$InputPath`" -i `"$palette`" -lavfi `"$($script:FILTERS) [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle`" -y -loop 0 `"$OutputPath`""
        if (-not (Invoke-FFmpeg -Arguments $a2 -ErrorMessage "GIF conversion failed.")) { exit 1 }
    } finally {
        Remove-Item $palette -ErrorAction SilentlyContinue
    }

    Write-InfoLog "Step 3/3: Optimizing with gifsicle..."
    if (Get-Command gifsicle -ErrorAction SilentlyContinue) {
        $lossy = $script:GIF_LOSSY
        $proc = Start-Process -FilePath "gifsicle" -ArgumentList "-O3 --lossy=$lossy -o `"$OutputPath`" `"$OutputPath`"" -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-WarnLog "gifsicle optimization failed (non-critical)." }
    } else {
        Write-WarnLog "gifsicle not found -- skipping GIF optimization. Install it for smaller files."
    }
}

# ── Main ───────────────────────────────────────────────────────────────────────
function Start-VidConv {
    if (-not (Install-Dependency -Command "ffmpeg" -WingetId "Gyan.FFmpeg")) { exit 1 }
    if (-not (Get-Command gifsicle -ErrorAction SilentlyContinue)) {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-WarnLog "gifsicle not found. Installing via Chocolatey..."
            choco install gifsicle -y 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path", "User")
        } else {
            Write-WarnLog "gifsicle not found. GIF files will not be size-optimized without it."
            $answer = Read-Host "Install Chocolatey + gifsicle now? Requires admin privileges (Y/N)"
            if ($answer -match "^[Yy]") {
                Write-InfoLog "Requesting admin privileges..."
                $installScript = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
choco install gifsicle -y
'@
                $tempScript = Join-Path $env:TEMP "vidconv_choco_install.ps1"
                $installScript | Out-File -FilePath $tempScript -Encoding UTF8
                try {
                    $proc = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$tempScript`"" -Verb RunAs -Wait -PassThru
                    Remove-Item $tempScript -ErrorAction SilentlyContinue
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                                [System.Environment]::GetEnvironmentVariable("Path", "User")
                    if ($proc.ExitCode -eq 0 -and (Get-Command gifsicle -ErrorAction SilentlyContinue)) {
                        Write-InfoLog "Chocolatey and gifsicle installed successfully."
                    } else {
                        Write-WarnLog "Installation may require a terminal restart to take effect."
                    }
                } catch {
                    Remove-Item $tempScript -ErrorAction SilentlyContinue
                    Write-WarnLog "Admin privileges were declined. Continuing without gifsicle."
                }
            } else {
                Write-WarnLog "Skipping. GIF files will not be size-optimized."
            }
        }
    }

    $inputFile = Select-InputFile
    if (-not $inputFile) { Write-InfoLog "Canceled."; exit 0 }
    if (-not (Test-Path $inputFile)) { Write-ErrorLog "File not found: $inputFile"; exit 1 }

    $format = Select-OutputFormat
    if (-not $format) { Write-InfoLog "Canceled."; exit 0 }

    $outputFile = Select-OutputFile -InputPath $inputFile -Format $format
    if (-not $outputFile) { Write-InfoLog "Canceled."; exit 0 }

    $actualOutput = Get-SafeOutputPath -InputPath $inputFile -OutputPath $outputFile
    $inputSize = (Get-Item $inputFile).Length
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    if ($format -eq "GIF") {
        ConvertTo-Gif -InputPath $inputFile -OutputPath $actualOutput
    } else {
        ConvertTo-Video -InputPath $inputFile -OutputPath $actualOutput -Format $format
    }

    $stopwatch.Stop()

    if ($actualOutput -ne $outputFile) {
        Move-Item -Force -Path $actualOutput -Destination $outputFile
    }

    $outputSize = (Get-Item $outputFile).Length
    $ratio = [math]::Round(($outputSize / $inputSize) * 100, 1)
    $saved = [math]::Round(($inputSize - $outputSize) / 1MB, 1)
    $elapsed = $stopwatch.Elapsed.ToString('mm\:ss')
    Write-InfoLog "Done in $elapsed! $(Format-FileSize $inputSize) -> $(Format-FileSize $outputSize) ($ratio% of original, ${saved}MB saved)"
    Start-Process explorer.exe -ArgumentList "/select,`"$outputFile`""
}

Start-VidConv
