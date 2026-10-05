%% PREDICTOR_DATOS_CRUDOS
% Clasificación continua de intención motora (DEDOS: abre/cierra)
%
% Función principal que realiza predicción continua de movimientos
% de dedos usando ventanas deslizantes y la red neuronal entrenada.
%
% USO:
%   [pred, conf, tiempo] = PREDICTOR_DATOS_CRUDOS(archivo_set, modelo_mat);
%   [pred, conf, tiempo] = PREDICTOR_DATOS_CRUDOS(archivo_set, modelo_mat, 'duracion_ventana', 2, 'paso', 1);
%
% ENTRADA:
%   archivo_set: ruta a archivo .set CRUDO (sin filtrar)
%   modelo_mat: ruta a 'Modelo_BCI_Completo_Wav.mat' (red entrenada)
%
% PARÁMETROS OPCIONALES (nombre-valor):
%   'duracion_ventana': duración ventana en segundos (default: 2)
%   'paso': intervalo entre predicciones en segundos (default: 1)
%   'canales': [C3_idx, C4_idx, Cz_idx] (default: [10, 12, 11])
%
% SALIDA:
%   predicciones: [N×1] double - Clase predicha (0=abre, 1=cierra)
%   confianza:    [N×1] double - Confianza predicción (0-1)
%   tiempo:       [N×1] double - Timestamps en segundos
%   EEG_filt:     struct EEGLAB - Datos filtrados (opcional)
%
% REFERENCIA TESIS:
%   Hipótesis (main.tex:664-669):
%   "El control de mano humanoide mediante EEG con reconocedor de patrones
%    mejorará la exactitud de movimientos respecto a sin clasificador"
%
%   Objetivo General (main.tex:814-816):
%   "Implementar ICO por reconocimiento de patrones para control de 4 tipos
%    de movimientos de mano (apertura, cierre, pronación, supinación)"
%
% CARACTERÍSTICAS UTILIZADAS:
%   - Welch Power Spectral Density (13-30 Hz): 3 features (C3, C4, Cz)
%   - Burg Autoregressive (orden 16, 13-30 Hz): 3 features (C3, C4, Cz)
%   - Wavelet Daubechies-4, nivel 4 (13-30 Hz): 3 features (C3, C4, Cz)
%   Total: 9 features
%
% RED NEURONAL:
%   Arquitectura: MLP 9→10→2 (entrada 9 features, oculta 10, salida 2 clases)
%   Función activación: Tangente sigmoidea + Softmax
%   Algoritmo: Backpropagation + Adam
%
% PARÁMETROS TÉCNICOS:
%   - Frecuencia muestreo: 500 Hz
%   - Filtro: FIR Legacy EEGLAB 13-30 Hz (orden automático)
%   - Ventana Welch: 500 muestras (1 seg), overlap 50%, FFT 1000
%   - Método Burg: orden 16, FFT 1000
%   - Wavelet: Daubechies-4, 4 niveles, coef. D4 → banda Beta
%
% VENTANAS DESLIZANTES:
%   - Duración: 2 segundos (1000 muestras @ 500 Hz)
%   - Overlap: 50% (500 muestras entre ventanas)
%   - Predicción: cada 1 segundo (paso de 500 muestras)
%
% NORMALIZACIÓN:
%   - Método: Z-score
%   - Media (μ): calculada en training con X_Clean
%   - Desv.Est. (σ): calculada en training con X_Clean
%   - Aplicación: X_norm = (X_raw - μ) / σ
%
% EJEMPLO:
%   % Predicción continua en archivo de prueba
%   [pred, conf, t] = PREDICTOR_DATOS_CRUDOS(...
%       'Acquisition_15_crudo.set', ...
%       'Modelo_BCI_Completo_Wav.mat');
%   
%   % Visualizar resultados
%   figure('Name', 'Predicciones Continuas - DEDOS');
%   subplot(2,1,1); plot(t, pred, 'b.-', 'MarkerSize', 6);
%   xlabel('Tiempo (seg)'); ylabel('Clase (0=abre, 1=cierra)');
%   title('Predicciones de Dedos');
%   
%   subplot(2,1,2); plot(t, conf, 'r.-', 'MarkerSize', 6);
%   xlabel('Tiempo (seg)'); ylabel('Confianza');
%   title('Confianza de Predicción');
%   ylim([0 1]);
%
% AUTHOR: OpenCode BCI System
% DATE: 2026-09-30
% VERSION: 1.0
%

function [predicciones, confianza, tiempo, varargout] = ...
    PREDICTOR_DATOS_CRUDOS(archivo_set, modelo_mat, varargin)

