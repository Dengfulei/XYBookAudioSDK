"""生成确定性、低音量的四秒 PCM 测试音频，不使用外部受版权保护的内容。"""
import math
from pathlib import Path
import struct
import wave

SAMPLE_RATE = 22050
DURATION_SECONDS = 4
AMPLITUDE = 1800
for chapter, frequency in enumerate((220, 330, 440), start=1):
    path = Path(__file__).resolve().parents[1] / "DemoResources" / "Fixture" / f"chapter-{chapter}.wav"
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, SAMPLE_RATE, 0, "NONE", "not compressed"))
        frames = []
        for sample in range(SAMPLE_RATE * DURATION_SECONDS):
            seconds = sample / SAMPLE_RATE
            envelope = min(1, seconds * 8, (DURATION_SECONDS - seconds) * 8)
            frames.append(struct.pack("<h", round(AMPLITUDE * envelope * math.sin(2 * math.pi * frequency * seconds))))
        output.writeframes(b"".join(frames))
