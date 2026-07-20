pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    // Native annotation editor (Edit action). Lives in this Scope so it survives
    // the selection overlay dismissing.
    Loader {
        active: GlobalStates.annotationEditorOpen
        sourceComponent: AnnotationEditor {}
    }

    function screenshot() {
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options?.search?.imageSearch?.useCircleSelection ?? false) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function record() {
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function recordWithSound() {
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function menu() {
        // Unified snip entry point: open the selector with a neutral default; the
        // in-overlay toolbar lets the user switch action/scope on the fly.
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    IpcHandler {
        target: "region"

        function screenshot(): void {
            root.screenshot()
        }
        function search(): void {
            root.search()
        }
        function googleLens(): void {
            root.search()
        }
        function ocr(): void {
            root.ocr()
        }
        function record(): void {
            root.record()
        }
        function recordWithSound(): void {
            root.recordWithSound()
        }
        function menu(): void {
            root.menu()
        }
    }

    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Item {
            GlobalShortcut {
                name: "regionScreenshot"
                description: "Takes a screenshot of the selected region"
                onPressed: root.screenshot()
            }
            GlobalShortcut {
                name: "regionSearch"
                description: "Searches the selected region"
                onPressed: root.search()
            }
            GlobalShortcut {
                name: "regionOcr"
                description: "Recognizes text in the selected region"
                onPressed: root.ocr()
            }
            GlobalShortcut {
                name: "regionRecord"
                description: "Records the selected region"
                onPressed: root.record()
            }
            GlobalShortcut {
                name: "regionRecordWithSound"
                description: "Records the selected region with sound"
                onPressed: root.recordWithSound()
            }
            GlobalShortcut {
                name: "regionMenu"
                description: "Opens the unified snip menu"
                onPressed: root.menu()
            }
        }
    }
}
