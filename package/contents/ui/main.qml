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
    readonly property bool canToggle: commandAvailable && boostSupported && !busy
    readonly property bool canChangeGovernor: commandAvailable && availableGovernorsModel.length > 0 && !busy
    readonly property string stateIcon: statusKind === "active"
        ? "active"
        : (statusKind === "inactive" ? "inactive" : "unsupported")

    property int refreshIntervalSeconds: normalizedRefreshInterval(Plasmoid.configuration.refreshIntervalSeconds)
    property string desiredBoostState: normalizedDesiredBoostState(Plasmoid.configuration.desiredBoostState)
    property string desiredGovernor: Plasmoid.configuration.desiredGovernor || ""
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
    property string availableGovernors: ""
    property var availableGovernorsModel: []
    property string currentGovernor: ""
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
                tr("cpupower is unavailable"),
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
                tr("Check whether the CPU driver and platform expose the 'boost state support' block."),
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
                tr("cpupower is unavailable"),
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
                tr("Refresh the state and choose one of the governors reported by cpupower."),
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
        return "sh -lc 'if ! command -v cpupower >/dev/null 2>&1; then echo CPUBOOST_ERROR:missing_cpupower; exit 127; fi; LC_ALL=C cpupower frequency-info 2>&1'"
    }

    function buildSetCommand(targetEnabled) {
        const value = targetEnabled ? 1 : 0
        return "sh -lc 'if ! command -v cpupower >/dev/null 2>&1; then echo CPUBOOST_ERROR:missing_cpupower; exit 127; fi; if ! command -v sudo >/dev/null 2>&1; then echo CPUBOOST_ERROR:missing_sudo; exit 127; fi; LC_ALL=C sudo -n cpupower set --turbo-boost " + value + " 2>&1'"
    }

    function buildGovernorCommand(governor) {
        return "sh -lc 'if ! command -v cpupower >/dev/null 2>&1; then echo CPUBOOST_ERROR:missing_cpupower; exit 127; fi; if ! command -v sudo >/dev/null 2>&1; then echo CPUBOOST_ERROR:missing_sudo; exit 127; fi; LC_ALL=C sudo -n cpupower frequency-set -g " + governor + " 2>&1'"
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
        }
    }

    function handleRefreshResult(exitCode, stdout, stderr, openDiagnosticsOnError) {
        operationSummary = ""

        if (exitCode !== 0) {
            const commandDiagnostic = CpuBoostParser.diagnoseCommand("refresh", exitCode, stdout, stderr)
            const diagnostic = localizedDiagnostic(commandDiagnostic.code)
            commandAvailable = false
            boostSupported = false
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

        const parsed = CpuBoostParser.parseFrequencyInfo(stdout)
        if (!parsed.ok) {
            const diagnostic = localizedDiagnostic(parsed.errorCode)
            commandAvailable = true
            boostSupported = false
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
        availableGovernors = parsed.availableGovernors
        availableGovernorsModel = parsed.availableGovernors.split(/\s+/).filter(Boolean)
        currentGovernor = parsed.currentGovernor
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
            statusDetails = tr("The 'Supported' field returned 'no'.")
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

    function presentDiagnostic(title, message, details, recommendation, openNow) {
        diagnosticTitle = title
        diagnosticMessage = message
        diagnosticDetails = details
        diagnosticRecommendation = recommendation
        diagnosticSerial += 1
        pendingDiagnosticOpen = openNow

        if (openNow) {
            expanded = true
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

    function syncSavedConfiguration() {
        if (!commandAvailable) {
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

            const desiredEnabled = desiredBoostState === "enabled"
            if (boostActive !== desiredEnabled) {
                requestToggle(desiredEnabled, {
                    persistDesired: false,
                    openDiagnosticsOnError: false
                })
                return
            }
        }

        if (desiredGovernor !== "") {
            if (availableGovernorsModel.indexOf(desiredGovernor) === -1) {
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

            if (currentGovernor !== desiredGovernor) {
                requestGovernorChange(desiredGovernor, {
                    persistDesired: false,
                    openDiagnosticsOnError: false
                })
                return
            }
        }

        startupSyncPending = false
    }

    function localizedDiagnostic(code) {
        switch (code) {
        case "missing_cpupower":
            return {
                title: tr("cpupower is missing"),
                message: tr("The system could not find the 'cpupower' command."),
                recommendation: tr("Install the package that provides 'cpupower' and ensure the command is available in PATH.")
            }
        case "missing_sudo":
            return {
                title: tr("sudo is missing"),
                message: tr("The CPU Boost state cannot be changed because the 'sudo' command is unavailable."),
                recommendation: tr("Install 'sudo' or replace the execution path with a helper based on polkit/pkexec.")
            }
        case "sudo_password_required":
            return {
                title: tr("sudo requires a password"),
                message: tr("Changing the CPU Boost state requires an interactive sudo password prompt."),
                recommendation: tr("Configure passwordless sudo for this command or add a helper with graphical authentication in the future.")
            }
        case "sudo_not_allowed":
            return {
                title: tr("sudo permission denied"),
                message: tr("The current user is not allowed to run the command that changes the CPU Boost state."),
                recommendation: tr("Add an appropriate sudoers entry or switch to a different authorization mechanism.")
            }
        case "permission_denied":
            return {
                title: tr("Changing the state is not permitted"),
                message: tr("The command failed with a permission error while trying to change CPU Boost."),
                recommendation: tr("Check whether 'sudo cpupower set --turbo-boost 0|1' works manually for the current user.")
            }
        case "set_failed":
            return {
                title: tr("Failed to change CPU Boost"),
                message: tr("The command that changes the CPU Boost state failed."),
                recommendation: tr("Run 'sudo cpupower set --turbo-boost 0|1' manually and inspect the error details.")
            }
        case "governor_failed":
            return {
                title: tr("Failed to change governor"),
                message: tr("The command that changes the CPU governor failed."),
                recommendation: tr("Run 'sudo cpupower frequency-set -g <governor>' manually and inspect the error details.")
            }
        case "empty_output":
            return {
                title: tr("cpupower returned no data"),
                message: tr("The 'cpupower frequency-info' command returned no data."),
                recommendation: tr("Run 'cpupower frequency-info' manually and make sure it prints CPU frequency information.")
            }
        case "missing_boost_block":
            return {
                title: tr("Unknown cpupower output format"),
                message: tr("The applet could not recognize the 'boost state support' section in the command output."),
                recommendation: tr("Run 'cpupower frequency-info' manually and compare its output with the expected structure.")
            }
        case "refresh_failed":
        default:
            return {
                title: tr("Failed to read CPU Boost state"),
                message: tr("The 'cpupower frequency-info' command failed."),
                recommendation: tr("Check whether 'cpupower frequency-info' works correctly in a terminal.")
            }
        }
    }

    function tr(text) {
        return I18n.tr(localeName, text)
    }
}
