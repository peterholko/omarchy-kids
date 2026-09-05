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

To build on an x86_64 Linux machine with Docker and enough free space for the build and ISO:

```bash
./packaging/build
./packaging/iso build ./build-output
```

Use a committed checkout: the ISO builder rejects dirty or mixed package releases. `packaging/iso-builder.ref` pins the installer revision. The ISO, SHA-256 checksum and source/build metadata land under `build-output/iso`. Flash the resulting ISO to a USB drive and boot the fresh laptop, then follow the kid and parent password prompts.

For optional local VM testing, run `./packaging/iso test ./build-output/iso/GENERATED_ISO_FILENAME.iso`. This requires `/dev/kvm` and enough space for the VM disk. Acceptance screenshots and logs are saved in `build-output/iso/test`.

## Validation

`./test/kids` includes conversion recovery and release-validation tests. Run package-upgrade and conversion integration checks only in a disposable Linux container. These cover real parent-only sudo authentication, PAM configuration, retained child credentials, additive LUKS keys and a repeat installation. Local ISO acceptance installs the image into a disposable VM and saves screenshots and logs for inspection. Unit and container checks alone do not establish that a laptop boots successfully.
