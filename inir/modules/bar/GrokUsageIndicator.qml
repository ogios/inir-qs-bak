import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options?.bar?.borderless ?? false
    property bool alwaysShow: false
    property int useShortenedForm: 0

    readonly property bool enabled: Config.options?.bar?.grokUsage?.enable ?? true
    readonly property int warningThreshold: Config.options?.bar?.grokUsage?.warningThreshold ?? 90
    readonly property int cautionThreshold: Config.options?.bar?.grokUsage?.cautionThreshold ?? 75

    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: true
    visible: enabled && (alwaysShow || useShortenedForm < 2)

    Component.onCompleted: GrokUsage.keepAlive()
    Component.onDestruction: GrokUsage.releaseKeepAlive()

    RowLayout {
        id: rowLayout
        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            iconName: "token"
            customIcon: "grok-symbolic"
            percentage: GrokUsage.usedFraction
            shown: GrokUsage.hasUsage || GrokUsage.requesting || GrokUsage.error.length > 0
            warningThreshold: root.warningThreshold
            cautionThreshold: root.cautionThreshold
        }
    }

    GrokUsagePopup {
        hoverTarget: root
    }
}
