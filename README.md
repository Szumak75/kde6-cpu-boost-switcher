# CPU Boost Switcher

`CPU Boost Switcher` is a Plasma 6 plasmoid for the panel that reads CPU boost and governor state from Linux `sysfs` and applies privileged changes through `KAuth`/Polkit.

When startup restore is enabled, the project can also persist the selected boost/governor state to a root-owned file and restore it during boot through a system `systemd` unit. This avoids interactive password prompts during login and reboot.

The project ships localization scaffolding for multiple languages. At runtime the plasmoid resolves user-facing strings from the current system locale via an in-package translation helper, and the repository also includes `po/` sources plus a helper script for rebuilding the packaged `.mo` catalogs.

## Features

- Panel icon with three visual states:
  - green CPU icon when boost is active
  - gray CPU icon when boost is inactive
  - gray CPU icon with a red strike when boost is unsupported or a blocking runtime issue is detected
- Popup panel with:
  - current boost state
  - support status
  - CPU driver, detected boost control, and hardware limits
  - available governors and governor selection
  - toggle switch for enabling/disabling boost
  - switch deciding whether saved boost/governor settings should be restored on startup
  - manual refresh button
  - diagnostics dialog
- Automatic refresh every 10 seconds by default
- Refresh interval control directly in the popup and in the standard plasmoid configuration page
- Runtime diagnostics for:
  - missing CPU frequency `sysfs` controls
  - missing `KAuth` client/helper installation
  - failed `KAuth` authorization
  - driver/platform combinations that do not expose writable boost controls
  - failed synchronization of the startup restore state
  - saved startup settings that cannot be restored on the current system

## Runtime requirements

- KDE Plasma 6
- a working Polkit authentication agent in the Plasma session
- system-wide installation of the `KAuth` helper, D-Bus service, and Polkit policy files
- `systemd`, if you want saved settings to be restored during boot

Reading the current state uses `sysfs`, including:

```bash
/sys/devices/system/cpu/cpufreq/policy*/scaling_driver
/sys/devices/system/cpu/cpufreq/policy*/scaling_governor
/sys/devices/system/cpu/cpufreq/policy*/scaling_available_governors
/sys/devices/system/cpu/cpufreq/boost
/sys/devices/system/cpu/intel_pstate/no_turbo
/sys/devices/system/cpu/cpufreq/policy*/cpb
```

Changing the state writes directly to the appropriate `sysfs` control for the active driver:

```bash
/sys/devices/system/cpu/cpufreq/boost
/sys/devices/system/cpu/intel_pstate/no_turbo
/sys/devices/system/cpu/cpufreq/policy*/cpb
/sys/devices/system/cpu/cpufreq/policy*/scaling_governor
```

Those write operations are executed by a privileged `KAuth` helper after Polkit authorization. The QML code does not invoke `sudo`, and the project no longer depends on parsing human-readable `cpupower` output.

The same codepath is intended to work on both Intel and AMD systems. At runtime the applet detects which writable boost interface is present on the current machine and uses that backend:

- `/sys/devices/system/cpu/cpufreq/boost`
- `/sys/devices/system/cpu/intel_pstate/no_turbo`
- `/sys/devices/system/cpu/cpufreq/policy*/cpb`

Governor state is also aggregated across all detected `policy*` directories so the UI can safely represent mixed-policy systems and only offer governors that are valid across the machine.

On startup, the plasmoid can optionally reconcile the current system state with the last successfully saved CPU Boost and governor settings. This behavior is controlled by the `Restore saved settings on startup` switch in the popup and in the standard configuration page.

The default value is `false`. When the option is disabled, the plasmoid treats the current system state as the source of truth after startup and updates its stored desired values from the current `sysfs` state instead of trying to restore older values from configuration.

When the option is enabled, the plasmoid writes the desired startup state to `/var/lib/kde6-cpu-boost-switcher/state.ini` through the privileged helper. The installed `systemd` service can then restore that state during boot without requiring an interactive password prompt from the applet session.

Inside the running Plasma session, the plasmoid still attempts to reconcile the current CPU state after the first successful refresh. If a saved option is no longer available, the plasmoid leaves the system unchanged and reports a diagnostic message instead of forcing an invalid configuration.

## Installation

### Build dependencies

On openSUSE Leap 15.6, install at least:

```bash
sudo zypper install cmake gcc-c++ extra-cmake-modules kf6-kauth-devel kf6-kcoreaddons-devel qt6-base-devel
```

Runtime packages required on the target system:

```bash
sudo zypper install polkit
```

### Build

For a working setup, configure the build with `/usr` as the install prefix:

```bash
cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j$(nproc)
```

This matters because the project defaults `CMAKE_INSTALL_PREFIX` to `~/.local` when the prefix is omitted. That default is convenient for local plasmoid iteration, but it is not sufficient for the privileged helper, D-Bus activation, Polkit policy, and boot-time restore integration. If an existing build directory was configured with the wrong prefix, re-run CMake with `-DCMAKE_INSTALL_PREFIX=/usr` or use a fresh build directory.

### Install

This project has a mandatory system-wide part:

