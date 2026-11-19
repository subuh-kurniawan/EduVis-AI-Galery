import os
import sys
import torch
import torch.onnx

# Monkeypatch torch.onnx.export untuk mematikan dynamo=True di PyTorch 2.15
orig_export = torch.onnx.export
def patched_export(*args, **kwargs):
    kwargs["dynamo"] = False
    return orig_export(*args, **kwargs)

torch.onnx.export = patched_export

from TTS.utils.synthesizer import Synthesizer

model_path = 'models/tts_indonesia/checkpoint_1260000-inference.pth'
config_path = 'TTS-Indonesia-Gratis/config.json'
speakers_path = 'TTS-Indonesia-Gratis/g2p_id/data/speakers.pth'
output_onnx = 'nano_asset/models/tts/vits_indonesia.onnx'

print("Memuat model VITS checkpoint...")
synth = Synthesizer(
    tts_checkpoint=model_path,
    tts_config_path=config_path,
    tts_speakers_file=speakers_path,
    use_cuda=False
)

print(f"Mengekspor model VITS (TorchScript ONNX) ke {output_onnx}...")
synth.tts_model.export_onnx(output_path=output_onnx, verbose=False)

if os.path.isfile(output_onnx):
    size_mb = os.path.getsize(output_onnx) / (1024 * 1024)
    print(f"✅ Ekspor ONNX Berhasil! Lokasi: {output_onnx} ({size_mb:.2f} MB)")
else:
    print("❌ Berkas ONNX tidak ditemukan!")
