"""Valida predicciones guardadas contra un CSV (t_start,t_end,clase).

Uso: python -m src.validate labels.csv [resultados/predictions.npz]
"""
from __future__ import annotations

import sys

import numpy as np

from src import config as cfg
from src.validation import compute_metrics, labels_for_times, load_labels_csv


def main() -> None:
    labels_path = sys.argv[1]
    npz = sys.argv[2] if len(sys.argv) > 2 else cfg.RESULTS_DIR / "predictions.npz"
    d = np.load(npz)
    truth = labels_for_times(d["t"], load_labels_csv(labels_path))
    m = compute_metrics(truth, d["cls"])
    print(f"n={m['n']}  accuracy={m['accuracy']:.3f}  recall(basal,apretar,estirar)={np.round(m['recall'], 3)}")
    print(m["confusion_matrix"])


if __name__ == "__main__":
    main()
