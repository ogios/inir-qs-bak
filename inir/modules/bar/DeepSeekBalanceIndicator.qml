import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root

    property bool alwaysShow: false
    property int useShortenedForm: 0

    readonly property bool enabled: Config.options?.bar?.deepseekBalance?.enable ?? true

    readonly property color textColor: root.warning
        ? (Appearance.inirEverywhere ? Appearance.inir.colError : Appearance.colors.colError)
        : Appearance.colors.colOnLayer1

    readonly property bool warning: DeepSeekBalance.warning

    visible: enabled && (alwaysShow || useShortenedForm < 2)
    implicitWidth: pill.width + 4
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Component.onCompleted: DeepSeekBalance.keepAlive()
    Component.onDestruction: DeepSeekBalance.releaseKeepAlive()

    Behavior on implicitWidth {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: contentRow.implicitWidth + 12
        height: contentRow.implicitHeight + 8
        radius: height / 2
        scale: root.pressed ? 0.95 : 1.0
        color: {
            if (root.pressed) {
                if (Appearance.angelEverywhere) return Appearance.angel.colGlassCardActive
                if (Appearance.inirEverywhere) return Appearance.inir.colLayer2Active
                return Appearance.colors.colLayer1Active
            }
            if (root.containsMouse) {
                if (Appearance.angelEverywhere) return Appearance.angel.colGlassCard
                if (Appearance.inirEverywhere) return Appearance.inir.colLayer1Hover
                return Appearance.colors.colLayer1Hover
            }
            return "transparent"
        }

        Behavior on color {
            enabled: Appearance.animationsEnabled
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    RowLayout {
        id: contentRow
        anchors.centerIn: pill
        spacing: 4

        CustomIcon {
            Layout.alignment: Qt.AlignVCenter
            visible: !DeepSeekBalance.requesting
            width: Appearance.font.pixelSize.normal
            height: Appearance.font.pixelSize.normal
            source: "deepseek-symbolic"
            colorize: true
            color: root.textColor
        }
        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            visible: DeepSeekBalance.requesting
            text: "progress_activity"
            iconSize: Appearance.font.pixelSize.normal
            color: root.textColor

            RotationAnimation on rotation {
                loops: Animation.Infinite
                running: DeepSeekBalance.requesting && root.visible
                from: 0
                to: 360
                duration: 1200
            }
        }

        StyledText {
            text: DeepSeekBalance.displayBalance()
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: root.textColor
            Layout.alignment: Qt.AlignVCenter
        }
    }

    DeepSeekBalancePopup {
        hoverTarget: root
    }
}
