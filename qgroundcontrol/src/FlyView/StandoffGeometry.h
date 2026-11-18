#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QVariantList>
#include <QtCore/qnumeric.h>
#include <QtPositioning/QGeoCoordinate>
#include <QtQmlIntegration/QtQmlIntegration>

/// STRATUM #98: standoff geometry model. Single source of truth for the Set Standoff panel,
/// the map overlay and the standoff command.
///
/// The operator supplies a target (lat/lon, altitude AMSL) and the standoff parameters:
///   R = horizontal distance target -> slot [m]
///   H = height of the slot ABOVE THE TARGET [m]
///   θ = true bearing target -> slot [deg, 0 <= θ < 360]
/// The slot is the WGS-84 geodesic point at distance R / bearing θ from the target, at
/// altitude (target AMSL + H). Target and home are assumed to be at the same level, so H is
/// sent to the vehicle exactly as entered (unchanged from the existing standoff command).
///
/// Unset numeric inputs are NaN. Every property shares the single changed() notify signal.
/// Limits come from FlyViewSettings (standoffMin/MaxDistance, standoffMin/MaxHeight,
/// standoffLinkRangeLimit).
class StandoffGeometry : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // ---- inputs ----
    Q_PROPERTY(double         targetLatitude   READ targetLatitude   WRITE setTargetLatitude   NOTIFY changed)
    Q_PROPERTY(double         targetLongitude  READ targetLongitude  WRITE setTargetLongitude  NOTIFY changed)
    Q_PROPERTY(double         targetAltitude   READ targetAltitude   WRITE setTargetAltitude   NOTIFY changed)   ///< m AMSL
    Q_PROPERTY(double         distance         READ distance         WRITE setDistance         NOTIFY changed)   ///< R [m]
    Q_PROPERTY(double         height           READ height           WRITE setHeight           NOTIFY changed)   ///< H above target [m]
    Q_PROPERTY(double         direction        READ direction        WRITE setDirection        NOTIFY changed)   ///< θ [deg true]
    Q_PROPERTY(QGeoCoordinate gcsCoordinate    READ gcsCoordinate    WRITE setGcsCoordinate    NOTIFY changed)   ///< operator / GCS position

    // ---- validation (empty string = OK) ----
    Q_PROPERTY(bool           valid            READ valid            NOTIFY changed)
    Q_PROPERTY(QString        targetError      READ targetError      NOTIFY changed)
    Q_PROPERTY(QString        altitudeError    READ altitudeError    NOTIFY changed)
    Q_PROPERTY(QString        distanceError    READ distanceError    NOTIFY changed)
    Q_PROPERTY(QString        heightError      READ heightError      NOTIFY changed)
    Q_PROPERTY(QString        directionError   READ directionError   NOTIFY changed)

    // ---- derived values (NaN / invalid coordinate when they cannot be computed) ----
    Q_PROPERTY(QGeoCoordinate slotCoordinate   READ slotCoordinate   NOTIFY changed)   ///< lat/lon + slot altitude AMSL
    Q_PROPERTY(QVariantList   ringPath         READ ringPath         NOTIFY changed)   ///< standoff ring: geodesic circle of radius R, one point per degree (kRingPoints + 1 coordinates, closed); empty without a target / R
    Q_PROPERTY(double         slotAltitude     READ slotAltitude     NOTIFY changed)   ///< target AMSL + H [m]
    Q_PROPERTY(double         slantRange       READ slantRange       NOTIFY changed)   ///< slot -> target [m]
    Q_PROPERTY(double         gcsDistanceToSlot READ gcsDistanceToSlot NOTIFY changed) ///< horizontal GCS -> slot [m]
    Q_PROPERTY(bool           linkRangeExceeded READ linkRangeExceeded NOTIFY changed) ///< warning only, never blocks

    // ---- configured limits ----
    Q_PROPERTY(double         minDistance      READ minDistance      NOTIFY changed)
    Q_PROPERTY(double         maxDistance      READ maxDistance      NOTIFY changed)
    Q_PROPERTY(double         minHeight        READ minHeight        NOTIFY changed)
    Q_PROPERTY(double         maxHeight        READ maxHeight        NOTIFY changed)
    Q_PROPERTY(double         linkRangeLimit   READ linkRangeLimit   NOTIFY changed)

public:
    static constexpr double kDefaultDistance = 100.0;   ///< default R [m]
    static constexpr double kDefaultHeight   = 100.0;   ///< default H [m]
    static constexpr int    kRingPoints      = 360;     ///< ring resolution: 1 degree

    explicit StandoffGeometry(QObject *parent = nullptr);

    double         targetLatitude() const  { return _targetLatitude; }
    double         targetLongitude() const { return _targetLongitude; }
    double         targetAltitude() const  { return _targetAltitude; }
    double         distance() const        { return _distance; }
    double         height() const          { return _height; }
    double         direction() const       { return _direction; }
    QGeoCoordinate gcsCoordinate() const   { return _gcsCoordinate; }

    void setTargetLatitude(double value)   { _setValue(_targetLatitude, value); }
    void setTargetLongitude(double value)  { _setValue(_targetLongitude, value); }
    void setTargetAltitude(double value)   { _setValue(_targetAltitude, value); }
    void setDistance(double value)         { _setValue(_distance, value); }
    void setHeight(double value)           { _setValue(_height, value); }
    void setDirection(double value)        { _setValue(_direction, value); }
    void setGcsCoordinate(const QGeoCoordinate &value);

    bool    valid() const;
    QString targetError() const;
    QString altitudeError() const;
    QString distanceError() const;
    QString heightError() const;
    QString directionError() const;

    QGeoCoordinate slotCoordinate() const;
    QVariantList   ringPath() const;
    double         slotAltitude() const;
    double         slantRange() const;
    double         gcsDistanceToSlot() const;
    bool           linkRangeExceeded() const;

    double minDistance() const;
    double maxDistance() const;
    double minHeight() const;
    double maxHeight() const;
    double linkRangeLimit() const;

signals:
    void changed();

private:
    void _setValue(double &member, double value);
    bool _hasSlot() const;

    double         _targetLatitude  = qQNaN();
    double         _targetLongitude = qQNaN();
    double         _targetAltitude  = qQNaN();
    double         _distance        = kDefaultDistance;
    double         _height          = kDefaultHeight;
    double         _direction       = 0.0;
    QGeoCoordinate _gcsCoordinate;
};
