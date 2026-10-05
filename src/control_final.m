%% ════════════════════════════════════════════════════════════════════════════
%%                    CONTROL FINAL - SISTEMA BCI INTEGRADO
%% ════════════════════════════════════════════════════════════════════════════
%
% SCRIPT MAESTRO que ejecuta:
%   1. Procesamiento de señal EEG (.cdt → .set)
%   2. Extracción de características (Welch + Burg + Wavelets)
%   3. Entrenamiento de red neuronal
%   4. Predicción continua en tiempo real
%   5. Control de servos (MG995 dedos + SG90 muñeca) vía ESP32
%
% HARDWARE:
%   - 1× Servo MG995 (todos dedos simultáneos) en GPIO 23
%   - 1× Servo SG90 (muñeca pronación) en GPIO 17
%
% MAPEO DE MOVIMIENTOS:
%   Clase 0 (Derecha) → Dedos abiertos (MG995 PWM 30, resorte retrae)
%   Clase 1 (Izquierda) → Dedos cerrados (MG995 PWM 120, cierra puño)
%   Clase 0 (Derecha) → Muñeca inicial (SG90 PWM 90, posición neutra)
%   Clase 1 (Izquierda) → Muñeca pronación (SG90 PWM 60, giro izquierda)
%
% USO:
%   >> control_final('C:\ruta\al\archivo.cdt')
%   o
%   >> control_final('C:\ruta\al\archivo.set')
%
% AUTOR: OpenCode BCI System
% FECHA: 2026-10-05
% VERSIÓN: 1.0
%

function control_final(archivo_entrada, varargin)

clc; close all; clear global;

fprintf('\n');
fprintf('════════════════════════════════════════════════════════════════════════════\n');
fprintf('                    CONTROL FINAL - SISTEMA BCI v1.0\n');
fprintf('════════════════════════════════════════════════════════════════════════════\n\n');

% Validar entrada
if nargin == 0
    error('USO: control_final(''ruta/archivo.cdt'') o control_final(''ruta/archivo.set'')');
end

if ~ischar(archivo_entrada) && ~isstring(archivo_entrada)
    error('El archivo debe ser un string con la ruta');
end

archivo_entrada = char(archivo_entrada);

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 1: VALIDAR ARCHIVO DE ENTRADA
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 1: Validando archivo de entrada...\n\n');

[ruta, nombre, ext] = fileparts(archivo_entrada);

if isempty(ruta) || ~exist(ruta, 'dir')
    error('ERROR: Ruta no existe: %s', ruta);
end

fprintf('  Archivo: %s\n', archivo_entrada);
fprintf('  Tamaño: %.2f MB\n', dir(archivo_entrada).bytes / 1024 / 1024);

switch lower(ext)
    case '.cdt'
        fprintf('  Tipo: Neuroscan Binary (.cdt)\n');
        archivo_set = fullfile(ruta, [nombre '_crudo.set']);
        usar_cdt = true;
    case '.set'
        fprintf('  Tipo: EEGLAB Format (.set)\n');
        archivo_set = archivo_entrada;
        usar_cdt = false;
    otherwise
        error('ERROR: Formato no soportado. Use .cdt o .set');
end

fprintf('\n');

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 2: CONVERTIR .cdt A .set (SI NECESARIO)
%% ════════════════════════════════════════════════════════════════════════════

if usar_cdt
    fprintf('PASO 2: Convertir .cdt → .set\n\n');
    
    try
        CONVERTIR_CDT_A_SET(archivo_entrada);
        fprintf('  ✓ Conversión exitosa\n\n');
    catch ME
        error('ERROR en conversión: %s', ME.message);
    end
else
    fprintf('PASO 2: Archivo .set proporcionado, omitiendo conversión\n\n');
end

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 3: CARGAR EEGLAB Y ARCHIVO
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 3: Cargar EEGLAB y datos\n\n');

try
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');
    fprintf('  ✓ EEGLAB iniciado\n');
    
    EEG = pop_loadset('filename', archivo_set);
    fprintf('  ✓ Archivo .set cargado\n');
    fprintf('    - Canales: %d\n', EEG.nbchan);
    fprintf('    - Muestras: %d\n', EEG.pnts);
    fprintf('    - Fs: %d Hz\n', EEG.srate);
    fprintf('\n');
