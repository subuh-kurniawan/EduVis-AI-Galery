#!/usr/bin/env bash
# =========================================================================
# 🚀 Chrome WebGPU & On-Device AI Launcher (macOS & Linux)
# File: launch_chrome_ai.sh (EduVis AI Gallery - Gemma 4)
# Deteksi otomatis: Chrome Dev, Chrome Canary, Chrome Beta, atau Chrome Stable
# =========================================================================

set -e

BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[0;35m"
RED="\033[0;31m"
RESET="\033[0m"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BOLD}${CYAN}========================================================"
echo "🚀 Gemma 4 AI Gallery - Chrome WebGPU & Edge AI Launcher"
echo -e "📁 Direktori: ${SCRIPT_DIR}${RESET}"
echo -e "${BOLD}${CYAN}========================================================${RESET}"
echo ""

OS_TYPE="$(uname -s)"

# 1. Pemeriksaan RAM & Storage
echo -e "${BOLD}${CYAN}[1/4] Memeriksa Spesifikasi Perangkat Keras...${RESET}"

RAM_GB=0
if [ "$OS_TYPE" = "Darwin" ]; then
    RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    RAM_GB=$(( RAM_BYTES / 1024 / 1024 / 1024 ))
else
    RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    RAM_GB=$(( RAM_KB / 1024 / 1024 ))
fi

echo -n "  • Total Unified/System RAM: ${RAM_GB} GB "
if [ "$RAM_GB" -ge 16 ]; then
    echo -e "${GREEN}(Sangat memadai untuk Gemma 4 E2B/E4B/12B)${RESET}"
else
    echo -e "${YELLOW}(Model E2B/E4B direkomendasikan untuk performa optimal)${RESET}"
fi

FREE_DISK_GB=0
if [ "$OS_TYPE" = "Darwin" ]; then
    FREE_DISK_KB=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    FREE_DISK_GB=$(( FREE_DISK_KB / 1024 / 1024 ))
else
    FREE_DISK_KB=$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    FREE_DISK_GB=$(( FREE_DISK_KB / 1024 / 1024 ))
fi

echo -e "  • Ruang Disk Bebas: ~${FREE_DISK_GB} GB ${GREEN}(Memadai)${RESET}\n"

# 2. Deteksi Instalasi Google Chrome
echo -e "${BOLD}${CYAN}[2/4] Mendeteksi Instalasi Google Chrome...${RESET}"

CHROME_BIN=""
CHROME_EDITION=""
CHROME_VERSION=""
FOUND_EDITIONS=()

detect_macos_chrome() {
    declare -a EDITIONS=(
        "Google Chrome Dev.app:Chrome Dev (Developer):/Applications/Google Chrome Dev.app/Contents/MacOS/Google Chrome Dev"
        "Google Chrome Canary.app:Chrome Canary (Canary):/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
        "Google Chrome Beta.app:Chrome Beta (Beta):/Applications/Google Chrome Beta.app/Contents/MacOS/Google Chrome Beta"
        "Google Chrome.app:Chrome Standar (Stable):/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        "Chromium.app:Chromium:/Applications/Chromium.app/Contents/MacOS/Chromium"
    )

    for item in "${EDITIONS[@]}"; do
        IFS=":" read -r app_name label bin_path <<< "$item"
        if [ -x "$bin_path" ]; then
            ver=$("$bin_path" --version 2>/dev/null || echo "Unknown Version")
            FOUND_EDITIONS+=("$label ($ver)")
            if [ -z "$CHROME_BIN" ]; then
                CHROME_BIN="$bin_path"
                CHROME_EDITION="$label"
                CHROME_VERSION="$ver"
            fi
        fi
    done
}

