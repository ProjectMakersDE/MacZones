# MacZones

English | [Deutsch](README.de.md)

**Lightweight window zone snapping for macOS.**

MacZones is a deliberately minimal alternative to tools like
[MacsyZones](https://github.com/rohanrhu/MacsyZones). It does exactly one
thing, snapping windows into zones you define, and it does it with **close to
0 % CPU when idle**.

The app's menus are in German. This README names each menu item in German with
an English translation.

## Why?

Many window managers run with a constantly high CPU load (polling, analytics,
background tasks). MacZones has **no timers and no polling**. All runtime
activity hangs on a single passive `CGEventTap` that **only fires while a mouse
button is actually pressed** (down / up / drag). If you move the mouse without
pressing a button, MacZones receives no event at all. At rest there are no
wakeups and no measurable CPU load.

## Features (and only these)

- **Right-click drag**: hold the right mouse button over a window and drag.
  The window follows the pointer and the zones appear; release over a zone and
  the window snaps into it. (A normal right-click without dragging opens the
  context menu as usual.)
- **Snap on shake**: drag a window as usual and shake it briefly back and
  forth. The zones appear; release over a zone and the window snaps into it.
- **Combine several zones**: drag across several adjacent zones and the window
  spans their combined area.
- **Zone editor per screen**: draw, move, resize and delete zones. Open it from
  the menu or with the shortcut **⌃⌥Z**.
- **Auto grid**: split a screen automatically into *n* columns × *m* rows
  (with an optional gap), either in the editor or directly from the menu
  "Schnelles Raster" (Quick Grid).
- **Profiles**: save different zone layouts and switch between them; kept
  separately for each screen.
- **Menu bar icon** with all options, optionally "Bei Anmeldung starten"
  (Launch at Login).

Deliberately **not** included: statistics/analytics, background daemons,
cloud sync, keyboard tiling, excessive animations. Nothing that costs
performance while idle.

## Installation

### Prebuilt release (recommended)

1. Download the latest `MacZones.dmg` (or `.zip`) from
   [Releases](../../releases).
2. Drag `MacZones.app` into the **Applications** folder.
3. Because the app is not notarized by Apple, remove the Gatekeeper quarantine
   once:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MacZones.app
   ```
4. Open MacZones from **Applications** as usual (double-click). There is **no
   Dock icon**: MacZones is a menu bar tool and shows its icon at the top right
   of the menu bar. That icon gives you all settings (profiles, grid,
   permission, Launch at Login, and so on). If you open the app again from
   Applications while it is already running, its menu opens automatically.
5. On first launch, let it ask for the **Accessibility** permission (see
   below). You can also grant the permission at any time from the menu bar
   menu.

### Build it yourself

Requirements: macOS 13+, Xcode / Swift 5.9+.

```bash
git clone https://github.com/ProjectMakersDE/MacZones.git
cd MacZones
./scripts/build-app.sh
open dist
```

The script creates a universal (Apple silicon + Intel) `MacZones.app`,
including `.zip` and `.dmg`, in `dist/`.

#### Install locally (with a stable signature)

So that local builds have the same signing identity as the releases (and the
Accessibility permission is kept), set up the local signing identity once.
After that you can build and install to `/Applications` at any time:

```bash
./scripts/setup-local-signing.sh        # once: certificate + local keychain (+ CI secrets)
./scripts/install-local.sh "$(git describe --tags --abbrev=0)"   # builds signed and installs to /Applications
```

The argument is the version written into the app; the command above uses the
latest release tag.

`setup-local-signing.sh` creates a dedicated signing keychain
(`~/Library/Keychains/maczones-signing.keychain-db`) and stores the same
certificate as GitHub secrets, so CI releases and local builds are signed
identically.

## Permission

MacZones needs **Accessibility** access to move windows of other apps and to
detect mouse gestures:

> System Settings › Privacy & Security › **Accessibility** →
> enable MacZones.

No restart needed: as soon as the permission is granted, MacZones works right
away.

**The permission is kept across updates:** release builds are signed with a
**stable, self-signed certificate** (the same identity for every build). macOS
ties the Accessibility grant to this identity, so you only grant it **once**
and it stays in place for future updates. (When switching from an old ad-hoc
signed version, remove the old "MacZones" entry once (−) and add it again.)

## Updates

MacZones updates itself from GitHub Releases:

- Menu → **"Auf Updates prüfen …"** (Check for Updates) downloads the latest
  release, installs it and restarts MacZones (the permission is kept thanks to
  the same certificate).
- **"Beim Start nach Updates suchen"** (Check for Updates at Launch, on by
  default) runs *one* silent check at launch; if a newer version is available,
  the menu shows a notice. No background polling.
- The installed version is shown at the top of the menu and under **"Über
  MacZones"** (About MacZones).

### Signing certificate (for maintainers)

The signing certificate is created once and stored as GitHub secrets:

```bash
./scripts/create-signing-cert.sh ProjectMakersDE/MacZones
```

This sets the secrets `SIGNING_CERTIFICATE_P12_BASE64` and
`SIGNING_CERTIFICATE_PASSWORD`. The build workflow imports them and signs with
them. Without these secrets the build falls back to ad-hoc signing
automatically.

## Quick reference

| Action | How |
| --- | --- |
| Edit zones | Menu → "Zonen bearbeiten" (Edit Zones) or **⌃⌥Z** |
| Split a zone | In the editor, **click inside a zone** (splits at that point); **⌥** = horizontal |
| Start with one zone | Palette → "Auf eine Zone zurücksetzen" (Reset to One Zone), then split |
| Auto grid | Palette → "Schnellauswahl" (Quick Select), or enter any number of columns/rows (up to 64 × 32) |
| Snap a window (right-click) | Hold the right mouse button over a window → drag → release over a zone |
| Snap a window (shake) | Drag a window → shake briefly → release over a zone |
| Several zones | While dragging, move across adjacent zones |
| Quick grid | Menu → "Schnelles Raster" (Quick Grid, applies to the screen under the mouse) |
| Switch profile | Menu → "Profil" (Profile) |

## Architecture

| File | Purpose |
| --- | --- |
| `EventTapController.swift` | The one `CGEventTap`; handles both gestures, swallows right-click drags, inactive when idle. |
| `ShakeDetector.swift` | Detects the shake from drag positions (pure arithmetic). |
| `SnapSession.swift` | Zone overlays + target calculation during a gesture. |
| `ZoneEditorController.swift` | Editor window + palette, auto grid, profiles. |
| `AX.swift` | Accessibility: find / move / resize windows. |
| `ScreenManager.swift` | Coordinate conversion Cocoa ↔ Quartz, per screen. |
| `ProfileStore.swift` | Profiles + settings as JSON in Application Support. |
| `StatusBarController.swift` | Menu bar menu. |

## License

MIT, see [LICENSE](LICENSE).
