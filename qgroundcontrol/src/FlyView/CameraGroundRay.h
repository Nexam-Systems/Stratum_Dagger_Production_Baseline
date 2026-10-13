#pragma once

#include <array>
#include <cmath>

namespace CameraGroundRay
{
using Vector = std::array<double, 3>;

struct Intersection {
    bool valid = false;
    const char *reason = "INVALID_INPUT";
    Vector ray{};
    Vector offset{};
    Vector displacement{};
    double slantRange = 0;
    double horizontalRange = 0;
    double bearingDegrees = 0;
};

inline Vector rotate(const Vector &vector, double roll, double pitch, double yaw)
{
    const double rollCos = std::cos(roll);
    const double rollSin = std::sin(roll);
    const double pitchCos = std::cos(pitch);
    const double pitchSin = std::sin(pitch);
    const double yawCos = std::cos(yaw);
    const double yawSin = std::sin(yaw);
    const Vector rolled{vector[0], rollCos * vector[1] - rollSin * vector[2], rollSin * vector[1] + rollCos * vector[2]};
    const Vector pitched{pitchCos * rolled[0] + pitchSin * rolled[2], rolled[1], -pitchSin * rolled[0] + pitchCos * rolled[2]};
    return {yawCos * pitched[0] - yawSin * pitched[1], yawSin * pitched[0] + yawCos * pitched[1], pitched[2]};
}

inline Intersection intersect(double vehicleRoll, double vehiclePitch, double vehicleYaw,
                              double cameraRoll, double cameraPitch, double cameraYaw, double relativeHeight,
                              bool curvedSurface = false)
{
    Intersection result;
    for (double value : {vehicleRoll, vehiclePitch, vehicleYaw, cameraRoll, cameraPitch, cameraYaw, relativeHeight}) {
        if (!std::isfinite(value)) return result;
    }
    if (std::abs(vehiclePitch) > 90 || std::abs(cameraPitch) > 90 || relativeHeight <= 0) return result;
    constexpr double radians = 3.14159265358979323846 / 180.0;
    const Vector bodyRay = rotate({1, 0, 0}, cameraRoll * radians, cameraPitch * radians, -cameraYaw * radians);
    result.ray = rotate(bodyRay, vehicleRoll * radians, vehiclePitch * radians, vehicleYaw * radians);
    result.offset = rotate({0.1524, 0, 0}, vehicleRoll * radians, vehiclePitch * radians, vehicleYaw * radians);
    if (result.ray[2] <= (curvedSurface ? 1e-6 : std::sin(radians))) {
        result.reason = "NOT_LOOKING_DOWN_OR_NEAR_HORIZON";
        return result;
    }
    const double clearance = relativeHeight - result.offset[2];
    if (clearance <= 0) {
        result.reason = "CAMERA_NOT_ABOVE_GROUND";
        return result;
    }
    result.slantRange = clearance / result.ray[2];
    for (unsigned axis = 0; axis < 3; ++axis) result.displacement[axis] = result.offset[axis] + result.slantRange * result.ray[axis];
    result.horizontalRange = std::hypot(result.displacement[0], result.displacement[1]);
    if (!curvedSurface && (result.horizontalRange > 2000 || result.slantRange > 40000)) {
        result.reason = "OUTSIDE_LOCAL_MODEL_ENVELOPE";
        return result;
    }
    result.bearingDegrees = std::fmod(std::atan2(result.displacement[1], result.displacement[0]) / radians + 360, 360);
    result.valid = true;
    result.reason = "";
    return result;
}

template<typename Residual>
inline double surfaceIntersection(Residual residual)
{
    const double initial = residual(0);
    if (!std::isfinite(initial) || initial <= 0) return NAN;
    double lower = 0;
    double upper = 0;
    for (double distance = 10; distance <= 40000; distance += 10) {
        const double value = residual(distance);
        if (!std::isfinite(value)) return NAN;
        if (value <= 0) { upper = distance; break; }
        lower = distance;
    }
    if (upper == 0) return NAN;
    for (int iteration = 0; iteration < 64; ++iteration) {
        const double middle = (lower + upper) / 2;
        const double value = residual(middle);
        if (!std::isfinite(value)) return NAN;
        if (upper - lower <= 0.1 && std::abs(value) <= 0.1) return middle;
        if (value > 0) lower = middle;
        else upper = middle;
    }
    return NAN;
}
}