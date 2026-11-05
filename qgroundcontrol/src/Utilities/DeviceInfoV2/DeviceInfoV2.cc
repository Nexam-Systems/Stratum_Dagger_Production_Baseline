#include "DeviceInfoV2.h"

#include "FF1.h"

#include <QtCore/QStringList>

#include <array>
#include <vector>

namespace {

// ASCII "DEVINFO-V2".
const uint8_t kTweak[] = {0x44, 0x45, 0x56, 0x49, 0x4E, 0x46, 0x4F, 0x2D, 0x56, 0x32};
constexpr size_t kTweakLen = sizeof(kTweak);

bool setError(QString* error, const QString& message)
{
    if (error) {
        *error = message;
    }
    return false;
}

// Parses a dotted IPv4 string, rejecting leading-zero octets. Returns false on failure.
bool parseIPv4(const QString& ip, std::array<int, 4>& octets, QString* error)
{
    const QStringList parts = ip.split(QLatin1Char('.'));
    if (parts.size() != 4) {
        return setError(error, QStringLiteral("invalid IPv4: %1").arg(ip));
    }
    for (int i = 0; i < 4; ++i) {
        const QString& part = parts.at(i);
        if (part.isEmpty() || part.size() > 3) {
            return setError(error, QStringLiteral("invalid IPv4 octet: %1").arg(part));
        }
        for (const QChar c : part) {
            if (!c.isDigit()) {
                return setError(error, QStringLiteral("invalid IPv4 octet: %1").arg(part));
            }
        }
        if (part.size() > 1 && part.at(0) == QLatin1Char('0')) {
            return setError(error, QStringLiteral("leading-zero IPv4 octet: %1").arg(part));
        }
        const int value = part.toInt();
        if (value < 0 || value > 255) {
            return setError(error, QStringLiteral("IPv4 octet out of range: %1").arg(value));
        }
        octets[static_cast<size_t>(i)] = value;
    }
    return true;
}

std::vector<uint8_t> toBits(quint64 value, int width)
{
    std::vector<uint8_t> bits(static_cast<size_t>(width));
    for (int i = 0; i < width; ++i) {
        bits[static_cast<size_t>(i)] = static_cast<uint8_t>((value >> (width - 1 - i)) & 1);
    }
    return bits;
}

quint64 fromBits(const std::vector<uint8_t>& bits)
{
    quint64 value = 0;
    for (const uint8_t bit : bits) {
        value = (value << 1) | bit;
    }
    return value;
}

} // namespace

namespace DeviceInfoV2 {

quint8 crc6(quint64 m58)
{
    quint8 crc = 0;
    for (int i = 57; i >= 0; --i) {
        const quint8 fb = static_cast<quint8>(((crc >> 5) & 1) ^ ((m58 >> i) & 1));
        crc = static_cast<quint8>((crc << 1) & 0x3F);
        if (fb) {
            crc ^= 0x03;
        }
    }
    return crc;
}

QByteArray encode(const DeviceInfo& info, const QByteArray& aesKey, QString* error)
{
    const auto fail = [&](const QString& msg) -> QByteArray {
        setError(error, msg);
        return QByteArray();
    };

    if (info.handshake.size() != 6) {
        return fail(QStringLiteral("handshake must be exactly 6 digits"));
    }
    for (const QChar c : info.handshake) {
        if (!c.isDigit()) {
            return fail(QStringLiteral("handshake must be exactly 6 digits"));
        }
    }
    if (aesKey.size() != 16) {
        return fail(QStringLiteral("AES key must be 16 bytes"));
    }
    if (info.port < 10000 || info.port > 19999) {
        return fail(QStringLiteral("port must be 10000..19999"));
    }

    std::array<int, 4> d{};
    std::array<int, 4> c{};
    if (!parseIPv4(info.dataIp, d, error) || !parseIPv4(info.cameraIp, c, error)) {
        return QByteArray();
    }
    if (d[0] != 192 || d[1] != 168 || c[0] != 192 || c[1] != 168) {
        return fail(QStringLiteral("both IPs must start with 192.168"));
    }
    if (d[3] != c[3]) {
        return fail(QStringLiteral("data-link and camera IPs must share the 4th octet"));
    }

    const quint64 h = info.handshake.toULongLong();
    const quint64 m58 = (h << 38) | (static_cast<quint64>(d[2]) << 30)
                        | (static_cast<quint64>(c[2]) << 22) | (static_cast<quint64>(d[3]) << 14)
                        | static_cast<quint64>(info.port - 10000);
    const quint64 w64 = (m58 << 6) | crc6(m58);

    const std::vector<uint8_t> key(aesKey.constData(), aesKey.constData() + 16);
    const std::vector<uint8_t> cipherBits = ff1Encrypt(key.data(), kTweak, kTweakLen, toBits(w64, 64), 2);
    const quint64 frameValue = fromBits(cipherBits);

    QByteArray frame(8, Qt::Uninitialized);
    for (int i = 0; i < 8; ++i) {
        frame[i] = static_cast<char>((frameValue >> (8 * (7 - i))) & 0xFF);
    }
    return frame;
}

bool decode(const QByteArray& frame, const QByteArray& aesKey, DeviceInfo& out, QString* error)
{
    if (frame.size() != 8) {
        return setError(error, QStringLiteral("frame must be exactly 8 bytes"));
    }
    if (aesKey.size() != 16) {
        return setError(error, QStringLiteral("AES key must be 16 bytes"));
    }

    std::vector<uint8_t> bits(64);
    for (int i = 0; i < 64; ++i) {
        const uint8_t byte = static_cast<uint8_t>(frame.at(i / 8));
        bits[static_cast<size_t>(i)] = static_cast<uint8_t>((byte >> (7 - (i % 8))) & 1);
    }

    const std::vector<uint8_t> key(aesKey.constData(), aesKey.constData() + 16);
    const quint64 w64 = fromBits(ff1Decrypt(key.data(), kTweak, kTweakLen, bits, 2));

    const quint64 m58 = w64 >> 6;
    const quint8 receivedCrc = static_cast<quint8>(w64 & 0x3F);
    if (crc6(m58) != receivedCrc) {
        return setError(error, QStringLiteral("CRC mismatch"));
    }

    const quint64 h = (w64 >> 44) & 0xFFFFF;
    const quint64 dOctet = (w64 >> 36) & 0xFF;
    const quint64 cOctet = (w64 >> 28) & 0xFF;
    const quint64 lOctet = (w64 >> 20) & 0xFF;
    const quint64 q = (w64 >> 6) & 0x3FFF;
    if (h > 999999 || q > 9999) {
        return setError(error, QStringLiteral("decoded value out of range"));
    }

    out.handshake = QStringLiteral("%1").arg(h, 6, 10, QLatin1Char('0'));
    out.dataIp = QStringLiteral("192.168.%1.%2").arg(dOctet).arg(lOctet);
    out.cameraIp = QStringLiteral("192.168.%1.%2").arg(cOctet).arg(lOctet);
    out.port = static_cast<quint16>(q + 10000);
    return true;
}

} // namespace DeviceInfoV2
