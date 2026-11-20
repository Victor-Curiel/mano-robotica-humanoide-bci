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
  slider / izq-der: recorre el tiempo (ancho de ventana fijo; flechas = media ventana)
  + / - / rueda   : zoom (rueda centrada en el puntero); clic en minimapa = ir ahi
  arriba / abajo  : escala uV de los canales EEG (0 = autoescala)
  m               : EMG: ambas / senal / envolvente
  f               : EMG: filtro 8-12 Hz (defecto) / 20-400 Hz
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


def load_signal(path: Path, emg_channel: str | None = cfg.EMG_CHANNEL):
    """Devuelve (eeg [3,n] filtrada, emg dict {'mu','broad'} o None, fs)."""
    from .preprocessing import load_for_view
    return load_for_view(path, emg_channel)


def minmax_decimate(t: np.ndarray, y: np.ndarray, max_pts: int = 4000):
    """Decimacion por bloques conservando minimo y maximo (mantiene picos)."""
    if len(y) <= max_pts:
        return t, y
    nb = max_pts // 2
    edges = np.linspace(0, len(y), nb + 1).astype(int)
    tt, yy = [], []
    for a, b in zip(edges[:-1], edges[1:]):
        seg = y[a:b]
        i0, i1 = sorted((a + int(seg.argmin()), a + int(seg.argmax())))
        tt += [t[i0], t[i1]]
        yy += [y[i0], y[i1]]
    return np.array(tt), np.array(yy)


def clamp_window(t0: float, width: float, dur: float) -> tuple[float, float]:
    """Ancho dentro de [min(0.5,dur), dur]; inicio dentro de [0, dur-ancho]."""
    width = float(min(max(width, min(0.5, dur)), dur))
    return float(min(max(t0, 0.0), dur - width)), width


def zoom_window(t0: float, width: float, dur: float, factor: float, center: float | None = None):
    c = t0 + width / 2 if center is None else center
    frac = (c - t0) / width if width else 0.5
    nw = min(max(width * factor, min(0.5, dur)), dur)
    return clamp_window(c - frac * nw, nw, dur)


