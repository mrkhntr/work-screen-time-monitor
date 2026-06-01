# Work Screen Time App

A local macOS menu bar utility that nudges you out of work during configured downtime windows. It sends a normal macOS notification before downtime, watches for keyboard/mouse activity during downtime, and shows a full-screen prompt when you are still active.

## Product And Engineering Principles

- Prefer SwiftUI for app UI, settings, menus, prompt content, and new user-facing surfaces.
- Use AppKit only as a small adapter when SwiftUI does not expose the required macOS behavior, such as screen-saver-level prompt windows across every connected display.
- Prefer built-in Apple frameworks over custom infrastructure. If a feature can be simplified by using a native SwiftUI or macOS API, simplify it.
- Use `https://sosumi.ai/` as the preferred Apple documentation lookup path for SwiftUI, AppKit, and other Apple framework API checks.
- Keep the app local, understandable, and boring to maintain. Avoid broad abstractions unless they remove real complexity.
- Use Docusaurus for the friend-facing download/docs site in `website/`.

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

## Releasing a New Version

The release process is fully automated with GitHub Actions. You **do not** need to update the `VERSION` file manually. 

To release a new version, simply tag the `main` branch with the new version number and push the tag to GitHub:

```sh
git tag v1.0.24
git push origin v1.0.24
```

The GitHub Actions pipeline will:
1. Extract the version number directly from the tag (`1.0.24`).
2. Build the `.dmg` package using `create-dmg`.
3. Auto-generate release notes dynamically by reading the git commit messages since the *last* tag.
4. Upload the built DMG to a new GitHub Release.
5. Generate a new `appcast.xml` and HTML release notes for Sparkle Auto-Updates.
6. Deploy the Docusaurus landing page and Sparkle appcast via GitHub Pages.

*Note: The `VERSION` file exists only as a fallback for local un-versioned development builds.*

## Build

```sh
scripts/build_app.sh
```

The app bundle is created at:

```text
.build/WorkScreenTimeApp.app
```

The build script runs the Swift Package Manager release build, embeds Sparkle, writes the generated app plist, ad-hoc signs the local app bundle, and exports a DMG.

Useful release build options:

```sh
scripts/build_app.sh --version 1.0.17 --build 1000017 --dmg .build/WorkScreenTimeApp-1.0.17.dmg
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

For unsigned friend/team builds, newer macOS versions may block the first launch. Recommended workarounds:

- Try Finder: right‑click (or Control‑click) the app and choose **Open**, then confirm **Open** in the dialog. This still works on many macOS releases.
- If that doesn't appear, open **System Settings** (or **System Preferences** on older macOS) → **Privacy & Security** (or **Security & Privacy**) and look for an "Open Anyway" / "Allow" button for the blocked app under the General/Security section; click it and re-open the app.
- Advanced / CLI option: remove the quarantine attribute and open from Terminal:

```bash
xattr -r -d com.apple.quarantine .build/WorkScreenTimeApp.app
open .build/WorkScreenTimeApp.app
```

Note: notarized or Developer ID–signed builds do not require these steps; Gatekeeper behavior varies by macOS version and security settings.

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

When creating the GitHub Release on the repository after pushing the tag, please add a clear release description that explains what this release does. The CI creates artifacts and performs several actions — including building the app, running tests, signing the packaged zip with the Sparkle key, and publishing the updated appcast and website — so the release notes should document those items for reviewers and users.

Suggested release notes template:

```
Summary: Short one-line overview of the change (bugfix / features / maintenance).

Includes:
- Built app bundle: `.build/WorkScreenTimeApp.app`
- Signed zip: `WorkScreenTimeApp-<version>.zip` (Sparkle-signed)
- Updated appcast: `appcast.xml` (Sparkle feed) deployed to website/static

Checks performed by CI:
- `swift test` run in CI
- Docusaurus site built and deployed
- Signed release artifact using `SPARKLE_PRIVATE_KEY` secret

Notes for users/admins:
- If you install a locally-built unsigned app, allow via Finder → Open on first run.
- Sparkle will verify updates using the embedded public key.
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

## Accountability Webhook

Settings can send a `POST` request to notify an accountability contact when you cross a downtime boundary. The request is disabled by default. When enabled, it fires:

- on **every dismiss** you make from the prompt, and
- on a **snooze** once that day's total snooze count reaches `snoozeNotifyThreshold` (default `3`, i.e. the 3rd snooze onward).

The full-screen prompt shows a yellow warning when the currently selected action (snooze or dismiss) will notify your contact, so there are no surprises. A typed reason is optional and is included when present; when a dismiss has no reason, `{{reason}}`/`{{dismissalReason}}` render as `<No Reason Given>`. A prompt that auto-expires after an hour records a local dismissal but does **not** send a message.

The snooze threshold is configured directly in the JSON (there is no Settings field for it). Edit `config.json` while the app is quit:

```json
{
  "accountabilityWebhook": {
    "isEnabled": true,
    "endpointURLString": "https://example.com/hook",
    "snoozeNotifyThreshold": 3
  }
}
```

The request always includes a `message` key rendered from the message template. You can add extra body keys in Settings; for a WhatsApp bridge, add:

```json
{
  "groupId": "ad@g.us"
}
```

The request always sends `Content-Type: application/json` and `Accept: application/json`. The Headers table can add enabled custom headers such as `x-api-key: <key>` or `Authorization: Bearer <token>`.

The message template and extra body values support `{{message}}`, `{{reason}}`, `{{dismissalReason}}`, `{{event}}`, `{{timestamp}}`, `{{dateKey}}`, `{{windowID}}`, `{{snoozeCount}}`, and `{{app}}`. Unknown placeholders are shown as a warning in Settings and are left unchanged when sent.

## Escalation

- 0 snoozes: gentle reminder and quote.
- 1 snooze: firmer reminder.
- 2 snoozes: snooze/dismiss requires holding the unlock button.
- 3+ snoozes: snooze/dismiss requires holding the unlock button, typing the current work-life-balance prompt exactly, and writing a short reason.

Snooze remains available at every level.

## Enforcement State Machine

Activity detection and enforcement follow a two-state machine. The tick interval adapts per state.

```
              ┌─────────────────┐                                     │
              │     NORMAL      │  tick: 10s (downtime) / 60s (idle) │
              │                 │                                     │
              └────────┬────────┘                                     │
                       │ activity detected during downtime            │
                       │                                              │
                       ▼                                              │
     ┌─────────────┐                                                  │
     │  FULLSCREEN │  tick: 5s · user can snooze or dismiss          │
     │   PROMPT    │                                                  │
     └──────┬──────┘                                                  │
            │                                                         │
   ┌────────┴──────────────────────────────────────────┐             │
   │ user action                                        │ auto-expiry │
   │ snooze / dismiss / pause                          │ downtime ended  →  reset NORMAL
   └──────────────────────────────────────►NORMAL      │ 1 hr elapsed    →  dismiss + reset NORMAL
                                                        └──────────────────────────────►NORMAL
```

**Resume Now** clears pause, snooze, or current-window dismissal state. If downtime is active and you are still working, enforcement begins immediately.
