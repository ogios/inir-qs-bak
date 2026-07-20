import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    settingsPageIndex: 15
    settingsPageName: Translation.tr("Monitors")

    readonly property var iiSurfaces: [
        { title: Translation.tr("Bar"), description: Translation.tr("Top workspace bar, or the vertical bar when that mode is enabled"), icon: "web_asset", path: "bar.screenList" },
        { title: Translation.tr("Dock"), description: Translation.tr("Application dock and its hover reveal area"), icon: "call_to_action", path: "dock.screenList" },
        { title: Translation.tr("Media controls"), description: Translation.tr("Floating player popup opened from the bar or IPC"), icon: "music_note", path: "media.screenList" }
    ]
    readonly property var sharedSurfaces: [
        { title: Translation.tr("Notification popups"), description: Translation.tr("Transient notification toasts"), icon: "notifications", path: "notifications.screenList" },
        { title: Translation.tr("OSD indicators"), description: Translation.tr("Volume, brightness, media, and keyboard feedback"), icon: "volume_up", path: "osd.screenList" },
        { title: Translation.tr("Desktop widgets"), description: Translation.tr("Clock, weather, media, visualizer, and custom widgets"), icon: "widgets", path: "background.widgets.screenList" }
    ]

    function connectedScreenNames(): var {
        const screens = Quickshell.screens
        let names = []
        for (let i = 0; i < screens.length; i++) {
            const name = String(screens[i]?.name ?? "")
            if (name.length > 0 && !names.includes(name))
                names.push(name)
        }
        return names
    }

    function primaryScreenName(): string {
        const preferred = Config.options?.display?.primaryMonitor ?? ""
        const names = connectedScreenNames()
        if (preferred && names.includes(preferred))
            return preferred
        return names.length > 0 ? names[0] : ""
    }

    function monitorOptions(): var {
        let opts = [{ displayName: Translation.tr("Auto (first available)"), icon: "auto_mode", value: "" }]
        const names = connectedScreenNames()
        for (let i = 0; i < names.length; i++)
            opts.push({ displayName: names[i], icon: "monitor", value: names[i] })
        return opts
    }

    function monitorResolution(screen: var): string {
        const width = screen?.width ?? 0
        const height = screen?.height ?? 0
        if (width <= 0 || height <= 0)
            return Translation.tr("Resolution unknown")
        return width + "×" + height
    }

    function configuredScreens(path: string): var {
        const raw = Config.getNestedValue(path, [])
        const names = connectedScreenNames()
        let selected = []
        for (let i = 0; i < (raw?.length ?? 0); i++) {
            const name = String(raw[i] ?? "")
            if (name.length > 0 && names.includes(name) && !selected.includes(name))
                selected.push(name)
        }
        return selected
    }

    function allScreensEnabled(path: string): bool {
        const raw = Config.getNestedValue(path, [])
        return !raw || raw.length === 0
    }

    function surfaceEnabled(path: string, screenName: string): bool {
        if (allScreensEnabled(path))
            return true
        return configuredScreens(path).includes(screenName)
    }

    function visibilitySummary(path: string): string {
        if (allScreensEnabled(path))
            return Translation.tr("All monitors")
        const selected = configuredScreens(path)
        if (selected.length === 0)
            return Translation.tr("Saved outputs missing")
        if (selected.length === 1)
            return selected[0]
        return selected.length + Translation.tr(" monitors")
    }

    function setSurfaceAll(path: string): void {
        Config.setNestedValue(path, [])
    }

    function setSurfaceScreen(path: string, screenName: string, enabled: bool): void {
        const names = connectedScreenNames()
        if (!screenName || names.length === 0)
            return

        let current = configuredScreens(path)
        if (current.length === 0 && !enabled)
            current = names.slice()

        if (enabled) {
            if (!current.includes(screenName))
                current.push(screenName)
        } else {
            if (current.length <= 1 && current.includes(screenName))
                return
            current = current.filter(name => name !== screenName)
        }

        if (names.length > 0 && names.every(name => current.includes(name)))
            current = []
        Config.setNestedValue(path, current)
    }

    function setPathsToPrimary(paths: var): void {
        const primary = primaryScreenName()
        if (!primary)
            return
        let updates = {}
        for (let i = 0; i < paths.length; i++)
            updates[paths[i]] = [primary]
        Config.setNestedValues(updates)
    }

    function setPathsToAll(paths: var): void {
        let updates = {}
        for (let i = 0; i < paths.length; i++)
            updates[paths[i]] = []
        Config.setNestedValues(updates)
    }

    function surfacePaths(surfaces: var): var {
        let paths = []
        for (let i = 0; i < surfaces.length; i++)
            paths.push(surfaces[i].path)
        return paths
    }

    component PresetActions: RowLayout {
        required property var paths
        Layout.fillWidth: true
        spacing: Appearance.sizes.spacingSmall

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "filter_1"
            mainText: Translation.tr("Primary only")
            onClicked: root.setPathsToPrimary(paths)
            StyledToolTip {
                text: Translation.tr("Restrict this whole group to the primary monitor.")
            }
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            materialIcon: "select_all"
            mainText: Translation.tr("Show everywhere")
            onClicked: root.setPathsToAll(paths)
            StyledToolTip {
                text: Translation.tr("Clear monitor restrictions for this whole group.")
            }
        }
    }

    component MonitorInfoRow: Rectangle {
        required property var monitor
        required property int index
        readonly property string screenName: monitor?.name ?? ""
        readonly property bool primary: screenName === root.primaryScreenName()

        Layout.fillWidth: true
        implicitHeight: rowLayout.implicitHeight + Appearance.sizes.spacingMedium
        radius: Appearance.rounding.small
        color: primary ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
        border.width: 1
        border.color: primary ? Appearance.colors.colPrimary : SettingsMaterialPreset.groupBorderColor

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.margins: Appearance.sizes.spacingSmall
            spacing: Appearance.sizes.spacingMedium

            MaterialSymbol {
                text: "monitor"
                iconSize: Appearance.font.pixelSize.hugeass
                color: primary ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: screenName || (Translation.tr("Monitor ") + (index + 1))
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: primary ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.monitorResolution(monitor)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: primary ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                    opacity: primary ? 0.78 : 1
                    elide: Text.ElideRight
                }
            }

            StyledText {
                visible: primary
                text: Translation.tr("Primary")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colOnPrimaryContainer
                Layout.alignment: Qt.AlignVCenter
            }

            RippleButtonWithIcon {
                visible: !primary
                materialIcon: "low_priority"
                mainText: Translation.tr("Make primary")
                onClicked: if (screenName.length > 0) Config.setNestedValue("display.primaryMonitor", screenName)
            }
        }
    }

    component SurfaceVisibilityBlock: Rectangle {
        required property var surface
        readonly property real leadingWidth: Appearance.font.pixelSize.hugeass + Appearance.sizes.spacingLarge
        readonly property bool allOutputs: root.allScreensEnabled(surface.path)

        Layout.fillWidth: true
        implicitHeight: surfaceLayout.implicitHeight + Appearance.sizes.spacingLarge * 2
        radius: Appearance.rounding.small
        color: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
            : Appearance.inirEverywhere ? Appearance.inir.colLayer1
            : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurface
            : Appearance.colors.colLayer1
        border.width: Appearance.angelEverywhere ? Appearance.angel.cardBorderWidth : 1
        border.color: SettingsMaterialPreset.groupBorderColor

        ColumnLayout {
            id: surfaceLayout
            anchors.fill: parent
            anchors.margins: Appearance.sizes.spacingLarge
            spacing: Appearance.sizes.spacingSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.spacingMedium

                Rectangle {
                    implicitWidth: leadingWidth
                    implicitHeight: leadingWidth
                    radius: Appearance.rounding.small
                    color: allOutputs ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryContainer
                    Layout.alignment: Qt.AlignTop

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: surface.icon
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: allOutputs ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.sizes.spacingSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: surface.title
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            implicitWidth: summaryText.implicitWidth + Appearance.sizes.spacingMedium
                            implicitHeight: summaryText.implicitHeight + Appearance.sizes.spacingSmall
                            radius: Appearance.rounding.full
                            color: allOutputs ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryContainer
                            Layout.alignment: Qt.AlignVCenter

                            StyledText {
                                id: summaryText
                                anchors.centerIn: parent
                                text: root.visibilitySummary(surface.path)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: allOutputs ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: surface.description
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: leadingWidth + Appearance.sizes.spacingMedium
                text: Translation.tr("Visible on")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }

            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: leadingWidth + Appearance.sizes.spacingMedium
                spacing: Appearance.sizes.spacingSmall / 2

                SelectionGroupButton {
                    leftmost: true
                    rightmost: true
                    buttonIcon: "select_all"
                    buttonText: Translation.tr("All outputs")
                    toggled: allOutputs
                    onClicked: root.setSurfaceAll(surface.path)
                }

                Repeater {
                    model: root.connectedScreenNames()

                    SelectionGroupButton {
                        required property var modelData
                        readonly property string screenName: String(modelData ?? "")
                        leftmost: true
                        rightmost: true
                        buttonIcon: "monitor"
                        buttonText: screenName
                        toggled: root.surfaceEnabled(surface.path, screenName)
                        onClicked: root.setSurfaceScreen(surface.path, screenName, !toggled)
                    }
                }
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "settings_input_component"
        title: Translation.tr("Shell visibility")

        SettingsGroup {
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("This page controls where iNiR shell surfaces appear. It does not change monitor resolution, scale, rotation, or physical output layout.")
            }

            ContentSubsection {
                title: Translation.tr("Primary monitor")
                tooltip: Translation.tr("Used as the default output when a popup cannot infer the focused monitor.")

                ConfigSelectionArray {
                    currentValue: Config.options?.display?.primaryMonitor ?? ""
                    options: root.monitorOptions()
                    onSelected: newValue => Config.setNestedValue("display.primaryMonitor", newValue)
                }
            }

            ContentSubsection {
                title: Translation.tr("Connected outputs")

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.spacingSmall / 2

                    Repeater {
                        model: Quickshell.screens

                        MonitorInfoRow {
                            required property var modelData
                            monitor: modelData
                        }
                    }
                }
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "web_asset"
        title: Translation.tr("Material shell surfaces")

        SettingsGroup {
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "apps"
                text: Translation.tr("These controls only affect the Material family: the ii bar, dock, and floating media controls.")
            }

            PresetActions {
                paths: root.surfacePaths(root.iiSurfaces)
            }

            Repeater {
                model: root.iiSurfaces
                SurfaceVisibilityBlock {
                    required property var modelData
                    surface: modelData
                }
            }
        }
    }

    SettingsCardSection {
        expanded: true
        icon: "notifications"
        title: Translation.tr("Shared popups and widgets")

        SettingsGroup {
            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "merge"
                text: Translation.tr("These surfaces are shared by both families, so the same monitor choices apply in Material and Waffle.")
            }

            PresetActions {
                paths: root.surfacePaths(root.sharedSurfaces)
            }

            Repeater {
                model: root.sharedSurfaces
                SurfaceVisibilityBlock {
                    required property var modelData
                    surface: modelData
                }
            }
        }
    }
}
