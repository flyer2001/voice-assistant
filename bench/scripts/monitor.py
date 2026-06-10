"""monitor.py — HW sampling utility для STT/Gemma бенчмарка.

Cross-platform (Win + Linux + macOS). Запускает sampling thread параллельно с inference,
собирает per-second snapshots CPU%, RSS, и (если nvidia-smi доступен) VRAM/GPU util/power/temp.

Usage:
    from monitor import HardwareMonitor
    with HardwareMonitor(interval_s=1.0) as mon:
        result = model.transcribe(audio_file)
    metrics = mon.summary()  # {ram_peak_mb, cpu_avg_pct, vram_peak_mb, gpu_util_avg_pct, ...}
"""

from __future__ import annotations

import os
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from typing import Optional

try:
    import psutil
except ImportError:
    psutil = None


@dataclass
class Sample:
    t_s: float
    cpu_pct: float
    ram_mb: float
    vram_mb: Optional[float] = None
    gpu_util_pct: Optional[float] = None
    gpu_power_w: Optional[float] = None
    gpu_temp_c: Optional[float] = None


@dataclass
class HardwareMonitor:
    interval_s: float = 0.1  # 100ms — enough samples for short STT inference (~200-800ms)
    gpu_index: int = 0
    samples: list[Sample] = field(default_factory=list)
    _stop_event: threading.Event = field(default_factory=threading.Event)
    _thread: Optional[threading.Thread] = None
    _has_nvidia_smi: bool = False
    _process: object = None

    def __post_init__(self):
        if psutil is None:
            raise RuntimeError("psutil required: pip install psutil")
        self._process = psutil.Process(os.getpid())
        self._process.cpu_percent(interval=None)  # prime, first call returns 0
        self._has_nvidia_smi = shutil.which("nvidia-smi") is not None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *exc):
        self.stop()

    def start(self):
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=5.0)

    def _loop(self):
        t0 = time.monotonic()
        while not self._stop_event.wait(self.interval_s):
            sample = Sample(
                t_s=time.monotonic() - t0,
                cpu_pct=self._process.cpu_percent(interval=None),
                ram_mb=self._process.memory_info().rss / 1024 / 1024,
            )
            if self._has_nvidia_smi:
                gpu = self._read_nvidia_smi()
                if gpu:
                    sample.vram_mb, sample.gpu_util_pct, sample.gpu_power_w, sample.gpu_temp_c = gpu
            self.samples.append(sample)

    def _read_nvidia_smi(self) -> Optional[tuple[float, float, float, float]]:
        try:
            out = subprocess.run(
                [
                    "nvidia-smi",
                    f"--id={self.gpu_index}",
                    "--query-gpu=memory.used,utilization.gpu,power.draw,temperature.gpu",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=2.0,
                check=True,
            )
            parts = [p.strip() for p in out.stdout.strip().split(",")]
            return float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])
        except (subprocess.SubprocessError, ValueError, IndexError):
            return None

    def summary(self) -> dict:
        if not self.samples:
            return {"samples": 0}

        def _peak(attr: str) -> Optional[float]:
            vals = [getattr(s, attr) for s in self.samples if getattr(s, attr) is not None]
            return max(vals) if vals else None

        def _avg(attr: str) -> Optional[float]:
            vals = [getattr(s, attr) for s in self.samples if getattr(s, attr) is not None]
            return sum(vals) / len(vals) if vals else None

        result = {
            "samples": len(self.samples),
            "duration_s": self.samples[-1].t_s,
            "ram_peak_mb": _peak("ram_mb"),
            "ram_avg_mb": _avg("ram_mb"),
            "cpu_avg_pct": _avg("cpu_pct"),
            "cpu_peak_pct": _peak("cpu_pct"),
        }
        if self._has_nvidia_smi:
            result.update({
                "vram_peak_mb": _peak("vram_mb"),
                "vram_avg_mb": _avg("vram_mb"),
                "gpu_util_avg_pct": _avg("gpu_util_pct"),
                "gpu_util_peak_pct": _peak("gpu_util_pct"),
                "gpu_power_avg_w": _avg("gpu_power_w"),
                "gpu_temp_max_c": _peak("gpu_temp_c"),
            })
        return result


if __name__ == "__main__":
    # Self-test: monitor for 3 seconds while doing some work
    import math
    with HardwareMonitor(interval_s=0.5) as mon:
        for _ in range(3_000_000):
            math.sqrt(12345.6789)
    print(mon.summary())
