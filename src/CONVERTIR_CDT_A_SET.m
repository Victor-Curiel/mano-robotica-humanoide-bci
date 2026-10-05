%% CONVERTIR_CDT_A_SET
% Convierte archivo Neuroscan .cdt a formato EEGLAB .set
%
% USO:
%   CONVERTIR_CDT_A_SET('Acquisition 15.cdt')
%
% SALIDA:
%   Acquisition_15_crudo.set (formato estándar EEGLAB)
%   Acquisition_15_crudo.fdt (datos binarios)
%
% REFERENCIA TESIS:
%   - Hipótesis: "El clasificador de patrones mejora exactitud"
%   - Objetivo: "Implementar ICO para control de mano robótica"
%
% Autor: OpenCode
% Fecha: 2026-09-30
%

function CONVERTIR_CDT_A_SET(archivo_cdt_entrada)

clc; close all;

fprintf('\n════════════════════════════════════════════════════════════\n');
fprintf('        CONVERTIDOR: Neuroscan .cdt → EEGLAB .set\n');
fprintf('════════════════════════════════════════════════════════════\n\n');

% Validar entrada
if nargin < 1
    fprintf('ERROR: Especifica archivo .cdt\n');
    fprintf('Uso: CONVERTIR_CDT_A_SET(''Acquisition 15.cdt'')\n');
    return
end

% Rutas
ruta_entrada = 'C:\Users\vhca1\Desktop\Acquisition\Sin_clasificar\arzaluzImagina280926-1\';
archivo_cdt_completo = fullfile(ruta_entrada, archivo_cdt_entrada);

% Verificar que existe
if ~exist(archivo_cdt_completo, 'file')
    fprintf('ERROR: Archivo no encontrado\n');
    fprintf('Ruta: %s\n', archivo_cdt_completo);
    return
end

fprintf('Archivo entrada: %s\n\n', archivo_cdt_entrada);

% OPCION 1: Usar LOAD_CDT.m (si existe)
fprintf('Intentando cargar con LOAD_CDT.m...\n');
try
    [signal, fs, labels] = LOAD_CDT(archivo_cdt_completo);
    fprintf('✓ Cargado con LOAD_CDT.m\n');
    fprintf('  - Canales: %d\n', size(signal, 1));
    fprintf('  - Muestras: %d\n', size(signal, 2));
    fprintf('  - Fs: %d Hz\n\n', fs);
    
    % Crear estructura EEGLAB
    EEG = eeg_emptyset();
    EEG.data = signal;
    EEG.srate = fs;
    EEG.nbchan = size(signal, 1);
    EEG.pnts = size(signal, 2);
    EEG.trials = 1;
    EEG.xmin = 0;
    EEG.xmax = (EEG.pnts - 1) / EEG.srate;
    
    % Asignar etiquetas de canales estándar (64 canales Neuroscan)
    if EEG.nbchan >= 64
        EEG = pop_chanedit(EEG, 'lookup', 'C:\Users\vhca1\Documents\eeglab\plugins\dipfit\standard_BESA\standard-10-5-cap385.elp');
    end
    
    EEG = eeg_checkset(EEG);
    
catch ME
    fprintf('ERROR con LOAD_CDT.m: %s\n\n', ME.message);
    fprintf('Intentando cargar directamente como binario...\n');
    
    % OPCION 2: Cargar como binario directo
    try
        fid = fopen(archivo_cdt_completo, 'rb');
        signal_raw = fread(fid, 'float32');
        fclose(fid);
        
        % Asumir 64 canales, 500 Hz
        fs = 500;
        nbchan = 64;
        npuntos = length(signal_raw) / nbchan;
        signal = reshape(signal_raw, nbchan, npuntos);
        
        fprintf('✓ Cargado como binario\n');
        fprintf('  - Canales: %d\n', nbchan);
        fprintf('  - Muestras: %d\n', npuntos);
        fprintf('  - Fs: %d Hz\n\n', fs);
        
        % Crear estructura EEGLAB
        EEG = eeg_emptyset();
        EEG.data = signal;
        EEG.srate = fs;
        EEG.nbchan = nbchan;
        EEG.pnts = npuntos;
        EEG.trials = 1;
        EEG.xmin = 0;
        EEG.xmax = (EEG.pnts - 1) / EEG.srate;
        
        EEG = eeg_checkset(EEG);
        
    catch ME2
        fprintf('ERROR: No se pudo cargar archivo\n');
        fprintf('%s\n', ME2.message);
        return
    end
end

% Guardar como .set
[~, nombre_sin_ext, ~] = fileparts(archivo_cdt_entrada);
archivo_set_salida = [nombre_sin_ext '_crudo.set'];
ruta_salida = ruta_entrada;

fprintf('Guardando como .set...\n');
fprintf('Archivo: %s\n\n', archivo_set_salida);

try
    EEG = pop_saveset(EEG, 'filename', archivo_set_salida, 'filepath', ruta_salida);
    fprintf('✓ CONVERSIÓN EXITOSA\n\n');
    fprintf('Salida:\n');
    fprintf('  %s\n', fullfile(ruta_salida, archivo_set_salida));
    fprintf('  %s\n', fullfile(ruta_salida, [nombre_sin_ext '_crudo.fdt']));
    fprintf('\nAhora puedes usar PREDICTOR_DATOS_CRUDOS.m con este archivo\n\n');
    
catch ME
    fprintf('ERROR al guardar: %s\n', ME.message);
    return
end

fprintf('════════════════════════════════════════════════════════════\n\n');

end
