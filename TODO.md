# TODO

Recommended implementation order for the next development phase.

## 1. Stabilization and regression safety

- [ ] Add a minimal CI pipeline that configures and builds the project on a Plasma 6 / Qt 6 environment.
- [ ] Add backend-focused tests for `src/cpuboost-sysfs.cpp` helpers where logic can be validated without touching the real host system.
- [ ] Add tests for `src/kauth-client.cpp` state aggregation logic, especially mixed `policy*` governor and driver scenarios.
- [ ] Define a small compatibility matrix for real-world validation: Intel + `intel_pstate`, AMD + `amd-pstate`, generic `cpufreq/boost`, and `policy*/cpb`.
- [ ] Review error contracts between C++ and QML so JSON fields and `CPUBOOST_ERROR:*` codes are treated as a stable interface.

## 2. Plasma 6 execution layer cleanup

- [ ] Replace or reduce reliance on `Plasma5Support.DataSource` with a more future-proof Plasma 6 compatible execution approach.
- [ ] Rework `Makefile` Plasma restart logic to avoid `kstart` for `plasmashell` startup where possible.
- [ ] Revisit install and runtime assumptions that differ across distributions, especially helper, `libexec`, and session restart behavior.

## 3. Refactor the QML controller layer

- [ ] Split `package/contents/ui/main.qml` into smaller responsibilities: state management, diagnostics, startup restore sync, and command construction.
- [ ] Move reusable diagnostic mapping or state conversion logic out of `main.qml` into dedicated helper modules where practical.
- [ ] Review popup state updates and busy handling so refresh/apply/sync flows stay easy to reason about.

## 4. Localization and UX consistency

- [ ] Unify the translation approach so the project does not continue to mix `tr(...)` and custom `I18n.tr(...)` patterns indefinitely.
- [ ] Audit newly added diagnostic recommendations and platform-specific messages for full localization coverage.
- [ ] Improve diagnostics UX by showing more structured platform hints when mixed policies or unsupported controls are detected.

## 5. Packaging and release readiness

- [ ] Add release-oriented build helpers or presets for common scenarios such as normal release, debug build, and staged install.
- [ ] Document a repeatable release checklist: version bump, translation rebuild, clean build, install verification, and runtime smoke test.
- [ ] Review whether the project should ship distro-specific packaging metadata later (for example spec/PKGBUILD/deb packaging inputs).

## 6. Functional expansion after stabilization

- [ ] Evaluate support for additional CPU policy controls beyond boost/governor, such as EPP/EPB where the platform exposes them.
- [ ] Consider user-facing performance profiles that map to boost + governor combinations.
- [ ] Consider optional integration with platform tools such as `powerprofilesctl` when this can be done without weakening the current direct-`sysfs` model.
- [ ] Consider extending the UI with explicit per-policy diagnostics when systems expose mixed policy state.

## Out of scope for now

- [ ] Do not merge KDE5-specific runtime assumptions back into this KDE6 fork.
- [ ] Do not broaden the feature set before tests, execution cleanup, and packaging reliability are improved.
