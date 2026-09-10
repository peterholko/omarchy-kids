# Community plugin exports

These adapters publish five root plugins, including one combined School & Screen Time plugin from Omarchy Kids without changing the built-in Kids packages. They target the stock Omarchy Quattro plugin API and use IDs under `io.github.peterholko.*`.

```bash
python3 packaging/community/export.py /tmp/omarchy-community-exports
COMMUNITY_EXPORT=/tmp/omarchy-community-exports python3 -m unittest discover -s test/community -v
```

The destination must be new or empty. Commit source changes before the release export so each generated `SOURCE.json` identifies the exact source revision. Exported game repositories include their Node logic tests and portable Qt visual tests. The exporter dereferences the native MathModel symlink; published plugins contain regular files only.

School & Screen Time includes both controllers and one parent control panel, backed by one controls service. The old School Mode plugin is superseded. It installs separately through the explicit `sudo ./setup --user USER` step documented in its generated README. The service has separate password, configuration, runtime and state paths; it does not alter OS accounts or adopt existing Omarchy Kids policies. School Mode's desktop effects require a second, unprivileged consent command. The service `VERSION` identifies the bundled privileged payload; changing an installed service requires an explicit upgrade.

Before publishing, run the stock `omarchy-plugin-validate` against each exported root, the marketplace's manifest and security-baseline validators, the focused service/export tests and the exported game tests. Portable Qt tests exercise actual game views, but mocks of Quickshell IPC or systemd do not validate Linux installation or desktop enforcement. Record that limitation in release/submission notes. No ISO build or GitHub Actions is needed for this process.

Create public repositories without workflows and disable Actions before pushing. Follow the marketplace's [SUBMISSION.md](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md), including the owner’s review of the completed issue titles, bodies and five checklist statements before creating submission issues.
