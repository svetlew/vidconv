# vidconv

Convert screen recordings to optimized **MP4**, **GIF**, **WebM**, or **MOV** with a single command. All dependencies are installed automatically.

## Install

**macOS**

```bash
git clone https://github.com/svetlew/vidconv.git /tmp/vidconv && sudo mv /tmp/vidconv/vidconv.sh /usr/local/bin/vidconv && rm -rf /tmp/vidconv
```

**Windows**

```powershell
git clone https://github.com/svetlew/vidconv.git $env:TEMP\vidconv 2>$null; $sd = if (Test-Path $HOME\Scripts) { (Get-Item $HOME\Scripts).FullName } else { (New-Item -ItemType Directory -Path $HOME\Scripts).FullName }; Copy-Item $env:TEMP\vidconv\vidconv.ps1 "$sd\vidconv.ps1"; Remove-Item $env:TEMP\vidconv -Recurse -Force; if (!(Select-String -Path $PROFILE -Pattern 'vidconv' -Quiet -ErrorAction SilentlyContinue)) { Add-Content $PROFILE "Set-Alias vidconv `"$sd\vidconv.ps1`"" }; . $PROFILE
```

## Usage

```
vidconv
```

The script will:

1. **Auto-install dependencies** — `ffmpeg` and `gifsicle` via Homebrew (macOS) or winget/Chocolatey (Windows)
2. Open a **native file picker** to select your video
3. Ask you to **choose a format** (MP4, GIF, WebM, MOV)
4. Open a **save dialog** for the output location
5. Convert and **reveal the file** in Finder / Explorer when done

## Output Formats

| Format | Best For | Notes |
|--------|----------|-------|
| ⭐ **MP4** | Jira, GitHub, Slack | Sharp, tiny files. Recommended. |
| 🎨 **GIF** | When `.gif` is required | 256 colors, larger files. Two-pass palette + gifsicle optimization. |
| 🌐 **WebM** | Web embedding | VP9 codec, very small files. |
| 🎬 **MOV** | Apple ecosystem | QuickTime-compatible H.264. |

## Configuration

Edit the top of `vidconv.sh` (macOS) or `vidconv.ps1` (Windows) to tweak defaults:

| Setting | Default | Description |
|---------|---------|-------------|
| `FPS` | 15 | Frame rate |
| `HEIGHT` | 720 | Output height in pixels |
| `SPEED_FACTOR` | 1/1.2 | Playback speed (1.2× faster) |
| `MP4_CRF` | 28 | MP4 quality (18 = lossless, 28 = good, 35 = low) |
| `GIF_MAX_COLORS` | 256 | GIF palette size |
| `GIF_LOSSY` | 80 | gifsicle compression (0 = lossless, 200 = aggressive) |

## Requirements

| | macOS | Windows |
|---|---|---|
| **OS** | macOS 10.15+ | Windows 10/11 |
| **Shell** | bash / zsh | PowerShell 5.1+ |
| **Package manager** | [Homebrew](https://brew.sh/) | [winget](https://aka.ms/getwinget) |
| **Dependencies** | ffmpeg, gifsicle (auto-installed) | ffmpeg (auto-installed), gifsicle via [Chocolatey](https://chocolatey.org/install) (prompted on first run) |
