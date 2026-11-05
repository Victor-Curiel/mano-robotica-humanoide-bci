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


def compute_metrics(y_true, y_pred, n_classes: int = 3) -> dict:
    """Accuracy, recall por clase y matriz de confusion. Ignora y_true == -1."""
    y_true, y_pred = np.asarray(y_true), np.asarray(y_pred)
    m = y_true >= 0
    y_true, y_pred = y_true[m], y_pred[m]
    labels = list(range(n_classes))
    cm = confusion_matrix(y_true, y_pred, labels=labels)
    support = cm.sum(axis=1)
    recall = np.where(support > 0, np.diag(cm) / np.maximum(support, 1), np.nan)
    return {
        "confusion_matrix": cm,
        "accuracy": accuracy_score(y_true, y_pred) if len(y_true) else float("nan"),
        "recall": recall,
        "n": int(m.sum()),
    }
