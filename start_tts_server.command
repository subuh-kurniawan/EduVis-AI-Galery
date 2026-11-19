#!/bin/bash
cd "$(dirname "$0")" || exit 1
echo "=========================================================="
echo "🚀 EduVis AI — Server TTS Lokal Indonesia (drat / VITS)"
echo "=========================================================="
echo "Endpoint: http://127.0.0.1:8765/api/tts"
echo "Karakter: Gadis, Ardi, Wibowo, Juminten, Asep"
echo "=========================================================="
exec .venv_tts/bin/python3 tts_server.py
