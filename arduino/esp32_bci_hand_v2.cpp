/*
 * esp32_bci_hand_v2.cpp
 * 
 * Control de mano robótica humanoide mediante BCI
 * VERSIÓN 2: 1 servo MG995 (todos los dedos) + 1 servo SG90 (muñeca)
 *
 * HARDWARE:
 *   - ESP32-WROOM-32
 *   - 1× Servo MG995 (dedos 1-5 simultáneamente) en GPIO 23
 *   - 1× Servo SG90 (muñeca pronación/supinación) en GPIO 17
 *   - Conexión: USB Serie COM3 @ 115200 baud
 *
 * PROTOCOLO DE ENTRADA:
 *   Formato: "clase,conf_ded,clase_mun,conf_mun,timestamp\n"
 *   Ejemplo: "1,0.87,1,0.65,1.234\n"
 *
 *   Campos:
 *   - clase:      0 = Mano IZQUIERDA, 1 = Mano DERECHA
 *   - conf_ded:   confianza 0-1 (informativa, no limita el actuado)
 *   - clase_mun:  campo heredado del protocolo v1; se conserva por
 *                 compatibilidad pero la v2.0 decide con 'clase'
 *   - conf_mun:   confianza 0-1 (informativa)
 *   - timestamp:  tiempo en segundos (ignorado)
 *
 * MAPEO CLASE -> SERVO (una clase comanda un servo; el otro a inicial):
 *
 *   clase 1 = MANO DERECHA
 *     MG995 (GPIO 23): PWM 120 -> CIERRA el puño, todos los dedos a la vez
 *     SG90  (GPIO 17): PWM 90  -> muñeca a posición inicial
 *
 *   clase 0 = MANO IZQUIERDA
 *     MG995 (GPIO 23): PWM 30  -> dedos a posición inicial (los retrae el resorte)
 *     SG90  (GPIO 17): PWM 60  -> PRONACIÓN de la muñeca
 *
 *   Nota sobre las etiquetas: el script de entrenamiento MODULO_BATCH asigna
 *   Y=1 a la carpeta "lado derecho" y Y=0 a "lado izquierdo", de modo que
 *   clase 1 SIEMPRE significa mano derecha. Ver MODULO_BATCH...m, linea 154.
 *
 * PARÁMETROS PWM:
 *   - Frecuencia: 50 Hz (estándar para servos)
 *   - Resolución: 10 bits (0-1023)
 *   - Canal LEDC 0 → MG995 (dedos)
 *   - Canal LEDC 1 → SG90 (muñeca)
 *   - Rango útil MG995: 30-120
 *   - Rango útil SG90: 60-90
 *
 * CONEXIÓN SERIAL:
 *   ESP32 RX (GPIO 3) ← USB → MATLAB TX
 *   ESP32 TX (GPIO 1) → USB → MATLAB RX
 *   Velocidad: 115200 baud
 *   Línea final: '\n' (LF)
 *
 * COMPILACIÓN:
 *   1. Arduino IDE
 *   2. Tools → Board → ESP32 → ESP32-WROOM-32
 *   3. Tools → Port → COM3
 *   4. Sketch → Upload
 *
 * TESTING:
 *   Serial Monitor (115200 baud)
 *   Enviar: 1,0.87,1,0.65,1.234
 *   Esperar movimiento de servos
 *
 * AUTHOR: OpenCode BCI System
 * DATE: 2026-10-05
 * VERSION: 2.0
 */

#include <Arduino.h>

// ===== CONFIGURACIÓN DE PINES =====
// Un servo para TODOS los dedos (MG995)
#define SERVO_DEDOS 23

// Un servo para MUÑECA (SG90)
#define SERVO_MUNECA 17

// ===== CONFIGURACIÓN PWM =====
#define PWM_FRECUENCIA 50      // Hz (servo standard)
#define PWM_RESOLUCION 10      // bits (0-1023)

// Cada servo usa su PROPIO canal LEDC. Si ambos comparten un canal,
// el segundo ledcWrite sobrescribe al primero y los dos servos terminan
// recibiendo el mismo PWM (el ultimo escrito).
#define CANAL_DEDOS   0
#define CANAL_MUNECA  1

