#include "AdminSettings.h"

#include <QtCore/QByteArray>
#include <QtCore/QCryptographicHash>

#ifndef STRATUM_ADMIN_PASSWORD_HASH
#define STRATUM_ADMIN_PASSWORD_HASH "66ca6b95033590484276644c82e336325b818dfc2d9342ed5c2599b7812235cc"
#endif

namespace {
constexpr const char* kAdminPasswordHashHex = STRATUM_ADMIN_PASSWORD_HASH;

QByteArray _sha256Hex(const QString& plaintext)
{
    return QCryptographicHash::hash(plaintext.toUtf8(), QCryptographicHash::Sha256).toHex();
}

bool _constantTimeEqualHex(const QByteArray& a, const QByteArray& b)
{
    if (a.size() != b.size() || a.isEmpty()) {
        return false;
    }
    unsigned char diff = 0;
    for (int i = 0; i < a.size(); ++i) {
        diff |= static_cast<unsigned char>(a[i]) ^ static_cast<unsigned char>(b[i]);
    }
    return diff == 0;
}
}

DECLARE_SETTINGGROUP(Admin, "Admin")
{
}

DECLARE_SETTINGSFACT(AdminSettings, trackerBoxSizePx)
DECLARE_SETTINGSFACT(AdminSettings, c12GimbalMaxSpeed)
DECLARE_SETTINGSFACT(AdminSettings, passwordHashOverride)
DECLARE_SETTINGSFACT(AdminSettings, requiredPx4MajorVersion)
DECLARE_SETTINGSFACT(AdminSettings, requiredPx4MinorVersion)
DECLARE_SETTINGSFACT(AdminSettings, requiredPx4PatchVersion)
DECLARE_SETTINGSFACT(AdminSettings, requiredStratumSchemaMajor)
DECLARE_SETTINGSFACT(AdminSettings, requiredStratumNxMajor)
DECLARE_SETTINGSFACT(AdminSettings, requiredStratumNxMinor)
DECLARE_SETTINGSFACT(AdminSettings, requiredStratumNxPatch)
DECLARE_SETTINGSFACT(AdminSettings, strictCompatibilityGate)

bool AdminSettings::verifyPassword(const QString& plaintext)
{
    if (lockedOut()) {
        return false;
    }

    const QByteArray digestHex = _sha256Hex(plaintext);
    const QString override = passwordHashOverride()->rawValue().toString().trimmed().toLower();
    const QByteArray expectedHex = override.isEmpty()
            ? QByteArray(kAdminPasswordHashHex)
            : override.toUtf8();

    if (!_constantTimeEqualHex(digestHex, expectedHex)) {
        ++_wrongAttempts;
        if (lockedOut()) {
            emit lockedOutChanged();
        }
        return false;
    }

    if (!_unlocked) {
        _unlocked = true;
        emit unlockedChanged();
    }
    return true;
}

bool AdminSettings::changePassword(const QString& currentPlaintext, const QString& newPlaintext)
{
    if (lockedOut()) {
        return false;
    }
    if (newPlaintext.size() < kMinPasswordLength) {
        return false;
    }
    if (newPlaintext == currentPlaintext) {
        return false;
    }

    const QByteArray currentDigestHex = _sha256Hex(currentPlaintext);
    const QString override = passwordHashOverride()->rawValue().toString().trimmed().toLower();
    const QByteArray expectedHex = override.isEmpty()
            ? QByteArray(kAdminPasswordHashHex)
            : override.toUtf8();
    if (!_constantTimeEqualHex(currentDigestHex, expectedHex)) {
        return false;
    }

    const QByteArray newDigestHex = _sha256Hex(newPlaintext);
    passwordHashOverride()->setRawValue(QString::fromUtf8(newDigestHex));
    return true;
}

void AdminSettings::relock()
{
    if (_unlocked) {
        _unlocked = false;
        emit unlockedChanged();
    }
}
