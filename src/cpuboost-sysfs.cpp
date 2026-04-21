#include "cpuboost-sysfs.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIODevice>
#include <QRegularExpression>
#include <QSettings>

namespace CpuBoost {

namespace {

const QString kCpufreqRoot = QStringLiteral("/sys/devices/system/cpu/cpufreq");
const QString kIntelPstateRoot = QStringLiteral("/sys/devices/system/cpu/intel_pstate");
const QString kPersistentStateDir = QStringLiteral("/var/lib/kde6-cpu-boost-switcher");
const QString kPersistentStatePath = kPersistentStateDir + QStringLiteral("/state.ini");

} // namespace

QString readTextFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }

    return QString::fromLocal8Bit(file.readAll()).trimmed();
}

bool writeTextFile(const QString &path, const QString &value, QString *errorText)
{
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        if (errorText) {
            *errorText = file.errorString();
        }
        return false;
    }

    if (file.write(value.toLocal8Bit()) == -1) {
        if (errorText) {
            *errorText = file.errorString();
        }
        return false;
    }

    return true;
}

QStringList policyPaths()
{
    QDir root(kCpufreqRoot);
    const QStringList entries = root.entryList(QStringList() << QStringLiteral("policy*"), QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    QStringList paths;
    for (const QString &entry : entries) {
        paths << root.absoluteFilePath(entry);
    }
    return paths;
}

QStringList uniqueWritablePolicyFiles(const QString &fileName)
{
    QStringList files;
    QStringList seenDomains;

    for (const QString &policy : policyPaths()) {
        const QString target = policy + QLatin1Char('/') + fileName;
        if (!QFileInfo::exists(target)) {
            continue;
        }

        const QString domain = readTextFile(policy + QStringLiteral("/freqdomain_cpus"));
        const QString dedupeKey = domain.isEmpty() ? target : domain;
        if (seenDomains.contains(dedupeKey)) {
            continue;
        }

        seenDomains << dedupeKey;
        files << target;
    }

    return files;
}

bool isValidBoostState(const QString &value)
{
    return value.isEmpty() || value == QStringLiteral("enabled") || value == QStringLiteral("disabled");
}

bool isValidGovernorName(const QString &value)
{
    static const QRegularExpression governorPattern(QStringLiteral("^[A-Za-z0-9_-]+$"));
    return value.isEmpty() || governorPattern.match(value).hasMatch();
}

QString persistentStateFilePath()
{
    return kPersistentStatePath;
}

bool loadPersistentState(PersistentState *state, QString *errorText)
{
    if (!state) {
        if (errorText) {
            *errorText = QStringLiteral("Invalid state pointer");
        }
        return false;
    }

    *state = PersistentState();

    const QFileInfo fileInfo(kPersistentStatePath);
    if (!fileInfo.exists()) {
        return true;
    }

    QSettings settings(kPersistentStatePath, QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("StartupRestore"));
    state->restoreOnStartup = settings.value(QStringLiteral("restoreOnStartup"), false).toBool();
    state->boostState = settings.value(QStringLiteral("boostState")).toString().trimmed();
    state->governor = settings.value(QStringLiteral("governor")).toString().trimmed();
    settings.endGroup();

    if (!isValidBoostState(state->boostState) || !isValidGovernorName(state->governor)) {
        if (errorText) {
            *errorText = QStringLiteral("CPUBOOST_ERROR:invalid_persistent_state");
        }
        return false;
    }

    return true;
}

bool savePersistentState(const PersistentState &state, QString *errorText)
{
    QDir dir;
    if (!dir.mkpath(kPersistentStateDir)) {
        if (errorText) {
            *errorText = QStringLiteral("Failed to create %1").arg(kPersistentStateDir);
        }
        return false;
    }

    if (!isValidBoostState(state.boostState) || !isValidGovernorName(state.governor)) {
        if (errorText) {
            *errorText = QStringLiteral("CPUBOOST_ERROR:invalid_arguments");
        }
        return false;
    }

    QSettings settings(kPersistentStatePath, QSettings::IniFormat);
    settings.clear();
    settings.beginGroup(QStringLiteral("StartupRestore"));
    settings.setValue(QStringLiteral("restoreOnStartup"), state.restoreOnStartup);
    settings.setValue(QStringLiteral("boostState"), state.boostState);
    settings.setValue(QStringLiteral("governor"), state.governor);
    settings.endGroup();
    settings.sync();

    if (settings.status() != QSettings::NoError) {
        if (errorText) {
            *errorText = QStringLiteral("Failed to write %1").arg(kPersistentStatePath);
        }
        return false;
    }

    return true;
}

bool clearPersistentState(QString *errorText)
{
    const QFileInfo fileInfo(kPersistentStatePath);
    if (!fileInfo.exists()) {
        return true;
    }

    QFile file(kPersistentStatePath);
    if (!file.remove()) {
        if (errorText) {
            *errorText = file.errorString();
        }
        return false;
    }

    return true;
}

bool syncPersistentState(bool restoreOnStartup, const QString &boostState, const QString &governor, QString *errorText)
{
    if (!restoreOnStartup) {
        return clearPersistentState(errorText);
    }

    PersistentState state;
    state.restoreOnStartup = true;
    state.boostState = boostState;
    state.governor = governor;
    return savePersistentState(state, errorText);
}

bool updatePersistentBoostState(bool enabled, QString *errorText)
{
    PersistentState state;
    if (!loadPersistentState(&state, errorText)) {
        return false;
    }

    state.restoreOnStartup = true;
    state.boostState = enabled ? QStringLiteral("enabled") : QStringLiteral("disabled");
    return savePersistentState(state, errorText);
}

bool updatePersistentGovernor(const QString &governor, QString *errorText)
{
    PersistentState state;
    if (!loadPersistentState(&state, errorText)) {
        return false;
    }

    state.restoreOnStartup = true;
    state.governor = governor;
    return savePersistentState(state, errorText);
}

bool applyBoostState(bool enabled, QString *errorText)
{
    const QString enabledValue = enabled ? QStringLiteral("1") : QStringLiteral("0");

    const QString genericBoostPath = kCpufreqRoot + QStringLiteral("/boost");
    if (QFileInfo::exists(genericBoostPath)) {
        return writeTextFile(genericBoostPath, enabledValue, errorText);
    }

    const QString noTurboPath = kIntelPstateRoot + QStringLiteral("/no_turbo");
    if (QFileInfo::exists(noTurboPath)) {
        const QString noTurboValue = enabled ? QStringLiteral("0") : QStringLiteral("1");
        return writeTextFile(noTurboPath, noTurboValue, errorText);
    }

    const QStringList cpbFiles = uniqueWritablePolicyFiles(QStringLiteral("cpb"));
    if (cpbFiles.isEmpty()) {
        if (errorText) {
            *errorText = QStringLiteral("CPUBOOST_ERROR:unsupported_boost_control");
        }
        return false;
    }

    for (const QString &path : cpbFiles) {
        if (!writeTextFile(path, enabledValue, errorText)) {
            return false;
        }
    }

    return true;
}

bool applyGovernor(const QString &governor, QString *errorText)
{
    if (!isValidGovernorName(governor) || governor.isEmpty()) {
        if (errorText) {
            *errorText = QStringLiteral("CPUBOOST_ERROR:invalid_arguments");
        }
        return false;
    }

    const QStringList governorFiles = uniqueWritablePolicyFiles(QStringLiteral("scaling_governor"));
    if (governorFiles.isEmpty()) {
        if (errorText) {
            *errorText = QStringLiteral("CPUBOOST_ERROR:missing_governor_control");
        }
        return false;
    }

    for (const QString &path : governorFiles) {
        if (!writeTextFile(path, governor, errorText)) {
            return false;
        }
    }

    return true;
}

} // namespace CpuBoost