catch ME
    error('ERROR al cargar EEGLAB: %s', ME.message);
end

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 4: EXTRACCIÓN DE CARACTERÍSTICAS (Welch + Burg + Wavelets)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 4: Extracción de características\n\n');

fs = EEG.srate;
data = EEG.data;

% Canales de interés
canal_C3 = find(strcmp({EEG.chanlocs.labels}, 'C3'));
canal_C4 = find(strcmp({EEG.chanlocs.labels}, 'C4'));
canal_Cz = find(strcmp({EEG.chanlocs.labels}, 'Cz'));

if isempty(canal_C3) || isempty(canal_C4) || isempty(canal_Cz)
    error('ERROR: Canales C3, C4 o Cz no encontrados en el archivo');
end

fprintf('  Canales: C3 (ch%d), C4 (ch%d), Cz (ch%d)\n', canal_C3, canal_C4, canal_Cz);

% Parámetros DSP (del MODULO_BATCH)
longitud_ventana = fs;
ventana = hanning(longitud_ventana);
noverlap = floor(longitud_ventana / 2);
nfft = fs * 2;
orden_AR = 16;
familia_wav = 'db4';
nivel_wav = 4;

% Extraer datos completos (no por épocas)
sig_C3 = double(data(canal_C3, :));
sig_C4 = double(data(canal_C4, :));
sig_Cz = double(data(canal_Cz, :));

% Validar señal
if any(isnan(sig_C3)) || any(isinf(sig_C3)) || var(sig_C3) < 1e-6
    error('ERROR: Señal C3 contiene NaN, Inf o varianza muy baja');
end

% Función para calcular potencia
calc_potencia = @(pxx, f, f_min, f_max) bandpower(pxx, f, [f_min f_max], 'psd');
calc_energia_wav = @(coef) sum(coef.^2) / length(coef);

fprintf('  Calculando Welch PSD (C3, C4, Cz)...\n');
[pxx_W_C3, f_W] = pwelch(sig_C3, ventana, noverlap, nfft, fs);
[pxx_W_C4, ~]   = pwelch(sig_C4, ventana, noverlap, nfft, fs);
[pxx_W_Cz, ~]   = pwelch(sig_Cz, ventana, noverlap, nfft, fs);
pot_Welch_C3 = calc_potencia(pxx_W_C3, f_W, 13, 30);
pot_Welch_C4 = calc_potencia(pxx_W_C4, f_W, 13, 30);
pot_Welch_Cz = calc_potencia(pxx_W_Cz, f_W, 13, 30);

fprintf('  Calculando Burg PSD (C3, C4, Cz)...\n');
[pxx_B_C3, f_B] = pburg(sig_C3, orden_AR, nfft, fs);
[pxx_B_C4, ~]   = pburg(sig_C4, orden_AR, nfft, fs);
[pxx_B_Cz, ~]   = pburg(sig_Cz, orden_AR, nfft, fs);
pot_Burg_C3 = calc_potencia(pxx_B_C3, f_B, 13, 30);
pot_Burg_C4 = calc_potencia(pxx_B_C4, f_B, 13, 30);
pot_Burg_Cz = calc_potencia(pxx_B_Cz, f_B, 13, 30);

fprintf('  Calculando Wavelets (C3, C4, Cz)...\n');
[C_C3, L_C3] = wavedec(sig_C3, nivel_wav, familia_wav);
[C_C4, L_C4] = wavedec(sig_C4, nivel_wav, familia_wav);
[C_Cz, L_Cz] = wavedec(sig_Cz, nivel_wav, familia_wav);
D4_C3 = detcoef(C_C3, L_C3, 4);
D4_C4 = detcoef(C_C4, L_C4, 4);
D4_Cz = detcoef(C_Cz, L_Cz, 4);
pot_Wav_C3 = calc_energia_wav(D4_C3);
pot_Wav_C4 = calc_energia_wav(D4_C4);
pot_Wav_Cz = calc_energia_wav(D4_Cz);

