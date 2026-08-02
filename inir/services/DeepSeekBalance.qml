pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Polls the DeepSeek /user/balance endpoint and publishes account balance
 * for bar widgets. API key is taken from --api-key, the api key file, or
 * the DEEPSEEK_API_KEY environment variable.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.bar?.deepseekBalance?.enable ?? true
    readonly property int requestDelaySeconds: Math.max(5, Config.options?.bar?.deepseekBalance?.requestDelaySeconds ?? 60)
    readonly property int fetchTimeoutSeconds: Math.max(5, Config.options?.bar?.deepseekBalance?.fetchTimeoutSeconds ?? 30)
    readonly property string apiKey: Config.options?.bar?.deepseekBalance?.apiKey ?? ""
    readonly property string apiKeyFile: {
        const configured = Config.options?.bar?.deepseekBalance?.apiKeyFile ?? ""
        if (configured && configured.length > 0)
            return configured.replace(/^~(?=\/)/, Directories.homePath)
        return `${Directories.homePath}/.deepseek/api_key`
    }
    readonly property string endpoint: Config.options?.bar?.deepseekBalance?.endpoint
        || "https://api.deepseek.com/user/balance"
    readonly property string preferredCurrency: (Config.options?.bar?.deepseekBalance?.preferredCurrency ?? "CNY").toUpperCase()
    readonly property bool showSymbol: Config.options?.bar?.deepseekBalance?.showSymbol ?? true
    readonly property real cautionBelow: Number(Config.options?.bar?.deepseekBalance?.cautionBelow ?? 50)
    readonly property real warningBelow: Number(Config.options?.bar?.deepseekBalance?.warningBelow ?? 20)
    readonly property string scriptPath: FileUtils.trimFileProtocol(
        `${Directories.scriptPath}/deepseek/fetch_balance.py`
    )

    property bool ok: false
    property bool requesting: false
    property string error: ""
    property bool isAvailable: false
    property int checkedAt: 0
    property int nextRequestAt: 0

    // balance_infos: [{ currency, total_balance, granted_balance, topped_up_balance }]
    property var balanceInfos: []

    // The entry matching preferredCurrency (falls back to the first entry).
    readonly property var currentInfo: root._pickInfo()

    readonly property bool hasBalance: ok && !!currentInfo
    readonly property string currency: currentInfo?.currency || ""
    readonly property real totalBalance: _asNumber(currentInfo?.total_balance)
    readonly property real grantedBalance: _asNumber(currentInfo?.granted_balance)
    readonly property real toppedUpBalance: _asNumber(currentInfo?.topped_up_balance)

    // Low-balance coloring for the bar widget.
    readonly property bool warning: hasBalance && (totalBalance < root.warningBelow || !isAvailable)
    readonly property bool caution: hasBalance && !warning && totalBalance < root.cautionBelow

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
            "--endpoint", root.endpoint,
            "--timeout", String(root.fetchTimeoutSeconds),
        ]
        if (root.apiKey.length > 0) {
            fetchProc.command.push("--api-key", root.apiKey)
        } else {
            fetchProc.command.push("--api-key-file", root.apiKeyFile)
        }
        fetchProc.running = true
        fetchTimeoutTimer.interval = root.fetchTimeoutSeconds * 1000
        fetchTimeoutTimer.start()
    }

    function _abortFetch(reason: string): void {
        if (!root.requesting)
            return
        fetchTimeoutTimer.stop()
        fetchProc.running = false
        root.requesting = false
        root.ok = false
        root.error = reason
        root.nextRequestAt = Math.floor(Date.now() / 1000) + root.requestDelaySeconds
        root._syncTimers()
        console.warn("[DeepSeekBalance] aborted:", reason)
    }

    function currencySymbol(): string {
        if (currency === "CNY")
            return "¥"
        if (currency === "USD")
            return "$"
        return currency
    }

    // Compact display for the bar, e.g. "¥110" or "110".
    function displayBalance(): string {
        if (!hasBalance)
            return "--"
        const value = root.showSymbol ? `${root.currencySymbol()}${_shortNumber(totalBalance)}` : _shortNumber(totalBalance)
        return value
    }

    function formatBalance(value): string {
        const n = _asNumber(value)
        if (!isFinite(n))
            return "--"
        const text = n.toLocaleString(Qt.locale(), "f", 2)
        return root.showSymbol ? `${root.currencySymbol()}${text}` : text
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

    function _shortNumber(value): string {
        const n = _asNumber(value)
        if (!isFinite(n))
            return "--"
        if (n >= 1000)
            return `${(n / 1000).toFixed(1)}k`
        return String(Math.round(n * 100) / 100)
    }

    function _pickInfo(): var {
        if (!root.ok || !root.balanceInfos || root.balanceInfos.length === 0)
            return null
        for (const info of root.balanceInfos) {
            if (String(info.currency || "").toUpperCase() === root.preferredCurrency)
                return info
        }
        return root.balanceInfos[0]
    }

    function _asNumber(value): real {
        const n = Number(value)
        return isFinite(n) ? n : NaN
    }

    function _applyPayload(data): void {
        root.checkedAt = Number(data.checked_at) || Math.floor(Date.now() / 1000)
        root.ok = !!data.ok
        root.error = data.ok ? "" : String(data.error || "unknown error")
        root.isAvailable = data.is_available !== false
        root.balanceInfos = Array.isArray(data.balance_infos) ? data.balance_infos : []
        root._scheduleRetry(!root.ok && root._isMissingKeyError(root.error))
        root._syncTimers()
        if (!root.ok)
            console.warn("[DeepSeekBalance] failed:", root.error)
    }

    function _isMissingKeyError(message): bool {
        return /api key/i.test(String(message || ""))
    }

    // While the key is missing, retry quickly so a newly created key file is
    // picked up without waiting for the full request interval.
    function _scheduleRetry(missingKey: bool): void {
        const now = Math.floor(Date.now() / 1000)
        root.nextRequestAt = now + (missingKey ? Math.min(10, root.requestDelaySeconds) : root.requestDelaySeconds)
    }

    // Fires whenever the API key file is created or modified.
    function _onKeyFileChanged(): void {
        root.nextRequestAt = 0
        Qt.callLater(() => root._maybeRefresh())
    }

    function _syncTimers(): void {
        const shouldRun = root.enabled && Config.ready && (_runningRequested || _persistentConsumers > 0)
        pollTimer.running = shouldRun
        clockTimer.running = shouldRun
    }

    // Watch the API key file so adding/editing ~/.deepseek/api_key triggers an
    // immediate refresh instead of waiting for the next poll.
    FileView {
        id: keyFileView
        path: Qt.resolvedUrl(root.apiKeyFile)
        watchChanges: true
        printErrors: false
        onLoaded: root._onKeyFileChanged()
        onLoadFailed: root._onKeyFileChanged()
    }

    Process {
        id: fetchProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                fetchTimeoutTimer.stop()
                const payload = text.trim()
                root.requesting = false
                if (payload.length === 0) {
                    root.ok = false
                    root.error = "empty balance response"
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
                    console.warn("[DeepSeekBalance] stderr:", err)
            }
        }
        onExited: (code) => {
            fetchTimeoutTimer.stop()
            if (code !== 0)
                console.warn("[DeepSeekBalance] process exit", code)
            if (root.requesting) {
                root.requesting = false
                if (!root.ok && root.error.length === 0)
                    root.error = `fetch exited with code ${code}`
                root.nextRequestAt = Math.floor(Date.now() / 1000) + root.requestDelaySeconds
            }
        }
    }

    Timer {
        id: fetchTimeoutTimer
        interval: 30000
        repeat: false
        running: false
        onTriggered: root._abortFetch(`fetch timed out after ${root.fetchTimeoutSeconds}s`)
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
