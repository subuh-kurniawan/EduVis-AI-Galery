#!/usr/bin/env python3
"""
EduVis AI - Local TTS Server (drat / VITS Indonesian Model)
Port: 8765
"""

import os
import sys
import re
import json
import uuid
import io
import wave
import tempfile
import subprocess
import threading
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# Base paths
ROOT_DIR = Path(__file__).resolve().parent
VENV_PYTHON = ROOT_DIR / ".venv_tts" / "bin" / "python3"
BIN_TTS = ROOT_DIR / ".venv_tts" / "bin" / "tts"
DATA_DIR = ROOT_DIR / "TTS-Indonesia-Gratis" / "g2p_id" / "data"
CONFIG_FILE = ROOT_DIR / "TTS-Indonesia-Gratis" / "config.json"
MODEL_FILE = ROOT_DIR / "models" / "tts_indonesia" / "checkpoint_1260000-inference.pth"
PIPER_MODEL_FILE = ROOT_DIR / "models" / "piper" / "id_ID-news_tts-medium-q8.onnx"
PIPER_CONFIG_FILE = Path(f"{PIPER_MODEL_FILE}.json")

# Ensure config.json points to the correct speakers.pth
if not CONFIG_FILE.exists() and DATA_DIR.exists():
    config_base_file = DATA_DIR / "config.json"
    speakers_file = DATA_DIR / "speakers.pth"
    if config_base_file.exists():
        with open(config_base_file, "r", encoding="utf-8") as f:
            d = json.load(f)
        d["model_args"]["speakers_file"] = str(speakers_file.resolve())
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(d, f, indent=2)

# Import g2p_id and terbilang directly
sys.path.insert(0, str((ROOT_DIR / "TTS-Indonesia-Gratis").resolve()))
try:
    import g2p_id
    from g2p_id.scripts.terbilang import terbilang
    g2p = g2p_id.G2P()
except Exception as e:
    print(f"Warning initializing g2p_id: {e}")
    g2p = None
    terbilang = lambda n: str(n)

# Global in-memory synthesizer
SYNTHESIZER = None
SYNTHESIZER_LOADING = False
SYNTHESIS_LOCK = threading.Lock()
PIPER_VOICE = None
PIPER_LOAD_LOCK = threading.Lock()
PIPER_SYNTHESIS_LOCK = threading.Lock()


class PiperUnavailableError(RuntimeError):
    pass


def get_piper_voice():
    global PIPER_VOICE
    if PIPER_VOICE is not None:
        return PIPER_VOICE

    if not PIPER_MODEL_FILE.is_file() or not PIPER_CONFIG_FILE.is_file():
        raise PiperUnavailableError(
            "Model Piper belum terpasang. Jalankan scripts/download_piper_news_voice.py."
        )

    try:
        from piper import PiperVoice
    except ImportError as error:
        raise PiperUnavailableError(
            "Runtime Piper belum terpasang. Jalankan "
            ".venv_tts/bin/python3 -m pip install -r requirements-piper.txt."
        ) from error

    with PIPER_LOAD_LOCK:
        if PIPER_VOICE is None:
            PIPER_VOICE = PiperVoice.load(
                str(PIPER_MODEL_FILE),
                config_path=str(PIPER_CONFIG_FILE),
                use_cuda=False,
            )
    return PIPER_VOICE

