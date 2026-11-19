#!/usr/bin/env python3
"""
Pembangun Installer macOS (.dmg) Siap Pakai untuk EduVis AI Gallery (Gemma 4 Local Suite).
Menghasilkan file `EduVis-AI-Gallery-macOS.dmg` yang berisi:
  1. `EduVis AI Gallery.app` mandiri (seluruh ruang kerja, aset lokal, embedding model,
     dan backend Python telah dibundel di dalam `Contents/Resources/app/`)
  2. Pintasan `/Applications` untuk instalasi seret-dan-lepas (drag-and-drop)
  3. `BACA SAYA - Panduan & Unduh Model.txt` berisi langkah instalasi & tautan unduh model .litertlm
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_DIR))

import gemma_chat_gui  # noqa: E402


GUIDE_TEXT = """========================================================================
EDU-VIS AI GALLERY — GEMMA 4 ENTERPRISE LOCAL AI SUITE (macOS)
Developer: Subuh Kurniawan (EduVis Project)
========================================================================

CARA INSTALASI (SIAP PAKAI):
1. Seret "EduVis Native AI.app" dan/atau "EduVis AI Gallery.app" ke folder "Applications".
   - EduVis Native AI.app  : Aplikasi SwiftUI Liquid Glass + mesin in-process Pure Swift
                             (liblitert-lm.dylib) tanpa ketergantungan Python saat offline.
   - EduVis AI Gallery.app : Launcher WebView + Pusat Model + akses LAN HTTPS/QR.
2. Saat dibuka pertama kali, seluruh requirement dijalankan OTOMATIS:
   - Menyiapkan virtual environment khusus aplikasi & menginstal runtime LiteRT-LM
     jika belum tersedia (perlu koneksi internet hanya pada eksekusi pertama).
   - Membuat konfigurasi GPU Metal + Speculative Decoding default di ~/.litert-lm/config.json.
   - Menyelaraskan model .litertlm lokal secara zero-copy.
   (Jika muncul peringatan Gatekeeper macOS saat pertama kali dibuka:
    Klik kanan ikon aplikasi -> pilih "Buka" / "Open").

CARA MENGUNDUH & MEMUAT MODEL AI (.litertlm):
Aplikasi ini sudah menyertakan seluruh ruang kerja, mesin RAG Vektor SQLite,
dan model embedding multibahasa lokal. Anda hanya perlu mengunduh minimal
1 file model bahasa berformat `.litertlm`:

1. Buka aplikasi "EduVis AI Gallery", lalu klik tombol "Pusat Model…".
2. Klik tombol "Unduh Model (.litertlm) Resmi…" atau buka tautan berikut di browser:
   - Koleksi Resmi Google AI Edge / LiteRT Community:
     https://huggingface.co/litert-community
   - Rekomendasi Model Ringan & Cepat (RAM 8 GB+):
     gemma-4-E2B-it.litertlm / gemma-3n-E2B-it-int4.litertlm
   - Rekomendasi Model Multimodal Penuh (RAM 16 GB+):
     gemma-4-E4B-it.litertlm / gemma-3n-E4B-it-int4.litertlm
3. Setelah file `.litertlm` selesai diunduh (misalnya di folder Downloads):
   - Seret langsung file `.litertlm` ke kotak "Pusat Model…" di aplikasi, ATAU
   - Klik "Pilih File Model…" lalu pilih file `.litertlm` tersebut, ATAU
   - Klik "Sinkronkan Model Proyek" bila model diletakkan di folder ~/Gemma4.
