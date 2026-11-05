"""Metricas de validacion contra ground truth."""
from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, confusion_matrix


def load_labels_csv(path) -> pd.DataFrame:
    """CSV con columnas: t_start, t_end, clase."""
    return pd.read_csv(path)


def labels_for_times(times: np.ndarray, events: pd.DataFrame, default: int = -1) -> np.ndarray:
    """Etiqueta por instante; -1 donde ningun evento cubre el tiempo."""
    labels = np.full(len(times), default, dtype=int)
    for _, r in events.iterrows():
        labels[(times >= r["t_start"]) & (times < r["t_end"])] = int(r["clase"])
    return labels


def compute_metrics(y_true, y_pred) -> dict:
    """Accuracy, sensibilidad (clase 1 = derecha) y especificidad (clase 0). Ignora y_true == -1."""
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    m = y_true >= 0
    y_true, y_pred = y_true[m], y_pred[m]
    cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
    tn, fp, fn, tp = cm.ravel()
    return {
        "confusion_matrix": cm,
        "accuracy": accuracy_score(y_true, y_pred) if len(y_true) else float("nan"),
        "sensitivity": tp / (tp + fn) if (tp + fn) else float("nan"),
        "specificity": tn / (tn + fp) if (tn + fp) else float("nan"),
        "n": int(m.sum()),
    }
