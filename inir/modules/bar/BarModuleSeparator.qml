import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property color lineColor: Appearance.inirEverywhere
        ? Appearance.inir.colBorderSubtle
        : Appearance.colors.colOutlineVariant

    Layout.alignment: Qt.AlignVCenter
    implicitWidth: 13
    implicitHeight: Appearance.sizes.barHeight

    Rectangle {
        anchors.centerIn: parent
        width: 1
        height: Math.max(0, parent.height - (Appearance.sizes.baseBarHeight / 3) * 2)
        color: root.lineColor
    }
}
