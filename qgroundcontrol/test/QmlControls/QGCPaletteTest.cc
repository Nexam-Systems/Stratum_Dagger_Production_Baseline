#include "QGCPaletteTest.h"
#include "QGCPalette.h"
#include "AppSettings.h"
#include "SettingsManager.h"

#include <QtTest/QSignalSpy>
#include <QtCore/qscopeguard.h>
#include <QtGui/QGuiApplication>

namespace {
class PaletteStateGuard
{
public:
    ~PaletteStateGuard()
    {
        QGCPalette::setHighContrast(_contrast);
        QGCPalette::setGlobalTheme(_theme);
    }

private:
    const bool _contrast = QGCPalette::highContrast();
    const QGCPalette::Theme _theme = QGCPalette::globalTheme();
};
}

void QGCPaletteTest::_standardThemeRestored()
{
    PaletteStateGuard guard;
    QGCPalette palette;
    palette.setColorGroupEnabled(true);
    for (const auto theme : {QGCPalette::Light, QGCPalette::Dark}) {
        QGCPalette::setHighContrast(false);
        QGCPalette::setGlobalTheme(theme);
        const auto window = palette.window();
        const auto button = palette.button();
        const auto text = palette.text();
        QGCPalette::setHighContrast(true);
        QCOMPARE(palette.window(), QColor("#050A06"));
        QCOMPARE(palette.buttonText(), QColor("#D6FF85"));
        QCOMPARE(QGCPalette::globalTheme(), theme);
        QGCPalette::setHighContrast(false);
        QCOMPARE(palette.window(), window);
        QCOMPARE(palette.button(), button);
        QCOMPARE(palette.text(), text);
    }
}

void QGCPaletteTest::_allPalettesNotified()
{
    PaletteStateGuard guard;
    QGCPalette first;
    QGCPalette second;
    QGCPalette::setHighContrast(false);
    QSignalSpy firstChanged(&first, &QGCPalette::paletteChanged);
    QSignalSpy secondChanged(&second, &QGCPalette::paletteChanged);
    QGCPalette::setHighContrast(true);
    QCOMPARE(firstChanged.count(), 1);
    QCOMPARE(secondChanged.count(), 1);
    QGCPalette::setHighContrast(true);
    QCOMPARE(firstChanged.count(), 1);
    QGCPalette::setHighContrast(false);
    QCOMPARE(firstChanged.count(), 2);
    QCOMPARE(secondChanged.count(), 2);
}

void QGCPaletteTest::_disabledControlsRemainReadable()
{
    PaletteStateGuard guard;
    QGCPalette palette;
    QGCPalette::setHighContrast(true);
    palette.setColorGroupEnabled(true);
    const auto enabledText = palette.buttonText();
    palette.setColorGroupEnabled(false);
    QCOMPARE(palette.buttonText(), QColor("#B5BDB0"));
    QCOMPARE(palette.button(), QColor("#202420"));
    QCOMPARE(palette.buttonBorder(), QColor("#7D8876"));
    QVERIFY(palette.buttonText() != enabledText);
    QCOMPARE(palette.warningText(), QColor("#FFD166"));
}

void QGCPaletteTest::_savedDisplayThemeAppliesToPalette()
{
    PaletteStateGuard guard;
    auto *theme = SettingsManager::instance()->appSettings()->indoorPalette();
    const QVariant previous = theme->rawValue();
    const auto restore = qScopeGuard([&]() { theme->setRawValue(previous); });
    QGCPalette palette;
    palette.setColorGroupEnabled(true);
    theme->setRawValue(0);
    theme->setRawValue(1);
    QVERIFY(!QGCPalette::highContrast());
    QCOMPARE(QGCPalette::globalTheme(), QGCPalette::Dark);
    QCOMPARE(palette.window(), QColor("#06131B"));
    const QPalette originalNativePalette = QGuiApplication::palette();
    theme->setRawValue(2);
    QVERIFY(QGCPalette::lightTheme());
    QVERIFY(!QGCPalette::highContrast());
    QCOMPARE(QGCPalette::globalTheme(), QGCPalette::Light);
    QCOMPARE(palette.window(), QColor("#ffffff"));
    QCOMPARE(palette.text(), QColor("#172B3A"));
    QCOMPARE(QGuiApplication::palette().color(QPalette::Window), palette.window());
    QCOMPARE(QGuiApplication::palette().color(QPalette::Text), palette.textFieldText());
    palette.setColorGroupEnabled(false);
    QCOMPARE(QGuiApplication::palette().color(QPalette::Disabled, QPalette::ButtonText), palette.buttonText());
    palette.setColorGroupEnabled(true);
    theme->setRawValue(0);
    QVERIFY(QGCPalette::highContrast());
    QVERIFY(!QGCPalette::lightTheme());
    QCOMPARE(palette.window(), QColor("#050A06"));
    QCOMPARE(QGuiApplication::palette(), originalNativePalette);
    theme->setRawValue(1);
    QVERIFY(!QGCPalette::lightTheme());
    QVERIFY(!QGCPalette::highContrast());
    QCOMPARE(palette.window(), QColor("#06131B"));
    QCOMPARE(QGuiApplication::palette(), originalNativePalette);
}

UT_REGISTER_TEST(QGCPaletteTest, TestLabel::Unit)