def get_synthesizer():
    global SYNTHESIZER
    if SYNTHESIZER is None and MODEL_FILE.exists() and MODEL_FILE.stat().st_size > 300_000_000:
        try:
            try:
                import torch
                torch.set_num_threads(min(6, os.cpu_count() or 4))
            except Exception:
                pass
            from TTS.utils.synthesizer import Synthesizer
            print("⏳ Memuat model VITS ke RAM untuk inferensi ultra-cepat...")
            SYNTHESIZER = Synthesizer(
                tts_checkpoint=str(MODEL_FILE.resolve()),
                tts_config_path=str(CONFIG_FILE.resolve()),
                use_cuda=False
            )
            # Injeksi Karakter Kustom Kloning Tokoh & Anak-anak Lucu
            try:
                import torch
                sm = SYNTHESIZER.tts_model.speaker_manager
                emb_table = SYNTHESIZER.tts_model.emb_g.weight.data
                idx_jv04285 = sm.name_to_id.get("JV-04285", 14)
                idx_su08659 = sm.name_to_id.get("SU-08659", 75)
                idx_wibowo = sm.name_to_id.get("wibowo", 82)
                idx_jv3424 = sm.name_to_id.get("JV-03424", 11)
                idx_jv264 = sm.name_to_id.get("JV-00264", 1)
                idx_jv8736 = sm.name_to_id.get("JV-08736", 36)
                idx_jv7638 = sm.name_to_id.get("JV-07638", 30)
                idx_su3887 = sm.name_to_id.get("SU-03887", 60)
                idx_jv4679 = sm.name_to_id.get("JV-04679", 16)
                idx_jv1519 = sm.name_to_id.get("JV-01519", 4)
                idx_gadis  = sm.name_to_id.get("gadis", 81)
                idx_ardi   = sm.name_to_id.get("ardi", 80)

                # 1. Tokoh Orator / Prabowo: F0 ~110-116 Hz, Spectral Centroid ~1600-2000 Hz
                orator_emb = (0.38 * emb_table[idx_jv04285] + 0.37 * emb_table[idx_su08659] + 0.25 * emb_table[idx_wibowo]).unsqueeze(0)
                
                # 2. Tokoh Bersahaja / Jokowi (Terkalibrasi dari RVC & jokowi-orasi.mp3: F0 Mean ~194-196 Hz)
                # Blend: 40% JV-00264 (medok vokal tinggi) + 35% JV-01519 (tenor santun) + 25% wibowo (artikulasi wibawa)
                jkw_emb = (0.40 * emb_table[idx_jv264] + 0.35 * emb_table[idx_jv1519] + 0.25 * emb_table[idx_wibowo]).unsqueeze(0)

                # 3. Lala (Anak Perempuan Lucu & Menggemaskan): F0 ~318 Hz
                lala_emb = (0.55 * emb_table[idx_jv8736] + 0.45 * emb_table[idx_jv7638]).unsqueeze(0)

                # 4. Kiki (Anak Laki-Laki Cilik Ceria & Enerjik): F0 ~301 Hz
                kiki_emb = (0.50 * emb_table[idx_su3887] + 0.30 * emb_table[idx_jv4679] + 0.20 * emb_table[idx_ardi]).unsqueeze(0)

                idx_sari   = sm.name_to_id.get("JV-01392", 3)
                idx_tari   = sm.name_to_id.get("JV-02884", 8)

                # 5. Mimi (Balita Manis & Gemas): F0 ~300 Hz
                mimi_emb = (0.50 * emb_table[idx_jv8736] + 0.30 * emb_table[idx_gadis] + 0.20 * emb_table[idx_jv1519]).unsqueeze(0)

                # 6. Dewi (Narator Audiobook & Cerita Puitis StorySight): F0 ~219 Hz
                dewi_emb = (0.50 * emb_table[idx_gadis] + 0.35 * emb_table[idx_sari] + 0.15 * emb_table[idx_tari]).unsqueeze(0)

                new_weight = torch.cat([emb_table, orator_emb, jkw_emb, lala_emb, kiki_emb, mimi_emb, dewi_emb], dim=0)
                new_emb = torch.nn.Embedding(new_weight.shape[0], 256)
                new_emb.weight.data = new_weight
                SYNTHESIZER.tts_model.emb_g = new_emb

                n = new_weight.shape[0]
                sm.name_to_id["orator"] = n - 6
                sm.name_to_id["prabowo"] = n - 6
                sm.name_to_id["jokowi"] = n - 5
                sm.name_to_id["lala"] = n - 4
                sm.name_to_id["kiki"] = n - 3
                sm.name_to_id["mimi"] = n - 2
                sm.name_to_id["dewi"] = n - 1
                for spk in ("orator", "jokowi", "lala", "kiki", "mimi", "dewi"):
                    if spk not in sm.speaker_names:
                        sm.speaker_names.append(spk)
                print("✅ Karakter 'Orator', 'Jokowi', 3 Anak Lucu, & 'Dewi (Audiobook)' aktif!")
            except Exception as e:
                print(f"Peringatan registrasi karakter kloning tokoh: {e}")
            print("✅ Model VITS tersimpan di RAM, siap inferensi instan jernih!")
        except Exception as e:
            print(f"Peringatan memuat synthesizer in-memory: {e}")
            SYNTHESIZER = None
    return SYNTHESIZER

# Global RVC Voice Converter
RVC_CONVERTER = None

def get_rvc_converter():
    global RVC_CONVERTER
    if RVC_CONVERTER is None:
        model_p = ROOT_DIR / "models" / "rvc" / "jokowi" / "model.pth"
        index_p = ROOT_DIR / "models" / "rvc" / "jokowi" / "model.index"
        rmvpe_p = ROOT_DIR / "rmvpe.pt"
        if model_p.exists() and rmvpe_p.exists():
            try:
                from rvc_converter import RVCVoiceConverter
                print("⏳ Mengaktifkan RVC Neural Voice Converter untuk vokal autentik...")
                RVC_CONVERTER = RVCVoiceConverter(
                    model_path=str(model_p.resolve()),
                    index_path=str(index_p.resolve()) if index_p.exists() else None,
                    rmvpe_path=str(rmvpe_p.resolve())
                )
                print("✅ RVC Neural Voice Converter aktif di RAM!")
            except Exception as e:
                print(f"Peringatan memuat RVC Voice Converter: {e}")
    return RVC_CONVERTER

