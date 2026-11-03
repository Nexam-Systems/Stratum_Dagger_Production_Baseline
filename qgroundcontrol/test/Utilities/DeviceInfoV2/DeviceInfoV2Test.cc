#include "DeviceInfoV2Test.h"

#include "AES128.h"
#include "DeviceInfoV2.h"
#include "FF1.h"

#include <array>
#include <vector>

using namespace DeviceInfoV2;

namespace {

// Public NIST demonstration key — NEVER deploy.
const QByteArray kDemoKey = QByteArray::fromHex("2B7E151628AED2A6ABF7158809CF4F3C");

std::vector<uint8_t> keyBytes()
{
    return std::vector<uint8_t>(kDemoKey.constData(), kDemoKey.constData() + 16);
}

QString digitsToString(const std::vector<uint8_t>& numerals)
{
    QString out;
    for (const uint8_t d : numerals) {
        out.append(QChar('0' + d));
    }
    return out;
}

} // namespace

void DeviceInfoV2Test::_ff1NistSample1_test()
{
    const std::vector<uint8_t> input = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    const auto out = ff1Encrypt(keyBytes().data(), nullptr, 0, input, 10);
    QCOMPARE(digitsToString(out), QStringLiteral("2433477484"));
}

void DeviceInfoV2Test::_ff1NistSample2_test()
{
    const QByteArray tweak = QByteArray::fromHex("39383736353433323130"); // "9876543210"
    const std::vector<uint8_t> input = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9};
    const auto out = ff1Encrypt(keyBytes().data(),
                                reinterpret_cast<const uint8_t*>(tweak.constData()),
                                static_cast<size_t>(tweak.size()), input, 10);
    QCOMPARE(digitsToString(out), QStringLiteral("6124200773"));
}

void DeviceInfoV2Test::_ff1InverseRoundtrip_test()
{
    const uint8_t tweak[] = {0x44, 0x45, 0x56, 0x49, 0x4E, 0x46, 0x4F, 0x2D, 0x56, 0x32};
    const auto key = keyBytes();
    quint64 seed = 0x1234567;
    for (int iter = 0; iter < 500; ++iter) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        std::vector<uint8_t> x(64);
        for (int i = 0; i < 64; ++i) {
            x[static_cast<size_t>(i)] = static_cast<uint8_t>((seed >> (i % 63)) & 1);
        }
        const auto ct = ff1Encrypt(key.data(), tweak, sizeof(tweak), x, 2);
        const auto pt = ff1Decrypt(key.data(), tweak, sizeof(tweak), ct, 2);
        QCOMPARE(pt, x);
    }
}

void DeviceInfoV2Test::_referencePacketA_test()
{
    DeviceInfo info;
    info.handshake = QStringLiteral("123456");
    info.dataIp = QStringLiteral("192.168.10.50");
    info.port = 14550;
    info.cameraIp = QStringLiteral("192.168.11.50");
    const QByteArray frame = encode(info, kDemoKey);
    QCOMPARE(frame.toHex().toUpper(), QByteArray("C3065B91380C8132"));
}

void DeviceInfoV2Test::_referencePacketB_test()
{
    DeviceInfo info;
    info.handshake = QStringLiteral("123456");
    info.dataIp = QStringLiteral("192.168.101.150");
    info.port = 14550;
    info.cameraIp = QStringLiteral("192.168.111.150");
    const QByteArray frame = encode(info, kDemoKey);
    QCOMPARE(frame.toHex().toUpper(), QByteArray("203365ABDE4900FC"));
}

void DeviceInfoV2Test::_decodeReferencePackets_test()
{
    DeviceInfo a;
    QVERIFY(decode(QByteArray::fromHex("C3065B91380C8132"), kDemoKey, a));
    QCOMPARE(a.handshake, QStringLiteral("123456"));
    QCOMPARE(a.dataIp, QStringLiteral("192.168.10.50"));
    QCOMPARE(a.cameraIp, QStringLiteral("192.168.11.50"));
    QCOMPARE(a.port, static_cast<quint16>(14550));

    DeviceInfo b;
    QVERIFY(decode(QByteArray::fromHex("203365ABDE4900FC"), kDemoKey, b));
    QCOMPARE(b.handshake, QStringLiteral("123456"));
    QCOMPARE(b.dataIp, QStringLiteral("192.168.101.150"));
    QCOMPARE(b.cameraIp, QStringLiteral("192.168.111.150"));
    QCOMPARE(b.port, static_cast<quint16>(14550));
}

