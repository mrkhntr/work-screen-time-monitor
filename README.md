# Work Screen Time — monorepo

A local screen-time / work-downtime enforcer for **macOS** and **Android**. It nudges (and, opt-in,
blocks) you out of work during your configured downtime windows, with escalating prompts and an
optional accountability webhook.

## Layout

| Path | What |
|------|------|
| `shared/core/` | **The brain.** A pure TypeScript core (schedule, escalation, accountability, webhook, app-block decisions, state machine). Built to a single `dist/core.js` that **both** apps run — macOS via JavaScriptCore, Android via QuickJS. Native code is only UI + a thin shell that feeds events in and runs the effects the core returns. |
| `mac_os/` | The macOS app (Swift + SwiftUI, Sparkle auto-updates). Menu-bar app. See `mac_os/README.md`. |
| `android_os/` | The Android app (Kotlin + Jetpack Compose, AccessibilityService-based blocking). |
| `shared/` | `SCHEMA.md` (canonical config schema), `test-fixtures/` both platforms load, default quotes/phrase. |
| `website/` | Docusaurus download/docs site, deployed to GitHub Pages with the Sparkle appcast. |
| `.github/` | Release CI (tag-driven `v*.*.*` → builds the macOS DMG, signs the Sparkle update, deploys the site). |

## Architecture: functional core + imperative shell

All behavior lives in `shared/core` as a pure, synchronous reducer:

```
reduce(state, event, now) -> { state, effects[] }
```

The native shells supply events (`tick`, `foregroundChanged`, `userSnoozed`, …) with a
native-resolved `now` (so the core never touches timezones), and execute the returned effects
(`showOverlay`, `postNotification`, `sendWebhook`, `persistState`, `scheduleWake`, …). The same
`dist/core.js` runs on both platforms, so the two apps behave identically by construction.

## Building

- **Shared core:** `cd shared/core && npm install && npm test && npm run build` → `dist/core.js`.
- **macOS:** `swift build --package-path mac_os` / `swift test --package-path mac_os`; package the
  app with `mac_os/scripts/build_app.sh`. See `mac_os/README.md`.
- **Android:** open `android_os/` in Android Studio (or `./gradlew assembleDebug`).

## Releasing (macOS)

Tag-driven, unchanged by the monorepo move: `git tag v1.0.36 && git push origin v1.0.36`. CI builds
the DMG, signs the Sparkle update, regenerates the appcast, and deploys the website to GitHub Pages.
