#!/usr/bin/env python3
"""
manage_litert_models.py - LiteRT-LM & Hugging Face Model Management Utility
Proyek: Gemma 4 / EduVis AI Gallery
"""

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys

COMMUNITY_CATALOG = {
    "gemma-4-E2B-it": {
        "repo": "litert-community/gemma-4-E2B-it-litert-lm",
        "desc": "Gemma 4 (1.6B parameter aktif), sangat cepat untuk CPU/GPU on-device.",
        "size_approx": "~2.5 GB",
        "recommended_ram": "8 GB"
    },
    "gemma-4-E4B-it": {
        "repo": "litert-community/gemma-4-E4B-it-litert-lm",
        "desc": "Gemma 4 (2.7B parameter aktif), seimbang untuk kecepatan dan pemahaman konteks.",
        "size_approx": "~4.2 GB",
        "recommended_ram": "12 GB - 16 GB"
    },
    "gemma-4-12B-it": {
        "repo": "litert-community/gemma-4-12B-it-litert-lm",
        "desc": "Gemma 4 12B, kemampuan penalaran menengah-tinggi untuk PC/Mac.",
        "size_approx": "~8.5 GB",
        "recommended_ram": "16 GB+"
    },
    "gemma-4-26B-A4B-it": {
        "repo": "litert-community/gemma-4-26B-A4B-it-litert-lm",
        "desc": "Gemma 4 MoE (Mixture of Experts), efisiensi komputasi tinggi pada skala 26B.",
        "size_approx": "~15 GB",
        "recommended_ram": "32 GB+"
    },
    "gemma-3-1B-it": {
        "repo": "litert-community/Gemma3-1B-IT",
        "desc": "Gemma 3 1B, ultra-ringan untuk perangkat mobile dan IoT.",
        "size_approx": "~1.2 GB",
        "recommended_ram": "4 GB"
    },
    "embeddinggemma-2-740m": {
        "repo": "litert-community/embeddinggemma-2-740m-litert-lm",
        "desc": "Model Embedding Multimodal (teks/gambar/suara) untuk On-Device RAG.",
        "size_approx": "~1.5 GB",
        "recommended_ram": "4 GB - 8 GB"
    },
    "functiongemma-270m": {
        "repo": "litert-community/functiongemma-270m-ft-mobile-actions",
        "desc": "Model ringkas khusus Function Calling dan aksi antarmuka.",
        "size_approx": "~550 MB",
        "recommended_ram": "2 GB"
    }
}


def format_bytes(size):
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024.0:
            return f"{size:.2f} {unit}"
        size /= 1024.0
    return f"{size:.2f} PB"


def list_local_models():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pattern = os.path.join(base_dir, "*.litertlm")
    models = glob.glob(pattern)

    # Cek juga di folder models/ jika ada
    models_dir_pattern = os.path.join(base_dir, "models", "*.litertlm")
    models.extend(glob.glob(models_dir_pattern))

    print("\n📦 MODEL LOKAL TERSEDIA (.litertlm):")
    print("=" * 70)
    if not models:
        print("  (Belum ada file .litertlm yang ditemukan)")
    else:
        for idx, path in enumerate(models, 1):
            size = os.path.getsize(path)
            fname = os.path.basename(path)
            
            # Cek status cache
            has_xnnpack = any(fname in c for c in glob.glob(os.path.join(base_dir, "*.xnnpack_cache")))
            has_mldrift = any(fname in c for c in glob.glob(os.path.join(base_dir, "*_mldrift_*")))
            
            cache_info = []
            if has_xnnpack:
                cache_info.append("CPU XNNPack")
            if has_mldrift:
                cache_info.append("GPU MLDrift")
            cache_str = f" [Cache: {', '.join(cache_info)}]" if cache_info else " [Belum ada cache]"

            print(f"  {idx}. {fname} ({format_bytes(size)}){cache_str}")
            print(f"     Path: {path}")

    print("\n🌐 KATALOG MODEL DARI HUGGING FACE (litert-community):")
    print("=" * 70)
    for key, item in COMMUNITY_CATALOG.items():
        print(f"  • {key.upper()}:")
        print(f"    Repo: {item['repo']}")
        print(f"    Ukuran: {item['size_approx']} | Rekomendasi RAM: {item['recommended_ram']}")
        print(f"    Fungsi: {item['desc']}\n")


