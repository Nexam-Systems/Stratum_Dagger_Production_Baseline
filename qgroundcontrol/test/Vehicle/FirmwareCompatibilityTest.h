#pragma once

#include "UnitTest.h"

class FirmwareCompatibilityTest : public UnitTest
{
    Q_OBJECT

private slots:
    void _compatibilityToggle_data();
    void _compatibilityToggle();
};