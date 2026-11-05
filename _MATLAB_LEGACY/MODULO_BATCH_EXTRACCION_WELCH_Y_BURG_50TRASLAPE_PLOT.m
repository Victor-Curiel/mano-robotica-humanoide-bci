 %% =========================================================
%  SCRIPT MAESTRO BCI: WELCH + BURG + WAVELETS (ONDA BETA) + MLP
% =========================================================
clear; clc; close all;
fprintf('--- INICIANDO EXTRACCIÓN Y LIMPIEZA AUTOMÁTICA ---\n');

% --- 1. CONFIGURACIÓN DE RUTAS Y CANALES ---
carpeta_der = 'C:\Users\vhca1\Desktop\Acquisition\Ordenadas\lado derecho'; 
carpeta_izq = 'C:\Users\vhca1\Desktop\Acquisition\Ordenadas\lado izquierdo';

% CANALES ANALIZADOS
canal_C3 = 10;
canal_C4 = 12;
canal_Cz = 11;

% FRECUENCIA DE MUESTREO Y PARÁMETROS DSP
fs = 500; 
longitud_ventana = fs; 
ventana = hanning(longitud_ventana); 
noverlap = floor(longitud_ventana / 2); 
nfft = fs * 2; 

% Parámetro para el Método de Burg
orden_AR = 16; 

% Parámetros para Wavelet
familia_wav = 'db4'; % Daubechies 4 (Excelente para EEG)
nivel_wav = 4;       % D4 corresponde a ~15.6 - 31.25 Hz (Banda Beta)

