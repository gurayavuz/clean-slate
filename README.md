# Clean Slate

[![Build](https://github.com/gurayavuz/clean-slate/actions/workflows/build.yml/badge.svg)](https://github.com/gurayavuz/clean-slate/actions/workflows/build.yml)

Dragging an app to the Trash removes the app. It leaves everything else — preferences,
caches, containers, launch agents, saved state, cookies — scattered across `~/Library`
under names you'd never think to search for.

Clean Slate finds those files, shows you what it found and why it thinks each one belongs
to that app, and deletes only what you tick.

A menu bar app. No Dock icon, no network access, nothing phones home.

## Requirements

- macOS 14 or later
- Swift toolchain — `xcode-select --install` if you don't have it

## Install

```sh
git clone https://github.com/gurayavuz/clean-slate
cd clean-slate
./build.sh
```

That builds the app, signs it, and installs it to `/Applications`. Launch it from there;
it appears as ✨ in the menu bar.

There is deliberately only one copy — `/Applications/Clean Slate.app`. The bundle is
staged inside `.build/` during the build, because a second identically-named app sitting
next to the source is a trap: it has no Full Disk Access grant, so launching it by mistake
silently finds less.

## Grant Full Disk Access — do this first

**Without this, Clean Slate misses files.** macOS hides parts of `~/Library` from apps
that haven't been granted access, and there is no way for an app to ask for it on your
behalf.

1. System Settings → Privacy & Security → **Full Disk Access**
2. **+**, then choose `/Applications/Clean Slate.app`
3. Quit Clean Slate from the ✨ menu — closing the window isn't enough
4. Open it again

The app tells you when it's working blind: an amber card at the top of the results reading
"*N* folders couldn't be read". If you don't see it, you're fully granted.

## A signing certificate you make yourself

The Full Disk Access grant is tied to the app's code signature, not its location. Without a
stable signing identity, macOS treats each rebuild as a different app and the grant quietly
stops working — the switch stays on, but it no longer applies.

`build.sh` signs with a certificate called **Clean Slate Local Signing** and warns you if it
can't find one, falling back to ad-hoc signing. To make it — one minute, free, once:

1. Open **Keychain Access**
2. Menu: Keychain Access → Certificate Assistant → **Create a Certificate…**
3. Name: `Clean Slate Local Signing`
4. Identity Type: **Self Signed Root**
5. Certificate Type: **Code Signing**
6. Create, then rebuild

Already have a Developer ID? Use it instead:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

The certificate lives in your keychain and never enters this repository. On a new Mac
you'll make a fresh one and grant Full Disk Access once more.

## Using it

Drop an app on the window, or pick one from the ✨ menu. Nothing is deleted while it looks.

Results are grouped by kind, biggest first, and every row is labelled by how confident the
match is:

| Badge | Means | Selected by default |
|---|---|---|
| **Certain** | Named after the app's bundle identifier, or its own container | Yes |
| **Likely** | Prefixed with the bundle identifier, or named exactly after the app | No |
| **Possible** | A name or vendor guess — may belong to a different app | No |

**Possible** is the one to read carefully. Removing Microsoft Word will offer you Excel's
and PowerPoint's containers too, because they share the `com.microsoft` prefix. That's why
they start unticked, why hovering any row explains the match, and why the confirmation
counts them back to you before anything moves.

Items go to the **Trash**, so mistakes are recoverable. Permanent deletion is available
under Options in the bottom-left and always asks first.

### Files that need an administrator

Anything under `/Library` or `/private/var` is listed but **never touched**. Tick the ones
you want, and Clean Slate hands you a `sudo` command to review and run yourself. Only what
you ticked goes into it.

## Menu bar and login

Clean Slate lives in the menu bar under ✨ and keeps running when you close the window —
Quit is in that menu, and ⌘Q works while the window is focused.

**Open at Login** in the same menu registers it with macOS via `SMAppService`; no helper
app, no launchd plist. Started that way, it stays quietly in the menu bar instead of opening
a window.

## Command line

```sh
# Show what the app would offer for a given .app, and delete nothing
"/Applications/Clean Slate.app/Contents/MacOS/CleanSlate" --scan /Applications/Foo.app

# Check or change the login item
"/Applications/Clean Slate.app/Contents/MacOS/CleanSlate" --login-item status
```

Run from a terminal, the scan reports on *your terminal's* permissions rather than the
app's, so it will often claim folders are unreadable even when the app itself can read
them. Trust the app window over the command line here.

## How it avoids deleting the wrong thing

- Matching errs toward silence — anything unrecognised is simply not offered
- App names shorter than four characters, and generic ones like `Mail`, `Player` or
  `Updater`, are refused for name matching entirely; only bundle identifiers count
- A protected-path list (`~`, `~/Documents`, `/Library`, every scan root itself…) is checked
  again at the moment of deletion, not just while scanning
- System paths cannot reach the deletion code at all — they are tracked separately from
  everything else
- The Trash is the default, so the undo is macOS's own

## Development

```sh
./build.sh              # release, installs to /Applications
./build.sh debug        # debug build, installs
./build.sh --no-install # build only, bundle left in .build/
```

Installing quits the running copy first, and re-registers the login item afterwards so the
setting keeps pointing at the app that's actually there.

## Contributing

Bug reports and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The
most useful report is a match that was wrong or missing, with the app and path involved.

Found a way to make it delete something it shouldn't? Report it privately:
[SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE) — Copyright 2026 guray.

Use it, change it, ship it. It comes with no warranty of any kind: this software deletes
files, and you are the one deciding which.
