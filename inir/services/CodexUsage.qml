pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Polls local Codex auth + ChatGPT usage endpoint.
 * Publishes 5-hour / weekly remaining usage for bar widgets.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.bar?.codexUsage?.enable ?? true
    readonly property int requestDelaySeconds: Math.max(5, Config.options?.bar?.codexUsage?.requestDelaySeconds ?? 60)
    readonly property string authFile: {
        const configured = Config.options?.bar?.codexUsage?.authFile ?? ""
        if (configured && configured.length > 0)
            return configured.replace(/^~(?=\/)/, Directories.homePath)
        return `${Directories.homePath}/.codex/auth.json`
    }
    readonly property string endpoint: Config.options?.bar?.codexUsage?.endpoint
        || "https://chatgpt.com/backend-api/wham/usage"
    readonly property string scriptPath: FileUtils.trimFileProtocol(
        `${Directories.scriptPath}/codex/fetch_usage.py`
    )

    property bool ok: false
    property bool requesting: false
    property string error: ""
    property string planType: ""
    property string email: ""
    property bool allowed: true
    property bool limitReached: false
    property int checkedAt: 0
    property int nextRequestAt: 0

    // Window payloads: { used_percent, remaining_percent, reset_at, reset_after_seconds, limit_window_seconds }
    property var fiveHour: null
    property var weekly: null

    readonly property real fiveHourUsedPercentage: _usedFraction(fiveHour)
    readonly property real fiveHourRemainingPercentage: _remainingFraction(fiveHour)
    readonly property real weeklyUsedPercentage: _usedFraction(weekly)
    readonly property real weeklyRemainingPercentage: _remainingFraction(weekly)
    readonly property bool hasFiveHour: _windowHasData(fiveHour)
    readonly property bool hasWeekly: _windowHasData(weekly)
    readonly property bool available: ok && (hasFiveHour || hasWeekly)

    property int _clockTick: 0
    property int _persistentConsumers: 0
    property bool _runningRequested: false

    function keepAlive(): void {
        _persistentConsumers++
        _runningRequested = true
        _syncTimers()
        Qt.callLater(() => root._maybeRefresh())
    }

    function releaseKeepAlive(): void {
        _persistentConsumers = Math.max(0, _persistentConsumers - 1)
        if (_persistentConsumers === 0)
            _runningRequested = false
        _syncTimers()
    }

    function ensureRunning(): void {
        _runningRequested = true
        _syncTimers()
        Qt.callLater(() => root._maybeRefresh())
    }

    function _maybeRefresh(): void {
        if (!root.enabled || !Config.ready || fetchProc.running)
            return
        if ((_runningRequested || _persistentConsumers > 0) && Date.now() / 1000 >= nextRequestAt)
            refresh()
    }

    function refresh(): void {
        if (!root.enabled || fetchProc.running)
            return
        root.requesting = true
        fetchProc.command = [
            "/usr/bin/python3",
            root.scriptPath,
            "--auth-file", root.authFile,
            "--endpoint", root.endpoint,
            "--timeout", "30",
        ]
        fetchProc.running = true
    }

    function formatDuration(seconds): string {
        let total = Number(seconds)
        if (!isFinite(total))
            return "--"
        total = Math.max(0, Math.floor(total))
        const days = Math.floor(total / 86400)
        total %= 86400
        const hours = Math.floor(total / 3600)
        total %= 3600
        const minutes = Math.floor(total / 60)
        const secs = total % 60
        if (days > 0)
            return `${days}d ${hours}h`
        if (hours > 0)
            return `${hours}h ${minutes}m`
        if (minutes > 0)
            return `${minutes}m ${secs}s`
        return `${secs}s`
    }

    function resetRemainingSeconds(window): var {
        root._clockTick // dependency for live countdown
        if (!window || window.reset_at === undefined || window.reset_at === null)
            return null
        const resetAt = Number(window.reset_at)
        if (!isFinite(resetAt))
            return null
        return resetAt - Math.floor(Date.now() / 1000)
    }

    function formatPercent(value): string {
        const n = Number(value)
        if (!isFinite(n))
            return "--%"
        return `${Math.round(Math.max(0, Math.min(100, n)))}%`
    }

    function _windowHasData(window): bool {
        if (!window)
            return false
        if (window.remaining_percent !== undefined && window.remaining_percent !== null && isFinite(Number(window.remaining_percent)))
            return true
        if (window.used_percent !== undefined && window.used_percent !== null && isFinite(Number(window.used_percent)))
            return true
        return false
    }

    function _usedFraction(window): real {
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

    function _remainingFraction(window): real {
        if (!window)
            return 0
        if (window.remaining_percent !== undefined && window.remaining_percent !== null) {
            const r = Number(window.remaining_percent)
            if (isFinite(r))
                return Math.max(0, Math.min(1, r / 100))
        }
        if (window.used_percent !== undefined && window.used_percent !== null) {
            const u = Number(window.used_percent)
            if (isFinite(u))
                return Math.max(0, Math.min(1, 1 - u / 100))
        }
        return 0
    }

    function _applyPayload(data): void {
        root.checkedAt = Number(data.checked_at) || Math.floor(Date.now() / 1000)
        root.nextRequestAt = root.checkedAt + root.requestDelaySeconds
        root.ok = !!data.ok
        root.error = data.ok ? "" : String(data.error || "unknown error")
        root.planType = data.plan_type ? String(data.plan_type) : ""
        root.email = data.email ? String(data.email) : ""
        root.allowed = data.allowed !== false
        root.limitReached = !!data.limit_reached
        root.fiveHour = data.five_hour || null
        root.weekly = data.weekly || null
        root._syncTimers()
        if (!root.ok)
            console.warn("[CodexUsage] failed:", root.error)
    }

    function _syncTimers(): void {
        const shouldRun = root.enabled && Config.ready && (_runningRequested || _persistentConsumers > 0)
        pollTimer.running = shouldRun
        clockTimer.running = shouldRun
    }

    Process {
        id: fetchProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const payload = text.trim()
                root.requesting = false
                if (payload.length === 0) {
                    root.ok = false
                    root.error = "empty usage response"
                    root.nextRequestAt = Math.floor(Date.now() / 1000) + root.requestDelaySeconds
                    return
                }
                try {
                    root._applyPayload(JSON.parse(payload))
                } catch (e) {
                    root.ok = false
                    root.error = `parse error: ${e.message || e}`
                    root.nextRequestAt = Math.floor(Date.now() / 1000) + root.requestDelaySeconds
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = text.trim()
                if (err.length > 0)
                    console.warn("[CodexUsage] stderr:", err)
            }
        }
        onExited: (code) => {
            if (code !== 0)
                console.warn("[CodexUsage] process exit", code)
            if (root.requesting) {
                root.requesting = false
                if (!root.ok && root.error.length === 0)
                    root.error = `fetch exited with code ${code}`
                root.nextRequestAt = Math.floor(Date.now() / 1000) + root.requestDelaySeconds
            }
        }
    }

    Component.onCompleted: root._syncTimers()

    Timer {
        id: pollTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            if (!root.enabled || fetchProc.running)
                return
            const now = Date.now() / 1000
            if (now >= root.nextRequestAt)
                root.refresh()
        }
    }

    Timer {
        id: clockTimer
        interval: 1000
        repeat: true
        running: false
        onTriggered: root._clockTick++
    }

    Connections {
        target: Config
        function onReadyChanged() {
            root._syncTimers()
            if (Config.ready && root.enabled && root._persistentConsumers > 0)
                root.refresh()
        }
    }

    onEnabledChanged: {
        root._syncTimers()
        if (root.enabled && root._persistentConsumers > 0)
            root.refresh()
    }
}
