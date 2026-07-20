import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RippleButton {
    id: root
    required property string materialSymbol
    required property bool current
    property bool showLabel: true
    horizontalPadding: 10

    implicitHeight: (Appearance.inirEverywhere || Appearance.angelEverywhere) ? 32 : 40
    readonly property real _iconOnlyImplicitWidth: icon.implicitWidth + horizontalPadding * 2
    implicitWidth: root.showLabel ? (implicitContentWidth + horizontalPadding * 2) : root._iconOnlyImplicitWidth
    buttonRadius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
        : Appearance.inirEverywhere ? Appearance.inir.roundingSmall : height / 2

    colBackground: "transparent"
    colBackgroundHover: current ? "transparent" 
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : Appearance.inirEverywhere ? ColorUtils.transparentize(Appearance.inir.colText, 0.92)
        : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.95)
    colRipple: current ? "transparent" 
        : Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
        : Appearance.inirEverywhere ? ColorUtils.transparentize(Appearance.inir.colText, 0.85)
        : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.95)

    contentItem: Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: root.showLabel ? 6 : 0

        Behavior on spacing {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
        }

        MaterialSymbol {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            iconSize: 22
            text: root.materialSymbol
            color: Appearance.angelEverywhere
                ? (root.current ? Appearance.angel.colOnPrimary : Appearance.angel.colText)
                : Appearance.inirEverywhere
                ? (root.current ? Appearance.inir.colOnPrimary : Appearance.inir.colText)
                : Appearance.m3colors.m3onSurface
        }
        Item {
            id: labelReveal
            anchors.verticalCenter: parent.verticalCenter
            width: root.showLabel ? labelText.implicitWidth : 0
            implicitWidth: width
            implicitHeight: labelText.implicitHeight
            opacity: root.showLabel ? 1 : 0
            visible: opacity > 0
            clip: true

            Behavior on width {
                enabled: Appearance.animationsEnabled
                animation: NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
            }
            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }

            StyledText {
                id: labelText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                color: Appearance.angelEverywhere
                    ? (root.current ? Appearance.angel.colOnPrimary : Appearance.angel.colText)
                    : Appearance.inirEverywhere
                    ? (root.current ? Appearance.inir.colOnPrimary : Appearance.inir.colText)
                    : Appearance.m3colors.m3onSurface
            }
        }
    }
}
