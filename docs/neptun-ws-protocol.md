# NEPTUN WebSocket observations (A01)

Research date: 2026-10-17. This records evidence for the v2 migration.
The A01–A05 sections describe work before integration; A06 below connects the
transport, decoder, store and projection to the WebSocket-only production service.

## Initial official-alert synchronization

**Observed: a new connection sends a threat `snapshot`, then a separate complete
`alerts` baseline, even when the alert collection has not changed.**

Two consecutive, independently opened 65-second connections were recorded with
websocat 1.14.1. Both received `alerts` approximately 0.4 seconds after process
launch, with 69 raion records and four oblast/city records. Their `data` objects
were identical, including version `1792266284` and
`updatedAt = 2026-10-17T19:44:44.605796775Z`. A one-off research read of the public
`/api/v1/alerts` endpoint returned exactly the same object and version, confirming
that these WS messages contained the full snapshot rather than a delta. This
comparison is a research check, not a proposed runtime REST dependency.

| Capture | First snapshot `ts` (UTC) | Initial alerts `ts` (UTC) | Events |
| --- | --- | --- | --- |
| `session-1.jsonl` | 19:50:51.398 | 19:50:51.007 | 1 snapshot, 1 alerts, 6 remove, 5 upsert, 4 heartbeat |
| `session-2.jsonl` | 19:51:57.057 | 19:51:57.001 | 1 snapshot, 1 alerts, 8 remove, 22 upsert, 5 heartbeat |

The first process was terminated deliberately; the second then opened a new
connection. This verifies resynchronization on reopening a connection. It does
**not** verify internal `autoreconnect:` behavior, recovery after a network
interruption, or lifecycle behavior inside Noctalia; those remain A02 checks.

The initial-baseline blocker was not reproduced in these sessions. There is no
documented guarantee that every session always delivers it, and no naturally
empty official-alert baseline was observed. Future code must remain unknown or
stale until it actually receives and validates a new `alerts` frame.

## Envelope and payloads

