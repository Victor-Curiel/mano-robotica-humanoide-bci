%% VALIDADOR_CON_LABELS
% Compara predicciones continuas con labels reales de grabación
%
% Calcula matrices de confusión, accuracy, y genera visualizaciones
% para validación del sistema BCI con datos reales etiquetados.
%
% USO:
%   [cm, acc] = VALIDADOR_CON_LABELS(pred_ded, conf_ded, ...
%                                     pred_mun, conf_mun, ...
%                                     tiempo, csv_labels);
%
% ENTRADA:
%   pred_ded: [N×1] - Predicciones DEDOS (0=abre, 1=cierra)
%   conf_ded: [N×1] - Confianza DEDOS (0-1)
%   pred_mun: [N×1] - Predicciones MUÑECA (0=neutro, 1=pronación)
%   conf_mun: [N×1] - Confianza MUÑECA (0-1)
%   tiempo: [N×1] - Timestamps de predicciones (seg)
%   csv_labels: string - Ruta a archivo CSV con labels reales
%
% FORMATO CSV ESPERADO:
%   timestamp_inicio,timestamp_fin,clase
%   0.5,2.5,1
%   3.0,5.0,0
%   ...
%   Columna 1: timestamp inicio evento (seg)
%   Columna 2: timestamp fin evento (seg)
%   Columna 3: clase (1=Derecha, 0=Izquierda) — ver MODULO_BATCH...m línea 154
%
% SALIDA:
%   cm_ded: [2×2] - Matriz confusión DEDOS
%           [TN, FP; FN, TP]
%   cm_mun: [2×2] - Matriz confusión MUÑECA
%   acc_ded: double - Accuracy DEDOS (0-1)
%   acc_mun: double - Accuracy MUÑECA (0-1)
%
% REFERENCIAS TESIS:
%   Hipótesis (main.tex:664-669):
%   "El clasificador mejorará exactitud respecto a sin clasificador"
%
%   Objetivo (main.tex:814-823):
%   "Implementar ICO para control de movimientos de mano"
%
% GRÁFICOS GENERADOS:
%   1. Predicciones DEDOS vs Labels en tiempo
%   2. Predicciones MUÑECA vs Labels en tiempo
%   3. Confianza DEDOS en tiempo
%   4. Confianza MUÑECA en tiempo
%   5. Matriz confusión DEDOS (heatmap)
%   6. Matriz confusión MUÑECA (heatmap)
%
% EJEMPLO:
%   [cm_d, cm_m, acc_d, acc_m] = VALIDADOR_CON_LABELS(...
%       pred_ded, conf_ded, ...
%       pred_mun, conf_mun, ...
%       tiempo, ...
%       'labels_reales.csv');
%   
%   fprintf('Accuracy DEDOS: %.2f%%\n', acc_d*100);
%   fprintf('Accuracy MUÑECA: %.2f%%\n', acc_m*100);
%
% AUTHOR: OpenCode BCI System
% DATE: 2026-09-30
% VERSION: 1.0
%

function [cm_ded, cm_mun, acc_ded, acc_mun] = ...
    VALIDADOR_CON_LABELS(pred_ded, conf_ded, pred_mun, conf_mun, tiempo, csv_labels)

fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('           VALIDADOR: Predicciones vs Labels Reales\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

%% 1. CARGAR LABELS DESDE CSV
fprintf('1. Cargando labels reales desde CSV...\n');
try
    labels_table = readtable(csv_labels);
    fprintf('   ✓ CSV cargado\n');
    fprintf('   - Eventos: %d\n\n', height(labels_table));
catch ME
    error('No se pudo cargar CSV: %s', ME.message);
end

%% 2. GENERAR LABELS CONTINUOS PARA CADA PREDICCIÓN
fprintf('2. Generando labels continuos...\n');

% Extraer timestamps y clases del CSV
timestamps_ini = labels_table{:, 1};
timestamps_fin = labels_table{:, 2};
clases_reales = labels_table{:, 3};

% Para cada predicción, buscar qué clase debería tener
labels_ded = zeros(length(tiempo), 1);
labels_mun = zeros(length(tiempo), 1);

for i = 1 : length(tiempo)
    t = tiempo(i);
    
    % Buscar si este timestamp cae dentro de algún evento
    evento_idx = find((t >= timestamps_ini) & (t <= timestamps_fin), 1);
    
    if ~isempty(evento_idx)
        clase_evento = clases_reales(evento_idx);
        labels_ded(i) = clase_evento;
        labels_mun(i) = clase_evento;  % Mismo label para ambos (simplificado)
    else
        % Sin etiqueta: asumir posición neutra (0)
        labels_ded(i) = 0;
        labels_mun(i) = 0;
    end
end

n_etiquetadas = sum((labels_ded ~= -1) & (labels_ded ~= 0));
fprintf('   ✓ Labels generados\n');
fprintf('   - Predicciones etiquetadas: %d / %d (%.1f%%)\n\n', n_etiquetadas, length(tiempo), n_etiquetadas/length(tiempo)*100);

%% 3. CALCULAR MATRICES DE CONFUSIÓN - DEDOS
fprintf('3. Calculando matriz confusión - DEDOS...\n');

cm_ded = confusionmat(labels_ded, pred_ded);
if size(cm_ded, 1) == 1
    cm_ded = [cm_ded, 0; 0, 0];
end

TP_ded = cm_ded(2, 2);
FP_ded = cm_ded(1, 2);
FN_ded = cm_ded(2, 1);
TN_ded = cm_ded(1, 1);

sensitivity_ded = TP_ded / (TP_ded + FN_ded + eps);
specificity_ded = TN_ded / (TN_ded + FP_ded + eps);
acc_ded = (TP_ded + TN_ded) / sum(cm_ded(:));

fprintf('   Matriz confusión DEDOS:\n');
fprintf('                Predicho 0   Predicho 1\n');
fprintf('   Real 0:        %4d          %4d\n', TN_ded, FP_ded);
fprintf('   Real 1:        %4d          %4d\n', FN_ded, TP_ded);
fprintf('   \n');
fprintf('   Accuracy:   %.3f (%.1f%%)\n', acc_ded, acc_ded*100);
fprintf('   Sensitivity: %.3f\n', sensitivity_ded);
fprintf('   Specificity: %.3f\n\n', specificity_ded);

%% 4. CALCULAR MATRICES DE CONFUSIÓN - MUÑECA
fprintf('4. Calculando matriz confusión - MUÑECA...\n');

cm_mun = confusionmat(labels_mun, pred_mun);
if size(cm_mun, 1) == 1
    cm_mun = [cm_mun, 0; 0, 0];
end

TP_mun = cm_mun(2, 2);
FP_mun = cm_mun(1, 2);
FN_mun = cm_mun(2, 1);
TN_mun = cm_mun(1, 1);

sensitivity_mun = TP_mun / (TP_mun + FN_mun + eps);
specificity_mun = TN_mun / (TN_mun + FP_mun + eps);
acc_mun = (TP_mun + TN_mun) / sum(cm_mun(:));

fprintf('   Matriz confusión MUÑECA:\n');
fprintf('                Predicho 0   Predicho 1\n');
fprintf('   Real 0:        %4d          %4d\n', TN_mun, FP_mun);
fprintf('   Real 1:        %4d          %4d\n', FN_mun, TP_mun);
fprintf('   \n');
fprintf('   Accuracy:   %.3f (%.1f%%)\n', acc_mun, acc_mun*100);
fprintf('   Sensitivity: %.3f\n', sensitivity_mun);
fprintf('   Specificity: %.3f\n\n', specificity_mun);

%% 5. GENERAR GRÁFICOS
fprintf('5. Generando visualizaciones...\n');

% === FIGURA 1: PREDICCIONES DEDOS vs LABELS ===
figure('Name', 'Validación - DEDOS vs Labels', 'Color', 'w', 'Position', [100 100 1000 600]);

subplot(2,2,1); hold on; grid on;
stairs(tiempo, labels_ded, 'b-', 'LineWidth', 2);
stairs(tiempo, pred_ded, 'r--', 'LineWidth', 1.5);
xlabel('Tiempo (seg)');
ylabel('Clase');
title('Predicciones DEDOS vs Labels Reales');
legend('Label Real', 'Predicción', 'Location', 'best');
ylim([-0.5, 1.5]);
set(gca, 'YTick', [0, 1], 'YTickLabel', {'Abre (0)', 'Cierra (1)'});

% === FIGURA 2: CONFIANZA DEDOS ===
subplot(2,2,2); hold on; grid on;
plot(tiempo, conf_ded, 'r.-', 'MarkerSize', 4);
xlabel('Tiempo (seg)');
ylabel('Confianza');
title('Confianza Predicción - DEDOS');
ylim([0, 1]);

% === FIGURA 3: MATRIZ CONFUSIÓN DEDOS ===
subplot(2,2,3);
imagesc(cm_ded);
colorbar;
set(gca, 'XTick', [1, 2], 'YTick', [1, 2]);
set(gca, 'XTickLabel', {'Pred 0 (Abre)', 'Pred 1 (Cierra)'});
set(gca, 'YTickLabel', {'Real 0 (Abre)', 'Real 1 (Cierra)'});
title(sprintf('Matriz Confusión DEDOS (Acc: %.1f%%)', acc_ded*100));
for i = 1:2
    for j = 1:2
        text(j, i, num2str(cm_ded(i,j)), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontSize', 12, 'FontWeight', 'bold', 'Color', 'w');
    end
end

% === FIGURA 4: ESTADÍSTICAS ===
subplot(2,2,4); axis off;
stats_text = sprintf(...
    'DEDOS - Estadísticas\n\n' ...
    'Accuracy:   %.1f%%\n' ...
    'Sensitivity: %.1f%%\n' ...
    'Specificity: %.1f%%\n' ...
    'TP: %d, FP: %d\n' ...
    'FN: %d, TN: %d\n' ...
    'Total muestras: %d\n' ...
    'Confianza media: %.3f\n', ...
    acc_ded*100, sensitivity_ded*100, specificity_ded*100, ...
    TP_ded, FP_ded, FN_ded, TN_ded, ...
    sum(cm_ded(:)), mean(conf_ded));
text(0.1, 0.5, stats_text, 'FontSize', 11, 'FontFamily', 'monospace', ...
    'VerticalAlignment', 'middle', 'BackgroundColor', [0.95 0.95 0.95]);

%% === FIGURA 2: PREDICCIONES MUÑECA ===
figure('Name', 'Validación - MUÑECA vs Labels', 'Color', 'w', 'Position', [1100 100 1000 600]);

subplot(2,2,1); hold on; grid on;
stairs(tiempo, labels_mun, 'g-', 'LineWidth', 2);
stairs(tiempo, pred_mun, 'r--', 'LineWidth', 1.5);
xlabel('Tiempo (seg)');
ylabel('Clase');
title('Predicciones MUÑECA vs Labels Reales');
legend('Label Real', 'Predicción', 'Location', 'best');
ylim([-0.5, 1.5]);
set(gca, 'YTick', [0, 1], 'YTickLabel', {'Neutro (0)', 'Pronación (1)'});

% === CONFIANZA MUÑECA ===
subplot(2,2,2); hold on; grid on;
plot(tiempo, conf_mun, 'm.-', 'MarkerSize', 4);
xlabel('Tiempo (seg)');
ylabel('Confianza');
title('Confianza Predicción - MUÑECA');
ylim([0, 1]);

% === MATRIZ CONFUSIÓN MUÑECA ===
subplot(2,2,3);
imagesc(cm_mun);
colorbar;
set(gca, 'XTick', [1, 2], 'YTick', [1, 2]);
set(gca, 'XTickLabel', {'Pred 0 (Neutro)', 'Pred 1 (Pronación)'});
set(gca, 'YTickLabel', {'Real 0 (Neutro)', 'Real 1 (Pronación)'});
title(sprintf('Matriz Confusión MUÑECA (Acc: %.1f%%)', acc_mun*100));
for i = 1:2
    for j = 1:2
        text(j, i, num2str(cm_mun(i,j)), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontSize', 12, 'FontWeight', 'bold', 'Color', 'w');
    end
end

% === ESTADÍSTICAS MUÑECA ===
subplot(2,2,4); axis off;
stats_text_mun = sprintf(...
    'MUÑECA - Estadísticas\n\n' ...
    'Accuracy:   %.1f%%\n' ...
    'Sensitivity: %.1f%%\n' ...
    'Specificity: %.1f%%\n' ...
    'TP: %d, FP: %d\n' ...
    'FN: %d, TN: %d\n' ...
    'Total muestras: %d\n' ...
    'Confianza media: %.3f\n', ...
    acc_mun*100, sensitivity_mun*100, specificity_mun*100, ...
    TP_mun, FP_mun, FN_mun, TN_mun, ...
    sum(cm_mun(:)), mean(conf_mun));
text(0.1, 0.5, stats_text_mun, 'FontSize', 11, 'FontFamily', 'monospace', ...
    'VerticalAlignment', 'middle', 'BackgroundColor', [0.95 0.95 0.95]);

fprintf('   ✓ Gráficos generados\n\n');

fprintf('════════════════════════════════════════════════════════════\n');
fprintf('✓ VALIDACIÓN COMPLETADA\n\n');
fprintf('RESUMEN:\n');
fprintf('  DEDOS - Accuracy: %.1f%% | Sensitivity: %.1f%% | Specificity: %.1f%%\n', ...
    acc_ded*100, sensitivity_ded*100, specificity_ded*100);
fprintf('  MUÑECA - Accuracy: %.1f%% | Sensitivity: %.1f%% | Specificity: %.1f%%\n\n', ...
    acc_mun*100, sensitivity_mun*100, specificity_mun*100);

end
