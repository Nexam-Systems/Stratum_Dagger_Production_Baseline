#pragma once

#include <array>
#include <cmath>
#include <cstdint>
#include <limits>

// Transport-independent state; callers supply monotonic receive times.
class ThermalState
{
public:
    static constexpr int SensorCount = 4;
    static constexpr double WarningC = 70.0;
    static constexpr double CriticalC = 80.0;
    enum class Severity { Unknown, Normal, Warning, Critical };
    enum class Availability { Missing, Offline, Invalid, Stale, Fresh };
    enum class Phase { Unknown, Ground, Airborne };

    struct Reading {
        double temperatureC = std::numeric_limits<double>::quiet_NaN();
        int64_t receivedAtMs = -1;
        bool online = false;
    };
    struct Result {
        double averageC = std::numeric_limits<double>::quiet_NaN();
        int freshCount = 0;
        unsigned criticalMask = 0;
        Severity severity = Severity::Unknown;
    };

    bool update(int index, double temperatureC, bool online, int64_t now)
    {
        if (index < 0 || index >= SensorCount || now < 0) {
            return false;
        }
        readings[index] = {temperatureC, now, online};
        return true;
    }

    Availability availability(int index, int64_t now, int64_t timeout) const
    {
        const auto &reading = readings[index];
        if (reading.receivedAtMs < 0) return Availability::Missing;
        if (now < reading.receivedAtMs || now - reading.receivedAtMs > timeout) return Availability::Stale;
        if (!reading.online) return Availability::Offline;
        if (!std::isfinite(reading.temperatureC)) return Availability::Invalid;
        return Availability::Fresh;
    }

    static Severity severity(double temperatureC, double warnLimit, double critLimit)
    {
        if (!std::isfinite(temperatureC)) return Severity::Unknown;
        if (temperatureC > critLimit) return Severity::Critical;
        if (temperatureC >= warnLimit) return Severity::Warning;
        return Severity::Normal;
    }

    // Default-threshold classifier (baseline 70/80 °C); used by callers/tests on the defaults.
    static Severity severity(double temperatureC)
    {
        return severity(temperatureC, WarningC, CriticalC);
    }

    // Instance classifier honoring the admin-configured critical limit (criticalC).
    Severity severityOf(double temperatureC) const
    {
        return severity(temperatureC, WarningC, criticalC);
    }

    // Override the critical limit (e.g. from the admin panel). Invalid values are ignored.
    void setCriticalC(double limitC)
    {
        if (std::isfinite(limitC) && limitC > 0.0) criticalC = limitC;
    }

    Result evaluate(int64_t now, int64_t timeout) const
    {
        Result result;
        double sum = 0;
        Severity worst = Severity::Unknown;
        for (int i = 0; i < SensorCount; ++i) {
            if (availability(i, now, timeout) != Availability::Fresh) {
                continue;
            }
            ++result.freshCount;
            sum += readings[i].temperatureC;
            const Severity current = severityOf(readings[i].temperatureC);
            if (current > worst) worst = current;
            if (current == Severity::Critical) result.criticalMask |= 1U << i;
        }
        if (result.freshCount) result.averageC = sum / result.freshCount;
        result.severity = worst;
        return result;
    }

    void updatePhase(Phase value, int64_t now)
    {
        phase = value;
        phaseReceivedAtMs = now;
    }

    bool confirmedGround(int64_t now, int64_t timeout) const
    {
        return phase == Phase::Ground && phaseReceivedAtMs >= 0
               && now >= phaseReceivedAtMs && now - phaseReceivedAtMs <= timeout;
    }

    bool blocksGroundCommands(int64_t now, int64_t timeout) const
    {
        const Result result = evaluate(now, timeout);
        return confirmedGround(now, timeout) && result.criticalMask;
    }

    std::array<Reading, SensorCount> readings{};
    Phase phase = Phase::Unknown;
    int64_t phaseReceivedAtMs = -1;
    double criticalC = CriticalC;  // critical limit in °C; overridable via setCriticalC()
};
