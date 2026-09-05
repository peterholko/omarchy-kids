# Kids deployment

Omarchy Kids supports converting a clean Omarchy 4 laptop and installing a fresh laptop from the dedicated Kids ISO. Both use the same seven package archives and `omarchy-kids-setup` to configure the account. Upstream PR acceptance is not a prerequisite.

## Existing laptop

Build with `./packaging/build`, then run `./packaging/install ./build-output --user CHILD_USERNAME --convert`. The default selection is all five modules. Existing child installations use `--all` instead of `--convert`; an update with neither flag retains the installed module selection.

Conversion requires the standard Omarchy 4 package layout, completed user setup, one regular local account with a working password, and ordinary sudo rules. It checks these conditions, package hashes and identities before installing. The parent supplies a different password, and the current disk-unlock password if encryption is present. It never formats the disk, changes the kid login password, removes existing encryption slots or overwrites the home directory.

The progress journal and recovery copies live under `/var/lib/omarchy/kids-conversion`, accessible only to root. They include the original account files, PAM and sudo rules, and a LUKS header backup for encrypted installs. Plaintext passwords are never saved there. Retrying the same command resumes the same account. An interrupted disk-key addition checks whether the parent key already works before adding another. A completed conversion becomes an ordinary package update on retry.

Both deployments require a reboot before use by the kid. Conversion removes wheel and docker membership and clears the kid’s sudo timestamp; processes from the previous session retain their old supplementary groups until they exit. The desktop module controls are added without resetting personal configuration. Browsing collection and optional restrictions remain disabled until a parent enables them.

## Fresh laptop

The Kids ISO builder accepts a complete, clean, committed x86_64 release directory. It verifies the seven archives, extracts the installer form and package lists from that exact runtime archive, and adds the packages and their dependency closure to the offline mirror. The image always installs the child profile. A matching `release.json` and all seven packages are copied to `/var/cache/omarchy-kids/packages` on the target.

The builder is maintained separately from the upstream installer PR, with its revision pinned by Omarchy Kids. The ISO and package artifacts carry their source revision and checksums. A public download release is separate from building an artifact in this private repository.

In GitHub, wait for **Kids modules** CI to pass, then run **Actions → Kids ISO → Run workflow** for that revision. It uses the matching package artifact from the passing tests and conversion checks, builds an ISO, and drives a fresh encrypted child installation in a KVM virtual machine. The ISO download artifact is uploaded only after that acceptance test passes. Test logs and screenshots are retained even on failure. Downloads from this private repository require GitHub access; distributing a public release is a separate step.

To build and test on an x86_64 Linux machine with Docker and enough free space for an ISO and VM disk:

```bash
./packaging/build
./packaging/iso build ./build-output
./packaging/iso test ./build-output/iso/GENERATED_ISO_FILENAME.iso
```

Use a committed checkout: the ISO builder rejects dirty or mixed package releases. `packaging/iso-builder.ref` pins the installer revision. ISO testing requires `/dev/kvm`. The ISO, SHA-256 checksum and source/build metadata land under `build-output/iso`; acceptance screenshots and logs are in its `test` directory. Flash the resulting ISO to a USB drive and boot the fresh laptop, then follow the kid and parent password prompts.

## Validation

`./test/kids` includes conversion recovery and release-validation tests. GitHub Actions builds the real packages and tests namespace upgrades. A separate disposable Linux container exercises conversion, real parent-only sudo authentication, PAM configuration, retained child credentials, additive LUKS keys and a repeat installation. The ISO workflow additionally installs a freshly built image into a disposable VM; its screenshots and logs are the evidence for the fresh-install path. Unit and container checks alone do not establish that a laptop boots successfully.
