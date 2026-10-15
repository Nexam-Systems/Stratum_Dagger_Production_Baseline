#include "../../src/FlyView/CameraGroundRay.h"

#include <cassert>
#include <iostream>

int main()
{
    const auto north = CameraGroundRay::intersect(0, 0, 0, 0, -45, 0, 100);
    assert(north.valid);
    assert(std::abs(north.displacement[0] - 100.1524) < 1e-8);
    assert(std::abs(north.displacement[1]) < 1e-8);
    assert(std::abs(north.slantRange - std::sqrt(20000.0)) < 1e-8);
    const auto right = CameraGroundRay::intersect(0, 0, 90, 0, -45, -30, 100);
    assert(right.valid);
    assert(std::abs(right.displacement[0] + 50) < 1e-8);
    assert(std::abs(right.displacement[1] - (std::sqrt(7500.0) + 0.1524)) < 1e-8);
    const auto rolledCamera = CameraGroundRay::intersect(0, 0, 90, 45, -45, -30, 100);
    assert(rolledCamera.valid && std::abs(rolledCamera.horizontalRange - right.horizontalRange) < 1e-8);
    const auto rolledAircraft = CameraGroundRay::intersect(30, 0, 0, 0, -45, 0, 100);
    assert(rolledAircraft.valid && rolledAircraft.displacement[1] < 0);
    const auto noseDown = CameraGroundRay::intersect(0, -30, 0, 0, 10, 0, 100);
    assert(noseDown.valid);
    const auto nadir = CameraGroundRay::intersect(0, 0, 0, 0, -90, 0, 100);
    assert(nadir.valid && std::abs(nadir.horizontalRange - 0.1524) < 1e-8);
    assert(!CameraGroundRay::intersect(0, 0, 0, 0, 45, 0, 100).valid);
    assert(!CameraGroundRay::intersect(0, 0, 0, 0, 0, 0, 100).valid);
    assert(!CameraGroundRay::intersect(0, 0, 0, 0, -45, 0, 0).valid);
    assert(!CameraGroundRay::intersect(0, 0, 0, 0, -45, 0, NAN).valid);
    assert(!CameraGroundRay::intersect(0, 0, 0, 0, -2, 0, 100).valid);
    assert(CameraGroundRay::intersect(0, 0, 0, 0, -0.5, 0, 100, true).valid);
    const double crossing = CameraGroundRay::surfaceIntersection([](double distance) { return 100 - distance / std::sqrt(2.0); });
    assert(std::abs(crossing - std::sqrt(20000.0)) <= 0.1);
    assert(!std::isfinite(CameraGroundRay::surfaceIntersection([](double) { return 100.0; })));
    assert(!std::isfinite(CameraGroundRay::surfaceIntersection([](double) { return -1.0; })));
    assert(!std::isfinite(CameraGroundRay::surfaceIntersection([](double) { return NAN; })));
    std::cout << "Camera ray: PDF worked examples, sign, roll, tilt, nadir and invalid-input tests passed\n";
}