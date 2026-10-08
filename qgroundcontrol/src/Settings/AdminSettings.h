#pragma once

#include <QtCore/QString>
#include <QtQmlIntegration/QtQmlIntegration>

#include "SettingsGroup.h"

class AdminSettings : public SettingsGroup
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")
    Q_PROPERTY(bool unlocked READ unlocked NOTIFY unlockedChanged)
    Q_PROPERTY(bool lockedOut READ lockedOut NOTIFY lockedOutChanged)
public:
    AdminSettings(QObject* parent = nullptr);

    DEFINE_SETTING_NAME_GROUP()

    DEFINE_SETTINGFACT(requiredPx4MajorVersion)
    DEFINE_SETTINGFACT(requiredPx4MinorVersion)
    DEFINE_SETTINGFACT(requiredPx4PatchVersion)
    DEFINE_SETTINGFACT(strictCompatibilityGate)
    DEFINE_SETTINGFACT(trackerBoxSizePx)
    DEFINE_SETTINGFACT(c12GimbalMaxSpeed)
    DEFINE_SETTINGFACT(passwordHashOverride)

    bool unlocked() const { return _unlocked; }
    bool lockedOut() const { return _wrongAttempts >= kMaxWrongAttempts; }

    Q_INVOKABLE bool verifyPassword(const QString& plaintext);
    Q_INVOKABLE bool changePassword(const QString& currentPlaintext, const QString& newPlaintext);
    Q_INVOKABLE void relock();

signals:
    void unlockedChanged();
    void lockedOutChanged();

private:
    static constexpr int kMaxWrongAttempts = 3;
    static constexpr int kMinPasswordLength = 8;

    bool _unlocked = false;
    int _wrongAttempts = 0;
};
