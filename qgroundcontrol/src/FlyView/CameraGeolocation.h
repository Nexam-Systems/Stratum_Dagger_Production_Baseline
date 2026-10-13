#pragma once

#include <QtCore/QObject>
#include <QtCore/QVariantMap>
#include <QtPositioning/QGeoCoordinate>
#include <QtQmlIntegration/QtQmlIntegration>

class CameraGeolocation : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit CameraGeolocation(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE QVariantMap estimate(const QGeoCoordinate &position, const QGeoCoordinate &home,
                                    double relativeHeight, double vehicleRoll, double vehiclePitch, double vehicleYaw,
                                    double cameraRoll, double cameraPitch, double cameraYaw) const;
};