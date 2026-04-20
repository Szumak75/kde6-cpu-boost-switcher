# CPU Boost Switcher

`CPU Boost Switcher` is a Plasma 6 plasmoid for the panel that reads the current CPU boost state from `cpupower frequency-info` and lets the user request `cpupower set --turbo-boost 0|1`.

The applet UI now uses English strings consistently, which avoids mixed-language output and provides a cleaner baseline for future localization work.

The project ships localization scaffolding for multiple languages. At runtime the plasmoid resolves user-facing strings from the current system locale via a lightweight in-package translation helper, and the repository also includes `po/` plus compiled `.mo` catalogs as a starting point for future KDE/Gettext integration.

## Features

- Panel icon with three visual states:
  - green CPU icon when boost is active
  - gray CPU icon when boost is inactive
  - gray CPU icon with a red strike when boost is unsupported or a blocking runtime issue is detected
- Popup panel with:
  - current boost state
  - support status
  - CPU driver and hardware limits
  - available governors and governor selection
  - toggle switch for enabling/disabling boost
  - manual refresh button
  - diagnostics dialog
- Automatic refresh every 10 seconds by default
- Refresh interval control directly in the popup and in the standard plasmoid configuration page
- Runtime diagnostics for:
  - missing `cpupower`
  - missing `sudo`
  - `sudo` authentication requirements
  - missing `sudo` privileges
  - unexpected `cpupower` output format
  - saved startup settings that cannot be restored on the current system

## Runtime requirements

- KDE Plasma 6
- `cpupower` available in `PATH`
- `sudo` available in `PATH` for state changes
- Permission to run `sudo cpupower set --turbo-boost 0|1`

Reading the current state uses:

```bash
cpupower frequency-info
```

Changing the state uses:

```bash
sudo cpupower set --turbo-boost 0
sudo cpupower set --turbo-boost 1
sudo cpupower frequency-set -g <governor>
```

The plasmoid executes these commands with `LC_ALL=C` so the parser can rely on the English `boost state support` block.

On startup, the plasmoid also reconciles the current system state with the last successfully saved CPU Boost and governor settings. If a saved option is no longer available, the plasmoid leaves the system unchanged and reports a diagnostic message instead of forcing an invalid configuration.

## Installation

```bash
cmake -B build -S .
cmake --install build
```

By default, files are installed to:

```text
~/.local/share/plasma/plasmoids/io.github.szumak75.cpu-boost-switcher
```

For a system-wide install:

```bash
cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr
sudo cmake --install build
```

After installation, restart Plasma Shell if the widget does not refresh automatically:

```bash
kquitapp6 plasmashell && kstart6 plasmashell
```

or

```bash
kquitapp6 plasmashell && kstart plasmashell
```

## Configuration

The plasmoid currently exposes one setting:

- refresh interval in seconds

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

## Troubleshooting

If the plasmoid reports a diagnostic error:

1. Ensure `cpupower frequency-info` works in a terminal.
2. Ensure `sudo` is installed and available in `PATH`.
3. Check whether `sudo -n cpupower set --turbo-boost 1` is allowed for the current user.
4. If `sudo` requires a password or is denied, configure `sudoers` appropriately or replace the execution path with a policy-based helper.

## Project layout

- `package/metadata.json` – plasmoid metadata
- `package/contents/ui/main.qml` – root applet controller and command orchestration
- `package/contents/ui/CompactRepresentation.qml` – panel icon view
- `package/contents/ui/FullRepresentation.qml` – popup UI and diagnostics dialog
- `package/contents/ui/CpuBoostIcon.qml` – custom processor icon
- `package/contents/ui/CommandRunner.qml` – executable command bridge
- `package/contents/code/CpuBoostParser.js` – parsing and diagnostics helpers
- `package/contents/config/main.xml` – serialized settings schema
- `po/*.po` – translation sources
- `scripts/build-translations.sh` – helper script for compiling `.po` files to `.mo`
