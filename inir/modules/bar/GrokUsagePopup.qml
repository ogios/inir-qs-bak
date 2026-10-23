import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: popup

    onActiveChanged: {
        if (popup.active)
            GrokUsage.ensureRunning()
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
            customIcon: "grok-symbolic"
            label: Translation.tr("Grok usage")
        }

        Column {
            spacing: 4
            visible: !GrokUsage.ok
            InfoItem {
                icon: "error"
                label: Translation.tr("Status:")
                value: GrokUsage.requesting
                    ? Translation.tr("Requesting…")
                    : (GrokUsage.error || Translation.tr("Unavailable"))
            }
        }

        Column {
            spacing: 4
            visible: GrokUsage.ok

            InfoItem {
                visible: GrokUsage.stale
                icon: "cloud_off"
                label: Translation.tr("Live refresh:")
                value: GrokUsage.error
            }
            InfoItem {
                visible: GrokUsage.subscriptionTier.length > 0
                icon: "workspace_premium"
                label: Translation.tr("Plan:")
                value: GrokUsage.subscriptionTier
            }
            InfoItem {
                icon: "data_usage"
                label: Translation.tr("Used:")
                value: GrokUsage.hasUsage ? GrokUsage.formatPercent(GrokUsage.usedPercent) : "--"
            }
            InfoItem {
                icon: "calendar_month"
                label: Translation.tr("Weekly left:")
                value: {
                    void GrokUsage._clockTick
                    if (!GrokUsage.hasUsage)
                        return "--"
                    const left = GrokUsage.formatPercent(GrokUsage.remainingPercent)
                    const reset = GrokUsage.formatDuration(GrokUsage.resetRemainingSeconds())
                    return `${left} · ${Translation.tr("resets in")} ${reset}`
                }
            }
            InfoItem {
                icon: "schedule"
                label: Translation.tr("Period:")
                value: {
                    if (GrokUsage.periodStart.length === 0 && GrokUsage.periodEnd.length === 0)
                        return "--"
                    if (GrokUsage.periodStart.length === 0)
                        return GrokUsage.periodEnd
                    if (GrokUsage.periodEnd.length === 0)
                        return GrokUsage.periodStart
                    return `${GrokUsage.periodStart} → ${GrokUsage.periodEnd}`
                }
            }
            InfoItem {
                visible: GrokUsage.periodType.length > 0
                icon: "event_repeat"
                label: Translation.tr("Period type:")
                value: GrokUsage.periodType
            }

            Repeater {
                model: GrokUsage.products
                delegate: InfoItem {
                    required property var modelData
                    icon: "category"
                    label: (modelData.product || Translation.tr("Product")) + ":"
                    value: GrokUsage.formatPercent(modelData.usage_percent)
                }
            }

            InfoItem {
                visible: GrokUsage.prepaidBalance !== null && GrokUsage.prepaidBalance !== undefined
                icon: "account_balance_wallet"
                label: Translation.tr("Prepaid balance:")
                value: GrokUsage.formatAmount(GrokUsage.prepaidBalance)
            }
            InfoItem {
                visible: GrokUsage.onDemandCap !== null && GrokUsage.onDemandCap !== undefined
                icon: "payments"
                label: Translation.tr("On-demand cap:")
                value: GrokUsage.formatAmount(GrokUsage.onDemandCap)
            }
            InfoItem {
                icon: "receipt_long"
                label: Translation.tr("Unified billing:")
                value: GrokUsage.unifiedBilling ? Translation.tr("Yes") : Translation.tr("No")
            }
            InfoItem {
                visible: GrokUsage.topUpMethod.length > 0
                icon: "credit_card"
                label: Translation.tr("Top-up:")
                value: GrokUsage.topUpMethod
            }
            InfoItem {
                visible: GrokUsage.billingPeriodDiffers
                icon: "date_range"
                label: Translation.tr("Billing period:")
                value: {
                    if (GrokUsage.billingPeriodStart.length === 0)
                        return GrokUsage.billingPeriodEnd
                    if (GrokUsage.billingPeriodEnd.length === 0)
                        return GrokUsage.billingPeriodStart
                    return `${GrokUsage.billingPeriodStart} → ${GrokUsage.billingPeriodEnd}`
                }
            }
            InfoItem {
                icon: "sync"
                label: Translation.tr("Next refresh:")
                value: {
                    void GrokUsage._clockTick
                    if (GrokUsage.requesting)
                        return Translation.tr("Requesting…")
                    return GrokUsage.formatDuration((GrokUsage.nextRequestAt || 0) - Math.floor(Date.now() / 1000))
                }
            }
        }
    }
}
