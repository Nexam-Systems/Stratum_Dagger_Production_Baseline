#pragma once

#include "UnitTest.h"

class DeviceInfoV2Test : public UnitTest
{
    Q_OBJECT

private slots:
    void _ff1NistSample1_test();
    void _ff1NistSample2_test();
    void _ff1InverseRoundtrip_test();
    void _referencePacketA_test();
    void _referencePacketB_test();
    void _decodeReferencePackets_test();
    void _boundaries_test();
    void _leadingZeroHandshakePreserved_test();
    void _randomRoundtrips_test();
    void _invalidInputsRejected_test();
    void _badFrameLengthRejected_test();
    void _crcMismatchRejected_test();
    void _crc6DetectsSingleBitErrors_test();
};
