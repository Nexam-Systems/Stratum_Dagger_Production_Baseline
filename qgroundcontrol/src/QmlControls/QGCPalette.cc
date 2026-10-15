#include "QGCPalette.h"
#include "QGCCorePlugin.h"

#include <QtCore/QDebug>

QList<QGCPalette*>   QGCPalette::_paletteObjects;

QGCPalette::Theme QGCPalette::_theme = QGCPalette::Dark;

QMap<int, QMap<int, QMap<QString, QColor>>> QGCPalette::_colorInfoMap;

QStringList QGCPalette::_colors;
bool QGCPalette::_highContrast = true;
QMap<QString, QColor> QGCPalette::_highContrastColors;

QGCPalette::QGCPalette(QObject* parent) :
    QObject(parent),
    _colorGroupEnabled(true)
{
    if (_colorInfoMap.isEmpty()) {
        _buildMap();
    }
    if (_highContrastColors.isEmpty()) setHighContrast(_highContrast);

    // We have to keep track of all QGCPalette objects in the system so we can signal theme change to all of them
    _paletteObjects += this;
}

QGCPalette::~QGCPalette()
{
    bool fSuccess = _paletteObjects.removeOne(this);
    if (!fSuccess) {
        qWarning() << "Internal error";
    }
}

void QGCPalette::_buildMap()
{
    // STRATUM tactical dark theme: unified signal-cyan accent (#48D6FF) on a deep-
    // graphite surface stack. Surface levels are spaced ~8-12 luminance steps apart so
    // panels, buttons and separators stay distinguishable in direct sunlight without
    // relying on drop shadows. Cyan replaces the earlier mint-green so the base palette
    // stays neutral and reserves warm/red hues for critical states (Engagement, Abort).
    //
    //                                      Light                 Dark
    //                                      Disabled   Enabled    Disabled   Enabled
    DECLARE_QGC_COLOR(window,               "#ffffff", "#ffffff", "#06131B", "#06131B")
    DECLARE_QGC_COLOR(windowTransparent,    "#ccffffff", "#ccffffff", "#F506131B", "#F506131B")
    DECLARE_QGC_COLOR(windowShadeLight,     "#909090", "#828282", "#263C48", "#183747")
    DECLARE_QGC_COLOR(windowShade,          "#d9d9d9", "#d9d9d9", "#0B1D27", "#0B1D27")
    DECLARE_QGC_COLOR(windowShadeDark,      "#bdbdbd", "#bdbdbd", "#030B10", "#030B10")
    // STRATUM: near-white body text on the dark stack, muted grey when disabled.
    DECLARE_QGC_COLOR(text,                 "#9d9d9d", "#333333", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(warningText,          "#cc0808", "#cc0808", "#FFB476", "#FFB476")
    DECLARE_QGC_COLOR(button,               "#ffffff", "#ffffff", "#172A34", "#102D43")
    DECLARE_QGC_COLOR(buttonBorder,         "#9d9d9d", "#9F9F00", "#617886", "#498DB4")
    DECLARE_QGC_COLOR(buttonText,           "#9d9d9d", "#333333", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(buttonHighlight,      "#e4e4e4", "#9F9F00", "#2A3239", "#48D6FF")
    DECLARE_QGC_COLOR(buttonHighlightText,  "#2c2c2c", "#ffffff", "#2c2c2c", "#001622")
    DECLARE_QGC_COLOR(primaryButton,        "#585858", "#8cb3be", "#172A34", "#126555")
    DECLARE_QGC_COLOR(primaryButtonText,    "#2c2c2c", "#333333", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(textField,            "#ffffff", "#ffffff", "#172A34", "#071923")
    DECLARE_QGC_COLOR(textFieldText,        "#808080", "#333333", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(mapButton,            "#585858", "#333333", "#585858", "#000000")
    DECLARE_QGC_COLOR(mapButtonHighlight,   "#585858", "#be781c", "#585858", "#be781c")
    DECLARE_QGC_COLOR(mapIndicator,         "#585858", "#be781c", "#585858", "#be781c")
    DECLARE_QGC_COLOR(mapIndicatorChild,    "#585858", "#766043", "#585858", "#766043")
    DECLARE_QGC_COLOR(colorGreen,           "#008f2d", "#008f2d", "#00e04b", "#00e04b")
    DECLARE_QGC_COLOR(colorYellow,          "#a2a200", "#a2a200", "#ffff00", "#ffff00")
    DECLARE_QGC_COLOR(colorYellowGreen,     "#799f26", "#799f26", "#9dbe2f", "#9dbe2f")
    DECLARE_QGC_COLOR(colorOrange,          "#bf7539", "#bf7539", "#de8500", "#de8500")
    DECLARE_QGC_COLOR(colorRed,             "#b52b2b", "#b52b2b", "#f32836", "#f32836")
    DECLARE_QGC_COLOR(colorGrey,            "#808080", "#808080", "#bfbfbf", "#bfbfbf")
    DECLARE_QGC_COLOR(colorBlue,            "#1a72ff", "#1a72ff", "#536dff", "#536dff")
    DECLARE_QGC_COLOR(alertBackground,      "#eecc44", "#eecc44", "#eecc44", "#eecc44")
    DECLARE_QGC_COLOR(alertBorder,          "#808080", "#808080", "#808080", "#808080")
    DECLARE_QGC_COLOR(alertText,            "#000000", "#000000", "#000000", "#000000")
    DECLARE_QGC_COLOR(missionItemEditor,    "#585858", "#dbfef8", "#585858", "#585d83")
    DECLARE_QGC_COLOR(toolStripHoverColor,  "#585858", "#9D9D9D", "#585858", "#585d83")
    DECLARE_QGC_COLOR(statusFailedText,     "#9d9d9d", "#000000", "#707070", "#ffffff")
    DECLARE_QGC_COLOR(statusPassedText,     "#9d9d9d", "#000000", "#707070", "#ffffff")
    DECLARE_QGC_COLOR(statusPendingText,    "#9d9d9d", "#000000", "#707070", "#ffffff")
    DECLARE_QGC_COLOR(toolbarBackground,    "#00ffffff", "#00ffffff", "#FF06131B", "#FF06131B")
    DECLARE_QGC_COLOR(groupBorder,          "#bbbbbb", "#9F9F00", "#263C48", "#285468")
    DECLARE_QGC_COLOR(modifiedParamValue,   "#bf7539", "#bf7539", "#de8500", "#de8500")

    // Colors not affecting by theming
    //                                                      Disabled     Enabled
    DECLARE_QGC_NONTHEMED_COLOR(brandingPurple,             "#48D6FF", "#48D6FF")
    DECLARE_QGC_NONTHEMED_COLOR(brandingBlue,               "#48D6FF", "#6045c5")
    DECLARE_QGC_NONTHEMED_COLOR(toolStripFGColor,           "#707070", "#ffffff")
    DECLARE_QGC_NONTHEMED_COLOR(photoCaptureButtonColor,    "#707070", "#ffffff")
    DECLARE_QGC_NONTHEMED_COLOR(videoCaptureButtonColor,    "#f89a9e", "#f32836")

    // Colors not affecting by theming or enable/disable
    DECLARE_QGC_SINGLE_COLOR(mapWidgetBorderLight,          "#ffffff")
    DECLARE_QGC_SINGLE_COLOR(mapWidgetBorderDark,           "#000000")
    DECLARE_QGC_SINGLE_COLOR(mapMissionTrajectory,          "#be781c")
    DECLARE_QGC_SINGLE_COLOR(surveyPolygonInterior,         "green")
    DECLARE_QGC_SINGLE_COLOR(surveyPolygonTerrainCollision, "red")

}

QColor QGCPalette::_color(const QString &name) const
{
    if (!_highContrast) return _colorInfoMap[_theme][_colorGroupEnabled ? ColorGroupEnabled : ColorGroupDisabled][name];
    QColor color = _highContrastColors.value(name, _colorInfoMap[Dark][ColorGroupEnabled][name]);
    if (!_colorGroupEnabled) {
        if (name == "button" || name == "primaryButton" || name == "buttonHighlight") return QColor("#202420");
        if (name == "text" || name == "buttonText" || name == "primaryButtonText" || name == "buttonHighlightText") return QColor("#B5BDB0");
        if (name == "buttonBorder") return QColor("#7D8876");
    }
    return color;
}

void QGCPalette::setHighContrast(bool enabled)
{
    if (_highContrast == enabled && !_highContrastColors.isEmpty()) return;
    if (_highContrastColors.isEmpty()) {
        const QMap<QString, QString> colors = {
            {"window", "#050A06"}, {"windowTransparent", "#FF050A06"},
            {"windowShade", "#101910"}, {"windowShadeDark", "#000000"}, {"windowShadeLight", "#273324"},
            {"text", "#F5FFE9"}, {"warningText", "#FFD166"},
            {"button", "#0B160B"}, {"buttonText", "#D6FF85"}, {"buttonBorder", "#C5F779"},
            {"buttonHighlight", "#C5F779"}, {"buttonHighlightText", "#071007"},
            {"primaryButton", "#C5F779"}, {"primaryButtonText", "#071007"},
            {"textField", "#000000"}, {"textFieldText", "#F5FFE9"},
            {"mapButton", "#050A06"}, {"mapButtonHighlight", "#C5F779"},
            {"mapIndicator", "#FFD166"}, {"mapIndicatorChild", "#F5FFE9"},
            {"groupBorder", "#C5F779"}, {"toolbarBackground", "#050A06"},
            {"brandingPurple", "#C5F779"}, {"brandingBlue", "#C5F779"},
            {"toolStripFGColor", "#D6FF85"}, {"toolStripHoverColor", "#273324"},
            {"statusFailedText", "#FF9292"}, {"statusPassedText", "#D6FF85"}, {"statusPendingText", "#FFD166"},
            {"colorRed", "#FF7070"}, {"colorOrange", "#FFBC66"}, {"colorYellow", "#FFE680"},
            {"colorGreen", "#B4FF87"}, {"colorBlue", "#8EDCFF"}, {"colorGrey", "#BEC8B7"},
            {"alertBackground", "#FFD166"}, {"alertBorder", "#FFFFFF"}, {"alertText", "#071007"},
            {"missionItemEditor", "#101910"}, {"modifiedParamValue", "#FFD166"}
        };
        for (auto entry = colors.cbegin(); entry != colors.cend(); ++entry) _highContrastColors.insert(entry.key(), QColor(entry.value()));
    }
    _highContrast = enabled;
    _signalPaletteChangeToAll();
}

void QGCPalette::setColorGroupEnabled(bool enabled)
{
    _colorGroupEnabled = enabled;
    emit paletteChanged();
}

void QGCPalette::setGlobalTheme(Theme newTheme)
{
    // Mobile build does not have themes
    if (_theme != newTheme) {
        _theme = newTheme;
        _signalPaletteChangeToAll();
    }
}

void QGCPalette::_signalPaletteChangeToAll()
{
    // Notify all objects of the new theme
    for (QGCPalette *palette : std::as_const(_paletteObjects)) {
        palette->_signalPaletteChanged();
    }
}

void QGCPalette::_signalPaletteChanged()
{
    emit paletteChanged();
}
