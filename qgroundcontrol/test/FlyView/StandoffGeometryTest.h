#pragma once

#include "UnitTest.h"

class StandoffGeometryTest : public UnitTest
{
    Q_OBJECT

private slots:
    void _slotMatchesReference_test();
    void _slotAltitudeAndSlantRange_test();
    void _slotRoundTrip_test();
    void _validation_test();
    void _limitsAreInclusive_test();
    void _gcsRangeAndLinkWarning_test();
    void _changedSignal_test();
    void _slotUnavailableWithoutTarget_test();
};
