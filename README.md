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

Create a production Cloudflare Tunnel on the personal Mac mini:

1. In the Cloudflare dashboard, go to **Networking → Tunnels**, create a tunnel, and select macOS.
2. Run the installation command Cloudflare provides. It has this form:

   ```sh
   sudo cloudflared service install <TUNNEL_TOKEN>
   ```

3. Open the tunnel's **Routes** tab and add a **Published application** route with:
   - Hostname: `reminders.merimerimeri.com`
   - Service URL: `http://localhost:8788`
4. If a DNS A or AAAA record already exists for `reminders.merimerimeri.com`, remove it before adding the route. Do not point the hostname at `127.0.0.1`, a private IP address, or the Mac mini's public IP. Saving the tunnel route creates the correct Cloudflare DNS record.

Cloudflare documents the [published-application route](https://developers.cloudflare.com/tunnel/setup/#publish-an-application) and supports running `cloudflared` as a [macOS service](https://developers.cloudflare.com/tunnel/advanced/local-management/as-a-service/macos/). `cloudflared` should remain a separately supervised system service. The app does not embed tunnel credentials or manage Cloudflare resources.

#### Public testing

For initial testing, leave **Protect with Access** disabled on the tunnel route. The hostname will be publicly reachable, but the bridge still rejects requests that do not include Task Ferry's bearer token.

On the remote Mac, leave the Cloudflare client ID and secret blank, enter `https://reminders.merimerimeri.com` as the Server URL, enter the bridge token from the Mac mini, and select **Save & Test**.

#### Recommended Zero Trust protection

For normal use, protect the hostname with Cloudflare Access:

1. Go to **Zero Trust → Access controls → Service credentials → Service Tokens**.
2. Create a service token named `Task Ferry Work Mac`. Copy both the Client ID and Client Secret; Cloudflare displays the secret only once.
3. Go to **Access controls → Applications** and create a **Self-hosted and private** application.
4. Add `reminders.merimerimeri.com` as its public hostname.
5. Add an Access policy with:
   - Action: **Service Auth**
   - Include selector: **Service Token**
   - Value: `Task Ferry Work Mac`
6. Enable **401 Response for Service Auth policies**. On the tunnel's published application route, enable **Protect with Access** if that option is shown.
7. On the remote Mac, enter the service token's Client ID and Client Secret in Task Ferry and select **Save & Test** again.

Task Ferry sends the documented `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers on every request when those fields are configured. Cloudflare Access and the bridge bearer token provide two independent authentication layers; see [Cloudflare service tokens](https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/).

### 3. Work Mac

1. Install the signed app and choose **Connect to my Mac mini**.
2. Open Settings and enter the public HTTPS hostname and the bridge token from the Mac mini. If Cloudflare Access is enabled, also enter the service-token Client ID and Client Secret.
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