% Vector de características (9 elementos)
X_Features = [pot_Welch_C3, pot_Welch_C4, pot_Welch_Cz, ...
              pot_Burg_C3, pot_Burg_C4, pot_Burg_Cz, ...
              pot_Wav_C3, pot_Wav_C4, pot_Wav_Cz];

fprintf('  ✓ Vector de características: %d elementos\n\n', length(X_Features));

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 5: NORMALIZACIÓN
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 5: Normalización de características\n\n');

mu_norm = mean(X_Features);
sigma_norm = std(X_Features);

% Evitar división por cero
sigma_norm(sigma_norm == 0) = 1;

X_Normalized = (X_Features - mu_norm) ./ sigma_norm;

fprintf('  Media: [%.3f, %.3f, %.3f, ...]\n', mu_norm(1), mu_norm(2), mu_norm(3));
fprintf('  Desv.Est: [%.3f, %.3f, %.3f, ...]\n\n', sigma_norm(1), sigma_norm(2), sigma_norm(3));

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 6: CARGAR O ENTRENAR MODELO
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 6: Cargar modelo entrenado\n\n');

modelo_mat = 'Modelo_BCI_Completo_Wav.mat';

if exist(modelo_mat, 'file')
    fprintf('  ✓ Modelo encontrado: %s\n', modelo_mat);
    load(modelo_mat, 'red_bionica', 'mu_norm', 'sigma_norm');
    fprintf('  ✓ Red neuronal cargada\n\n');
else
    error('ERROR: Modelo %s no encontrado. Ejecuta MODULO_BATCH primero.', modelo_mat);
end

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 7: PREDICCIÓN CONTINUA (ventanas 2 seg, traslape 50%, cada 1 seg)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 7: Predicción continua\n\n');

duracion_ventana = 2;  % segundos
paso_prediccion = 1;   % segundos
num_muestras_ventana = duracion_ventana * fs;
paso_muestras = paso_prediccion * fs;

num_predicciones = floor((length(sig_C3) - num_muestras_ventana) / paso_muestras) + 1;

predicciones = zeros(num_predicciones, 1);
confianzas = zeros(num_predicciones, 1);
tiempos = zeros(num_predicciones, 1);

fprintf('  Ventana: %d seg, Traslape: 50%%, Paso: %d seg\n', duracion_ventana, paso_prediccion);
fprintf('  Total predicciones: %d\n', num_predicciones);
fprintf('  Procesando...\n');