def inspect_model(model_path):
    if not os.path.exists(model_path):
        print(f"Error: Berkas model '{model_path}' tidak ditemukan.")
        return

    size = os.path.getsize(model_path)
    print("\n🔍 INSPEKSI MODEL LOKAL:")
    print("=" * 50)
    print(f"  Nama Berkas : {os.path.basename(model_path)}")
    print(f"  Ukuran      : {format_bytes(size)}")
    print(f"  Lokasi      : {os.path.abspath(model_path)}")

    # Cek litert-lm CLI
    if shutil.which("litert-lm"):
        print("\n  Menjalankan 'litert-lm describe'...")
        try:
            res = subprocess.run(
                ["litert-lm", "describe", "--model", model_path],
                capture_output=True,
                text=True,
                timeout=15
            )
            if res.stdout:
                print(res.stdout)
            elif res.stderr:
                print(res.stderr)
        except Exception as err:
            print(f"  Gagal menjalankan describe: {err}")
    else:
        print("  (Tip: Pasang 'pip install litert-lm' untuk melihat metadata graf internal)")


def download_model(model_key, target_dir=None):
    if target_dir is None:
        target_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    repo_id = model_key
    if model_key in COMMUNITY_CATALOG:
        repo_id = COMMUNITY_CATALOG[model_key]["repo"]

    print(f"\n📥 MENGUNDUH MODEL DARI HUGGING FACE: {repo_id}")
    print(f"Target Direktori: {target_dir}")
    print("-" * 60)

    if shutil.which("huggingface-cli"):
        cmd = [
            "huggingface-cli", "download",
            repo_id,
            "--include", "*.litertlm",
            "--local-dir", target_dir,
            "--local-dir-use-symlinks", "False"
        ]
        print(f"Menjalankan perintah: {' '.join(cmd)}")
        try:
            subprocess.run(cmd, check=True)
            print("✅ Unduhan selesai!")
        except subprocess.CalledProcessError as exc:
            print(f"❌ Unduhan gagal: {exc}")
    else:
        print("⚠️ 'huggingface-cli' tidak ditemukan.")
        print("Jalankan perintah berikut di terminal Anda:")
        print(f"  pip install huggingface_hub")
        print(f"  huggingface-cli download {repo_id} --include '*.litertlm' --local-dir {target_dir}")


def main():
    parser = argparse.ArgumentParser(description="Kelola Model LiteRT-LM & Hugging Face (EduVis AI Gallery)")
    subparsers = parser.add_subparsers(dest="command")

    # Command: list
    subparsers.add_parser("list", help="Tampilkan daftar model lokal dan katalog litert-community")

    # Command: inspect
    inspect_parser = subparsers.add_parser("inspect", help="Inspeksi metadata berkas .litertlm")
    inspect_parser.add_argument("model_path", help="Path ke berkas .litertlm")

    # Command: download
    download_parser = subparsers.add_parser("download", help="Unduh model dari litert-community")
    download_parser.add_argument("model_key", help="Key model (misal: gemma-4-E2B-it, embeddinggemma-2-740m) atau ID repo")
    download_parser.add_argument("--dir", default=None, help="Direktori penyimpanan target")

    args = parser.parse_args()

    if args.command == "list" or not args.command:
        list_local_models()
    elif args.command == "inspect":
        inspect_model(args.model_path)
    elif args.command == "download":
        download_model(args.model_key, args.dir)


if __name__ == "__main__":
    main()
