import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options?.bar?.borderless ?? false
    property bool alwaysShow: false
    property int useShortenedForm: 0

    readonly property bool enabled: Config.options?.bar?.codexUsage?.enable ?? true
    readonly property bool showFiveHour: Config.options?.bar?.codexUsage?.showFiveHour ?? true
    readonly property bool showWeekly: Config.options?.bar?.codexUsage?.showWeekly ?? true
    readonly property int warningThreshold: Config.options?.bar?.codexUsage?.warningThreshold ?? 90
    readonly property int cautionThreshold: Config.options?.bar?.codexUsage?.cautionThreshold ?? 75

    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: true
    visible: enabled && (alwaysShow || useShortenedForm < 2) && (showFiveHour || showWeekly)

    Component.onCompleted: CodexUsage.keepAlive()
    Component.onDestruction: CodexUsage.releaseKeepAlive()

    function usedFraction(window): real {
        if (!window)
            return 0
        if (window.used_percent !== undefined && window.used_percent !== null) {
            const u = Number(window.used_percent)
            if (isFinite(u))
                return Math.max(0, Math.min(1, u / 100))
        }
        if (window.remaining_percent !== undefined && window.remaining_percent !== null) {
            const r = Number(window.remaining_percent)
            if (isFinite(r))
                return Math.max(0, Math.min(1, 1 - r / 100))
        }
        return 0
    }

    RowLayout {
        id: rowLayout
        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        // Primary window (plugin labels as 5h; API may map differently by plan)
        Resource {
            iconName: "auto_awesome"
            customIcon: "openai-symbolic"
            percentage: root.usedFraction(CodexUsage.fiveHour)
            shown: root.showFiveHour && (CodexUsage.hasFiveHour || CodexUsage.requesting || CodexUsage.error.length > 0)
            warningThreshold: root.warningThreshold
            cautionThreshold: root.cautionThreshold
        }

        Resource {
            // Second ring keeps calendar when weekly data exists (primary already uses OpenAI mark)
            iconName: "calendar_month"
            percentage: root.usedFraction(CodexUsage.weekly)
            shown: root.showWeekly && CodexUsage.hasWeekly
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: root.warningThreshold
            cautionThreshold: root.cautionThreshold
        }
    }

    CodexUsagePopup {
        hoverTarget: root
    }
}
