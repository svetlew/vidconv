#!/bin/bash

# ==============================================================================
# vidconv - Screen recording converter for macOS
#
# Usage:  vidconv
#
# Dependencies (auto-installed via Homebrew): ffmpeg, gifsicle
# ==============================================================================

# Configuration
FPS=15
HEIGHT=720
SPEED_FACTOR="1/1.2"
MP4_CRF=28
GIF_MAX_COLORS=256
GIF_LOSSY=80
FILTERS="setpts=${SPEED_FACTOR}*PTS,fps=${FPS},scale=-2:${HEIGHT}:flags=lanczos"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

ensure_dep() {
    command -v "$1" &>/dev/null && return
    command -v brew &>/dev/null || { log_error "Homebrew is not installed. Visit https://brew.sh/"; exit 1; }
    log_warn "$1 not found. Installing via Homebrew..."
    brew install "$1" || { log_error "Failed to install $1."; exit 1; }
}

pick_input() {
    log_info "Opening Finder to select a video file..."
    osascript -e 'try' \
        -e 'POSIX path of (choose file with prompt "▶️  SELECT VIDEO FILE" of type {"mp4", "mov", "mkv", "avi"})' \
        -e 'end try'
}

pick_format() {
    local choice
    choice=$(osascript -e 'try' \
        -e 'set formatList to {"⭐ MP4 — Sharp, tiny, universal", "🎨 GIF — Animated, 256 colors", "🌐 WebM — Small, web-optimized", "🎬 MOV — QuickTime video"}' \
        -e 'set picked to choose from list formatList with prompt "📀  CHOOSE OUTPUT FORMAT" default items {"⭐ MP4 — Sharp, tiny, universal"} with title "Video Converter"' \
        -e 'if picked is false then return ""' \
        -e 'return first item of picked' \
        -e 'end try')
    [[ -z "$choice" ]] && return
    choice="${choice%% —*}"
    echo "${choice##* }"
}

pick_output() {
    local input="$1" format="$2"
    local ext
    case "$format" in
        MP4) ext="mp4" ;; GIF) ext="gif" ;; WebM) ext="webm" ;; MOV) ext="mov" ;; *) ext="mp4" ;;
    esac
    local stem="${input##*/}"; stem="${stem%.*}"

    log_info "Opening Finder to select save location..."
    local output
    output=$(osascript -e 'try' \
        -e 'POSIX path of (choose file name with prompt "💾  SAVE '"$format"' AS" default name "'"${stem}.${ext}"'")' \
        -e 'end try')
    [[ -z "$output" ]] && return
    [[ "${output##*.}" != "$ext" ]] && output="${output}.${ext}"
    echo "$output"
}

safe_output() {
    local input="$1" output="$2"
    if [[ "$(realpath "$input")" == "$(realpath "$output" 2>/dev/null)" ]]; then
        local tmp="${output}.vidconv_tmp.${output##*.}"
        echo "$tmp"
    else
        echo "$output"
    fi
}

convert_video() {
    local input="$1" output="$2" format="$3"
    local codec_opts
    case "$format" in
        MP4)  codec_opts="-c:v libx264 -crf ${MP4_CRF} -preset slow -movflags +faststart" ;;
        WebM) codec_opts="-c:v libvpx-vp9 -crf 30 -b:v 0 -deadline good" ;;
        MOV)  codec_opts="-c:v libx264 -crf ${MP4_CRF} -preset slow" ;;
    esac

    log_info "Converting to $format..."
    ffmpeg -v error -i "$input" -vf "$FILTERS" \
        $codec_opts -an -y "$output" || { log_error "$format conversion failed."; exit 1; }
}

convert_gif() {
    local input="$1" output="$2"
    local palette
    palette=$(mktemp /tmp/vidconv_palette_XXXXXX.png)

    log_info "Step 1/3: Generating color palette..."
    ffmpeg -v error -i "$input" -vf "$FILTERS,palettegen=max_colors=${GIF_MAX_COLORS}:stats_mode=diff" \
        -y "$palette" || { log_error "Palette generation failed."; rm -f "$palette"; exit 1; }

    log_info "Step 2/3: Converting to GIF..."
    ffmpeg -v error -i "$input" -i "$palette" \
        -lavfi "$FILTERS [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
        -y -loop 0 "$output" || { log_error "GIF conversion failed."; rm -f "$palette"; exit 1; }
    rm -f "$palette"

    log_info "Step 3/3: Optimizing with gifsicle..."
    gifsicle -O3 --lossy=${GIF_LOSSY} -o "$output" "$output" || log_warn "gifsicle optimization failed."
}

main() {
    ensure_dep ffmpeg
    ensure_dep gifsicle

    local input; input=$(pick_input)
    [[ -z "$input" ]] && { log_info "Canceled."; exit 0; }

    local format; format=$(pick_format)
    [[ -z "$format" ]] && { log_info "Canceled."; exit 0; }

    local output; output=$(pick_output "$input" "$format")
    [[ -z "$output" ]] && { log_info "Canceled."; exit 0; }

    local actual_output; actual_output=$(safe_output "$input" "$output")

    if [[ "$format" == "GIF" ]]; then
        convert_gif "$input" "$actual_output"
    else
        convert_video "$input" "$actual_output" "$format"
    fi

    if [[ "$actual_output" != "$output" ]]; then
        mv -f "$actual_output" "$output"
    fi

    log_info "Done! $output"
    open -R "$output"
}

main
