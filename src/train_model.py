"""Entrena el MLP BCI. Reemplaza MODULO_BATCH_...PLOT.m.

Uso: python -m src.train_model [--right DIR] [--left DIR] [--no-cv]

Evaluacion: leave-one-session-out (sin fuga entre sesiones). El z-score se ajusta
solo con el conjunto de entrenamiento de cada fold.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import torch
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, confusion_matrix
from sklearn.model_selection import LeaveOneGroupOut

from src import config as cfg
from src.model import predict_proba, train_model
from src.preprocessing import build_dataset
from src.utils import apply_zscore, fit_zscore, iqr_outlier_mask, save_stats


def cross_validate(X, y, groups):
    accs, base_accs, y_all, p_all = [], [], [], []
    for tr, te in LeaveOneGroupOut().split(X, y, groups):
        mu, sd = fit_zscore(X[tr])
        Xtr, Xte = apply_zscore(X[tr], mu, sd), apply_zscore(X[te], mu, sd)
        model, _ = train_model(Xtr, y[tr])
        pred = predict_proba(model, Xte).argmax(1)
        base = LogisticRegression(max_iter=1000).fit(Xtr, y[tr]).predict(Xte)
        accs.append(accuracy_score(y[te], pred))
        base_accs.append(accuracy_score(y[te], base))
        y_all.extend(y[te])
        p_all.extend(pred)
        print(f"  sesion {groups[te][0]:<14} n={len(te):3d}  MLP={accs[-1]:.3f}  LogReg={base_accs[-1]:.3f}")
    return accs, base_accs, confusion_matrix(y_all, p_all, labels=[0, 1])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--right", type=Path, default=cfg.DATA_RIGHT)
    ap.add_argument("--left", type=Path, default=cfg.DATA_LEFT)
    ap.add_argument("--no-cv", action="store_true")
    args = ap.parse_args()

    X, y, groups = build_dataset(args.right, args.left)
    mask = iqr_outlier_mask(X)
    print(f"\nEpocas: {len(y)} | outliers IQR eliminados: {mask.sum()}")
    X, y, groups = X[~mask], y[~mask], groups[~mask]
    print(f"Utiles: {len(y)}  (derecha={int((y == 1).sum())}, izquierda={int((y == 0).sum())})")

    if not args.no_cv:
        print("\nValidacion leave-one-session-out:")
        accs, base, cm = cross_validate(X, y, groups)
        print(f"\nMLP    : {np.mean(accs):.3f} +- {np.std(accs):.3f}")
        print(f"LogReg : {np.mean(base):.3f} +- {np.std(base):.3f}   (azar = 0.500)")
        print(f"Matriz de confusion agregada (filas=real 0/1, cols=pred 0/1):\n{cm}")

    mu, sd = fit_zscore(X)
    model, hist = train_model(apply_zscore(X, mu, sd), y)
    train_acc = accuracy_score(y, predict_proba(model, apply_zscore(X, mu, sd)).argmax(1))
    print(f"\nModelo final (todas las sesiones): acc entrenamiento={train_acc:.3f}, epocas={len(hist['val_loss'])}")

    cfg.MODELS_DIR.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), cfg.MODEL_PATH)
    save_stats(cfg.STATS_PATH, mu, sd, {"band": list(cfg.BAND), "channels": list(cfg.CHANNELS)})
    print(f"Guardado: {cfg.MODEL_PATH}\n          {cfg.STATS_PATH}")


if __name__ == "__main__":
    main()