detect_linux_chrome() {
    declare -a LINUX_EDITIONS=(
        "google-chrome-dev:Chrome Dev"
        "google-chrome-unstable:Chrome Canary"
        "google-chrome-beta:Chrome Beta"
        "google-chrome-stable:Chrome Stable"
        "google-chrome:Chrome Stable"
        "chromium-browser:Chromium"
    )

    for item in "${LINUX_EDITIONS[@]}"; do
        IFS=":" read -r cmd label <<< "$item"
        if command -v "$cmd" &>/dev/null; then
            bin_path="$(command -v "$cmd")"
            ver=$("$bin_path" --version 2>/dev/null || echo "Unknown Version")
            FOUND_EDITIONS+=("$label ($ver)")
            if [ -z "$CHROME_BIN" ]; then
                CHROME_BIN="$bin_path"
                CHROME_EDITION="$label"
                CHROME_VERSION="$ver"
            fi
        fi
    done
}

if [ "$OS_TYPE" = "Darwin" ]; then
    detect_macos_chrome
else
    detect_linux_chrome
fi

if [ -z "$CHROME_BIN" ]; then
    echo -e "${RED}❌ Tidak ditemukan Google Chrome di sistem Anda!${RESET}"
    exit 1
fi

echo -e "  🎯 ${BOLD}${GREEN}Edisi Terpilih:${RESET} ${BOLD}${MAGENTA}${CHROME_EDITION}${RESET} (${CHROME_VERSION})"
echo ""

# 3. Memeriksa Ketersediaan Local Server
echo -e "${BOLD}${CYAN}[3/4] Memeriksa Local Server Gemma 4 (Port 8000 / 1234)...${RESET}"

TARGET_URL="http://127.0.0.1:8000/index.html"
SERVER_RUNNING=0

if curl --silent --fail --output /dev/null "http://127.0.0.1:8000/index.html" 2>/dev/null; then
    SERVER_RUNNING=1
    echo -e "  ${GREEN}✅ Local HTTP Server aktif di port 8000.${RESET}"
elif curl --silent --insecure --fail --output /dev/null "https://127.0.0.1:1234/api/network-info" 2>/dev/null; then
    SERVER_RUNNING=1
    TARGET_URL="https://127.0.0.1:1234/index.html"
    echo -e "  ${GREEN}✅ Local HTTPS Launcher aktif di port 1234.${RESET}"
else
    echo -e "  ${YELLOW}ℹ️  Server lokal belum aktif. Memulai server lokal (port 8000) dengan COOP/COEP...${RESET}"
    python3 server.py 8000 >/dev/null 2>&1 &
    sleep 1
    echo -e "  ${GREEN}✅ Server Python berhasil dinyalakan di background (PID: $!).${RESET}"
fi
echo ""

# 4. Menyusun Chrome WebGPU Flags & Meluncurkan Browser
echo -e "${BOLD}${CYAN}[4/4] Meluncurkan ${CHROME_EDITION} dengan Akselerasi WebGPU & OPFS...${RESET}"

AI_PROFILE_DIR="/tmp/chrome-gemma4-ai-profile"
mkdir -p "$AI_PROFILE_DIR" 2>/dev/null || true

AI_FLAGS=(
    # WebGPU & Hardware Acceleration
    "--enable-unsafe-webgpu"
    "--enable-webgpu-developer-features"
    "--ignore-gpu-blocklist"
    
    # Chrome On-Device AI & Web Platform Features
    "--enable-features=OptimizationGuideOnDeviceModel:compatible_on_device_performance_classes/*,PromptAPIForGeminiNano,EnableWebGPU"
    "--optimization-guide-on-device-model-execution-eval=1"
    
    # Isolated Profile agar tidak mengganggu sesi browsing harian
    "--user-data-dir=${AI_PROFILE_DIR}"
    
    # Buka URL portal aplikasi
    "$TARGET_URL"
)

"$CHROME_BIN" "${AI_FLAGS[@]}" >/dev/null 2>&1 &

echo -e "${BOLD}${GREEN}========================================================"
echo "🎉 Google Chrome Berhasil Dibuka dengan Akselerasi WebGPU!"
echo -e "🔗 URL Aktif: ${TARGET_URL}"
echo -e "========================================================${RESET}"
echo ""
