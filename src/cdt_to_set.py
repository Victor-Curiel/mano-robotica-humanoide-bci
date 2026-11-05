"""Convierte .cdt (Curry/Neuroscan) a .set y corta epocas por estado.

Reemplaza CONVERTIR_CDT_A_SET.m y el paso manual de EEGLAB para marcar eventos.

CSV de eventos (columnas): onset_s, duration_s, label
  label = basal | apretar | estirar     (onset_s en segundos desde el inicio del .cdt)

Uso:
  python -m src.cdt_to_set convert archivo.cdt [--events eventos.csv] [--out DIR]
  python -m src.cdt_to_set epochs  archivo.cdt --events eventos.csv [--session marco110326-1]
"""
from __future__ import annotations

import argparse
import warnings
from pathlib import Path

import mne
import numpy as np
import pandas as pd

from . import config as cfg


def read_cdt(path: Path) -> mne.io.BaseRaw:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        return mne.io.read_raw_curry(str(path), preload=True, verbose=False)


def read_events_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    missing = {"onset_s", "duration_s", "label"} - set(df.columns)
    if missing:
        raise ValueError(f"faltan columnas en {path}: {sorted(missing)}")
    df["label"] = df["label"].str.strip().str.lower()
    bad = set(df["label"]) - set(cfg.CLASS_NAMES)
    if bad:
        raise ValueError(f"etiquetas invalidas {sorted(bad)}; validas: {cfg.CLASS_NAMES}")
    return df


def convert(cdt: Path, events: Path | None, out_dir: Path) -> Path:
    """.cdt -> <nombre>_crudo.set (continuo, con anotaciones si hay CSV)."""
    raw = read_cdt(cdt)
    if events is not None:
        ev = read_events_csv(events)
        raw.set_annotations(mne.Annotations(ev["onset_s"], ev["duration_s"], ev["label"]))
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{cdt.stem.replace(' ', '_')}_crudo.set"
    raw.export(str(out), fmt="eeglab", overwrite=True, verbose=False)
    return out


def segment_windows(events: pd.DataFrame, fs: float, n_times: int, win_s: float, step_s: float):
    """Genera (inicio_muestra, clase) de ventanas completas dentro de cada segmento etiquetado."""
    win, step = int(round(win_s * fs)), int(round(step_s * fs))
    for _, r in events.iterrows():
        a, b = int(round(r["onset_s"] * fs)), int(round((r["onset_s"] + r["duration_s"]) * fs))
        b = min(b, n_times)
        for s in range(a, b - win + 1, step):
            yield s, cfg.CLASS_NAMES.index(r["label"])


def extract_epochs(cdt: Path, events: Path, session: str, out_root: Path,
                   win_s: float = 1.0, step_s: float = 1.0, band=cfg.BAND) -> dict[str, int]:
    """Filtra (FIR zero-phase, banda cfg.BAND), corta epocas y guarda un .set por clase.

    Salida: <out_root>/<clase>/<PREFIJO>_<session>_Filter.set  (mismo patron que los .set previos).
    """
    raw = read_cdt(cdt)
    raw.filter(band[0], band[1], method="fir", phase="zero", verbose=False)
    fs = raw.info["sfreq"]
    data = raw.get_data()
    counts = {}
    wins = list(segment_windows(read_events_csv(events), fs, data.shape[1], win_s, step_s))
    for cls, name in enumerate(cfg.CLASS_NAMES):
        starts = [s for s, c in wins if c == cls]
        if not starts:
            continue
        arr = np.stack([data[:, s:s + int(round(win_s * fs))] for s in starts])
        ep = mne.EpochsArray(arr, raw.info, tmin=0.0, verbose=False)
        folder = out_root / name
        folder.mkdir(parents=True, exist_ok=True)
        ep.export(str(folder / f"{name[:2].upper()}_{session}_Filter.set"), fmt="eeglab",
                  overwrite=True, verbose=False)
        counts[name] = len(starts)
    return counts


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("convert")
    c.add_argument("cdt", type=Path)
    c.add_argument("--events", type=Path)
    c.add_argument("--out", type=Path, default=cfg.CDT_DIR / "convertidos")
    e = sub.add_parser("epochs")
    e.add_argument("cdt", type=Path)
    e.add_argument("--events", type=Path, required=True)
    e.add_argument("--session", help="p.ej. marco110326-1 (default: carpeta del .cdt)")
    e.add_argument("--out", type=Path, default=cfg.EPOCHS_DIR)
    e.add_argument("--win", type=float, default=cfg.WINDOW_SECS)
    e.add_argument("--step", type=float, default=cfg.WINDOW_SECS)
    a = ap.parse_args()
    if a.cmd == "convert":
        print("Guardado:", convert(a.cdt, a.events, a.out))
    else:
        print("Epocas por clase:", extract_epochs(
            a.cdt, a.events, a.session or a.cdt.parent.name, a.out, a.win, a.step))


if __name__ == "__main__":
    main()
