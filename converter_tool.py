#!/usr/bin/env python3
import argparse
import os
import shutil
import subprocess
import sys
import zipfile

def inspect_model(args):
    path = args.model_file
    if not os.path.exists(path):
        raise FileNotFoundError(f"File tidak ditemukan: {path}")

    file_size_mb = os.path.getsize(path) / (1024 * 1024)
    print("==================================================")
    print(f"🔍 Inspeksi Format Model: {os.path.basename(path)}")
    print(f"📦 Ukuran File: {file_size_mb:.2f} MB")

    with open(path, "rb") as f:
        header = f.read(16)

    if header.startswith(b"LITERTLM"):
        version = int.from_bytes(header[8:12], "little")
        sections = int.from_bytes(header[12:16], "little")
        print("✅ Format: Native LiteRT-LM Binary Container")
        print("📌 Magic Header: 'LITERTLM'")
        print(f"⚙️ Versi Format: {version}")
        print(f"📑 Jumlah Bagian (Sections): {sections}")
        print("🌐 WebGPU/WASM: Kompatibel penuh untuk inferensi in-browser MediaPipe / LiteRT")
    elif b"TFL3" in header[:8]:
        print("✅ Format: TensorFlow Lite FlatBuffer (TFL3 / LiteRT Model File)")
        print("📌 Identifier: 'TFL3'")
        print("🌐 WebGPU/WASM: Dapat dimuat oleh LiteRT / MediaPipe Web runtime")
    elif header.startswith(b"PK\x03\x04"):
        print("ℹ️ Format: MediaPipe Task / ZIP Bundle Container")
        try:
            with zipfile.ZipFile(path, "r") as zf:
                files = zf.namelist()
                print(f"📂 Berkas di dalam paket ({len(files)} file):")
                for name in files:
                    sz = zf.getinfo(name).file_size / (1024 * 1024)
                    print(f"   - {name} ({sz:.2f} MB)")
                has_gpu = any("gpu" in n.lower() or "artisan" in n.lower() for n in files)
                print(f"⚡ GPU Kernel Terdeteksi: {'Ya' if has_gpu else 'Tidak (hanya CPU fallback)'}")
        except Exception as e:
            print(f"⚠️ Gagal membaca daftar arsip zip: {e}")
    else:
        print(f"⚠️ Format: Biner kustom atau FlatBuffer murni (Magic: {header[:8].hex()})")
    print("==================================================")

