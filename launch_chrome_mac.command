#!/bin/bash
# =========================================================================
# Launch Chrome with WebGPU & Edge AI Flags (Double-Click Launcher macOS)
# =========================================================================
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

./launch_chrome_ai.sh
