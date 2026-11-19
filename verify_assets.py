#!/usr/bin/env python3
# =============================================================================
# 🛡️ Asset & Model Integrity Checker & Auto-Downloader
# Proyek: EduVis AI Gallery (Gemma 4 Web Chat)
# File: verify_assets.py
# Kompatibilitas: Python 3.6+ (macOS, Windows, Linux) - Tanpa dependensi pihak ketiga
# =============================================================================

import os
import sys
import urllib.request
import urllib.error

# Definisi Warna Terminal
try:
    if os.name == 'nt':
        os.system('color')
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    CYAN = '\033[96m'
    RED = '\033[91m'
    BOLD = '\033[1m'
    RESET = '\033[0m'
except Exception:
    GREEN = YELLOW = CYAN = RED = BOLD = RESET = ''

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(SCRIPT_DIR, 'nano_asset', 'models')
ASSETS_JS_DIR = os.path.join(SCRIPT_DIR, 'nano_asset', 'assets', 'js')
WASM_DIR = os.path.join(SCRIPT_DIR, 'wasm')

CRITICAL_ASSETS = [
    {
        'path': os.path.join(MODELS_DIR, 'multilingual-e5-small', 'onnx', 'model_quantized.onnx'),
        'name': 'Model multilingual-e5-small (ONNX)',
        'min_size': 50 * 1024 * 1024,  # min 50MB (asli ~118MB)
        'url': 'https://huggingface.co/Xenova/multilingual-e5-small/resolve/main/onnx/model_quantized.onnx',
        'category': 'model'
    },
    {
        'path': os.path.join(MODELS_DIR, 'all-MiniLM-L6-v2', 'onnx', 'model_quantized.onnx'),
        'name': 'Model all-MiniLM-L6-v2 (ONNX)',
        'min_size': 10 * 1024 * 1024,  # min 10MB (asli ~23MB)
        'url': 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx',
        'category': 'model'
    },
    {
        'path': os.path.join(WASM_DIR, 'genai_wasm_internal.wasm'),
        'name': 'MediaPipe GenAI WASM Engine',
        'min_size': 15 * 1024 * 1024,  # min 15MB (asli ~26MB)
        'url': None,
        'category': 'engine'
    },
    {
        'path': os.path.join(ASSETS_JS_DIR, 'pyodide.asm.wasm'),
        'name': 'Pyodide WebAssembly Engine',
        'min_size': 5 * 1024 * 1024,   # min 5MB (asli ~9MB)
        'url': None,
        'category': 'engine'
    }
]

def format_size(bytes_val):
    for unit in ['B', 'KB', 'MB', 'GB']:
        if bytes_val < 1024.0:
            return f"{bytes_val:.2f} {unit}"
        bytes_val /= 1024.0
    return f"{bytes_val:.2f} TB"

def download_file(url, dest_path):
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    temp_path = dest_path + ".tmp"
    try:
        print(f"  {CYAN}⬇️  Mengunduh dari:{RESET} {url}")
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (EduVis-Asset-Checker)'})
        with urllib.request.urlopen(req) as resp, open(temp_path, 'wb') as out_file:
            total_size = int(resp.info().get('Content-Length', -1))
            downloaded = 0
            chunk_size = 65536
            while True:
                chunk = resp.read(chunk_size)
                if not chunk:
                    break
                out_file.write(chunk)
                downloaded += len(chunk)
                if total_size > 0:
                    percent = downloaded * 100 / total_size
                    print(f"\r  {CYAN}Progress:{RESET} {format_size(downloaded)} / {format_size(total_size)} ({percent:.1f}%)", end='', flush=True)
                else:
                    print(f"\r  {CYAN}Progress:{RESET} {format_size(downloaded)}", end='', flush=True)
        print("\n  ✅ Selesai.")
        shutil.move(temp_path, dest_path)
        return True
    except Exception as e:
        print(f"\n  {RED}❌ Gagal mengunduh: {e}{RESET}")
        if os.path.exists(temp_path):
            os.remove(temp_path)
        return False

def verify_all():
    print(f"\n{BOLD}{CYAN}========================================================")
    print("🛡️  Pemeriksaan Integritas Model & Aset Web EduVis AI")
    print(f"========================================================{RESET}\n")

    all_ok = True
    for item in CRITICAL_ASSETS:
        path = item['path']
        name = item['name']
        min_sz = item['min_size']

        if not os.path.exists(path):
            print(f"{RED}❌ Hilang:{RESET} {name}")
            print(f"   Lokasi: {path}")
            if item.get('url'):
                if download_file(item['url'], path):
                    print(f"   {GREEN}✅ Berhasil dipulihkan!{RESET}\n")
                    continue
            all_ok = False
            continue

        actual_sz = os.path.getsize(path)
        if actual_sz < min_sz:
            print(f"{YELLOW}⚠️  File tidak lengkap/Git LFS pointer:{RESET} {name}")
            print(f"   Ukuran saat ini: {format_size(actual_sz)} (Minimal {format_size(min_sz)})")
            if item.get('url'):
                print(f"   {CYAN}Mengunduh versi lengkap...{RESET}")
                if download_file(item['url'], path):
                    print(f"   {GREEN}✅ Berhasil dipulihkan!{RESET}\n")
                    continue
            all_ok = False
            continue

        print(f"{GREEN}✅ Valid:{RESET} {name} ({format_size(actual_sz)})")

    # Periksa ketersediaan model LLM lokal (.litertlm)
    print(f"\n{BOLD}{CYAN}--------------------------------------------------------")
    print("🔍 Pemeriksaan Model LLM Lokal (.litertlm):")
    print(f"--------------------------------------------------------{RESET}")
    local_models = [f for f in os.listdir(SCRIPT_DIR) if f.endswith('.litertlm')]
    if local_models:
        for m in local_models:
            sz = os.path.getsize(os.path.join(SCRIPT_DIR, m))
            print(f"  {GREEN}📦 Ditemukan:{RESET} {m} ({format_size(sz)})")
    else:
        print(f"  {YELLOW}ℹ️  Belum ada file .litertlm lokal.{RESET}")
        print("  Model akan diunduh otomatis dari Hugging Face ke cache OPFS saat dipilih di browser.")

    print(f"\n{BOLD}{CYAN}========================================================{RESET}")
    if all_ok:
        print(f"{GREEN}{BOLD}🎉 Seluruh aset inti valid dan siap digunakan secara offline!{RESET}\n")
    else:
        print(f"{YELLOW}{BOLD}⚠️  Beberapa aset belum lengkap. Silakan periksa pesan di atas.{RESET}\n")

if __name__ == '__main__':
    verify_all()
