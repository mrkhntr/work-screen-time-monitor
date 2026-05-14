# Work Screen Time App

A local macOS menu bar utility that nudges you out of work during configured downtime windows. It sends a normal macOS notification before downtime, watches for keyboard/mouse activity during downtime, and shows a full-screen prompt when you are still active.

## What It Does

- Runs as a SwiftUI `MenuBarExtra` menu bar app.
- Starts on login with the app's built-in Launch at Login menu toggle.
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
scripts/build_app.sh --version 1.0.17 --build 1000017 --zip .build/WorkScreenTimeApp-1.0.17.zip
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

- Feed URL: `https://mrkhntr.com/work-screen-time-monitor/appcast.xml`
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
git tag v1.0.17
git push origin v1.0.17
```

The GitHub Actions release workflow will:

- install the Docusaurus website dependencies;
- run tests;
- build and zip `WorkScreenTimeApp.app`;
- create or update the matching GitHub Release;
- sign the zip with the Sparkle private key secret;
- build the Docusaurus download page with the release download URL;
- deploy the download page and `appcast.xml` to this repo's GitHub Pages project site.

GitHub Pages serves the download page and appcast at:

```text
https://mrkhntr.com/work-screen-time-monitor/
https://mrkhntr.com/work-screen-time-monitor/appcast.xml
```

The workflow uses GitHub Pages project-site routing for this repo, matching the pattern used by `mrk-app`. No app repo `CNAME` is needed. Pages should be configured to deploy from GitHub Actions.

Set the Sparkle repository secret before pushing a release tag:

```sh
scripts/set_github_sparkle_secret.sh
```

### Download Site

The friend-facing download page is a small Docusaurus site in `website/`.

```sh
cd website
npm install
npm run start
```

The release workflow copies the generated Sparkle appcast into `website/static/appcast.xml` before running `npm run build`. That generated XML is ignored locally.

## Start On Login

Use the menu bar item and choose **Enable Launch at Login**. The app uses macOS `SMAppService.mainApp`, so there is no separate LaunchAgent to install or keep in sync.

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

**Resume Now** clears pause, snooze, or current-window dismissal state. If downtime is active and you are still working, the normal grace and monitoring flow starts again.
