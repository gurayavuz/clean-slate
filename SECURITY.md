# Security Policy

## Reporting a vulnerability

Please report privately rather than in a public issue: use
[**Report a vulnerability**](https://github.com/gurayavuz/clean-slate/security/advisories/new)
under the Security tab.

Expect a first reply within a week. If you get none, open a public issue saying
only that you are waiting on a private report — no details.

## What counts

This app deletes files, so the interesting bugs are the ones that widen what it
is willing to delete:

- A path outside the scan roots reaching the deletion code
- A protected path (`~`, `~/Documents`, `/Library`, a scan root itself) getting past
  the check made at deletion time
- A crafted app name or bundle identifier that makes an unrelated app's files match
- Anything under `/Library` or `/private/var` reaching deletion instead of the
  sudo command handed back to the user
- Symlink or path-traversal tricks that move deletion outside what the UI listed

A **Possible** badge on a file that turns out to belong to another app is not a
vulnerability — that is the documented meaning of the badge, which is why those
rows start unticked. A **Certain** badge on the wrong file is.

## Scope

Clean Slate makes no network connections and has no server, no update channel, and
no telemetry. There is no remote attack surface to report against.

The build is signed with a certificate you generate yourself; it is not notarized
and is not distributed as a binary. Trust in a build comes from having built it.

## Supported versions

The tip of `main` is the only supported version. Fixes land there.
