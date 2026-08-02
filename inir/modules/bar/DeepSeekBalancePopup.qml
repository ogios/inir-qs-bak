import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: popup

    onActiveChanged: {
        if (popup.active)
            DeepSeekBalance.ensureRunning()
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
            customIcon: "deepseek-symbolic"
            label: Translation.tr("DeepSeek Balance")
        }

        Column {
            spacing: 4
            visible: !DeepSeekBalance.ok
            InfoItem {
                icon: "error"
                label: Translation.tr("Status:")
                value: DeepSeekBalance.requesting
                    ? Translation.tr("Requesting…")
                    : (DeepSeekBalance.error || Translation.tr("Unavailable"))
            }
        }

        Column {
            spacing: 4
            visible: DeepSeekBalance.ok

            InfoItem {
                icon: "account_balance_wallet"
                label: Translation.tr("Total balance:")
                value: DeepSeekBalance.hasBalance ? DeepSeekBalance.formatBalance(DeepSeekBalance.totalBalance) : "--"
            }
            InfoItem {
                icon: "savings"
                label: Translation.tr("Topped-up:")
                value: DeepSeekBalance.hasBalance ? DeepSeekBalance.formatBalance(DeepSeekBalance.toppedUpBalance) : "--"
            }
            InfoItem {
                icon: "redeem"
                label: Translation.tr("Granted:")
                value: DeepSeekBalance.hasBalance ? DeepSeekBalance.formatBalance(DeepSeekBalance.grantedBalance) : "--"
            }
            InfoItem {
                icon: "currency_exchange"
                label: Translation.tr("Currency:")
                value: DeepSeekBalance.currency || "--"
            }
            InfoItem {
                icon: DeepSeekBalance.isAvailable ? "check_circle" : "warning"
                label: Translation.tr("Availability:")
                value: Translation.tr(DeepSeekBalance.isAvailable ? "Available" : "Insufficient")
            }
            InfoItem {
                icon: "sync"
                label: Translation.tr("Next refresh:")
                value: {
                    void DeepSeekBalance._clockTick
                    if (DeepSeekBalance.requesting)
                        return Translation.tr("Requesting…")
                    return DeepSeekBalance.formatDuration((DeepSeekBalance.nextRequestAt || 0) - Math.floor(Date.now() / 1000))
                }
            }
        }
    }
}
