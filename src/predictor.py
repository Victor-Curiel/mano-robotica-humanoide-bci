"""Prediccion continua con ventana deslizante."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import torch

from . import config as cfg
from .feature_extraction import extract_features, is_valid_window
from .model import BCINet, predict_proba
from .utils import apply_zscore, load_stats


class SlidingWindowPredictor:
    def __init__(self, model_path: Path = cfg.MODEL_PATH, stats_path: Path = cfg.STATS_PATH):
        self.model = BCINet()
        self.model.load_state_dict(torch.load(model_path, map_location="cpu", weights_only=True))
        self.model.eval()
        self.mu, self.sigma, _ = load_stats(stats_path)

    def predict_window(self, window: np.ndarray, fs: float) -> tuple[int, float]:
        """Clase y confianza para una ventana [3, n]. Ventana invalida -> (0, 0.0)."""
        if not is_valid_window(window):
            return cfg.CLASS_LEFT, 0.0
        x = apply_zscore(extract_features(window, fs), self.mu, self.sigma)
        p = predict_proba(self.model, x[None, :])[0]
        cls = int(p.argmax())
        return cls, float(p[cls])

    def predict_continuous(
        self, signal: np.ndarray, fs: float,
        window_secs: float = cfg.WINDOW_SECS, step_secs: float = cfg.STEP_SECS,
    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """signal [3, N] en uV (C3, C4, Cz) ya filtrada. Devuelve (clases, confianzas, tiempos_inicio_s)."""
        win, step = int(round(window_secs * fs)), int(round(step_secs * fs))
        starts = range(0, signal.shape[1] - win + 1, step)
        out = [self.predict_window(signal[:, s:s + win], fs) for s in starts]
        if not out:
            return np.array([], int), np.array([]), np.array([])
        cls, conf = zip(*out)
        return np.array(cls), np.array(conf), np.array(list(starts)) / fs
