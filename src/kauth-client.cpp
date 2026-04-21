#include <iostream>

#include <KAuth/Action>
#include <KAuth/ExecuteJob>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStringList>
#include <QVariantMap>

namespace {

constexpr const char *kHelperId = "io.github.szumak75.kde6cpuboostswitcher.helper";
constexpr const char *kApplyStateAction = "io.github.szumak75.kde6cpuboostswitcher.helper.applyState";
const QString kCpufreqRoot = QStringLiteral("/sys/devices/system/cpu/cpufreq");
const QString kIntelPstateRoot = QStringLiteral("/sys/devices/system/cpu/intel_pstate");

struct PolicyState
{
    QString path;
    QString driver;
    QStringList availableGovernors;
    QString currentGovernor;
    qlonglong minFreqKHz = -1;
    qlonglong maxFreqKHz = -1;
    qlonglong biosLimitKHz = -1;
};

struct BoostState
{
    bool supported = false;
    bool active = false;
    QString control = QStringLiteral("unsupported");
};

QString readTextFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }

    return QString::fromLocal8Bit(file.readAll()).trimmed();
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

QStringList uniqueNonEmptyStrings(QStringList values)
{
    values.removeAll(QString());
    values.removeDuplicates();
    return values;
}

QStringList splitGovernors(const QString &value)
{
    QStringList governors = value.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    governors.removeDuplicates();
    return governors;
}

qlonglong readFrequencyKHz(const QString &path)
{
    bool ok = false;
    const qlonglong frequencyKHz = readTextFile(path).toLongLong(&ok);
    if (!ok || frequencyKHz <= 0) {
        return -1;
    }

    return frequencyKHz;
}

QString formatFrequencyKHz(qlonglong value)
{
    if (value <= 0) {
        return QString();
    }

    const double frequencyGHz = static_cast<double>(value) / 1000000.0;
    return QString::number(frequencyGHz, 'f', 2) + QStringLiteral(" GHz");
}

PolicyState readPolicyState(const QString &policyPath)
{
    PolicyState state;
    state.path = policyPath;
    state.driver = readTextFile(policyPath + QStringLiteral("/scaling_driver"));
    state.availableGovernors = splitGovernors(readTextFile(policyPath + QStringLiteral("/scaling_available_governors")));
    state.currentGovernor = readTextFile(policyPath + QStringLiteral("/scaling_governor"));
    state.minFreqKHz = readFrequencyKHz(policyPath + QStringLiteral("/cpuinfo_min_freq"));
    state.maxFreqKHz = readFrequencyKHz(policyPath + QStringLiteral("/cpuinfo_max_freq"));
    state.biosLimitKHz = readFrequencyKHz(policyPath + QStringLiteral("/bios_limit"));
    return state;
}

QString summarizeDrivers(const QList<PolicyState> &policies)
{
    QStringList drivers;
    for (const PolicyState &policy : policies) {
        if (!policy.driver.isEmpty()) {
            drivers << policy.driver;
        }
    }

    drivers = uniqueNonEmptyStrings(drivers);
    if (drivers.isEmpty()) {
        return QString();
    }
    if (drivers.size() == 1) {
        return drivers.first();
    }

    return QStringLiteral("Mixed: %1").arg(drivers.join(QStringLiteral(", ")));
}

QStringList commonAvailableGovernors(const QList<PolicyState> &policies)
{
    QStringList common;
    bool initialized = false;

    for (const PolicyState &policy : policies) {
        if (policy.availableGovernors.isEmpty()) {
            continue;
        }

        if (!initialized) {
            common = policy.availableGovernors;
            initialized = true;
            continue;
        }

        QStringList filtered;
        for (const QString &governor : common) {
            if (policy.availableGovernors.contains(governor)) {
                filtered << governor;
            }
        }
        common = filtered;
    }

    common.removeDuplicates();
    return common;
}

QString summarizeAvailableGovernors(const QList<PolicyState> &policies, const QStringList &commonGovernors)
{
    if (!commonGovernors.isEmpty()) {
        return commonGovernors.join(QLatin1Char(' '));
    }

    QStringList allGovernors;
    for (const PolicyState &policy : policies) {
        allGovernors << policy.availableGovernors;
    }
    allGovernors = uniqueNonEmptyStrings(allGovernors);

    if (allGovernors.isEmpty()) {
        return QString();
    }

    return QStringLiteral("Mixed: %1").arg(allGovernors.join(QStringLiteral(", ")));
}

