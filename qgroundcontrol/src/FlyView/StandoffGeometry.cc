#include "StandoffGeometry.h"

#include "Fact.h"
#include "FlyViewSettings.h"
#include "QGCGeo.h"
#include "SettingsManager.h"

#include <cmath>
#include <initializer_list>

namespace {

FlyViewSettings *flyViewSettings()
{
    return SettingsManager::instance()->flyViewSettings();
}

double limitValue(Fact *fact)
{
    return fact->rawValue().toDouble();
}

bool sameValue(double a, double b)
{
    return (std::isnan(a) && std::isnan(b)) || (a == b);
}

}  // namespace

StandoffGeometry::StandoffGeometry(QObject *parent)
    : QObject(parent)
{
    // The limits are user-configurable settings; re-evaluate validation when they change.
    FlyViewSettings *settings = flyViewSettings();
    for (Fact *fact : {settings->standoffMinDistance(), settings->standoffMaxDistance(),
                       settings->standoffMinHeight(), settings->standoffMaxHeight(),
                       settings->standoffLinkRangeLimit()}) {
        (void) connect(fact, &Fact::rawValueChanged, this, &StandoffGeometry::changed);
    }
}

void StandoffGeometry::_setValue(double &member, double value)
{
    if (sameValue(member, value)) {
        return;
    }
    member = value;
    emit changed();
}

void StandoffGeometry::setGcsCoordinate(const QGeoCoordinate &value)
{
    if (_gcsCoordinate == value) {
        return;
    }
    _gcsCoordinate = value;
    emit changed();
}

// ---- validation ------------------------------------------------------------

QString StandoffGeometry::targetError() const
{
    if (!std::isfinite(_targetLatitude) || !std::isfinite(_targetLongitude)) {
        return tr("Target latitude and longitude are required.");
    }
    if (std::fabs(_targetLatitude) > 90.0) {
        return tr("Latitude must be between -90 and 90 degrees.");
    }
    if (std::fabs(_targetLongitude) > 180.0) {
        return tr("Longitude must be between -180 and 180 degrees.");
    }
    return QString();
}

QString StandoffGeometry::altitudeError() const
{
    if (!std::isfinite(_targetAltitude)) {
        return tr("Target altitude (m AMSL) is required.");
    }
    return QString();
}

QString StandoffGeometry::distanceError() const
{
    if (!std::isfinite(_distance)) {
        return tr("Standoff distance is required.");
    }
    if (_distance < minDistance() || _distance > maxDistance()) {
        return tr("Standoff distance must be between %1 and %2 m.")
            .arg(minDistance(), 0, 'f', 0).arg(maxDistance(), 0, 'f', 0);
    }
    return QString();
}

QString StandoffGeometry::heightError() const
{
    if (!std::isfinite(_height)) {
        return tr("Standoff height is required.");
    }
    if (_height < minHeight() || _height > maxHeight()) {
        return tr("Standoff height must be between %1 and %2 m.")
            .arg(minHeight(), 0, 'f', 0).arg(maxHeight(), 0, 'f', 0);
    }
    return QString();
}

QString StandoffGeometry::directionError() const
{
    if (!std::isfinite(_direction)) {
        return tr("Standoff direction is required.");
    }
    if (_direction < 0.0 || _direction >= 360.0) {
        return tr("Standoff direction must be 0 or more and less than 360 degrees.");
    }
    return QString();
}

bool StandoffGeometry::valid() const
{
    return targetError().isEmpty() && altitudeError().isEmpty() && distanceError().isEmpty()
           && heightError().isEmpty() && directionError().isEmpty();
}

// ---- derived values --------------------------------------------------------

// The slot depends only on the target position, R and θ. It is computed even when R is outside
// the configured limits, so the map can show the draft while the panel flags the error.
bool StandoffGeometry::_hasSlot() const
{
    return targetError().isEmpty()
           && std::isfinite(_distance) && _distance >= 0.0
           && std::isfinite(_direction) && _direction >= 0.0 && _direction < 360.0;
}

double StandoffGeometry::slotAltitude() const
{
    if (!std::isfinite(_targetAltitude) || !std::isfinite(_height)) {
        return qQNaN();
    }
    return _targetAltitude + _height;
}

QGeoCoordinate StandoffGeometry::slotCoordinate() const
{
    if (!_hasSlot()) {
        return QGeoCoordinate();
    }

    QGeoCoordinate slot = QGCGeo::geodesicDestination(
        QGeoCoordinate(_targetLatitude, _targetLongitude), _direction, _distance);
    const double altitude = slotAltitude();
    if (std::isfinite(altitude)) {
        slot.setAltitude(altitude);
    }
    return slot;
}

// The ring only needs the target and R (not θ): it is drawn as soon as those are valid.
QVariantList StandoffGeometry::ringPath() const
{
    QVariantList path;
    if (!targetError().isEmpty() || !std::isfinite(_distance) || _distance <= 0.0) {
        return path;
    }

    const QGeoCoordinate target(_targetLatitude, _targetLongitude);
    path.reserve(kRingPoints + 1);
    for (int i = 0; i <= kRingPoints; ++i) {
        path.append(QVariant::fromValue(QGCGeo::geodesicDestination(target, static_cast<double>(i), _distance)));
    }
    return path;
}

double StandoffGeometry::slantRange() const
{
    if (!std::isfinite(_distance) || _distance < 0.0 || !std::isfinite(_height)) {
        return qQNaN();
    }
    // The slot is exactly R away horizontally (geodesic) and H above the target.
    return std::hypot(_distance, _height);
}

double StandoffGeometry::gcsDistanceToSlot() const
{
    const QGeoCoordinate slot = slotCoordinate();
    if (!slot.isValid() || !_gcsCoordinate.isValid()) {
        return qQNaN();
    }
    return QGCGeo::geodesicDistance(_gcsCoordinate, slot);
}

bool StandoffGeometry::linkRangeExceeded() const
{
    const double gcsDistance = gcsDistanceToSlot();
    return std::isfinite(gcsDistance) && gcsDistance > linkRangeLimit();
}

// ---- configured limits -----------------------------------------------------

double StandoffGeometry::minDistance() const    { return limitValue(flyViewSettings()->standoffMinDistance()); }
double StandoffGeometry::maxDistance() const    { return limitValue(flyViewSettings()->standoffMaxDistance()); }
double StandoffGeometry::minHeight() const      { return limitValue(flyViewSettings()->standoffMinHeight()); }
double StandoffGeometry::maxHeight() const      { return limitValue(flyViewSettings()->standoffMaxHeight()); }
double StandoffGeometry::linkRangeLimit() const { return limitValue(flyViewSettings()->standoffLinkRangeLimit()); }
