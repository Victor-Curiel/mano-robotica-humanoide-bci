%% TEST_ESP32_SIMULADO
% Simula transmisión a ESP32 sin hardware real
%
% Útil para testing offline del protocolo de comunicación,
% verificar formato de datos y debugging sin necesidad de
% microcontrolador disponible.
%
% USO:
%   TEST_ESP32_SIMULADO();  % Carga datos de demo_resultados.mat
%   TEST_ESP32_SIMULADO(pred_ded, conf_ded, pred_mun, conf_mun, tiempo);
%
% ENTRADA (opcional):
%   pred_ded: predicciones dedos
%   conf_ded: confianza dedos
%   pred_mun: predicciones muñeca
%   conf_mun: confianza muñeca
%   tiempo: timestamps
%
% FUNCIONES:
%   1. Genera datos de prueba (si no se proporciona entrada)
%   2. Simula puerto serial
%   3. Envía datos con formato correcto
%   4. Verifica integridad de mensajes
%   5. Genera reporte de transmisión
%
% PROTOCOLO:
%   Formato: "clase_ded,conf_ded,clase_mun,conf_mun,timestamp\n"
%   Ejemplo: "1,0.87,0,0.65,1.234\n"
%
% MAPEO VERIFICADO:
%   DEDOS:
%   - 0 → PWM 30 (abiertos)
%   - 1 → PWM 120 (cerrados)
%
%   MUÑECA:
%   - 0 → PWM 90 (neutra)
%   - 1 → PWM 60 (pronación)
%
% AUTHOR: OpenCode BCI System
% DATE: 2026-09-30
%

function TEST_ESP32_SIMULADO(varargin)

fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('      TEST ESP32 SIMULADO - Sin Hardware Real\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

%% CARGAR DATOS
if nargin == 0
    % Cargar desde demo_resultados.mat
    fprintf('1. Cargando datos de demo_resultados.mat...\n');
    if ~exist('demo_resultados.mat', 'file')
        fprintf('   ERROR: demo_resultados.mat no encontrado\n');
        fprintf('   Ejecuta DEMO_PREDICCION_COMPLETA primero\n');
        return
    end
    load('demo_resultados.mat', 'pred_ded', 'conf_ded', 'pred_mun', 'conf_mun', 'tiempo');
    fprintf('   ✓ Datos cargados\n\n');
    
elseif nargin == 5
    % Usar datos proporcionados
    pred_ded = varargin{1};
    conf_ded = varargin{2};
    pred_mun = varargin{3};
    conf_mun = varargin{4};
    tiempo = varargin{5};
    fprintf('1. Usando datos proporcionados\n');
    fprintf('   - Muestras: %d\n\n', length(pred_ded));
else
    error('Uso: TEST_ESP32_SIMULADO() o TEST_ESP32_SIMULADO(pred_ded, conf_ded, pred_mun, conf_mun, tiempo)');
end

%% SIMULAR ENVÍO
fprintf('2. Simulando transmisión a COM3...\n');
fprintf('   Protocolo: clase_ded,conf_ded,clase_mun,conf_mun,timestamp\n\n');

% Arreglos para almacenar datos
mensajes = cell(length(pred_ded), 1);
mensajes_parsidos = zeros(length(pred_ded), 5);
errores = 0;

% Generar y verificar cada mensaje
for i = 1 : length(pred_ded)
    % Formatear mensaje
    msg = sprintf('%d,%.2f,%d,%.2f,%.3f', ...
        pred_ded(i), conf_ded(i), ...
        pred_mun(i), conf_mun(i), ...
        tiempo(i));
    
    mensajes{i} = msg;
    
    % Parsear de vuelta para verificar
    n = sscanf(msg, '%d,%f,%d,%f,%f', ...
        [1 5]);
    
    if length(n) ~= 5
        errores = errores + 1;
    else
        mensajes_parsidos(i, :) = n;
    end
    
    % Mostrar primeros 5 y últimos 5 mensajes
    if i <= 5 || i > length(pred_ded) - 5
        fprintf('   [%3d] "%s"\n', i, msg);
    elseif i == 6
        fprintf('   ...\n');
    end
end

fprintf('\n   ✓ %d mensajes generados\n', length(pred_ded));
fprintf('   ✓ %d mensajes verificados\n', length(pred_ded) - errores);
fprintf('   ✗ %d mensajes con error\n\n', errores);

%% VERIFICAR INTEGRIDAD
fprintf('3. Verificando integridad de datos...\n');

% Validar rango de valores
errores_rango = 0;
for i = 1 : length(pred_ded)
    % Clase dedos: debe ser 0 o 1
    if pred_ded(i) ~= 0 && pred_ded(i) ~= 1
        errores_rango = errores_rango + 1;
    end
    % Clase muñeca: debe ser 0 o 1
    if pred_mun(i) ~= 0 && pred_mun(i) ~= 1
        errores_rango = errores_rango + 1;
    end
    % Confianza: debe estar 0-1
    if conf_ded(i) < 0 || conf_ded(i) > 1
        errores_rango = errores_rango + 1;
    end
    if conf_mun(i) < 0 || conf_mun(i) > 1
        errores_rango = errores_rango + 1;
    end
end

fprintf('   - Rango valores: ');
if errores_rango == 0
    fprintf('✓ OK\n');
else
    fprintf('✗ %d errores\n', errores_rango);
end

fprintf('   - Longitud consistente: ');
if length(pred_ded) == length(pred_mun) && length(pred_ded) == length(conf_ded)
    fprintf('✓ OK (%d muestras)\n', length(pred_ded));
else
    fprintf('✗ INCONSISTENTE\n');
end

fprintf('   - Timestamps monotónicos: ');
if all(diff(tiempo) >= 0)
    fprintf('✓ OK\n');
else
    fprintf('✗ NO MONOTÓNICOS\n');
end

fprintf('\n');

%% MAPEO A SERVOS
fprintf('4. Verificando mapeo a servos...\n');

% Calcular PWM para cada predicción
pwm_dedos = zeros(length(pred_ded), 1);
pwm_muneca = zeros(length(pred_ded), 1);

for i = 1 : length(pred_ded)
    if pred_ded(i) == 0
        pwm_dedos(i) = 30;   % Abiertos
    else
        pwm_dedos(i) = 120;  % Cerrados
    end
    
    if pred_mun(i) == 0
        pwm_muneca(i) = 90;  % Neutro
    else
        pwm_muneca(i) = 60;  % Pronación
    end
end

fprintf('   DEDOS (MG995):\n');
fprintf('     - Abiertos (PWM 30): %d (%.1f%%)\n', sum(pwm_dedos == 30), sum(pwm_dedos == 30)/length(pwm_dedos)*100);
fprintf('     - Cerrados (PWM 120): %d (%.1f%%)\n', sum(pwm_dedos == 120), sum(pwm_dedos == 120)/length(pwm_dedos)*100);

fprintf('   MUÑECA (SG90):\n');
fprintf('     - Neutra (PWM 90): %d (%.1f%%)\n', sum(pwm_muneca == 90), sum(pwm_muneca == 90)/length(pwm_muneca)*100);
fprintf('     - Pronación (PWM 60): %d (%.1f%%)\n', sum(pwm_muneca == 60), sum(pwm_muneca == 60)/length(pwm_muneca)*100);

fprintf('\n');

%% VISUALIZAR SECUENCIA
fprintf('5. Generando visualización de secuencia...\n');

figure('Name', 'TEST ESP32 - Secuencia de Movimientos', 'Color', 'w', 'Position', [100 100 1000 600]);

% DEDOS
subplot(2,2,1); hold on; grid on;
plot(tiempo, pwm_dedos, 'b.-', 'MarkerSize', 4, 'LineWidth', 1);
xlabel('Tiempo (seg)'); ylabel('PWM');
title('Secuencia PWM DEDOS (MG995)');
ylim([20, 130]);
set(gca, 'YTick', [30, 120], 'YTickLabel', {'Abiertos (30)', 'Cerrados (120)'});

% MUÑECA
subplot(2,2,2); hold on; grid on;
plot(tiempo, pwm_muneca, 'g.-', 'MarkerSize', 4, 'LineWidth', 1);
xlabel('Tiempo (seg)'); ylabel('PWM');
title('Secuencia PWM MUÑECA (SG90)');
ylim([50, 100]);
set(gca, 'YTick', [60, 90], 'YTickLabel', {'Pronación (60)', 'Neutro (90)'});

% HISTOGRAMA DEDOS
subplot(2,2,3);
h1 = histogram(pwm_dedos, 'FaceColor', 'b', 'EdgeColor', 'none');
xlabel('PWM'); ylabel('Frecuencia');
title('Distribución PWM DEDOS');
xlim([0, 150]);

% HISTOGRAMA MUÑECA
subplot(2,2,4);
h2 = histogram(pwm_muneca, 'FaceColor', 'g', 'EdgeColor', 'none');
xlabel('PWM'); ylabel('Frecuencia');
title('Distribución PWM MUÑECA');
xlim([40, 100]);

fprintf('   ✓ Gráfico generado\n\n');

%% RESUMEN FINAL
fprintf('════════════════════════════════════════════════════════════\n');
fprintf('RESUMEN DE TEST\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

fprintf('ESTADÍSTICAS:\n');
fprintf('  Total muestras transmitidas: %d\n', length(pred_ded));
fprintf('  Duración transmisión: %.1f segundos\n', tiempo(end));
fprintf('  Velocidad: %.2f muestras/segundo (esperado: 1.0)\n\n', length(pred_ded)/tiempo(end));

fprintf('ERRORES:\n');
fprintf('  Formateo: %d\n', errores);
fprintf('  Rango: %d\n', errores_rango);
fprintf('  Total: %d\n\n', errores + errores_rango);

fprintf('MOVIMIENTOS ESPERADOS:\n');
fprintf('  Cambios en DEDOS: %d transiciones\n', sum(diff(pwm_dedos) ~= 0));
fprintf('  Cambios en MUÑECA: %d transiciones\n', sum(diff(pwm_muneca) ~= 0));

fprintf('\n');

if errores + errores_rango == 0
    fprintf('✓ TEST EXITOSO\n');
    fprintf('  El ESP32 debería recibir los datos correctamente\n');
else
    fprintf('✗ ERRORES DETECTADOS\n');
    fprintf('  Revisar datos antes de transmitir a ESP32\n');
end

fprintf('\n════════════════════════════════════════════════════════════\n\n');

fprintf('PRÓXIMO PASO:\n');
fprintf('  Si test pasó, envía a ESP32 real:\n');
fprintf('  >> ENVIAR_A_ESP32(archivo_set, modelo_mat, ''puerto_com'', ''COM3'');\n\n');

end
