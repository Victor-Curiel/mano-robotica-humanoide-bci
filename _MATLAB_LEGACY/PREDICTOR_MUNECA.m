%% PREDICTOR_MUNECA
% Clasificación continua de movimiento de muñeca (pronación/supinación)
%
% VERSIÓN: 1.0 - OPCIÓN B (Adapta Red 1 para muñeca)
% En versión futura, podría reentrenarse Red 2 independiente
%
% USO:
%   [pred, conf, tiempo] = PREDICTOR_MUNECA(archivo_set, modelo_mat);
%
% ENTRADA:
%   archivo_set: ruta a archivo .set CRUDO (sin filtrar)
%   modelo_mat: ruta a 'Modelo_BCI_Completo_Wav.mat' (red entrenada)
%
% SALIDA:
%   predicciones: [N×1] - Clase predicha (0=posición neutra, 1=pronación izq)
%   confianza:    [N×1] - Confianza predicción (0-1)
%   tiempo:       [N×1] - Timestamps en segundos
%
% REFERENCIA TESIS:
%   Objetivo Específico (main.tex:841-851):
%   "Replicar el movimiento de pronación y supinación de 180°"
%
% MAPEO ACTUAL (v1.0 - Red 1 adaptada):
%   - Predicción Red 1 = 0 → Interpretado como SUPINACIÓN (regresa a posición neutra)
%   - Predicción Red 1 = 1 → Interpretado como PRONACIÓN (gira izquierda)
%
% NOTA TÉCNICA:
%   Esta versión utiliza la misma Red 1 que para dedos, pero interpreta
%   la salida para control de muñeca. En versión v2.0, podría:
%   - Reentrenar Red 2 específica para pronación/supinación
%   - Usar datos de movimiento de muñeca etiquetados
%   - Implementar Red multicapa más profunda
%
% PARÁMETROS TÉCNICOS:
%   - Mismo filtro que Red 1: FIR 13-30 Hz
%   - Mismas características: Welch + Burg + Wavelets (9 features)
%   - Misma arquitectura de red: MLP 9→10→2
%   - Normalización: Z-score con estadísticas de training
%
% EJEMPLO:
%   % Predicción continua de muñeca
%   [pred_mun, conf_mun, t_mun] = PREDICTOR_MUNECA(...
%       'Acquisition_15_crudo.set', ...
%       'Modelo_BCI_Completo_Wav.mat');
%   
%   % Visualizar
%   figure('Name', 'Predicciones Continuas - MUÑECA');
%   subplot(2,1,1); plot(t_mun, pred_mun, 'g.-');
%   xlabel('Tiempo (seg)'); ylabel('Clase (0=neutro, 1=pronación)');
%   title('Predicciones de Muñeca');
%   
%   subplot(2,1,2); plot(t_mun, conf_mun, 'r.-');
%   xlabel('Tiempo (seg)'); ylabel('Confianza');
%   ylim([0 1]);
%
% AUTHOR: OpenCode BCI System
% DATE: 2026-09-30
% VERSION: 1.0
%

function [predicciones, confianza, tiempo] = ...
    PREDICTOR_MUNECA(archivo_set, modelo_mat)

fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('  PREDICTOR DE MOVIMIENTO DE MUÑECA - PRONACIÓN/SUPINACIÓN\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

fprintf('NOTA: v1.0 utiliza Red 1 adaptada\n');
fprintf('      En v2.0 se podría entrenar Red 2 independiente\n\n');

%% CARGAR MODELO
fprintf('1. Cargando modelo entrenado...\n');
load(modelo_mat, 'red_bionica', 'mu_norm', 'sigma_norm', ...
    'fs', 'canal_C3', 'canal_C4', 'canal_Cz', ...
    'orden_AR', 'familia_wav', 'nivel_wav', ...
    'longitud_ventana', 'noverlap', 'nfft', 'ventana');

fprintf('   ✓ Red 1 cargada (adaptada para muñeca)\n\n');

%% CARGAR ARCHIVO .SET CRUDO
fprintf('2. Cargando archivo .set crudo...\n');
try
    [~, ~, CURRENTSET, ALLCOM] = eeglab('nogui');
    EEG_crudo = pop_loadset('filename', archivo_set);
    fprintf('   ✓ Archivo cargado\n\n');
catch ME
    error('No se pudo cargar archivo .set: %s', ME.message);
end

%% APLICAR FILTRO FIR 13-30 Hz
fprintf('3. Aplicando filtro FIR 13-30 Hz...\n');
EEG_filt = pop_eegfilt(EEG_crudo, 13, 30, [], 0);
fprintf('   ✓ Filtro aplicado\n\n');

%% EXTRAER DATOS
fprintf('4. Extrayendo canales...\n');
signal = double(EEG_filt.data([canal_C3, canal_C4, canal_Cz], :));
fprintf('   ✓ Canales extraídos\n\n');

%% CONFIGURAR VENTANAS
duracion_muestras = 2 * fs;  % 2 segundos
paso_muestras = 1 * fs;      % 1 segundo
n_muestras_total = size(signal, 2);

indices_inicio = 1 : paso_muestras : (n_muestras_total - duracion_muestras + 1);
n_ventanas = length(indices_inicio);

fprintf('5. Procesando %d ventanas...\n\n', n_ventanas);

%% EXTRAER CARACTERÍSTICAS
predicciones = zeros(n_ventanas, 1);
confianza = zeros(n_ventanas, 1);
tiempo = zeros(n_ventanas, 1);

calc_potencia = @(pxx, f, f_min, f_max) bandpower(pxx, f, [f_min f_max], 'psd');
calc_energia_wav = @(coef) sum(coef.^2) / length(coef);

for i = 1 : n_ventanas
    idx_inicio = indices_inicio(i);
    idx_fin = idx_inicio + duracion_muestras - 1;
    
    ventana_C3 = signal(1, idx_inicio:idx_fin);
    ventana_C4 = signal(2, idx_inicio:idx_fin);
    ventana_Cz = signal(3, idx_inicio:idx_fin);
    
    % Validación
    if any(isnan([ventana_C3, ventana_C4, ventana_Cz])) || ...
       var(ventana_C3) < 1e-6 || var(ventana_C4) < 1e-6 || var(ventana_Cz) < 1e-6
        predicciones(i) = 0;
        confianza(i) = 0;
        tiempo(i) = idx_inicio / fs;
        continue;
    end
    
    % Welch
    [pxx_W_C3, f_W] = pwelch(ventana_C3, ventana, noverlap, nfft, fs);
    [pxx_W_C4, ~] = pwelch(ventana_C4, ventana, noverlap, nfft, fs);
    [pxx_W_Cz, ~] = pwelch(ventana_Cz, ventana, noverlap, nfft, fs);
    
    pot_Welch_C3 = calc_potencia(pxx_W_C3, f_W, 13, 30);
    pot_Welch_C4 = calc_potencia(pxx_W_C4, f_W, 13, 30);
    pot_Welch_Cz = calc_potencia(pxx_W_Cz, f_W, 13, 30);
    
    % Burg
    [pxx_B_C3, f_B] = pburg(ventana_C3, orden_AR, nfft, fs);
    [pxx_B_C4, ~] = pburg(ventana_C4, orden_AR, nfft, fs);
    [pxx_B_Cz, ~] = pburg(ventana_Cz, orden_AR, nfft, fs);
    
    pot_Burg_C3 = calc_potencia(pxx_B_C3, f_B, 13, 30);
    pot_Burg_C4 = calc_potencia(pxx_B_C4, f_B, 13, 30);
    pot_Burg_Cz = calc_potencia(pxx_B_Cz, f_B, 13, 30);
    
    % Wavelets
    [C_C3, L_C3] = wavedec(ventana_C3, nivel_wav, 'db4');
    [C_C4, L_C4] = wavedec(ventana_C4, nivel_wav, 'db4');
    [C_Cz, L_Cz] = wavedec(ventana_Cz, nivel_wav, 'db4');
    
    D4_C3 = detcoef(C_C3, L_C3, 4);
    D4_C4 = detcoef(C_C4, L_C4, 4);
    D4_Cz = detcoef(C_Cz, L_Cz, 4);
    
    pot_Wav_C3 = calc_energia_wav(D4_C3);
    pot_Wav_C4 = calc_energia_wav(D4_C4);
    pot_Wav_Cz = calc_energia_wav(D4_Cz);
    
    % Concatenar features
    X_ventana = [pot_Welch_C3, pot_Welch_C4, pot_Welch_Cz, ...
                 pot_Burg_C3, pot_Burg_C4, pot_Burg_Cz, ...
                 pot_Wav_C3, pot_Wav_C4, pot_Wav_Cz];
    
    % Normalizar
    X_norm = (X_ventana - mu_norm) ./ sigma_norm;
    
    % Clasificar
    Y_pred = red_bionica(X_norm');
    [conf, idx_clase] = max(Y_pred);
    clase = idx_clase - 1;
    
    predicciones(i) = clase;
    confianza(i) = conf;
    tiempo(i) = idx_inicio / fs;
end

%% ESTADÍSTICAS
fprintf('6. Estadísticas de predicción:\n');
n_clase0 = sum(predicciones == 0);
n_clase1 = sum(predicciones == 1);
fprintf('   - Clase 0 (posición neutra): %d (%.1f%%)\n', n_clase0, n_clase0/n_ventanas*100);
fprintf('   - Clase 1 (pronación izq): %d (%.1f%%)\n', n_clase1, n_clase1/n_ventanas*100);
fprintf('   - Confianza media: %.3f\n\n', mean(confianza));

fprintf('════════════════════════════════════════════════════════════\n');
fprintf('✓ PREDICCIÓN DE MUÑECA COMPLETADA\n\n');

end
