# Repository guide

- Generate the Xcode project with `xcodegen generate`; edit `project.yml`, not project settings by hand.
- Keep one native app target and avoid runtime dependencies unless a concrete requirement makes one unavoidable.
- The app has two roles: EventKit bridge and remote client. Apple Reminders is always the source of truth.
- Preserve due dates as `ReminderDue` calendar components. Never replace date-only values with absolute `Date` timestamps on the wire.
- Fetch EventKit objects by identifier for each mutation. Do not cache `EKReminder` or `EKCalendar` instances across requests.
- Keep the bridge bound to loopback. Cloudflare Tunnel and Access are separate operational layers.
- Never log or persist credentials outside Keychain.
- Use `REMINDERS_REMOTE_DEMO=1` for UI verification so tests cannot mutate real reminders or trigger privacy prompts.
- Run the core tests after substantive model, protocol, or service changes. They are intentionally host-independent because a `MenuBarExtra` app is not a reliable XCTest host.