void DeviceInfoV2Test::_boundaries_test()
{
    struct Case {
        const char* hs;
        const char* dip;
        quint16 port;
        const char* cip;
    };
    const Case cases[] = {
        {"000000", "192.168.0.0", 10000, "192.168.0.0"},
        {"999999", "192.168.255.255", 19999, "192.168.255.255"},
        {"000007", "192.168.255.0", 10000, "192.168.0.0"},
    };
    for (const Case& cse : cases) {
        DeviceInfo in;
        in.handshake = QString::fromLatin1(cse.hs);
        in.dataIp = QString::fromLatin1(cse.dip);
        in.port = cse.port;
        in.cameraIp = QString::fromLatin1(cse.cip);
        const QByteArray frame = encode(in, kDemoKey);
        QCOMPARE(frame.size(), 8);
        DeviceInfo out;
        QVERIFY(decode(frame, kDemoKey, out));
        QCOMPARE(out.handshake, in.handshake);
        QCOMPARE(out.dataIp, in.dataIp);
        QCOMPARE(out.cameraIp, in.cameraIp);
        QCOMPARE(out.port, in.port);
    }
}

void DeviceInfoV2Test::_leadingZeroHandshakePreserved_test()
{
    DeviceInfo in;
    in.handshake = QStringLiteral("000042");
    in.dataIp = QStringLiteral("192.168.1.9");
    in.port = 12000;
    in.cameraIp = QStringLiteral("192.168.2.9");
    DeviceInfo out;
    QVERIFY(decode(encode(in, kDemoKey), kDemoKey, out));
    QCOMPARE(out.handshake, QStringLiteral("000042"));
}

void DeviceInfoV2Test::_randomRoundtrips_test()
{
    quint64 seed = 7;
    for (int iter = 0; iter < 300; ++iter) {
        seed = seed * 6364136223846793005ULL + 1442695040888963407ULL;
        const quint32 hs = static_cast<quint32>(seed % 1000000);
        const int l = static_cast<int>((seed >> 20) % 256);
        const int dOct = static_cast<int>((seed >> 28) % 256);
        const int cOct = static_cast<int>((seed >> 36) % 256);
        const quint16 port = static_cast<quint16>(10000 + ((seed >> 44) % 10000));

        DeviceInfo in;
        in.handshake = QStringLiteral("%1").arg(hs, 6, 10, QLatin1Char('0'));
        in.dataIp = QStringLiteral("192.168.%1.%2").arg(dOct).arg(l);
        in.cameraIp = QStringLiteral("192.168.%1.%2").arg(cOct).arg(l);
        in.port = port;

        const QByteArray frame = encode(in, kDemoKey);
        QCOMPARE(frame.size(), 8);
        DeviceInfo out;
        QVERIFY(decode(frame, kDemoKey, out));
        QCOMPARE(out.handshake, in.handshake);
        QCOMPARE(out.dataIp, in.dataIp);
        QCOMPARE(out.cameraIp, in.cameraIp);
        QCOMPARE(out.port, in.port);
    }
}

void DeviceInfoV2Test::_invalidInputsRejected_test()
{
    const auto bad = [](const char* hs, const char* dip, quint16 port, const char* cip) {
        DeviceInfo in;
        in.handshake = QString::fromLatin1(hs);
        in.dataIp = QString::fromLatin1(dip);
        in.port = port;
        in.cameraIp = QString::fromLatin1(cip);
        return encode(in, kDemoKey).isEmpty();
    };
    QVERIFY(bad("12345", "192.168.1.1", 14550, "192.168.2.1"));     // 5-digit handshake
    QVERIFY(bad("123456", "10.0.0.1", 14550, "192.168.2.1"));       // wrong prefix
    QVERIFY(bad("123456", "192.168.1.5", 14550, "192.168.2.6"));    // mismatched 4th octet
    QVERIFY(bad("123456", "192.168.1.1", 9999, "192.168.2.1"));     // port too low
    QVERIFY(bad("123456", "192.168.1.1", 20000, "192.168.2.1"));    // port too high
    QVERIFY(bad("123456", "192.168.010.1", 14550, "192.168.2.1"));  // leading-zero octet
}

void DeviceInfoV2Test::_badFrameLengthRejected_test()
{
    DeviceInfo out;
    QVERIFY(!decode(QByteArray(7, '\0'), kDemoKey, out));
}

void DeviceInfoV2Test::_crcMismatchRejected_test()
{
    QByteArray frame = QByteArray::fromHex("203365ABDE4900FC");
    frame[0] = static_cast<char>(frame.at(0) ^ 0xFF);
    DeviceInfo out;
    QVERIFY(!decode(frame, kDemoKey, out));
}

void DeviceInfoV2Test::_crc6DetectsSingleBitErrors_test()
{
    const quint64 m58 = (static_cast<quint64>(123456) << 38) | (static_cast<quint64>(101) << 30)
                       | (static_cast<quint64>(111) << 22) | (static_cast<quint64>(150) << 14)
                       | static_cast<quint64>(4550);
    const quint8 base = crc6(m58);
    for (int i = 0; i < 58; ++i) {
        QVERIFY(crc6(m58 ^ (static_cast<quint64>(1) << i)) != base);
    }
}

UT_REGISTER_TEST_LIGHTWEIGHT(DeviceInfoV2Test, TestLabel::Unit, TestLabel::Utilities)
