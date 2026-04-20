.pragma library

function parseFrequencyInfo(rawText) {
    const result = {
        ok: false,
        driver: "",
        availableGovernors: "",
        hardwareLimits: "",
        currentPolicy: "",
        currentGovernor: "",
        boostSupported: false,
        boostActive: false,
        errorCode: "",
        errorMessage: ""
    }

    if (!rawText || rawText.trim() === "") {
        result.errorCode = "empty_output"
        return result
    }

    const lines = rawText.split(/\r?\n/)
    let inBoostSection = false
    let foundSupported = false
    let foundActive = false
    let collectingPolicy = false
    let policyLines = []

    for (let index = 0; index < lines.length; ++index) {
        const line = lines[index]
        const trimmed = line.trim()

        if (/^driver:\s*/.test(trimmed)) {
            result.driver = trimmed.replace(/^driver:\s*/, "")
        } else if (/^available cpufreq governors:\s*/.test(trimmed)) {
            result.availableGovernors = trimmed.replace(/^available cpufreq governors:\s*/, "")
        } else if (/^hardware limits:\s*/.test(trimmed)) {
            result.hardwareLimits = trimmed.replace(/^hardware limits:\s*/, "")
        }

        if (/^current policy:\s*/.test(trimmed)) {
            collectingPolicy = true
            policyLines = [trimmed.replace(/^current policy:\s*/, "")]
            continue
        }

        if (collectingPolicy) {
            if (/^\s{10,}\S/.test(line)) {
                policyLines.push(trimmed)
                continue
            }

            result.currentPolicy = policyLines.join(" ")
            collectingPolicy = false
        }

        if (trimmed === "boost state support:") {
            inBoostSection = true
            continue
        }

        if (inBoostSection) {
            const supportedMatch = trimmed.match(/^Supported:\s*(yes|no)$/i)
            if (supportedMatch) {
                result.boostSupported = supportedMatch[1].toLowerCase() === "yes"
                foundSupported = true
                continue
            }

            const activeMatch = trimmed.match(/^Active:\s*(yes|no)$/i)
            if (activeMatch) {
                result.boostActive = activeMatch[1].toLowerCase() === "yes"
                foundActive = true
                continue
            }

            if (/^[A-Za-z].*:\s*$/.test(trimmed)) {
                inBoostSection = false
            }
        }
    }

    if (collectingPolicy && policyLines.length > 0) {
        result.currentPolicy = policyLines.join(" ")
    }

    const governorMatch = result.currentPolicy.match(/The governor "([^"]+)"/)
    if (governorMatch) {
        result.currentGovernor = governorMatch[1]
    }

    if (!foundSupported || !foundActive) {
        result.errorCode = "missing_boost_block"
        return result
    }

    result.ok = true
    return result
}

function diagnoseCommand(kind, exitCode, stdout, stderr) {
    const details = [stdout.trim(), stderr.trim()].filter(Boolean).join("\n")
    const combined = details.toLowerCase()

    if (details.indexOf("CPUBOOST_ERROR:missing_cpupower") !== -1) {
        return {
            details: details,
            code: "missing_cpupower"
        }
    }

    if (details.indexOf("CPUBOOST_ERROR:missing_sudo") !== -1) {
        return {
            details: details,
            code: "missing_sudo"
        }
    }

    if ((kind === "set" || kind === "governor") && (combined.indexOf("a password is required") !== -1 || combined.indexOf("no password was provided") !== -1)) {
        return {
            details: details,
            code: "sudo_password_required"
        }
    }

    if ((kind === "set" || kind === "governor") && (combined.indexOf("not in the sudoers file") !== -1
        || combined.indexOf("is not allowed to execute") !== -1
        || combined.indexOf("is not allowed to run sudo") !== -1)) {
        return {
            details: details,
            code: "sudo_not_allowed"
        }
    }

    if ((kind === "set" || kind === "governor") && (combined.indexOf("permission denied") !== -1 || combined.indexOf("operation not permitted") !== -1)) {
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

    return {
        details: details,
        code: exitCode === 0 ? "refresh_failed" : "refresh_exit_" + exitCode
    }
}
