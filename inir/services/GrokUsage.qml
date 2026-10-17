pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Polls local Grok auth + cli-chat-proxy billing.
 * Publishes SuperGrok weekly credit usage for bar widgets.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.bar?.grokUsage?.enable ?? true
    readonly property int requestDelaySeconds: Math.max(5, Config.options?.bar?.grokUsage?.requestDelaySeconds ?? 60)
    readonly property string authFile: {
        const configured = Config.options?.bar?.grokUsage?.authFile ?? ""
        if (configured && configured.length > 0)
            return configured.replace(/^~(?=\/)/, Directories.homePath)
        return `${Directories.homePath}/.grok/auth.json`
    }
    readonly property string endpoint: Config.options?.bar?.grokUsage?.endpoint
        || "https://grok.com/rest/grok/credits"
    readonly property string scriptPath: FileUtils.trimFileProtocol(
        `${Directories.scriptPath}/grok/fetch_usage.py`
    )

    property bool ok: false
    property bool stale: false
    property bool requesting: false
    property string error: ""
    property string subscriptionTier: ""
    property int checkedAt: 0
    property int nextRequestAt: 0

    property string periodType: ""
    property string periodStart: ""
    property string periodEnd: ""
    property var periodEndAt: null
    property var usedPercent: null
    property var remainingPercent: null
    property var products: []
    property bool unifiedBilling: false
    property var prepaidBalance: null
    property var onDemandCap: null
    property string topUpMethod: ""
    property string billingPeriodStart: ""
    property string billingPeriodEnd: ""

    readonly property real usedFraction: _fraction(usedPercent)
    readonly property bool hasUsage: usedPercent !== null && usedPercent !== undefined && isFinite(Number(usedPercent))
    readonly property bool available: ok && hasUsage
    readonly property bool billingPeriodDiffers: {
        if (billingPeriodStart.length === 0 && billingPeriodEnd.length === 0)
            return false
        return billingPeriodStart !== periodStart || billingPeriodEnd !== periodEnd
    }

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

    function resetRemainingSeconds(): var {
        root._clockTick // dependency for live countdown
        if (periodEndAt === undefined || periodEndAt === null)
            return null
        const resetAt = Number(periodEndAt)
        if (!isFinite(resetAt))
            return null
        return resetAt - Math.floor(Date.now() / 1000)
    }

    function formatPercent(value): string {
        const n = Number(value)
        if (!isFinite(n))
            return "--%"
        const clamped = Math.max(0, Math.min(100, n))
        const rounded = Math.round(clamped * 10) / 10
        if (Math.abs(rounded - Math.round(rounded)) < 0.05)
            return `${Math.round(rounded)}%`
        return `${rounded.toFixed(1)}%`
    }

    function formatAmount(value): string {
        const n = Number(value)
        if (!isFinite(n))
            return "--"
        if (Math.abs(n - Math.round(n)) < 0.001)
            return `${Math.round(n)}`
        return `${Math.round(n * 100) / 100}`
    }

    function _fraction(value): real {
        if (value === undefined || value === null)
            return 0
        const n = Number(value)
        if (!isFinite(n))
            return 0
        return Math.max(0, Math.min(1, n / 100))
    }

    function _applyPayload(data): void {
        root.checkedAt = Number(data.checked_at) || Math.floor(Date.now() / 1000)
        // Schedule from wall clock so stale snapshots (old checked_at) do not tight-loop.
        root.nextRequestAt = Math.floor(Date.now() / 1000) + root.requestDelaySeconds
        root.ok = !!data.ok
        root.stale = !!data.stale
        root.subscriptionTier = data.subscription_tier ? String(data.subscription_tier) : ""
        root.error = (!data.ok || data.stale) ? String(data.error || (data.ok ? "" : "unknown error")) : ""
        root.periodType = data.period_type ? String(data.period_type) : ""
        root.periodStart = data.period_start ? String(data.period_start) : ""
        root.periodEnd = data.period_end ? String(data.period_end) : ""
        root.periodEndAt = (data.period_end_at === undefined || data.period_end_at === null)
            ? null : Number(data.period_end_at)
        root.usedPercent = (data.used_percent === undefined || data.used_percent === null)
            ? null : Number(data.used_percent)
        root.remainingPercent = (data.remaining_percent === undefined || data.remaining_percent === null)
            ? null : Number(data.remaining_percent)
        root.products = Array.isArray(data.products) ? data.products : []
        root.unifiedBilling = !!data.unified_billing
        root.prepaidBalance = (data.prepaid_balance === undefined || data.prepaid_balance === null)
            ? null : Number(data.prepaid_balance)
        root.onDemandCap = (data.on_demand_cap === undefined || data.on_demand_cap === null)
            ? null : Number(data.on_demand_cap)
        root.topUpMethod = data.top_up_method ? String(data.top_up_method) : ""
        root.billingPeriodStart = data.billing_period_start ? String(data.billing_period_start) : ""
        root.billingPeriodEnd = data.billing_period_end ? String(data.billing_period_end) : ""
        root._syncTimers()
        if (!root.ok || root.stale)
            console.warn("[GrokUsage]", root.stale ? "stale:" : "failed:", root.error)
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
                    console.warn("[GrokUsage] stderr:", err)
            }
        }
        onExited: (code) => {
            if (code !== 0)
                console.warn("[GrokUsage] process exit", code)
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
                root._maybeRefresh()
        }
    }

    onEnabledChanged: {
        root._syncTimers()
        if (root.enabled && root._persistentConsumers > 0)
            root._maybeRefresh()
    }
}
