.pragma library

function parseStateJson(rawText) {
    const result = {
        ok: false,
        driver: "",
        boostControl: "",
        availableGovernors: "",
        availableGovernorsModel: [],
        hardwareLimits: "",
        currentPolicy: "",
        currentGovernor: "",
        mixedGovernor: false,
        policyCount: 0,
        boostSupported: false,
        boostActive: false,
        errorCode: ""
    }

    if (!rawText || rawText.trim() === "") {
        result.errorCode = "empty_output"
        return result
    }

    let parsed
    try {
        parsed = JSON.parse(rawText)
    } catch (error) {
        result.errorCode = "invalid_state_json"
        return result
    }

    if (!parsed || parsed.ok !== true) {
        result.errorCode = parsed && parsed.errorCode ? parsed.errorCode : "state_read_failed"
        return result
    }

    result.ok = true
    result.driver = parsed.driver || ""
    result.boostControl = parsed.boostControl || ""
    result.availableGovernors = parsed.availableGovernors || ""
    result.availableGovernorsModel = parsed.availableGovernorsModel || []
    result.hardwareLimits = parsed.hardwareLimits || ""
    result.currentPolicy = parsed.currentPolicy || ""
    result.currentGovernor = parsed.currentGovernor || ""
    result.mixedGovernor = parsed.mixedGovernor === true
    result.policyCount = parsed.policyCount || 0
    result.boostSupported = parsed.boostSupported === true
    result.boostActive = parsed.boostActive === true
    return result
}

function diagnoseCommand(kind, exitCode, stdout, stderr) {
    const details = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n")
    const combined = details.toLowerCase()

    if (details.indexOf("CPUBOOST_ERROR:missing_kauth_client") !== -1) {
        return {
            details: details,
            code: "missing_kauth_client"
        }
    }

    if (details.indexOf("CPUBOOST_ERROR:kauth_not_configured") !== -1) {
        return {
            details: details,
            code: "kauth_not_configured"
        }
    }

    if (details.indexOf("CPUBOOST_ERROR:kauth_action_failed") !== -1) {
        return {
            details: details,
            code: "kauth_action_failed"
        }
    }

    if (details.indexOf("CPUBOOST_ERROR:invalid_arguments") !== -1) {
        return {
            details: details,
            code: "invalid_arguments"
        }
    }

    if (details.indexOf("CPUBOOST_ERROR:unsupported_boost_control") !== -1) {
        return {
            details: details,
            code: "unsupported_boost_control"
        }
    }

    if (details.indexOf("CPUBOOST_ERROR:missing_governor_control") !== -1) {
        return {
            details: details,
            code: "missing_governor_control"
        }
    }

    if (kind === "refresh") {
        if (details.indexOf("\"errorCode\":\"missing_cpufreq\"") !== -1) {
            return {
                details: details,
                code: "missing_cpufreq"
            }
        }

        if (details.indexOf("\"errorCode\":\"empty_output\"") !== -1) {
            return {
                details: details,
                code: "empty_output"
            }
        }
    }

    if ((kind === "set" || kind === "governor" || kind === "sync-persistent-state" || kind === "startup-apply") && (combined.indexOf("permission denied") !== -1 || combined.indexOf("operation not permitted") !== -1 || combined.indexOf("read-only file system") !== -1)) {
        return {
            details: details,
            code: "permission_denied"
        }
    }

    if (kind === "set") {
        return {
            details: details,
            code: "set_failed"
        }
    }

    if (kind === "governor") {
        return {
            details: details,
            code: "governor_failed"
        }
    }

    if (kind === "sync-persistent-state") {
        return {
            details: details,
            code: "sync_persistent_state_failed"
        }
    }

    return {
        details: details,
        code: "state_read_failed"
    }
}
