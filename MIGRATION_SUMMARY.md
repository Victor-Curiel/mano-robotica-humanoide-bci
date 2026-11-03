# Resumen Ejecutivo: Migración MATLAB → Python

**Estado:** Plan listo para implementación  
**Tiempo estimado:** 4-5 semanas (full-time)  
**Riesgo:** MEDIUM (depende datos entrenamiento)  
**Responsable:** Claude (modelo IA potente)

---

## 🎯 Misión

Reemplazar pipeline BCI MATLAB/EEGLAB (9 scripts, ~2300 líneas) con equivalente Python/MNE-Python tras expiración licencia MATLAB julio 2026.

## 📋 Alcance

| Componente | De | A |
|---|---|---|
| **Lectura EEG** | EEGLAB pop_loadset() | MNE-Python read_eeglab() |
| **DSP Características** | MATLAB Signal/Wavelet Toolboxes | SciPy + PyWavelets |
| **Red Neuronal** | MATLAB patternnet | PyTorch MLP 9→10→2 |
| **Control Hardware** | MATLAB serialport() | PySerial |
| **Tests/Validación** | MATLAB confusionmat() | scikit-learn |

## 🚀 Fases Principales

| Fase | Duración | Deliverable | Status |
|------|----------|-------------|--------|
| 0 | 1 día | venv + repo setup | Pending |
| 1 | 3-4 días | `src/feature_extraction.py` | Pending |
| 2 | 2-3 días | `src/preprocessing.py` | Pending |
| **3** | **5-7 días** | **Modelo reentrenado** | **⚠️ CRÍTICA** |
| 4 | 3-4 días | `src/predictor.py` | Pending |
| 5 | 2-3 días | `src/validation.py` | Pending |
| 6 | 2-3 días | `src/hardware.py` + ESP32 | Pending |
| 7 | 3-4 días | Tests (80%+ coverage) | Pending |
| 8 | 2-3 días | Cleanup, release v2.0 | Pending |
| **TOTAL** | **23-35 días** | **v2.0-python released** | **Ready** |

## 🔴 Preguntas Críticas (MUST ANSWER)

**Sin estas respuestas, NO puede proceder:**

1. **¿Acceso a datos entrenamiento?**
   - PATH: `lado_derecho/` + `lado_izquierda/` carpetas
   - Cuántos .set por carpeta?

2. **¿Accuracy MATLAB baseline?**
   - Test accuracy (default ~80%)?
   - Sensitivity + Specificity?

3. **¿Cómo están anotados eventos?**
   - En .set annotations?
   - En CSV separado (PATH)?

4. **¿Un sujeto o múltiples?**
   - Single-subject?
   - Multi-subject?

**→ Responde antes de comenzar Phase 0**

## 📊 Mapeo Equivalencias Críticas

### Características (Phase 1)
- `pwelch()` → `scipy.signal.welch()` ✓ Directo
- `pburg()` → `statsmodels yule_walker()` ⚠️ Aproximación (no equiv. 100%)
- `wavedec()` → `pywt.wavedec()` ✓ Directo
- `bandpower()` → `np.trapz()` ✓ Directo

### Red Neuronal (Phase 3) ⚠️ CRITICAL
- `patternnet([10])` → `torch.nn.Sequential()` → **REQUIERE REENTRENAMIENTO**
- Topología: 9→10→2 (igual)
- Pesos: Diferentes (new random init, nuevo optimizer)
- **Accuracy esperada:** ≥ 78% (baseline ~80%, drop tolerable 2%)

### Serial (Phase 6)
- `serial('COM3')` → `pyserial.Serial()` ✓ Directo
- Formato: `"clase,conf,clase,conf,timestamp\n"` ✓ Igual

## 🏗️ Estructura Carpetas Target

```
src/                    (7 módulos Python)
├── config.py           (parámetros centralizados)
├── feature_extraction.py
├── preprocessing.py
├── model.py            (PyTorch BCINet)
├── predictor.py        (sliding window)
├── validation.py
├── hardware.py
└── utils.py

scripts/                (6 scripts ejecutables)
├── train_model.py
├── predict_continuous.py
├── validate.py
├── send_to_esp32.py
├── test_esp32_sim.py
└── demo.py

tests/                  (unit + integration)
├── test_feature_extraction.py
├── test_preprocessing.py
├── test_model.py
├── test_predictor.py
└── test_hardware.py

data/models/
├── bci_model.pth       (trained weights)
└── normalization_stats.json
```

## 🎓 Decisiones Técnicas Recomendadas

| Decisión | Opción | Ventajas | Desventajas |
|---|---|---|---|
| **Framework NN** | PyTorch | Control granular, debugging fácil | Curva aprendizaje |
| **Alternativa** | TensorFlow/Keras | API simple, rápido prototiping | Menos control |
| **Filtro** | IIR (scipy) + retrain | Rápido, simple | FIR ≠ MATLAB |
| **Alternativa** | FIR exacto (match EEGLAB) | Reproducibilidad | Más complejo |
| **AR modelo** | Yule-Walker statsmodels | Disponible, validated | No es Burg puro |

## ⚠️ Riesgos Top 3

1. **Welch/Burg Python ≠ MATLAB** → Mitigación: Unit tests fase 1 vs. CSV MATLAB
2. **Red neural accuracy < 70%** → Mitigación: Debug fase 1/2, retrain con FIR si necesario
3. **Datos entrenamiento faltantes** → Mitigación: **VERIFICA AHORA acceso carpetas**

## 🔍 Validación Expected Outcomes

```
✓ Features MATLAB = Python (< 1% error RMS)
✓ Predictions MATLAB = Python (≥ 95% coincidencia)
✓ Accuracy Python ≥ 78% (baseline MATLAB ~80%)
✓ Latency ESP32 < 500 ms
✓ Tests pass (80%+ coverage)
✓ v2.0-python tag created
```

## 📚 Documentación Generada

| Doc | Ubicación | Propósito |
|---|---|---|
| **PYTHON_MIGRATION_PLAN.md** | Repo raíz | Plan detallado (este archivo) |
| **MIGRATION_SUMMARY.md** | Repo raíz | Este resumen |
| MIGRATION_GUIDE.md | docs/ | Notas implementación + troubleshooting |
| MATLAB_vs_PYTHON_EQUIVALENCE.md | docs/ | Tablas mapeo detalladas |
| TRAINING_PROCEDURE.md | docs/ | Cómo reentrenar con datos nuevos |
| QUICKSTART_PYTHON.md | docs/ | Guía usuario Python |

## 🚀 Next Steps (Orden Crítico)

1. **HOY:** Responde 4 preguntas críticas
2. **Mañana:** Crea rama Git `feature/python-migration`
3. **Semana 1:** Phase 0 (venv) + Phase 1 (features)
4. **Semana 2-3:** Phase 2-3 (preprocessing + modelo)
5. **Semana 4:** Phase 4-6 (predictor + hardware)
6. **Semana 5:** Phase 7-8 (tests + release)

## 📞 Soporte

- **Plan detallado:** `PYTHON_MIGRATION_PLAN.md` (61 KB, comprehensive)
- **Asistencia IA:** Claude (modelo potente) para implementación Phase 0→8
- **Debugging:** Consultar sección "Debugging Checklists" en plan detallado

---

**Timeline:** 4-5 semanas (optimista con datos disponibles)  
**Fin estimado:** Semana de 2026-12-23 (tag v2.0-python)  
**Modo:** Build (no más PLAN)  

**Ready to implement. Waiting for your answers to critical questions.**
