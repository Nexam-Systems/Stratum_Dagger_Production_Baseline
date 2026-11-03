"""Conformance tests for the Device Information Protocol V2 reference codec.

Covers the issue's verification matrix: NIST FF1 vectors, both reference packets,
boundary values, invalid inputs, CRC single-bit detection, and round-trips.

Run from the scripts/ directory:
    python -m unittest device_info_v2.tests.test_device_info_v2 -v
"""
import random
import unittest

from device_info_v2 import DeviceInfoError, crc6, decode, encode
from device_info_v2.ff1 import ff1_decrypt, ff1_encrypt

# Public NIST demonstration key — NEVER deploy.
KEY = bytes.fromhex("2B7E151628AED2A6ABF7158809CF4F3C")


class FF1Test(unittest.TestCase):
    def test_nist_sample1(self):
        out = ff1_encrypt(KEY, b"", list(range(10)), 10)
        self.assertEqual("".join(map(str, out)), "2433477484")

    def test_nist_sample2(self):
        tweak = bytes.fromhex("39383736353433323130")  # "9876543210"
        out = ff1_encrypt(KEY, tweak, list(range(10)), 10)
        self.assertEqual("".join(map(str, out)), "6124200773")

    def test_inverse_roundtrip(self):
        rnd = random.Random(1)
        for _ in range(1000):
            n = rnd.choice([10, 16, 20, 64])
            radix = 2 if n == 64 else 10
            x = [rnd.randrange(radix) for _ in range(n)]
            ct = ff1_encrypt(KEY, b"DEVINFO-V2", x, radix)
            self.assertEqual(ff1_decrypt(KEY, b"DEVINFO-V2", ct, radix), x)


class DeviceInfoV2Test(unittest.TestCase):
    def test_reference_packet_b(self):
        frame = encode("123456", "192.168.101.150", 14550, "192.168.111.150", KEY)
        self.assertEqual(frame.hex().upper(), "203365ABDE4900FC")

    def test_reference_packet_a(self):
        frame = encode("123456", "192.168.10.50", 14550, "192.168.11.50", KEY)
        self.assertEqual(frame.hex().upper(), "C3065B91380C8132")

    def test_decode_reference_packets(self):
        self.assertEqual(
            decode(bytes.fromhex("203365ABDE4900FC"), KEY),
            {"handshake": "123456", "data_ip": "192.168.101.150",
             "camera_ip": "192.168.111.150", "port": 14550})
        self.assertEqual(
            decode(bytes.fromhex("C3065B91380C8132"), KEY),
            {"handshake": "123456", "data_ip": "192.168.10.50",
             "camera_ip": "192.168.11.50", "port": 14550})

    def test_boundaries(self):
        cases = [
            ("000000", "192.168.0.0", 10000, "192.168.0.0"),
            ("999999", "192.168.255.255", 19999, "192.168.255.255"),
            ("000007", "192.168.255.0", 10000, "192.168.0.0"),
        ]
        for hs, dip, port, cip in cases:
            got = decode(encode(hs, dip, port, cip, KEY), KEY)
            self.assertEqual(got, {"handshake": hs, "data_ip": dip,
                                   "camera_ip": cip, "port": port})

    def test_leading_zero_handshake_preserved(self):
        self.assertEqual(decode(encode("000042", "192.168.1.9", 12000, "192.168.2.9", KEY), KEY)["handshake"], "000042")

    def test_random_roundtrips(self):
        rnd = random.Random(7)
        for _ in range(500):
            hs = "%06d" % rnd.randrange(1000000)
            L = rnd.randrange(256)
            dip = "192.168.%d.%d" % (rnd.randrange(256), L)
            cip = "192.168.%d.%d" % (rnd.randrange(256), L)
            port = rnd.randrange(10000, 20000)
            frame = encode(hs, dip, port, cip, KEY)
            self.assertEqual(len(frame), 8)
            self.assertEqual(decode(frame, KEY),
                             {"handshake": hs, "data_ip": dip, "camera_ip": cip, "port": port})

    def test_invalid_inputs_rejected(self):
        with self.assertRaises(DeviceInfoError):
            encode("12345", "192.168.1.1", 14550, "192.168.2.1", KEY)       # 5-digit handshake
        with self.assertRaises(DeviceInfoError):
            encode("123456", "10.0.0.1", 14550, "192.168.2.1", KEY)          # wrong prefix
        with self.assertRaises(DeviceInfoError):
            encode("123456", "192.168.1.5", 14550, "192.168.2.6", KEY)       # mismatched 4th octet
        with self.assertRaises(DeviceInfoError):
            encode("123456", "192.168.1.1", 9999, "192.168.2.1", KEY)        # port too low
        with self.assertRaises(DeviceInfoError):
            encode("123456", "192.168.1.1", 20000, "192.168.2.1", KEY)       # port too high
        with self.assertRaises(DeviceInfoError):
            encode("123456", "192.168.010.1", 14550, "192.168.2.1", KEY)     # leading-zero octet

    def test_bad_frame_length_rejected(self):
        with self.assertRaises(DeviceInfoError):
            decode(b"\x00" * 7, KEY)

    def test_crc_mismatch_rejected(self):
        frame = bytearray(encode("123456", "192.168.101.150", 14550, "192.168.111.150", KEY))
        frame[0] ^= 0xFF  # corrupt ciphertext
        with self.assertRaises(DeviceInfoError):
            decode(bytes(frame), KEY)

    def test_crc6_detects_all_single_bit_errors(self):
        m58 = (123456 << 38) | (101 << 30) | (111 << 22) | (150 << 14) | 4550
        base = crc6(m58)
        for i in range(58):
            self.assertNotEqual(crc6(m58 ^ (1 << i)), base)


if __name__ == "__main__":
    unittest.main()