- the privileged `KAuth` helper, the startup restore tool, the `systemd` unit, and the D-Bus/Polkit files must be installed system-wide
- the plasmoid package and `KAuth` client can live in the Plasma data directory, but user-scoped installation alone is not sufficient for helper activation

Install both components system-wide:

```bash
sudo cmake --install build --component Plasmoid
sudo cmake --install build --component KAuthSystem
```

Enable the boot-time restore service if you want saved settings to be applied automatically during system startup:

```bash
sudo systemctl enable cpuboost-restore.service
```

You can test or run it manually with:

```bash
sudo systemctl start cpuboost-restore.service
```

This unit is defined as `Type=oneshot`, so after a successful run `systemctl status` will normally show it as `inactive (dead)`. That is the expected state, not a failure.

After installation, restart Plasma Shell if the widget does not refresh automatically:

```bash
kquitapp6 plasmashell && kstart6 plasmashell
```

or

```bash
kquitapp6 plasmashell && kstart plasmashell
```

## Configuration

The plasmoid currently exposes these settings:

- refresh interval in seconds
- restore saved boost/governor settings on startup

When startup restore is enabled:

- changing boost or governor from the plasmoid updates the persisted boot-time state
- disabling the option removes the persisted boot-time state file
- the next boot can restore the saved state through `systemd` without another password prompt

When startup restore is disabled, `/var/lib/kde6-cpu-boost-switcher/state.ini` is removed or left absent. In that case the `cpuboost-restore.service` condition check is skipped intentionally and no state is restored during boot.

## Localization

Translation domain:

```text
plasma_applet_io.github.szumak75.cpu-boost-switcher
```

Included starter catalogs:

- Polish (`pl`)
- German (`de`)
- French (`fr`)
- Spanish (`es`)

To rebuild `.mo` files after editing the `.po` sources:

```bash
./scripts/build-translations.sh
```

The helper script uses `msgfmt`, so translation rebuilds require GNU gettext tools to be installed.

## Troubleshooting

If the plasmoid reports a diagnostic error:

1. Ensure the relevant `sysfs` controls exist for the current platform:
   - `/sys/devices/system/cpu/cpufreq/policy*/scaling_driver`
   - `/sys/devices/system/cpu/cpufreq/policy*/scaling_governor`
   - one of:
     - `/sys/devices/system/cpu/cpufreq/boost`
     - `/sys/devices/system/cpu/intel_pstate/no_turbo`
     - `/sys/devices/system/cpu/cpufreq/policy*/cpb`
2. Ensure the plasmoid package itself is installed in the active Plasma data path.
3. Ensure the plasmoid install includes `contents/bin/cpuboost-kauth-client`.
4. Ensure the helper is installed in the KF6 KAuth helper directory. On the current build configuration that resolves to:
   - `/usr/libexec/kf6/kauth/cpuboost-kauth-helper`
   - on some distributions the exact `libexec` prefix may differ, but it must match the `Exec=` path in `io.github.szumak75.kde6cpuboostswitcher.helper.service`
5. Ensure these system files exist:
   - `/usr/share/dbus-1/system-services/io.github.szumak75.kde6cpuboostswitcher.helper.service`
   - `/usr/share/dbus-1/system.d/io.github.szumak75.kde6cpuboostswitcher.helper.conf`
   - `/usr/share/polkit-1/actions/io.github.szumak75.kde6cpuboostswitcher.helper.policy`
   - `/usr/lib/systemd/system/cpuboost-restore.service` or `/lib/systemd/system/cpuboost-restore.service`
   - `/usr/libexec/kde6-cpu-boost-switcher/cpuboost-restore-state` or the corresponding libexec path on your distribution
6. Ensure a Polkit authentication agent is running in the current Plasma session.
7. If boot-time restore is enabled, ensure the systemd unit is enabled:

```bash
systemctl is-enabled cpuboost-restore.service
```

8. If state detection still looks wrong, try the client manually:

```bash
<plasmoid-data-path>/io.github.szumak75.cpu-boost-switcher/contents/bin/cpuboost-kauth-client read-state
```

9. If authorization works but writes still fail, inspect the writable `sysfs` files directly for the active driver:

```bash
ls /sys/devices/system/cpu/cpufreq/boost
ls /sys/devices/system/cpu/intel_pstate/no_turbo
find /sys/devices/system/cpu/cpufreq -name cpb -o -name scaling_governor
```

## Project layout

- `package/metadata.json` – plasmoid metadata
- `package/contents/ui/main.qml` – root applet controller and command orchestration
- `package/contents/ui/CompactRepresentation.qml` – panel icon view
- `package/contents/ui/FullRepresentation.qml` – popup UI and diagnostics dialog
- `package/contents/ui/CpuBoostIcon.qml` – custom processor icon
- `package/contents/ui/CommandRunner.qml` – executable command bridge
- `package/contents/code/CpuBoostParser.js` – parsing and diagnostics helpers
- `package/contents/config/main.xml` – serialized settings schema
- `systemd/cpuboost-restore.service.in` – boot-time restore unit template
- `po/*.po` – translation sources
- `scripts/build-translations.sh` – helper script for compiling `.po` files to `.mo`
- `src/cpuboost-sysfs.cpp` – shared `sysfs` and persistent-state backend
- `src/restore-state.cpp` – root-side startup restore tool used by `systemd`
