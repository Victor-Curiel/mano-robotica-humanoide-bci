"""Interfaz serial con el ESP32 (protocolo: 'clase,conf,clase,conf,timestamp\\n').

El firmware v2.0 solo decide con el primer campo; los campos de muneca se
mantienen por compatibilidad, asi que se envia la misma clase en ambos pares.
"""
from __future__ import annotations

from . import config as cfg


def format_message(clase: int, conf: float, timestamp: float) -> str:
    return f"{int(clase)},{conf:.2f},{int(clase)},{conf:.2f},{timestamp:.3f}\n"


class ESP32Interface:
    def __init__(self, port: str = cfg.ESP32_PORT, baudrate: int = cfg.ESP32_BAUD, serial_factory=None):
        self.port, self.baudrate = port, baudrate
        self._factory = serial_factory
        self.ser = None

    def open(self) -> None:
        import time

        factory = self._factory
        if factory is None:
            import serial
            factory = serial.Serial
        self.ser = factory(self.port, self.baudrate, timeout=1)
        if self._factory is None:
            time.sleep(2)  # el ESP32 se reinicia al abrir el puerto

    def send(self, clase: int, conf: float, timestamp: float) -> str:
        if self.ser is None:
            raise RuntimeError("puerto no abierto")
        msg = format_message(clase, conf, timestamp)
        self.ser.write(msg.encode("utf-8"))
        return msg

    def read_response(self) -> str | None:
        if self.ser is not None and self.ser.in_waiting > 0:
            return self.ser.readline().decode("utf-8", errors="ignore").strip()
        return None

    def close(self) -> None:
        if self.ser is not None:
            self.ser.close()
            self.ser = None

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, *exc):
        self.close()
