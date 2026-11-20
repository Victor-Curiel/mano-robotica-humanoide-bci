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


def load_for_view(path: str | Path, emg_channel: str | None = cfg.EMG_CHANNEL):
    """Para el visor: (eeg [3,n] filtrado en cfg.BAND, emg dict {"mu": 8-12 Hz, "broad": 20-400 Hz} o None, fs). En uV."""
    path = Path(path)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        if path.suffix.lower() == ".cdt":
            raw = mne.io.read_raw_curry(str(path), preload=True, verbose=False)
        else:
            raw = mne.io.read_raw_eeglab(str(path), preload=True, verbose=False)
    fs = float(raw.info["sfreq"])
    names = [raw.ch_names[i] for i in _pick_channels(raw)]
    eeg = raw.copy().pick(names)
    eeg.filter(cfg.BAND[0], cfg.BAND[1], method="fir", phase="zero", verbose=False)
    emg = None
    if emg_channel and emg_channel.upper() in [c.upper() for c in raw.ch_names]:
        from scipy.signal import butter, sosfiltfilt
        idx = [c.upper() for c in raw.ch_names].index(emg_channel.upper())
        x = raw.get_data(picks=[idx])[0] * UV
        hi = min(cfg.EMG_BAND[1], fs / 2 - 1)
        sos = lambda lo, h: butter(4, [lo, h], btype="band", fs=fs, output="sos")
        emg = {"mu": sosfiltfilt(sos(cfg.BAND[0], cfg.BAND[1]), x),
               "broad": sosfiltfilt(sos(cfg.EMG_BAND[0], hi), x)}
    return eeg.get_data() * UV, emg, fs


def emg_envelope(emg: np.ndarray, fs: float, win_s: float = 0.1) -> np.ndarray:
    """Envolvente: |senal| suavizada con media movil de win_s segundos."""
    n = max(int(win_s * fs), 1)
    return np.convolve(np.abs(emg), np.ones(n) / n, mode="same")


_SESSION_RE = re.compile(r"_([A-Za-z]+\d{6})-\d+", re.IGNORECASE)
_FOLDER_RE = re.compile(r"^([A-Za-z]+?)(?:Ojos(?:Abiertos|Cerrados))?(\d{6})-(\d+)$", re.IGNORECASE)


def subject_from_folder(path: str | Path) -> str:
    """'arturoOjosAbiertos091126-1' -> 'arturo' (busca en la carpeta del archivo y sus padres)."""
    for part in [Path(path).name, *[p.name for p in Path(path).parents]]:
        m = _FOLDER_RE.match(part)
        if m:
            return m.group(1).lower()
    return Path(path).stem.lower()


def session_from_folder(path: str | Path) -> str:
    """'arturoOjosAbiertos091126-1' -> 'arturo091126-1'."""
    for part in [Path(path).name, *[p.name for p in Path(path).parents]]:
        m = _FOLDER_RE.match(part)
        if m:
            return f"{m.group(1).lower()}{m.group(2)}-{m.group(3)}"
    return Path(path).stem.lower()


def resolve_recording(path: str | Path) -> Path:
    """Acepta archivo .cdt/.set o carpeta que contenga uno. Errores claros en espanol."""
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"La ruta no existe: {p}")
    if p.is_dir():
        found = sorted([*p.glob("*.cdt"), *p.glob("*.set")])
        if not found:
            raise FileNotFoundError(f"No hay .cdt ni .set en la carpeta: {p}")
        if len(found) > 1:
            raise ValueError("Hay varios archivos, indica uno: " + ", ".join(f.name for f in found))
        return found[0]
    if p.suffix.lower() not in (".cdt", ".set"):
        raise ValueError(f"Extension no soportada ({p.suffix}); usa .cdt o .set")
    return p


def session_id(path: str | Path) -> str:
    """Identificador de sujeto/sesion tomado del nombre (p.ej. MD_marco020326-1 -> marco020326)."""
    m = _SESSION_RE.search(Path(path).name)
    return m.group(1).lower() if m else Path(path).stem.lower()


def subject_of_session(session: str) -> str:
    """'arturo091126-1' -> 'arturo' (para validar dejando un sujeto fuera)."""
    return re.sub(r"\d{6}(-\d+)?$", "", session)


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
