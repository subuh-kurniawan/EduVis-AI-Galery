import io
import sys
import unittest
from pathlib import Path

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import tts_server


class PiperAudioNormalizationTests(unittest.TestCase):
    def test_piper_wav_is_normalized_with_peak_headroom(self):
        sample_rate = 22050
        time = np.arange(sample_rate, dtype=np.float32) / sample_rate
        samples = (np.sin(2 * np.pi * 440 * time) * 30000).astype(np.int16)
        source = io.BytesIO()
        wavfile.write(source, sample_rate, samples)

        normalized = tts_server.normalize_piper_wav(source.getvalue())
        output_rate, output = wavfile.read(io.BytesIO(normalized))

        self.assertEqual(output_rate, sample_rate)
        self.assertEqual(output.dtype, np.int16)
        self.assertLessEqual(np.max(np.abs(output.astype(np.int32))) / 32768, 0.781)

    def test_quiet_piper_audio_is_not_boosted_without_limit(self):
        sample_rate = 22050
        time = np.arange(sample_rate, dtype=np.float32) / sample_rate
        samples = (np.sin(2 * np.pi * 440 * time) * 1000).astype(np.int16)
        source = io.BytesIO()
        wavfile.write(source, sample_rate, samples)

        normalized = tts_server.normalize_piper_wav(source.getvalue())
        _, output = wavfile.read(io.BytesIO(normalized))

        input_peak = np.max(np.abs(samples.astype(np.int32)))
        output_peak = np.max(np.abs(output.astype(np.int32)))
        self.assertLessEqual(output_peak, input_peak * 1.26)


if __name__ == "__main__":
    unittest.main()
