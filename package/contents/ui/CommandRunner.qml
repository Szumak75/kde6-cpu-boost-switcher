import QtQuick 2.15
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: runner
    visible: false

    property bool running: false
    property var currentContext: ({})

    signal finished(var context, int exitCode, string stdout, string stderr)

    function run(command, context) {
        if (running) {
            return false
        }

        currentContext = context || {}
        running = true
        executable.connectSource(command)
        return true
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(sourceName, data) {
            const stdout = data["stdout"] || ""
            const stderr = data["stderr"] || ""
            const exitCode = data["exit code"] !== undefined ? data["exit code"] : -1

            disconnectSource(sourceName)
            runner.running = false
            runner.finished(runner.currentContext, exitCode, stdout, stderr)
        }
    }
}