def process_tts_audio(wav, sample_rate, max_gain=None):
    import numpy as np

    audio = np.array(wav, dtype=np.float32)
    if audio.size == 0 or not np.isfinite(audio).all():
        raise ValueError("Audio TTS kosong atau berisi nilai non-finite.")

    # 1. Hapus DC offset
    audio = audio - np.mean(audio)

    # 1b. Pangkas hening mati (leading/trailing silence) bawaan VITS agar jeda antar kalimat rapat & natural
    mono_env = np.abs(audio) if audio.ndim == 1 else np.max(np.abs(audio), axis=1)
    peak_raw = float(np.max(mono_env)) if mono_env.size else 0.0
    if peak_raw > 1e-4:
        silence_thresh = max(0.008, peak_raw * 0.02)
        non_silent = np.flatnonzero(mono_env > silence_thresh)
        if non_silent.size > 0:
            pad_lead = int(sample_rate * 0.012)   # Sisakan 12ms saja di awal kalimat
            pad_trail = int(sample_rate * 0.035)  # Sisakan 35ms saja di akhir kalimat
            start_idx = max(0, int(non_silent[0]) - pad_lead)
            end_idx = min(len(audio), int(non_silent[-1]) + 1 + pad_trail)
            if end_idx - start_idx > int(sample_rate * 0.04):
                audio = audio[start_idx:end_idx]

    # 2. Soft-clipper tanh lembut untuk meredam lonjakan transien tanpa distorsi persegi
    threshold = 0.88
    over_mask = np.abs(audio) > threshold
    if np.any(over_mask):
        audio[over_mask] = np.sign(audio[over_mask]) * (
            threshold + (1.0 - threshold) * np.tanh((np.abs(audio[over_mask]) - threshold) / max(1e-4, (1.0 - threshold)))
        )

    # Target -2.1 dBFS leaves headroom for Web Audio resampling; max_gain caps boosts on quiet inputs.
    peak = np.max(np.abs(audio))
    if peak > 1e-4:
        gain = 0.78 / peak
        if max_gain is not None:
            gain = min(gain, max_gain)
        audio = audio * gain

    # 4. Micro fade-in dan fade-out kosinus lembut 8ms untuk menghilangkan klik batas segmen
    fade_len = int(sample_rate * 0.008)
    if len(audio) > fade_len * 2:
        fade_in = 0.5 * (1.0 - np.cos(np.linspace(0, np.pi, fade_len)))
        fade_out = 0.5 * (1.0 + np.cos(np.linspace(0, np.pi, fade_len)))
        fade_shape = (fade_len,) + (1,) * (audio.ndim - 1)
        audio[:fade_len] *= fade_in.reshape(fade_shape)
        audio[-fade_len:] *= fade_out.reshape(fade_shape)

    return audio


def master_audio_to_bytes(wav, sample_rate=22050):
    import numpy as np
    import scipy.io.wavfile

    audio = process_tts_audio(wav, sample_rate)
    pcm16 = np.clip(audio * 32767.0, -32767.0, 32767.0).astype(np.int16)
    buf = io.BytesIO()
    scipy.io.wavfile.write(buf, sample_rate, pcm16)
    return buf.getvalue()


def master_audio_with_clipper(wav, out_path, sample_rate=22050):
    import numpy as np
    import scipy.io.wavfile

    audio = process_tts_audio(wav, sample_rate)
    pcm16 = np.clip(audio * 32767.0, -32767.0, 32767.0).astype(np.int16)
    scipy.io.wavfile.write(out_path, sample_rate, pcm16)


def normalize_piper_wav(audio_bytes):
    import numpy as np
    import scipy.io.wavfile

    sample_rate, samples = scipy.io.wavfile.read(io.BytesIO(audio_bytes))
    if np.issubdtype(samples.dtype, np.floating):
        audio = samples.astype(np.float32)
    elif samples.dtype == np.uint8:
        audio = (samples.astype(np.float32) - 128.0) / 128.0
    elif np.issubdtype(samples.dtype, np.integer):
        limits = np.iinfo(samples.dtype)
        audio = samples.astype(np.float32) / max(abs(limits.min), limits.max)
    else:
        raise ValueError(f"Format sample WAV Piper tidak didukung: {samples.dtype}")

    audio = process_tts_audio(audio, sample_rate, max_gain=1.25)
    pcm16 = np.clip(audio * 32767.0, -32767.0, 32767.0).astype(np.int16)
    normalized_wav = io.BytesIO()
    scipy.io.wavfile.write(normalized_wav, sample_rate, pcm16)
    return normalized_wav.getvalue()

