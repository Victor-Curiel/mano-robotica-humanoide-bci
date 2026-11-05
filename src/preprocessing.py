"""Carga de EEG (.set / .cdt) y construccion del dataset de entrenamiento."""
from __future__ import annotations

import re
import warnings
from pathlib import Path

import mne
import numpy as np

from . import config as cfg
from .feature_extraction import extract_features, is_valid_window

UV = 1e6  # MNE trabaja en Volts; MATLAB/EEGLAB en uV. Se normaliza a uV.


def _pick_channels(inst, names=cfg.CHANNELS) -> np.ndarray:
    upper = [c.upper() for c in inst.ch_names]
    idx = []
    for name in names:
        if name.upper() not in upper:
            raise ValueError(f"canal {name} no encontrado en {inst.ch_names}")
        idx.append(upper.index(name.upper()))
    return np.array(idx)


def load_set_epochs(path: str | Path) -> tuple[np.ndarray, float]:
    """Carga un .set ya segmentado en epocas. Devuelve ([n_ep, 3, n], fs) en uV."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        ep = mne.io.read_epochs_eeglab(str(path), verbose=False)
    data = ep.get_data()[:, _pick_channels(ep), :] * UV
    return data, float(ep.info["sfreq"])


def load_continuous(path: str | Path, band=cfg.BAND, filter_signal: bool = True) -> tuple[np.ndarray, float]:
    """Carga registro continuo (.set o .cdt) y devuelve ([3, n], fs) en uV.

    Si filter_signal, aplica FIR pasabanda (equivalente a pop_eegfilt, banda cfg.BAND).
    """
    path = Path(path)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        if path.suffix.lower() == ".cdt":
            raw = mne.io.read_raw_curry(str(path), preload=True, verbose=False)
        else:
            raw = mne.io.read_raw_eeglab(str(path), preload=True, verbose=False)
    idx = _pick_channels(raw)
    raw.pick([raw.ch_names[i] for i in idx])
    if filter_signal:
        raw.filter(band[0], band[1], method="fir", phase="zero", verbose=False)
    return raw.get_data() * UV, float(raw.info["sfreq"])


_SESSION_RE = re.compile(r"_([A-Za-z]+\d{6})-\d+", re.IGNORECASE)


def session_id(path: str | Path) -> str:
    """Identificador de sujeto/sesion tomado del nombre (p.ej. MD_marco020326-1 -> marco020326)."""
    m = _SESSION_RE.search(Path(path).name)
    return m.group(1).lower() if m else Path(path).stem.lower()


def build_dataset(
    dirs: dict[int, Path] | None = None, verbose: bool = True
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Devuelve X [n, 9], y [n] (0 basal, 1 apretar, 2 estirar) y groups [n] (sesion)."""
    dirs = dirs or cfg.DATA_DIRS
    X, y, groups = [], [], []
    for label, folder in sorted(dirs.items()):
        files = sorted(Path(folder).glob("*.set"))
        if not files:
            raise FileNotFoundError(f"sin archivos .set en {folder}")
        n_skipped = 0
        for f in files:
            data, fs = load_set_epochs(f)
            for epoch in data:
                if not is_valid_window(epoch):
                    n_skipped += 1
                    continue
                X.append(extract_features(epoch, fs))
                y.append(label)
                groups.append(session_id(f))
        if verbose:
            print(f"{cfg.CLASS_NAMES[label]}: {len(files)} archivos, {n_skipped} epocas descartadas")
    return np.array(X), np.array(y), np.array(groups)