The [developer documentation](https://neptun.in.ua/developers) describes five
event kinds. The following shapes were observed directly in both sessions:

| Kind | Observed shape and semantics |
| --- | --- |
| `snapshot` | `{ type, ts, data: { threats: [...] } }`; contains no official alerts. |
| `upsert` | `{ type, ts, data: <Threat> }`; one threat object with a string `id`. |
| `remove` | `{ type, ts, data: { id: string } }`; refers only to a threat. |
| `alerts` | `{ type, ts, data: { version, updatedAt, raions: [...], oblasts: [...] } }`; complete alert set. |
| `heartbeat` | `{ type, ts }`; **no `data` property** in the observed messages. |

`ts` is an ISO timestamp with UTC `Z`. Arrival order is not necessarily timestamp
order: both initial `alerts.ts` values predate the preceding `snapshot.ts`.
Neither timestamp sorting nor rejection of all older envelopes is a safe session
or event-order rule. `alerts.data.updatedAt` can be much older than the current
connection; its value is not a transport-liveness timestamp. The numeric
`version` did not change between initial baselines; its ordering contract is not
documented here.

Heartbeat server timestamp gaps were 15.000, 15.001 and 15.000 seconds in the first
session, and 15.125, 14.875, 15.001 and 15.000 seconds in the second. Threat events
arrived between heartbeats. These short observations are evidence for A07, not a
guaranteed maximum idle time or a chosen expiry threshold. Local arrival timings
after the baseline were affected by Python pipe buffering and are not used to
measure heartbeat cadence.

### Official alerts and location keys

Observed alert records contain `key`, `name`, `oblast`, `since` and `level`.
Raion alerts included `reasons`; some oblast records omitted it. Observed levels
were `red` and `yellow`. Public documentation omits `level` in its examples, so
presence in these captures is not proof it is required. Missing metadata and
unknown levels must not be synthesized into a known severity or an all-clear.

`since` and `updatedAt` use UTC, sometimes with six or nine fractional digits.
Missing, invalid and future timestamps were not observed; their synthetic test
cases must be distinguished from captured protocol evidence. Keep unknown times
unknown and do not substitute envelope time for an alert start time.

The public [oblast catalog](https://neptun.in.ua/oblasts.geojson) had 27 features
with `properties.key` and `properties.region`. The
[raion catalog](https://neptun.in.ua/raions.geojson) had 136 features with
`properties.key` and `properties.rayon`. Every captured official-alert key was
present in its corresponding catalog.

Actual keys are Ukrainian strings, for example `бориспільський`, `київська`,
`м. київ`, `автономна республіка крим` and `севастополь`. They differ from Latin
examples such as `odeska:odeskyi` in the developer page. Raion records supply
parent names such as `Київська область` in `oblast`, which the existing API
boundary already maps explicitly. Kyiv city occurred separately as `м. київ` in
the `oblasts` array. Sevastopol had its own key even though its `oblast` value
was `Автономна Республіка Крим`; never infer its identity from that parent name.
The `oblasts` array contains active whole-territory alerts, not all 27 locations.

### Threat metadata

Captured threats have string IDs, type, title, region, district, locality,
coordinates, update time, confidence, source count, status and explanatory text.
Optional fields observed across snapshot/upsert records include `heading`
(including `null`), `confirmedAt`, `count`, `uncertaintyKm`, `positionQuality`,
`regionKey`, `trail`, `areaOnly`, `destination`, `presumptiveCourse`, `sea`,
`lifecycle` and `displayConfidence`. Presence varies between objects. These are
track attributes, not official-alert severity or official location membership.

`advisory` and `velocity` are documented but were absent from these captures.
No semantic contract is inferred for undocumented extra fields. The
[official SDK](https://neptun.in.ua/sdk/neptun.esm.js) fetched for this check had
SHA-256 `a2b8b06ed673ae85036754f17df883688f3d368023380b543d9161271208fb50`.
It fetches alerts over REST on socket open as well as handling WS `alerts`.
Its startup behavior therefore cannot alone prove WS-only initialization.

## Fixtures and checks

`tests/fixtures/neptun-ws/session-1.jsonl` and `session-2.jsonl` preserve the full
event sequence and collection sizes from the two captures. Each line is one raw
JSON envelope, suitable for later decoder/store playback. Threat IDs are replaced
consistently across both sessions by `fixture-track-NNN`. Nonempty titles,
explanatory text and locality strings are replaced by fixture labels; coordinates,
including trail coordinates, are replaced by `50.0, 30.0`. These are test positions,
not real observations. Field presence, timestamps and other values are retained.
Official-alert records retain their public geographic keys and metadata.

`synthetic-cases.json` contains named raw strings and intended A03 outcomes
(`accept`, `reject`, `ignore`). They cover empty alerts, missing metadata, unknown
severity, extra fields, malformed JSON/envelopes, missing collections and invalid
IDs. They are authored test inputs, **not captured server messages**. In
particular, the empty alert set is a hypothetical complete baseline, not evidence
that an empty baseline was observed. A03 now runs these cases through the
production decoder; `test_ws_fixtures.py` separately checks corpus integrity.

Capture command (use a bounded duration and keep stderr separate):

```sh
timeout 65s websocat -t -u -n -B 1048576 \
  wss://neptun.in.ua/api/v1/stream - </dev/null >session.jsonl 2>session.stderr
```

Without `-n` (`--no-close`), closed stdin caused an early WebSocket close, even
with `-u`. With it, the process continued receiving for each full recording
window. All captured stdout lines decoded independently as complete JSON.
No captured message approached the 1 MiB buffer limit; oversized-frame behavior
and message limits still need an explicit A02 policy.

Verification commands:

```sh
python3 tests/run.py /path/to/luau
python3 -m unittest discover -s tests -p 'test_*.py' -v
stylua --check air-alert tests
```

The original 10 regression groups and all four fixture integrity tests passed.
The regression suite used the official Luau 0.743 portable CLI, extracted into
`/tmp` after checking the release archive SHA-256. The plan's
translation-path defect was already absent: both the runner and repository use
`translations/uk.json`. No harness repair was needed. The baseline StyLua check
reported existing formatting differences in `alerts/api.luau`,
`alerts/status.luau`, `notification.luau` and `tests/checks.luau`; these unrelated
files were left unchanged.

The [Noctalia runtime API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/)
documents line callbacks and a launch boolean for `runStream`, and termination
on reload/removal/stop. It documents no per-stream stop handle or exit callback.
Actual API 24 behavior remains to be verified in Noctalia during A02.
The [websocat reference](https://github.com/vi/websocat/blob/master/doc.md)
documents the autoreconnect overlay and retry delay; neither was exercised here.

## A02 transport investigation — original design blocked

The following additional checks used the installed websocat 1.14.1. The original
transport prototype was removed because the executable could not satisfy the
plan's bounded-retry requirement for both failure paths. The subsequently
approved replacement is described below; the service remains unchanged.

`--autoreconnect-delay-millis 5000` delays failed connection construction, but
does **not** delay a retry after a previously established WebSocket closes or
fails during reading. The
[versioned implementation](https://github.com/vi/websocat/blob/v1.14.1/src/reconnect_peer.rs)
sets a timer in the construction-error branch of `State::poll()`. Its
`State::reconnect()` only discards the current peer and sets no timer.

This was reproduced in two independent ways:

- A temporary SOCKS5 relay forwarded encrypted traffic to the real NEPTUN WSS
  endpoint without terminating TLS. After the first `alerts` frame, it dropped
  that test connection. The same websocat PID opened a new connection about
  0.057 seconds later and received another `snapshot`, `alerts` and heartbeat.
  Every stdout line was complete JSON and closed stdin did not end the process.
  The five-second lower-bound assertion failed; no other user's connection was
  interrupted.
- An isolated loopback server accepted and then closed WebSockets. Consecutive
  connection attempts were approximately 0.057 and 0.056 seconds apart. When the
  same server instead rejected the handshake with HTTP 503, the next attempt
  arrived 5.007 seconds later. Thus the configured delay works only on the latter
  path. The loopback experiment uses plain WS only for local testing and never
  disables certificate verification for external WSS.

Repeat the opt-in diagnostic with:

```sh
python3 tests/probe_websocat_retry.py
# Or: python3 tests/probe_websocat_retry.py /path/to/websocat
```

This opens a temporary loopback listener and one websocat process at a time,
then terminates them. It is separate from the normal regression suite. Exit
status 1 with `BLOCKED` is expected on the checked 1.14.1 executable; this is a
failed external-capability check, not an expected passing regression test.

This matters beyond a transient outage: a server that repeatedly accepts and
closes a session can cause rapid retries. So can a baseline exceeding a configured
message limit, because the handshake succeeds before reading fails. Keeping the
five-second option without addressing this path would not meet the plan's
no-hot-loop requirement. No speculative shell supervisor or repeated
`runStream()` calls were added. Continuing requires either a verified executable
that bounds both paths, or approval to revise the single-process reconnect design.

The [Noctalia host source checked at commit
3982122906f2409aeaff17399552153c4c323f20](https://github.com/noctalia-dev/noctalia/blob/3982122906f2409aeaff17399552153c4c323f20/src/scripting/luau_host.cpp)
also exposes a 64 KiB unfinished-line buffer in `runStream()`. A future command
must account for this limit rather than reuse A01's 1 MiB capture buffer. The
candidate command used `-S -B 65536 --max-ws-frame-length 61440
--max-ws-message-length 61440`, keeping messages below the host limit and avoiding
split frames. Larger baselines must remain unknown/stale, not become all-clear.
The source registers `commandExists` and `runStream` without a newer API gate;
the [API history](https://docs.noctalia.dev/noctalia/plugins/development/plugin-api/)
does not require a bump above API 24 for these calls.

The host gives Lua neither stderr callbacks nor process-exit callbacks for
`runStream()`. A true launch result therefore does not prove websocat remains
alive. Source inspection is not an actual Noctalia lifecycle test: reload,
disable, child termination and network recovery in a running Noctalia session
remain unverified. No live plugin configuration was changed during this check.

## A02 approved shell supervisor

The user approved a revised lifecycle on 2026-10-17: one `runStream()` owns a
shell supervisor, with at most one foreground websocat child at a time. Each
completed child is followed by `sleep 5` before another is launched, including
after a clean server close. This replaces the internal `autoreconnect:` overlay.
There is no Lua timer that launches additional streams and no detached daemon.

`alerts/transport.luau` exposes `start(onLine)`, returning `started`,
`missing_dependency` or `launch_failed`. Repeated calls return the cached result
and retain the original callback. Missing dependency and rejected submission are
cached too; install the dependency and reload the entry to try again. Requiring
the module alone does not launch anything. Only the service should require it:
Noctalia's module cache is entry-local, not shared among widgets.

`started` means the host accepted submission, not that the socket is live. Each
stdout line is forwarded unchanged with `noctalia.nowMs()` at callback delivery.
The timestamp measures raw activity, including malformed input; it must not be
used as a validated official-alert timestamp. The module performs no JSON parsing,
HTTP requests, alert selection or shared-state publication. Service integration
remains A06; the currently enabled plugin does not start this new transport.

The child has closed stdin and uses `-n` to keep receiving. TLS verification stays
enabled. Strict message handling and the 60 KiB frame/message limits keep stdout
lines within the checked host's buffer limit. An oversized baseline can therefore
prevent initial synchronization; later code must keep unknown/stale state in this
case. Diagnostics remain on stderr, which the host does not expose to Lua.

Child exit statuses 126/127 stop the supervisor (unexecutable/missing command),
rather than retry an unavailable executable forever. Failure of `sleep` stops it
too. There is no Lua exit callback or automatic supervisor respawn: silence must
be handled by A07, and a terminated supervisor requires entry reload.

The [checked process implementation](https://github.com/noctalia-dev/noctalia/blob/3982122906f2409aeaff17399552153c4c323f20/src/core/process/process.cpp)
creates a separate process group and cancels the entire group with SIGTERM then
SIGKILL. The shell traps TERM/INT/HUP to exit without restarting the child. Both
websocat and sleep remain in that group; neither is backgrounded or detached.
The same process-group cancellation is present in the
[v5.0.0-beta.9 source](https://github.com/noctalia-dev/noctalia/blob/v5.0.0-beta.9/src/core/process/process.cpp),
the release that introduced API 24, so this does not require raising `plugin_api`.

Verification of the approved replacement:

- Original 10 Luau regression groups and three new transport groups pass,
  covering single submission, callback ownership, raw activity, dependency and
  launch failures, cached results and reentrant start.
- Strict analysis of the new module passes with minimal declarations for the
  verified host API signatures; this is not a type-check of the entire plugin.
  StyLua passes for the changed Luau files and Noctalia plugin lint reports no
  errors or warnings. The pre-existing formatting differences noted under A01
  are not changed by A02.
- Four process tests run the exact production shell string with a controlled
  executable. They cover the five-second pause, separate stdout/stderr, terminal
  exit codes, and group cancellation during both a connection and retry sleep.
- Live WSS through the temporary encrypted-byte relay recovered after a forced
  drop with a 5.065-second connection-attempt gap, delivering a new `snapshot`,
  `alerts` and heartbeat. The supervisor PID stayed the same; the websocat child
  was replaced. All stdout lines decoded as independent JSON messages.

The standalone `probe_websocat_retry.py` still reports the original websocat
limitation and is not a pass criterion for the approved supervisor. Run the new
process tests with `python3 -B -m unittest discover -s tests -p 'test_*.py' -v`.
The mock and subprocess tests do not prove Noctalia's runtime behavior. Manual
checks still needed in Noctalia: reload/disable terminates the old process group,
reload starts one replacement, and network recovery resynchronizes without
overlapping children. UI behavior and location changes are unchanged at A02.

## A03 event decoder and A04 realtime store

`alerts/events.luau` exposes `decode(raw) -> (Event?, ErrorCode?)` for all five
known envelope types. An unknown type returns `nil, nil`; malformed input returns
one of `oversized`, `json`, `envelope` or `payload`. These are fixed codes for
future service logging, without including untrusted payloads or decoder error
text. The decoder itself is a pure transform and does not log, request data or
publish shared state. Known events require a valid envelope `ts`; optional alert
and threat dates that fail validation remain unknown.

The normalized threat record retains only `id`, `type`, `updatedAt`, `advisory`
and `areaOnly`. Other fields, including coordinates, trajectories and labels,
are not consumed or stored in this release. Unknown threat types are retained
as strings, and absent boolean metadata stays absent rather than being invented.
Optional flags must be booleans when present. Official alerts retain keys,
optional severity, start time and reasons, plus optional collection version and
update time. Missing severity remains unknown; unfamiliar nonempty levels remain
unchanged. Reasons and alert collections are sorted to compare equivalent sets
independently of arrival order. Duplicate IDs/keys within a collection reject
the complete frame rather than silently dropping records.

Raion source-parent names are mapped to `oblastKey` at the decoder boundary
using explicit names and keys from the existing catalog. No translated labels
or name heuristics are used. Unknown parents reject the entire frame, preserving
the previous validated set. Projection for a selected location is described in A05 below.

The checked Noctalia `jsonToLua` conversion turns both JSON objects and arrays
into tables and removes `null` values. The decoder therefore adds temporary
boolean guards at both ends of each JSON array before invoking the native
decoder. A string-aware scan leaves quoted brackets and escaped quotes untouched.
The guards let validation distinguish `{}` from `[]` and detect null holes,
including a trailing null. They never enter the normalized event. Messages above
60 KiB and nesting above 64 levels are rejected before host conversion. Object
keys containing an encoded NUL are rejected too, since the checked host passes
keys through a NUL-terminated C API. This prevents malformed property names from
turning into valid collection keys.

All normalized events and nested collections are frozen. Their public types use
ordinary table fields/indexers for compatibility with the editor's legacy Luau
analyzer, which rejects `read` annotations even though the runtime parser accepts
them. Narrow assertions on already validated, frozen records bridge the new
solver's read-only inference; they do not replace payload validation. The store
never mutates decoder output.

`alerts/realtime-store.luau` exposes `new()` and `apply(store, event, receivedAtMs)`.
It accepts only validated events from the decoder and owns a separate mutable
threat map. Official-alert state is discriminated as:

- `unknown`: no official baseline has been established.
- `current`: a validated full `alerts` frame established this session's baseline.
- `stale`: a new session was observed; last-known data and sync time are retained.

Each `snapshot` replaces only the threat map, increments the session counter and
invalidates official-alert freshness. Even an identical snapshot is a session
boundary: a new connection can carry cached data. An `alerts` frame replaces the
official set atomically and establishes freshness, including a validated empty
set. Upsert/remove affect only threats; an unknown remove is harmless. Heartbeats
advance message activity without establishing an official baseline.

`apply` returns whether content, session or baseline changed. Identical normalized
upserts and equivalent current alerts return false; their relevant receipt-time
metadata still advances. In particular, a repeated `alerts` frame refreshes its
sync receipt time without replacing the stored data object. Heartbeat receipt,
last envelope `ts` and last official sync are tracked separately. Arrival order
is respected even when envelope timestamps decrease; no undocumented timestamp
or version ordering is assumed. Expiry policy and disconnection detection remain
A07, and notification decisions remain A08.

Verification uses both A01 sessions and 51 authored cases across the two fixture
manifests. It covers all event types, empty sets, invalid arrays/nulls, escaped
strings and keys, duplicates, unknown/missing metadata, rejected frames, immutable
results, canonical equality and reconnect baseline reset. Two independent stores
produce identical results from full fixture playback. Message-size and nesting
limits are also checked before the mocked host decoder is called.

The runner uses Python JSON decoding and Luau literals to reproduce the host's
table/null/key conversion, with an independent reference array transform. These
tests exercise production validation/store code, but are not a live Noctalia JSON
integration test. Noctalia plugin lint passes. Targeted strict analysis reports
no diagnostics in the new modules; Luau 0.743 still reports the pre-existing
`alerts/time.luau:12` diagnostic, also reproduced when checking that unchanged
file alone. No suppressions or unrelated time changes were added. The installed
luau-lsp 1.70.1, using `noctalia.d.luau` and its legacy solver, checks both new
modules and their dependencies without diagnostics. The new solver has only the
previously noted time diagnostic. Repeat the editor-compatible check with:

```sh
luau-lsp analyze --flag:LuauSolverV2=false --definitions=noctalia.d.luau \
  air-alert/alerts/events.luau air-alert/alerts/realtime-store.luau
```


## A05 location projection

`alerts/status.luau` now exposes `project(alertState, locationKey)`. It consumes
only the official-alert branch of the realtime store, so tracked threats cannot
activate or clear an official warning. Its result distinguishes `unsupported`,
`unknown`, `current` and `stale`. Only a `current` projection with no matching
alert establishes a current absence; a stale projection retains its last-known
alert (or absence), update time and synchronization receipt time.

Unknown selection keys and unrecognized territory keys in the official set
cannot establish a clear status. Kyiv city and Kyiv Oblast use separate explicit
catalog keys. Matching oblast and raion alerts are combined without mutating
frozen decoder output. Red takes precedence over yellow; missing classification
remains absent, and unfamiliar levels dominate known levels. Multiple unfamiliar
levels use lexical ordering for a deterministic representative, without assigning
severity to that ordering. Reasons are a sorted union. Start time is the earliest
matching start only when all matching starts are known.

The existing `forLocation` aggregation remains available for the HTTP service
until A06 connects the pipeline. Shared alert state and its presentation now
accept an absent level and show the existing translated unknown-level label.
No settings format, catalog entries, plugin API or dependency changed.

`projection-cases.json` and `tests/ws-status.luau` cover city/oblast separation,
multiple raions, severity changes, absent/unfamiliar levels, missing start times,
empty official sets for all 27 supported selections, unknown territory keys,
threat-only activity and reconnect invalidation of active and empty baselines.
The regression suite, editor-compatible legacy analyzer, targeted formatting and
plugin lint pass. These are fixture/mock checks: live status in Noctalia can be
tested after A06 switches the service to WebSocket; watchdog/expiry behavior is A07.


## A06 WebSocket-only service

`service.luau` now composes transport → decoder → realtime store → location
projection → shared state and notifications. `alerts/api.luau` and HTTP polling,
request IDs and HTTP callbacks are removed. The stream starts only once a
supported selection exists. Existing `config.json` and public settings remain
unchanged, and multiple widget instances consume the same shared state.
Selection changes project the current official set immediately and reset the
notification baseline without reopening the stream. The aggregator is now
private to `status.project`; its HTTP compatibility export is removed.

The service publishes only on official content/session changes, selection changes
or a liveness transition. Heartbeats and tracked-threat updates do not publish
alerts or trigger notifications. Initial official data establish a baseline;
verified activity transitions retain existing notifications and the 15-second
clear highlight. Malformed events leave validated data untouched and log only
the decoder's fixed error code, without raw messages.

A minimal local watchdog runs every second, without network requests or process
launches. Forty-five seconds without a validated message (three observed
heartbeat intervals) invalidates the official baseline, even if a heartbeat
arrives before the next timer tick. A reconnect snapshot also invalidates the
baseline. Last-known data remain in the store, but the existing UI shows data
unavailable until a fresh `alerts` event arrives. This deliberately brings the
minimum freshness protection into A06; A07 still owns richer connection states,
visible last-known stale details and further failure handling. This 45-second
threshold is a conservative local policy, not a NEPTUN timing guarantee.

The stream API still has no process-exit callback. Missing dependency and
rejected submission are cached with translated errors; fix the cause and reload.
A permanently stopped supervisor cannot be automatically distinguished from a
silent stream; the watchdog shows unavailable and never launches a second
supervisor. A fresh `alerts` frame or plugin reload is required after expiry;
heartbeat activity alone cannot make expired official data current.

Source inspection of Noctalia's
[shared state store](https://github.com/noctalia-dev/noctalia/blob/3982122906f2409aeaff17399552153c4c323f20/src/scripting/plugin_state_store.cpp)
and [runtime mailbox](https://github.com/noctalia-dev/noctalia/blob/3982122906f2409aeaff17399552153c4c323f20/src/scripting/script_runtime.cpp)
confirmed that watcher notifications are enqueued per runtime. Widgets and the
status panel now read the latest published state on selection changes, so a
new projection delivered before the local selection callback is not discarded.
A regression test exercises that order in addition to normal delivery.

Checks: 20 Luau test groups pass, including the adapted UI/persistence/notification
regressions and stream lifecycle integration. Eight Python fixture/process tests
pass. The legacy editor analyzer passes for all production Luau modules;
formatting passes for changed Luau files and plugin lint passes. Tests reject
any HTTP invocation in the mock. `websocat 1.14.1` is installed in this environment.
No live Noctalia settings were modified and no live plugin reload was performed.

### Manual Noctalia checks after A06

Live functionality is ready for manual testing using this local checkout:

1. Verify `websocat --version` works in Noctalia's environment, then reload Air
   Alert. The saved region should remain selected. Loading must change only after
   an official-alert baseline arrives; initial status must not notify.
2. Open the tooltip and details panel. Check region, severity, available reasons
   and timestamps against NEPTUN. Check icon/status/region modes and both color
   modes. Missing level/time must stay unknown.
3. Switch between Kyiv city and Kyiv Oblast, including A → B → A. Both widget
   and open panel must show the selected location immediately from synchronized
   data. Region changes must not notify.
4. Add a second widget. Both must agree, and panels must open beside the clicked
   instance. `ps -C websocat -o pid,ppid,args` should show only one plugin-owned
   websocat child while connected, regardless of widgets or region changes.
5. Temporarily disconnect the network. By 45 seconds of silence the widget must
   show stale last-known data (A07), or unavailable if no baseline was ever received,
   with no all-clear notification. Restore the network and
   wait for a new official baseline. The same supervisor should reconnect;
   unchanged official activity must not generate a notification.
6. Reload and then disable the plugin. Check that the old supervisor/child stop,
   including during retry sleep; re-enable and confirm only one child remains.
   This is the outstanding real-host lifecycle check from A02.

These are manual checks to perform, not claims of a completed live-host test.


## A07 freshness and failure handling

The A06 liveness guard now publishes an explicit `stale` shared state containing
`lastKnown` (a discriminated alert/clear record), source `updatedAt` when known,
and the unchanged local official synchronization receipt `syncedAtMs`. The store
continues tracking valid-message receipt independently. Loading represents
connecting/awaiting the initial official set; live data use the existing alert
and clear variants. Missing dependency, rejected launch and unavailable initial
data remain distinct from a known stale baseline.

The widget shows the translated stale label and neutral colors, including in
colored mode. Tooltip and panel identify the last confirmed status; an old alert
retains severity, reasons and start time. The panel retains source update time
but hides the increasing duration until a fresh baseline confirms the alert.
Last-known clear is visibly stale too and cannot activate green highlighting.
A stale region change projects that region from the retained official collection,
without borrowing the previous region's alert or reopening the stream.

The service checks both transport silence and pending session synchronization.
Each deadline is 45 seconds: silence is measured from the last valid event;
synchronization is measured from startup or the newest validated snapshot and
cannot be extended by heartbeats or tracks. A fresh snapshot begins another
synchronization attempt. A fresh valid `alerts` clears the pending deadline and
restores current official data. An identical recovery baseline does not notify;
missing/invalid data and stale transitions never emit all-clear notifications.
An established synchronized set can remain current through regular heartbeats
without inventing a newer official synchronization timestamp.

No process lifecycle API or retry mechanism changed. Existing shell process tests
cover the five-second retry delay, process-group termination and permanent child
exit codes 126/127. A07 additionally simulates a permanently silent stream with
repeated watchdog ticks and verifies that no second stream is submitted. Because
`runStream` has no exit callback, Lua cannot diagnose a permanently exited shell;
reload is still required to restart it. This limitation is explicit, not an
automatic recovery guarantee.

Verification: 23 Luau test groups pass, including a regression first reproduced
against the A06 unavailable-only implementation, active/clear stale rendering,
initial synchronization deadline despite heartbeats, normal heartbeat liveness,
invalid input, region changes and recovery. The editor-compatible legacy analyzer
passes for all production modules; changed-file formatting, translation-key parity
and plugin lint pass. No live Noctalia session or settings were changed.

Manual check: reload this checkout, open the panel, then disconnect the network
for at least 45 seconds. Expect a stale marker in the widget and tooltip, neutral
colors in both color modes, retained last-known details, no running stale duration
and no false all-clear notification. Reconnect and wait for fresh `alerts`; the
same supervisor should recover current status. Repeat with two widgets and with
a previously clear region. Check startup without a baseline separately: it must
show unavailable after its deadline, never clear. Real-host lifecycle checks in
the A06 list remain pending.


## Recovery fix: half-open network connections

A manual network-disconnect test reported that stale status persisted after the
network returned. The previous supervisor waited for websocat to exit, but the
command had no protocol ping or pong timeout: a half-open TCP/WebSocket could
survive the outage. A resumed stream could send only heartbeats/tracks while
Luau correctly continued waiting for a new official baseline. Earlier tests
closed the test connection explicitly and did not cover this failure mode.

The transport now adds `--ping-interval 10 --ping-timeout 30`, supported by the
installed websocat 1.14.1 and its
[reference](https://github.com/vi/websocat/blob/v1.14.1/doc.md).
Pong timeout closes an established nonresponsive connection; the existing shell
waits five seconds and launches its next child. The fresh connection supplies a
snapshot and official baseline. Lua still starts exactly one supervisor and
never marks a heartbeat-only recovery as current official data.

`tests/test_transport_keepalive.py` uses the real installed websocat against a
loopback WebSocket peer. It keeps a healthy connection longer than its timeout,
then stops answering pings without closing the socket. It verifies that the same
supervisor reconnects with the five-second retry delay and receives another
snapshot plus alerts. Test ping deadlines are shortened to one/three seconds;
the production ten/thirty-second settings are preserved. The test failed before
the flags were added and passes afterward. It is skipped when websocat is absent.
This test needs loopback socket permission; it does not modify system networking.

Reload the plugin once to replace the already running command, then repeat the
manual network interruption test. Connection establishment failures and a dead
supervisor remain separate from an established connection with missing pongs;
there is still no host process-exit callback and no uncontrolled Lua respawn.

A separate 35-second connection to real NEPTUN received an initial snapshot,
official alerts and heartbeats, with three measured pong round trips around
0.08–0.09 seconds. This verifies NEPTUN answers protocol pings; actual Noctalia
network toggling remains a manual check.

The binary prints a generic ping-mode warning suggesting `-E`/`-U`. Testing `-E`
with this command's closed stdin caused an immediate stream close, so it is not
used. The real-client lost-pong regression passes with the existing `-u -n`
direction and without `-E`; the warning alone is not evidence of failed keepalive.
