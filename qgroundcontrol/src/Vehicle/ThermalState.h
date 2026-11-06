#pragma once

#include <array>
#include <cmath>
#include <cstdint>
#include <limits>

// Transport-independent state; callers supply monotonic receive times.
class ThermalState
{
public:
    static constexpr int SensorCount = 5; // FC IMU, then ESCs 1-4
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
        unsigned missingRequiredMask = 0;
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

    static Severity severity(double temperatureC)
    {
        if (!std::isfinite(temperatureC)) return Severity::Unknown;
        if (temperatureC > CriticalC) return Severity::Critical;
        if (temperatureC >= WarningC) return Severity::Warning;
        return Severity::Normal;
    }

    Result evaluate(int64_t now, int64_t timeout, unsigned requiredMask) const
    {
        Result result;
        double sum = 0;
        Severity worst = Severity::Unknown;
        for (int i = 0; i < SensorCount; ++i) {
            if (availability(i, now, timeout) != Availability::Fresh) {
                result.missingRequiredMask |= requiredMask & (1U << i);
                continue;
            }
            ++result.freshCount;
            sum += readings[i].temperatureC;
            const Severity current = severity(readings[i].temperatureC);
            if (current > worst) worst = current;
            if (current == Severity::Critical) result.criticalMask |= 1U << i;
        }
        if (result.freshCount) result.averageC = sum / result.freshCount;
        result.severity = result.criticalMask ? Severity::Critical
                         : result.missingRequiredMask ? Severity::Unknown : worst;
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

    bool blocksGroundCommands(int64_t now, int64_t timeout, unsigned requiredMask) const
    {
        const Result result = evaluate(now, timeout, requiredMask);
        return confirmedGround(now, timeout) && (result.criticalMask || result.missingRequiredMask);
    }

    std::array<Reading, SensorCount> readings{};
    Phase phase = Phase::Unknown;
    int64_t phaseReceivedAtMs = -1;
};
