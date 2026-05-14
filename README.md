# Work Screen Time App

A local macOS menu bar utility that nudges you out of work during configured downtime windows. It sends a normal macOS notification before downtime, watches for keyboard/mouse activity during downtime, and shows a full-screen prompt when you are still active.

## What It Does

- Runs as a SwiftUI `MenuBarExtra` menu bar app.
- Starts on login with a per-user LaunchAgent.
- Uses Apple Screen Time-style weekday rows with enabled toggle, start time, and end time.
- Supports overnight windows.
- Defaults to:
  - Monday-Friday: `6:00 PM` to `6:00 AM`
  - Saturday-Sunday: `4:00 PM` to `10:00 AM`
- Sends a downtime warning notification 15 minutes before each window.
- Prompts immediately if you are active during downtime.
- Snoozes for 15 minutes and notifies you of the snoozed-until time.
- Tracks snoozes in local JSON and escalates after repeated snoozes.

## Build

```sh
scripts/build_app.sh
```

The app bundle is created at:

```text
.build/WorkScreenTimeApp.app
```

The build script runs the Swift Package Manager release build, embeds Sparkle, writes the generated app plist, ad-hoc signs the local app bundle, and exports a zip unless `--no-zip` is passed.

Useful release build options:

```sh
scripts/build_app.sh --version 1.0.12 --build 1000012 --zip .build/WorkScreenTimeApp-1.0.12.zip
scripts/build_app.sh --no-zip
```

This workspace also includes `Package.swift`, so on a healthy Swift toolchain you can run:

```sh
swift build
swift test
```

If the toolchain is not healthy, start with:

```sh
xcode-select -p
xcrun --find swift
swift --version
```

If `swift`, `git`, or `xcrun` reports that the Xcode license has not been accepted, run:

```sh
sudo xcodebuild -license
```

If `Foundation` or other SDK modules fail to import because the compiler and SDK were built with different Swift versions, install a matching full Xcode or matching Command Line Tools, then select it:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Run

```sh
open .build/WorkScreenTimeApp.app
```

The first launch should request notification permission. If you miss it, enable notifications in System Settings.

For unsigned friend/team builds, macOS may require right-clicking the app and choosing **Open** the first time.

## Auto-Updates

The app uses Sparkle 2 for update checks. Installed copies do not need git, source files, Xcode, or Swift.

- Feed URL: `https://workscreen.mrkhntr.com/releases/work-screen-time/appcast.xml`
- Check interval: daily
- Install behavior: Sparkle asks before installing an available update.
- Update verification: Sparkle EdDSA signatures.
- Apple Developer ID signing: not required for v1, but first-run Gatekeeper approval may be required.

The committed public Sparkle key is embedded into the generated app plist. The private key must stay out of git and be available to GitHub Actions as `SPARKLE_PRIVATE_KEY`.

To create or reuse the local Sparkle key and set the GitHub secret:

```sh
swift package resolve
scripts/set_github_sparkle_secret.sh
```

That script exports the private key from the local Keychain only long enough to pass it to `gh secret set`.

### Publishing A Release

Releases are tag-driven. Push a semantic version tag:

```sh
git tag v1.0.12
git push origin v1.0.12
```

The GitHub Actions release workflow will:

- run tests;
- build and zip `WorkScreenTimeApp.app`;
- create or update the matching GitHub Release;
- sign the zip with the Sparkle private key secret;
- update `releases/work-screen-time/appcast.xml` on `main`.

Your `mrkhntr.com` hosting must serve that appcast file at:

```text
https://workscreen.mrkhntr.com/releases/work-screen-time/appcast.xml
```

The workflow commits the appcast into this repo under `releases/work-screen-time/`. GitHub Pages is configured to serve this repo's `main` branch from the repo root with `CNAME` set to `workscreen.mrkhntr.com`.

## Start On Login

After building:

```sh
scripts/install_launch_agent.sh
```

The installer writes a per-user LaunchAgent to:

```text
~/Library/LaunchAgents/app.workscreentime.WorkScreenTimeApp.plist
```

That plist points at the resolved absolute executable path inside the app bundle. For this checkout, it ends with:

```text
.build/WorkScreenTimeApp.app/Contents/MacOS/WorkScreenTimeApp
```

If you move, delete, or rebuild the app bundle at a different path, run `scripts/install_launch_agent.sh` again so launchd has the current executable path. You can also pass an explicit app bundle path:

```sh
scripts/install_launch_agent.sh /path/to/WorkScreenTimeApp.app
```

To remove startup:

```sh
scripts/uninstall_launch_agent.sh
```

Useful LaunchAgent checks:

```sh
plutil -lint ~/Library/LaunchAgents/app.workscreentime.WorkScreenTimeApp.plist
launchctl print gui/$(id -u)/app.workscreentime.WorkScreenTimeApp
tail -n 100 ~/Library/Logs/app.workscreentime.WorkScreenTimeApp.err.log
```

## Local Files

Config:

```text
~/Library/Application Support/WorkScreenTimeApp/config.json
```

History:

```text
~/Library/Application Support/WorkScreenTimeApp/history.json
```

The SwiftUI Settings window edits the same JSON config. You can also edit the JSON directly while the app is quit.

## Escalation

- 0 snoozes: gentle reminder and quote.
- 1 snooze: firmer reminder.
- 2 snoozes: snooze/dismiss requires holding the unlock button.
- 3+ snoozes: snooze/dismiss requires holding the unlock button, typing `I am done for today`, and writing a short reason.

Snooze remains available at every level.

## Enforcement State Machine

Activity detection and enforcement follow a three-state machine. The tick interval adapts per state.

```
                        ┌─────────────────────────────────────────────┐
                        │                                             │
                        ▼                                             │
              ┌─────────────────┐                                     │
              │     NORMAL      │  tick: 10s (downtime) / 60s (idle) │
              │                 │                                     │
              └────────┬────────┘                                     │
                       │ activity detected during downtime            │
                       │                                              │
                       ▼                                              │
              ┌─────────────────┐                                     │
              │      GRACE      │  tick: 5s  · duration: 30s         │
              │                 │  notification fires once            │
              └────────┬────────┘                                     │
                       │ 30s elapsed                                  │
                       │                                              │
                       ▼                                              │
              ┌─────────────────┐                                     │
              │   MONITORING    │  tick: 5s  · window: 60s           │
              │                 │  observes for any input             │
              └────────┬────────┘                                     │
                       │                                              │
            ┌──────────┴──────────┐                                  │
            │ activity seen?      │                                   │
           YES                   NO                                   │
            │                    └──────────────────────────────────►┘
            ▼                                   reset to NORMAL
     ┌─────────────┐
     │  FULLSCREEN │  tick: 5s · user can snooze or dismiss
     │   PROMPT    │
     └──────┬──────┘
            │
   ┌────────┴──────────────────────────────────────────┐
   │ user action                                        │ auto-expiry (tick checks each 5s)
   │ snooze / dismiss / pause                          │ downtime ended  →  close, reset NORMAL
   └──────────────────────────────────────►NORMAL      │ 1 hr elapsed    →  dismiss + reset NORMAL
                                                        └──────────────────────────────►NORMAL
```

**Resume Now** sets a separate 30-second grace (`resumeGraceUntil`) that suppresses the state machine
regardless of phase, then lets it run normally once expired.