// PWM del MG995 (dedos 1-5 simultáneos)
#define PWM_DEDOS_ABIERTOS  30   // posición inicial; los retrae el resorte
#define PWM_DEDOS_CERRADOS  120  // cierra el puño

// PWM del SG90 (muñeca)
#define PWM_MUNECA_INICIAL  90   // posición inicial / neutra
#define PWM_MUNECA_PRONACION 60  // pronación

// Etiquetas de clase (ver MODULO_BATCH...m linea 154)
#define CLASE_MANO_DERECHA    1   // Y=1 -> carpeta "lado derecho"
#define CLASE_MANO_IZQUIERDA  0   // Y=0 -> carpeta "lado izquierdo"

// ===== VARIABLES GLOBALES =====
int contador_mensajes = 0;
unsigned long tiempo_ultimo_mensaje = 0;

// ===== SETUP =====
void setup() {
  // Configurar comunicación serial
  Serial.begin(115200);
  delay(500);
  
  // Configurar PWM para servos (un canal por servo)
  ledcSetup(CANAL_DEDOS, PWM_FRECUENCIA, PWM_RESOLUCION);   // Canal 0: dedos
  ledcSetup(CANAL_MUNECA, PWM_FRECUENCIA, PWM_RESOLUCION);  // Canal 1: muñeca
  
  // Asignar cada pin a su canal PWM
  ledcAttachPin(SERVO_DEDOS, CANAL_DEDOS);     // PIN 23 → Canal 0
  ledcAttachPin(SERVO_MUNECA, CANAL_MUNECA);   // PIN 17 → Canal 1
  
  // Posición inicial: dedos abiertos, muñeca neutra
  ledcWrite(CANAL_DEDOS, PWM_DEDOS_ABIERTOS);    // Dedos abiertos
  ledcWrite(CANAL_MUNECA, PWM_MUNECA_INICIAL);   // Muñeca neutra
  
  // Mensaje de bienvenida
  Serial.println("════════════════════════════════════════════════════════════════════════════");
  Serial.println("                   ESP32 BCI - Mano Robótica v2.0");
  Serial.println("════════════════════════════════════════════════════════════════════════════");
  Serial.println("");
  Serial.println("Hardware:");
  Serial.println("  • 1× Servo MG995 (dedos 1-5 simultáneos) en GPIO 23");
  Serial.println("  • 1× Servo SG90 (muñeca pronación) en GPIO 17");
  Serial.println("");
  Serial.println("PWM configurado:");
  Serial.println("  • Frecuencia: 50 Hz");
  Serial.println("  • Resolución: 10 bits (0-1023)");
  Serial.println("  • Canales: 0 (dedos) y 1 (muñeca)");
  Serial.println("");
  Serial.println("Estado inicial:");
  Serial.println("  • Dedos: ABIERTOS (PWM 30)");
  Serial.println("  • Muñeca: NEUTRA (PWM 90)");
  Serial.println("");
  Serial.println("Sistema listo. Esperando datos de MATLAB...");
  Serial.println("════════════════════════════════════════════════════════════════════════════");
  Serial.println("");
}