[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');

% FUNCIONES MATEMÁTICAS
calc_potencia = @(pxx, f, f_min, f_max) bandpower(pxx, f, [f_min f_max], 'psd');
% Función para energía de coeficientes Wavelet
calc_energia_wav = @(coef) sum(coef.^2) / length(coef); 

X_Der = []; 
X_Izq = []; 

% --- 2. EXTRACCIÓN CARPETA DERECHA ---
archivos_der = dir(fullfile(carpeta_der, '*.set'));
for a = 1:length(archivos_der)
    EEG_tmp = pop_loadset('filename', archivos_der(a).name, 'filepath', carpeta_der);
    data = EEG_tmp.data;
    if ndims(data) < 3; data = reshape(data, size(data,1), size(data,2), 1); end
    
    for i = 1:size(data, 3)
        sig_C3 = double(data(canal_C3, :, i));
        sig_C4 = double(data(canal_C4, :, i));
        sig_Cz = double(data(canal_Cz, :, i));
        
        % ESCUDO ANTI-CRASH
        if any(isnan(sig_C3)) || any(isinf(sig_C3)) || var(sig_C3) < 1e-6 || ...
           any(isnan(sig_C4)) || any(isinf(sig_C4)) || var(sig_C4) < 1e-6 || ...
           any(isnan(sig_Cz)) || any(isinf(sig_Cz)) || var(sig_Cz) < 1e-6
            continue; 
        end
        
        % 1. Welch PSD
        [pxx_W_C3, f_W] = pwelch(sig_C3, ventana, noverlap, nfft, fs);
        [pxx_W_C4, ~]   = pwelch(sig_C4, ventana, noverlap, nfft, fs);
        [pxx_W_Cz, ~]   = pwelch(sig_Cz, ventana, noverlap, nfft, fs);
        pot_Welch_C3 = calc_potencia(pxx_W_C3, f_W, 13, 30);
        pot_Welch_C4 = calc_potencia(pxx_W_C4, f_W, 13, 30);
        pot_Welch_Cz = calc_potencia(pxx_W_Cz, f_W, 13, 30);
        
        % 2. Burg PSD
        [pxx_B_C3, f_B] = pburg(sig_C3, orden_AR, nfft, fs);
        [pxx_B_C4, ~]   = pburg(sig_C4, orden_AR, nfft, fs);
        [pxx_B_Cz, ~]   = pburg(sig_Cz, orden_AR, nfft, fs);
        pot_Burg_C3 = calc_potencia(pxx_B_C3, f_B, 13, 30);
        pot_Burg_C4 = calc_potencia(pxx_B_C4, f_B, 13, 30);
        pot_Burg_Cz = calc_potencia(pxx_B_Cz, f_B, 13, 30);

        % 3. WAVELETS (Transformada Discreta)
        [C_C3, L_C3] = wavedec(sig_C3, nivel_wav, familia_wav);
        [C_C4, L_C4] = wavedec(sig_C4, nivel_wav, familia_wav);
        [C_Cz, L_Cz] = wavedec(sig_Cz, nivel_wav, familia_wav);
        
        % Extraer los coeficientes de Detalle Nivel 4 (D4)
        D4_C3 = detcoef(C_C3, L_C3, 4);
        D4_C4 = detcoef(C_C4, L_C4, 4);
        D4_Cz = detcoef(C_Cz, L_Cz, 4);
        
        % Calcular la energía de la banda Beta capturada por D4
        pot_Wav_C3 = calc_energia_wav(D4_C3);
        pot_Wav_C4 = calc_energia_wav(D4_C4);
        pot_Wav_Cz = calc_energia_wav(D4_Cz);
        
        % Vector ahora es de 9 dimensiones
        x_temp = [pot_Welch_C3, pot_Welch_C4, pot_Welch_Cz, ...
                  pot_Burg_C3, pot_Burg_C4, pot_Burg_Cz, ...
                  pot_Wav_C3, pot_Wav_C4, pot_Wav_Cz];
        X_Der = [X_Der; x_temp];
    end
end

% --- 3. EXTRACCIÓN CARPETA IZQUIERDA ---
archivos_izq = dir(fullfile(carpeta_izq, '*.set'));
for a = 1:length(archivos_izq)
    EEG_tmp = pop_loadset('filename', archivos_izq(a).name, 'filepath', carpeta_izq);
    data = EEG_tmp.data;
    if ndims(data) < 3; data = reshape(data, size(data,1), size(data,2), 1); end
    
    for i = 1:size(data, 3)
        sig_C3 = double(data(canal_C3, :, i));
        sig_C4 = double(data(canal_C4, :, i));
        sig_Cz = double(data(canal_Cz, :, i));
        
        if any(isnan(sig_C3)) || any(isinf(sig_C3)) || var(sig_C3) < 1e-6 || ...
           any(isnan(sig_C4)) || any(isinf(sig_C4)) || var(sig_C4) < 1e-6 || ...
           any(isnan(sig_Cz)) || any(isinf(sig_Cz)) || var(sig_Cz) < 1e-6
            continue; 
        end
        
        % 1. Welch
        [pxx_W_C3, f_W] = pwelch(sig_C3, ventana, noverlap, nfft, fs);
        [pxx_W_C4, ~]   = pwelch(sig_C4, ventana, noverlap, nfft, fs);
        [pxx_W_Cz, ~]   = pwelch(sig_Cz, ventana, noverlap, nfft, fs);
        pot_Welch_C3 = calc_potencia(pxx_W_C3, f_W, 13, 30);
        pot_Welch_C4 = calc_potencia(pxx_W_C4, f_W, 13, 30);
        pot_Welch_Cz = calc_potencia(pxx_W_Cz, f_W, 13, 30);
        
        % 2. Burg
        [pxx_B_C3, f_B] = pburg(sig_C3, orden_AR, nfft, fs);
        [pxx_B_C4, ~]   = pburg(sig_C4, orden_AR, nfft, fs);
        [pxx_B_Cz, ~]   = pburg(sig_Cz, orden_AR, nfft, fs);
        pot_Burg_C3 = calc_potencia(pxx_B_C3, f_B, 13, 30);
        pot_Burg_C4 = calc_potencia(pxx_B_C4, f_B, 13, 30);
        pot_Burg_Cz = calc_potencia(pxx_B_Cz, f_B, 13, 30);

        % 3. WAVELETS
        [C_C3, L_C3] = wavedec(sig_C3, nivel_wav, familia_wav);
        [C_C4, L_C4] = wavedec(sig_C4, nivel_wav, familia_wav);
        [C_Cz, L_Cz] = wavedec(sig_Cz, nivel_wav, familia_wav);
        
        D4_C3 = detcoef(C_C3, L_C3, 4);
        D4_C4 = detcoef(C_C4, L_C4, 4);
        D4_Cz = detcoef(C_Cz, L_Cz, 4);
        
        pot_Wav_C3 = calc_energia_wav(D4_C3);
        pot_Wav_C4 = calc_energia_wav(D4_C4);
        pot_Wav_Cz = calc_energia_wav(D4_Cz);
        
        x_temp = [pot_Welch_C3, pot_Welch_C4, pot_Welch_Cz, ...
                  pot_Burg_C3, pot_Burg_C4, pot_Burg_Cz, ...
                  pot_Wav_C3, pot_Wav_C4, pot_Wav_Cz];
        X_Izq = [X_Izq; x_temp];
    end
end

% --- 4. CONSOLIDACIÓN INICIAL ---
X_Features = [X_Der; X_Izq];
Y_Labels = [ones(size(X_Der, 1), 1); zeros(size(X_Izq, 1), 1)];

% --- 5. DETECCIÓN Y ELIMINACIÓN DE ARTEFACTOS ---
fprintf('\nAplicando filtro estadístico IQR para eliminar artefactos...\n');
indices_ruidosos = any(isoutlier(X_Features, 'quartiles'), 2);
num_eliminados = sum(indices_ruidosos);

% Dataset limpio (Ahora de 9 columnas)
X_Clean = X_Features(~indices_ruidosos, :);
Y_Clean = Y_Labels(~indices_ruidosos);
fprintf('¡Se detectaron y eliminaron %d épocas contaminadas!\n', num_eliminados);
fprintf('Total de épocas útiles para la Red Neuronal: %d\n', length(Y_Clean));

% --- 6. PLOT CON DATOS LIMPIOS  ---
X_Der_Clean = X_Clean(Y_Clean == 1, :);
X_Izq_Clean = X_Clean(Y_Clean == 0, :);

figure('Name', 'Comparativa Welch vs Wavelets (Banda Beta)', 'Color', 'w', 'Position', [100 100 1000 400]);
subplot(1,2,1); hold on; grid on;
scatter(X_Der_Clean(:,1), X_Der_Clean(:,2), 60, 'r', 'filled', 'MarkerFaceAlpha', 0.8);
scatter(X_Izq_Clean(:,1), X_Izq_Clean(:,2), 60, 'b', 'filled', 'MarkerFaceAlpha', 0.8);
xlabel('Potencia Welch \beta en C3'); ylabel('Potencia Welch \beta en C4');
title('Separabilidad Espacial - Welch'); legend('Mano Derecha', 'Mano Izquierda');

subplot(1,2,2); hold on; grid on;
% Columnas 7 y 8 son Wavelet C3 y C4 respectivamente
scatter(X_Der_Clean(:,7), X_Der_Clean(:,8), 60, 'r', 'filled', 'MarkerFaceAlpha', 0.8);
scatter(X_Izq_Clean(:,7), X_Izq_Clean(:,8), 60, 'b', 'filled', 'MarkerFaceAlpha', 0.8);
xlabel('Energía Wavelet D4 en C3'); ylabel('Energía Wavelet D4 en C4');
title('Separabilidad Espacial - Wavelets (Nivel 4)'); legend('Mano Derecha', 'Mano Izquierda');

% =========================================================
% --- 7. ENTRENAMIENTO DEL PERCEPTRÓN MULTICAPA (COMPLETO) ---
% =========================================================
fprintf('\n--- PREPARANDO DATOS PARA LA RED NEURONAL ---\n');

% 2. NORMALIZACIÓN (Z-Score)
fprintf('Normalizando las 9 características (Z-Score) para igualar pesos...\n');
X_Norm = zscore(X_Clean);

% 3. PREPARACIÓN PARA LA RED NEURONAL
X_NN = X_Norm'; 
Y_OneHot = zeros(2, length(Y_Clean));
Y_OneHot(1, Y_Clean == 1) = 1; 
Y_OneHot(2, Y_Clean == 0) = 1; 

neuronas_ocultas = 10;
red_bionica = patternnet(neuronas_ocultas);
red_bionica.divideParam.trainRatio = 0.70;
red_bionica.divideParam.valRatio   = 0.15;
red_bionica.divideParam.testRatio  = 0.15;

% 4. ENTRENAR Y EVALUAR
fprintf('Entrenando... (Observa la ventana de Neural Network Training)\n');
[red_bionica, registro] = train(red_bionica, X_NN, Y_OneHot);
predicciones = red_bionica(X_NN);

% Matriz de Confusión 
figure('Name', 'Rendimiento BCI - Dataset Completo', 'Color', 'w');
plotconfusion(Y_OneHot, predicciones);
title('Matriz de Confusión (9 Características: Welch + Burg + Wavelets)');

% Calcular y guardar estadísticas de normalización para predicción
mu_norm = mean(X_Clean, 1);
sigma_norm = std(X_Clean, 1);

save('Modelo_BCI_Completo_Wav.mat', ...
    'X_Norm', 'Y_Clean', 'red_bionica', 'registro', ...
    'mu_norm', 'sigma_norm', ...
    'fs', 'canal_C3', 'canal_C4', 'canal_Cz', ...
    'orden_AR', 'familia_wav', 'nivel_wav', ...
    'longitud_ventana', 'noverlap', 'nfft', 'ventana');

fprintf('\n✓ ¡PROCESO DE ENTRENAMIENTO COMPLETO EXITOSO!\n');
fprintf('  Estadísticas de normalización guardadas para predicción continua\n');