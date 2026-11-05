# Notchy schedule sync

This tool reads browser schedule pages and writes a local cache that Notchy merges with macOS calendar events. Chromium starts only for a sync or manual login and closes afterward. A single headless browser reads enabled sources sequentially. Nothing runs continuously unless you enable the optional four-hour launchd timer.

The bundled adapters connect Messier teaching schedules and BINUS LMS college schedules. Messier reads dated teaching sessions and exam proctor assignments from the current semester. BINUS LMS reads the previous, current, and next month, including exams. Both use Asia/Jakarta times. Messier work shifts are excluded because the inspected shift response has no dates.

Your configured sources are outside the repository. The example sources start disabled for a fresh installation.

## Set up

From this directory, run:

```sh
npm ci
npx playwright install chromium
node cli.mjs init
```

Edit `~/Library/Application Support/NotchyScheduleSync/config.json`. The bundled Messier and LMS URLs and adapters are already filled in. Set `enabled` to `true` for each source you want. Keep each source ID unchanged after setup. IDs use lowercase letters, numbers, underscores, and hyphens.

The cache goes to `~/Library/Containers/com.talax0n.notchy/Data/Library/Application Support/Notchy/schedules.json`. Run Notchy once before setting up the tool so macOS creates its app container. `output` and `stateDirectory` are optional config properties for testing. Relative paths resolve against the configuration directory. Use `--config /absolute/path/config.json` with any command to use another config.

## Sign in and sync

```sh
node cli.mjs login teaching
node cli.mjs login college
node cli.mjs sync
node cli.mjs status
```

Login opens Chromium. Complete your usual login and any two-step verification, navigate to the schedule, then press Enter in the terminal. Cookies, local storage, and IndexedDB are saved per source. Sync reuses that session in headless Chromium. Public pages do not require the login step. If a portal requires a fresh login or blocks headless access, sync reports a failure and keeps that source's last successful schedule. Run `login` again when needed.

Saved browser sessions can provide access to your accounts. They live outside the repository in `~/Library/Application Support/NotchyScheduleSync/sessions/`, with private directory and file permissions. Do not share them or generated browser code containing credentials. Microsoft passwords are entered during login and are not kept by this tool. Messier can also renew its login from `~/Library/Application Support/NotchyScheduleSync/credentials/teaching.json`. This optional private file contains a JSON object with `username` and `password`. Keep its permissions at `0600`. Without that file, use `login teaching` to renew the saved browser session. Credentials never belong in the config or repository. Portals that depend on sessionStorage or device-bound sign-in may need a custom adapter or renewed login.

## Extraction rules

For a simple page, use the `selectors` shape in `config.generic.example.json`. These are CSS selectors read from the actual authenticated schedule page:

- `ready` identifies the authenticated schedule view. A login screen must never match it.
- `rows` identifies event rows after the schedule has loaded.
- `empty` identifies an explicit loaded empty schedule. An absent row alone never clears cached events.
- `fields` maps event fields to a selector relative to each row, with an optional `attribute` property. `:scope` reads an attribute on the row itself.

Events require a title, start, and end. Dates must contain seconds and an explicit timezone, such as `2026-11-05T09:00:00+07:00`. The generic adapter does not guess the meaning of `05/11/26`, `Monday`, or `09.00`. If the portal only exposes human-readable or repeating timetable values, write a custom adapter to turn the actual date, time, and timezone into timestamps.

A stable portal event ID is preferred. Without one, the tool derives an ID from the normalized event fields. Identical duplicate rows collapse. Conflicting rows with the same ID fail the source and preserve its cache. Different sources remain distinct even when their times and titles match.

For pagination, week navigation, frames, API responses, or complex date parsing, set `adapter` to a `.mjs` file relative to the config instead of `selectors`. The file must export a default async function:

```js
export default async function scrape(page, source) {
  // Navigate and read the real portal here.
  // Return only after proving that the authenticated schedule finished loading.
  return events;
}
```

The adapter receives a Playwright Page already navigated to `source.url` and the source config. It returns an array of `{ id?, title, start, end, location?, url? }`. Only HTTP(S) source and event URLs are accepted. Event times normalize to UTC in the cache. Extraction has a 90-second limit. An adapter must throw when authentication expires, loading fails, pagination is incomplete, or the page format is unrecognized. Return an empty array only after verifying that the schedule is actually empty. A sync replaces the complete event set for each successful source, so adapters must fetch the whole date range you want available in Notchy.

Playwright's generated recording can supply navigation steps and locators. Remove the test wrapper and login steps, and use those steps inside the adapter. It still needs extraction and date conversion code. A recording alone does not read a schedule.

## Failure behavior

A failed refresh preserves that source's last successful events and timestamp, sets its error, and exits with code 1. Other sources still refresh. Successful empty schedules clear old events. Removing or disabling a source removes it from the next successfully written cache. Cache writes use atomic replacement so Notchy sees complete JSON. A process lock prevents overlapping login/sync operations; an abandoned lock from a dead process is recovered on the next run.

## Optional timer

After a successful manual sync:

```sh
node cli.mjs launchd
```

This writes `~/Library/LaunchAgents/com.talax0n.notchy.schedule-sync.plist` with absolute Node, script, and config paths. It does not activate it. Activate and stop it with:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.talax0n.notchy.schedule-sync.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.talax0n.notchy.schedule-sync.plist
```

The timer runs every four hours while your user session is active. Logs are in `~/Library/Application Support/NotchyScheduleSync/logs/`. Moving this checkout or changing the Node installation requires regenerating the plist and reloading the timer. The app remains usable when the tool fails or is not running.

## Verify

Run the Swift cache-model checks from the repository root:

```sh
./scripts/test-browser-schedules.sh
```

Run the browser tool tests from this directory:


```sh
npm test
```

Tests cover timestamp validation, duplicate IDs, per-source failure retention, disabled-source removal, private atomic writes, overlapping-run rejection, and a real headless Chromium scrape against a temporary local server. Adapter tests also check Jakarta timestamps, exam seats, cancellation, and dated Messier sessions. The browser test simulates events, an expired login, and an explicitly empty schedule. It never writes demonstration events into the app cache.
