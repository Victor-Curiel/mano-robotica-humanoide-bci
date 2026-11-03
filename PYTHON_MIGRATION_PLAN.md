# Plan de Migración: MATLAB/EEGLAB → Python/MNE-Python

**Estado:** Plan integral (Ready for implementation)  
**Fecha:** 2026-11-02  
**Autor:** OpenCode BCI System  
**Objetivo:** Migrar completo pipeline BCI de MATLAB a Python tras expiración de licencia

---

## Tabla de Contenidos

1. [Resumen Ejecutivo](#resumen-ejecutivo)
2. [Contexto & Motivación](#contexto--motivación)
3. [Inventario de Dependencias MATLAB](#inventario-de-dependencias-matlab)
4. [Mapeo de Equivalencias Python/MNE](#mapeo-de-equivalencias-pythonmne)
5. [Estructura de Proyecto Propuesta](#estructura-de-proyecto-propuesta)
6. [Fases de Migración Detalladas](#fases-de-migración-detalladas)
7. [Evaluación de Riesgos](#evaluación-de-riesgos)
8. [Preguntas Críticas Antes de Implementar](#preguntas-críticas-antes-de-implementar)
9. [Timeline & Hitos](#timeline--hitos)
10. [Criterios de Éxito](#criterios-de-éxito)
11. [Decisiones Técnicas & Recomendaciones](#decisiones-técnicas--recomendaciones)

---

## Resumen Ejecutivo

### Situación Actual
- **Pipeline:** 9 archivos MATLAB + EEGLAB + 3 toolboxes (Signal Processing, Wavelet, Deep Learning)
- **Problema:** Licencia MATLAB expirada (julio 2026), imposible renovación inmediata
- **Alternativas evaluadas:** EEGLAB standalone (limitado), GNU Octave (lento), MATLAB Online (20 hrs/mes)
- **Decisión:** Migrar completamente a Python con MNE-Python

### Alcance
| Componente | Acción |
|---|---|
| **Lectura EEG** | .cdt (CURRY 8) + .set (EEGLAB) → MNE |
| **Extracción de características** | Welch, Burg, Wavelet (9D) → SciPy, PyWavelets |
| **Entrenamiento red neuronal** | MLP 9→10→2 (MATLAB) → PyTorch/TensorFlow (reentrenamiento) |
| **Predicción continua** | Sliding window (2s, 50% overlap, 1 Hz rate) → Python nativo |
| **Validación** | Confusion matrices, métricas → scikit-learn |
| **Control de hardware** | Serial a ESP32 (115200 baud) → PySerial |
| **Firmware ESP32** | Sin cambios (.ino compilado ya) |

### Deliverables Finales
1. Python v2.0 del pipeline BCI completo
2. Modelo neuronal reentrenado (.pth o .h5)
3. Suite de pruebas unitarias e integración
4. Documentación técnica (MIGRATION_GUIDE.md, TRAINING_PROCEDURE.md)
5. GitHub release tag `v2.0-python`

### Timeline Estimado
**4-5 semanas** (trabajo individual, full-time)  
**Riesgo:** MEDIUM (depende disponibilidad datos entrenamiento + validación de características)

---

## Contexto & Motivación

### Problema Base
Tu proyecto es tesis de Ingeniería Biónica (UPIITA-IPN): interfaz cerebro-computadora que clasifica imagery motora (mano izq vs. derecha) desde señales EEG para controlar mano robótica humanoide.

**Flujo Actual (MATLAB):**
```
EEGLAB GUI
  ↓ (manual: abrir .cdt, filtrar, seleccionar épocas)
  ↓
Epochs .set
  ↓ (MODULO_BATCH_...PLOT.m)
  ↓
Modelo entrenado (Modelo_BCI_Completo_Wav.mat)
  ↓
Predicción continua (control_final.m)
  ↓
ESP32 → Servos (MG995, SG90) → Mano robótica
```

**Problema:** Licencia MATLAB expirada. Alternativas:
- EEGLAB standalone: ✗ No soporta plugins, lectura Curry limitada
- GNU Octave: ✗ Lento, inestable, sin equivalentes directos
- MATLAB Online: ✗ 20 hrs/mes, límites de cómputo
- Licencia Student: ? ~115 USD (por confirmar México), tiempo

**Solución:** Python + MNE-Python (open-source, bien mantenida, comunidad BCI activa)

### Alternativas Evaluadas vs. Python

| Alternativa | Ventajas | Desventajas | Veredicto |
|---|---|---|---|
| EEGLAB compilado | Sin licencia requerida | Sin plugins, funciones limitadas | ✗ Rechazo |
| GNU Octave | Sintaxis similar MATLAB | Rendimiento pobre, inestable | ✗ Rechazo |
| MATLAB Online | Full MATLAB | 20 hrs/mes, límites cómputo | ? Temporal |
| MATLAB Student License | Full MATLAB | ~115 USD, debe renovar anualmente | ? Backup |
| **Python + MNE** | **Open-source, activo, BCI-native** | **Reentrenamiento red, nueva curva aprendizaje** | **✓ Seleccionado** |

### Ventajas Python para BCI
1. **MNE-Python:** Estándar de facto para procesamiento EEG, API intuitiva, bien documentada
2. **Comunidades:** BrainHack, Neuroscience Python, INCF muy activos
3. **Reproducibilidad:** Código abierto, sin vendor lock-in
4. **Rendimiento:** NumPy + SciPy + PyTorch/TensorFlow ≥ MATLAB
5. **Costo:** Gratuito, perpetuo
6. **Deployment:** Python corre en cualquier OS, sin licencia

---

## Inventario de Dependencias MATLAB

### A. Archivos Requiriendo Migración

| # | Archivo | Propósito | Dependencias MATLAB | Complejidad | Estado |
|---|---|---|---|---|---|
| 1 | MODULO_BATCH_EXTRACCION_WELCH_Y_BURG_50TRASLAPE_PLOT.m | Pipeline entrenamiento | Signal Processing, Wavelet, NN Toolbox, EEGLAB | **ALTA** | Core |
| 2 | PREDICTOR_DATOS_CRUDOS.m | Clasificación dedos continua | Signal Processing, Wavelet, EEGLAB | MEDIA | Core |
| 3 | PREDICTOR_MUNECA.m | Clasificación muñeca continua | Igual a #2 | MEDIA | Core |
| 4 | VALIDADOR_CON_LABELS.m | Validación vs. ground truth | MATLAB core | BAJA | Validación |
| 5 | control_final.m | Orquestación maestra | Todos (1-4) + serialport() | **ALTA** | Master |
| 6 | CONVERTIR_CDT_A_SET.m | Conversión formato .cdt→.set | EEGLAB | BAJA | ✓ Ya reemplazado (extraer_epocas_cdt.py) |
| 7 | ENVIAR_A_ESP32.m | Transmisión serial a hardware | serialport() + Signal/Wavelet | MEDIA | Periférico |
| 8 | TEST_ESP32_SIMULADO.m | Validación protocolo offline | MATLAB core | BAJA | Testing |
| 9 | DEMO_FLEXIBLE.m | Demo usuario | Todos | MEDIA | Testing |

**Ubicación actual:** `src/*.m`  
**Total líneas código:** ~2300  
**Funciones auxiliares:** contarComas(), obtenerCampo(), etc. (incorporadas en Python)

### B. Toolboxes MATLAB & Sus Funciones

| Toolbox | Funciones Usadas | Archivos que las Usan |
|---|---|---|
| **Signal Processing** | `pwelch()`, `pburg()`, `hanning()`, `bandpower()` | MODULO, PREDICTOR_*, control_final, ENVIAR |
| **Wavelet** | `wavedec()`, `detcoef()` | MODULO, PREDICTOR_*, control_final, ENVIAR |
| **Neural Network** | `patternnet()`, `train()`, `plotconfusion()` | MODULO (entrenamiento) |
| **EEGLAB** | `eeglab()`, `pop_loadset()`, `pop_eegfilt()`, `pop_chanedit()`, `pop_saveset()`, `eeg_emptyset()`, `eeg_checkset()` | CONVERTIR, MODULO, PREDICTOR_*, control_final |
| **MATLAB Core** | `readtable()`, `confusionmat()`, `isoutlier()`, `zscore()`, `serialport()`, `fopen()`, `fprintf()`, `save()`, `load()` | Todos |

### C. Estructura de Datos MATLAB

```matlab
% Señal EEG
raw.data         % [n_canales × n_muestras]
raw.srate        % Frecuencia muestreo (Hz)
raw.chanlocs     % Posiciones electrodos
raw.times        % Vector tiempo (seg)

% Épocas
epochs.data      % [n_canales × n_muestras × n_épocas]
epochs.event_id  % struct con códigos eventos

% Características
X_Features       % [n_épocas × 9] matriz características
Y_Labels         % [n_épocas × 1] etiquetas (0 o 1)

% Normalización (guardada en .mat)
mu_norm          % [1×9] media por característica
sigma_norm       % [1×9] desviación estándar

% Red neuronal
red_bionica      % network object (patternnet)
% Contiene: pesos, biases, funciones activación, topología
```

### D. Archivos de Configuración Hardcodeados

```matlab
% MODULO_BATCH_EXTRACCION_WELCH_Y_BURG_50TRASLAPE_PLOT.m (líneas 8-9)
carpeta_der = 'C:\Users\vhca1\Desktop\Acquisition\Ordenadas\lado derecho'
carpeta_izq = 'C:\Users\vhca1\Desktop\Acquisition\Ordenadas\lado izquierdo'

% CONVERTIR_CDT_A_SET.m (línea 35)
ruta_entrada = 'C:\Users\vhca1\Desktop\Acquisition\Sin_clasificar\arzaluzImagina280926-1\'

% DEMO_FLEXIBLE.m (línea 46)
ruta_datos = 'C:\Users\vhca1\Desktop\Acquisition\Sin_clasificar\arzaluzImagina280926-1\'

% control_final.m (línea 325)
puerto_com = 'COM7'

% ENVIAR_A_ESP32.m (línea 81)
puerto_com = 'COM3' (default)
```

**ACCIÓN:** En Python → archivo `src/config.py` centralizado.

---

## Mapeo de Equivalencias Python/MNE

### A. Equivalencias por Categoría

#### I/O & Carga de Datos

| Operación | MATLAB | Python | Notas |
|---|---|---|---|
| Cargar .cdt (Curry 8) | Custom `LOAD_CDT.m` | `mne.io.read_raw_curry()` + curryreader | ✓ Ya implementado (extraer_epocas_cdt.py) |
| Cargar .set (EEGLAB) | `pop_loadset()` | `mne.io.read_eeglab()` | Directo |
| Guardar .fif (MNE native) | N/A | `raw.save()` o `epochs.save()` | Mejor formato para Python |
| Cargar modelo entrenado | `load('*.mat')` | `torch.load()` / `model.load_weights()` | **Diferente formato, debe reentrenarse** |
| Guardar datos normalizados | `.mat` binary | `.npy` (NumPy) + `.json` (metadata) | Estándar Python |

#### Procesamiento de Señal

| Operación | MATLAB | Python | Crítico? |
|---|---|---|---|
| Filtro bandpass 13-30 Hz | `pop_eegfilt(EEG, 13, 30)` (FIR) | `mne.filter.filter_data()` o `scipy.signal.iirfilter()` | ⚠️ **FIR vs IIR discrepancia** |
| Filtro notch 60 Hz | `pop_eegnotchfilt()` | `mne.filter.notch_filter()` o `scipy` | Menor impacto |
| Welch PSD | `pwelch(x, window, noverlap, nfft, fs)` | `scipy.signal.welch()` | ✓ Equivalencia directa |
| Burg AR PSD | `pburg(x, order, nfft, fs)` | `statsmodels.tsa.ar_model.yule_walker()` o manual | ⚠️ **No equiv. directa en SciPy** |
| Band power | Manual trapz sobre Welch/Burg | `np.trapz(pxx[idx_min:idx_max])` | ✓ Igual algoritmo |
| DWT Daubechies-4 | `wavedec(x, 'db4', level=4)` | `pywt.wavedec(x, 'db4', level=4)` | ✓ Equivalencia directa |
| Detail coef | `detcoef(C, L, level)` | `C[-(level)]` o `pywt.detcoef()` | ✓ Equivalencia directa |

#### Red Neuronal & Clasificación

| Operación | MATLAB | Python | Crítico? |
|---|---|---|---|
| Crear red MLP | `patternnet([10])` → 9→10→2 | `torch.nn.Sequential()` o `tf.keras.Sequential()` | ⚠️ **Topología igual, pesos ≠** |
| Entrenar | `train(net, X, Y)` | `.fit(X, y, epochs=...)` | ✓ Equivalencia, pero hiperparámetros varían |
| Función pérdida | Cross-entropy (default) | `nn.CrossEntropyLoss()` o `tf.keras.losses.BinaryCrossentropy()` | ✓ Equivalencia |
| Guardador/cargar pesos | `save('*.mat', 'net')` | `torch.save()` / `model.save_weights()` | ✓ Formatos distintos |
| Inferencia | `Y_pred = red_bionica(X)` | `Y_pred = model(X)` | ✓ Equivalencia |

#### Validación & Métricas

| Operación | MATLAB | Python | Notas |
|---|---|---|---|
| Confusion matrix | `confusionmat()` | `sklearn.metrics.confusion_matrix()` | ✓ Directo |
| Accuracy | Manual: (TP+TN)/Total | `sklearn.metrics.accuracy_score()` | ✓ Directo |
| Sensitivity/Recall | Manual: TP/(TP+FN) | `sklearn.metrics.recall_score()` | ✓ Directo |
| Specificity | Manual: TN/(TN+FP) | `sklearn.metrics.fbeta_score()` (custom) | ✓ Fácil implementar |

#### Comunicación Serial

| Operación | MATLAB | Python | Notas |
|---|---|---|---|
| Abrir puerto | `serial('COM3')` + `fopen()` | `pyserial.Serial('/dev/COM3', 115200)` | ✓ Directo |
| Enviar mensaje | `fprintf(puerto, formato, datos)` | `puerto.write(mensaje.encode())` | ✓ Directo |
| Cerrar puerto | `fclose(puerto)` | `puerto.close()` | ✓ Directo |

### B. Parámetros Críticos del DSP (Deben Coincidir con MATLAB)

```python
# Parámetros fijos en MATLAB (hardcoded o derivados)
FS = 500                    # Hz, frecuencia muestreo
L_FREQ = 13                 # Hz, filtro bandpass inferior
H_FREQ = 30                 # Hz, filtro bandpass superior
NOTCH_FREQ = 60             # Hz, notch filter (opcional)

# Welch
WELCH_WINDOW = 'hann'       # Ventana Hanning
WELCH_NPERSEG = 500         # Ventanas de 1 segundo (500 muestras @ 500 Hz)
WELCH_NOVERLAP = 250        # 50% overlap
WELCH_NFFT = 1000           # FFT 1000 puntos

# Burg
BURG_ORDER = 16             # Orden del AR

# Wavelet
WAVELET_FAMILY = 'db4'      # Daubechies-4
WAVELET_LEVEL = 4           # Nivel descomposición

# Sliding window (predicción)
WINDOW_SECS = 2.0           # Ventana 2 segundos
STEP_SECS = 1.0             # Paso 1 segundo (50% overlap)
WINDOW_SAMPLES = int(WINDOW_SECS * FS)  # 1000 muestras
STEP_SAMPLES = int(STEP_SECS * FS)      # 500 muestras

# Red neuronal (entrenamiento)
MLP_HIDDEN = 10             # Neuronas capa oculta
MLP_INPUT = 9               # Dimensión entrada (9 características)
MLP_OUTPUT = 2              # 2 clases (0, 1)
TRAIN_VAL_TEST = (0.7, 0.15, 0.15)  # Split (si se conoce)

# ESP32
ESP32_BAUD = 115200         # Velocidad serial
ESP32_PORT = 'COM3'         # Puerto (configurable)
```

### C. Detección de Discrepancias Esperadas

| Fuente de Discrepancia | MATLAB | Python | Impacto | Solución |
|---|---|---|---|---|
| **Tipo FIR vs IIR** | EEGLAB: FIR (lineal fase) | SciPy default: IIR | MEDIA | Usar FIR en Python (librosa/scipy.signal.firwin) o retrain |
| **Precisión numérica** | float64 (default) | numpy float32/64 (ambas disponibles) | BAJA | Usar float64 en Python |
| **Orden de operaciones** | Operadores MATLAB (distintos) | NumPy/SciPy (puede variar) | BAJA | Test unitario vs. MATLAB |
| **Inicialización red** | MATLAB random seed | PyTorch/TF random seed | MEDIA | Fijar seed (reproducibilidad) |
| **Optimizer training** | MATLAB default (Levenberg-Marquardt) | PyTorch Adam o SGD | MEDIA | Documentar hiperparámetros, retrain |
| **Batch normalization** | N/A (no usado en MATLAB) | Opcional en Python | N/A | No implementar si MATLAB no lo usa |

---

## Estructura de Proyecto Propuesta

### Árbol Directorios

```
mano-robotica-humanoide-bci/
├── src/                                              # Módulos Python (reemplaza MATLAB src/)
│   ├── __init__.py
│   ├── config.py                                     # Parámetros centralizados
│   ├── feature_extraction.py                         # Welch, Burg, Wavelet, bandpower
│   ├── preprocessing.py                              # Carga MNE, filtrado, extracción épocas
│   ├── model.py                                      # Red neuronal (PyTorch o TF)
│   ├── predictor.py                                  # Predicción continua (sliding window)
│   ├── validation.py                                 # Confusion matrices, métricas
│   ├── hardware.py                                   # Interfaz serial ESP32
│   ├── utils.py                                      # Z-score, outlier detection, I/O utils
│   └── logger.py                                     # Logging centralizado
│
├── scripts/                                          # Scripts ejecutables (punto entrada usuario)
│   ├── train_model.py                                # → reemplaza MODULO_BATCH_...PLOT.m
│   ├── predict_continuous.py                         # → reemplaza control_final.m
│   ├── validate.py                                   # → reemplaza VALIDADOR_CON_LABELS.m
│   ├── send_to_esp32.py                              # → reemplaza ENVIAR_A_ESP32.m
│   ├── test_esp32_sim.py                             # → reemplaza TEST_ESP32_SIMULADO.m
│   └── demo.py                                       # → reemplaza DEMO_FLEXIBLE.m
│
├── data/                                             # Datos & modelos
│   ├── models/
│   │   ├── bci_model.pth (o .h5)                    # Pesos entrenados
│   │   └── normalization_stats.json                  # μ, σ para Z-score
│   ├── raw_eeg/                                      # Archivos .cdt/.set entrada
│   │   └── (no versionado, muy grandes)
│   ├── extracted/                                    # Salida extraer_epocas_cdt.py
│   │   ├── Acquisition_11-epo.fif
│   │   ├── Acquisition_11_X.npy
│   │   ├── Acquisition_11_y.npy
│   │   └── Acquisition_11_meta.json
│   └── calibration/                                  # Datos calibración sujeto
│
├── tests/                                            # Unit + integration tests
│   ├── __init__.py
│   ├── test_feature_extraction.py                    # Compara vs. MATLAB
│   ├── test_preprocessing.py
│   ├── test_model.py
│   ├── test_predictor.py
│   ├── test_hardware.py                              # Serial mock
│   ├── fixtures/                                     # Datos prueba (pequeños .cdt/.set)
│   │   └── sample_eeg.set
│   └── conftest.py                                   # pytest config
│
├── docs/                                             # Documentación
│   ├── MIGRATION_PLAN.md                             # Este archivo (plan detallado)
│   ├── MIGRATION_GUIDE.md                            # Notas implementación + troubleshooting
│   ├── MATLAB_vs_PYTHON_EQUIVALENCE.md               # Tablas de mapeo detalladas
│   ├── TRAINING_PROCEDURE.md                         # Cómo reentrenar con datos nuevos
│   ├── QUICKSTART_PYTHON.md                          # Guía rápida Python (reemplaza GUIA_RAPIDA_V2.txt)
│   ├── TROUBLESHOOTING.md                            # Problemas comunes + soluciones
│   ├── (mantener *.txt existentes por ahora)
│
├── arduino/                                          # Sin cambios
│   └── esp32_bci_hand_v2.ino                         # Firmware (ya correcto v3.x compatible)
│
├── modelos/                                          # Deprecated (mantener por referencia)
│   └── Modelo_BCI_Completo_Wav.mat                   # Red antigua MATLAB (deprecada)
│
├── resultados/                                       # Salidas ejecución (gitignored)
│   └── (auto-generado)
│
├── .gitignore                                        # Actualizado para Python
├── .github/workflows/                                # (Opcional) CI/CD
│   └── test.yml                                      # GitHub Actions: run tests
├── pyproject.toml                                    # Packaging Python moderno
├── requirements.txt                                  # Dependencias con versiones fijas
├── setup.py                                          # (Opcional, backward compat)
├── README.md                                         # Actualizado: instrucciones Python
├── PYTHON_MIGRATION_PLAN.md                          # Este plan (en repo)
├── LICENSE                                           # Mantener
└── .gitattributes                                    # Line endings (CRLF vs LF)
```

### Cambios a .gitignore

```gitignore
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
.venv
.eggs/
*.egg-info/
dist/
build/

# Jupyter
.ipynb_checkpoints/
*.ipynb

# IDE
.vscode/
.idea/
*.swp
*.swo

# Testing
.pytest_cache/
.coverage
htmlcov/

# Data (mantenidas excepto señales brutas)
data/raw_eeg/*.cdt
data/raw_eeg/*.set
data/raw_eeg/*.fdt
data/extracted/*.fif          # Opcional: si muy grande
resultados/
*.log

# Models (mantener versionados)
# data/models/*.pth → NO gitignore (versionar)
# data/models/*.json → NO gitignore (versionar)
```

### Archivo requirements.txt

```
numpy>=1.24.0
scipy>=1.10.0
scikit-learn>=1.3.0
matplotlib>=3.7.0
pandas>=2.0.0

# MNE & EEG processing
mne>=1.5.0
pywt>=1.5.0
curryreader>=0.2.0

# Neural networks (elige UNO)
torch>=2.0.0                    # PyTorch (recomendado)
# tensorflow>=2.13.0            # Alternativa: TensorFlow

# Serial communication
pyserial>=3.5

# Testing & development
pytest>=7.4.0
pytest-cov>=4.1.0
flake8>=6.0.0
black>=23.0.0
pylint>=2.17.0

# Documentation
sphinx>=7.0.0
sphinx-rtd-theme>=1.3.0
```

---

## Fases de Migración Detalladas

### FASE 0: Configuración Ambiente (1-2 días)

**Objetivo:** Entorno Python listo, dependencias validadas, repo preparado.

**Tareas:**
1. Crear rama Git: `git checkout -b feature/python-migration`
2. Crear venv Python 3.10+:
   ```bash
   python -m venv venv
   source venv/Scripts/activate  # Windows
   ```
3. Instalar dependencias:
   ```bash
   pip install -r requirements.txt
   ```
4. Verificar imports:
   ```python
   import mne, numpy, scipy, torch  # o tensorflow
   import pywt, curryreader, pyserial
   ```
5. Verificar MNE puede leer .set:
   ```python
   raw = mne.io.read_eeglab('path/to/file.set')
   print(raw)
   ```
6. Ejecutar extraer_epocas_cdt.py (script Python ya existe):
   ```bash
   python Programa\ Pruebas/extraer_epocas_cdt.py
   ```
7. Crear estructura carpetas:
   ```bash
   mkdir -p src scripts data/models data/extracted tests/fixtures
   touch src/__init__.py src/config.py
   ```

**Criterios Aceptación:**
- ✓ Todos los imports funcionan
- ✓ MNE lee archivo .set sin errores
- ✓ extraer_epocas_cdt.py produce output esperado
- ✓ Estructura carpetas creada
- ✓ Rama Git creada y configurada

**Timeline:** 1 día

---

### FASE 1: Librería Extracción de Características (3-4 días)

**Objetivo:** Equivalente Python de Welch + Burg + Wavelet + bandpower, validado vs. MATLAB.

**Tareas:**

1. **Implementar `src/feature_extraction.py`:**
   ```python
   def welch_psd(x, fs=500, window='hann', nperseg=500, noverlap=250, nfft=1000):
       """Welch PSD matching MATLAB pwelch()"""
       from scipy.signal import welch
       freqs, pxx = welch(x, fs=fs, window=window, nperseg=nperseg, 
                          noverlap=noverlap, nfft=nfft)
       return freqs, pxx
   
   def burg_ar_psd(x, order=16, fs=500, nfft=1000):
       """Burg AR PSD (via Yule-Walker as proxy)"""
       from statsmodels.tsa.ar_model import AutoReg
       # Implementar Yule-Walker + AR PSD estimation
       # Retornar frequencies, pxx
       pass
   
   def wavelet_energy(x, wavelet='db4', level=4):
       """Energía de coeficientes wavelet D4 (nivel 4)"""
       import pywt
       coeffs = pywt.wavedec(x, wavelet, level=level)
       # Extraer detail coef nivel 4 (índice -1)
       detail = coeffs[-1]
       energy = np.sum(detail**2) / len(detail)
       return energy
   
   def bandpower(pxx, freqs, f_min=13, f_max=30):
       """Potencia integrada en banda"""
       idx = np.where((freqs >= f_min) & (freqs <= f_max))[0]
       return np.trapz(pxx[idx])
   
   def extract_9d_features(x_3ch, fs=500):
       """Extrae 9 características (Welch:3 + Burg:3 + Wavelet:3)"""
       features = []
       for ch in range(3):
           # Welch
           f, pxx = welch_psd(x_3ch[ch], fs=fs)
           features.append(bandpower(pxx, f))
           
           # Burg
           f, pxx = burg_ar_psd(x_3ch[ch], fs=fs)
           features.append(bandpower(pxx, f))
           
           # Wavelet
           features.append(wavelet_energy(x_3ch[ch]))
       
       return np.array(features)  # [9,]
   ```

2. **Crear test unitario `tests/test_feature_extraction.py`:**
   ```python
   def test_welch_vs_matlab():
       """Compara Welch Python vs. valores MATLAB guardados"""
       # Cargar señal de prueba
       # Ejecutar welch_psd()
       # Cargar resultado MATLAB (CSV)
       # Assert diff < 1%
       pass
   
   def test_9d_features_shape():
       """Verifica output shape [9,]"""
       x = np.random.randn(3, 1000)  # 3 canales, 1000 muestras
       features = extract_9d_features(x)
       assert features.shape == (9,)
   ```

3. **Guardar referencia MATLAB:**
   - En MATLAB, ejecutar sobre archivo de prueba:
     ```matlab
     load('test_eeg.set', '-mat')
     X = data(10:12, :);  % canales C3, C4, Cz
     [f1, p1] = pwelch(X(1,:), hanning(500), 250, 1000, 500);
     save('welch_reference.csv', 'f1', 'p1', '-ascii')
     ```
   - Guardar en `tests/fixtures/welch_reference.csv`
   - Test compara Python vs. archivo

4. **Benchmark Burg:**
   - Investigar si `statsmodels.tsa.ar_model.yule_walker()` + AR PSD cálculo da resultados similares a MATLAB `pburg()`
   - Si no: considerar implementación personalizada o investigar librería `spectrum` (si existe)

**Criterios Aceptación:**
- ✓ Extracción de características coincide MATLAB (< 1% error RMS)
- ✓ Vector [9,] correcto
- ✓ Test unitario pasa
- ✓ Documentado (docstrings)

**Timeline:** 3-4 días

**Preguntas Críticas:**
- ¿Tienes archivo de prueba .set con señal EEG real? (para validación Burg)
- ¿Cuál fue el error esperado Welch MATLAB en banda 13-30 Hz?

---

### FASE 2: Preprocesamiento & Carga de Datos (2-3 días)

**Objetivo:** Loader unificado MNE, filtrado, extracción épocas, consistente con MATLAB.

**Tareas:**

1. **Implementar `src/preprocessing.py`:**
   ```python
   import mne
   
   def load_eeglab_set(filepath):
       """Load .set file via MNE"""
       raw = mne.io.read_eeglab(filepath)
       return raw
   
   def load_curry_cdt(filepath):
       """Load .cdt file via MNE + curryreader"""
       raw = mne.io.read_raw_curry(filepath, preload=True)
       return raw
   
   def apply_filters(raw, l_freq=1, h_freq=40, notch_freq=60, picks='eeg'):
       """Filtro bandpass + notch, matching EEGLAB"""
       raw_filt = raw.copy()
       raw_filt.filter(l_freq, h_freq, picks=picks, method='iir')  # o 'fir'
       if notch_freq:
           raw_filt.notch_filter(notch_freq, picks=picks)
       return raw_filt
   
   def extract_epochs(raw, events, event_id, tmin=-0.5, tmax=2.0, picks='eeg'):
       """Extract epochs from raw signal"""
       epochs = mne.Epochs(raw, events, event_id=event_id,
                          tmin=tmin, tmax=tmax, picks=picks, preload=True)
       return epochs
   
   def get_channel_indices(raw, target_names=['C3', 'C4', 'Cz']):
       """Find indices of target channels"""
       indices = [raw.ch_names.index(name) for name in target_names]
       return indices
   ```

2. **Crear test de carga:**
   ```python
   def test_load_set():
       filepath = 'tests/fixtures/sample.set'
       raw = load_eeglab_set(filepath)
       assert raw.info['sfreq'] == 500
       assert 'C3' in raw.ch_names
   
   def test_filter_consistency():
       """Compara filtro Python vs. MATLAB output"""
       raw_python = apply_filters(raw_orig, l_freq=13, h_freq=30)
       # Cargar raw_matlab filtrado desde .set MATLAB
       # Comparar PSD Welch
       # Assert diff < 2% (permitir IIR vs FIR)
   ```

3. **Validación filtrado:**
   - Si FIR necesario (match MATLAB exacto): usar `scipy.signal.firwin()` + `scipy.signal.filtfilt()`
   - Documentar diferencia FIR vs. IIR

4. **Crear fixtures de prueba:**
   - Guardar pequeño .set (< 1 MB) en `tests/fixtures/`
   - Usar para tests reproducibles

**Criterios Aceptación:**
- ✓ Carga .set sin errores
- ✓ Carga .cdt sin errores
- ✓ Filtrado produce Welch PSD similar a MATLAB (< 2%)
- ✓ Épocas extraídas con shape correcto

**Timeline:** 2-3 días

**Preguntas Críticas:**
- ¿Prefieres FIR (exacto a EEGLAB) o IIR (más rápido, requiere reentrenamiento)?

---

### FASE 3: Reentrenamiento Red Neuronal (5-7 días) ⚠️ **CRÍTICA**

**Objetivo:** Red MLP 9→10→2 entrenada en Python, validada vs. baseline MATLAB.

**Tareas:**

1. **Implementar `src/model.py` (PyTorch):**
   ```python
   import torch
   import torch.nn as nn
   
   class BCINet(nn.Module):
       def __init__(self, input_size=9, hidden_size=10, num_classes=2):
           super().__init__()
           self.fc1 = nn.Linear(input_size, hidden_size)
           self.relu = nn.Tanh()  # MATLAB patternnet usa tanh
           self.fc2 = nn.Linear(hidden_size, num_classes)
       
       def forward(self, x):
           x = self.relu(self.fc1(x))
           x = self.fc2(x)
           return x  # Salida logits (sin softmax explícito)
   
   def train_model(X, y, epochs=100, batch_size=32, lr=0.001):
       """Entrena red neuronal"""
       model = BCINet()
       criterion = nn.CrossEntropyLoss()
       optimizer = torch.optim.Adam(model.parameters(), lr=lr)
       
       for epoch in range(epochs):
           # Shuffle, minibatch, forward, backward, update
           # Log loss
           pass
       
       return model
   ```

2. **Script `scripts/train_model.py`:**
   ```python
   import os
   from pathlib import Path
   import numpy as np
   from src.preprocessing import load_eeglab_set, apply_filters, extract_epochs
   from src.feature_extraction import extract_9d_features
   from src.utils import z_score_normalize, remove_outliers
   from src.model import train_model
   
   # Configuración
   FOLDER_RIGHT = Path('data/raw_eeg/lado_derecho')
   FOLDER_LEFT = Path('data/raw_eeg/lado_izquierda')
   
   # Cargar todos los .set
   X_list, y_list = [], []
   
   for set_file in FOLDER_RIGHT.glob('*.set'):
       raw = load_eeglab_set(set_file)
       raw_filt = apply_filters(raw)
       # Extraer eventos
       events, event_id = mne.events_from_annotations(raw_filt)
       epochs = extract_epochs(raw_filt, events, event_id)
       # Extraer características
       for epoch_data in epochs.get_data():
           features = extract_9d_features(epoch_data)
           X_list.append(features)
           y_list.append(1)  # Clase 1 = derecha
   
   # Ídem para FOLDER_LEFT con y_list.append(0)
   
   X = np.array(X_list)  # [n_épocas, 9]
   y = np.array(y_list)  # [n_épocas]
   
   # Limpiar outliers
   X_clean, y_clean = remove_outliers(X, y, method='iqr')
   
   # Normalizar (Z-score)
   X_norm, mu, sigma = z_score_normalize(X_clean)
   
   # Dividir train/val/test (70/15/15)
   n = len(X_norm)
   perm = np.random.permutation(n)
   X_train = X_norm[perm[:int(0.7*n)]]
   y_train = y_clean[perm[:int(0.7*n)]]
   # ... val, test
   
   # Entrenar
   model = train_model(X_train, y_train, epochs=200, batch_size=32)
   
   # Validar
   acc_val = evaluate(model, X_val, y_val)
   acc_test = evaluate(model, X_test, y_test)
   
   print(f"Accuracy test: {acc_test:.3f}")
   
   # Guardar
   torch.save(model.state_dict(), 'data/models/bci_model.pth')
   
   with open('data/models/normalization_stats.json', 'w') as f:
       json.dump({'mu': mu.tolist(), 'sigma': sigma.tolist()}, f)
   ```

3. **Validación vs. MATLAB:**
   - Ejecutar MATLAB `MODULO_BATCH_...PLOT.m` → obtener:
     - Test accuracy (baseline)
     - Confusion matrix
     - Pesos red (exportar a CSV si posible)
   - Ejecutar Python script
   - Comparar:
     ```
     MATLAB accuracy:  0.82
     Python accuracy:  0.80  ← Aceptable (diff < 5%)
     ```
   - Si diff > 5%: investigar Phase 1/2 (características, filtrado)

4. **Hiperparámetros documentados:**
   - Guardar en `src/config.py`:
     ```python
     TRAINING_CONFIG = {
         'epochs': 200,
         'batch_size': 32,
         'learning_rate': 0.001,
         'optimizer': 'Adam',
         'loss': 'CrossEntropyLoss',
         'train_val_test_split': (0.7, 0.15, 0.15),
     }
     ```

**Criterios Aceptación:**
- ✓ Model entrena sin errores
- ✓ Test accuracy ≥ 78% (si MATLAB ~80%)
- ✓ Weights + normalization stats guardados
- ✓ Curvas loss/acc ploteadas y verificadas
- ✓ Comparación MATLAB documentada

**Timeline:** 5-7 días

**Bloqueadores Potenciales:**
- Falta datos entrenamiento → no puede avanzar
- Accuracy < 70% → debuggear Phase 1/2, probablemente filtro
- Burg AR no coincide → usar Yule-Walker + documentar diferencia

**Preguntas CRÍTICAS para ti:**
1. **¿Tienes acceso a los .set archivos de entrenamiento?** (lado_derecho + lado_izquierda)
2. **¿Cuál fue accuracy MATLAB en test set?** (baseline para Python)
3. **¿Todos los .set tienen eventos anotados?** ¿O hay CSV de eventos?
4. **¿Hay múltiples sujetos o un sujeto?** (para validación cross-subject)

---

### FASE 4: Predicción Continua (Sliding Window) (3-4 días)

**Objetivo:** Predicción tiempo real / offline con ventana deslizante 2s, paso 1s.

**Tareas:**

1. **Implementar `src/predictor.py`:**
   ```python
   import torch
   import numpy as np
   from src.model import BCINet
   from src.feature_extraction import extract_9d_features
   from src.preprocessing import apply_filters
   from src.utils import z_score_normalize_test
   
   class SlidingWindowPredictor:
       def __init__(self, model_path, normalization_stats_path, fs=500):
           self.fs = fs
           self.model = BCINet()
           self.model.load_state_dict(torch.load(model_path))
           self.model.eval()
           
           # Cargar stats
           with open(normalization_stats_path) as f:
               stats = json.load(f)
               self.mu = np.array(stats['mu'])
               self.sigma = np.array(stats['sigma'])
       
       def predict_continuous(self, raw, window_secs=2, step_secs=1):
           """Predicción continua sobre raw signal"""
           raw_filt = apply_filters(raw)  # Filtrar
           
           window_samples = int(window_secs * self.fs)
           step_samples = int(step_secs * self.fs)
           
           predictions, confidences, times = [], [], []
           
           for idx_start in range(0, len(raw) - window_samples, step_samples):
               idx_end = idx_start + window_samples
               window = raw_filt[:3, idx_start:idx_end]  # C3, C4, Cz
               
               # Extraer 9 características
               features = extract_9d_features(window)
               
               # Z-score normalizar
               features_norm = (features - self.mu) / self.sigma
               
               # Inferencia
               x = torch.FloatTensor(features_norm).unsqueeze(0)
               with torch.no_grad():
                   logits = self.model(x)
                   probs = torch.softmax(logits, dim=1)
                   pred = torch.argmax(probs, dim=1).item()
                   conf = probs[0, pred].item()
               
               time = idx_end / self.fs
               predictions.append(pred)
               confidences.append(conf)
               times.append(time)
           
           return np.array(predictions), np.array(confidences), np.array(times)
   ```

2. **Script `scripts/predict_continuous.py`:**
   ```python
   from pathlib import Path
   import matplotlib.pyplot as plt
   from src.preprocessing import load_eeglab_set
   from src.predictor import SlidingWindowPredictor
   
   # Cargar modelo
   predictor = SlidingWindowPredictor(
       'data/models/bci_model.pth',
       'data/models/normalization_stats.json'
   )
   
   # Cargar .set
   set_file = Path('data/raw_eeg/test_file.set')
   raw = load_eeglab_set(set_file)
   
   # Predicción continua
   preds, confs, times = predictor.predict_continuous(raw)
   
   # Plotear
   fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 6))
   
   ax1.plot(times, preds, 'o-', label='Predicción')
   ax1.plot(times, confs, 's--', label='Confianza')
   ax1.set_ylabel('Clase / Confianza')
   ax1.set_xlabel('Tiempo (s)')
   ax1.set_title('Predicciones BCI - Mano Derecha (1) vs Izquierda (0)')
   ax1.legend()
   ax1.grid()
   
   # Histograma
   n0 = np.sum(preds == 0)
   n1 = np.sum(preds == 1)
   ax2.bar([0, 1], [n0, n1])
   ax2.set_xlabel('Clase')
   ax2.set_ylabel('Conteo')
   ax2.set_xticklabels(['Izquierda (0)', 'Derecha (1)'])
   ax2.set_title('Distribución de Predicciones')
   
   plt.tight_layout()
   plt.savefig('resultados/predicciones.png')
   plt.show()
   
   print(f"Total predicciones: {len(preds)}")
   print(f"Izquierda (0): {n0} ({100*n0/len(preds):.1f}%)")
   print(f"Derecha (1): {n1} ({100*n1/len(preds):.1f}%)")
   print(f"Confianza media: {np.mean(confs):.3f}")
   ```

3. **Validación vs. MATLAB:**
   - Ejecutar `PREDICTOR_DATOS_CRUDOS.m` sobre mismo .set
   - Comparar predicciones Python vs. MATLAB
   - Esperar ≥ 95% coincidencia de clase (permite diferencias en confianza)

**Criterios Aceptación:**
- ✓ Predicciones coinciden MATLAB ≥ 95%
- ✓ Timing: 1 prediction/second (consistent)
- ✓ Plots generados y sensibles
- ✓ Output arrays shape correcto

**Timeline:** 3-4 días

---

### FASE 5: Framework Validación (2-3 días)

**Objetivo:** Confusion matrices, métricas (accuracy, sensitivity, specificity) vs. ground truth.

**Tareas:**

1. **Implementar `src/validation.py`:**
   ```python
   import pandas as pd
   from sklearn.metrics import confusion_matrix, accuracy_score, recall_score
   import numpy as np
   
   def load_labels_csv(csv_path):
       """Load event labels from CSV"""
       df = pd.read_csv(csv_path)
       # Expected columns: timestamp_start, timestamp_end, clase
       return df
   
   def map_predictions_to_labels(predictions, times, label_events):
       """Map continuous predictions to event-based labels"""
       labels_continuous = np.zeros_like(predictions)
       
       for _, row in label_events.iterrows():
           t_start, t_end, clase = row['timestamp_start'], row['timestamp_end'], row['clase']
           mask = (times >= t_start) & (times <= t_end)
           labels_continuous[mask] = clase
       
       return labels_continuous
   
   def compute_metrics(y_true, y_pred):
       """Compute confusion matrix + metrics"""
       cm = confusion_matrix(y_true, y_pred, labels=[0, 1])
       acc = accuracy_score(y_true, y_pred)
       sens = recall_score(y_true, y_pred, pos_label=1)  # TP/(TP+FN)
       spec = recall_score(y_true, y_pred, pos_label=0)  # TN/(TN+FP)
       
       return {
           'confusion_matrix': cm,
           'accuracy': acc,
           'sensitivity': sens,
           'specificity': spec
       }
   ```

2. **Script `scripts/validate.py`:**
   ```python
   from src.validation import *
   import matplotlib.pyplot as plt
   import seaborn as sns
   
   # Cargar predicciones (de predict_continuous.py output)
   preds = np.load('resultados/predictions.npy')
   confs = np.load('resultados/confidences.npy')
   times = np.load('resultados/times.npy')
   
   # Cargar labels
   labels_df = load_labels_csv('data/calibration/labels.csv')
   labels = map_predictions_to_labels(preds, times, labels_df)
   
   # Calcular métricas
   metrics = compute_metrics(labels, preds)
   
   # Plotear
   fig, axes = plt.subplots(2, 2, figsize=(12, 10))
   
   # Timeline
   ax = axes[0, 0]
   ax.plot(times, preds, 'o-', label='Predicción', alpha=0.7)
   ax.plot(times, labels, 's-', label='Ground Truth', alpha=0.7)
   ax.set_xlabel('Tiempo (s)')
   ax.set_ylabel('Clase')
   ax.set_title('Predicciones vs. Ground Truth')
   ax.legend()
   ax.grid()
   
   # Confianza
   ax = axes[0, 1]
   ax.plot(times, confs, '-', label='Confianza')
   ax.set_xlabel('Tiempo (s)')
   ax.set_ylabel('Confianza [0-1]')
   ax.set_title('Evolución de Confianza')
   ax.grid()
   
   # Confusion matrix
   ax = axes[1, 0]
   cm = metrics['confusion_matrix']
   sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', ax=ax,
               xticklabels=['Izq (0)', 'Der (1)'],
               yticklabels=['Izq (0)', 'Der (1)'])
   ax.set_xlabel('Predicción')
   ax.set_ylabel('True Label')
   ax.set_title('Confusion Matrix')
   
   # Estadísticas
   ax = axes[1, 1]
   ax.axis('off')
   stats_text = f"""
   Accuracy:   {metrics['accuracy']:.3f}
   Sensitivity: {metrics['sensitivity']:.3f}
   Specificity: {metrics['specificity']:.3f}
   
   Confusion Matrix:
   TP: {cm[1,1]}, FP: {cm[0,1]}
   FN: {cm[1,0]}, TN: {cm[0,0]}
   """
   ax.text(0.1, 0.5, stats_text, fontsize=12, family='monospace')
   
   plt.tight_layout()
   plt.savefig('resultados/validation_report.png')
   plt.show()
   
   # Imprimir
   print("\n=== VALIDACIÓN ===")
   print(f"Accuracy: {metrics['accuracy']:.3f}")
   print(f"Sensitivity: {metrics['sensitivity']:.3f}")
   print(f"Specificity: {metrics['specificity']:.3f}")
   ```

**Criterios Aceptación:**
- ✓ Métricas calculadas correctamente
- ✓ Plots generados (timeline, confusion matrix, stats)
- ✓ Valores coinciden MATLAB ± 1%

**Timeline:** 2-3 días

---

### FASE 6: Integración Hardware (Serial → ESP32) (2-3 días)

**Objetivo:** Enviar predicciones a microcontrolador en tiempo real.

**Tareas:**

1. **Implementar `src/hardware.py`:**
   ```python
   import serial
   import time
   
   class ESP32Interface:
       def __init__(self, port='COM3', baudrate=115200, timeout=1):
           self.port_name = port
           self.baudrate = baudrate
           self.ser = None
       
       def open(self):
           """Abrir puerto serial"""
           try:
               self.ser = serial.Serial(self.port_name, self.baudrate, timeout=1)
               time.sleep(2)  # ESP32 reset
               print(f"Puerto {self.port_name} abierto @ {self.baudrate} baud")
               return True
           except serial.SerialException as e:
               print(f"ERROR: No se pudo abrir {self.port_name}: {e}")
               return False
       
       def send_prediction(self, clase, confianza, timestamp):
           """Enviar una predicción al ESP32"""
           if not self.ser:
               raise RuntimeError("Puerto no abierto")
           
           # Formato: "clase,conf,clase,conf,timestamp\n"
           msg = f"{clase},{confianza:.2f},{clase},{confianza:.2f},{timestamp:.3f}\n"
           
           try:
               self.ser.write(msg.encode('utf-8'))
               return True
           except Exception as e:
               print(f"ERROR enviando: {e}")
               return False
       
       def read_response(self):
           """Leer respuesta del Serial Monitor"""
           if self.ser.in_waiting > 0:
               response = self.ser.readline().decode('utf-8', errors='ignore').strip()
               return response
           return None
       
       def close(self):
           """Cerrar puerto"""
           if self.ser:
               self.ser.close()
               print("Puerto cerrado")
   ```

2. **Script `scripts/send_to_esp32.py`:**
   ```python
   import time
   from pathlib import Path
   from src.preprocessing import load_eeglab_set
   from src.predictor import SlidingWindowPredictor
   from src.hardware import ESP32Interface
   
   # Detectar puerto COM
   import serial.tools.list_ports
   ports = [p.device for p in serial.tools.list_ports.comports()]
   print(f"Puertos disponibles: {ports}")
   
   PORT = 'COM3'  # Configurable
   
   # Abrir ESP32
   esp32 = ESP32Interface(port=PORT)
   if not esp32.open():
       print("No se pudo conectar al ESP32")
       exit(1)
   
   # Cargar modelo
   predictor = SlidingWindowPredictor(
       'data/models/bci_model.pth',
       'data/models/normalization_stats.json'
   )
   
   # Cargar EEG
   raw = load_eeglab_set('data/raw_eeg/test_file.set')
   
   # Predicción continua
   preds, confs, times = predictor.predict_continuous(raw)
   
   # Enviar predicciones
   print("\nEnviando predicciones a ESP32...")
   errors = 0
   for i, (pred, conf, t) in enumerate(zip(preds, confs, times)):
       success = esp32.send_prediction(int(pred), float(conf), float(t))
       if not success:
           errors += 1
       
       # Log cada 10 mensajes
       if (i + 1) % 10 == 0:
           print(f"  [{i+1}/{len(preds)}] clase={pred}, conf={conf:.2f}, t={t:.2f}s")
       
       # Leer respuesta
       response = esp32.read_response()
       if response:
           print(f"    → {response}")
       
       # Pausa entre envíos (simulando rate 1 Hz)
       time.sleep(1)
   
   # Resumen
   print(f"\nEnvío completado: {len(preds)} predicciones, {errors} errores")
   
   # Cerrar puerto
   esp32.close()
   ```

3. **Test serial (mock):**
   ```python
   def test_esp32_message_format():
       """Verifica formato mensaje"""
       msg = f"{1},{0.87:.2f},{1},{0.65:.2f},{1.234:.3f}\n"
       assert msg == "1,0.87,1,0.65,1.234\n"
   
   def test_esp32_interface_mock():
       """Test ESP32Interface con puerto simulado"""
       # Mock de serial.Serial
       from unittest.mock import MagicMock, patch
       
       with patch('serial.Serial') as mock_serial:
           esp32 = ESP32Interface(port='COM3')
           esp32.open()
           success = esp32.send_prediction(1, 0.87, 1.234)
           assert success
           # Verificar que write() fue llamado con formato correcto
   ```

**Criterios Aceptación:**
- ✓ Mensajes se envían a 1 Hz sin errores
- ✓ Serial Monitor muestra recepción
- ✓ Servos responden visiblemente a predicciones
- ✓ Log file genera estadísticas

**Timeline:** 2-3 días

**Pregunta Crítica:**
- ¿ESP32 debe estar conectado durante desarrollo, o con puerto simulado?

---

### FASE 7: Testing & Validación (3-4 días)

**Objetivo:** Pruebas unitarias, integración, cross-validation MATLAB vs. Python.

**Tareas:**

1. **Unit tests:**
   ```bash
   pytest tests/test_feature_extraction.py -v
   pytest tests/test_preprocessing.py -v
   pytest tests/test_model.py -v
   pytest tests/test_predictor.py -v
   pytest tests/test_hardware.py -v
   pytest --cov=src tests/  # Coverage report
   ```

2. **Integration test (`tests/test_integration.py`):**
   ```python
   def test_end_to_end():
       """Full pipeline: .set → features → prediction → ESP32 mock"""
       # Cargar test .set
       raw = load_eeglab_set('tests/fixtures/sample.set')
       
       # Predictor
       predictor = SlidingWindowPredictor(...)
       preds, confs, times = predictor.predict_continuous(raw)
       
       # Validar output
       assert len(preds) > 0
       assert all(p in [0, 1] for p in preds)
       assert all(0 <= c <= 1 for c in confs)
       
       # Mock ESP32 send
       esp32 = ESP32Interface(port='MOCK')
       for pred, conf, t in zip(preds, confs, times):
           success = esp32.send_prediction(pred, conf, t)
           assert success
   ```

3. **Cross-validation MATLAB:**
   - Ejecutar MATLAB pipeline sobre mismo .set
   - Comparar predicciones clase-a-clase
   - Verificar ≥ 95% coincidencia

4. **Documentación:**
   - `docs/MIGRATION_GUIDE.md`: Notas implementación, troubleshooting
   - `docs/MATLAB_vs_PYTHON_EQUIVALENCE.md`: Tablas detalladas
   - `docs/TRAINING_PROCEDURE.md`: Cómo reentrenar con datos nuevos
   - `docs/QUICKSTART_PYTHON.md`: Guía usuario rápida

**Criterios Aceptación:**
- ✓ Todos los unit tests pasan (pytest)
- ✓ Integration test pasa
- ✓ Cross-validation MATLAB ≥ 95%
- ✓ Coverage > 80%
- ✓ Documentación completa

**Timeline:** 3-4 días

---

### FASE 8: Productización & Finalización (2-3 días)

**Objetivo:** Código limpio, versión release, documentación final.

**Tareas:**

1. **Limpieza código:**
   ```bash
   black src/ scripts/ tests/  # Formatea automáticamente
   pylint src/ scripts/ --disable=C0103,R0903  # Checks
   flake8 src/ scripts/ --max-line-length=100
   ```

2. **Agregar docstrings completos:**
   ```python
   def extract_9d_features(x_3ch, fs=500):
       """Extrae vector 9D de características motor imagery.
       
       Computa características Welch (3) + Burg (3) + Wavelet (3)
       en banda motor cortex 13-30 Hz sobre 3 canales (C3, C4, Cz).
       
       Args:
           x_3ch (np.ndarray): [3, n_samples] señal EEG 3 canales
           fs (float): Frecuencia muestreo (Hz). Default: 500
       
       Returns:
           np.ndarray: [9] vector características normalizadas
       
       References:
           MODULO_BATCH_EXTRACCION_WELCH_Y_BURG_50TRASLAPE_PLOT.m
       """
       ...
   ```

3. **Type hints:**
   ```python
   from typing import Tuple, Optional
   
   def predict_continuous(self, raw: mne.io.Raw, 
                         window_secs: float = 2.0,
                         step_secs: float = 1.0) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
       """..."""
   ```

4. **Actualizar README.md:**
   ```markdown
   # Control de Mano Robótica mediante Interfaz Cerebro-Computador
   
   ## Versión Python (v2.0)
   
   Migración completa desde MATLAB/EEGLAB. Pipeline BCI offline
   clasificando motor imagery (mano izq vs. derecha) desde EEG.
   
   ### Quick Start
   
   ```bash
   # Instalar dependencias
   pip install -r requirements.txt
   
   # Entrenar modelo (requiere datos en data/raw_eeg/)
   python scripts/train_model.py
   
   # Predicción continua
   python scripts/predict_continuous.py data/raw_eeg/test.set
   
   # Enviar a ESP32
   python scripts/send_to_esp32.py
   ```
   
   ### Documentación
   - [Plan de Migración](PYTHON_MIGRATION_PLAN.md)
   - [Guía de Entrenamiento](docs/TRAINING_PROCEDURE.md)
   - [Troubleshooting](docs/TROUBLESHOOTING.md)
   ```

5. **Git finalization:**
   ```bash
   git add -A
   git commit -m "chore: Python v2.0 production ready

   - All tests passing
   - Cross-validation MATLAB ≥95%
   - Documentation complete
   - Type hints + docstrings
   "
   git push origin feature/python-migration
   
   # GitHub: Create PR, review, merge to main
   # Tag release
   git tag v2.0-python
   git push origin v2.0-python
   ```

6. **Deprecate MATLAB:**
   - Mover src/*.m → `_MATLAB_LEGACY/` (archival)
   - Agregar nota a README: "MATLAB version deprecated; use Python v2.0"
   - Keep `.mat` model por referencia

**Criterios Aceptación:**
- ✓ Código formateado, linted, type-hinted
- ✓ Docstrings en todas las funciones
- ✓ requirements.txt reproducible (pip install)
- ✓ README actualizado (instrucciones Python)
- ✓ PR creado, revisado, mergeado
- ✓ Tag v2.0-python creado

**Timeline:** 2-3 días

---

## Evaluación de Riesgos

### Matriz Riesgo-Impacto

| Riesgo | Impacto | Probabilidad | Severidad | Mitigación |
|---|---|---|---|---|
| **Welch/Burg no coincide MATLAB** | Características incorrectas → red no entrena | ALTA | CRÍTICA | Phase 1: Unit test detallado vs. MATLAB CSV |
| **FIR vs. IIR filtrado discrepa** | Features degradadas → accuracy baja | ALTA | CRÍTICA | Phase 2: Documentar; opción retrain con IIR |
| **Burg AR sin equivalente Python** | Feature extraction incompleta | MEDIA | CRÍTICA | Investigar yule_walker + manual AR; benchmark |
| **Red neuronal no retrain < 70%** | Pipeline quebrado | MEDIA | CRÍTICA | Phase 3: Debug Phase 1/2; usar EEGLAB FIR filter |
| **Datos entrenamiento faltantes** | No puede reentrenar | ALTA | CRÍTICA | **VERIFICAR AHORA** acceso carpetas lado_derecho + lado_izquierda |
| **Serial latency > 500 ms** | Control servo inestable | BAJA | ALTA | Phase 6: Benchmark; considerar threading |
| **Cross-subject validation falla** | Generalización limitada | MEDIA | MEDIA | Phase 7: Documentar single-subject; plan future work |
| **Curva aprendizaje PyTorch** | Delays implementación | MEDIA | MEDIA | Usar Keras (más simple) si TensorFlow; ejemplos disponibles |
| **MNE cambios API futuro** | Código se rompe | BAJA | MEDIA | Pin versión requirements.txt; monitor releases |

### Plan Contingencia

| Escenario | Probabilidad | Plan B |
|---|---|---|
| Welch/Burg Python ≠ MATLAB | HIGH | Usar MATLAB para features offline, guardar en .npy, cargar Python |
| Accuracy < 70% | MEDIUM | Usar MATLAB .mat model convertido a PyTorch via ONNX (si posible) |
| Datos entrenamiento faltantes | HIGH | Entrenar solo con sujeto actual; documentar como v2.0-beta |
| Serial issues | LOW | Test con ESP32 simulado primero; agregar buffer/logging |

---

## Preguntas Críticas Antes de Implementar

### Tier 1: BLOQUEADORES (debe responder SÍ/NO/PATH)

1. **¿Tienes acceso a los .set de entrenamiento?**
   - Carpeta: `lado_derecho/` (mano derecha imagery)
   - Carpeta: `lado_izquierda/` (mano izquierda imagery)
   - PATH exacto: ?
   - Cuántos .set por carpeta: ?

2. **¿Cuál fue la accuracy test de MATLAB model (Modelo_BCI_Completo_Wav.mat)?**
   - Accuracy: ___%
   - Sensitivity: ___%
   - Specificity: ___%
   - (usado como baseline Python)

3. **¿Los eventos están anotados en los .set?** ¿O hay CSV separado?
   - Si anotados: formato (nombre evento, código)?
   - Si CSV: PATH + columns (timestamp_start, timestamp_end, clase)?

4. **¿Todos los .set son del mismo sujeto o múltiples sujetos?**
   - Sujetos: 1 / 2+ / desconocido
   - (determina si es single-subject o multi-subject)

### Tier 2: PREFERENCIAS TÉCNICAS

5. **FIR vs. IIR filter:** ¿Prioridad es exactitud a EEGLAB o simplicidad/speed?
   - A: Exactitud (usa FIR en Python)
   - B: Simplicidad (IIR, retrain)

6. **Framework red neuronal:** ¿PyTorch o TensorFlow/Keras?
   - PyTorch: más flexible, steeper curve
   - TensorFlow/Keras: simpler API, faster prototyping

7. **Latencia aceptable ESP32:** ¿Cuál es máximo tolerable?
   - < 100 ms (high priority)
   - < 500 ms (acceptable)
   - < 2 s (current MATLAB)

### Tier 3: VALIDACIÓN

8. **¿Tienes CSV labels para archivo test?** (para VALIDADOR_CON_LABELS.py)
   - Sí: PATH?
   - No: OK (validar solo vs. MATLAB predicciones)

9. **¿Hay múltiples sujetos para test cross-subject?**
   - Sí: cuántos + PATHs?
   - No: OK (single-subject para v2.0, plan v2.1)

10. **¿ESP32 conectado durante desarrollo, o usar simulación?**
    - Hardware disponible: Sí / No
    - Si No: mock serial port en tests

---

## Timeline & Hitos

### Cronograma Recomendado (4-5 semanas full-time)

```
SEMANA 1
├─ Lun-Mar: Phase 0 (Environment setup)
│           - Git branch, venv, requirements.txt
│           ✓ Deliverable: venv funcional + repo ready
│
├─ Mié-Vie: Phase 1 (Feature extraction)
│           - Welch, Burg, Wavelet, 9D features
│           - Unit tests vs. MATLAB CSV
│           ✓ Deliverable: src/feature_extraction.py + tests pass

SEMANA 2
├─ Lun-Mar: Phase 2 (Preprocessing)
│           - MNE loaders, filtrado, épocas
│           - Test filtrado vs. MATLAB
│           ✓ Deliverable: src/preprocessing.py + validado
│
├─ Mié-Vie: Phase 3 INICIO (Neural network)
│           - Implementar BCINet
│           - Cargar datos entrenamiento
│           ✓ Deliverable: Model class + data pipeline

SEMANA 3
├─ Lun-Mié: Phase 3 CONTINUACIÓN (Entrenamiento)
│           - Entrenar red
│           - Comparar vs. MATLAB accuracy
│           ✓ Deliverable: Trained model + stats
│
├─ Jue-Vie: Phase 4 (Predictor continuo)
│           - Sliding window predictor
│           - Plots
│           ✓ Deliverable: src/predictor.py + cross-validation

SEMANA 4
├─ Lun-Mar: Phase 5 (Validación)
│           - Confusion matrices, métricas
│           - Validation report
│           ✓ Deliverable: src/validation.py + plots
│
├─ Mié-Jue: Phase 6 (Hardware)
│           - Serial ESP32 interface
│           - Stress test
│           ✓ Deliverable: src/hardware.py + test send

Vie: Buffer (debugging)

SEMANA 5
├─ Lun-Mar: Phase 7 (Testing)
│           - Unit + integration tests
│           - Coverage > 80%
│           ✓ Deliverable: All tests pass
│
├─ Mié: Phase 8 (Finalization)
│        - Code cleanup, linting
│        - Docstrings, type hints
│        - README, docs
│        ✓ Deliverable: Production code
│
├─ Jue-Vie: Review + Tag release
│           - PR review
│           - Merge main
│           - Tag v2.0-python
│           ✓ RELEASE HITO
```

### Milestones Clave

| Milestone | Fecha | Criterio Éxito |
|---|---|---|
| Phase 0 complete | +1 día | venv OK, repo ready |
| Features validated | +4 días | MATLAB error < 1% |
| Preprocessing ready | +7 días | Filter validated |
| **Model retrained** | **+12 días** | **Accuracy ≥ 78%** ⚠️ Critical |
| Predictor working | +15 días | Cross-validation ≥ 95% |
| Hardware integrated | +18 días | Servo responds |
| All tests pass | +21 días | Coverage > 80% |
| **v2.0-python released** | **+23 días** | **Tag created, docs complete** ✓ Final |

### Buffer & Contingencia

- **Built-in buffer:** 1 semana (weeks 2-3 debugging si Phase 1/2 falla)
- **Extended buffer:** 2 semanas (si reentrenamiento problemático)
- **Total:** 4-5 weeks (optimista-realista), 6-7 weeks (pessimistic)

---

## Criterios de Éxito

### End-to-End Verificación

```
✓ PIPELINE FUNCIONAL
  └─ [.cdt/.set] → [Features 9D] → [Model inference] → [ESP32 PWM]

✓ EQUIVALENCIA NUMÉRICA
  └─ Features MATLAB = Python (< 1% error)
  └─ Predictions MATLAB = Python (≥ 95% match)
  └─ Metrics MATLAB = Python (accuracy, sensitivity ± 1%)

✓ PERFORMANCE
  └─ Training converge (loss → 0)
  └─ Test accuracy ≥ 78% (baseline ~80% MATLAB)
  └─ Latency ESP32 < 500 ms

✓ ROBUSTEZ
  └─ Unit tests: 80%+ coverage, all passing
  └─ Error handling: graceful failures, logging
  └─ Multiple subjects: tested on ≥ 2 files si available

✓ DOCUMENTACIÓN
  └─ README Python
  └─ MIGRATION_GUIDE.md
  └─ TRAINING_PROCEDURE.md
  └─ QUICKSTART_PYTHON.md
  └─ Docstrings en todas las funciones
  └─ Type hints completos

✓ VERSIONADO
  └─ Código limpio (linted)
  └─ Commit messages descriptivos
  └─ Git PR reviewed + merged
  └─ Tag v2.0-python creado
  └─ GitHub release publicado
```

---

## Decisiones Técnicas & Recomendaciones

### A. Arquitectura Neural Network

| Decisión | Recomendación | Justificación |
|---|---|---|
| **Framework** | PyTorch | Control granular, debugging más fácil, comunidad BCI activa |
| **Alternativa** | TensorFlow/Keras | Si prefieres API más simple (trade-off: menos control) |
| **Topología** | MLP 9→10→2 (idéntica MATLAB) | Reproducibilidad, baseline clear |
| **Activación oculta** | Tanh | Coincide MATLAB patternnet |
| **Activación salida** | None (logits) | Softmax aplicado en loss (CrossEntropyLoss) |
| **Loss** | CrossEntropyLoss | Binary classification estándar |
| **Optimizer** | Adam (lr=0.001) | Más robusto que SGD, converge rápido |
| **Inicialización pesos** | Pytorch default (Kaiming) | OK, más moderno que MATLAB random |

### B. Procesamiento Señal

| Decisión | Recomendación | Justificación |
|---|---|---|
| **Filtro tipo** | IIR (scipy) + retrain | Más rápido; discrepancia FIR manejable reentrenando |
| **Alternativa** | FIR (match EEGLAB exacto) | Si exactitud crítica; costo: implementación más compleja |
| **Burg implementation** | statsmodels yule_walker | No existe Burg directo en scipy; esta es aproximación mejor |
| **Wavelet library** | PyWavelets (pywt) | Estándar Python, bien mantenida, exacta |

### C. Formato Datos

| Decisión | Recomendación | Justificación |
|---|---|---|
| **EEG I/O** | .fif (MNE native) | Más eficiente que .set; EEGLAB puede leerlo con plugin |
| **Fallback** | Mantener .set | Si no quieres romper compat EEGLAB |
| **Model weights** | .pth (PyTorch) | Nativo, ligero, sin MATLAB dependency |
| **Metadata** | .json | Human-readable, versionable, standard Python |
| **Dataset** | .npy (NumPy) | Rápido, eficiente, estándar ML |

### D. Testing & CI/CD

| Decisión | Recomendación | Justificación |
|---|---|---|
| **Test framework** | pytest | Standard Python, simple, poderoso |
| **Coverage target** | > 80% | Reasonable para código crítico |
| **CI/CD** | GitHub Actions (opcional) | Automate tests en cada push, detectar regresiones |
| **Mock hardware** | serial.Serial mock | Permite testing sin ESP32 físico |

### E. Documentación

| Decisión | Recomendación | Justificación |
|---|---|---|
| **Docs tool** | Markdown + Sphinx (opcional) | Markdown simple, Sphinx si quieres HTML formal |
| **Code docs** | Docstrings (NumPy style) | Estándar Python BCI/ML |
| **Version control** | Este plan (PYTHON_MIGRATION_PLAN.md) | Referencia futura |

---

## Apéndices

### A. Comando Git Workflow

```bash
# Crear rama
git checkout -b feature/python-migration

# Trabajo diario
git add src/feature_extraction.py
git commit -m "feat: implement Welch+Burg+Wavelet feature extraction"
git push origin feature/python-migration

# Crear PR en GitHub
# Esperar review, hacer cambios si needed
# Merge a main

# Release
git tag v2.0-python
git push origin v2.0-python
```

### B. Comandos Testing

```bash
# Run all tests
pytest tests/ -v

# Run specific test file
pytest tests/test_feature_extraction.py -v

# Coverage report
pytest --cov=src tests/ --cov-report=html
# Abre htmlcov/index.html

# Linting
flake8 src/ scripts/ --max-line-length=100
black src/ scripts/ --check  # Dry run
black src/ scripts/           # Apply
```

### C. Debugging Checklists

**Si accuracy < 70%:**
1. ¿Features coinciden MATLAB? → Run Phase 1 tests
2. ¿Filtrado correcto? → Compare Welch pre/post filtro vs. MATLAB
3. ¿Split train/val/test igual? → Print split indices
4. ¿Normalization stats aplicados? → Print mu/sigma valores
5. ¿Network architecture correcto? → Print model topology
6. ¿Learning rate OK? → Plot loss curve

**Si predictions no coinciden MATLAB:**
1. ¿Mismo .set usado? → Verify file path
2. ¿Modelo cargado correctamente? → Print model state_dict keys
3. ¿Sliding window parámetros iguales? → Check window_secs, step_secs
4. ¿Normalización aplicada? → Print normalized feature ranges

**Si ESP32 no recibe:**
1. ¿Puerto correcto? → Verificar device manager / `ls /dev/ttyUSB*`
2. ¿Baud rate OK? → Esperar 115200
3. ¿Mensaje formato? → Imprimir msg antes de enviar
4. ¿Linebreak? → Verificar `\n` al final

---

## Resumen de Deliverables por Fase

| Fase | Deliverables | Status |
|---|---|---|
| 0 | venv, requirements.txt, repo setup | Pending |
| 1 | `src/feature_extraction.py` + tests | Pending |
| 2 | `src/preprocessing.py` + MNE loaders | Pending |
| 3 | Trained model (.pth) + normalization stats (.json) | **Pending (CRITICAL)** |
| 4 | `src/predictor.py` + continuous predictions | Pending |
| 5 | `src/validation.py` + confusion matrices | Pending |
| 6 | `src/hardware.py` + ESP32 interface | Pending |
| 7 | Test suite (unit + integration, 80%+ coverage) | Pending |
| 8 | README, docs, tagged release v2.0-python | Pending |

---

## Contactos & Recursos

### Documentación Externa
- [MNE-Python](https://mne.tools/) — EEG processing
- [PyTorch](https://pytorch.org/) — Neural networks
- [SciPy Signal](https://docs.scipy.org/doc/scipy/reference/signal.html) — DSP
- [PyWavelets](https://pywavelets.readthedocs.io/) — Wavelets
- [PySerial](https://github.com/pyserial/pyserial) — Serial comms

### Comunidades
- BrainHack, Neuroscience Python Slack
- Stack Overflow: tags `mne-python`, `pytorch`, `signal-processing`
- GitHub Issues en proyectos respectivos

---

**Plan completado. Listo para implementación.**

**Próximos pasos:**
1. **Responde las 10 preguntas críticas (sección 8)**
2. **Confirma acceso a datos de entrenamiento**
3. **Selecciona framework (PyTorch vs. TensorFlow)**
4. **Inicia Phase 0 y crea rama Git**

**Revisión de plan:** Recomendable cada semana, ajustar timeline si es necesario.

---

*Documento: PYTHON_MIGRATION_PLAN.md*  
*Fecha: 2026-11-02*  
*Versión: 1.0 (Comprehensive Plan)*  
*Estado: Ready for Implementation*
