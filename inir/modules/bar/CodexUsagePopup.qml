import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: popup

    onActiveChanged: {
        if (popup.active)
            CodexUsage.ensureRunning()
    }

    component InfoItem: RowLayout {
        id: infoItem
        required property string icon
        required property string label
        required property string value
        spacing: 4

        MaterialSymbol {
            text: infoItem.icon
            color: Appearance.colors.colOnSurfaceVariant
            iconSize: Appearance.font.pixelSize.large
        }
        StyledText {
            text: infoItem.label
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            visible: infoItem.value !== ""
            color: Appearance.colors.colOnSurfaceVariant
            text: infoItem.value
        }
    }

    component HeaderItem: Row {
        id: headerItem
        property string icon: ""
        property string customIcon: ""
        required property var label
        spacing: 5

        CustomIcon {
            anchors.verticalCenter: parent.verticalCenter
            visible: headerItem.customIcon.length > 0
            width: Appearance.font.pixelSize.large
            height: Appearance.font.pixelSize.large
            source: headerItem.customIcon
            colorize: true
            color: Appearance.colors.colOnSurfaceVariant
        }
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: headerItem.customIcon.length === 0
            fill: 0
            font.weight: Font.Medium
            text: headerItem.icon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: headerItem.label
            font {
                weight: Font.Medium
                pixelSize: Appearance.font.pixelSize.normal
            }
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 10

        HeaderItem {
            customIcon: "openai-symbolic"
            label: Translation.tr("Codex Usage")
        }

        Column {
            spacing: 4
            visible: !CodexUsage.ok
            InfoItem {
                icon: "error"
                label: Translation.tr("Status:")
                value: CodexUsage.requesting
                    ? Translation.tr("Requesting…")
                    : (CodexUsage.error || Translation.tr("Unavailable"))
            }
        }

        Column {
            spacing: 4
            visible: CodexUsage.ok

            InfoItem {
                icon: "bolt"
                label: Translation.tr("Primary left:")
                value: {
                    void CodexUsage._clockTick
                    if (!CodexUsage.hasFiveHour)
                        return "--"
                    const left = CodexUsage.formatPercent(CodexUsage.fiveHour?.remaining_percent)
                    const reset = CodexUsage.formatDuration(CodexUsage.resetRemainingSeconds(CodexUsage.fiveHour))
                    return `${left} · ${Translation.tr("resets in")} ${reset}`
                }
            }
            InfoItem {
                icon: "calendar_month"
                label: Translation.tr("Weekly left:")
                value: {
                    void CodexUsage._clockTick
                    if (!CodexUsage.hasWeekly)
                        return "--"
                    const left = CodexUsage.formatPercent(CodexUsage.weekly?.remaining_percent)
                    const reset = CodexUsage.formatDuration(CodexUsage.resetRemainingSeconds(CodexUsage.weekly))
                    return `${left} · ${Translation.tr("resets in")} ${reset}`
                }
            }
            InfoItem {
                icon: "workspace_premium"
                label: Translation.tr("Plan:")
                value: CodexUsage.planType || "--"
            }
            InfoItem {
                visible: Config.options?.bar?.codexUsage?.showAccount ?? false
                icon: "person"
                label: Translation.tr("Account:")
                value: CodexUsage.email || "--"
            }
            InfoItem {
                icon: "sync"
                label: Translation.tr("Next refresh:")
                value: {
                    void CodexUsage._clockTick
                    if (CodexUsage.requesting)
                        return Translation.tr("Requesting…")
                    return CodexUsage.formatDuration((CodexUsage.nextRequestAt || 0) - Math.floor(Date.now() / 1000))
                }
            }
            InfoItem {
                visible: CodexUsage.limitReached
                icon: "warning"
                label: Translation.tr("Limit:")
                value: Translation.tr("Reached")
            }
        }
    }
}
