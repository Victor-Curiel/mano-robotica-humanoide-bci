%% ENVIAR_A_ESP32
% Ejecuta predictores y envía datos a ESP32 por puerto serial
%
% Realiza predicción continua (DEDOS + MUÑECA) y transmite
% resultados a microcontrolador ESP32 para control en tiempo real
% de mano robótica.
%
% USO:
%   ENVIAR_A_ESP32(archivo_set, modelo_mat);
%   ENVIAR_A_ESP32(archivo_set, modelo_mat, 'puerto_com', 'COM3');
%
% ENTRADA:
%   archivo_set: ruta a archivo .set CRUDO (sin filtrar)
%   modelo_mat: ruta a 'Modelo_BCI_Completo_Wav.mat' (red entrenada)
%
% PARÁMETROS OPCIONALES:
%   'puerto_com': puerto COM para ESP32 (default: 'COM3')
%   'baudrate': velocidad comunicación (default: 115200)
%   'duracion': duración máxima transmisión en segundos (default: inf)
%
% PROTOCOLO DE COMUNICACIÓN:
%   Formato: "clase_dedos,conf_dedos,clase_muneca,conf_muneca,timestamp\n"
%   Ejemplo: "1,0.87,0,0.65,1.234\n"
%
%   Campos:
%   - clase_dedos: 0=abre, 1=cierra
%   - conf_dedos: confianza 0-1 (2 decimales)
%   - clase_muneca: 0=neutro, 1=pronación
%   - conf_muneca: confianza 0-1 (2 decimales)
%   - timestamp: tiempo en segundos (3 decimales)
%
% MAPEO SERVO:
%   DEDOS (5x MG995):
%   - clase=0: PWM 30 (0°, dedos abiertos)
%   - clase=1: PWM 120 (180°, dedos cerrados)
%
%   MUÑECA (SG90):
%   - clase=0: PWM 90 (posición neutra)
%   - clase=1: PWM 60 (pronación/giro izquierda)
%
% REFERENCIA TESIS:
%   Objetivo Específico (main.tex:832-851):
%   "Implementar estructura de redes neuronales para correlacionar
%    patrones reconocidos con movimientos de mano"
%
% DIAGRAMA DE FLUJO:
%   1. Cargar modelo entrenado
%   2. Abrir puerto serial a ESP32
%   3. Ejecutar PREDICTOR_DATOS_CRUDOS (DEDOS)
%   4. Ejecutar PREDICTOR_MUNECA
%   5. Para cada segundo de predicción:
%      - Formatear datos
%      - Enviar por serie a ESP32
%      - Esperar 1 segundo (intervalo de predicción)
%   6. Cerrar puerto
%
% EJEMPLO:
%   % Transmisión a ESP32 por COM3
%   ENVIAR_A_ESP32('Acquisition_15_crudo.set', ...
%                  'Modelo_BCI_Completo_Wav.mat', ...
%                  'puerto_com', 'COM3');
%
%   % Con parámetros personalizados
%   ENVIAR_A_ESP32('Acquisition_15_crudo.set', ...
%                  'Modelo_BCI_Completo_Wav.mat', ...
%                  'puerto_com', 'COM4', ...
%                  'baudrate', 9600, ...
%                  'duracion', 120);  % 2 minutos
%
% AUTHOR: OpenCode BCI System
% DATE: 2026-09-30
% VERSION: 1.0
%

function ENVIAR_A_ESP32(archivo_set, modelo_mat, varargin)

%% PARSING DE PARÁMETROS
p = inputParser;
addParameter(p, 'puerto_com', 'COM3', @ischar);
addParameter(p, 'baudrate', 115200, @isnumeric);
addParameter(p, 'duracion', inf, @isnumeric);
parse(p, varargin{:});

puerto_com = p.Results.puerto_com;
baudrate = p.Results.baudrate;
duracion_max = p.Results.duracion;

fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('           ENVIAR A ESP32 - Control en Tiempo Real\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

fprintf('Puerto: %s\n', puerto_com);
fprintf('Baudrate: %d\n', baudrate);
fprintf('Duración máx: ');
if isinf(duracion_max)
    fprintf('indefinida\n\n');
else
    fprintf('%.0f segundos\n\n', duracion_max);
end

%% 1. EJECUTAR PREDICTORES
fprintf('1. Ejecutando predictor DEDOS...\n');
[pred_ded, conf_ded, tiempo, ~] = PREDICTOR_DATOS_CRUDOS(archivo_set, modelo_mat);
fprintf('   ✓ %d predicciones obtenidas\n\n', length(pred_ded));

fprintf('2. Ejecutando predictor MUÑECA...\n');
[pred_mun, conf_mun, ~] = PREDICTOR_MUNECA(archivo_set, modelo_mat);
fprintf('   ✓ %d predicciones obtenidas\n\n', length(pred_mun));

%% 2. VALIDAR QUE TENEMOS MISMA CANTIDAD DE DATOS
if length(pred_ded) ~= length(pred_mun)
    warning('Longitud predicciones DEDOS (%d) != MUÑECA (%d)', ...
        length(pred_ded), length(pred_mun));
    min_len = min(length(pred_ded), length(pred_mun));
    pred_ded = pred_ded(1:min_len);
    conf_ded = conf_ded(1:min_len);
    pred_mun = pred_mun(1:min_len);
    conf_mun = conf_mun(1:min_len);
    tiempo = tiempo(1:min_len);
end

%% 3. ABRIR PUERTO SERIAL
fprintf('3. Abriendo puerto serial %s...\n', puerto_com);

try
    puerto = serial(puerto_com, 'BaudRate', baudrate, 'Terminator', 'LF');
    fopen(puerto);
    pause(1);  % Esperar a que se estabilice conexión
    fprintf('   ✓ Puerto abierto\n\n');
catch ME
    error('ERROR al abrir puerto: %s\n', ME.message);
end

%% 4. ENVIAR DATOS
fprintf('4. Enviando datos a ESP32...\n');
fprintf('   Protocolo: clase_ded,conf_ded,clase_mun,conf_mun,timestamp\n\n');

n_datos = length(pred_ded);
inicio_envio = tic;

for i = 1 : n_datos
    % Verificar duración máxima
    tiempo_transcurrido = toc(inicio_envio);
    if tiempo_transcurrido > duracion_max
        fprintf('   ⏱ Duración máxima alcanzada (%.0f seg)\n', duracion_max);
        break;
    end
    
    % Formatear mensaje
    % Formato: "clase_ded,conf_ded,clase_mun,conf_mun,tiempo"
    msg = sprintf('%d,%.2f,%d,%.2f,%.3f\n', ...
        pred_ded(i), conf_ded(i), ...
        pred_mun(i), conf_mun(i), ...
        tiempo(i));
    
    % Enviar
    try
        fprintf(puerto, msg);
        
        % Mostrar progreso cada 10 datos o al final
        if mod(i, 10) == 0 || i == n_datos
            fprintf('   [%3d/%3d] Enviado: %s', i, n_datos, msg);
        end
        
    catch ME
        fprintf('   ERROR en envío %d: %s\n', i, ME.message);
        break;
    end
    
    % Esperar 1 segundo (intervalo de predicción)
    pause(1);
end

fprintf('\n   ✓ Transmisión completada\n\n');

%% 5. CERRAR PUERTO
fprintf('5. Cerrando puerto...\n');
try
    fclose(puerto);
    delete(puerto);
    fprintf('   ✓ Puerto cerrado\n\n');
catch ME
    fprintf('   ERROR al cerrar: %s\n\n', ME.message);
end

%% 6. RESUMEN
fprintf('════════════════════════════════════════════════════════════\n');
fprintf('✓ TRANSMISIÓN A ESP32 COMPLETADA\n\n');

fprintf('RESUMEN:\n');
fprintf('  Datos enviados: %d predicciones\n', n_datos);
fprintf('  Tiempo de transmisión: %.1f segundos\n', tiempo_transcurrido);
fprintf('  Velocidad: %.1f pred/seg (esperado: 1 pred/seg)\n\n', n_datos/tiempo_transcurrido);

fprintf('El ESP32 debe haber recibido los comandos de movimiento.\n');
fprintf('Verifica que la mano se movió correctamente:\n');
fprintf('  - Dedos: abiertos ↔ cerrados según clase\n');
fprintf('  - Muñeca: neutra ↔ pronación según clase\n\n');

end
