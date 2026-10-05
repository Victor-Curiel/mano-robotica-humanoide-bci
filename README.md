# Control de Mano Robótica Humanoide mediante Interfaz Cerebro-Computador

Sistema BCI offline que clasifica imagery motora (mano izquierda vs. derecha) a partir
de señales EEG y controla una mano robótica de 2 grados de libertad.

- **1 × MG995** → cierre/aperura simultánea de los dedos 1-5 (GPIO 23)
- **1 × SG90** → pronación de la muñeca (GPIO 17)

> Tesis terminal — UPIITA. Procesamiento offline, control en tiempo de ejecución.

---

## Arquitectura

```
EEG (.cdt / .set)
   │
   ├─► Conversión           CONVERTIR_CDT_A_SET.m
   │
   ├─► Extracción de características (9D)
   │     ├─ Welch PSD      C3, C4, Cz   banda Beta 13-30 Hz
   │     ├─ Burg PSD       C3, C4, Cz   AR order 16
   │     └─ Wavelets D4    db4, nivel 4
   │
   ├─► Normalización        Z-Score  (mu_norm, sigma_norm)
   │
   ├─► Clasificación        MLP 9 → 10 → 2   (patternnet)
   │     clase 1 = Mano Derecha    -> cierra el puño
   │     clase 0 = Mano Izquierda  -> pronación de la muñeca
   │
   ├─► Predicción continua  ventana 2 s · traslape 50 % · decisión cada 1 s
   │
   └─► Serial COM3 @ 115200 baud
         │
         └─► ESP32 ─► MG995 (dedos) + SG90 (muñeca)
```

---

## Mapeo de movimientos

Cada clase comanda **un solo servo**; el otro vuelve a su posición inicial.

| Clase | Significado | MG995 — dedos | SG90 — muñeca |
|:-----:|-------------|---------------|---------------|
| `1`   | **Mano Derecha** (imaginar cerrar la mano) | PWM 120 — **cierra el puño** | PWM 90 — posición inicial |
| `0`   | **Mano Izquierda** (imaginar rotar la muñeca) | PWM 30 — posición inicial (resorte) | PWM 60 — **pronación** |

La asignación de etiquetas no es una convención de este repo: el script de
entrenamiento define `Y=1` para la carpeta `lado derecho` y `Y=0` para
`lado izquierdo` (`src/MODULO_BATCH_EXTRACCION_WELCH_Y_BURG_50TRASLAPE_PLOT.m`,
línea 154). Por eso **clase 1 siempre significa mano derecha**.

---

## Estructura del repositorio

```
bci-mano-robotica/
├── src/                    Pipeline MATLAB
│   ├── control_final.m               Script maestro (punto de entrada)
│   ├── CONVERTIR_CDT_A_SET.m         Neuroscan .cdt → EEGLAB .set
│   ├── MODULO_BATCH_...PLOT.m        Entrenamiento del modelo
│   ├── PREDICTOR_DATOS_CRUDOS.m     Predicción DEDOS
│   ├── PREDICTOR_MUNECA.m            Predicción MUÑECA
│   ├── VALIDADOR_CON_LABELS.m        Validación vs. ground truth
│   ├── ENVIAR_A_ESP32.m              Integración serial
│   ├── TEST_ESP32_SIMULADO.m         Test sin hardware
│   └── DEMO_FLEXIBLE.m               Demo con rutas configurables
├── arduino/
│   └── esp32_bci_hand_v2.cpp         Firmware ESP32
├── modelos/
│   └── Modelo_BCI_Completo_Wav.mat   Red entrenada + normalización
├── docs/
│   ├── CONTROL_DE_VERSION.md           Git, ramas, datos sensibles
│   ├── GUIA_RAPIDA_V2.txt            Inicio rápido
│   ├── CARGAR_EN_ARDUINO_V2.txt      Carga del firmware
│   ├── RESUMEN_SISTEMA_V2.txt        Documentación técnica
│   └── INICIO_RAPIDO.txt             Referencia de ejecución
├── resultados/              Salidas de ejecución (ignoradas por git)
└── .gitignore
```

