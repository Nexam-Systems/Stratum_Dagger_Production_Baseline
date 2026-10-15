#pragma once

#include "UnitTest.h"

class FlyViewArmedTimerTest : public UnitTest
{
    Q_OBJECT

private slots:
    void _observedArmingResetsAndDisarmingFreezes();
    void _alreadyArmedConnectionIsLabeled();
};