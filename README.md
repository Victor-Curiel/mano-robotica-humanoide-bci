# Control de Mano Robótica Humanoide mediante Interfaz Cerebro-Computador

Sistema BCI offline que clasifica, con la mano dominante (derecha), tres estados a
partir de EEG: **basal**, **apretar** (flexión de dedos) y **estirar** (pronación de
la muñeca), y comanda una mano robótica de 2 grados de libertad.

- **MG995** → cierre/apertura simultánea de los dedos 1-5 (GPIO 23)
- **SG90** → pronación de la muñeca (GPIO 17)

> Tesis terminal — UPIITA. Versión vigente: **Python** (MATLAB archivado en `_MATLAB_LEGACY/`).

---

## Estados y mapeo al hardware

| Estado | Clase | (dedos, muñeca) | Estímulo | Acción |
|---|:-:|:-:|---|---|
| basal   | 0 | (0,0) | ninguno | reposo (muñeca 0°, dedos abiertos) |
| apretar | 1 | (1,0) | círculo rojo + tono 1000 Hz | MG995 cierra el puño (PWM 120) |
| estirar | 2 | (0,1) | cuadrado verde + tono 500 Hz | SG90 pronación (PWM 60) |

El estado (1,1) no existe. Protocolo serial (115200 baud): `ded,conf,mun,conf,timestamp\n`,
p. ej. `1,0.87,0,0.87,1.234`.

---

## Mapeo de canales (casco → registro de Curry)

Las features se calculan en este orden. Aplica a **todos los registros nuevos**
(carpetas `Ojos Abiertos` / `Ojos Cerrados`):

| Posición en el casco | Nombre en Curry |
|---|---|
| C3 | **PZ** |
| C4 | **P8** |
| Cz | **P4** |

El canal **ECG** del registro se usa como **EMG** para guiarse en el movimiento del
sujeto; solo se visualiza, no entra al entrenamiento. Se define en `src/config.py`
(`CHANNELS`, `EMG_CHANNEL`).

---

## Pipeline

```
EEG (.cdt)  +  CSV de estímulos (Registro De Pruebas/)
   │
   ├─► seleccionar_epocas   marcar eventos (visor con EEG + EMG)  → eventos.csv
   ├─► cdt_to_set epochs    filtro FIR 8-12 Hz, ventanas de 1 s   → datos/epocas/<estado>/*.set
   ├─► Características 9D   Welch (3) + Burg orden 16 (3) + Wavelet db4 D4 (3), banda 8-12 Hz
   ├─► IQR + z-score        elimina artefactos y normaliza
   ├─► MLP 9 → 10 (tanh) → 3 (softmax)
   ├─► Predicción continua  ventana 1 s, paso 0.5 s
   └─► Serial 115200 baud → ESP32 → MG995 + SG90
```

---

## Instalación

El entorno virtual va **fuera de OneDrive** (límite de ruta larga de Windows):

```powershell
python -m venv C:\bcivenv
C:\bcivenv\Scripts\python -m pip install -r requirements.txt
```

No hace falta activarlo: se llama directamente a `C:\bcivenv\Scripts\python`.
Requiere Python 3.10+ (probado con 3.12).

---

## Flujo de trabajo (paso a paso)

Ejecutar desde la raíz del repositorio.

**1. Correr el experimento** y anotar en Curry la hora exacta de inicio de la grabación:

```powershell
C:\bcivenv\Scripts\python src\Experimento.py          # estímulo 2 s, ISI 2-6 s
C:\bcivenv\Scripts\python src\ExperimentoRapido.py    # estímulo 0.5 s, ISI 0.8-1.8 s
```
El CSV con los timestamps de cada estímulo queda en `Registro De Pruebas/`.

**2. Seleccionar épocas** en el visor (acepta un `.cdt`/`.set` o una carpeta con uno solo):

```powershell
C:\bcivenv\Scripts\python -m src.seleccionar_epocas "ruta\Acquisition 01.cdt" `
  --stimuli "Registro De Pruebas\<csv>" --start HH:MM:SS.fff --basal-auto
```
Teclas: arrastrar = marcar segmento · `b`/`a`/`e` = basal/apretar/estirar · `x` = descartar
el evento más cercano · `u` = deshacer · `[` `]` = desplazar estímulos ±0.25 s ·
`m` = EMG (ambas/señal/envolvente) · flechas = navegar · `s` = guardar `eventos.csv`.
Opciones: `--emg-canal ECG`, `--out`.

**3. Cortar épocas** a partir del `eventos.csv`:

```powershell
C:\bcivenv\Scripts\python -m src.cdt_to_set epochs "ruta\Acquisition 01.cdt" `
  --events "ruta\eventos.csv"
```
La sesión se deduce de la carpeta (`arturoOjosAbiertos091126-1` → `arturo091126-1`); también
se puede dar con `--session`. `cdt_to_set convert` genera un `.set` continuo con anotaciones.

**4. Entrenar y validar:**