QString summarizeCurrentGovernor(const QList<PolicyState> &policies, bool *mixed)
{
    QStringList governors;
    for (const PolicyState &policy : policies) {
        if (!policy.currentGovernor.isEmpty()) {
            governors << policy.currentGovernor;
        }
    }

    governors = uniqueNonEmptyStrings(governors);
    const bool isMixed = governors.size() > 1;
    if (mixed) {
        *mixed = isMixed;
    }

    if (governors.size() == 1) {
        return governors.first();
    }

    return QString();
}

QString summarizeHardwareLimits(const QList<PolicyState> &policies)
{
    qlonglong globalMin = -1;
    qlonglong globalMax = -1;

    for (const PolicyState &policy : policies) {
        if (policy.minFreqKHz > 0 && (globalMin < 0 || policy.minFreqKHz < globalMin)) {
            globalMin = policy.minFreqKHz;
        }
        if (policy.maxFreqKHz > 0 && (globalMax < 0 || policy.maxFreqKHz > globalMax)) {
            globalMax = policy.maxFreqKHz;
        }
    }

    const QString minText = formatFrequencyKHz(globalMin);
    const QString maxText = formatFrequencyKHz(globalMax);
    if (!minText.isEmpty() && !maxText.isEmpty()) {
        return minText + QStringLiteral(" - ") + maxText;
    }
    if (!maxText.isEmpty()) {
        return maxText;
    }
    return minText;
}

QString summarizeBiosLimit(const QList<PolicyState> &policies)
{
    QStringList biosLimits;
    for (const PolicyState &policy : policies) {
        const QString biosLimit = formatFrequencyKHz(policy.biosLimitKHz);
        if (!biosLimit.isEmpty()) {
            biosLimits << biosLimit;
        }
    }

    biosLimits = uniqueNonEmptyStrings(biosLimits);
    if (biosLimits.isEmpty()) {
        return QString();
    }
    if (biosLimits.size() == 1) {
        return QStringLiteral("BIOS limit: %1").arg(biosLimits.first());
    }

    return QStringLiteral("BIOS limits: %1").arg(biosLimits.join(QStringLiteral(", ")));
}

QString buildCurrentPolicySummary(const QList<PolicyState> &policies, const QString &currentGovernor, bool mixedGovernor, const QString &hardwareLimits, const QString &biosLimit)
{
    QStringList parts;
    if (!currentGovernor.isEmpty()) {
        parts << QStringLiteral("Governor: %1").arg(currentGovernor);
    } else if (mixedGovernor) {
        QStringList governors;
        for (const PolicyState &policy : policies) {
            if (!policy.currentGovernor.isEmpty()) {
                governors << policy.currentGovernor;
            }
        }
        governors = uniqueNonEmptyStrings(governors);
        parts << QStringLiteral("Governor: Mixed (%1)").arg(governors.join(QStringLiteral(", ")));
    }

    if (!hardwareLimits.isEmpty()) {
        parts << QStringLiteral("Range: %1").arg(hardwareLimits);
    }
    if (!biosLimit.isEmpty()) {
        parts << biosLimit;
    }

    return parts.join(QStringLiteral(" | "));
}

QStringList uniqueReadablePolicyFiles(const QString &fileName)
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

BoostState detectBoostState()
{
    BoostState state;

    const QString genericBoost = readTextFile(kCpufreqRoot + QStringLiteral("/boost"));
    if (!genericBoost.isEmpty()) {
        state.supported = true;
        state.active = genericBoost == QStringLiteral("1");
        state.control = QStringLiteral("cpufreq-boost");
        return state;
    }

    const QString noTurbo = readTextFile(kIntelPstateRoot + QStringLiteral("/no_turbo"));
    if (!noTurbo.isEmpty()) {
        state.supported = true;
        state.active = noTurbo == QStringLiteral("0");
        state.control = QStringLiteral("intel-pstate-no-turbo");
        return state;
    }

    const QStringList cpbFiles = uniqueReadablePolicyFiles(QStringLiteral("cpb"));
    if (!cpbFiles.isEmpty()) {
        bool allEnabled = true;
        for (const QString &path : cpbFiles) {
            if (readTextFile(path) != QStringLiteral("1")) {
                allEnabled = false;
            }
        }

        state.supported = true;
        state.active = allEnabled;
        state.control = QStringLiteral("policy-cpb");
    }

    return state;
}

