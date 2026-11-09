import pygame
import random
import time
import csv
import numpy as np
from datetime import datetime
import sys
from pathlib import Path

REGISTRO_DIR = Path(__file__).resolve().parent.parent / "Registro De Pruebas" 
import os
from pathlib import Path

# ==========================================
# CONFIGURACIÓN DEL EXPERIMENTO
# ==========================================
# Colores
COLOR_FONDO = (255, 255, 255)  # Blanco
COLOR_ROJO = (255, 0, 0)       # Círculo (Der)
COLOR_VERDE = (0, 255, 0)      # Cuadrado (Izq)
COLOR_TEXTO = (0, 0, 0)

# Pantalla
ANCHO = 800
ALTO = 600

# Tiempos (segundos)
DURACION_INTRO = 10.0
DURACION_ESTIMULO = 2.0
DURACION_TOTAL_PRUEBA = 3 * 60 

# Rangos aleatorios
RANGO_INICIO_ALEATORIO = (3.0, 6.0)
RANGO_ISI = (2.0, 6.0)

# Frecuencias de Audio (Hz)
FREQ_ROJO = 1000  # Agudo para Rojo
FREQ_VERDE = 500  # Grave para Verde

# ==========================================
# GENERADOR DE SONIDO (SINTETIZADOR)
# ==========================================
def generar_tono(frecuencia, duracion=0.5, volumen=0.5, sample_rate=44100):
    """
    Genera un objeto de sonido Pygame (onda senoidal) sin archivos externos.
    """
    n_samples = int(sample_rate * duracion)
    # Generar onda senoidal con numpy
    t = np.linspace(0, duracion, n_samples, False)
    onda = np.sin(2 * np.pi * frecuencia * t) * volumen * 32767
    
    # Convertir a array de 16-bit estéreo para Pygame
    onda_stereo = np.column_stack((onda, onda)).astype(np.int16)
    return pygame.sndarray.make_sound(onda_stereo)

# ==========================================
# FUNCIONES AUXILIARES
# ==========================================
def esperar_tiempo(segundos):
    tiempo_inicio = time.time()
    while (time.time() - tiempo_inicio) < segundos:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                pygame.quit()
                sys.exit()
        time.sleep(0.01)

def dibujar_texto(pantalla, texto, tamano=30):
    pantalla.fill(COLOR_FONDO)
    fuente = pygame.font.SysFont("Arial", tamano)
    superficie = fuente.render(texto, True, COLOR_TEXTO)
    rect = superficie.get_rect(center=(ANCHO//2, ALTO//2))
    pantalla.blit(superficie, rect)
    pygame.display.flip()

def presentar_estimulo(pantalla, tipo, sonido_rojo, sonido_verde):
    """
    Dibuja la figura y reproduce el sonido correspondiente.
    """
    pantalla.fill(COLOR_FONDO)
    centro = (ANCHO // 2, ALTO // 2)
    radio = 100 

    if tipo == 'rojo':
        # ESTÍMULO ROJO (Derecha) -> Tono Agudo
        pygame.draw.circle(pantalla, COLOR_ROJO, centro, radio)
        sonido_rojo.play()
        etiqueta = "Circulo_Rojo_Der"
        
    elif tipo == 'verde':
        # ESTÍMULO VERDE (Izquierda) -> Tono Grave
        rect = pygame.Rect(0, 0, radio*2, radio*2)
        rect.center = centro
        pygame.draw.rect(pantalla, COLOR_VERDE, rect)
        sonido_verde.play()
        etiqueta = "Cuadrado_Verde_Izq"
    
    pygame.display.flip()
    return etiqueta

# ==========================================
# MAIN
# ==========================================
def main():
    # 1. Inicialización de Pygame y Audio
    pygame.init()
    pygame.mixer.init(frequency=44100, size=-16, channels=2) # Init mixer
    
    pantalla = pygame.display.set_mode((ANCHO, ALTO))
    pygame.display.set_caption("Protocolo BCI - Visual + Auditivo")
    
    # Pre-generar sonidos para evitar latencia
    sound_rojo = generar_tono(FREQ_ROJO, duracion=0.5)
    sound_verde = generar_tono(FREQ_VERDE, duracion=0.5)

    # 2. Configuración de Directorio y CSV con Timestamp
    directorio_destino = str(REGISTRO_DIR)
    
    # Asegurarse de que la carpeta exista
    if not os.path.exists(directorio_destino):
        os.makedirs(directorio_destino, exist_ok=True)

    timestamp_inicio = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    nombre_archivo = f"{timestamp_inicio}.csv"
    ruta_completa = os.path.join(directorio_destino, nombre_archivo)
    
    archivo_csv = open(ruta_completa, mode='w', newline='', encoding='utf-8')
    escritor_csv = csv.writer(archivo_csv)
    escritor_csv.writerow(['Timestamp', 'Tiempo_Exp', 'Estimulo', 'Frecuencia_Audio_Hz', 'Duracion_Show', 'ISI_Previo'])
    
    print(f"--- INICIANDO PRUEBA (Salida: {ruta_completa}) ---")

    # 3. Intro (10s)
    dibujar_texto(pantalla, "La prueba comenzará en breve...", tamano=40)
    esperar_tiempo(DURACION_INTRO)

    # 4. Primer intervalo aleatorio (3-6s)
    isi_actual = random.uniform(*RANGO_INICIO_ALEATORIO)
    pantalla.fill(COLOR_FONDO)
    pygame.display.flip()
    esperar_tiempo(isi_actual)

    tiempo_inicio_global = time.time()
    
    # 5. Bucle Principal
    while True:
        tiempo_actual = time.time()
        t_transcurrido = tiempo_actual - tiempo_inicio_global
        
        if t_transcurrido >= DURACION_TOTAL_PRUEBA:
            break

        # A. Selección Aleatoria
        tipo = random.choice(['rojo', 'verde'])
        
        # B. Presentación (Visual + Audio)
        etiqueta = presentar_estimulo(pantalla, tipo, sound_rojo, sound_verde)
        
        # C. Registro de Datos
        timestamp = datetime.now().strftime("%H:%M:%S.%f")
        freq_audio = FREQ_ROJO if tipo == 'rojo' else FREQ_VERDE
        
        escritor_csv.writerow([
            timestamp,
            f"{t_transcurrido:.3f}",
            etiqueta,
            freq_audio,
            DURACION_ESTIMULO,
            f"{isi_actual:.3f}"
        ])
        archivo_csv.flush()

        # D. Duración del Estímulo
        esperar_tiempo(DURACION_ESTIMULO)

        # E. Intervalo (ISI) variable
        pantalla.fill(COLOR_FONDO)
        pygame.display.flip()
        
        isi_siguiente = random.uniform(*RANGO_ISI)
        esperar_tiempo(isi_siguiente)
        
        isi_actual = isi_siguiente

    # 6. Fin
    dibujar_texto(pantalla, "Prueba Finalizada.", tamano=40)
    time.sleep(3)
    archivo_csv.close()
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()