import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool borderless: Config.options?.bar?.borderless ?? false
    property bool showDate: Config.options?.bar?.verbose ?? true
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.angelEverywhere ? Appearance.angel.colText
                : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
            text: DateTime.timeDisplay
        }

        Revealer {
            reveal: root.showDate
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
                    : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
                text: "•"
            }
        }

        Revealer {
            reveal: root.showDate
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.angelEverywhere ? Appearance.angel.colText
                    : Appearance.inirEverywhere ? Appearance.inir.colText : Appearance.colors.colOnLayer1
                text: DateTime.date
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        ClockWidgetTooltip {
            hoverTarget: mouseArea
        }
    }
}