%% PARSING DE PARÁMETROS
p = inputParser;
addParameter(p, 'duracion_ventana', 2, @isnumeric);
addParameter(p, 'paso', 1, @isnumeric);
addParameter(p, 'canales', [10, 12, 11], @isvector);
parse(p, varargin{:});

duracion_ventana = p.Results.duracion_ventana;
paso_tiempo = p.Results.paso;
canales = p.Results.canales;

fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('    PREDICTOR DE INTENCIÓN MOTORA - CLASIFICACIÓN CONTINUA\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

%% 1. CARGAR MODELO Y ESTADÍSTICAS
fprintf('1. Cargando modelo entrenado...\n');
load(modelo_mat, 'red_bionica', 'mu_norm', 'sigma_norm', ...
    'fs', 'canal_C3', 'canal_C4', 'canal_Cz', ...
    'orden_AR', 'familia_wav', 'nivel_wav', ...
    'longitud_ventana', 'noverlap', 'nfft', 'ventana');

fprintf('   ✓ Modelo cargado\n');
fprintf('   - Red: MLP 9→10→2\n');
fprintf('   - Fs: %d Hz\n\n', fs);

%% 2. CARGAR ARCHIVO .SET CRUDO
fprintf('2. Cargando archivo .set crudo...\n');
try
    [~, ~, CURRENTSET, ALLCOM] = eeglab('nogui');
    EEG_crudo = pop_loadset('filename', archivo_set);
    fprintf('   ✓ Archivo cargado\n');
    fprintf('   - Canales: %d\n', EEG_crudo.nbchan);
    fprintf('   - Duración: %.2f segundos\n', EEG_crudo.xmax);
    fprintf('   - Fs: %d Hz\n\n', EEG_crudo.srate);
catch ME
    error('No se pudo cargar archivo .set: %s', ME.message);
end

%% 3. APLICAR FILTRO FIR 13-30 Hz
fprintf('3. Aplicando filtro FIR 13-30 Hz (Legacy EEGLAB)...\n');
EEG_filt = pop_eegfilt(EEG_crudo, 13, 30, [], 0);
fprintf('   ✓ Filtro aplicado (FIR, orden automático)\n\n');

%% 4. EXTRAER DATOS DE CANALES C3, C4, CZ
fprintf('4. Extrayendo canales C3, C4, Cz...\n');
% Usar canales especificados o defaults
C3_idx = canales(1);
C4_idx = canales(2);
Cz_idx = canales(3);

signal = double(EEG_filt.data([C3_idx, C4_idx, Cz_idx], :));
fprintf('   ✓ Canales extraídos\n');
fprintf('   - C3 (canal %d), C4 (canal %d), Cz (canal %d)\n', C3_idx, C4_idx, Cz_idx);
fprintf('   - Muestras totales: %d\n\n', size(signal, 2));

%% 5. CONFIGURAR VENTANAS DESLIZANTES
duracion_muestras = duracion_ventana * fs;  % 2 segundos = 1000 muestras
paso_muestras = paso_tiempo * fs;            % 1 segundo = 500 muestras
n_muestras_total = size(signal, 2);

% Calcular índices de inicio de ventanas
indices_inicio = 1 : paso_muestras : (n_muestras_total - duracion_muestras + 1);
n_ventanas = length(indices_inicio);

fprintf('5. Configurando ventanas deslizantes...\n');
fprintf('   - Duración ventana: %d segundos (%d muestras)\n', duracion_ventana, duracion_muestras);
fprintf('   - Paso: %d segundo (%d muestras)\n', paso_tiempo, paso_muestras);
fprintf('   - Total ventanas: %d\n\n', n_ventanas);

%% 6. EXTRAER CARACTERÍSTICAS PARA CADA VENTANA
fprintf('6. Extrayendo características continuas...\n');

predicciones = zeros(n_ventanas, 1);
confianza = zeros(n_ventanas, 1);
tiempo = zeros(n_ventanas, 1);

% Parámetros para extracción (del modelo training)
calc_potencia = @(pxx, f, f_min, f_max) bandpower(pxx, f, [f_min f_max], 'psd');
calc_energia_wav = @(coef) sum(coef.^2) / length(coef);

for i = 1 : n_ventanas
    % Índices de ventana
    idx_inicio = indices_inicio(i);
    idx_fin = idx_inicio + duracion_muestras - 1;
    
    % Extraer ventana para 3 canales
    ventana_C3 = signal(1, idx_inicio:idx_fin);
    ventana_C4 = signal(2, idx_inicio:idx_fin);
    ventana_Cz = signal(3, idx_inicio:idx_fin);
    
    % VALIDACIÓN: Verificar que ventana es válida
    if any(isnan([ventana_C3, ventana_C4, ventana_Cz])) || ...
       var(ventana_C3) < 1e-6 || var(ventana_C4) < 1e-6 || var(ventana_Cz) < 1e-6
        predicciones(i) = 0;
        confianza(i) = 0;
        tiempo(i) = idx_inicio / fs;
        continue;
    end
    
    % === EXTRAER 9 CARACTERÍSTICAS ===
    
    % 1. WELCH PSD (13-30 Hz)
    [pxx_W_C3, f_W] = pwelch(ventana_C3, ventana, noverlap, nfft, fs);
    [pxx_W_C4, ~] = pwelch(ventana_C4, ventana, noverlap, nfft, fs);
    [pxx_W_Cz, ~] = pwelch(ventana_Cz, ventana, noverlap, nfft, fs);
    
    pot_Welch_C3 = calc_potencia(pxx_W_C3, f_W, 13, 30);
    pot_Welch_C4 = calc_potencia(pxx_W_C4, f_W, 13, 30);
    pot_Welch_Cz = calc_potencia(pxx_W_Cz, f_W, 13, 30);
    
    % 2. BURG PSD (13-30 Hz)
    [pxx_B_C3, f_B] = pburg(ventana_C3, orden_AR, nfft, fs);
    [pxx_B_C4, ~] = pburg(ventana_C4, orden_AR, nfft, fs);
    [pxx_B_Cz, ~] = pburg(ventana_Cz, orden_AR, nfft, fs);
    
    pot_Burg_C3 = calc_potencia(pxx_B_C3, f_B, 13, 30);
    pot_Burg_C4 = calc_potencia(pxx_B_C4, f_B, 13, 30);
    pot_Burg_Cz = calc_potencia(pxx_B_Cz, f_B, 13, 30);
    
    % 3. WAVELETS - Daubechies 4, Nivel 4 (13-30 Hz)
    [C_C3, L_C3] = wavedec(ventana_C3, nivel_wav, familia_wav);
    [C_C4, L_C4] = wavedec(ventana_C4, nivel_wav, familia_wav);
    [C_Cz, L_Cz] = wavedec(ventana_Cz, nivel_wav, familia_wav);
    
    D4_C3 = detcoef(C_C3, L_C3, 4);
    D4_C4 = detcoef(C_C4, L_C4, 4);
    D4_Cz = detcoef(C_Cz, L_Cz, 4);
    
    pot_Wav_C3 = calc_energia_wav(D4_C3);
    pot_Wav_C4 = calc_energia_wav(D4_C4);
    pot_Wav_Cz = calc_energia_wav(D4_Cz);
    
    % === CONCATENAR 9 FEATURES ===
    X_ventana = [pot_Welch_C3, pot_Welch_C4, pot_Welch_Cz, ...
                 pot_Burg_C3, pot_Burg_C4, pot_Burg_Cz, ...
                 pot_Wav_C3, pot_Wav_C4, pot_Wav_Cz];
    
    % === NORMALIZAR (Z-SCORE) ===
    X_norm = (X_ventana - mu_norm) ./ sigma_norm;
    
    % === CLASIFICAR CON RED NEURONAL ===
    Y_pred = red_bionica(X_norm');
    
    % === EXTRAER CLASE Y CONFIANZA ===
    [conf, idx_clase] = max(Y_pred);
    clase = idx_clase - 1;  % 0 o 1
    
    predicciones(i) = clase;
    confianza(i) = conf;
    tiempo(i) = idx_inicio / fs;
end

fprintf('   ✓ Características extraídas\n');
fprintf('   - Ventanas procesadas: %d\n\n', n_ventanas);

%% 7. MOSTRAR ESTADÍSTICAS
fprintf('7. Estadísticas de predicción:\n');
n_clase0 = sum(predicciones == 0);
n_clase1 = sum(predicciones == 1);
fprintf('   - Clase 0 (abre): %d (%.1f%%)\n', n_clase0, n_clase0/n_ventanas*100);
fprintf('   - Clase 1 (cierra): %d (%.1f%%)\n', n_clase1, n_clase1/n_ventanas*100);
fprintf('   - Confianza media: %.3f\n', mean(confianza));
fprintf('   - Confianza min/max: %.3f / %.3f\n\n', min(confianza), max(confianza));

fprintf('════════════════════════════════════════════════════════════\n');
fprintf('✓ PREDICCIÓN COMPLETADA\n\n');

%% 8. RETORNAR DATOS FILTRADOS SI SE SOLICITA
if nargout > 3
    varargout{1} = EEG_filt;
end

end
