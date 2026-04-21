import QtQuick 2.15
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "../code/CpuBoostParser.js" as CpuBoostParser
import "../code/I18n.js" as I18n

PlasmoidItem {
    id: root

    width: 360
    height: 260

    readonly property bool inPanel: Plasmoid.location === PlasmaCore.Types.TopEdge
        || Plasmoid.location === PlasmaCore.Types.RightEdge
        || Plasmoid.location === PlasmaCore.Types.BottomEdge
        || Plasmoid.location === PlasmaCore.Types.LeftEdge
    readonly property string translationDomain: "plasma_applet_io.github.szumak75.cpu-boost-switcher"
    readonly property string localeName: Qt.locale().name
    readonly property string kauthClientPath: resolvedExecutablePath("../bin/cpuboost-kauth-client")
    readonly property bool canToggle: commandAvailable && boostSupported && !busy
    readonly property bool canChangeGovernor: commandAvailable && availableGovernorsModel.length > 0 && !busy
    readonly property string stateIcon: statusKind === "active"
        ? "active"
        : (statusKind === "inactive" ? "inactive" : "unsupported")

    readonly property bool popupExpanded: expanded
    property int refreshIntervalSeconds: normalizedRefreshInterval(Plasmoid.configuration.refreshIntervalSeconds)
    property string desiredBoostState: normalizedDesiredBoostState(Plasmoid.configuration.desiredBoostState)
    property string desiredGovernor: Plasmoid.configuration.desiredGovernor || ""
    property bool restoreSavedStateOnStartup: normalizedRestoreSavedStateOnStartup(Plasmoid.configuration.restoreSavedStateOnStartup)
    property bool busy: false
    property bool commandAvailable: false
    property bool boostSupported: false
    property bool boostActive: false
    property bool startupSyncPending: true
    property string statusKind: "loading"
    property string statusSummary: tr("Reading CPU Boost state...")
    property string statusDetails: tr("The first refresh is in progress.")
    property string operationSummary: ""
    property string driver: ""
    property string boostControl: ""
    property string availableGovernors: ""
    property var availableGovernorsModel: []
    property string currentGovernor: ""
    property bool mixedGovernor: false
    property string hardwareLimits: ""
    property string currentPolicy: ""
    property string lastUpdatedText: ""
    property string lastCommandOutput: ""
    property string diagnosticTitle: ""
    property string diagnosticMessage: ""
    property string diagnosticDetails: ""
    property string diagnosticRecommendation: ""
    property int diagnosticSerial: 0
    property bool pendingDiagnosticOpen: false

    preferredRepresentation: inPanel ? compactRepresentation : fullRepresentation
    Plasmoid.title: tr("CPU Boost Switcher")
    toolTipMainText: tr("CPU Boost")
    toolTipSubText: busy && operationSummary !== "" ? operationSummary : statusSummary
    Plasmoid.icon: "preferences-system-performance"

    compactRepresentation: CompactRepresentation {
        controller: root
    }

    fullRepresentation: FullRepresentation {
        controller: root
    }

    Timer {
        id: refreshTimer
        interval: root.refreshIntervalSeconds * 1000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.refreshStatus(false)
    }

    CommandRunner {
        id: commandRunner
        onFinished: function(context, exitCode, stdout, stderr) {
            root.handleCommandFinished(context, exitCode, stdout, stderr)
        }
    }

    Connections {
        target: Plasmoid.configuration

        function onRefreshIntervalSecondsChanged() {
            root.applyRefreshInterval(Plasmoid.configuration.refreshIntervalSeconds, false)
        }

        function onDesiredBoostStateChanged() {
            root.desiredBoostState = root.normalizedDesiredBoostState(Plasmoid.configuration.desiredBoostState)
        }

        function onDesiredGovernorChanged() {
            root.desiredGovernor = Plasmoid.configuration.desiredGovernor || ""
        }

        function onRestoreSavedStateOnStartupChanged() {
            root.restoreSavedStateOnStartup = root.normalizedRestoreSavedStateOnStartup(Plasmoid.configuration.restoreSavedStateOnStartup)
        }
    }

    Component.onCompleted: refreshStatus(true)

    function refreshStatus(openDiagnosticsOnError) {
        if (commandRunner.running) {
            return
        }

        busy = true
        operationSummary = tr("Reading CPU Boost state...")
        commandRunner.run(buildInfoCommand(), {
            kind: "refresh",
            openDiagnosticsOnError: openDiagnosticsOnError
        })
    }

    function requestToggle(targetEnabled, options) {
        const requestOptions = options || {}

        if (commandRunner.running) {
            return
        }

        if (!commandAvailable) {
            presentDiagnostic(
                tr("State control is unavailable"),
                tr("The state cannot be changed because the last refresh did not complete successfully."),
                lastCommandOutput,
                tr("Resolve the diagnostic issue first and then refresh the state."),
                true
            )
            return
        }

        if (!boostSupported) {
            presentDiagnostic(
                tr("CPU Boost is unsupported"),
                tr("This system does not report support for switching CPU Boost."),
                lastCommandOutput,
                tr("Check whether the active CPU driver exposes boost control through sysfs."),
                true
            )
            return
        }

        busy = true
        operationSummary = requestOptions.operationSummary || (targetEnabled
            ? tr("Enabling CPU Boost...")
            : tr("Disabling CPU Boost..."))
        commandRunner.run(buildSetCommand(targetEnabled), {
            kind: "set",
            targetEnabled: targetEnabled,
            persistDesired: requestOptions.persistDesired !== false,
            openDiagnosticsOnError: requestOptions.openDiagnosticsOnError !== false
        })
    }

    function requestGovernorChange(governor, options) {
        const requestOptions = options || {}

        if (commandRunner.running) {
            return
        }

        if (!commandAvailable) {
            presentDiagnostic(
                tr("State control is unavailable"),
                tr("The state cannot be changed because the last refresh did not complete successfully."),
                lastCommandOutput,
                tr("Resolve the diagnostic issue first and then refresh the state."),
                true
            )
            return
        }

        if (!/^[A-Za-z0-9_-]+$/.test(governor) || availableGovernorsModel.indexOf(governor) === -1) {
            presentDiagnostic(
                tr("Invalid governor selection"),
                tr("The selected governor is not available on this system."),
                governor,
                tr("Refresh the state and choose one of the governors reported by the current CPU driver."),
                true
            )
            return
        }

        busy = true
        operationSummary = requestOptions.operationSummary || tr("Changing governor to %1...").replace("%1", governor)
        commandRunner.run(buildGovernorCommand(governor), {
            kind: "governor",
            governor: governor,
            persistDesired: requestOptions.persistDesired !== false,
            openDiagnosticsOnError: requestOptions.openDiagnosticsOnError !== false
        })
    }

    function buildInfoCommand() {
        return "sh -lc " + shellQuote("if [ ! -x " + shellQuote(kauthClientPath) + " ]; then echo CPUBOOST_ERROR:missing_kauth_client; exit 127; fi; " + shellQuote(kauthClientPath) + " read-state 2>&1")
    }

    function buildSetCommand(targetEnabled) {
        return buildApplyStateCommand({
            applyBoost: true,
            boostEnabled: targetEnabled,
            applyGovernor: false,
            governor: "",
            restoreOnStartup: restoreSavedStateOnStartup,
            startupBoostState: targetEnabled ? "enabled" : "disabled",
            startupGovernor: effectiveDesiredGovernor()
        })
    }

    function buildGovernorCommand(governor) {
        return buildApplyStateCommand({
            applyBoost: false,
            boostEnabled: boostActive,
            applyGovernor: true,
            governor: governor,
            restoreOnStartup: restoreSavedStateOnStartup,
            startupBoostState: effectiveDesiredBoostState(),
            startupGovernor: governor
        })
    }

    function buildSyncPersistentStateCommand(targetRestoreEnabled, boostState, governor) {
        return buildApplyStateCommand({
            applyBoost: false,
            boostEnabled: boostActive,
            applyGovernor: false,
            governor: "",
            restoreOnStartup: targetRestoreEnabled,
            startupBoostState: boostState,
            startupGovernor: governor
        })
    }

    function buildApplyStateCommand(options) {
        const applyBoost = options.applyBoost ? 1 : 0
        const boostValue = options.boostEnabled ? 1 : 0
        const applyGovernor = options.applyGovernor ? 1 : 0
        const governor = options.governor && options.governor !== "" ? options.governor : "-"
        const restoreValue = options.restoreOnStartup ? 1 : 0
        const startupBoostState = options.startupBoostState && options.startupBoostState !== "" ? options.startupBoostState : "-"
        const startupGovernor = options.startupGovernor && options.startupGovernor !== "" ? options.startupGovernor : "-"
        return "sh -lc " + shellQuote("if [ ! -x " + shellQuote(kauthClientPath) + " ]; then echo CPUBOOST_ERROR:missing_kauth_client; exit 127; fi; " + shellQuote(kauthClientPath) + " apply-state " + applyBoost + " " + boostValue + " " + applyGovernor + " " + governor + " " + restoreValue + " " + startupBoostState + " " + startupGovernor + " 2>&1")
    }

    function handleCommandFinished(context, exitCode, stdout, stderr) {
        busy = false
        lastCommandOutput = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n")

        if (context.kind === "refresh") {
            handleRefreshResult(exitCode, stdout, stderr, context.openDiagnosticsOnError)
            return
        }

        if (context.kind === "set") {
            handleSetResult(context.targetEnabled, exitCode, stdout, stderr, context.persistDesired, context.openDiagnosticsOnError)
            return
        }

        if (context.kind === "governor") {
            handleGovernorResult(context.governor, exitCode, stdout, stderr, context.persistDesired, context.openDiagnosticsOnError)
            return
        }

        if (context.kind === "sync-persistent-state") {
            handleSyncPersistentStateResult(
                context.targetRestoreEnabled,
                context.targetBoostState,
                context.targetGovernor,
                exitCode,
                stdout,
                stderr,
                context.openDiagnosticsOnError
            )
            return
        }

        if (context.kind === "startup-apply") {
            handleStartupApplyResult(
                context.diagnosticKind,
                exitCode,
                stdout,
                stderr,
                context.openDiagnosticsOnError
            )
        }
    }

    function handleRefreshResult(exitCode, stdout, stderr, openDiagnosticsOnError) {
        operationSummary = ""

        if (exitCode !== 0) {
            const commandDiagnostic = CpuBoostParser.diagnoseCommand("refresh", exitCode, stdout, stderr)
            const diagnostic = localizedDiagnostic(commandDiagnostic.code)
            commandAvailable = false
            boostSupported = false
            boostControl = ""
            mixedGovernor = false
            statusKind = "error"
            statusSummary = diagnostic.message
            statusDetails = diagnostic.recommendation
            presentDiagnostic(
                diagnostic.title,
                diagnostic.message,
                commandDiagnostic.details,
                diagnostic.recommendation,
                openDiagnosticsOnError
            )
            return
        }

        const parsed = CpuBoostParser.parseStateJson(stdout)
        if (!parsed.ok) {
            const diagnostic = localizedDiagnostic(parsed.errorCode)
            commandAvailable = true
            boostSupported = false
            boostControl = ""
            mixedGovernor = false
            statusKind = "error"
            statusSummary = diagnostic.message
            statusDetails = diagnostic.recommendation
            presentDiagnostic(
                diagnostic.title,
                diagnostic.message,
                stdout.trim(),
                diagnostic.recommendation,
                openDiagnosticsOnError
            )
            return
        }

        commandAvailable = true
        boostSupported = parsed.boostSupported
        boostActive = parsed.boostActive
        driver = parsed.driver
        boostControl = parsed.boostControl
        availableGovernors = parsed.availableGovernors
        availableGovernorsModel = parsed.availableGovernorsModel || parsed.availableGovernors.split(/\s+/).filter(Boolean)
        currentGovernor = parsed.currentGovernor
        mixedGovernor = parsed.mixedGovernor === true
        hardwareLimits = parsed.hardwareLimits
        currentPolicy = parsed.currentPolicy
        lastUpdatedText = Qt.formatTime(new Date(), "HH:mm:ss")

        if (boostSupported) {
            statusKind = boostActive ? "active" : "inactive"
            statusSummary = boostActive
                ? tr("CPU Boost is enabled.")
                : tr("CPU Boost is disabled.")
            statusDetails = currentPolicy !== ""
                ? currentPolicy
                : tr("State read successfully.")
        } else {
            statusKind = "unsupported"
            statusSummary = tr("CPU Boost is unsupported.")
            statusDetails = tr("The active CPU driver does not expose a writable sysfs control for CPU Boost.")
        }

        if (startupSyncPending) {
            syncSavedConfiguration()
        }
    }

    function handleSetResult(targetEnabled, exitCode, stdout, stderr, persistDesired, openDiagnosticsOnError) {
        operationSummary = ""

        if (exitCode !== 0) {
            const commandDiagnostic = CpuBoostParser.diagnoseCommand("set", exitCode, stdout, stderr)
            const diagnostic = localizedDiagnostic(commandDiagnostic.code)
            statusSummary = diagnostic.message
            statusDetails = diagnostic.recommendation
            presentDiagnostic(
                diagnostic.title,
                diagnostic.message,
                commandDiagnostic.details,
                diagnostic.recommendation,
                openDiagnosticsOnError
            )
            return
        }

        if (persistDesired) {
            desiredBoostState = targetEnabled ? "enabled" : "disabled"
            Plasmoid.configuration.desiredBoostState = desiredBoostState
        }

        refreshStatus(false)
    }

    function handleGovernorResult(governor, exitCode, stdout, stderr, persistDesired, openDiagnosticsOnError) {
        operationSummary = ""

        if (exitCode !== 0) {
            const commandDiagnostic = CpuBoostParser.diagnoseCommand("governor", exitCode, stdout, stderr)
            const diagnostic = localizedDiagnostic(commandDiagnostic.code)
            statusSummary = diagnostic.message
            statusDetails = diagnostic.recommendation
            presentDiagnostic(
                diagnostic.title,
                diagnostic.message,
                commandDiagnostic.details,
                diagnostic.recommendation,
                openDiagnosticsOnError
            )
            return
        }

        if (persistDesired) {
            desiredGovernor = governor
            Plasmoid.configuration.desiredGovernor = governor
        }

        refreshStatus(false)
    }

    function handleSyncPersistentStateResult(targetRestoreEnabled, targetBoostState, targetGovernor, exitCode, stdout, stderr, openDiagnosticsOnError) {
        operationSummary = ""

        if (exitCode !== 0) {
            const commandDiagnostic = CpuBoostParser.diagnoseCommand("sync-persistent-state", exitCode, stdout, stderr)
            const diagnostic = localizedDiagnostic(commandDiagnostic.code)
            presentDiagnostic(
                diagnostic.title,
                diagnostic.message,
                commandDiagnostic.details,
                diagnostic.recommendation,
                openDiagnosticsOnError
            )
            return
        }

        restoreSavedStateOnStartup = targetRestoreEnabled
        if (Plasmoid.configuration.restoreSavedStateOnStartup !== targetRestoreEnabled) {
            Plasmoid.configuration.restoreSavedStateOnStartup = targetRestoreEnabled
        }

        if (desiredBoostState !== targetBoostState) {
            desiredBoostState = targetBoostState
        }
        if (Plasmoid.configuration.desiredBoostState !== targetBoostState) {
            Plasmoid.configuration.desiredBoostState = targetBoostState
        }

        if (desiredGovernor !== targetGovernor) {
            desiredGovernor = targetGovernor
        }
        if (Plasmoid.configuration.desiredGovernor !== targetGovernor) {
            Plasmoid.configuration.desiredGovernor = targetGovernor
        }
    }

    function handleStartupApplyResult(diagnosticKind, exitCode, stdout, stderr, openDiagnosticsOnError) {
        operationSummary = ""

        if (exitCode !== 0) {
            const commandDiagnostic = CpuBoostParser.diagnoseCommand(diagnosticKind, exitCode, stdout, stderr)
            const diagnostic = localizedDiagnostic(commandDiagnostic.code)
            statusSummary = diagnostic.message
            statusDetails = diagnostic.recommendation
            startupSyncPending = false
            presentDiagnostic(
                diagnostic.title,
                diagnostic.message,
                commandDiagnostic.details,
                diagnostic.recommendation,
                openDiagnosticsOnError
            )
            return
        }

        refreshStatus(false)
    }

    function presentDiagnostic(title, message, details, recommendation, openNow) {
        diagnosticTitle = title
        diagnosticMessage = message
        diagnosticDetails = details
        diagnosticRecommendation = recommendation
        diagnosticSerial += 1
        pendingDiagnosticOpen = openNow

        if (openNow) {
            setPopupExpanded(true)
        }
    }

    function normalizedRefreshInterval(value) {
        const parsed = Number(value)
        if (!Number.isFinite(parsed) || parsed < 1) {
            return 10
        }

        return Math.max(1, Math.min(60, Math.round(parsed)))
    }

    function normalizedDesiredBoostState(value) {
        if (value === "enabled" || value === "disabled") {
            return value
        }

        return ""
    }

    function normalizedRestoreSavedStateOnStartup(value) {
        return value === true
    }

    function resolvedExecutablePath(relativePath) {
        return decodeURIComponent(Qt.resolvedUrl(relativePath).toString().replace(/^file:\/\//, ""))
    }

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function applyRefreshInterval(value, persist) {
        const normalized = normalizedRefreshInterval(value)

        if (refreshIntervalSeconds !== normalized) {
            refreshIntervalSeconds = normalized
        }

        refreshTimer.restart()

        if (persist && Plasmoid.configuration.refreshIntervalSeconds !== normalized) {
            Plasmoid.configuration.refreshIntervalSeconds = normalized
        }
    }

    function setRefreshIntervalSeconds(value) {
        applyRefreshInterval(value, true)
    }

    function setRestoreSavedStateOnStartup(value) {
        const normalized = normalizedRestoreSavedStateOnStartup(value)
        const targetBoostState = normalized
            ? effectiveDesiredBoostState()
            : currentDesiredBoostState()
        const targetGovernor = normalized
            ? effectiveDesiredGovernor()
            : currentDesiredGovernor()

        if (commandRunner.running) {
            return
        }

        if (!commandAvailable) {
            presentDiagnostic(
                tr("State control is unavailable"),
                tr("The startup restore setting cannot be changed because the current CPU state is unavailable."),
                lastCommandOutput,
                tr("Refresh the state successfully and then try again."),
                true
            )
            return
        }

        busy = true
        operationSummary = normalized
            ? tr("Enabling startup restore...")
            : tr("Disabling startup restore...")
        commandRunner.run(buildSyncPersistentStateCommand(normalized, targetBoostState, targetGovernor), {
            kind: "sync-persistent-state",
            targetRestoreEnabled: normalized,
            targetBoostState: targetBoostState,
            targetGovernor: targetGovernor,
            openDiagnosticsOnError: true
        })
    }

    function currentDesiredBoostState() {
        return boostSupported
            ? (boostActive ? "enabled" : "disabled")
            : ""
    }

    function currentDesiredGovernor() {
        return currentGovernor !== "" ? currentGovernor : ""
    }

    function effectiveDesiredBoostState() {
        return desiredBoostState !== "" ? desiredBoostState : currentDesiredBoostState()
    }

    function effectiveDesiredGovernor() {
        return desiredGovernor !== "" ? desiredGovernor : currentDesiredGovernor()
    }

    function syncDesiredStateFromCurrent() {
        const currentDesiredBoostStateValue = currentDesiredBoostState()
        const currentDesiredGovernorValue = currentDesiredGovernor()

        if (desiredBoostState !== currentDesiredBoostStateValue) {
            desiredBoostState = currentDesiredBoostStateValue
        }
        if (Plasmoid.configuration.desiredBoostState !== currentDesiredBoostStateValue) {
            Plasmoid.configuration.desiredBoostState = currentDesiredBoostStateValue
        }

        if (desiredGovernor !== currentDesiredGovernorValue) {
            desiredGovernor = currentDesiredGovernorValue
        }
        if (Plasmoid.configuration.desiredGovernor !== currentDesiredGovernorValue) {
            Plasmoid.configuration.desiredGovernor = currentDesiredGovernorValue
        }
    }

    function setPopupExpanded(value) {
        expanded = value
    }

    function togglePopup() {
        setPopupExpanded(!expanded)
    }

    function boostControlDisplayText() {
        switch (boostControl) {
        case "cpufreq-boost":
            return "/sys/devices/system/cpu/cpufreq/boost"
        case "intel-pstate-no-turbo":
            return "/sys/devices/system/cpu/intel_pstate/no_turbo"
        case "policy-cpb":
            return "/sys/devices/system/cpu/cpufreq/policy*/cpb"
        default:
            return commandAvailable ? "Unsupported" : tr("No data")
        }
    }

    function currentGovernorDisplayText() {
        if (mixedGovernor) {
            return tr("Mixed")
        }
        if (currentGovernor !== "") {
            return currentGovernor
        }
        return "—"
    }

    function platformBoostRecommendation() {
        if (boostControl === "cpufreq-boost") {
            return "Check whether /sys/devices/system/cpu/cpufreq/boost exists and is writable."
        }
        if (boostControl === "intel-pstate-no-turbo" || driver.toLowerCase().indexOf("intel") !== -1) {
            return "Check whether /sys/devices/system/cpu/intel_pstate/no_turbo exists and is writable."
        }
        if (boostControl === "policy-cpb") {
            return "Check whether /sys/devices/system/cpu/cpufreq/policy*/cpb exists and is writable for each policy domain."
        }
        if (driver.toLowerCase().indexOf("amd") !== -1) {
            return "Check whether /sys/devices/system/cpu/cpufreq/boost or /sys/devices/system/cpu/cpufreq/policy*/cpb exists and is writable."
        }
        return tr("Check whether the active CPU driver exposes boost control through sysfs.")
    }

    function governorControlRecommendation() {
        return "Check whether /sys/devices/system/cpu/cpufreq/policy*/scaling_governor exists and is writable for each policy domain."
    }

    function syncSavedConfiguration() {
        if (!commandAvailable) {
            return
        }

        if (!restoreSavedStateOnStartup) {
            syncDesiredStateFromCurrent()
            startupSyncPending = false
            return
        }

        if (desiredBoostState === "" && boostSupported) {
            desiredBoostState = boostActive ? "enabled" : "disabled"
            Plasmoid.configuration.desiredBoostState = desiredBoostState
        }

        if (desiredGovernor === "" && currentGovernor !== "") {
            desiredGovernor = currentGovernor
            Plasmoid.configuration.desiredGovernor = currentGovernor
        }

        if (desiredBoostState !== "") {
            if (!boostSupported) {
                startupSyncPending = false
                presentDiagnostic(
                    tr("Saved CPU Boost state cannot be applied"),
                    tr("The saved CPU Boost state cannot be restored because CPU Boost is not supported on this system."),
                    lastCommandOutput,
                    tr("Leave the saved value unchanged or move the plasmoid to hardware that supports CPU Boost control."),
                    false
                )
                return
            }
        }

        if (desiredGovernor !== "" && availableGovernorsModel.indexOf(desiredGovernor) === -1) {
            startupSyncPending = false
            presentDiagnostic(
                tr("Saved governor is unavailable"),
                tr("The saved governor '%1' is not available on this system.").replace("%1", desiredGovernor),
                availableGovernors,
                tr("Select one of the available governors or update the saved setting."),
                false
            )
            return
        }

        const shouldApplyBoost = desiredBoostState !== "" && boostActive !== (desiredBoostState === "enabled")
        const shouldApplyGovernor = desiredGovernor !== "" && currentGovernor !== desiredGovernor

        if (shouldApplyBoost || shouldApplyGovernor) {
            busy = true
            operationSummary = tr("Restoring saved settings...")
            commandRunner.run(buildApplyStateCommand({
                applyBoost: shouldApplyBoost,
                boostEnabled: desiredBoostState === "enabled",
                applyGovernor: shouldApplyGovernor,
                governor: shouldApplyGovernor ? desiredGovernor : "",
                restoreOnStartup: true,
                startupBoostState: desiredBoostState,
                startupGovernor: desiredGovernor
            }), {
                kind: "startup-apply",
                diagnosticKind: shouldApplyBoost ? "set" : "governor",
                openDiagnosticsOnError: false
            })
            return
        }

        startupSyncPending = false
    }

    function localizedDiagnostic(code) {
        switch (code) {
        case "missing_kauth_client":
            return {
                title: tr("The KAuth client is missing"),
                message: tr("The installed plasmoid does not include the KAuth client executable."),
                recommendation: tr("Reinstall the project with the KAuth client enabled and make sure the helper binaries are installed.")
            }
        case "kauth_not_configured":
            return {
                title: tr("KAuth is not configured"),
                message: tr("The KAuth action could not be created for this operation."),
                recommendation: tr("Install the KAuth helper, D-Bus service, and policy files system-wide, then restart the Plasma session.")
            }
        case "kauth_action_failed":
            return {
                title: tr("KAuth authorization failed"),
                message: tr("The privileged KAuth action did not complete successfully."),
                recommendation: tr("Check whether the helper is installed system-wide and whether Polkit can prompt for authentication.")
            }
        case "invalid_arguments":
            return {
                title: tr("Invalid privileged command arguments"),
                message: tr("The KAuth client or helper rejected the requested operation arguments."),
                recommendation: tr("Refresh the state and try again. If the error persists, review helper argument validation.")
            }
        case "unsupported_boost_control":
            return {
                title: tr("CPU Boost control is unsupported"),
                message: tr("The active CPU driver does not expose a writable sysfs control for CPU Boost."),
                recommendation: platformBoostRecommendation()
            }
        case "missing_governor_control":
            return {
                title: tr("Governor control is unavailable"),
                message: tr("The active CPU driver does not expose writable governor controls through sysfs."),
                recommendation: governorControlRecommendation()
            }
        case "permission_denied":
            return {
                title: tr("Changing the state is not permitted"),
                message: tr("The helper failed with a permission error while trying to change the CPU state."),
                recommendation: tr("Check file permissions under /sys/devices/system/cpu and verify the KAuth helper is installed correctly.")
            }
        case "sync_persistent_state_failed":
            return {
                title: tr("Failed to update startup restore state"),
                message: tr("The operation that updates the startup restore state failed."),
                recommendation: tr("Inspect the diagnostic details and verify the helper can write the persistent startup state.")
            }
        case "set_failed":
            return {
                title: tr("Failed to change CPU Boost"),
                message: tr("The operation that changes the CPU Boost state failed."),
                recommendation: platformBoostRecommendation()
            }
        case "governor_failed":
            return {
                title: tr("Failed to change governor"),
                message: tr("The operation that changes the CPU governor failed."),
                recommendation: governorControlRecommendation()
            }
        case "missing_cpufreq":
            return {
                title: tr("CPU frequency sysfs is unavailable"),
                message: tr("The system does not expose the expected cpufreq policy directories."),
                recommendation: tr("Check whether cpufreq is enabled for this kernel and CPU driver.")
            }
        case "empty_output":
            return {
                title: tr("State reader returned no data"),
                message: tr("The state reader returned no data."),
                recommendation: tr("Reinstall the KAuth client and verify the CPU sysfs hierarchy is available.")
            }
        case "invalid_state_json":
            return {
                title: tr("Invalid state data"),
                message: tr("The applet could not parse the state data returned by the local helper client."),
                recommendation: tr("Check the diagnostic details and verify the installed client binary matches the current plasmoid version.")
            }
        case "state_read_failed":
        default:
            return {
                title: tr("Failed to read CPU Boost state"),
                message: tr("The applet could not read CPU state from sysfs."),
                recommendation: tr("Check the diagnostic details and verify the current CPU driver exposes cpufreq sysfs controls.")
            }
        }
    }

    function tr(text) {
        return I18n.tr(localeName, text)
    }
}