def ganti_angka(s):
    while True:
        match = re.search(r'\d+', s)
        if not match:
            return s
        angka = int(match.group(0))
        t = terbilang(angka)
        awal, akhir = match.span()
        s = s[:awal] + t + s[akhir:]

def ganti_persen(s):
    while True:
        i = s.find('%')
        if i < 0:
            return s
        s = s[:i] + ' persen' + s[i+1:]

def ganti_titik_dua(s):
    while True:
        match = re.search(r'\b\w+:', s)
        if not match:
            return s
        awal, akhir = match.span()
        s = s[:akhir-1] + ',' + s[akhir:]

def strip_stage_directions(text):
    text = str(text or '')
    # Hapus baris yang seluruhnya berupa petunjuk musik / panggung dalam tanda kurung () atau []
    text = re.sub(r'^\s*[\(\[][^\)\]]+[\)\]]\s*$', '', text, flags=re.MULTILINE)
    # Hapus petunjuk musik, sfx, jeda, audio di mana saja dalam tanda kurung
    text = re.sub(r'[\(\[][^\)\]]*(?:musik|music|audio|sfx|sound|efek|backsound|bgm|jeda|pause|volume|beat|upbeat|slow|fade|hening|tertawa|senyum|desah|berbisik|nada|vokal|intro|outro)[^\)\]]*[\)\]]', '', text, flags=re.IGNORECASE)
    # Hapus prefix nama pembicara & AI persona seperti Arsi:, EduVis:, Narator:, Guru:, Pembicara:
    text = re.sub(
        r'^\s*(?:\[|\*\*|\*)?\s*(?:arsi|eduvis|gemma(?:[-_ ]?\d+[a-z]*)?|ai|asisten|assistant|model|bot|konsultan|tutor|guru|pembicara|narator|narrator|suara|vo|voiceover|voice\s*over|jawaban|respon|response|gadis|ardi|wibowo|citra|bimo|sari|dimas|bayu|tari|juminten|asep|orator|jokowi|lala|kiki|mimi|dewi|piper|[a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+){0,3})\s*(?:\]|\*\*|\*)?\s*[:\-–]\s*',
        '',
        text,
        flags=re.IGNORECASE | re.MULTILINE,
    )
    # Hapus simbol formatting markdown
    text = re.sub(r'[*_#`]', '', text)
    return text.strip()

def text_normalization(content):
    content = strip_stage_directions(content)
    text_list = []
    for line in content.splitlines():
        line = line.strip()
        if not line:
            continue
        if line[-1] not in ['.', '?', '!']:
            line = line + '.'
        line = ganti_angka(line)
        line = ganti_persen(line)
        line = ganti_titik_dua(line)
        text_list.append(line)
    return '\n'.join(text_list)

