#include <KAuth/ActionReply>
#include <KAuth/HelperSupport>
#include <QCoreApplication>
#include <QVariantMap>

#include "cpuboost-sysfs.h"

namespace {

constexpr const char *kHelperId = "io.github.szumak75.kde6cpuboostswitcher.helper";

KAuth::ActionReply helperErrorReply(int code, const QString &stderrText)
{
    KAuth::ActionReply reply = KAuth::ActionReply::HelperErrorReply(code);
    reply.setErrorDescription(stderrText);
    reply.addData(QStringLiteral("stderr"), stderrText);
    return reply;
}

class CpuBoostHelper : public QObject
{
    Q_OBJECT

public:
    explicit CpuBoostHelper(QObject *parent = nullptr)
        : QObject(parent)
    {
    }

public Q_SLOTS:
    KAuth::ActionReply applyState(const QVariantMap &args)
    {
        const bool applyBoost = args.value(QStringLiteral("applyBoost")).toBool();
        const bool boostEnabled = args.value(QStringLiteral("boostEnabled")).toBool();
        const bool applyGovernor = args.value(QStringLiteral("applyGovernor")).toBool();
        const QString governor = args.value(QStringLiteral("governor")).toString().trimmed();
        const bool persistStartupState = args.value(QStringLiteral("persistStartupState")).toBool();
        const bool restoreOnStartup = args.value(QStringLiteral("restoreOnStartup")).toBool();
        const QString startupBoostState = args.value(QStringLiteral("startupBoostState")).toString().trimmed();
        const QString startupGovernor = args.value(QStringLiteral("startupGovernor")).toString().trimmed();

        if (!CpuBoost::isValidBoostState(startupBoostState)
            || !CpuBoost::isValidGovernorName(governor)
            || !CpuBoost::isValidGovernorName(startupGovernor)) {
            return helperErrorReply(2, QStringLiteral("CPUBOOST_ERROR:invalid_arguments"));
        }

        QString errorText;
        if (applyBoost) {
            if (!CpuBoost::applyBoostState(boostEnabled, &errorText)) {
                return helperErrorReply(1, errorText);
            }
        }

        if (applyGovernor) {
            if (governor.isEmpty()) {
                return helperErrorReply(2, QStringLiteral("CPUBOOST_ERROR:invalid_arguments"));
            }

            if (!CpuBoost::applyGovernor(governor, &errorText)) {
                return helperErrorReply(1, errorText);
            }
        }

        if (persistStartupState) {
            if (!CpuBoost::syncPersistentState(restoreOnStartup, startupBoostState, startupGovernor, &errorText)) {
                return helperErrorReply(1, errorText);
            }
        }

        return KAuth::ActionReply::SuccessReply();
    }
};

}

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    CpuBoostHelper helper;
    return KAuth::HelperSupport::helperMain(argc, argv, kHelperId, &helper);
}

#include "kauth-helper.moc"