```powershell
C:\bcivenv\Scripts\python -m src.train_model                 # deja una sesión fuera
C:\bcivenv\Scripts\python -m src.train_model --por-sujeto    # deja un sujeto fuera
```
Guarda `modelos/bci_model.pth` y `modelos/normalization_stats.json`.

**5. Predecir / enviar al ESP32:**

```powershell
C:\bcivenv\Scripts\python -m src.predict_continuous archivo.cdt --dry-run
C:\bcivenv\Scripts\python -m src.predict_continuous archivo.cdt --port COM3
```

**6. Validar contra etiquetas** (CSV `t_start,t_end,clase`):

```powershell
C:\bcivenv\Scripts\python -m src.validate labels.csv
```

**7. Pruebas:** `C:\bcivenv\Scripts\python -m pytest`

---

## Herramientas (qué hace cada una y qué sustituye)

| Programa | Función | Sustituye (MATLAB) |
|---|---|---|
| `src/Experimento.py`, `ExperimentoRapido.py` | Presentan estímulos (figura + tono) y registran timestamps | — (nuevo) |
| `src/seleccionar_epocas.py` | Visor EEG + EMG para marcar eventos | selección manual en EEGLAB |
| `src/cdt_to_set.py` | `.cdt` → `.set` y corte de épocas por evento | `CONVERTIR_CDT_A_SET.m` |
| `src/train_model.py` | Características, IQR, z-score, validación y entrenamiento | `MODULO_BATCH_...PLOT.m` |
| `src/predict_continuous.py` | Predicción con ventana deslizante y envío serial | `control_final.m`, `PREDICTOR_*.m`, `ENVIAR_A_ESP32.m`, `DEMO_FLEXIBLE.m`, `TEST_ESP32_SIMULADO.m` |
| `src/validate.py` | Matriz de confusión y recall por clase | `VALIDADOR_CON_LABELS.m` |
| `src/config.py` | Parámetros y rutas centralizados | variables al inicio de cada `.m` |
| `src/feature_extraction.py` | Welch, Burg, wavelet, bandpower | `pwelch`, `pburg`, `wavedec`, `bandpower` |
| `src/preprocessing.py` | Carga, filtrado, dataset, sesiones | `pop_loadset`, `pop_eegfilt` |
| `src/model.py`, `predictor.py` | MLP y predicción | `patternnet`, `train` |
| `src/utils.py`, `validation.py`, `hardware.py` | IQR/z-score, métricas, serial | `isoutlier`, `zscore`, `confusionmat`, `serialport` |

Detalle ampliado en `docs/RESUMEN_MIGRACION_PYTHON.txt`.

---

## Estructura del repositorio

```
src/              Código Python (módulos y programas)
arduino/          Firmware ESP32 (esp32_bci_hand_v2.cpp, 3 estados)
modelos/          Modelo entrenado (.pth + JSON), LEGACY_* y .mat de MATLAB
datos/            Datos de sujetos (ignorados por git): cdt/, epocas/, ojos_abiertos/, ojos_cerrados/
Registro De Pruebas/  CSV de timestamps de estímulos (ignorados por git)
docs/             Documentación (los .txt de V2 describen la versión MATLAB, legado)
tests/            Pruebas automáticas (pytest)
resultados/       Salidas de ejecución (ignoradas)
_MATLAB_LEGACY/   Scripts .m originales
```

---

## Hardware

| Actuador | Pin | Señal | Rango PWM |
|---|---|---|---|
| MG995 (dedos 1-5) | GPIO 23 | Rojo→VIN · Negro→GND · Amarillo→GPIO | 30 – 120 |
| SG90 (muñeca) | GPIO 17 | Rojo→VIN · Negro→GND · Amarillo→GPIO | 60 – 90 |

PWM a 50 Hz, 10 bits, un canal LEDC por servo. Alimentación: 5 V @ 2.5 A mínimo.
Cargar el firmware con Arduino IDE (ESP32-WROOM-32, 115200 baud) y verificar en el
Serial Monitor: `Sistema listo. Esperando datos de MATLAB...` (el texto del firmware
conserva esa frase por herencia).

---

## Estado del proyecto

- [x] Migración MATLAB → Python (pipeline, visor, conversión, tests)
- [x] Firmware con 3 estados (sin compilar/probar en hardware)
- [ ] Marcar eventos y entrenar el modelo de 3 estados con los registros nuevos
- [ ] Validación entre sujetos (Arturo, Arza, Marco)
- [ ] Comparación ojos abiertos vs. cerrados (carpeta `Ojos Cerrados` aún vacía)
- [ ] Prueba con el ESP32 conectado

---

## Control de versiones

Repositorio **privado**: `github.com/Victor-Curiel/mano-robotica-humanoide-bci`. Rama de
trabajo `feature/python-migration`. Se versiona código, modelos y documentación; las
señales EEG y los CSV de estímulos quedan fuera por confidencialidad. Guía en
[`docs/CONTROL_DE_VERSION.md`](docs/CONTROL_DE_VERSION.md).

## Consideraciones éticas

Los datos corresponden a sujetos de prueba y no se versionan.
