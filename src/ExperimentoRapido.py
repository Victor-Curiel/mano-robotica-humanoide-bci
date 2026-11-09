import pygame
import random
import time
import csv
import numpy as np
from datetime import datetime
import sys
from pathlib import Path

REGISTRO_DIR = Path(__file__).resolve().parent.parent / "Registro De Pruebas"

# ==========================================
# CONFIGURACIÓN DEL EXPERIMENTO (TIEMPOS RÁPIDOS)
# ==========================================
COLOR_FONDO = (255, 255, 255)
COLOR_ROJO = (255, 0, 0)
COLOR_VERDE = (0, 255, 0)
COLOR_TEXTO = (0, 0, 0)

ANCHO = 800
ALTO = 600

# Tiempos ultracortos para mantener alerta (en segundos)
DURACION_INTRO = 5.0
DURACION_ESTIMULO = 0.5
DURACION_TOTAL_PRUEBA = 3 * 60

RANGO_INICIO_ALEATORIO = (1.0, 2.0)
RANGO_ISI = (0.8, 1.8) # Intervalo muy corto para evitar sincronización Alfa

FREQ_ROJO = 1000
FREQ_VERDE = 500

def generar_tono(frecuencia, duracion=0.5, volumen=0.5, sample_rate=44100):
    n_samples = int(sample_rate * duracion)
    t = np.linspace(0, duracion, n_samples, False)
    onda = np.sin(2 * np.pi * frecuencia * t) * volumen * 32767
    onda_stereo = np.column_stack((onda, onda)).astype(np.int16)
    return pygame.sndarray.make_sound(onda_stereo)

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
    pantalla.fill(COLOR_FONDO)
    centro = (ANCHO // 2, ALTO // 2)
    radio = 100

    if tipo == 'rojo':
        pygame.draw.circle(pantalla, COLOR_ROJO, centro, radio)
        sonido_rojo.play()
        etiqueta = "Circulo_Rojo_Der"
        
    elif tipo == 'verde':
        rect = pygame.Rect(0, 0, radio*2, radio*2)
        rect.center = centro
        pygame.draw.rect(pantalla, COLOR_VERDE, rect)
        sonido_verde.play()
        etiqueta = "Cuadrado_Verde_Izq"
    
    pygame.display.flip()
    return etiqueta

def main():
    pygame.init()
    pygame.mixer.init(frequency=44100, size=-16, channels=2)
    
    pantalla = pygame.display.set_mode((ANCHO, ALTO))
    pygame.display.set_caption("Protocolo BCI - Estimulacion Pasiva Rapida")
    
    # Audio configurado a 0.5s para empatar perfectamente con el estimulo visual
    sound_rojo = generar_tono(FREQ_ROJO, duracion=0.5)
    sound_verde = generar_tono(FREQ_VERDE, duracion=0.5)

    REGISTRO_DIR.mkdir(exist_ok=True)
    nombre_archivo = REGISTRO_DIR / datetime.now().strftime("Exp_BCI_PasivoRapido_%Y-%m-%d_%H-%M-%S.csv")
    archivo_csv = open(nombre_archivo, mode='w', newline='', encoding='utf-8')
    print(f"--- INICIANDO PRUEBA (Salida: {nombre_archivo}) ---")
    escritor_csv = csv.writer(archivo_csv)
    escritor_csv.writerow(['Timestamp', 'Tiempo_Exp', 'Estimulo', 'Frecuencia_Audio_Hz', 'Duracion_Show', 'ISI_Previo'])
    
    dibujar_texto(pantalla, "Preparate. La prueba comenzara en breve.", tamano=35)
    esperar_tiempo(DURACION_INTRO)

    isi_actual = random.uniform(*RANGO_INICIO_ALEATORIO)
    pantalla.fill(COLOR_FONDO)
    pygame.display.flip()
    esperar_tiempo(isi_actual)

    tiempo_inicio_global = time.time()
    
    while True:
        tiempo_actual = time.time()
        t_transcurrido = tiempo_actual - tiempo_inicio_global
        
        if t_transcurrido >= DURACION_TOTAL_PRUEBA:
            break

        tipo = random.choice(['rojo', 'verde'])
        etiqueta = presentar_estimulo(pantalla, tipo, sound_rojo, sound_verde)
        
        timestamp = datetime.now().strftime("%H:%M:%S.%f")
        freq_audio = FREQ_ROJO if tipo == 'rojo' else FREQ_VERDE
        
        escritor_csv.writerow([
            timestamp,
            f"{t_transcurrido:.3f}",
            etiqueta,
            freq_audio,
            f"{DURACION_ESTIMULO:.3f}",
            f"{isi_actual:.3f}"
        ])
        archivo_csv.flush()

        # El estímulo solo dura 0.5 segundos en pantalla
        esperar_tiempo(DURACION_ESTIMULO)

        # Se limpia la pantalla (fondo blanco) durante el ISI
        pantalla.fill(COLOR_FONDO)
        pygame.display.flip()
        
        isi_siguiente = random.uniform(*RANGO_ISI)
        esperar_tiempo(isi_siguiente)
        
        isi_actual = isi_siguiente

    dibujar_texto(pantalla, "Prueba Finalizada.", tamano=40)
    time.sleep(3)
    archivo_csv.close()
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()