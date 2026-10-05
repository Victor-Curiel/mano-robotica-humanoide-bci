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
 *   Formato: "clase_ded,conf_ded,clase_mun,conf_mun,timestamp\n"
 *   Ejemplo: "1,0.87,1,0.65,1.234\n"
 *
 *   Campos:
 *   - clase_ded: 0=dedos abiertos, 1=dedos cerrados
 *   - conf_ded: confianza 0-1 (ignorada en v2.0)
 *   - clase_mun: 0=muñeca posición inicial, 1=muñeca pronación
 *   - conf_mun: confianza 0-1 (ignorada en v2.0)
 *   - timestamp: tiempo en segundos (ignorado)
 *
 * MAPEO SERVO:
 *   DEDOS (MG995 - rango 0-180°) en GPIO 23:
 *   - clase_ded=0: PWM ~30 (0°, dedos ABIERTOS, resorte retrae)
 *   - clase_ded=1: PWM ~120 (180°, dedos CERRADOS, cierra puño)
 *
 *   MUÑECA (SG90 - rango 0-180°) en GPIO 17:
 *   - clase_mun=0: PWM ~90 (90°, posición INICIAL/NEUTRA)
 *   - clase_mun=1: PWM ~60 (60°, PRONACIÓN/giro izquierda)
 *
 * PARÁMETROS PWM:
 *   - Frecuencia: 50 Hz (estándar para servos)
 *   - Resolución: 10 bits (0-1023)
 *   - Rango útil MG995: 30-120
 *   - Rango útil SG90: 60-120
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

// PWM values para MG995 (dedos - todos juntos)
#define PWM_DEDOS_ABIERTOS  30   // ~0° (estado inicial, resorte abre)
#define PWM_DEDOS_CERRADOS  120  // ~180° (cierra puño)

// PWM values para SG90 (muñeca)
#define PWM_MUNECA_INICIAL  90   // ~90° (posición inicial/neutra)
#define PWM_MUNECA_PRONACION 60  // ~60° (giro izquierda/pronación)

// ===== VARIABLES GLOBALES =====
int contador_mensajes = 0;
unsigned long tiempo_ultimo_mensaje = 0;

// ===== SETUP =====
void setup() {
  // Configurar comunicación serial
  Serial.begin(115200);
  delay(500);
  
  // Configurar PWM para servos
  ledcSetup(0, PWM_FRECUENCIA, PWM_RESOLUCION);  // Canal 0, 50 Hz, 10 bits
  
  // Asignar pines al canal PWM
  ledcAttachPin(SERVO_DEDOS, 0);    // PIN 23 → Canal 0
  ledcAttachPin(SERVO_MUNECA, 0);   // PIN 17 → Canal 0 (mismo canal, sincronizado)
  
  // Posición inicial: dedos abiertos, muñeca neutra
  ledcWrite(0, PWM_DEDOS_ABIERTOS);   // Dedos abiertos
  ledcWrite(0, PWM_MUNECA_INICIAL);   // Muñeca neutra
  
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
  Serial.println("  • Canal: 0 (ambos pines)");
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
      
      // ===== CONTROLAR DEDOS (MG995) =====
      int pwm_dedos;
      if (clase_ded == 1) {
        pwm_dedos = PWM_DEDOS_CERRADOS;  // Cerrar puño
      } else {
        pwm_dedos = PWM_DEDOS_ABIERTOS;  // Abrir (resorte)
      }
      
      // ===== CONTROLAR MUÑECA (SG90) =====
      int pwm_muneca;
      if (clase_mun == 1) {
        pwm_muneca = PWM_MUNECA_PRONACION;  // Pronación (giro izquierda)
      } else {
        pwm_muneca = PWM_MUNECA_INICIAL;    // Posición inicial
      }
      
      // Aplicar PWM a los servos
      ledcWrite(0, pwm_dedos);    // GPIO 23 - Dedos
      delayMicroseconds(100);     // Pequeño delay para estabilidad
      ledcWrite(0, pwm_muneca);   // GPIO 17 - Muñeca
      
      // Log de mensaje recibido
      Serial.print("[");
      Serial.print(contador_mensajes);
      Serial.print("] Recibido: ded=");
      Serial.print(clase_ded);
      Serial.print(" (");
      Serial.print(conf_ded, 2);
      Serial.print("), mun=");
      Serial.print(clase_mun);
      Serial.print(" (");
      Serial.print(conf_mun, 2);
      Serial.print("), t=");
      Serial.println(timestamp, 2);
      
      // Log de acción tomada
      Serial.print("  → Dedos: ");
      if (clase_ded == 1) {
        Serial.println("CERRADOS (PWM 120)");
      } else {
        Serial.println("ABIERTOS (PWM 30)");
      }
      
      Serial.print("  → Muñeca: ");
      if (clase_mun == 1) {
        Serial.println("PRONACIÓN (PWM 60)");
      } else {
        Serial.println("POSICIÓN INICIAL (PWM 90)");
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
