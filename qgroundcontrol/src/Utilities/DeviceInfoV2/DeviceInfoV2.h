#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QString>

#include <cstdint>

// Device Information Protocol V2 (DIP V2) codec.
//
// Packs {6-digit handshake, data-link IPv4+port, camera IPv4} into a 58-bit word,
// appends a CRC-6, and AES-FF1-encrypts the resulting 64-bit word into exactly
// 8 bytes. This mirrors the verified Python reference
// (scripts/device_info_v2/) bit-for-bit; both sides must agree for interop.

namespace DeviceInfoV2 {

struct DeviceInfo {
    QString handshake;  // exactly 6 decimal digits (leading zeros significant)
    QString dataIp;     // 192.168.D.L
    QString cameraIp;   // 192.168.C.L (shares the 4th octet L with dataIp)
    quint16 port = 0;   // 10000..19999
};

// CRC-6, poly x^6+x+1 (0x03), init 0, no reflection, MSB-first over the low 58 bits.
quint8 crc6(quint64 m58);

// Encodes info into the 8-byte encrypted frame. Returns an 8-byte array on
// success, or an empty QByteArray on invalid input (optional reason in error).
QByteArray encode(const DeviceInfo& info, const QByteArray& aesKey, QString* error = nullptr);

// Decrypts/validates an 8-byte frame. Returns true and fills out on success;
// returns false (optional reason in error) on bad length/key/CRC/range.
bool decode(const QByteArray& frame, const QByteArray& aesKey, DeviceInfo& out, QString* error = nullptr);

} // namespace DeviceInfoV2
