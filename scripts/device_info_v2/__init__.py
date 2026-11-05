"""Device Information Protocol V2 — reference codec (AES-FF1 + CRC-6)."""
from .device_info_v2 import DeviceInfoError, crc6, decode, encode

__all__ = ["encode", "decode", "crc6", "DeviceInfoError"]
