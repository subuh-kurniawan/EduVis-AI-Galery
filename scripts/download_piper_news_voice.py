#!/usr/bin/env python3
"""Download and verify the Indonesian Piper News Q8 voice model."""

import hashlib
import os
import tempfile
from pathlib import Path
from urllib.request import Request, urlopen


ROOT_DIR = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT_DIR / "models" / "piper"
REVISION = "2115c4b78e65fa224cb5aac1aad73f9e054a7f23"
REPOSITORY = "okasi/piper-indonesian-news-tts-onnx-q8"
FILES = {
    "id_ID-news_tts-medium-q8.onnx": (
        "cb18ababdd66fd6562b4b8b5c186865d6122a0ade0755c8483c44467f3dacf27",
        20 * 1024 * 1024,
    ),
    "id_ID-news_tts-medium-q8.onnx.json": (
        "1ef677072668a5e172e0759b1d3871f129009d1167f093325a17607f7add5ad7",
        32 * 1024,
    ),
}


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as model_file:
        for chunk in iter(lambda: model_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_verified(filename, expected_sha256, max_bytes):
    target = MODEL_DIR / filename
    if target.is_file() and sha256_file(target) == expected_sha256:
        print(f"Verified: {target}")
        return

    url = (
        f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/"
        f"{filename}?download=true"
    )
    request = Request(url, headers={"User-Agent": "EduVis-Piper-Voice-Setup/1.0"})
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    temporary_path = None
    try:
        with urlopen(request, timeout=60) as response:
            with tempfile.NamedTemporaryFile(
                mode="wb", dir=MODEL_DIR, prefix=f".{filename}.", delete=False
            ) as temporary_file:
                temporary_path = Path(temporary_file.name)
                digest = hashlib.sha256()
                total_bytes = 0
                while chunk := response.read(1024 * 1024):
                    total_bytes += len(chunk)
                    if total_bytes > max_bytes:
                        raise ValueError(f"{filename} exceeds its allowed size.")
                    digest.update(chunk)
                    temporary_file.write(chunk)

        if digest.hexdigest() != expected_sha256:
            raise ValueError(f"SHA-256 verification failed for {filename}.")
        os.replace(temporary_path, target)
        temporary_path = None
        print(f"Downloaded and verified: {target}")
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def main():
    for filename, (expected_sha256, max_bytes) in FILES.items():
        download_verified(filename, expected_sha256, max_bytes)


if __name__ == "__main__":
    main()