// ===== LOOP PRINCIPAL =====
void loop() {
  // Esperar datos desde MATLAB
  if (Serial.available() > 0) {
    String linea = Serial.readStringUntil('\n');
    linea.trim();
    
    // Parsear datos: "clase_ded,conf_ded,clase_mun,conf_mun,timestamp"
    int num_campos = contarComas(linea) + 1;
    
    if (num_campos >= 4) {  // Mínimo 4 campos (clase_ded, conf_ded, clase_mun, conf_mun)
      // Extraer campos
      int clase_ded = obtenerCampo(linea, 0).toInt();
      float conf_ded = obtenerCampo(linea, 1).toFloat();
      int clase_mun = obtenerCampo(linea, 2).toInt();
      float conf_mun = obtenerCampo(linea, 3).toFloat();
      float timestamp = obtenerCampo(linea, 4).toFloat();
      
      // Incrementar contador
      contador_mensajes++;
      tiempo_ultimo_mensaje = millis();
      
      // ===== APLICAR LA CLASE RECIBIDA =====
      // Cada clase comanda UN servo; el otro vuelve a su posicion inicial.
      //   clase 1 = Mano DERECHA -> cierra el puno  (MG995 cierra, SG90 neutral)
      //   clase 0 = Mano IZQUIERDA -> gira la muneca (SG90 pronacion, MG995 abierto)
      int pwm_dedos;
      int pwm_muneca;
      
      if (clase_ded == CLASE_MANO_DERECHA) {
        pwm_dedos   = PWM_DEDOS_CERRADOS;    // Mano derecha: cerrar el puño
        pwm_muneca  = PWM_MUNECA_INICIAL;     // La muñeca no participa
      } else {
        pwm_dedos   = PWM_DEDOS_ABIERTOS;     // Los dedos vuelven al inicio
        pwm_muneca  = PWM_MUNECA_PRONACION;   // Mano izquierda: pronar la muñeca
      }
      
      // Aplicar PWM a los servos (cada uno en su propio canal)
      ledcWrite(CANAL_DEDOS, pwm_dedos);      // GPIO 23 - Dedos
      ledcWrite(CANAL_MUNECA, pwm_muneca);    // GPIO 17 - Muñeca
      
      // Log de mensaje recibido
      Serial.print("[");
      Serial.print(contador_mensajes);
      Serial.print("] Recibido: clase=");
      Serial.print(clase_ded);
      Serial.print(" (");
      Serial.print(conf_ded, 2);
      Serial.print(") t=");
      Serial.println(timestamp, 2);
      
      // Log de la accion executada
      if (clase_ded == CLASE_MANO_DERECHA) {
        Serial.println("  Mano DERECHA");
        Serial.println("  -> Dedos: CERRADOS (PWM 120)");
        Serial.println("  -> Muneca: POSICION INICIAL (PWM 90)");
      } else {
        Serial.println("  Mano IZQUIERDA");
        Serial.println("  -> Dedos: ABIERTOS (PWM 30, resorte)");
        Serial.println("  -> Muneca: PRONACION (PWM 60)");
      }
      Serial.println("");
      
    } else {
      Serial.println("ERROR: Formato inválido. Esperado: clase_ded,conf_ded,clase_mun,conf_mun[,timestamp]");
    }
  }
  
  // Verificar timeout (sin datos por 5 segundos)
  if (contador_mensajes > 0 && (millis() - tiempo_ultimo_mensaje) > 5000) {
    Serial.println("⚠️  TIMEOUT: Sin datos por 5 segundos. Sistema en espera...");
    contador_mensajes = 0;  // Reset para no repetir mensaje
  }
  
  delay(10);  // Pequeño delay para no saturar el loop
}

// ===== FUNCIONES AUXILIARES =====

// Contar comas en un string
int contarComas(String str) {
  int count = 0;
  for (int i = 0; i < str.length(); i++) {
    if (str[i] == ',') count++;
  }
  return count;
}

// Obtener campo N de un string separado por comas
String obtenerCampo(String str, int num_campo) {
  int inicio = 0;
  int fin = 0;
  int contador = 0;
  
  for (int i = 0; i <= str.length(); i++) {
    if (i == str.length() || str[i] == ',') {
      if (contador == num_campo) {
        return str.substring(inicio, i);
      }
      inicio = i + 1;
      contador++;
    }
  }
  return "";
}

/*
 * ════════════════════════════════════════════════════════════════════════════
 * MAPEO DE PINES ESP32
 * ════════════════════════════════════════════════════════════════════════════
 * 
 * DEDOS (MG995):
 *   GPIO 23 ← Rojo (5V), Negro (GND), Amarillo (Señal)
 * 
 * MUÑECA (SG90):
 *   GPIO 17 ← Rojo (5V), Negro (GND), Amarillo (Señal)
 * 
 * CONEXIÓN USB:
 *   ESP32 RX (GPIO 3) ← MATLAB TX
 *   ESP32 TX (GPIO 1) → MATLAB RX
 *   Masa común (GND)
 * 
 * FUENTE:
 *   5V @ 2A mínimo (para 1 MG995 + 1 SG90)
 * 
 * ════════════════════════════════════════════════════════════════════════════
 */