QJsonObject buildStateObject()
{
    QJsonObject result;
    result.insert(QStringLiteral("ok"), false);

    const QStringList paths = policyPaths();
    if (paths.isEmpty()) {
        result.insert(QStringLiteral("errorCode"), QStringLiteral("missing_cpufreq"));
        return result;
    }

    QList<PolicyState> policies;
    for (const QString &path : paths) {
        policies << readPolicyState(path);
    }

    const QStringList commonGovernors = commonAvailableGovernors(policies);
    const QString availableGovernors = summarizeAvailableGovernors(policies, commonGovernors);
    bool mixedGovernor = false;
    const QString currentGovernor = summarizeCurrentGovernor(policies, &mixedGovernor);
    const QString hardwareLimits = summarizeHardwareLimits(policies);
    const QString biosLimit = summarizeBiosLimit(policies);
    const QString currentPolicy = buildCurrentPolicySummary(policies, currentGovernor, mixedGovernor, hardwareLimits, biosLimit);
    const BoostState boostState = detectBoostState();

    result.insert(QStringLiteral("ok"), true);
    result.insert(QStringLiteral("driver"), summarizeDrivers(policies));
    result.insert(QStringLiteral("availableGovernors"), availableGovernors);
    result.insert(QStringLiteral("currentGovernor"), currentGovernor);
    result.insert(QStringLiteral("mixedGovernor"), mixedGovernor);
    result.insert(QStringLiteral("policyCount"), policies.size());
    result.insert(QStringLiteral("hardwareLimits"), hardwareLimits);
    result.insert(QStringLiteral("currentPolicy"), currentPolicy);
    result.insert(QStringLiteral("biosLimit"), biosLimit);
    result.insert(QStringLiteral("boostSupported"), boostState.supported);
    result.insert(QStringLiteral("boostActive"), boostState.active);
    result.insert(QStringLiteral("boostControl"), boostState.control);

    QJsonArray governorsArray;
    for (const QString &governor : commonGovernors) {
        governorsArray.append(governor);
    }
    result.insert(QStringLiteral("availableGovernorsModel"), governorsArray);

    return result;
}

void printText(std::ostream &stream, const QString &text)
{
    if (!text.isEmpty()) {
        stream << text.toStdString() << std::endl;
    }
}