class Selector:
    def __init__(self, data, fs, proposed: pd.DataFrame, out: Path, emg=None):
        import matplotlib.pyplot as plt
        from matplotlib.widgets import Slider, SpanSelector

        from .preprocessing import emg_envelope

        self.data, self.fs, self.out = data, fs, out
        self.dur = data.shape[1] / fs
        self.proposed = proposed.copy()
        self.manual: list[dict] = []
        self.pending: tuple[float, float] | None = None
        self.last_click = 0.0
        self.t0, self.width = 0.0, self.dur  # grabacion completa al inicio
        self.emg = emg
        self.env = {k: emg_envelope(v, fs) for k, v in emg.items()} if emg else None
        self.emg_mode = 0      # 0 ambas, 1 senal, 2 envolvente
        self.emg_band = "mu"   # 'mu' 8-12 Hz | 'broad' 20-400 Hz
        self.scale = None      # uV por canal (None = autoescala)
        n_ax = 4 if emg else 3
        self.fig = plt.figure(figsize=(14, 9))
        gs = self.fig.add_gridspec(n_ax + 1, 1, height_ratios=[3] * n_ax + [1],
                                   left=0.07, right=0.98, top=0.95, bottom=0.14, hspace=0.12)
        self.axes = [self.fig.add_subplot(gs[0])]
        self.axes += [self.fig.add_subplot(gs[i], sharex=self.axes[0]) for i in range(1, n_ax)]
        self.ax_map = self.fig.add_subplot(gs[n_ax])
        self.ax_sl = self.fig.add_axes([0.07, 0.04, 0.80, 0.025])
        self.slider = Slider(self.ax_sl, "t (s)", 0, max(self.dur - 0.5, 0.5), valinit=0)
        self.slider.on_changed(self._on_slider)
        self._updating = False
        self.span = SpanSelector(self.axes[-1], self._on_span, "horizontal", useblit=False,
                                 props=dict(alpha=0.3, facecolor="gray"), interactive=True)
        c = self.fig.canvas
        c.mpl_connect("key_press_event", self._on_key)
        c.mpl_connect("scroll_event", self._on_scroll)
        c.mpl_connect("button_press_event", self._on_click)
        # minimapa: envolvente de una version submuestreada del primer canal
        self._map_t, self._map_y = minmax_decimate(np.arange(data.shape[1]) / fs, data[0], 3000)
        self.draw()

    def events(self) -> pd.DataFrame:
        parts = [self.proposed[["onset_s", "duration_s", "label"]], pd.DataFrame(self.manual)]
        return pd.concat([p for p in parts if len(p)], ignore_index=True) if any(len(p) for p in parts) \
            else pd.DataFrame(columns=["onset_s", "duration_s", "label"])

    def _set_window(self, t0, width):
        self.t0, self.width = clamp_window(t0, width, self.dur)
        self._updating = True
        self.slider.set_val(self.t0)
        self._updating = False
        self.draw()

    def _on_slider(self, v):
        if not self._updating:
            self.t0, self.width = clamp_window(v, self.width, self.dur)
            self.draw()

    def _on_scroll(self, e):
        if e.inaxes in self.axes and e.xdata is not None:
            f = 0.8 if e.button == "up" else 1.25
            self._set_window(*zoom_window(self.t0, self.width, self.dur, f, e.xdata))

    def _on_click(self, e):
        if e.inaxes is self.ax_map and e.xdata is not None:
            self._set_window(e.xdata - self.width / 2, self.width)
        elif e.inaxes in self.axes and e.xdata is not None:
            self.last_click = e.xdata

    def draw(self):
        a, b = self.t0, self.t0 + self.width
        i, j = int(a * self.fs), min(int(np.ceil(b * self.fs)), self.data.shape[1])
        t = np.arange(i, j) / self.fs
        ev = self.events()
        for k, ax in enumerate(self.axes):
            ax.clear()
            if k < 3:
                y = self.data[k, i:j]
                ax.plot(*minmax_decimate(t, y), lw=0.6, color="k")
                ax.set_ylabel(f"{cfg.CHANNELS[k]}\n(uV)")
            else:
                if self.emg_mode in (0, 1):
                    y = self.emg[self.emg_band][i:j]
                    ax.plot(*minmax_decimate(t, y), lw=0.4, color="gray")
                if self.emg_mode in (0, 2):
                    y = self.env[self.emg_band][i:j]
                    ax.plot(*minmax_decimate(t, y), lw=1.2, color="tab:orange")
                ax.set_ylabel("EMG (ECG)\n" + ("8-12 Hz" if self.emg_band == "mu" else "20-400 Hz"))
            if self.scale and k < 3:
                ax.set_ylim(-self.scale, self.scale)
            ax.set_xlim(a, b)
            if k < len(self.axes) - 1:
                ax.tick_params(labelbottom=False)
            for _, r in ev.iterrows():
                if r["onset_s"] < b and r["onset_s"] + r["duration_s"] > a:
                    ax.axvspan(r["onset_s"], r["onset_s"] + r["duration_s"], alpha=0.25,
                               color=COLORS[r["label"]])
                    if k == 0:
                        ax.text(max(r["onset_s"], a), ax.get_ylim()[1], r["label"], fontsize=7,
                                va="top", clip_on=True)
        self.axes[-1].set_xlabel("s")
        n = ev["label"].value_counts().to_dict() if len(ev) else {}
        self.axes[0].set_title(f"{a:.1f}-{b:.1f} s (ancho {self.width:.1f} s) | eventos: {n}", fontsize=9)
        m = self.ax_map
        m.clear()
        m.plot(self._map_t, self._map_y, lw=0.3, color="k")
        for _, r in ev.iterrows():
            m.axvspan(r["onset_s"], r["onset_s"] + r["duration_s"], alpha=0.4, color=COLORS[r["label"]])
        m.axvspan(a, b, facecolor="none", edgecolor="tab:purple", lw=1.5)
        m.set_xlim(0, self.dur)
        m.set_yticks([])
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
        elif k == "m" and self.emg:
            self.emg_mode = (self.emg_mode + 1) % 3
        elif k == "f" and self.emg:
            self.emg_band = "broad" if self.emg_band == "mu" else "mu"
        elif k == "x":
            self._remove_nearest()
        elif k in ("[", "]") and len(self.proposed):
            self.proposed["onset_s"] += SHIFT if k == "]" else -SHIFT
        elif k in ("+", "="):
            return self._set_window(*zoom_window(self.t0, self.width, self.dur, 0.5))
        elif k in ("-", "_"):
            return self._set_window(*zoom_window(self.t0, self.width, self.dur, 2.0))
        elif k == "right":
            return self._set_window(self.t0 + self.width / 2, self.width)
        elif k == "left":
            return self._set_window(self.t0 - self.width / 2, self.width)
        elif k in ("up", "down"):
            cur = self.scale or float(np.percentile(np.abs(self.data), 99))
            self.scale = cur * (0.7 if k == "up" else 1.4)
        elif k == "0":
            self.scale = None
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
    ap.add_argument("--emg-canal", default=cfg.EMG_CHANNEL, help="canal usado como EMG ('' para ocultar)")
    ap.add_argument("--out", type=Path, help="eventos.csv (default: junto al archivo)")
    a = ap.parse_args()

    import matplotlib.pyplot as plt
    from .preprocessing import resolve_recording
    try:
        a.file = resolve_recording(a.file)
    except (FileNotFoundError, ValueError) as e:
        raise SystemExit(f"ERROR: {e}")
    data, emg, fs = load_signal(a.file, a.emg_canal or None)
    if emg is None and a.emg_canal:
        print(f"AVISO: canal {a.emg_canal} no encontrado; se muestran solo 3 ejes EEG")
    prop = pd.DataFrame(columns=["onset_s", "duration_s", "label"])
    if a.stimuli:
        prop = parse_stimuli(a.stimuli, a.start)
        if a.basal_auto:
            prop = pd.concat([prop, basal_between(prop)], ignore_index=True)
    out = a.out or a.file.with_name("eventos.csv")
    sel = Selector(data, fs, prop, out, emg)  # noqa: F841 (mantiene referencias de widgets)
    plt.show()


if __name__ == "__main__":
    main()