4. Klik "Mulai →" untuk masuk ke ruang kerja AI lokal Anda!
========================================================================
"""


def copy_project_runtime(dest_app_dir: Path) -> None:
    """Salin seluruh file runtime aplikasi (tanpa file model .litertlm raksasa & node_modules)."""
    dest_app_dir.mkdir(parents=True, exist_ok=True)

    for pattern in ("*.html", "*.js", "*.py", "Banner.jpg", "favicon.ico", "manifest.webmanifest", "requirements-piper.txt"):
        for src_file in PROJECT_DIR.glob(pattern):
            if src_file.is_file() and not src_file.is_symlink():
                shutil.copy2(src_file, dest_app_dir / src_file.name)

    for folder_name in ("nano_asset", "litert_lm_compat", "models", "scripts"):
        src_folder = PROJECT_DIR / folder_name
        if src_folder.is_dir():
            shutil.copytree(
                src_folder,
                dest_app_dir / folder_name,
                dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("*.litertlm", "*.xnnpack_cache", "*_mldrift_*", "__pycache__", ".DS_Store"),
            )


def build_dmg(output_dmg: Path | None = None, app_only: bool = False, dmg_only: bool = False) -> Path:
    swiftc = shutil.which("swiftc")
    if not swiftc:
        raise RuntimeError("Perintah `swiftc` tidak ditemukan. Pasang Xcode Command Line Tools.")

    if output_dmg is None:
        output_dmg = PROJECT_DIR / "EduVis-AI-Gallery-macOS.dmg"
    output_dmg = Path(output_dmg).resolve()

    gemma_chat_gui.reclaim_backend_ports()
    workspace_app_bundle = PROJECT_DIR / "EduVis AI Gallery.app"
    local_app_bundle = Path.home() / "Applications" / "EduVis AI Gallery.app"

    if not (dmg_only and workspace_app_bundle.is_dir()):
        print(f"[1/4] Mengompilasi aplikasi native {workspace_app_bundle.name}...")
        if workspace_app_bundle.exists():
            shutil.rmtree(workspace_app_bundle)
        gemma_chat_gui.compile_webview(swiftc, workspace_app_bundle)

        print("[2/4] Menyiapkan bundle mandiri (self-contained .app)...")
        bundled_runtime_dir = workspace_app_bundle / "Contents" / "Resources" / "app"
        copy_project_runtime(bundled_runtime_dir)

        subprocess.run(["xattr", "-cr", str(workspace_app_bundle)], check=True)
        subprocess.run(
            ["codesign", "--force", "--deep", "--sign", "-", str(workspace_app_bundle)],
            check=True,
        )

    lsregister = (
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
        "LaunchServices.framework/Support/lsregister"
    )
    for target_bundle in (
        local_app_bundle,
        Path("/Applications") / "EduVis AI Gallery.app",
    ):
        try:
            if target_bundle != local_app_bundle and not target_bundle.exists():
                continue
            if target_bundle.exists():
                shutil.rmtree(target_bundle)
            shutil.copytree(workspace_app_bundle, target_bundle, symlinks=True)
            if Path(lsregister).is_file():
                subprocess.run([lsregister, "-f", str(target_bundle)], check=False)
            os.utime(target_bundle, None)
            print(f"      -> Bundle lokal diperbarui: {target_bundle}")
        except OSError:
            pass

    if app_only:
        print(f"[Selesai] Bundle aplikasi mandiri siap: {workspace_app_bundle}")
        return workspace_app_bundle

    native_app_dir = PROJECT_DIR / "EduVisNativeApp"
    native_app_bundle = native_app_dir / "EduVis Native AI.app"
    native_build_script = native_app_dir / "build_native_app.sh"
    if native_build_script.is_file() and not (dmg_only and native_app_bundle.is_dir()):
        print("[2b/4] Memperbarui bundle SwiftUI Native (EduVis Native AI.app)...")
        subprocess.run(["bash", str(native_build_script)], cwd=native_app_dir, check=True)

    with tempfile.TemporaryDirectory(dir="/tmp", prefix="eduvis-dmg-stage-") as staging_str:
        staging_dir = Path(staging_str)
        staged_app = staging_dir / "EduVis AI Gallery.app"
        shutil.copytree(workspace_app_bundle, staged_app, symlinks=True)
        if native_app_bundle.is_dir():
            shutil.copytree(
                native_app_bundle,
                staging_dir / "EduVis Native AI.app",
                symlinks=True,
            )

        # Tambahkan symlink /Applications dan panduan instalasi
        os.symlink("/Applications", staging_dir / "Applications")
        (staging_dir / "BACA SAYA - Panduan & Unduh Model.txt").write_text(
            GUIDE_TEXT, encoding="utf-8"
        )

        print(f"[3/4] Membuat image disk terkompresi: {output_dmg.name}...")
        if output_dmg.exists():
            output_dmg.unlink()

        subprocess.run(
            [
                "hdiutil",
                "create",
                "-volname",
                "EduVis AI Gallery",
                "-srcfolder",
                str(staging_dir),
                "-ov",
                "-format",
                "UDZO",
                str(output_dmg),
            ],
            check=True,
        )

    size_mb = output_dmg.stat().st_size / (1024 * 1024)
    print(f"[4/4] Selesai! File DMG siap pakai: {output_dmg} ({size_mb:.1f} MB)")
    return output_dmg


if __name__ == "__main__":
    build_dmg(
        app_only="--app-only" in sys.argv[1:],
        dmg_only="--dmg-only" in sys.argv[1:],
    )
