#include <iostream>

#include <QCoreApplication>

#include "cpuboost-sysfs.h"

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);

    CpuBoost::PersistentState state;
    QString errorText;
    if (!CpuBoost::loadPersistentState(&state, &errorText)) {
        std::cerr << errorText.toStdString() << std::endl;
        return 1;
    }

    if (!state.restoreOnStartup) {
        return 0;
    }

    if (state.boostState == QStringLiteral("enabled") || state.boostState == QStringLiteral("disabled")) {
        if (!CpuBoost::applyBoostState(state.boostState == QStringLiteral("enabled"), &errorText)) {
            std::cerr << errorText.toStdString() << std::endl;
            return 1;
        }
    }

    if (!state.governor.isEmpty()) {
        if (!CpuBoost::applyGovernor(state.governor, &errorText)) {
            std::cerr << errorText.toStdString() << std::endl;
            return 1;
        }
    }

    return 0;
}