def repackage_model(args):
    print("Memproses Pemaketan LiteRT-LM...")
    print(f"Model TFLite : {args.model_tflite}")
    print(f"Tokenizer    : {args.tokenizer}")
    print(f"Output File  : {args.output_litertlm}")

    if not os.path.exists(args.model_tflite):
        raise FileNotFoundError(f"File model tidak ditemukan: {args.model_tflite}")
    if not os.path.exists(args.tokenizer):
        raise FileNotFoundError(f"File tokenizer tidak ditemukan: {args.tokenizer}")

    builder_bin = shutil.which("litert-lm-builder")
    if builder_bin and not args.force_zip:
        print("🛠️ Ditemukan 'litert-lm-builder' resmi di sistem. Menjalankan compiler GPU...")
        cmd = [
            builder_bin,
            f"--model_path={args.model_tflite}",
            f"--tokenizer_path={args.tokenizer}",
            f"--output_path={args.output_litertlm}"
        ]
        if args.target_gpu:
            cmd.append("--backend_constraint=gpu")
        res = subprocess.run(cmd)
        if res.returncode == 0:
            print(f"✅ Berhasil membuat binary LiteRT-LM WebGPU di: {args.output_litertlm}")
            return
        print("⚠️ 'litert-lm-builder' gagal, beralih ke pembungkus arsip standar...")

    # Fallback membuat bundel kontainer
    with zipfile.ZipFile(args.output_litertlm, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(args.model_tflite, arcname="model.tflite")
        zf.write(args.tokenizer, arcname="tokenizer.model")
        if getattr(args, "gpu_artisan", None) and os.path.exists(args.gpu_artisan):
            zf.write(args.gpu_artisan, arcname="gpu_artisan.bin")
            print(f"⚡ GPU Artisan Shader disertakan: {args.gpu_artisan}")

    print(f"Berhasil membuat paket model di: {args.output_litertlm}")
    if not builder_bin:
        print("💡 Catatan: Pasang 'pip install litert-lm-builder' untuk kompilasi native container LITERTLM WebGPU.")

def convert_mediapipe(args):
    print("Memproses Konversi MediaPipe LLM...")
    print(f"Checkpoint Dir : {args.input_ckpt}")
    print(f"Vocab File     : {args.vocab_file}")
    print(f"Output Dir     : {args.output_dir}")
    print(f"Model Type     : {args.model_type}")
    print(f"Backend Target : {args.backend}")

    if not os.path.exists(args.input_ckpt):
        raise FileNotFoundError(f"Folder checkpoint tidak ditemukan: {args.input_ckpt}")

    os.makedirs(args.output_dir, exist_ok=True)

    try:
        from mediapipe.tasks.python.genai import llm as mp_llm

        print("Menjalankan konverter internal MediaPipe...")
        mp_llm.convert(
            checkpoint_dir=args.input_ckpt,
            vocab_model_file=args.vocab_file,
            output_dir=args.output_dir,
            model_type=args.model_type,
            backend=args.backend
        )
        print("Konversi MediaPipe selesai dengan sukses.")
    except ImportError:
        print("PERINGATAN: Modul 'mediapipe.tasks.python.genai' tidak ditemukan.")
        print("Pastikan paket mediapipe versi terbaru telah terinstal di lingkungan virtual Anda.")
        sys.exit(1)
    except Exception as e:
        print(f"Error saat konversi MediaPipe: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="LiteRT-LM & MediaPipe Converter Tool CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Subcommand: inspect
    parser_inspect = subparsers.add_parser("inspect", help="Inspeksi header dan kompatibilitas berkas model .litertlm / .task")
    parser_inspect.add_argument("model_file", help="Path ke file .litertlm atau .task")

    # Subcommand: repackage
    parser_repack = subparsers.add_parser("repackage", help="Repackage model & tokenizer ke .litertlm")
    parser_repack.add_argument("--model_tflite", required=True, help="Path ke file .tflite")
    parser_repack.add_argument("--tokenizer", required=True, help="Path ke file tokenizer (.model)")
    parser_repack.add_argument("--output_litertlm", required=True, help="Path output file .litertlm")
    parser_repack.add_argument("--gpu_artisan", required=False, default=None, help="Path ke shader gpu_artisan.bin (opsional)")
    parser_repack.add_argument("--target_gpu", action="store_true", default=True, help="Target akselerasi GPU")
    parser_repack.add_argument("--force_zip", action="store_true", default=False, help="Paksa gunakan zip wrapper alih-alih litert-lm-builder")

    # Subcommand: mediapipe
    parser_conv = subparsers.add_parser("mediapipe", help="Konversi checkpoint mentah ke format MediaPipe")
    parser_conv.add_argument("--input_ckpt", required=True, help="Folder checkpoint mentah")
    parser_conv.add_argument("--vocab_file", required=True, help="File tokenizer.model")
    parser_conv.add_argument("--output_dir", required=True, help="Folder output hasil konversi")
    parser_conv.add_argument("--model_type", required=True, help="Tipe model (misal: GEMMA_2B)")
    parser_conv.add_argument("--backend", required=True, help="Backend target (cpu / gpu)")

    args = parser.parse_args()

    if args.command == "inspect":
        inspect_model(args)
    elif args.command == "repackage":
        repackage_model(args)
    elif args.command == "mediapipe":
        convert_mediapipe(args)

if __name__ == "__main__":
    main()