---

## Control de versiones

Repositorio **privado** en `github.com/Victor-Curiel/mano-robotica-humanoide-bci`,
rama `main`.

```powershell
git status              # ver qué cambió
git add .
git commit -m "mensaje"
git push
```

Se versiona **código, modelos y documentación**. Las señales EEG de los sujetos
de prueba quedan fuera del repositorio por confidencialidad: el repo guarda
*cómo* se procesa la señal, nunca la señal. El modelo entrenado
(`modelos/Modelo_BCI_Completo_Wav.mat`) sí se versiona, porque sin él el
pipeline no es reproducible.

Guía completa —deshacer cambios, ramas, tags por hito de tesis, resolución de
problemas de PATH— en [`docs/CONTROL_DE_VERSION.md`](docs/CONTROL_DE_VERSION.md).

---

## Requisitos

| Componente | Versión |
|------------|---------|
| MATLAB      | 2026a    |
| EEGLAB      | versión verificada en MATLAB 2026a |
| Signal Processing Toolbox | requerido (`pwelch`, `pburg`, `bandpower`) |
| Wavelet Toolbox | requerido (`wavedec`, `detcoef`) |
| Deep Learning Toolbox | requerido (`patternnet`, `train`) |
| Arduino IDE | 2.x con soporte ESP32 |
| ESP32       | ESP32-WROOM-32 |

---

## Uso

### 1. Cargar el firmware (una sola vez)

```bash
# Arduino IDE → Preferences → Additional boards manager URLs:
#   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
#
# Tools → Board      → ESP32-WROOM-32
# Tools → Port       → COM3
# Copiar arduino/esp32_bci_hand_v2.cpp en un sketch nuevo
# Sketch → Upload
```

Verificar en Serial Monitor (115200 baud):
```
Sistema listo. Esperando datos de MATLAB...
```

### 2. Ejecutar el pipeline

```matlab
>> control_final('C:\ruta\a\archivo.cdt')
```

El script maestro ejecuta el pipeline completo y activa los servos.
Detalle en `docs/GUIA_RAPIDA_V2.txt`.

### 3. Entrenar / reentrenar el modelo

```matlab
>> MODULO_BATCH_EXTRACCION_WELCH_Y_BURG_50TRASLAPE_PLOT
```

Lee las carpetas `carpeta_der` y `carpeta_izq` (definidas en las líneas 8-9 del script),
extrae características de cada `.set`, limpia artefactos con IQR y guarda
`modelos/Modelo_BCI_Completo_Wav.mat`.

---

## Hardware

| Actuador | Pin | Señal | Rango PWM |
|----------|-----|-------|-----------|
| MG995 (dedos 1-5) | GPIO 23 | Rojo→VIN · Negro→GND · Amarillo→GPIO | 30 – 120 |
| SG90 (muñeca)     | GPIO 17 | Rojo→VIN · Negro→GND · Amarillo→GPIO | 60 – 90 |

PWM a 50 Hz, resolución 10 bits, canal único para sincronía.
Alimentación: 5 V @ 2.5 A mínimo.

---

## Protocolo serial

```
"clase_ded,conf_ded,clase_mun,conf_mun,timestamp\n"
"1,0.87,1,0.65,1.234\n"
```

---

## Estado del proyecto

- [x] Pipeline offline funcional (extracción → normalización → clasificación → predicción)
- [x] Integración ESP32 + 2 servos
- [ ] Validación con señales de otros sujetos de prueba
- [ ] Robustecer la red con nuevos *sets* de entrenamiento
- [ ] Validación acoplada completa con labels manuales

---

## Consideraciones éticas

Este repositorio es **privado**. Las señales EEG corresponden a sujetos de prueba y
no se versionan. Mantener los datos fuera del control de versiones; versionar
únicamente código, modelos y documentación.