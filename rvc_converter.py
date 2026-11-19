"""
RVC Converter Module for Antigravity & EduVis Local TTS
Uses the official RVC pipeline (vc_infer_pipeline.py) with:
- Median pitch filter (filter_radius=3) to eliminate robotic buzz
- Dynamic RMS loudness matching (rms_mix_rate=0.25)
- Boundary reflection padding and 48Hz highpass filter
- FAISS acoustic index retrieval (62k vectors)
"""

import os
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
import glob
from pathlib import Path
import numpy as np
import torch
import torch.nn.functional as F
import librosa
import faiss

faiss.omp_set_num_threads(1)

from config import Config
from vc_infer_pipeline import VC
from lib.infer_pack.models import SynthesizerTrnMs256NSFsid
from transformers import HubertModel
import safetensors.torch

class HubertWrapper(torch.nn.Module):
    def __init__(self, hf_hubert, w, b):
        super().__init__()
        self.hubert = hf_hubert
        self.w = w
        self.b = b

    def extract_features(self, source, padding_mask=None, output_layer=9):
        out = self.hubert(source, output_hidden_states=True)
        return (out.hidden_states[output_layer], None)

    def final_proj(self, feats):
        return F.linear(feats, self.w, self.b)


class RVCVoiceConverter:
    def __init__(
        self,
        model_path="models/rvc/jokowi/model.pth",
        index_path="models/rvc/jokowi/model.index",
        rmvpe_path="rmvpe.pt",
        device="cpu"
    ):
        self.config = Config()
        self.config.device = device
        self.config.is_half = False
        self.device = torch.device(device)
        self.index_path = index_path if (index_path and os.path.exists(index_path)) else ""

        print("⏳ [RVC] Memuat Feature Extractor (ContentVec)...")
        hf_hubert = HubertModel.from_pretrained("lengyue233/content-vec-best")
        hf_hubert.to(self.device).eval()

        files = glob.glob(str(Path.home() / ".cache/huggingface/hub/models--lengyue233--content-vec-best/snapshots/*/*.safetensors"))
        if not files:
            raise FileNotFoundError("ContentVec safetensors not found in HuggingFace cache!")
        st = safetensors.torch.load_file(files[0])
        w = st["final_proj.weight"].to(self.device)
        b = st["final_proj.bias"].to(self.device)
        self.hubert_model = HubertWrapper(hf_hubert, w, b)

        print("⏳ [RVC] Memuat Model Generator Jokowi (model.pth)...")
        cpt = torch.load(model_path, map_location=self.device)
        self.tgt_sr = cpt.get("config", [1025, 32, 192, 192, 768, 2, 6, 3, 0, "1", [3, 7, 11], [[1, 3, 5], [1, 3, 5], [1, 3, 5]], [10, 10, 2, 2], 512, [16, 16, 4, 4], 109, 256, 40000])[-1]
        cpt["config"][-3] = cpt["weight"]["emb_g.weight"].shape[0]  # n_spk

        self.net_g = SynthesizerTrnMs256NSFsid(*cpt["config"], is_half=False)
        if hasattr(self.net_g, "enc_q"):
            del self.net_g.enc_q
        self.net_g.load_state_dict(cpt["weight"], strict=False)
        self.net_g.to(self.device).eval()

        print("⏳ [RVC] Menginisialisasi Official VC Pipeline (Filter Radius=3, RMS Mix=0.25)...")
        self.vc = VC(self.tgt_sr, self.config)
        print("✅ [RVC] Jokowi Voice Converter siap digunakan!")

    def convert(self, audio, sr=22050, f0_up_key=0, index_rate=0.75, filter_radius=3, rms_mix_rate=0.25, protect=0.33):
        """
        Converts input audio to natural, authentic Jokowi voice using the full official RVC pipeline.
        Returns: (out_audio_float32, target_sample_rate)
        """
        if isinstance(audio, torch.Tensor):
            audio = audio.squeeze().detach().cpu().numpy()
        elif isinstance(audio, list):
            audio = np.array(audio, dtype=np.float32)
        else:
            audio = np.asarray(audio, dtype=np.float32)

        if sr != 16000:
            audio_16k = librosa.resample(audio, orig_sr=sr, target_sr=16000)
        else:
            audio_16k = audio

        times = [0, 0, 0]
        converted_int16 = self.vc.pipeline(
            self.hubert_model,
            self.net_g,
            0,  # sid
            audio_16k,
            "input.wav",
            times,
            f0_up_key,
            "rmvpe",
            self.index_path,
            index_rate,
            1,  # if_f0
            filter_radius,
            self.tgt_sr,
            0,  # resample_sr
            rms_mix_rate,
            "v1",
            protect,
        )

        out_f32 = converted_int16.astype(np.float32) / 32768.0
        max_val = np.max(np.abs(out_f32))
        if max_val > 0.78:
            out_f32 = out_f32 * (0.78 / max_val)

        return out_f32, self.tgt_sr
