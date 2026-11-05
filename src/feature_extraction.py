"""Extraccion de caracteristicas 9D: Welch + Burg + Wavelet D4 (C3, C4, Cz).

Orden del vector: [Welch C3,C4,Cz | Burg C3,C4,Cz | Wavelet C3,C4,Cz].
Referencia: MODULO_BATCH_EXTRACCION_WELCH_Y_BURG_50TRASLAPE_PLOT.m
"""
from __future__ import annotations

import numpy as np
import pywt
from scipy.signal import welch

from . import config as cfg


def matlab_hanning(n: int) -> np.ndarray:
    """Equivalente a hanning(n) de MATLAB (simetrica, sin ceros en los extremos)."""
    return np.hanning(n + 2)[1:-1]


def welch_psd(x: np.ndarray, fs: float, seg_secs: float = cfg.WELCH_SEG_SECS):
    """PSD de Welch (ventana Hanning MATLAB, 50 % traslape). Devuelve (f, pxx)."""
    nperseg = min(int(round(seg_secs * fs)), len(x))
    nfft = int(cfg.NFFT_FACTOR * fs)
    return welch(
        x, fs=fs, window=matlab_hanning(nperseg), noverlap=nperseg // 2,
        nfft=nfft, detrend=False, scaling="density",
    )


def burg_coefficients(x: np.ndarray, order: int) -> tuple[np.ndarray, float]:
    """Metodo de Burg. Devuelve (a, var) con a = [1, a1..ap] y varianza del ruido."""
    x = np.asarray(x, dtype=float)
    n = len(x)
    if order >= n:
        raise ValueError("orden AR debe ser menor que la longitud de la senal")
    f = x.copy()
    b = x.copy()
    a = np.array([1.0])
    err = float(x @ x) / n
    for _ in range(order):
        fp, bp = f[1:], b[:-1]
        den = fp @ fp + bp @ bp
        k = -2.0 * (fp @ bp) / den if den > 0 else 0.0
        a = np.append(a, 0.0)
        a = a + k * a[::-1]
        f, b = fp + k * bp, bp + k * fp
        err *= 1.0 - k * k
    return a, err


def burg_psd(x: np.ndarray, fs: float, order: int = cfg.BURG_ORDER):
    """PSD AR por Burg, unilateral (equivalente a pburg). Devuelve (f, pxx)."""
    nfft = int(cfg.NFFT_FACTOR * fs)
    a, err = burg_coefficients(x, order)
    h = np.fft.rfft(a, nfft)
    pxx = err / fs / (np.abs(h) ** 2)
    pxx[1:-1] *= 2.0  # unilateral (nfft par: DC y Nyquist no se duplican)
    return np.fft.rfftfreq(nfft, 1.0 / fs), pxx


def bandpower(pxx: np.ndarray, f: np.ndarray, band=cfg.BAND) -> float:
    """Potencia integrada (trapecio) en la banda [f_min, f_max]."""
    idx = (f >= band[0]) & (f <= band[1])
    return float(np.trapezoid(pxx[idx], f[idx]))


def wavelet_energy(x: np.ndarray, wavelet: str = cfg.WAVELET, level: int = cfg.WAVELET_LEVEL) -> float:
    """Energia media del detalle D<level>. pywt devuelve [cA_n, cD_n, ..., cD_1]."""
    d = pywt.wavedec(x, wavelet, level=level)[1]
    return float(np.sum(d ** 2) / len(d))


def is_valid_window(x_3ch: np.ndarray) -> bool:
    """Equivale al 'escudo anti-crash' de MATLAB."""
    return bool(
        np.all(np.isfinite(x_3ch)) and np.all(np.var(x_3ch, axis=1) >= cfg.MIN_VARIANCE)
    )


def extract_features(x_3ch: np.ndarray, fs: float) -> np.ndarray:
    """Vector de 9 caracteristicas a partir de [3, n_muestras] (C3, C4, Cz) en uV."""
    x_3ch = np.asarray(x_3ch, dtype=float)
    if x_3ch.ndim != 2 or x_3ch.shape[0] != 3:
        raise ValueError(f"se esperaba forma [3, n], se obtuvo {x_3ch.shape}")
    welch_p = [bandpower(*reversed(welch_psd(ch, fs))) for ch in x_3ch]
    burg_p = [bandpower(*reversed(burg_psd(ch, fs))) for ch in x_3ch]
    wav_p = [wavelet_energy(ch) for ch in x_3ch]
    return np.array(welch_p + burg_p + wav_p)
