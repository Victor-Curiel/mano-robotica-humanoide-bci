"""Utilidades: outliers IQR y normalizacion z-score."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np


def iqr_outlier_mask(X: np.ndarray, k: float = 1.5) -> np.ndarray:
    """True en filas con algun valor fuera de [Q1 - k*IQR, Q3 + k*IQR] (isoutlier 'quartiles')."""
    q1, q3 = np.percentile(X, [25, 75], axis=0)
    iqr = q3 - q1
    return np.any((X < q1 - k * iqr) | (X > q3 + k * iqr), axis=1)


def fit_zscore(X: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """mu y sigma poblacional (std(.,1) de MATLAB). sigma=0 se reemplaza por 1."""
    mu = X.mean(axis=0)
    sigma = X.std(axis=0)
    sigma = np.where(sigma < 1e-12, 1.0, sigma)
    return mu, sigma


def apply_zscore(X: np.ndarray, mu: np.ndarray, sigma: np.ndarray) -> np.ndarray:
    return (X - mu) / sigma


def save_stats(path: Path, mu: np.ndarray, sigma: np.ndarray, meta: dict | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"mu": mu.tolist(), "sigma": sigma.tolist(), **(meta or {})}
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def load_stats(path: Path) -> tuple[np.ndarray, np.ndarray, dict]:
    d = json.loads(Path(path).read_text(encoding="utf-8"))
    return np.array(d["mu"]), np.array(d["sigma"]), d
