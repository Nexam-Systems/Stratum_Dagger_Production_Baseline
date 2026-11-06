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
    DECLARE_QGC_COLOR(windowTransparent,    "#F5FFFFFF", "#F5FFFFFF", "#F506131B", "#F506131B")
    DECLARE_QGC_COLOR(windowShadeLight,     "#F7F9FA", "#F7F9FA", "#263C48", "#183747")
    DECLARE_QGC_COLOR(windowShade,          "#EFF3F6", "#EFF3F6", "#0B1D27", "#0B1D27")
    DECLARE_QGC_COLOR(windowShadeDark,      "#DDE5EA", "#DDE5EA", "#030B10", "#030B10")
    // STRATUM: near-white body text on the dark stack, muted grey when disabled.
    DECLARE_QGC_COLOR(text,                 "#4D5F6C", "#172B3A", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(warningText,          "#934600", "#934600", "#FFB476", "#FFB476")
    DECLARE_QGC_COLOR(button,               "#E4E9ED", "#EFF3F6", "#172A34", "#102D43")
    DECLARE_QGC_COLOR(buttonBorder,         "#6A7E8C", "#526C7C", "#617886", "#498DB4")
    DECLARE_QGC_COLOR(buttonText,           "#4D5F6C", "#172B3A", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(buttonHighlight,      "#E4E9ED", "#006B82", "#2A3239", "#48D6FF")
    DECLARE_QGC_COLOR(buttonHighlightText,  "#4D5F6C", "#FFFFFF", "#2c2c2c", "#001622")
    DECLARE_QGC_COLOR(primaryButton,        "#E4E9ED", "#006B82", "#172A34", "#126555")
    DECLARE_QGC_COLOR(primaryButtonText,    "#4D5F6C", "#FFFFFF", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(textField,            "#EDF1F4", "#FFFFFF", "#172A34", "#071923")
    DECLARE_QGC_COLOR(textFieldText,        "#4D5F6C", "#172B3A", "#9FB1BE", "#F1F7FA")
    DECLARE_QGC_COLOR(mapButton,            "#E4E9ED", "#FFFFFF", "#585858", "#000000")
    DECLARE_QGC_COLOR(mapButtonHighlight,   "#E4E9ED", "#006B82", "#585858", "#be781c")
    DECLARE_QGC_COLOR(mapIndicator,         "#6A7E8C", "#805000", "#585858", "#be781c")
    DECLARE_QGC_COLOR(mapIndicatorChild,    "#6A7E8C", "#655238", "#585858", "#766043")
    DECLARE_QGC_COLOR(colorGreen,           "#166534", "#166534", "#00e04b", "#00e04b")
    DECLARE_QGC_COLOR(colorYellow,          "#765600", "#765600", "#ffff00", "#ffff00")
    DECLARE_QGC_COLOR(colorYellowGreen,     "#4D6415", "#4D6415", "#9dbe2f", "#9dbe2f")
    DECLARE_QGC_COLOR(colorOrange,          "#934600", "#934600", "#de8500", "#de8500")
    DECLARE_QGC_COLOR(colorRed,             "#B42318", "#B42318", "#f32836", "#f32836")
    DECLARE_QGC_COLOR(colorGrey,            "#526675", "#526675", "#bfbfbf", "#bfbfbf")
    DECLARE_QGC_COLOR(colorBlue,            "#1D4ED8", "#1D4ED8", "#536dff", "#536dff")
    DECLARE_QGC_COLOR(alertBackground,      "#FFF0CC", "#FFF0CC", "#eecc44", "#eecc44")
    DECLARE_QGC_COLOR(alertBorder,          "#906000", "#906000", "#808080", "#808080")
    DECLARE_QGC_COLOR(alertText,            "#172B3A", "#172B3A", "#000000", "#000000")
    DECLARE_QGC_COLOR(missionItemEditor,    "#EDF1F4", "#EFF7FA", "#585858", "#585d83")
    DECLARE_QGC_COLOR(toolStripHoverColor,  "#E4E9ED", "#D4E7ED", "#585858", "#585d83")
    DECLARE_QGC_COLOR(statusFailedText,     "#4D5F6C", "#B42318", "#707070", "#ffffff")
    DECLARE_QGC_COLOR(statusPassedText,     "#4D5F6C", "#166534", "#707070", "#ffffff")
    DECLARE_QGC_COLOR(statusPendingText,    "#4D5F6C", "#934600", "#707070", "#ffffff")
    DECLARE_QGC_COLOR(toolbarBackground,    "#FFFFFF", "#FFFFFF", "#FF06131B", "#FF06131B")
    DECLARE_QGC_COLOR(groupBorder,          "#6A7E8C", "#526C7C", "#263C48", "#285468")
    DECLARE_QGC_COLOR(modifiedParamValue,   "#934600", "#934600", "#de8500", "#de8500")

    // Darker cyan keeps the brand accent readable on white surfaces.
    DECLARE_QGC_COLOR(brandingPurple,      "#4D5F6C", "#005B70", "#48D6FF", "#48D6FF")
    DECLARE_QGC_COLOR(brandingBlue,        "#4D5F6C", "#1D4ED8", "#48D6FF", "#6045c5")
    DECLARE_QGC_COLOR(toolStripFGColor,    "#4D5F6C", "#172B3A", "#707070", "#ffffff")

    // Colors not affected by theming
    //                                                      Disabled     Enabled
    DECLARE_QGC_NONTHEMED_COLOR(photoCaptureButtonColor,    "#707070", "#ffffff")
    DECLARE_QGC_COLOR(videoCaptureButtonColor, "#A06868", "#B42318", "#f89a9e", "#f32836")

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
