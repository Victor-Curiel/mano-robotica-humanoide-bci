"""Prediccion continua sobre un registro EEG y envio opcional al ESP32.

Reemplaza control_final.m / PREDICTOR_*.m / ENVIAR_A_ESP32.m.

Ejemplos:
  python -m src.predict_continuous archivo.cdt
  python -m src.predict_continuous archivo.set --port COM3 --interval 1.0
  python -m src.predict_continuous archivo.set --dry-run
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import numpy as np

from src import config as cfg
from src.hardware import ESP32Interface, format_message
from src.predictor import SlidingWindowPredictor
from src.preprocessing import load_continuous


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("file", type=Path)
    ap.add_argument("--port", help="puerto serial (p.ej. COM3); sin esto no se envia nada")
    ap.add_argument("--dry-run", action="store_true", help="imprime los mensajes en lugar de enviarlos")
    ap.add_argument("--interval", type=float, default=1.0, help="segundos entre mensajes")
    ap.add_argument("--no-filter", action="store_true", help="la senal ya esta filtrada (.set *_Filter)")
    args = ap.parse_args()

    signal, fs = load_continuous(args.file, filter_signal=not args.no_filter)
    pred = SlidingWindowPredictor()
    cls, conf, t = pred.predict_continuous(signal, fs)
    n1 = int((cls == 1).sum())
    print(f"{len(cls)} ventanas | derecha={n1} izquierda={len(cls) - n1} | confianza media={np.mean(conf):.3f}")

    cfg.RESULTS_DIR.mkdir(exist_ok=True)
    np.savez(cfg.RESULTS_DIR / "predictions.npz", cls=cls, conf=conf, t=t)

    if args.dry_run:
        for c, p, ts in zip(cls, conf, t):
            print(format_message(c, p, ts), end="")
    elif args.port:
        with ESP32Interface(args.port) as esp:
            for c, p, ts in zip(cls, conf, t):
                print(esp.send(c, p, ts).strip(), "->", esp.read_response())
                time.sleep(args.interval)


if __name__ == "__main__":
    main()
