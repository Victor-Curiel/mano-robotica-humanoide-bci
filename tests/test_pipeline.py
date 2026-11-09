import numpy as np
import pandas as pd
import pytest
import torch

from src import config as cfg
from src.feature_extraction import (
    bandpower, burg_coefficients, burg_psd, extract_features, welch_psd, wavelet_energy,
)
from src.hardware import ESP32Interface, format_message
from src.model import BCINet, predict_proba, train_model
from src.utils import apply_zscore, fit_zscore, iqr_outlier_mask
from src.validation import compute_metrics, labels_for_times

FS = 1024.0


def ar2_signal(n=20000, seed=0):
    rng = np.random.default_rng(seed)
    e = rng.standard_normal(n)
    x = np.zeros(n)
    for i in range(2, n):
        x[i] = 1.5 * x[i - 1] - 0.75 * x[i - 2] + e[i]
    return x


def test_burg_recovers_ar_coefficients():
    a, var = burg_coefficients(ar2_signal(), 2)
    assert a[1] == pytest.approx(-1.5, abs=0.03)
    assert a[2] == pytest.approx(0.75, abs=0.03)
    assert var == pytest.approx(1.0, rel=0.05)


def test_burg_and_welch_agree_on_sinusoid_peak():
    t = np.arange(1024) / FS
    x = np.sin(2 * np.pi * 20 * t) + 0.1 * np.random.default_rng(1).standard_normal(1024)
    for psd in (welch_psd, burg_psd):
        f, p = psd(x, FS)
        assert abs(f[np.argmax(p)] - 20) < 2


def test_welch_power_matches_variance():
    x = np.random.default_rng(2).standard_normal(8192)
    f, p = welch_psd(x, FS)
    assert bandpower(p, f, (0, FS / 2)) == pytest.approx(x.var(), rel=0.1)


def test_wavelet_energy_positive_and_scale_quadratic():
    x = np.random.default_rng(3).standard_normal(1024)
    assert wavelet_energy(2 * x) == pytest.approx(4 * wavelet_energy(x))


def test_extract_features_shape_and_bad_input():
    x = np.random.default_rng(4).standard_normal((3, 1024)) * 10
    f = extract_features(x, FS)
    assert f.shape == (cfg.N_FEATURES,) and np.all(np.isfinite(f)) and np.all(f > 0)
    with pytest.raises(ValueError):
        extract_features(x[:2], FS)


def test_zscore_and_iqr():
    X = np.random.default_rng(5).standard_normal((100, 9))
    X[0, 0] = 100
    assert iqr_outlier_mask(X)[0]
    mu, sd = fit_zscore(X)
    Z = apply_zscore(X, mu, sd)
    assert np.allclose(Z.mean(0), 0, atol=1e-9) and np.allclose(Z.std(0), 1)


def test_model_trains_on_separable_data(tmp_path):
    rng = np.random.default_rng(6)
    X = np.vstack([rng.normal(m, 1, (80, 9)) for m in (-2, 0, 2)])
    y = np.repeat([0, 1, 2], 80)
    model, hist = train_model(X, y, {"max_epochs": 300})
    assert (predict_proba(model, X).argmax(1) == y).mean() > 0.9
    torch.save(model.state_dict(), tmp_path / "m.pth")
    m2 = BCINet()
    m2.load_state_dict(torch.load(tmp_path / "m.pth", weights_only=True))
    assert np.allclose(predict_proba(m2, X), predict_proba(model, X))


def test_message_format_matches_firmware_protocol():
    assert format_message(1, 0.87, 1.234) == "1,0.87,0,0.87,1.234\n"   # apretar
    assert format_message(2, 0.5, 2.0) == "0,0.50,1,0.50,2.000\n"       # estirar
    assert format_message(0, 0.9, 0.0) == "0,0.90,0,0.90,0.000\n"       # basal


def test_esp32_interface_with_fake_serial():
    class Fake:
        def __init__(self, *a, **k):
            self.buf, self.in_waiting, self.closed = [], 0, False
        def write(self, b): self.buf.append(b)
        def close(self): self.closed = True

    with ESP32Interface("FAKE", serial_factory=Fake) as esp:
        esp.send(0, 0.5, 2.0)
        ser = esp.ser
    assert ser.buf == [b"0,0.50,0,0.50,2.000\n"] and ser.closed
    with pytest.raises(RuntimeError):
        esp.send(1, 1, 1)


def test_validation_metrics():
    ev = pd.DataFrame({"t_start": [0, 4], "t_end": [4, 8], "clase": [0, 2]})
    truth = labels_for_times(np.arange(10.0), ev)
    assert list(truth[[0, 5, 9]]) == [0, 2, -1]
    m = compute_metrics(truth, [0, 0, 0, 0, 2, 2, 2, 0, 2, 2])
    assert m["n"] == 8 and m["accuracy"] == pytest.approx(7 / 8)
    assert m["recall"][0] == 1.0 and m["recall"][2] == pytest.approx(3 / 4) and np.isnan(m["recall"][1])


def test_segment_windows_only_full_windows_per_label():
    from src.cdt_to_set import segment_windows
    ev = pd.DataFrame({"onset_s": [0, 10], "duration_s": [3.5, 2], "label": ["basal", "estirar"]})
    w = list(segment_windows(ev, fs=100, n_times=1500, win_s=1, step_s=1))
    assert w == [(0, 0), (100, 0), (200, 0), (1000, 2), (1100, 2)]


def test_parse_stimuli_and_basal(tmp_path):
    from src.seleccionar_epocas import basal_between, parse_stimuli
    p = tmp_path / "s.csv"
    pd.DataFrame({"Timestamp": ["10:00:20.000", "10:00:25.500"], "Tiempo_Exp": [0, 5.5],
                  "Estimulo": ["Circulo_Rojo_Der", "Cuadrado_Verde_Izq"],
                  "Duracion_Show": [0.5, 2.0]}).to_csv(p, index=False)
    a = parse_stimuli(p, "10:00:10")
    assert a.values.tolist() == [[10.0, 1.0, "apretar"], [15.5, 2.0, "estirar"]]
    assert basal_between(a).values.tolist() == [[11.5, 3.5, "basal"]]
