"""Device Information Protocol V2 (DIP V2) reference codec.

Packs {6-digit handshake, data-link IPv4+port, camera IPv4} into a 58-bit word,
appends a CRC-6, and AES-FF1-encrypts the 64-bit frame into exactly 8 bytes.
Encrypted-only: there is no plaintext fallback. The internal 64-bit word is an
implementation intermediate and must never be transmitted in clear.

This is the interoperability reference for the STRATUM C++ codec and the PX4
firmware. Both must produce identical 8-byte ciphertext for the same key/tweak.
"""
from .ff1 import ff1_decrypt, ff1_encrypt

TWEAK = b"DEVINFO-V2"


class DeviceInfoError(ValueError):
    pass


def crc6(m58: int) -> int:
    """CRC-6, poly x^6+x+1 (0x03), init 0, no reflection, MSB-first over 58 bits."""
    crc = 0
    for i in range(57, -1, -1):
        fb = ((crc >> 5) & 1) ^ ((m58 >> i) & 1)
        crc = (crc << 1) & 0x3F
        if fb:
            crc ^= 0x03
    return crc


def _bits(value: int, width: int):
    return [(value >> (width - 1 - i)) & 1 for i in range(width)]


def _from_bits(bits) -> int:
    v = 0
    for b in bits:
        v = (v << 1) | b
    return v


def _parse_ipv4(ip: str):
    parts = ip.split(".")
    if len(parts) != 4:
        raise DeviceInfoError(f"invalid IPv4: {ip}")
    octets = []
    for p in parts:
        if not p.isdigit() or (len(p) > 1 and p[0] == "0"):  # reject leading-zero octets
            raise DeviceInfoError(f"invalid IPv4 octet: {p!r}")
        v = int(p)
        if not 0 <= v <= 255:
            raise DeviceInfoError(f"IPv4 octet out of range: {v}")
        octets.append(v)
    return octets


def encode(handshake: str, data_ip: str, port: int, camera_ip: str, aes_key: bytes) -> bytes:
    """Return the 8-byte encrypted V2 frame."""
    if not (isinstance(handshake, str) and len(handshake) == 6 and handshake.isdigit()):
        raise DeviceInfoError("handshake must be exactly 6 digits")
    if len(aes_key) != 16:
        raise DeviceInfoError("AES key must be 16 bytes")
    if not 10000 <= port <= 19999:
        raise DeviceInfoError("port must be 10000..19999")

    d = _parse_ipv4(data_ip)
    c = _parse_ipv4(camera_ip)
    if d[0:2] != [192, 168] or c[0:2] != [192, 168]:
        raise DeviceInfoError("both IPs must start with 192.168")
    if d[3] != c[3]:
        raise DeviceInfoError("data-link and camera IPs must share the 4th octet")

    H, D, C, L, Q = int(handshake), d[2], c[2], d[3], port - 10000
    m58 = (H << 38) | (D << 30) | (C << 22) | (L << 14) | Q
    w64 = (m58 << 6) | crc6(m58)
    cipher_bits = ff1_encrypt(aes_key, TWEAK, _bits(w64, 64), 2)
    frame = _from_bits(cipher_bits).to_bytes(8, "big")
    assert len(frame) == 8
    return frame


def decode(frame8: bytes, aes_key: bytes) -> dict:
    """Decrypt/validate an 8-byte frame and reconstruct the device info."""
    if len(frame8) != 8:
        raise DeviceInfoError("frame must be exactly 8 bytes")
    if len(aes_key) != 16:
        raise DeviceInfoError("AES key must be 16 bytes")

    bits = [(frame8[i // 8] >> (7 - i % 8)) & 1 for i in range(64)]
    w64 = _from_bits(ff1_decrypt(aes_key, TWEAK, bits, 2))
    m58, received_crc = w64 >> 6, w64 & 0x3F
    if crc6(m58) != received_crc:
        raise DeviceInfoError("CRC mismatch")

    H = (w64 >> 44) & 0xFFFFF
    D = (w64 >> 36) & 0xFF
    C = (w64 >> 28) & 0xFF
    L = (w64 >> 20) & 0xFF
    Q = (w64 >> 6) & 0x3FFF
    if H > 999999 or Q > 9999:
        raise DeviceInfoError("decoded value out of range")

    return {
        "handshake": "%06d" % H,
        "data_ip": "192.168.%d.%d" % (D, L),
        "camera_ip": "192.168.%d.%d" % (C, L),
        "port": Q + 10000,
    }
