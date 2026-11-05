"""MLP 9 -> 10 (tanh) -> 2 (equivalente a patternnet([10])) y entrenamiento."""
from __future__ import annotations

import copy

import numpy as np
import torch
import torch.nn as nn
from sklearn.model_selection import train_test_split

from . import config as cfg


class BCINet(nn.Module):
    """Salida en logits; usar softmax para probabilidades (clase 1 = derecha)."""

    def __init__(self, n_in: int = cfg.N_FEATURES, n_hidden: int = cfg.MLP_HIDDEN, n_out: int = 2):
        super().__init__()
        self.fc1 = nn.Linear(n_in, n_hidden)
        self.act = nn.Tanh()
        self.fc2 = nn.Linear(n_hidden, n_out)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.fc2(self.act(self.fc1(x)))


def train_model(X: np.ndarray, y: np.ndarray, config: dict | None = None) -> tuple[BCINet, dict]:
    """Entrena con early stopping sobre una particion de validacion estratificada.

    X debe venir ya normalizado. Devuelve (modelo en eval, historial).
    """
    c = {**cfg.TRAIN_CONFIG, **(config or {})}
    torch.manual_seed(c["seed"])
    X_tr, X_va, y_tr, y_va = train_test_split(
        X, y, test_size=c["val_fraction"], stratify=y, random_state=c["seed"]
    )
    t = lambda a, dt: torch.as_tensor(a, dtype=dt)
    X_tr, X_va = t(X_tr, torch.float32), t(X_va, torch.float32)
    y_tr, y_va = t(y_tr, torch.long), t(y_va, torch.long)

    model = BCINet()
    opt = torch.optim.Adam(model.parameters(), lr=c["lr"], weight_decay=c["weight_decay"])
    loss_fn = nn.CrossEntropyLoss()
    hist = {"train_loss": [], "val_loss": [], "val_acc": []}
    best, best_state, wait = np.inf, copy.deepcopy(model.state_dict()), 0

    for _ in range(c["max_epochs"]):
        model.train()
        opt.zero_grad()
        loss = loss_fn(model(X_tr), y_tr)
        loss.backward()
        opt.step()
        model.eval()
        with torch.no_grad():
            out = model(X_va)
            v = loss_fn(out, y_va).item()
            acc = (out.argmax(1) == y_va).float().mean().item()
        hist["train_loss"].append(loss.item())
        hist["val_loss"].append(v)
        hist["val_acc"].append(acc)
        if v < best - 1e-5:
            best, best_state, wait = v, copy.deepcopy(model.state_dict()), 0
        else:
            wait += 1
            if wait >= c["patience"]:
                break
    model.load_state_dict(best_state)
    model.eval()
    return model, hist


def predict_proba(model: BCINet, X: np.ndarray) -> np.ndarray:
    """Probabilidades [n, 2] (columna 0 = izquierda, columna 1 = derecha)."""
    model.eval()
    with torch.no_grad():
        return torch.softmax(model(torch.as_tensor(X, dtype=torch.float32)), dim=1).numpy()