int runAction(const QString &actionName, const QVariantMap &arguments)
{
    KAuth::Action action(actionName);
    action.setHelperId(QString::fromLatin1(kHelperId));
    action.setArguments(arguments);

    if (!action.isValid()) {
        std::cerr << "CPUBOOST_ERROR:kauth_not_configured" << std::endl;
        return 1;
    }

    KAuth::ExecuteJob *job = action.execute();
    const bool ok = job->exec();
    const QVariantMap result = job->data();

    printText(std::cout, result.value(QStringLiteral("stdout")).toString().trimmed());
    printText(std::cerr, result.value(QStringLiteral("stderr")).toString().trimmed());

    if (!ok) {
        std::cerr << "CPUBOOST_ERROR:kauth_action_failed" << std::endl;
        printText(std::cerr, job->errorString().trimmed());
        return 1;
    }

    return 0;
}

} // namespace

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);

    const QStringList args = app.arguments();
    if (args.size() < 2) {
        std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
        return 2;
    }

    const QString command = args.at(1);
    if (command == QStringLiteral("read-state")) {
        const QJsonObject state = buildStateObject();
        std::cout << QJsonDocument(state).toJson(QJsonDocument::Compact).toStdString() << std::endl;
        return state.value(QStringLiteral("ok")).toBool() ? 0 : 1;
    }

    if (args.size() < 3) {
        std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
        return 2;
    }

    if (command == QStringLiteral("set-boost")) {
        const QString value = args.at(2);
        if (value != QStringLiteral("0") && value != QStringLiteral("1")) {
            std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
            return 2;
        }

        QVariantMap arguments;
        arguments.insert(QStringLiteral("applyBoost"), true);
        arguments.insert(QStringLiteral("boostEnabled"), value == QStringLiteral("1"));
        arguments.insert(QStringLiteral("applyGovernor"), false);
        arguments.insert(QStringLiteral("persistStartupState"), args.value(3) == QStringLiteral("1"));
        arguments.insert(QStringLiteral("restoreOnStartup"), args.value(3) == QStringLiteral("1"));
        arguments.insert(QStringLiteral("startupBoostState"), value == QStringLiteral("1") ? QStringLiteral("enabled") : QStringLiteral("disabled"));
        arguments.insert(QStringLiteral("startupGovernor"), QString());
        return runAction(QString::fromLatin1(kApplyStateAction), arguments);
    }

    if (command == QStringLiteral("set-governor")) {
        const QString governor = args.at(2);
        if (governor.isEmpty()) {
            std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
            return 2;
        }

        QVariantMap arguments;
        arguments.insert(QStringLiteral("applyBoost"), false);
        arguments.insert(QStringLiteral("boostEnabled"), false);
        arguments.insert(QStringLiteral("applyGovernor"), true);
        arguments.insert(QStringLiteral("governor"), governor);
        arguments.insert(QStringLiteral("persistStartupState"), args.value(3) == QStringLiteral("1"));
        arguments.insert(QStringLiteral("restoreOnStartup"), args.value(3) == QStringLiteral("1"));
        arguments.insert(QStringLiteral("startupBoostState"), QString());
        arguments.insert(QStringLiteral("startupGovernor"), governor);
        return runAction(QString::fromLatin1(kApplyStateAction), arguments);
    }

    if (command == QStringLiteral("sync-persistent-state")) {
        if (args.size() < 5) {
            std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
            return 2;
        }

        const QString restoreValue = args.at(2);
        const QString boostState = args.at(3) == QStringLiteral("-")
            ? QString()
            : args.at(3);
        const QString governor = args.at(4) == QStringLiteral("-")
            ? QString()
            : args.at(4);

        if (restoreValue != QStringLiteral("0") && restoreValue != QStringLiteral("1")) {
            std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
            return 2;
        }

        QVariantMap arguments;
        arguments.insert(QStringLiteral("applyBoost"), false);
        arguments.insert(QStringLiteral("boostEnabled"), false);
        arguments.insert(QStringLiteral("applyGovernor"), false);
        arguments.insert(QStringLiteral("governor"), QString());
        arguments.insert(QStringLiteral("persistStartupState"), true);
        arguments.insert(QStringLiteral("restoreOnStartup"), restoreValue == QStringLiteral("1"));
        arguments.insert(QStringLiteral("startupBoostState"), boostState);
        arguments.insert(QStringLiteral("startupGovernor"), governor);
        return runAction(QString::fromLatin1(kApplyStateAction), arguments);
    }

    if (command == QStringLiteral("apply-state")) {
        if (args.size() < 8) {
            std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
            return 2;
        }

        const QString applyBoost = args.at(2);
        const QString boostValue = args.at(3);
        const QString applyGovernor = args.at(4);
        const QString governor = args.at(5) == QStringLiteral("-") ? QString() : args.at(5);
        const QString restoreValue = args.at(6);
        const QString startupBoostState = args.at(7) == QStringLiteral("-") ? QString() : args.at(7);
        const QString startupGovernor = args.size() >= 9 && args.at(8) != QStringLiteral("-") ? args.at(8) : QString();

        if ((applyBoost != QStringLiteral("0") && applyBoost != QStringLiteral("1"))
            || (applyGovernor != QStringLiteral("0") && applyGovernor != QStringLiteral("1"))
            || (restoreValue != QStringLiteral("0") && restoreValue != QStringLiteral("1"))
            || (boostValue != QStringLiteral("0") && boostValue != QStringLiteral("1"))) {
            std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
            return 2;
        }

        QVariantMap arguments;
        arguments.insert(QStringLiteral("applyBoost"), applyBoost == QStringLiteral("1"));
        arguments.insert(QStringLiteral("boostEnabled"), boostValue == QStringLiteral("1"));
        arguments.insert(QStringLiteral("applyGovernor"), applyGovernor == QStringLiteral("1"));
        arguments.insert(QStringLiteral("governor"), governor);
        arguments.insert(QStringLiteral("persistStartupState"), true);
        arguments.insert(QStringLiteral("restoreOnStartup"), restoreValue == QStringLiteral("1"));
        arguments.insert(QStringLiteral("startupBoostState"), startupBoostState);
        arguments.insert(QStringLiteral("startupGovernor"), startupGovernor);
        return runAction(QString::fromLatin1(kApplyStateAction), arguments);
    }

    std::cerr << "CPUBOOST_ERROR:invalid_arguments" << std::endl;
    return 2;
}
