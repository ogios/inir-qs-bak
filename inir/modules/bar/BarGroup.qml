import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property real padding: 8
    readonly property bool cardStyleEverywhere: (Config.options?.dock?.cardStyle ?? false) && (Config.options?.sidebar?.cardStyle ?? false) && (Config.options?.bar?.cornerStyle === 3)
    implicitWidth: vertical ? Appearance.sizes.baseVerticalBarWidth : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight
    // Natural content width regardless of any implicitWidth override, so the bar
    // can size a pill to its content without a binding loop.
    readonly property real contentWidth: gridLayout.implicitWidth + padding * 2
    // True when the group has no visible children (Qt layouts exclude
    // visible:false items, so an all-hidden zone reports ~0 inner width). Lets
    // callers collapse the pill entirely instead of showing a ghost background.
    readonly property bool empty: gridLayout.implicitWidth < 1
    default property alias items: gridLayout.children

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        color: (Config.options?.bar?.borderless ?? false) ? "transparent"
            : (Appearance.angelEverywhere ? Appearance.angel.colGlassCard
              : Appearance.inirEverywhere ? Appearance.inir.colLayer1
              : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface 
              : Appearance.colors.colLayer1)
        border.width: Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth
                    : Appearance.inirEverywhere ? 1 : (root.cardStyleEverywhere ? 1 : 0)
        border.color: Appearance.angelEverywhere ? Appearance.angel.colCardBorder
                    : Appearance.inirEverywhere ? Appearance.inir.colBorder : Appearance.colors.colLayer0Border
        radius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
              : Appearance.inirEverywhere ? Appearance.inir.roundingNormal 
              : (root.cardStyleEverywhere ? Appearance.rounding.normal : Appearance.rounding.small)
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors {
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            horizontalCenter: parent.horizontalCenter
            top: root.vertical ? parent.top : undefined
            bottom: root.vertical ? parent.bottom : undefined
            margins: root.padding
        }
        columnSpacing: 4
        rowSpacing: 12
    }
}