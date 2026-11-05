"""Parametros centralizados del pipeline BCI.

Las rutas de datos pueden sobreescribirse con variables de entorno
(BCI_DATA_RIGHT, BCI_DATA_LEFT, BCI_PORT).
"""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# --- Datos ---------------------------------------------------------------
_ACQ = Path(r"C:\Users\vhca1\Desktop\Acquisition")
# Carpetas con .set (epocas) por estado. Sobrescribibles: BCI_DATA_BASAL / _APRETAR / _ESTIRAR
DATA_DIRS = {
    0: Path(os.environ.get("BCI_DATA_BASAL", _ACQ / "basal")),
    1: Path(os.environ.get("BCI_DATA_APRETAR", _ACQ / "apretar")),
    2: Path(os.environ.get("BCI_DATA_ESTIRAR", _ACQ / "estirar")),
}

MODELS_DIR = ROOT / "modelos"
MODEL_PATH = MODELS_DIR / "bci_model.pth"
STATS_PATH = MODELS_DIR / "normalization_stats.json"
RESULTS_DIR = ROOT / "resultados"

# Estados (clase_dedos, clase_muneca) que recibe el firmware. (1,1) no existe.
CLASS_BASAL, CLASS_APRETAR, CLASS_ESTIRAR = 0, 1, 2
N_CLASSES = 3
CLASS_NAMES = ("basal", "apretar", "estirar")
CLASS_TO_PAIR = {0: (0, 0), 1: (1, 0), 2: (0, 1)}

# --- Canales -------------------------------------------------------------
# Orden de features: C3, C4, Cz (igual que MATLAB).
CHANNELS = ("C3", "C4", "CZ")

# --- DSP -----------------------------------------------------------------
# NOTA: MATLAB fijaba fs=500 aunque los .set estan a 1024 Hz (el eje de
# frecuencias quedaba mal escalado). Aqui se usa SIEMPRE la fs real del archivo.
BAND = (8.0, 12.0)             # Hz, banda mu/alfa (decision del proyecto)
WELCH_SEG_SECS = 0.5           # ventana Welch (s); 50 % de traslape
NFFT_FACTOR = 2                # nfft = NFFT_FACTOR * fs
BURG_ORDER = 16
WAVELET = "db4"
WAVELET_LEVEL = 4
N_FEATURES = 9
MIN_VARIANCE = 1e-6            # (uV^2) descarta canales planos

# --- Prediccion continua -------------------------------------------------
# Las epocas de entrenamiento duran 1 s, asi que la ventana por defecto es 1 s.
WINDOW_SECS = 1.0
STEP_SECS = 0.5

# --- Red -----------------------------------------------------------------
MLP_HIDDEN = 10
TRAIN_CONFIG = {
    "max_epochs": 1000,
    "lr": 5e-3,
    "weight_decay": 1e-3,
    "patience": 80,
    "val_fraction": 0.15,
    "seed": 42,
}

# --- ESP32 ---------------------------------------------------------------
ESP32_PORT = os.environ.get("BCI_PORT", "COM3")
ESP32_BAUD = 115200