SPEAKER_CONFIGS = {
    "gadis": {
        "speaker_idx": "gadis",
        "name": "Gadis — Perempuan Merdu & Elegan (ID)",
        "lang": "id-ID",
        "gender": "female",
        "desc": "Suara perempuan merdu, artikulatif, dan anggun.",
        "length_scale": 1.0,
        "noise_scale": 0.42,
        "noise_scale_dp": 0.42,
    },
    "ardi": {
        "speaker_idx": "ardi",
        "name": "Ardi — Pria Lembut & Bersahabat (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Suara laki-laki hangat, santai, dan bersahabat.",
        "length_scale": 1.0,
        "noise_scale": 0.40,
        "noise_scale_dp": 0.40,
    },
    "wibowo": {
        "speaker_idx": "wibowo",
        "name": "Wibowo — Pria Dewasa & Berwibawa (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Suara berat, karismatik, cocok untuk pidato dan narasi formal.",
        "length_scale": 0.96,
        "noise_scale": 0.36,
        "noise_scale_dp": 0.38,
    },
    "citra": {
        "speaker_idx": "JV-00658",
        "name": "Citra — Perempuan Ceria & Ekspresif (ID)",
        "lang": "id-ID",
        "gender": "female",
        "desc": "Suara wanita muda yang lincah, ekspresif, dan ceria.",
        "length_scale": 0.92,
        "noise_scale": 0.52,
        "noise_scale_dp": 0.48,
    },
    "bimo": {
        "speaker_idx": "SU-00600",
        "name": "Bimo — Narator Dokumenter & Tegas (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Vokal narator dokumenter dengan artikulasi tegas dan dalam.",
        "length_scale": 0.98,
        "noise_scale": 0.38,
        "noise_scale_dp": 0.40,
    },
    "sari": {
        "speaker_idx": "JV-01392",
        "name": "Sari — Pengajar Lembut & Artikulatif (ID)",
        "lang": "id-ID",
        "gender": "female",
        "desc": "Vokal guru instruktur yang sabar, lembut, dan jelas.",
        "length_scale": 1.04,
        "noise_scale": 0.38,
        "noise_scale_dp": 0.40,
    },
    "dimas": {
        "speaker_idx": "SU-01038",
        "name": "Dimas — Pemuda Santai & Kasual (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Gaya bicara santai sehari-hari, santai dan modern.",
        "length_scale": 1.0,
        "noise_scale": 0.45,
        "noise_scale_dp": 0.45,
    },
    "bayu": {
        "speaker_idx": "SU-02092",
        "name": "Bayu — Pemuda Cerdas & Enerjik (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Intonasi cerdas, optimis, dan bersemangat.",
        "length_scale": 0.94,
        "noise_scale": 0.48,
        "noise_scale_dp": 0.48,
    },
    "tari": {
        "speaker_idx": "JV-02884",
        "name": "Tari — Gadis Remaja & Ramah (ID)",
        "lang": "id-ID",
        "gender": "female",
        "desc": "Suara cerah, berseri-seri, dan penuh kehangatan.",
        "length_scale": 0.95,
        "noise_scale": 0.50,
        "noise_scale_dp": 0.48,
    },
    "JV-00264": {
        "speaker_idx": "JV-00264",
        "name": "Juminten — Logat Jawa Medok Autentik (JV)",
        "lang": "jv-ID",
        "gender": "female",
        "desc": "Dialek Jawa medok yang khas, ramah, dan bersahaja.",
        "length_scale": 1.0,
        "noise_scale": 0.45,
        "noise_scale_dp": 0.45,
    },
    "SU-00060": {
        "speaker_idx": "SU-00060",
        "name": "Asep — Logat Sunda Akang Ramah (SU)",
        "lang": "su-ID",
        "gender": "male",
        "desc": "Dialek Sunda akrab, luwes, dan bersahabat.",
        "length_scale": 1.0,
        "noise_scale": 0.45,
        "noise_scale_dp": 0.45,
    },
    "orator": {
        "speaker_idx": "orator",
        "name": "Orator — Karismatik, Tegas & Menggelegar (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Tiruan vokal orasi tegas, karismatik, berapi-api, dan berwibawa tinggi.",
        "length_scale": 0.90,
        "noise_scale": 0.54,
        "noise_scale_dp": 0.50,
    },
    "jokowi": {
        "speaker_idx": "jokowi",
        "name": "Jokowi — RVC Neural 40kHz Asli (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Kloning vokal 100% autentik berbasis model RVC neural 175 epoch & retrieval FAISS 40kHz.",
        "length_scale": 1.06,
        "noise_scale": 0.38,
        "noise_scale_dp": 0.38,
    },
    "lala": {
        "speaker_idx": "lala",
        "name": "Lala — Anak Perempuan Lucu & Imut (ID)",
        "lang": "id-ID",
        "gender": "female",
        "desc": "Suara anak perempuan ceria, imut, menggemaskan, nada tinggi manis.",
        "length_scale": 0.90,
        "noise_scale": 0.58,
        "noise_scale_dp": 0.55,
    },
    "kiki": {
        "speaker_idx": "kiki",
        "name": "Kiki — Bocah Laki-laki Ceria & Enerjik (ID)",
        "lang": "id-ID",
        "gender": "male",
        "desc": "Suara bocah laki-laki polos, ceria, enerjik, penuh rasa ingin tahu.",
        "length_scale": 0.88,
        "noise_scale": 0.60,
        "noise_scale_dp": 0.52,
    },
    "mimi": {
        "speaker_idx": "mimi",
        "name": "Mimi — Balita Gemas & Manis (ID)",
        "lang": "id-ID",
        "gender": "female",
        "desc": "Suara si kecil balita lucu yang menggemaskan, lembut, dan manja.",
        "length_scale": 0.95,
        "noise_scale": 0.64,
        "noise_scale_dp": 0.58,
    },
    "dewi": {
        "speaker_idx": "dewi",
        "name": "Dewi — Narator Audiobook & Puitis (ID)",
        "lang": "id-ID",
        "gender": "female",
        "desc": "Vokal narator audiobook lembut, hangat, puitis, dan penuh penghayatan rasa.",
        "length_scale": 1.08,
        "noise_scale": 0.36,
        "noise_scale_dp": 0.40,
    },
    "piper-news": {
        "speaker_idx": "piper-news",
        "name": "News TTS — Narator Berita Piper (ID)",
        "lang": "id-ID",
        "gender": "unknown",
        "desc": "Suara tunggal Bahasa Indonesia dari model Piper medium Q8.",
        "length_scale": 1.0,
        "noise_scale": 0.667,
        "noise_scale_dp": 0.8,
    },
}
SPEAKER_CONFIGS["juminten"] = SPEAKER_CONFIGS["JV-00264"]
SPEAKER_CONFIGS["asep"] = SPEAKER_CONFIGS["SU-00060"]
SPEAKER_CONFIGS["prabowo"] = SPEAKER_CONFIGS["orator"]

