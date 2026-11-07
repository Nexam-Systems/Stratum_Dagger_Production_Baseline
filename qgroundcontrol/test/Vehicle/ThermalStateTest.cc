#include "ThermalState.h"

#include <cstdio>

#define CHECK(condition) do { if (!(condition)) { std::fprintf(stderr, "Failed at line %d: %s\n", __LINE__, #condition); return 1; } } while (false)

int main()
{
    using State = ThermalState;
    CHECK(State::SensorCount == 4);
    CHECK(State::severity(69.99) == State::Severity::Normal);
    CHECK(State::severity(70.0) == State::Severity::Warning);
    CHECK(State::severity(80.0) == State::Severity::Warning);
    CHECK(State::severity(80.01) == State::Severity::Critical);
    CHECK(State::severity(std::numeric_limits<double>::quiet_NaN()) == State::Severity::Unknown);

    State state;
    CHECK(state.evaluate(0, 3000).freshCount == 0);
    CHECK(std::isnan(state.evaluate(0, 3000).averageC));
    CHECK(!state.update(-1, 40, true, 0));
    CHECK(!state.update(4, 40, true, 0));
    for (int i = 0; i < State::SensorCount; ++i) CHECK(state.update(i, 40 + i * 10, true, 0));
    CHECK(state.update(3, 80, true, 0));
    CHECK(state.evaluate(0, 3000).freshCount == 4);
    CHECK(state.evaluate(0, 3000).averageC == 57.5);
    CHECK(!state.blocksGroundCommands(0, 3000));
    state.updatePhase(State::Phase::Ground, 0);
    CHECK(!state.blocksGroundCommands(0, 3000)); // Exactly 80 is permitted.

    CHECK(state.update(0, 81, true, 0));
    CHECK(state.evaluate(0, 3000).averageC < 80);
    CHECK(state.evaluate(0, 3000).criticalMask == 1);
    CHECK(state.blocksGroundCommands(0, 3000)); // Any fresh hot motor, not the average.
    for (const auto phase : {State::Phase::Unknown, State::Phase::Airborne}) {
        state.updatePhase(phase, 0);
        CHECK(!state.blocksGroundCommands(0, 3000));
    }
    state.updatePhase(State::Phase::Ground, 0);
    CHECK(state.blocksGroundCommands(3000, 3000));
    CHECK(!state.blocksGroundCommands(3001, 3000)); // Stale ground status is not ground proof.
    CHECK(state.evaluate(3001, 3000).freshCount == 0);
    CHECK(state.evaluate(3001, 3000).severity == State::Severity::Unknown);

    state.updatePhase(State::Phase::Ground, 3001);
    CHECK(!state.blocksGroundCommands(3001, 3000)); // No missing-data interlock.
    CHECK(state.update(1, 45, false, 3001));
    CHECK(state.availability(1, 3001, 3000) == State::Availability::Offline);
    CHECK(state.update(2, std::numeric_limits<double>::quiet_NaN(), true, 3001));
    CHECK(state.availability(2, 3001, 3000) == State::Availability::Invalid);
    CHECK(state.update(3, 0, true, 3001)); // A genuine zero ESC reading is valid.
    CHECK(state.evaluate(3001, 3000).freshCount == 1);
    CHECK(state.evaluate(3001, 3000).averageC == 0);
    CHECK(state.evaluate(3001, 3000).severity == State::Severity::Normal);
    CHECK(state.update(0, 81, true, 3001));
    CHECK(state.evaluate(3001, 3000).severity == State::Severity::Critical);
    CHECK(state.blocksGroundCommands(3001, 3000));
    state = {}; // Link loss/reconnect clears all live data and ground proof.
    CHECK(state.evaluate(4000, 3000).freshCount == 0);
    CHECK(!state.confirmedGround(4000, 3000));

    // Admin-configurable critical threshold: the blocking limit follows setCriticalC().
    {
        State dyn;
        dyn.updatePhase(State::Phase::Ground, 0);
        for (int i = 0; i < State::SensorCount; ++i) CHECK(dyn.update(i, 81, true, 0));
        CHECK(dyn.blocksGroundCommands(0, 3000)); // Default 80 °C: 81 is hot.

        dyn.setCriticalC(90); // Raise the limit.
        CHECK(dyn.severityOf(81) == State::Severity::Warning);
        CHECK(dyn.evaluate(0, 3000).criticalMask == 0);
        CHECK(!dyn.blocksGroundCommands(0, 3000)); // 81 < 90: no longer hot.
        CHECK(dyn.severityOf(90.01) == State::Severity::Critical);

        dyn.setCriticalC(60); // Lower the limit.
        CHECK(dyn.severityOf(65) == State::Severity::Critical);
        CHECK(dyn.blocksGroundCommands(0, 3000)); // 81 >> 60: hot again.

        dyn.setCriticalC(-5); // Invalid values are ignored.
        CHECK(dyn.criticalC == 60);
        dyn.setCriticalC(std::numeric_limits<double>::quiet_NaN());
        CHECK(dyn.criticalC == 60);
    }

    std::puts("Thermal policy: four ESCs, thresholds, averaging, freshness and flight-phase checks passed.");
    return 0;
}
