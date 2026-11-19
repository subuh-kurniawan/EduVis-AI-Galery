#!/usr/bin/env python3
import os
import urllib.request
import sys

BASE_URL = "https://huggingface.co/Xenova/multilingual-e5-small/resolve/main/"
TARGET_DIR = os.path.join(os.path.dirname(__file__), "..", "nano_asset", "models", "multilingual-e5-small")

FILES = [
    "config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
    "onnx/model_quantized.onnx"
]

def download_file(rel_path):
    url = BASE_URL + rel_path
    dest = os.path.join(TARGET_DIR, rel_path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print(f"Already exists: {dest} ({os.path.getsize(dest)} bytes)")
        return True

    print(f"Downloading {url} -> {dest} ...")
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as resp, open(dest, 'wb') as f:
            total_size = int(resp.info().get('Content-Length', -1))
            downloaded = 0
            block_size = 65536
            while True:
                chunk = resp.read(block_size)
                if not chunk:
                    break
                f.write(chunk)
                downloaded += len(chunk)
                if total_size > 0:
                    percent = downloaded * 100 / total_size
                    print(f"\r  Downloaded {downloaded}/{total_size} bytes ({percent:.1f}%)", end='', flush=True)
                else:
                    print(f"\r  Downloaded {downloaded} bytes", end='', flush=True)
        print("\n  Done.")
        return True
    except Exception as e:
        print(f"\n  Failed: {e}", file=sys.stderr)
        if os.path.exists(dest):
            os.remove(dest)
        return False

def main():
    os.makedirs(TARGET_DIR, exist_ok=True)
    success = True
    for rel_path in FILES:
        if not download_file(rel_path):
            success = False
            break
    if success:
        print("\nAll multilingual-e5-small model files downloaded successfully!")
    else:
        print("\nSome files failed to download.", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
