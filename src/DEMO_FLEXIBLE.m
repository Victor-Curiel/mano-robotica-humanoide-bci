%% DEMO_FLEXIBLE
% Demostración flexible del sistema BCI con cambio fácil de rutas
%
% Este script está diseñado para cambiar fácilmente entre diferentes archivos.
% Simplemente modifica las rutas en la sección CONFIGURACIÓN y ejecuta.
%
% USO:
%   >> DEMO_FLEXIBLE
%
% VENTAJAS:
%   - Fácil de modificar rutas
%   - No requiere editar el flujo principal
%   - Pueden probarse diferentes archivos .cdt/.set
%   - Labels opcionales (si no existen, solo predice)
%
% EJEMPLO 1: Usar archivo ACTUAL
%   ruta_datos = 'C:\Users\vhca1\Desktop\Acquisition\Sin_clasificar\arzaluzImagina280926-1\';
%   archivo_cdt = 'Acquisition 15.cdt';
%
% EJEMPLO 2: Usar archivo DE OTRA CARPETA
%   ruta_datos = 'C:\Users\vhca1\Desktop\Acquisition\Ordenadas\lado derecho\';
%   archivo_cdt = 'MD_marco260226-1.cdt';
%
% EJEMPLO 3: Usar archivo .set DIRECTO (sin convertir)
%   usar_cdt = false;  % Cambiar a false
%   archivo_set = 'mi_archivo_ya_procesado.set';
%
% AUTOR: OpenCode BCI System
% FECHA: 2026-09-30
%

clc; close all; clear all;

fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('    DEMO FLEXIBLE - Sistema BCI (Fácil Cambio de Archivos)\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

%% ╔══════════════════════════════════════════════════════════════╗
%% ║  CONFIGURACIÓN - MODIFICA AQUÍ PARA CAMBIAR ARCHIVOS        ║
%% ╚══════════════════════════════════════════════════════════════╝

% ============ OPCIÓN 1: Usar archivo .cdt ==============
usar_cdt = true;  % true = convertir .cdt a .set | false = usar .set directo

% Carpeta donde está el archivo
ruta_datos = 'C:\Users\vhca1\Desktop\Acquisition\Sin_clasificar\arzaluzImagina280926-1\';

% Nombre del archivo .cdt (SOLO si usar_cdt = true)
archivo_cdt = 'Acquisition 15.cdt';

% ============ OPCIÓN 2: Usar archivo .set DIRECTO ==============
% Si usar_cdt = false, necesitas tener el archivo .set
% archivo_set = 'tu_archivo_procesado.set';

% ============ MODELO Y LABELS ==============
modelo_mat = 'Modelo_BCI_Completo_Wav.mat';
csv_labels = fullfile(ruta_datos, 'labels_reales.csv');

% ============ PARÁMETROS OPCIONALES ==============
% Puedes cambiar estos parámetros para la predicción
duracion_ventana = 2;    % segundos
paso_prediccion = 1;     % segundos
validar_con_labels = true;  % true = validar, false = solo predecir

fprintf('CONFIGURACIÓN ACTUAL:\n');
fprintf('  Carpeta: %s\n', ruta_datos);
if usar_cdt
    fprintf('  Archivo: %s (convertirá a .set)\n', archivo_cdt);
else
    fprintf('  Archivo: %s (ya es .set)\n', archivo_set);
end
fprintf('  Modelo: %s\n', modelo_mat);
fprintf('  Validar con labels: %s\n', string(validar_con_labels));
fprintf('  Duración ventana: %d seg, Paso: %d seg\n\n', duracion_ventana, paso_prediccion);

%% PASO 0: VALIDAR RUTAS
fprintf('VALIDANDO RUTAS Y ARCHIVOS...\n\n');

% Verificar que existen los archivos necesarios
if usar_cdt
    archivo_entrada_completo = fullfile(ruta_datos, archivo_cdt);
    if ~exist(archivo_entrada_completo, 'file')
        error('ERROR: No se encontró %s', archivo_entrada_completo);
    end
    fprintf('  ✓ Archivo .cdt encontrado: %s\n', archivo_entrada_completo);
end

if ~exist(modelo_mat, 'file')
    error('ERROR: No se encontró modelo %s', modelo_mat);
end
fprintf('  ✓ Modelo encontrado: %s\n', modelo_mat);

labels_existen = exist(csv_labels, 'file');
if labels_existen
    fprintf('  ✓ Labels encontrados: %s\n', csv_labels);
    validar_con_labels = true;
else
    fprintf('  ⚠ Labels NO encontrados: %s\n', csv_labels);
    fprintf('    (Se hará predicción sin validación)\n');
    validar_con_labels = false;
end

fprintf('\n');

%% PASO 1: CONVERTIR .cdt A .set (SI APLICA)
if usar_cdt
    fprintf('════════════════════════════════════════════════════════════\n');
    fprintf('PASO 1: Convertir .cdt → .set\n');
    fprintf('════════════════════════════════════════════════════════════\n');
    
    CONVERTIR_CDT_A_SET(archivo_cdt);
    archivo_set = strrep(archivo_cdt, '.cdt', '_crudo.set');
end

archivo_set_completo = fullfile(ruta_datos, archivo_set);

%% PASO 2: CARGAR MODELO
fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('PASO 2: Verificar modelo entrenado\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

if ~exist(modelo_mat, 'file')
    error('ERROR: %s no encontrado. Ejecuta MODULO_BATCH_EXTRACCION primero', modelo_mat);
end

load(modelo_mat, 'red_bionica', 'X_Norm', 'Y_Clean');
fprintf('✓ Modelo cargado\n');
fprintf('  - Características en training: %d\n', size(X_Norm, 1));
fprintf('  - Clases training: %d\n\n', sum(Y_Clean == 1));

%% PASO 3: PREDICCIÓN DEDOS
fprintf('════════════════════════════════════════════════════════════\n');
fprintf('PASO 3: Predicción DEDOS (Abre/Cierra)\n');
fprintf('════════════════════════════════════════════════════════════\n');

[pred_ded, conf_ded, tiempo, EEG_filt] = PREDICTOR_DATOS_CRUDOS(...
    archivo_set_completo, modelo_mat, ...
    'duracion_ventana', duracion_ventana, ...
    'paso', paso_prediccion);

%% PASO 4: PREDICCIÓN MUÑECA
fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('PASO 4: Predicción MUÑECA (Pronación/Supinación)\n');
fprintf('════════════════════════════════════════════════════════════\n');

[pred_mun, conf_mun, ~] = PREDICTOR_MUNECA(archivo_set_completo, modelo_mat);

%% PASO 5: VALIDACIÓN (SI HAY LABELS)
if validar_con_labels
    fprintf('\n════════════════════════════════════════════════════════════\n');
    fprintf('PASO 5: Validación con Labels Reales\n');
    fprintf('════════════════════════════════════════════════════════════\n');
    
    [cm_ded, cm_mun, acc_ded, acc_mun] = VALIDADOR_CON_LABELS(...
        pred_ded, conf_ded, ...
        pred_mun, conf_mun, ...
        tiempo, csv_labels);
else
    cm_ded = [];
    cm_mun = [];
    acc_ded = [];
    acc_mun = [];
end

%% PASO 6: RESUMEN FINAL
fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('RESUMEN FINAL\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

fprintf('ARCHIVO PROCESADO:\n');
fprintf('  %s\n', archivo_set_completo);
fprintf('\nPREDICCIONES:\n');
fprintf('  Total: %d predicciones (cada %d segundo)\n', length(pred_ded), paso_prediccion);
fprintf('  Duración: %.1f segundos\n\n', tiempo(end));

fprintf('DEDOS (Abre/Cierra):\n');
n_ded0 = sum(pred_ded == 0);
n_ded1 = sum(pred_ded == 1);
fprintf('  - Abiertos (0): %d (%.1f%%)\n', n_ded0, n_ded0/length(pred_ded)*100);
fprintf('  - Cerrados (1): %d (%.1f%%)\n', n_ded1, n_ded1/length(pred_ded)*100);
fprintf('  - Confianza promedio: %.3f\n\n', mean(conf_ded));

fprintf('MUÑECA (Pronación/Supinación):\n');
n_mun0 = sum(pred_mun == 0);
n_mun1 = sum(pred_mun == 1);
fprintf('  - Posición neutra (0): %d (%.1f%%)\n', n_mun0, n_mun0/length(pred_mun)*100);
fprintf('  - Pronación (1): %d (%.1f%%)\n', n_mun1, n_mun1/length(pred_mun)*100);
fprintf('  - Confianza promedio: %.3f\n\n', mean(conf_mun));

if validar_con_labels
    fprintf('VALIDACIÓN (vs labels reales):\n');
    fprintf('  DEDOS:  Accuracy %.1f%%\n', acc_ded*100);
    fprintf('  MUÑECA: Accuracy %.1f%%\n\n', acc_mun*100);
end

%% GUARDAR RESULTADOS
fprintf('════════════════════════════════════════════════════════════\n');
fprintf('GUARDANDO RESULTADOS...\n');

timestamp_guardado = datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss');
archivo_salida = sprintf('demo_resultados_%s.mat', timestamp_guardado);

save(archivo_salida, 'pred_ded', 'conf_ded', 'pred_mun', 'conf_mun', 'tiempo', ...
    'cm_ded', 'cm_mun', 'acc_ded', 'acc_mun', 'EEG_filt', 'ruta_datos', 'archivo_set');

fprintf('✓ Resultados guardados en: %s\n\n', archivo_salida);

fprintf('════════════════════════════════════════════════════════════\n');
fprintf('✓ DEMO COMPLETADA EXITOSAMENTE\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

fprintf('PRÓXIMOS PASOS:\n');
fprintf('  1. Para cambiar de archivo:\n');
fprintf('     - Edita las líneas 33-37 de DEMO_FLEXIBLE.m\n');
fprintf('     - Cambiar ruta_datos y archivo_cdt\n');
fprintf('     - Ejecuta >> DEMO_FLEXIBLE nuevamente\n\n');

fprintf('  2. Para enviar a ESP32:\n');
fprintf('     >> ENVIAR_A_ESP32(''%s'', ''%s'');\n\n', archivo_set_completo, modelo_mat);

fprintf('════════════════════════════════════════════════════════════\n\n');
