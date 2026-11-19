#!/usr/bin/env python3
"""
Standalone model & asset downloader for EduVis AI Gallery.
Downloads heavy model weights directly into the exact local paths expected by
the web UI, TTS server, and native macOS app without bloating the Git repo.

Usage:
    python3 scripts/download_models.py              # Download public models (Hugging Face)
    python3 scripts/download_models.py --all        # Also download custom Release assets & Piper
    python3 scripts/download_models.py --only embeddings
    python3 scripts/download_models.py --only tts
    python3 scripts/download_models.py --only rvc
"""

import argparse
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent

DEFAULT_RELEASE_BASE = os.environ.get(
    "EDUVIS_RELEASE_URL",
    "https://github.com/subuh-kurniawan/EduVis-AI-Galery/releases/download/assets-v1/",
).rstrip("/") + "/"

HF_E5_BASE = "https://huggingface.co/Xenova/multilingual-e5-small/resolve/main/"
HF_MINILM_BASE = "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/"
HF_TTS_ID_URL = "https://huggingface.co/wikidepia/indonesian-tts/resolve/main/checkpoint_1260000-inference.pth"

MODEL_GROUPS = {
    "embeddings": [
        # multilingual-e5-small (~135 MB)
        (HF_E5_BASE + "config.json", ROOT_DIR / "nano_asset/models/multilingual-e5-small/config.json"),
        (HF_E5_BASE + "tokenizer.json", ROOT_DIR / "nano_asset/models/multilingual-e5-small/tokenizer.json"),
        (HF_E5_BASE + "tokenizer_config.json", ROOT_DIR / "nano_asset/models/multilingual-e5-small/tokenizer_config.json"),
        (HF_E5_BASE + "special_tokens_map.json", ROOT_DIR / "nano_asset/models/multilingual-e5-small/special_tokens_map.json"),
        (HF_E5_BASE + "onnx/model_quantized.onnx", ROOT_DIR / "nano_asset/models/multilingual-e5-small/onnx/model_quantized.onnx"),
        # all-MiniLM-L6-v2 (~23 MB)
        (HF_MINILM_BASE + "config.json", ROOT_DIR / "nano_asset/models/all-MiniLM-L6-v2/config.json"),
        (HF_MINILM_BASE + "tokenizer.json", ROOT_DIR / "nano_asset/models/all-MiniLM-L6-v2/tokenizer.json"),
        (HF_MINILM_BASE + "tokenizer_config.json", ROOT_DIR / "nano_asset/models/all-MiniLM-L6-v2/tokenizer_config.json"),
        (HF_MINILM_BASE + "special_tokens_map.json", ROOT_DIR / "nano_asset/models/all-MiniLM-L6-v2/special_tokens_map.json"),
        (HF_MINILM_BASE + "onnx/model_quantized.onnx", ROOT_DIR / "nano_asset/models/all-MiniLM-L6-v2/onnx/model_quantized.onnx"),
    ],
    "tts": [
        (HF_TTS_ID_URL, ROOT_DIR / "models/tts_indonesia/checkpoint_1260000-inference.pth"),
    ],
    "tts-onnx": [
        (DEFAULT_RELEASE_BASE + "vits_indonesia.onnx", ROOT_DIR / "nano_asset/models/tts/vits_indonesia.onnx"),
    ],
    "rvc": [
        (DEFAULT_RELEASE_BASE + "jokowi_model.pth", ROOT_DIR / "models/rvc/jokowi/model.pth"),
        (DEFAULT_RELEASE_BASE + "jokowi_model.index", ROOT_DIR / "models/rvc/jokowi/model.index"),
    ],
}


def download_file(url: str, dest: Path, optional: bool = False) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        size_mb = dest.stat().st_size / (1024 * 1024)
        print(f"[SKIP] Sudah ada: {dest.relative_to(ROOT_DIR)} ({size_mb:.1f} MB)")
        return True

    print(f"[GET ] {url}")
    print(f"    -> {dest.relative_to(ROOT_DIR)}")
    tmp_dest = dest.with_suffix(dest.suffix + ".part")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "EduVis-Model-Downloader/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp, open(tmp_dest, "wb") as out:
            total = int(resp.info().get("Content-Length", -1))
            downloaded = 0
            while True:
                chunk = resp.read(65536)
                if not chunk:
                    break
                out.write(chunk)
                downloaded += len(chunk)
                if total > 0:
                    pct = downloaded * 100.0 / total
                    print(f"\r       {downloaded / (1024 * 1024):.1f} / {total / (1024 * 1024):.1f} MB ({pct:.1f}%)", end="", flush=True)
                else:
                    print(f"\r       {downloaded / (1024 * 1024):.1f} MB", end="", flush=True)
        print(" - Selesai")
        tmp_dest.replace(dest)
        return True
    except urllib.error.HTTPError as e:
        print(f"\n[WARN] HTTP {e.code} untuk {url}")
        if optional:
            print("       (Aset opsional dari GitHub Releases belum tersedia; bisa diunggah ke tag 'assets-v1' atau di-export lokal.)")
        if tmp_dest.exists():
            tmp_dest.unlink()
        return optional
    except Exception as e:
        print(f"\n[ERR ] Gagal mengunduh {url}: {e}", file=sys.stderr)
        if tmp_dest.exists():
            tmp_dest.unlink()
        return optional


def main() -> int:
    parser = argparse.ArgumentParser(description="Unduh model berat EduVis AI Gallery secara mandiri.")
    parser.add_argument(
        "--only",
        choices=["embeddings", "tts", "tts-onnx", "rvc"],
        help="Unduh hanya grup model tertentu.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Unduh semua grup termasuk aset opsional GitHub Releases (tts-onnx, rvc) dan Piper.",
    )
    parser.add_argument(
        "--with-piper",
        action="store_true",
        help="Jalankan juga scripts/download_piper_news_voice.py.",
    )
    args = parser.parse_args()

    if args.only:
        groups = [args.only]
    elif args.all:
        groups = ["embeddings", "tts", "tts-onnx", "rvc"]
    else:
        groups = ["embeddings", "tts"]

    all_ok = True
    for group in groups:
        print(f"\n=== Grup: {group} ===")
        is_optional = group in ("tts-onnx", "rvc")
        for url, dest in MODEL_GROUPS[group]:
            if not download_file(url, dest, optional=is_optional):
                all_ok = False

    if args.all or args.with_piper:
        piper_script = ROOT_DIR / "scripts/download_piper_news_voice.py"
        if piper_script.exists():
            print("\n=== Grup: piper ===")
            res = subprocess.run([sys.executable, str(piper_script)], cwd=str(ROOT_DIR))
            if res.returncode != 0:
                all_ok = False

    if all_ok:
        print("\nSelesai! Semua model yang diminta telah siap.")
        return 0
    print("\nBeberapa file gagal diunduh. Periksa koneksi atau EDUVIS_RELEASE_URL.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
