# Task Ferry

A small, private Mac app that ferries Apple Reminders between your personal and work Macs. The same binary runs in either role:

## Screenshots

<p align="center">
  <img src="docs/screenshots/task-ferry-main.png" alt="Task Ferry showing today's reminders" width="400">
  <br>
  <img src="docs/screenshots/task-ferry-quick-entry.png" alt="Task Ferry menu-bar quick entry" width="340">
</p>

- **Bridge** on the personal Mac mini: reads and writes Reminders with EventKit and serves one authenticated loopback endpoint.
- **Remote client** on the work Mac: shows Today, Tomorrow, lists, reminders, and due dates through a Cloudflare Tunnel.

There is no hosted database, web frontend, or account system. Apple Reminders remains the source of truth. Direct-distribution builds include only one runtime dependency: Sparkle for signed automatic updates.

## Architecture

```text
Work Mac app
  │ HTTPS + Cloudflare service token + bridge bearer token
  ▼
Cloudflare Access → Cloudflare Tunnel
                         │ HTTP on the same Mac only
                         ▼
                  127.0.0.1:8788/v1/rpc
                         │ EventKit
                         ▼
                  Apple Reminders / iCloud
```

Every mutation returns a complete authoritative snapshot. Due dates are transferred as calendar components, rather than absolute timestamps, so a date-only reminder stays date-only across time zones.

## Build and test

Requirements: macOS 14 or newer, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project TaskFerry.xcodeproj \
  -scheme TaskFerry \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .derivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES
```

Run the eight host-independent core tests with `xcodebuild test` and the same arguments.

For the safe sample UI used during development:

```sh
TASK_FERRY_DEMO=1 .derivedData/Build/Products/Debug/TaskFerry.app/Contents/MacOS/TaskFerry
```

Demo mode is in-memory and never requests Reminders access.

## Personal setup

### 1. Personal Mac mini

1. Build and launch the app, then choose **Share this Mac's reminders**.
2. Select **Allow Reminders Access** and approve the macOS Reminders permission.
3. In Settings, copy the generated bridge token and enable launch at login.
4. Keep the app running. It listens only on `127.0.0.1:8788`; it is not reachable from the LAN.

### 2. Cloudflare

Create a production Cloudflare Tunnel with a published application route from your chosen hostname to `http://localhost:8788`. Cloudflare documents the [published-application route](https://developers.cloudflare.com/tunnel/setup/#publish-an-application) and supports running `cloudflared` as a [macOS launch agent](https://developers.cloudflare.com/tunnel/advanced/local-management/create-local-tunnel/).

Protect the hostname with a Cloudflare Access self-hosted application and a **Service Auth** policy. Create a service token for this app. The client sends the documented `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers on every call; see [Cloudflare service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/).

`cloudflared` should remain a separately supervised system service. The app does not embed tunnel credentials or manage Cloudflare resources.

### 3. Work Mac

1. Install the signed app and choose **Connect to my Mac mini**.
2. Open Settings and enter the public HTTPS hostname, Cloudflare service-token ID and secret, and the bridge token from the Mac mini.
3. Select **Save & Test**, then enable launch at login if desired.

Secrets are stored in the macOS Keychain. Network requests use an ephemeral URL session with caching disabled.

## Scope

The current app intentionally supports only:

- writable reminder lists: create, rename, delete;
- incomplete reminders: create, edit, complete, delete;
- date-only and timed due dates;
- Today (including overdue) and Tomorrow;
- a menu-bar quick entry with list selection and None, Today, or Tomorrow due dates.

It intentionally omits notes, tags, priorities, recurrence, attachments, shared-list administration, completed-history browsing, offline writes, and conflict merging. Since each change is immediately applied to EventKit and followed by a fresh snapshot, there is no second task database to reconcile.

## Distribution

Task Ferry is a regular Mac app: it has a main window, appears in the Dock, and uses the standard application menu for About, Settings, Hide, and Quit. Its separate menu-bar item is a focused task-entry form.

The `Release-Direct` configuration follows the MenuMines direct-distribution pattern: Hardened Runtime, Developer ID signing, Apple notarization, a drag-to-Applications DMG, and EdDSA-signed Sparkle updates. Debug and ordinary Release builds remain sandboxed; the direct build is not sandboxed so Sparkle can replace the installed app cleanly.

Create releases with:

```sh
APPLE_TEAM_ID=YOUR_TEAM_ID scripts/release.sh 0.1.0
```

The script uses the `TaskFerry` notarization profile and the Sparkle private key in the login Keychain. It produces a versioned DMG, a stable `TaskFerry.dmg`, an update ZIP, and `appcast.xml` under `build/release/`.

The included GitHub Actions workflow publishes those four files when a `v*` tag is pushed. It requires these repository secrets:

- `DEVELOPER_ID_CERT_BASE64`
- `DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_ID`
- `APPLE_ID_PASSWORD` (an app-specific password)
- `APPLE_TEAM_ID`
- `SPARKLE_PRIVATE_KEY`

Sparkle's `generate_keys` tool stores the private update key in the login Keychain. Export it once with `generate_keys -x <temporary-file>`, copy it directly into the `SPARKLE_PRIVATE_KEY` repository secret, and remove the temporary file immediately.

The release repository must be publicly readable so a corporate Mac can download the DMG and Sparkle appcast without GitHub credentials. The Developer ID certificate and notarization credentials are the only pieces that cannot be created from source code.

## License

Copyright © 2026 MeriMeriMeri Software. Task Ferry is licensed under the [GNU Affero General Public License v3.0 only](LICENSE). Distributed modifications—and modified versions offered to users over a network—must make their corresponding source available under the same license. The license does not permit relicensing Task Ferry as a closed proprietary product.
