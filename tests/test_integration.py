import pytest
from src import config as cfg
from src.preprocessing import load_set_epochs, build_dataset
from src.predictor import SlidingWindowPredictor
import numpy as np

pytestmark = pytest.mark.skipif(not all(d.exists() for d in cfg.DATA_DIRS.values()), reason="datos EEG no disponibles")


def test_real_data_end_to_end():
    f = sorted(cfg.DATA_DIRS[1].glob("*.set"))[0]
    data, fs = load_set_epochs(f)
    assert data.shape[1] == 3 and fs > 0
    if not cfg.MODEL_PATH.exists():
        pytest.skip("modelo no entrenado")
    sig = np.concatenate(list(data), axis=1)
    cls, conf, t = SlidingWindowPredictor().predict_continuous(sig, fs)
    assert len(cls) == len(conf) == len(t) > 0
    assert set(cls) <= {0, 1, 2} and np.all((conf >= 0) & (conf <= 1))