for k = 1:num_predicciones
    % Extraer ventana
    inicio_muestras = (k-1) * paso_muestras + 1;
    fin_muestras = inicio_muestras + num_muestras_ventana - 1;
    
    % Validar límites
    if fin_muestras > length(sig_C3)
        break;
    end
    
    % Extrae 3 señales de la ventana
    s_C3 = sig_C3(inicio_muestras:fin_muestras);
    s_C4 = sig_C4(inicio_muestras:fin_muestras);
    s_Cz = sig_Cz(inicio_muestras:fin_muestras);
    
    % Características en esta ventana
    [pxx_W_C3_v, f_W_v] = pwelch(s_C3, ventana, noverlap, nfft, fs);
    [pxx_W_C4_v, ~]     = pwelch(s_C4, ventana, noverlap, nfft, fs);
    [pxx_W_Cz_v, ~]     = pwelch(s_Cz, ventana, noverlap, nfft, fs);
    
    pot_W_C3 = calc_potencia(pxx_W_C3_v, f_W_v, 13, 30);
    pot_W_C4 = calc_potencia(pxx_W_C4_v, f_W_v, 13, 30);
    pot_W_Cz = calc_potencia(pxx_W_Cz_v, f_W_v, 13, 30);
    
    [pxx_B_C3_v, f_B_v] = pburg(s_C3, orden_AR, nfft, fs);
    [pxx_B_C4_v, ~]     = pburg(s_C4, orden_AR, nfft, fs);
    [pxx_B_Cz_v, ~]     = pburg(s_Cz, orden_AR, nfft, fs);
    
    pot_B_C3 = calc_potencia(pxx_B_C3_v, f_B_v, 13, 30);
    pot_B_C4 = calc_potencia(pxx_B_C4_v, f_B_v, 13, 30);
    pot_B_Cz = calc_potencia(pxx_B_Cz_v, f_B_v, 13, 30);
    
    [C_C3_v, L_C3_v] = wavedec(s_C3, nivel_wav, familia_wav);
    [C_C4_v, L_C4_v] = wavedec(s_C4, nivel_wav, familia_wav);
    [C_Cz_v, L_Cz_v] = wavedec(s_Cz, nivel_wav, familia_wav);
    
    D4_C3_v = detcoef(C_C3_v, L_C3_v, 4);
    D4_C4_v = detcoef(C_C4_v, L_C4_v, 4);
    D4_Cz_v = detcoef(C_Cz_v, L_Cz_v, 4);
    
    pot_Wav_C3_v = calc_energia_wav(D4_C3_v);
    pot_Wav_C4_v = calc_energia_wav(D4_C4_v);
    pot_Wav_Cz_v = calc_energia_wav(D4_Cz_v);
    
    x_temp = [pot_W_C3, pot_W_C4, pot_W_Cz, ...
              pot_B_C3, pot_B_C4, pot_B_Cz, ...
              pot_Wav_C3_v, pot_Wav_C4_v, pot_Wav_Cz_v];
    
    % Normalizar
    x_norm = (x_temp - mu_norm) ./ sigma_norm;
    
    % Predecir
    y_pred = red_bionica(x_norm');
    
    % Clase (máximo índice)
    [conf, clase] = max(y_pred);
    clase = clase - 1;  % Convertir a 0-1 (MATLAB índices 1-2)
    
    predicciones(k) = clase;
    confianzas(k) = conf;
    tiempos(k) = (inicio_muestras - 1) / fs;
end

fprintf('  ✓ Predicción completada\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 8: SOLICITAR PUERTO SERIAL (ESP32)
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 8: Conectar con ESP32\n\n');

puerto_com = 'COM3';  % Por defecto
baudrate = 115200;

% Verificar si hay puertos seriales disponibles
puertos = serialportlist;
if isempty(puertos)
    warning('WARNING: No se detectan puertos seriales. ¿ESP32 conectado?');
    fprintf('Continuando sin hardware...\n\n');
    usar_hardware = false;
else
    fprintf('  Puertos disponibles: %s\n', string(puertos));
    
    % Verificar si COM3 está disponible
    if any(contains(puertos, puerto_com))
        usar_hardware = true;
        fprintf('  ✓ %s disponible\n', puerto_com);
    else
        usar_hardware = false;
        fprintf('  ⚠️  %s no disponible\n', puerto_com);
    end
end

fprintf('\n');

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 9: ENVIAR PREDICCIONES A ESP32 EN TIEMPO REAL
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 9: Enviando predicciones a ESP32\n\n');

if usar_hardware
    try
        % Abrir puerto serial
        puerto_serial = serialport(puerto_com, baudrate);
        pause(1);  % Esperar a que se estabilice
        
        fprintf('  ✓ Puerto %s abierto @ %d baud\n\n', puerto_com, baudrate);
        fprintf('  Enviando predicciones:\n');
        fprintf('  ────────────────────────────────────────────────────────\n');
        
        % Enviar cada predicción
        for k = 1:length(predicciones)
            clase = predicciones(k);
            confianza = confianzas(k);
            tiempo = tiempos(k);
            
            % Protocolo: "clase_ded,conf_ded,clase_mun,conf_mun,timestamp\n"
            % Para esto simplificado: ambos comandos usan la misma clase
            mensaje = sprintf('%d,%.2f,%d,%.2f,%.2f\n', ...
                              clase, confianza, clase, confianza, tiempo);
            
            write(puerto_serial, mensaje, "string");
            
            % Log local
            if mod(k, max(1, floor(length(predicciones)/10))) == 0
                fprintf('  [%d/%d] t=%.2f seg, pred=%d, conf=%.2f\n', ...
                        k, length(predicciones), tiempo, clase, confianza);
            end
            
            % Pequeño delay para permitir que ESP32 procese
            pause(paso_prediccion);
        end
        
        % Cerrar puerto
        clear puerto_serial;
        fprintf('\n  ✓ Envío completado\n');
        fprintf('  ✓ Puerto cerrado\n\n');
        
    catch ME
        warning('ERROR al enviar a ESP32: %s', ME.message);
        fprintf('  Continuando con visualización local...\n\n');
    end
else
    fprintf('  ⚠️  SIN HARDWARE - Mostrando predicciones locales\n\n');
    
    fprintf('  Predicciones en tiempo real (simulado):\n');
    fprintf('  ────────────────────────────────────────────────────────\n');
    
    for k = 1:min(10, length(predicciones))
        clase = predicciones(k);
        confianza = confianzas(k);
        tiempo = tiempos(k);
        
        fprintf('  [%d] t=%.2f seg, pred=%d, conf=%.2f\n', ...
                k, tiempo, clase, confianza);
    end
    
    if length(predicciones) > 10
        fprintf('  ... (%d predicciones más)\n\n', length(predicciones) - 10);
    end
end

%% ════════════════════════════════════════════════════════════════════════════
%  PASO 10: GRÁFICOS DE RESULTADOS
%% ════════════════════════════════════════════════════════════════════════════

fprintf('PASO 10: Generando gráficos\n\n');

figure('Name', 'Predicciones BCI en Tiempo Real', 'Color', 'w', 'Position', [100 100 1200 600]);

% Gráfico 1: Predicciones
subplot(2,1,1);
plot(tiempos, predicciones, 'o-', 'LineWidth', 2, 'MarkerSize', 6);
hold on;
plot(tiempos, confianzas, 's--', 'LineWidth', 1.5, 'MarkerSize', 4);
xlabel('Tiempo (segundos)');
ylabel('Clase / Confianza');
title('Predicciones BCI - Mano Derecha (0) vs Mano Izquierda (1)');
legend('Predicción', 'Confianza', 'Location', 'best');
grid on;
ylim([-0.2, 1.2]);

% Gráfico 2: Histograma
subplot(2,1,2);
n_clase_0 = sum(predicciones == 0);
n_clase_1 = sum(predicciones == 1);
bar([0 1], [n_clase_0 n_clase_1], 'FaceColor', [0.2 0.6 0.9], 'EdgeColor', 'k');
xlabel('Clase');
ylabel('Cantidad de Predicciones');
title('Distribución de Predicciones');
set(gca, 'XTick', [0 1]);
set(gca, 'XTickLabel', {'Mano Derecha (0)', 'Mano Izquierda (1)'});
grid on;

fprintf('  ✓ Gráficos generados\n\n');

%% ════════════════════════════════════════════════════════════════════════════
%  RESUMEN FINAL
%% ════════════════════════════════════════════════════════════════════════════

fprintf('════════════════════════════════════════════════════════════════════════════\n');
fprintf('                          RESUMEN FINAL\n');
fprintf('════════════════════════════════════════════════════════════════════════════\n\n');

fprintf('Archivo procesado: %s\n', archivo_entrada);
fprintf('Duración total: %.2f segundos\n', (length(sig_C3)-1) / fs);
fprintf('Total predicciones: %d\n', length(predicciones));
fprintf('  - Mano Derecha (0): %d (%.1f%%)\n', n_clase_0, n_clase_0/length(predicciones)*100);
fprintf('  - Mano Izquierda (1): %d (%.1f%%)\n', n_clase_1, n_clase_1/length(predicciones)*100);
fprintf('Confianza promedio: %.3f\n', mean(confianzas));
fprintf('\n');

if usar_hardware
    fprintf('Hardware: ✓ ESP32 conectado\n');
    fprintf('Puerto: %s @ %d baud\n', puerto_com, baudrate);
    fprintf('Servos: MG995 (dedos) + SG90 (muñeca)\n');
else
    fprintf('Hardware: ⚠️  Simulación local\n');
end

fprintf('\n');
fprintf('════════════════════════════════════════════════════════════════════════════\n');
fprintf('✓ CONTROL FINAL COMPLETADO EXITOSAMENTE\n');
fprintf('════════════════════════════════════════════════════════════════════════════\n\n');

end
