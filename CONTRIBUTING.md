# Contributing

Bug reports and pull requests are welcome.

## Building

```sh
./build.sh --no-install   # build only, bundle left in .build/
./build.sh debug          # debug build, installed to /Applications
```

Set up the self-signed certificate described in the [README](README.md#a-signing-certificate-you-make-yourself)
first. Without it every rebuild is a different app to macOS, the Full Disk Access
grant stops applying, and you will spend an afternoon debugging a scanner that
"suddenly finds nothing".

## Reporting a bug

The useful bug report for this app is a *missed* or *wrong* match. Include:

- macOS version, and whether Full Disk Access is granted
- The app you scanned — its name and bundle identifier
- The path that was wrong, and which badge it carried (Certain / Likely / Possible)
- Output of `"/Applications/Clean Slate.app/Contents/MacOS/CleanSlate" --scan /Applications/Foo.app`

Paths under `~/Library` can carry account names and the names of other apps you
have installed. Redact whatever you would rather not publish; a partial report is
better than none.

## Pull requests

CI builds both configurations and verifies the signed bundle. Before opening a PR:

- `swift build -c release` cleanly
- `./build.sh --no-install`, then click through a scan of a real app

The bar for matching logic is deliberately lopsided. A missed file is an
inconvenience; a wrongly-offered file is somebody's data in the Trash. New match
rules should:

- Err toward silence — if a heuristic is unsure, it should not offer the file
- Carry the right badge, and default to unticked below **Certain**
- Explain themselves in the row's hover text, in the same plain language as the rest
- Leave `/Library` and `/private/var` on the sudo-command path, never the deletion path

Changes that widen what gets selected by default need a good argument in the PR
description.

## Style

Match the surrounding code. Comments explain *why* a thing is done, not what the
line does — the existing files are the reference.
