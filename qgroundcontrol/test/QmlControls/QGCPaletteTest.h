#pragma once

#include "UnitTest.h"

class QGCPaletteTest : public UnitTest
{
    Q_OBJECT

private slots:
    void _standardThemeRestored();
    void _allPalettesNotified();
    void _disabledControlsRemainReadable();
};