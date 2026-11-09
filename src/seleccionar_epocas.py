"""Visor interactivo para seleccionar epocas en un .cdt/.set y generar eventos.csv.

Uso:
  python -m src.seleccionar_epocas archivo.cdt
  python -m src.seleccionar_epocas archivo.cdt --stimuli "Registro De Pruebas/<csv>" --start 14:03:25.500
  python -m src.seleccionar_epocas archivo.cdt --stimuli <csv> --basal-auto

Sin --start, los estimulos se ubican con Tiempo_Exp (cuenta desde el 1er estimulo);
alinealos con [ y ] (desplaza todos los estimulos propuestos 0.25 s).

Teclas:
  arrastrar raton : marca un segmento nuevo (queda pendiente)
  b / a / e       : etiqueta el segmento pendiente como basal / apretar / estirar
  x               : descarta el evento mas cercano al ultimo clic
  u               : deshace el ultimo evento agregado manualmente
  [ / ]           : desplaza estimulos propuestos -/+ 0.25 s
  izq / der       : navega 10 s
  s               : guarda eventos.csv
Salida: eventos.csv (onset_s,duration_s,label), consumido por 'cdt_to_set epochs'.
"""
from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

from . import config as cfg

COLORS = {"basal": "tab:blue", "apretar": "tab:red", "estirar": "tab:green"}
STIM_TO_LABEL = {"rojo": "apretar", "verde": "estirar"}
SHIFT = 0.25
VIEW_S = 20.0


def _label_from_stimulus(name: str) -> str:
    n = name.lower()
    for key, lab in STIM_TO_LABEL.items():
        if key in n:
            return lab
    raise ValueError(f"estimulo desconocido: {name}")


def parse_stimuli(csv_path: Path, start: str | None = None, min_dur: float = 1.0) -> pd.DataFrame:
    """CSV de Experimento*.py -> DataFrame(onset_s, duration_s, label).

    start: hora (HH:MM:SS[.ffffff]) de inicio de la grabacion; si None usa Tiempo_Exp.
    """
    df = pd.read_csv(csv_path)
    if start:
        fmt = "%H:%M:%S.%f" if "." in start else "%H:%M:%S"
        t0 = datetime.strptime(start, fmt)
        onset = [(datetime.strptime(t, "%H:%M:%S.%f") - t0).total_seconds() for t in df["Timestamp"]]
    else:
        onset = df["Tiempo_Exp"].astype(float).tolist()
    dur = np.maximum(df["Duracion_Show"].astype(float), min_dur)
    return pd.DataFrame({
        "onset_s": onset, "duration_s": dur,
        "label": [_label_from_stimulus(s) for s in df["Estimulo"]],
    })


def basal_between(stim: pd.DataFrame, margin: float = 0.5, min_dur: float = 1.0) -> pd.DataFrame:
    """Segmentos basales en los huecos entre estimulos (con margen), de al menos min_dur."""
    s = stim.sort_values("onset_s").reset_index(drop=True)
    rows = []
    for i in range(len(s) - 1):
        a = s.loc[i, "onset_s"] + s.loc[i, "duration_s"] + margin
        b = s.loc[i + 1, "onset_s"] - margin
        if b - a >= min_dur:
            rows.append((a, b - a, "basal"))
    return pd.DataFrame(rows, columns=["onset_s", "duration_s", "label"])


def save_events(df: pd.DataFrame, path: Path) -> None:
    df = df.sort_values("onset_s").round(3)
    df.to_csv(path, index=False)


def load_signal(path: Path):
    """Devuelve (data [3,n] en uV filtrada, fs)."""
    from .preprocessing import load_continuous
    return load_continuous(path, filter_signal=True)