STYLE_MODIFIERS = {
    "natural": {"len": 1.0, "noise": 1.0, "dp": 1.0},
    "cheerful": {"len": 0.92, "noise": 1.25, "dp": 1.20},
    "formal": {"len": 1.04, "noise": 0.85, "dp": 0.90},
    "calm": {"len": 1.12, "noise": 0.75, "dp": 0.85},
    "expressive": {"len": 0.94, "noise": 1.30, "dp": 1.25},
}

SPEAKERS = [
    {"id": k, "name": v["name"], "lang": v["lang"], "gender": v["gender"], "desc": v["desc"]}
    for k, v in SPEAKER_CONFIGS.items() if k not in ("juminten", "asep", "prabowo")
]

PORT = 8765
AUDIO_CACHE = {}  # In-memory LRU cache for ultra-low latency TTS

class TTSRequestHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path == "/api/health":
            self.send_response(200)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            ready = MODEL_FILE.exists() and MODEL_FILE.stat().st_size > 300_000_000
            resp = {
                "status": "ok",
                "model_ready": ready,
                "synthesizer_ready": SYNTHESIZER is not None and not SYNTHESIZER_LOADING,
                "synthesizer_loading": SYNTHESIZER_LOADING,
                "piper_model_ready": PIPER_MODEL_FILE.is_file() and PIPER_CONFIG_FILE.is_file(),
                "piper_voice_ready": PIPER_VOICE is not None,
                "model_path": str(MODEL_FILE),
                "model_size_mb": round(MODEL_FILE.stat().st_size / (1024 * 1024), 1) if MODEL_FILE.exists() else 0,
                "model_target_mb": 329.0
            }
            self.wfile.write(json.dumps(resp).encode("utf-8"))
            return

        elif path == "/api/speakers":
            self.send_response(200)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(SPEAKERS).encode("utf-8"))
            return

        elif path == "/api/tts":
            text = query.get("text", [""])[0]
            speaker = query.get("speaker", ["gadis"])[0]
            style = query.get("style", ["natural"])[0]
            try:
                speed = float(query.get("speed", ["1.0"])[0])
            except (ValueError, TypeError):
                speed = 1.0
            self.handle_tts(text, speaker, style=style, speed=speed)
            return

        else:
            # Serve static files from ROOT_DIR (e.g. tts_studio_lokal.html, gemini_live.html, images)
            clean_path = path.lstrip("/")
            if not clean_path:
                clean_path = "tts_studio_lokal.html"
            file_path = (ROOT_DIR / clean_path).resolve()
            if file_path.is_file() and (ROOT_DIR in file_path.parents or file_path == ROOT_DIR):
                ext = file_path.suffix.lower()
                mime_types = {
                    ".html": "text/html; charset=utf-8",
                    ".js": "application/javascript; charset=utf-8",
                    ".css": "text/css; charset=utf-8",
                    ".json": "application/json",
                    ".png": "image/png",
                    ".jpg": "image/jpeg",
                    ".jpeg": "image/jpeg",
                    ".svg": "image/svg+xml",
                    ".ico": "image/x-icon",
                    ".wav": "audio/wav",
                    ".mp3": "audio/mpeg",
                    ".webmanifest": "application/manifest+json",
                }
                content_type = mime_types.get(ext, "application/octet-stream")
                try:
                    content = file_path.read_bytes()
                    self.send_response(200)
                    self._send_cors_headers()
                    self.send_header("Content-Type", content_type)
                    self.send_header("Content-Length", str(len(content)))
                    if ext in {".html", ".js"}:
                        self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                    self.wfile.write(content)
                    return
                except Exception as e:
                    self.send_response(500)
                    self._send_cors_headers()
                    self.end_headers()
                    self.wfile.write(str(e).encode())
                    return
            self.send_response(404)
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(b"Not Found")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/api/tts":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            try:
                data = json.loads(body.decode("utf-8"))
                text = data.get("text", "")
                speaker = data.get("speaker", "gadis")
                style = data.get("style", "natural")
                speed = float(data.get("speed", 1.0))
            except Exception:
                text = ""
                speaker = "gadis"
                style = "natural"
                speed = 1.0
            self.handle_tts(text, speaker, style=style, speed=speed)
        else:
            self.send_response(404)
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(b"Not Found")

    def handle_tts(self, text, speaker="gadis", style="natural", speed=1.0):
        if not text:
            self.send_response(400)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Parameter text diperlukan"}).encode("utf-8"))
            return

        if speaker == "piper-news":
            self.handle_piper_tts(text, style=style, speed=speed)
            return

        cfg = SPEAKER_CONFIGS.get(speaker, SPEAKER_CONFIGS.get("gadis"))
        target_speaker_idx = cfg["speaker_idx"]

        style_mod = STYLE_MODIFIERS.get(style.lower(), STYLE_MODIFIERS["natural"])
        target_len = float(cfg["length_scale"] * style_mod["len"] / max(0.5, min(2.0, float(speed))))
        target_noise = float(cfg["noise_scale"] * style_mod["noise"])
        target_dp = float(cfg["noise_scale_dp"] * style_mod["dp"])

        cache_key = (speaker, style.lower(), round(float(speed), 2), text.strip())
        if cache_key in AUDIO_CACHE:
            audio_bytes = AUDIO_CACHE[cache_key]
            self.send_response(200)
            self._send_cors_headers()
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(audio_bytes)))
            self.end_headers()
            self.wfile.write(audio_bytes)
            return

        if not MODEL_FILE.exists() or MODEL_FILE.stat().st_size < 300_000_000:
            self.send_response(503)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            downloaded = round(MODEL_FILE.stat().st_size / (1024 * 1024), 1) if MODEL_FILE.exists() else 0
            self.wfile.write(json.dumps({"error": f"Model TTS Indonesia sedang diunduh ({downloaded}/329 MB)..."}).encode("utf-8"))
            return

        try:
            normalized = text_normalization(text)
            phonemes = g2p(normalized) if g2p else normalized

            synth = SYNTHESIZER
            if SYNTHESIZER_LOADING:
                self.send_response(503)
                self._send_cors_headers()
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": "Model TTS sedang disiapkan; coba lagi sebentar."}).encode("utf-8"))
                return

            audio_bytes = None
            if synth is not None:
                import torch
                with SYNTHESIS_LOCK, torch.inference_mode():
                    if hasattr(synth, "tts_model") and synth.tts_model is not None:
                        synth.tts_model.length_scale = target_len
                        synth.tts_model.noise_scale = target_noise
                        synth.tts_model.noise_scale_dp = target_dp
                    if target_speaker_idx == "jokowi":
                        # Gunakan basis suara manusia alami (wibowo) sebelum dikonversi RVC untuk menghindari resonansi robotik
                        wav = synth.tts(phonemes, speaker_name="wibowo", split_sentences=False)
                        rvc = get_rvc_converter()
                        if rvc is not None:
                            try:
                                rvc_wav, rvc_sr = rvc.convert(wav, sr=22050, f0_up_key=2, index_rate=0.75, filter_radius=3, rms_mix_rate=0.25)
                                audio_bytes = master_audio_to_bytes(rvc_wav, sample_rate=rvc_sr)
                            except Exception as e:
                                print(f"Error inferensi RVC Jokowi: {e}")
                                audio_bytes = master_audio_to_bytes(wav)
                        else:
                            audio_bytes = master_audio_to_bytes(wav)
                    else:
                        wav = synth.tts(phonemes, speaker_name=target_speaker_idx, split_sentences=False)
                        audio_bytes = master_audio_to_bytes(wav)
            else:
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                    out_wav = tmp.name
                if target_speaker_idx in ("orator", "prabowo", "jokowi"):
                    cli_spk = "wibowo"
                elif target_speaker_idx in ("lala", "mimi", "dewi"):
                    cli_spk = "gadis"
                elif target_speaker_idx == "kiki":
                    cli_spk = "ardi"
                else:
                    cli_spk = target_speaker_idx
                cmd = [
                    str(BIN_TTS.resolve()),
                    "--text", phonemes,
                    "--model_path", str(MODEL_FILE.resolve()),
                    "--config_path", str(CONFIG_FILE.resolve()),
                    "--speaker_idx", cli_spk,
                    "--out_path", out_wav
                ]
                env = os.environ.copy()
                env["MPLCONFIGDIR"] = "/tmp/matplotlib"
                env["NUMBA_CACHE_DIR"] = "/tmp/numba"
                res = subprocess.run(cmd, env=env, capture_output=True, text=True)
                if res.returncode != 0 or not os.path.exists(out_wav):
                    err_msg = res.stderr or res.stdout or "Gagal inferensi audio"
                    self.send_response(500)
                    self._send_cors_headers()
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": err_msg}).encode("utf-8"))
                    return
                try:
                    import scipy.io.wavfile
                    sr, raw_data = scipy.io.wavfile.read(out_wav)
                    audio_bytes = master_audio_to_bytes(raw_data.astype(np.float32) / 32768.0, sample_rate=sr)
                except Exception:
                    with open(out_wav, "rb") as f:
                        audio_bytes = f.read()
                try:
                    os.remove(out_wav)
                except OSError:
                    pass

            if len(AUDIO_CACHE) > 256:
                for k in list(AUDIO_CACHE.keys())[:32]:
                    AUDIO_CACHE.pop(k, None)
            AUDIO_CACHE[cache_key] = audio_bytes

            self.send_response(200)
            self._send_cors_headers()
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(audio_bytes)))
            self.end_headers()
            self.wfile.write(audio_bytes)

        except Exception as e:
            self.send_response(500)
            self._send_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode("utf-8"))

    def handle_piper_tts(self, text, style="natural", speed=1.0):
        style_key = style.lower()
        style_mod = STYLE_MODIFIERS.get(style_key, STYLE_MODIFIERS["natural"])
        speed_value = max(0.5, min(2.0, float(speed)))
        cache_key = ("piper-news", style_key, round(speed_value, 2), text.strip())

        audio_bytes = AUDIO_CACHE.get(cache_key)
        if audio_bytes is None:
            try:
                voice = get_piper_voice()
                from piper import SynthesisConfig

                cfg = SPEAKER_CONFIGS["piper-news"]
                synthesis_config = SynthesisConfig(
                    length_scale=cfg["length_scale"] * style_mod["len"] / speed_value,
                    noise_scale=cfg["noise_scale"] * style_mod["noise"],
                    noise_w_scale=cfg["noise_scale_dp"] * style_mod["dp"],
                )
                audio_buffer = io.BytesIO()
                with PIPER_SYNTHESIS_LOCK:
                    with wave.open(audio_buffer, "wb") as wav_file:
                        voice.synthesize_wav(
                            text_normalization(text),
                            wav_file,
                            syn_config=synthesis_config,
                        )
                audio_bytes = audio_buffer.getvalue()
                if len(audio_bytes) <= 44 or audio_bytes[:4] != b"RIFF":
                    raise RuntimeError("Piper tidak menghasilkan file WAV yang valid.")
                audio_bytes = normalize_piper_wav(audio_bytes)

                if len(AUDIO_CACHE) > 256:
                    for key in list(AUDIO_CACHE.keys())[:32]:
                        AUDIO_CACHE.pop(key, None)
                AUDIO_CACHE[cache_key] = audio_bytes
            except PiperUnavailableError as error:
                self.send_response(503)
                self._send_cors_headers()
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(error)}).encode("utf-8"))
                return
            except Exception as error:
                self.send_response(500)
                self._send_cors_headers()
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": f"Gagal sintesis Piper: {error}"}).encode("utf-8"))
                return

        self.send_response(200)
        self._send_cors_headers()
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(audio_bytes)))
        self.end_headers()
        self.wfile.write(audio_bytes)

class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def server_bind(self):
        import socket
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            try:
                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
            except OSError:
                pass
        super().server_bind()

def main():
    global SYNTHESIZER_LOADING
    server_address = ("127.0.0.1", PORT)
    httpd = ReusableHTTPServer(server_address, TTSRequestHandler)
    print(f"🚀 EduVis Local TTS Indonesia Server aktif di http://127.0.0.1:{PORT}")
    print(f"📌 Health: http://127.0.0.1:{PORT}/api/health")
    print(f"📌 Speakers: http://127.0.0.1:{PORT}/api/speakers")
    if MODEL_FILE.exists() and MODEL_FILE.stat().st_size > 300_000_000:
        SYNTHESIZER_LOADING = True
        threading.Thread(
            target=warm_synthesizer,
            name="tts-model-warmup",
            daemon=True,
        ).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer dihentikan.")
        httpd.server_close()

def warm_synthesizer():
    global SYNTHESIZER_LOADING
    try:
        get_synthesizer()
    finally:
        SYNTHESIZER_LOADING = False

if __name__ == "__main__":
    main()
