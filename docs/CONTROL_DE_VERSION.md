# Control de versiones

Guía de uso de Git para este proyecto. No necesitas leerla completa: la
sección [Ciclo diario](#ciclo-diario) tiene lo essencial.

---

## Qué es este repositorio

| | |
|---|---|
| **Remote** | `https://github.com/Victor-Curiel/mano-robotica-humanoide-bci.git` |
| **Visibilidad** | Privada |
| **Rama principal** | `main` |
| **Herramientas** | Git for Windows 2.55.0 · GitHub Credential Manager |

Versiona **código, modelos y documentación**. No versiona **datos EEG de
sujetos** —ver [Datos sensibles](#datos-sensibles)—.

---

## Ciclo diario

```powershell
git status              # ver qué cambió
git add .               # preparar todos los cambios
git commit -m "mensaje"
git push
```

Tres pasos, siempre en ese orden. Tras `git push`, los cambios están en GitHub.

### Sobre `git`

Si aparece `git : no se reconoce como nombre de un cmdlet`, tu terminal
arrancó antes de que Git se instalara, o quedó con un PATH viejo. Dos formas
de resolverlo:

```powershell
# Opción A — usar la ruta completa (siempre funciona)
& "C:\Program Files\Git\cmd\git.exe" status

# Opción B — reparar el PATH en esta terminal
$env:Path += ";C:\Program Files\Git\cmd"
git --version
```

En una terminal nueva ya funciona directo: `C:\Program Files\Git\cmd` está en
el PATH del sistema.

### Autenticación

No hace falta configurar nada. Git Credential Manager abre una ventana de
navegador la primera vez; después las credenciales quedan cacheadas en Windows.

Si algún día pide contraseña y tu contraseña normal falla: GitHub la
deshabilitó en 2021. Necesitas un token personal
(`Settings → Developer settings → Personal access tokens → Classic`, scope
`repo`).

---

## Clonar en otra computadora

```powershell
git clone https://github.com/Victor-Curiel/mano-robotica-humanoide-bci.git
cd mano-robotica-humanoide-bci
```

Trae todo menos los datos EEG, que no están en el repo.

---

## Commits: cómo escribirlos

Un commit es un registro de un cambio con sentido. La regla práctica:

> Un commit = una cosa. Si tu mensaje dice "arreglé varias cosas", divídelo.

Formato que usamos:

```
<qué cambió> en <ámbito>

<cuerpo: por qué, no qué>
```

Ejemplos reales de este proyecto:

```
Anade normalizacion Z-Score al pipeline de prediccion

pwelch y pburg devuelven magnitudes distintas segun el canal;
sin normalizar la red prioriza C3 sobre Cz por escala, no por
informacion. Se guardan mu_norm y sigma_norm para aplicar la
misma transformacion en prediccion.
```

`git log --oneline` muestra solo la primera línea, que es la que importa.

---

## Deshacer cambios

Según qué te arrepientas:

| Quiero deshacer | Comando | Efecto |
|---|---|---|
| Descartar cambios sin guardar | `git restore src/control_final.m` | Vuelve el archivo a la última versión confirmada |
| Descartar todo lo no confirmado | `git restore .` | ⚠️ Pierdes trabajo sin commit |
| Ver un cambio antes de decidir | `git diff` | Muestra diferencias línea por línea |
| Corregir el mensaje del último commit | `git commit --amend` | Solo si **no** hiciste push |
| Revertir un commit ya subido | `git revert <hash>` | Crea un commit nuevo que lo deshace — **historial seguro** |

> ⚠️ **Nunca** uses `git reset --hard` después de haber hecho push, ni
> `git push --force`. Reescribir historia compartida causa que otras
> máquinas pierdan commits. Si ya subirte algo que no debías, la vía segura es
> `git revert`.

Commits que no contienen datos sensibles se pueden reescribir con
`git commit --amend` **antes** de hacer push, sin riesgo.

---

## Ramas

`main` es el estado que siempre funciona. Para trabajo en curso:

```powershell
git switch -c feature/validacion-multiple-sujetos
# ... trabajas ...
git add .
git commit -m "Anade pipeline de validacion multi-sujeto"
git push -u origin feature/validacion-multiple-sujetos
```

Cuando esté listo:

```powershell
git switch main
git merge feature/validacion-multiple-sujetos
git push
```

En GitHub puedes abrir una Pull Request para revisar los cambios antes de
integrarlos. Útil cuando termines la fase de validación.

---

## Estructura del repo

```
mano-robotica-humanoide-bci/
├── src/          Pipeline MATLAB
├── arduino/      Firmware ESP32
├── modelos/      Red entrenada (.mat)
├── docs/         Esta documentación
├── resultados/   Ignorado por git — salidas de ejecución
├── README.md
└── .gitignore
```

---

## Datos sensibles

`.gitignore` está configurado para que **nunca** se suban datos de sujetos:

```gitignore
respuestas*.xlsx      # cuestionarios identificables
*.log
resultados/*          # se regeneran al ejecutar
```

Las señales EEG (`.cdt`, `.set`, `.fdt`, `Exp_BCI_*.csv`) **no** están
ignoradas por defecto, porque hasta ahora no hay ninguna en esta carpeta. Si
alguna vez las copias aquí, descomenta ese bloque en `.gitignore` antes de
hacer commit:

```gitignore
data/
*.cdt
*.set
*.fdt
*.vhdr
*.eeg
*.vmrk
Exp_BCI_*.csv
```

**Regla:** el repositorio guarda cómo se procesa la señal, nunca la señal.

### El modelo sí se versiona

`modelos/Modelo_BCI_Completo_Wav.mat` (31 KB) está en el repo a propósito:
sin él, el pipeline no es reproducible. Contiene la red entrenada, las
estadísticas de normalización y los parámetros DSP. No contiene datos de
sujetos.

Cuando reentrenes, **sustituye el archivo y commitea**. Así el modelo siempre
corresponde al código que lo produjo.

---

## Privacidad del email en el historial

La configuración local del repo usa el correo real. Queda visible en los
commits. Para usar el correo anonimizado de GitHub:

```powershell
git config user.email "12345678+Victor-Curiel@users.noreply.github.com"
```

Solo aplica a commits **futuros**; los anteriores conservan el valor original.
Para limpiarlos hay que reescribir historia, así que decide ahora si te importa.

---

## Qué hacer en cada fase de la tesis

Cuando cierres cada hito, deja rastro:

```powershell
git tag -a validacion-sujetos -m "Validacion con 3 sujetos de prueba"
git push --tags
```

Los tags crearían releases ordenadas en GitHub
(`https://github.com/Victor-Curiel/mano-robotica-humanoide-bci/releases`),
que es justo lo que pide un jurado: poder ver la evolución del trabajo.

Hitos previstos:

- `v1.0-pipeline-offline` — extracción, entrenamiento y predicción
- `v1.1-integracion-esp32` — firmware y control de servos
- `v2.0-validacion-multiple-sujetos` — *(pendiente)*
- `v2.1-modelo-robustecido` — *(pendiente)*

---

## Referencia rápida

| Quiero... | Comando |
|---|---|
| Ver qué cambió | `git status` |
| Ver diferencias detalladas | `git diff` |
| Ver historial | `git log --oneline --graph` |
| Subir cambios | `git add . && git commit -m "msg" && git push` |
| Descargar cambios de GitHub | `git pull` |
| Ver qué rama estoy | `git branch` |
| Cambiar de rama | `git switch main` |
| Deshacer archivo sin commit | `git restore <archivo>` |

---

**Documento generado el 2026-10-05** · Git 2.55.0 · rama `main`