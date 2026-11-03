"""AES-FF1 format-preserving encryption (NIST SP 800-38G), AES-128.

Reference implementation for Device Information Protocol V2. Verified against the
official NIST FF1-AES128 sample vectors. Educational reference, not an audited
production cryptographic library.
"""
import math

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes


def _aes_block(key: bytes, block16: bytes) -> bytes:
    enc = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    return enc.update(block16) + enc.finalize()


def _num(numerals, radix: int) -> int:
    x = 0
    for d in numerals:
        x = x * radix + d
    return x


def _str(x: int, radix: int, m: int):
    out = [0] * m
    for i in range(m - 1, -1, -1):
        out[i] = x % radix
        x //= radix
    return out


def _prf(key: bytes, data: bytes) -> bytes:
    # CBC-MAC with a zero IV (the FF1 PRF).
    y = bytes(16)
    for i in range(0, len(data), 16):
        y = _aes_block(key, bytes(a ^ b for a, b in zip(y, data[i:i + 16])))
    return y


def _y(key, tweak, radix, n, t, u, half, b, d, i) -> int:
    P = (bytes([1, 2, 1]) + radix.to_bytes(3, "big") + bytes([10, u & 0xFF])
         + n.to_bytes(4, "big") + t.to_bytes(4, "big"))
    pad = (-t - b - 1) % 16
    Q = bytes(tweak) + bytes(pad) + bytes([i]) + _num(half, radix).to_bytes(b, "big")
    R = _prf(key, P + Q)
    S = bytearray(R)
    j = 1
    while len(S) < d:
        S += _aes_block(key, bytes(a ^ bb for a, bb in zip(R, j.to_bytes(16, "big"))))
        j += 1
    return int.from_bytes(bytes(S[:d]), "big")


def _params(numerals, tweak, radix):
    n = len(numerals)
    t = len(tweak)
    u = n // 2
    v = n - u
    b = math.ceil(math.ceil(v * math.log2(radix)) / 8)
    d = 4 * math.ceil(b / 4) + 4
    return n, t, u, v, b, d


def ff1_encrypt(key: bytes, tweak: bytes, numerals, radix: int):
    n, t, u, v, b, d = _params(numerals, tweak, radix)
    A, B = list(numerals[:u]), list(numerals[u:])
    for i in range(10):
        y = _y(key, tweak, radix, n, t, u, B, b, d, i)
        m = u if i % 2 == 0 else v
        c = (_num(A, radix) + y) % (radix ** m)
        A, B = B, _str(c, radix, m)
    return A + B


def ff1_decrypt(key: bytes, tweak: bytes, numerals, radix: int):
    n, t, u, v, b, d = _params(numerals, tweak, radix)
    A, B = list(numerals[:u]), list(numerals[u:])
    for i in range(9, -1, -1):
        y = _y(key, tweak, radix, n, t, u, A, b, d, i)
        m = u if i % 2 == 0 else v
        c = (_num(B, radix) - y) % (radix ** m)
        B, A = A, _str(c, radix, m)
    return A + B
