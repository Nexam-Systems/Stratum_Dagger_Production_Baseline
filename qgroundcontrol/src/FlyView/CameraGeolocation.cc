#include "CameraGeolocation.h"
#include "CameraGroundRay.h"
#include "QGCGeo.h"

#include <GeographicLib/Geocentric.hpp>
#include <GeographicLib/Geoid.hpp>
#include <GeographicLib/LocalCartesian.hpp>
#include <memory>
#include <exception>

namespace {
const GeographicLib::Geoid *geoidModel()
{
    static const std::unique_ptr<GeographicLib::Geoid> model = []() {
        try {
            return std::make_unique<GeographicLib::Geoid>("egm96-5");
        } catch (const std::exception &) {
            return std::unique_ptr<GeographicLib::Geoid>{};
        }
    }();
    return model.get();
}
}

QVariantMap CameraGeolocation::estimate(const QGeoCoordinate &position, const QGeoCoordinate &home,
                                       double relativeHeight, double vehicleRoll, double vehiclePitch, double vehicleYaw,
                                       double cameraRoll, double cameraPitch, double cameraYaw) const
{
    QVariantMap result{{"status", "INVALID"}, {"reason", "INVALID_POSITION"}};
    if (!position.isValid() || !home.isValid()) return result;
    const auto *geoid = geoidModel();
    const bool curvedSurface = geoid && std::isfinite(home.altitude()) && std::isfinite(position.altitude());
    auto hit = CameraGroundRay::intersect(vehicleRoll, vehiclePitch, vehicleYaw,
                                         cameraRoll, cameraPitch, cameraYaw, relativeHeight, curvedSurface);
    if (!hit.valid) {
        result["reason"] = QString::fromLatin1(hit.reason);
        return result;
    }
    QGeoCoordinate target;
    if (curvedSurface) {
        try {
            const double ellipsoidHeight = position.altitude() + (*geoid)(position.latitude(), position.longitude());
            const auto &earth = GeographicLib::Geocentric::WGS84();
            double originX, originY, originZ;
            earth.Forward(position.latitude(), position.longitude(), ellipsoidHeight, originX, originY, originZ);
            constexpr double radians = 3.14159265358979323846 / 180.0;
            const double latitude = position.latitude() * radians;
            const double longitude = position.longitude() * radians;
            const auto toEcef = [latitude, longitude](const CameraGroundRay::Vector &ned) {
                return CameraGroundRay::Vector{
                    -std::sin(latitude) * std::cos(longitude) * ned[0] - std::sin(longitude) * ned[1] - std::cos(latitude) * std::cos(longitude) * ned[2],
                    -std::sin(latitude) * std::sin(longitude) * ned[0] + std::cos(longitude) * ned[1] - std::cos(latitude) * std::sin(longitude) * ned[2],
                    std::cos(latitude) * ned[0] - std::sin(latitude) * ned[2]};
            };
            const auto offset = toEcef(hit.offset);
            const auto ray = toEcef(hit.ray);
            const auto pointAt = [&](double distance) {
                return CameraGroundRay::Vector{originX + offset[0] + distance * ray[0],
                                               originY + offset[1] + distance * ray[1],
                                               originZ + offset[2] + distance * ray[2]};
            };
            const auto surfaceResidual = [&](double distance) {
                const auto point = pointAt(distance);
                double targetLatitude, targetLongitude, targetHeight;
                earth.Reverse(point[0], point[1], point[2], targetLatitude, targetLongitude, targetHeight);
                return targetHeight - (*geoid)(targetLatitude, targetLongitude) - home.altitude();
            };
            if (!std::isfinite(surfaceResidual(0)) || surfaceResidual(0) <= 0) {
                result["reason"] = "CAMERA_NOT_ABOVE_SURFACE";
                return result;
            }
            hit.slantRange = CameraGroundRay::surfaceIntersection(surfaceResidual);
            if (!std::isfinite(hit.slantRange)) {
                result["reason"] = "NO_SURFACE_INTERSECTION";
                return result;
            }
            const auto point = pointAt(hit.slantRange);
            double targetLatitude, targetLongitude, targetHeight;
            earth.Reverse(point[0], point[1], point[2], targetLatitude, targetLongitude, targetHeight);
            target = QGeoCoordinate(targetLatitude, targetLongitude, home.altitude());
            GeographicLib::LocalCartesian local(position.latitude(), position.longitude(), ellipsoidHeight);
            double east, north, up;
            local.Forward(targetLatitude, targetLongitude, targetHeight, east, north, up);
            hit.displacement = {north, east, -up};
            hit.horizontalRange = std::hypot(north, east);
            hit.bearingDegrees = std::fmod(std::atan2(east, north) / radians + 360, 360);
        } catch (const std::exception &) {
            result["reason"] = "GEOID_OR_SURFACE_LOOKUP_FAILED";
            return result;
        }
    } else {
        target = QGCGeo::geodesicDestination(position, hit.bearingDegrees, hit.horizontalRange);
    }
    const double homeDistance = QGCGeo::geodesicDistance(home, target);
    if (!target.isValid() || !std::isfinite(homeDistance) || homeDistance > 15000) {
        result["reason"] = "OUTSIDE_HOME_AREA";
        return result;
    }
    result = {
        {"status", "DEGRADED"},
        {"reason", curvedSurface
            ? "WGS84 ECEF/EGM96 intersection; assumed body-relative pose, ideal centre ray and nominal mount; home-height ground; not video capture-aligned; accuracy unknown"
            : "EGM96 geoid or AMSL unavailable: short-range local approximation only; assumed body-relative pose, ideal centre ray and nominal mount; home-height ground; not video capture-aligned; accuracy unknown"},
        {"source", "CAMERA_CENTRE_RAY"},
        {"surfaceMode", curvedSurface ? "HOME_HEIGHT_WGS84_EGM96" : "HOME_HEIGHT_LOCAL_PLANE"},
        {"geoidModel", curvedSurface ? "egm96-5" : "UNAVAILABLE"},
        {"latitude", target.latitude()}, {"longitude", target.longitude()},
        {"horizontalRange", hit.horizontalRange}, {"slantRange", hit.slantRange},
        {"bearing", hit.bearingDegrees}, {"dNorth", hit.displacement[0]}, {"dEast", hit.displacement[1]},
        {"homeDistance", homeDistance}, {"heightAboveTakeoff", relativeHeight},
        {"targetAltitudeAmsl", std::isfinite(home.altitude()) ? QVariant(home.altitude()) : QVariant()},
        {"cameraClearance", relativeHeight - hit.offset[2]},
        {"rayNorth", hit.ray[0]}, {"rayEast", hit.ray[1]}, {"rayDown", hit.ray[2]},
        {"cameraRoll", cameraRoll}, {"cameraPitch", cameraPitch}, {"cameraYaw", cameraYaw},
        {"accuracyMeters", QVariant()}, {"productionReady", false}
    };
    return result;
}