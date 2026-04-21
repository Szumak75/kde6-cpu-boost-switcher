#pragma once

#include <QString>
#include <QStringList>

namespace CpuBoost {

struct PersistentState
{
    bool restoreOnStartup = false;
    QString boostState;
    QString governor;
};

QString readTextFile(const QString &path);
bool writeTextFile(const QString &path, const QString &value, QString *errorText);
QStringList policyPaths();
QStringList uniqueWritablePolicyFiles(const QString &fileName);

bool isValidBoostState(const QString &value);
bool isValidGovernorName(const QString &value);

QString persistentStateFilePath();
bool loadPersistentState(PersistentState *state, QString *errorText);
bool savePersistentState(const PersistentState &state, QString *errorText);
bool clearPersistentState(QString *errorText);
bool syncPersistentState(bool restoreOnStartup, const QString &boostState, const QString &governor, QString *errorText);
bool updatePersistentBoostState(bool enabled, QString *errorText);
bool updatePersistentGovernor(const QString &governor, QString *errorText);

bool applyBoostState(bool enabled, QString *errorText);
bool applyGovernor(const QString &governor, QString *errorText);

} // namespace CpuBoost