class Selector:
    def __init__(self, data, fs, proposed: pd.DataFrame, out: Path):
        import matplotlib.pyplot as plt
        from matplotlib.widgets import SpanSelector

        self.data, self.fs, self.out = data, fs, out
        self.dur = data.shape[1] / fs
        self.proposed = proposed.copy()
        self.manual: list[dict] = []
        self.pending: tuple[float, float] | None = None
        self.last_click = 0.0
        self.t0 = 0.0
        self.fig, self.axes = plt.subplots(3, 1, sharex=True, figsize=(13, 7))
        for ax, name in zip(self.axes, cfg.CHANNELS):
            ax.set_ylabel(name)
        self.span = SpanSelector(self.axes[-1], self._on_span, "horizontal", useblit=False,
                                 props=dict(alpha=0.3, facecolor="gray"), interactive=True)
        self.fig.canvas.mpl_connect("key_press_event", self._on_key)
        self.fig.canvas.mpl_connect("button_press_event",
                                    lambda e: setattr(self, "last_click", e.xdata or self.last_click))
        self.draw()

    def events(self) -> pd.DataFrame:
        parts = [self.proposed[["onset_s", "duration_s", "label"]], pd.DataFrame(self.manual)]
        return pd.concat([p for p in parts if len(p)], ignore_index=True) if any(len(p) for p in parts) \
            else pd.DataFrame(columns=["onset_s", "duration_s", "label"])

    def draw(self):
        a, b = self.t0, min(self.t0 + VIEW_S, self.dur)
        i, j = int(a * self.fs), int(b * self.fs)
        t = np.arange(i, j) / self.fs
        ev = self.events()
        for k, ax in enumerate(self.axes):
            ax.clear()
            ax.plot(t, self.data[k, i:j], lw=0.6, color="k")
            ax.set_ylabel(cfg.CHANNELS[k])
            for _, r in ev.iterrows():
                if r["onset_s"] < b and r["onset_s"] + r["duration_s"] > a:
                    ax.axvspan(r["onset_s"], r["onset_s"] + r["duration_s"], alpha=0.25,
                               color=COLORS[r["label"]])
            ax.set_xlim(a, b)
        n = ev["label"].value_counts().to_dict() if len(ev) else {}
        self.axes[0].set_title(f"{a:.0f}-{b:.0f} s | eventos: {n} | b/a/e etiqueta, x borra, u deshace, s guarda")
        self.axes[-1].set_xlabel("s")
        self.fig.canvas.draw_idle()

    def _on_span(self, lo, hi):
        self.pending = (lo, hi) if hi - lo > 0.05 else None

    def _on_key(self, e):
        k = e.key
        if k in ("b", "a", "e") and self.pending:
            lo, hi = self.pending
            lab = {"b": "basal", "a": "apretar", "e": "estirar"}[k]
            self.manual.append({"onset_s": lo, "duration_s": hi - lo, "label": lab})
            self.pending = None
            self.span.clear()
        elif k == "u" and self.manual:
            self.manual.pop()
        elif k == "x":
            self._remove_nearest()
        elif k in ("[", "]") and len(self.proposed):
            self.proposed["onset_s"] += SHIFT if k == "]" else -SHIFT
        elif k == "right":
            self.t0 = min(self.t0 + 10, max(self.dur - VIEW_S, 0))
        elif k == "left":
            self.t0 = max(self.t0 - 10, 0)
        elif k == "s":
            save_events(self.events(), self.out)
            print(f"Guardado: {self.out}  ({len(self.events())} eventos)")
            return
        else:
            return
        self.draw()

    def _remove_nearest(self):
        def dist(r):
            return abs(r["onset_s"] + r["duration_s"] / 2 - self.last_click)
        cands = [("p", i, dist(r)) for i, r in self.proposed.iterrows()] + \
                [("m", i, dist(r)) for i, r in enumerate(self.manual)]
        if not cands:
            return
        src, i, _ = min(cands, key=lambda c: c[2])
        if src == "p":
            self.proposed = self.proposed.drop(index=i)
        else:
            self.manual.pop(i)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("file", type=Path)
    ap.add_argument("--stimuli", type=Path, help="CSV de Registro De Pruebas")
    ap.add_argument("--start", help="hora de inicio de la grabacion HH:MM:SS[.ffffff]")
    ap.add_argument("--basal-auto", action="store_true", help="proponer basal entre estimulos")
    ap.add_argument("--out", type=Path, help="eventos.csv (default: junto al archivo)")
    a = ap.parse_args()

    import matplotlib.pyplot as plt
    data, fs = load_signal(a.file)
    prop = pd.DataFrame(columns=["onset_s", "duration_s", "label"])
    if a.stimuli:
        prop = parse_stimuli(a.stimuli, a.start)
        if a.basal_auto:
            prop = pd.concat([prop, basal_between(prop)], ignore_index=True)
    out = a.out or a.file.with_name("eventos.csv")
    sel = Selector(data, fs, prop, out)  # noqa: F841 (mantiene referencias de widgets)
    plt.show()


if __name__ == "__main__":
    main()
