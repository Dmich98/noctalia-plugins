# Air Alert v2 — WebSocket-only migration plan

**Project:** [Dmich98/noctalia-plugins](https://github.com/Dmich98/noctalia-plugins), plugin `air-alert`\
**Starting version (at planning time):** `0.3.1`, `plugin_api = 24`\
**Status:** A01–A07 implemented; manual Noctalia verification of A02/A06/A07 is pending. A08 and later tasks are not complete.\
**Primary language:** Luau (`--!strict`)\
**Transport dependency:** `websocat`\
**Server:** `wss://neptun.in.ua/api/v1/stream`

**Approved A02 adjustment (2026-10-17):** use one `runStream()` shell supervisor
with at most one foreground `websocat` child at a time. After a child exits, wait
five seconds before launching its replacement. Do not use `autoreconnect:`:
websocat 1.14.1 does not delay retries after an established session closes.
This adjustment supersedes references below to one permanent websocat PID and
its internal reconnect mechanism. Lua must still submit only one stream per
service lifetime; location changes and watchdog ticks must never resubmit it.
Noctalia owns cancellation of the shell's process group, including its child.
See `docs/neptun-ws-protocol.md` for the investigation and verification limits.

## 1. Goal and scope

Migrate the existing Noctalia v5 Air Alert plugin from HTTP polling to **WebSocket exclusively**, without rewriting its UI or losing existing configuration.

### Non-negotiable constraints

- **No REST at runtime. No REST fallback. No `noctalia.http()` for NEPTUN.** Remove the periodic HTTP request and unused HTTP client code.
- Use the installed **`websocat`** executable and `noctalia.runStream()`; **do not build a Rust daemon, a systemd service, or a separate local server**.
- Exactly **one stream per plugin service**, regardless of the number of widgets.
- Keep existing region selection, stored configuration, tooltip, details panel, translations and notification behavior unless a task explicitly changes them.
- Treat **official alerts** (`alerts` frames) and **tracked threats** (`snapshot`/`upsert`/`remove`) as separate datasets.
- Never interpret a connection failure, unknown/missing data, invalid message or incomplete initial sync as an **all-clear**.
- Do not imply NEPTUN is an official public-warning system. Keep visible source attribution and an appropriate disclaimer; follow official local alerts.
- Do not add support for new location levels, maps, movement prediction, persistence of alert history or a redesigned UI in this release.
- Avoid premature abstractions. Prefer small, testable modules and dependency boundaries consistent with the repository.

## 2. Verified external API facts and open questions

### NEPTUN documented WebSocket envelope

Every frame is documented as `{ "type": "...", "ts": "...", "data": ... }`.

| Frame type | Documented payload | Meaning |
| --- | --- | --- |
| `snapshot` | `{ threats: [...] }` | Initial **threats** snapshot on connection; does **not** establish official alerts. |
| `upsert` | Threat object | Insert/update a tracked threat by `id`. |
| `remove` | `{ id: string }` | Remove one tracked threat. |
| `alerts` | `{ raions: [...], oblasts: [...] }` | Current set of official alerts. |
| `heartbeat` | Keep-alive envelope | Evidence that the stream is sending data, not proof that `alerts` were synced. |

Documentation: <https://neptun.in.ua/developers>.

**Must verify before changing production logic:**

1. Does a freshly established connection **always** send a complete `alerts` frame promptly, including if no alerts changed? If not, WS-only cannot establish a trustworthy initial official-alert status from `snapshot` alone. **Stop and report the blocker; never assume an empty alert list.**
2. Record real payloads and optional fields for `snapshot`, `upsert`, `remove`, `alerts`, `heartbeat`. The existing REST parser expects `level`; the public documented alert examples omit this field. Do not invent missing severity or timestamps.
3. How is a new session observed when `websocat` reconnects internally (e.g. a fresh `snapshot`)? Verify that reconnection reliably initiates a new baseline; do not count on an undocumented process-exit callback.
4. Measure the heartbeat interval and typical idle times before choosing connection-health thresholds.
5. Verify that a single WebSocket frame produces one complete newline-delimited JSON message on stdout and survives connection loss and recovery.
6. Verify `websocat` `autoreconnect:` works with WSS and a non-interactive stdin in the Noctalia process environment; choose a reasonable retry delay to avoid a busy loop.

`websocat` documentation: <https://github.com/vi/websocat/blob/master/doc.md>.\
Noctalia runtime API: <https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/>.

> **Runtime limitation:** `noctalia.runStream(cmd, onLine)` returns a launch boolean and forwards stdout lines. Its documented API does not provide a per-stream stop handle or explicit process-exit callback. The runtime terminates active streams when the entry/plugin is stopped or reloaded. Design stream lifecycle accordingly; **do not repeatedly spawn processes as a naive reconnect mechanism**.

## 3. Target architecture

```text
NEPTUN WSS
   |
websocat (single process, reconnects internally)
   |
noctalia.runStream()                   <-- transport/lifecycle
   |
events.luau                          <-- decode + validation
   |
realtime-store.luau                  <-- alerts and threats (separate)
   |
status.luau                          <-- projection for selected location
   |
service.luau                         <-- orchestrates state and notifications
   |
noctalia.state
   +--> widget.luau / widget-view.luau
   +--> status-panel.luau
   +--> notification.luau
```

### Responsibility boundaries

- **Transport:** starts the process once, receives raw lines, reports launch failure and measured stream activity; does not interpret threat severity.
- **Parser:** converts raw JSON lines into validated typed events; unknown event types are ignored safely.
- **Realtime store:** independently maintains authoritative-in-memory *official alert set* and tracked threats by ID. Supports reset on session boundary.
- **Status resolver:** combines the verified official-alert set for a selected location; tracked threats remain informational and **must not silently become official alerts**.
- **Service:** owns startup, lifecycle, selected region, freshness, deduplication, notifications and shared state.
- **Presentation:** reflects `loading`, `live`, `stale` and missing-dependency states without implying safety when data are unknown.

### State / freshness invariants

1. Before the **first validated `alerts` frame** of a session: official-alert state is **unknown**, even if a `snapshot` or `heartbeat` has arrived.
2. On a known fresh `alerts` frame: replace the official alert collection **atomically**. An empty, validated `alerts` collection may be treated as *no official alert* only after confirming the protocol sends a complete set.
3. The threat `snapshot` replaces the previous threat set; subsequent `upsert`/`remove` mutate only threats.
4. A fresh `snapshot` signaling a new connection invalidates previous-session official-alert freshness pending a new `alerts` baseline. Preserve the last displayed state as **stale**, not live.
5. Silence beyond a measured timeout marks the feed as **stale**; heartbeat extends transport liveness but does not fabricate official-alert data.
6. While stale, preserve last-known alert details (when available) with a visible stale marker; do not issue a notification announcing all-clear.
7. After recovery, reconcile against fresh official-alert data; notify only on a verified change, never solely on reconnect. Establish the initial baseline without notifications.
8. Multiple widgets render from one shared state. Changing region never starts a second `websocat`.
9. Invalid JSON/events do not clear previously validated data and do not count as a successful alert sync.
10. Repeated equivalent events do not trigger redundant state updates or notifications.

**Recommended state model:** keep the existing location alert state separate from connection/freshness metadata (e.g. `connecting | live | stale | missing_dependency | error`). Preserve a `lastKnownAlert` snapshot and timestamps. Exact names are implementation choices, but these invariants must hold.

## 4. Task breakdown

Each task should be a **small independently reviewable change with tests**. Do not implement later tasks as a side effect. IDs can be used as Codex prompts.

### A01 — Protocol research, fixtures, test baseline (P0)

**Goal:** eliminate assumptions about event shapes and make the current test suite runnable.

**Work:**
- Inspect current `air-alert/` and test infrastructure.
- Capture sanitized samples for all five frame types and a reconnection sequence; commit deterministic test fixtures (no personal data).
- Record observed `alerts` delivery on a fresh connection and after reconnect. This is a **release blocker** if an initial complete `alerts` baseline cannot be obtained over WS.
- Document optional fields including `level`, `since`, `reasons`, missing/unknown values, and region/raion key mappings.
- Fix baseline test harness defects without altering runtime behavior. At planning time `tests/run.py` refers to `translations/uk.json`, while the repository has `translations/uk-UA.json`.

**Likely files:** `tests/`, `README.md` or new `docs/neptun-ws-protocol.md`.

**Acceptance:** original regression tests run; committed valid/invalid fixture set exists; WS initial official-alert sync is confirmed or explicitly reported as blocking.

### A02 — WebSocket transport and process lifecycle (P0)

**Goal:** one durable stdout stream in Noctalia, without HTTP.

**Work:**
- Add `alerts/transport.luau`, using `noctalia.commandExists("websocat")` and `noctalia.runStream()`.
- Test `autoreconnect:` and an appropriately bounded delay, with stderr diagnostics that do not mix into stdout JSON. Do not use insecure TLS switches.
- Avoid stdin EOF prematurely terminating a background stream; verify the exact command on the installed `websocat` version.
- Start once per service lifetime; mark dependency/launch failures explicitly; never start additional streams on a timer or on location changes.
- Extend test mock with `runStream` and `commandExists`.

**Likely files:** `alerts/transport.luau`, `tests/runtime.luau`, new transport tests.

**Acceptance:** valid frames reach callback; no duplicated process on repeated update calls; no stream when executable is absent; reconnection works in an actual Noctalia session.

### A03 — Typed event decoder (P0)

**Goal:** a pure and defensively validated protocol parser.

**Work:**
- Create `alerts/events.luau` with `--!strict` types for all known event envelopes.
- Validate frame kind and expected `data` types; parse optional threat/alert metadata without inventing fields.
- Unknown event types: ignore. Malformed/oversized/unexpected events: log safely, leave state untouched.
- Distinguish `alerts` from `snapshot` structurally; no reuse of HTTP request client.
- Add unit tests from A01 fixtures.

**Acceptance:** valid cases parse; missing/invalid data are rejected without exceptions; unknown fields do not break compatibility unnecessarily.

### A04 — In-memory realtime store (P0)

**Goal:** deterministic reducer for stream events.

**Work:**
- Create `alerts/realtime-store.luau`: threat map by ID, official alerts collection, session/baseline flags and timestamps.
- Implement `snapshot` replacement, `upsert`, `remove`, official `alerts` replacement and `heartbeat` handling.
- Implement reset of alert freshness on newly observed session; do not erase last-known status merely due to disconnect.
- Avoid storing unnecessary map or movement-prediction data beyond what the model needs.
- Add tests for duplicates, out-of-order/unknown remove, malformed frames and reconnect reset.

**Acceptance:** identical sequences yield identical derived stores; `snapshot` never implicitly clears official alerts; complete new `alerts` replaces prior official state.

### A05 — Location projection and status semantics (P0)

**Goal:** preserve correct current-user status without confusing tracks with official warnings.

**Work:**
- Refactor `alerts/status.luau` to consume the new store/validated official alert model.
- Keep Kyiv city distinct from Kyiv Oblast; preserve raion-to-oblast aggregation of official alerts.
- Preserve supported locations and existing settings format.
- Do not invent red/yellow severity when a valid official alert lacks a `level`; represent unknown classification explicitly. Threats (`advisory`, `areaOnly`, coordinates) are informative, not official alarm triggers.
- Add fixtures for Kyiv/city-vs-oblast, multiple raions, missing level, severity transitions and empty-but-valid alerts.

**Acceptance:** verified official alert status is deterministic; unknown input never produces `clear` by accident.

### A06 — Switch service to WebSocket only (P0)

**Goal:** replace the REST orchestrator while preserving one shared service.

**Work:**
- Rework `service.luau` to compose transport → parser → store → resolver → state.
- Remove HTTP polling, pending HTTP request IDs and HTTP callbacks; do not run any replacement REST call.
- Start the stream when appropriate; determine whether the plugin should connect before region selection (prefer no stream until configured unless tracked-threat features require otherwise).
- On region change, recompute from fresh stored official alert data without restarting the stream; establish a new notification baseline.
- Preserve compatibility with `locations/store.luau`, `widget.luau` and existing state consumers where practical.
- Add integration tests for multiple widget instances and region changes.

**Acceptance:** **no NEPTUN HTTP requests**; one process; UI shows correct status on first validated `alerts` frame; existing location configuration survives upgrade.

### A07 — Reconnect, stale-data detection and failure handling (P0)

**Goal:** safe, observable WS-only failure behavior.

**Work:**
- Track the last valid message, last validated official `alerts` sync and the current session baseline independently.
- Use measured heartbeat behavior to implement a watchdog; schedule a lightweight local update (not network polling).
- Distinguish `connecting`, `live`, `stale`, missing dependency and hard launch failure.
- On silence/connection failure, keep the last validated state visibly stale. On a fresh reconnect `snapshot`, require a new `alerts` baseline before declaring live official-alert status.
- Never spawn another `runStream` merely because a watchdog fired; let the single `websocat` process retry.
- Verify behavior when `websocat` exits permanently. If the API does not expose sufficient lifecycle signals for automatic respawn, **document that limitation** rather than creating uncontrolled duplicate streams.

**Acceptance:** simulated disconnect/reconnect never emits false all-clear; UI displays stale data; no hot reconnect loop or multiple background processes.

### A08 — Notification deduplication (P0)

**Goal:** notify only for verified changes in official alert activity.

**Work:**
- Preserve current behavior: initial baseline and region switch do not notify; a verified start/end does.
- Compare canonical official alert state, not the arrival of `snapshot`, `heartbeat` or connection-status changes.
- Prevent duplicate notifications after reconnect, repeated `alerts` events and unchanged source values.
- Missing severity must not cause an unjustified critical-level notification.

**Likely files:** `notification.luau`, `service.luau`, tests.

**Acceptance:** exactly one notification for each verified activity transition; zero notifications for disconnect, reconnect and repeated equivalent data.

### A09 — Minimal status UI and translations (P1)

**Goal:** communicate data freshness accurately without redesigning the bar.

**Work:**
- Keep layout/modes, tooltip, panels, region picker and current visuals as much as possible.
- Indicate connecting, live and stale states in panel/tooltip; show last valid official update time when known.
- Distinguish **"no confirmed official alert"** from **"data unavailable"**; do not show reassuring green for unknown or stale data.
- Keep the NEPTUN attribution link visible and add a compact notice that it is an aggregator, not an official alert service.
- Update Ukrainian, Russian and English translations.

**Likely files:** `alerts/state.luau`, `ui/presentation.luau`, `ui/widget-view.luau`, `panels/status-panel.luau`, `translations/*.json`.

**Acceptance:** all three languages and display modes render; stale states are visually unambiguous; details panel retains attribution.

### A10 — Regression, cleanup and release (P0)

**Goal:** remove dead REST code, document the external dependency, deliver v2 safely.

**Work:**
- Remove `alerts/api.luau` **if no reusable parser remains**; otherwise rename/extract only the useful pure parsing logic. Remove unused REST mock paths and outdated HTTP comments.
- Check codebase for `noctalia.http`, `/api/v1/alerts`, 30s network polling, HTTP fallback and obsolete test expectations. None should remain in the production data path.
- Extend `tests/runtime.luau`, `tests/checks.luau` (or split targeted tests) with stream fixture playback, reconnect, stale data, missing executable and lifecycle assertions.
- Run existing Luau tests, static analysis/type checking (if configured), format and lint checks; fix failures and record any limitations.
- Update `README.md`, `catalog.toml`, `plugin.toml`, and external dependency guidance. No silent package installation by the plugin.
- Bump the version only when tests and manual Noctalia verification pass.

**Acceptance:** automated tests pass; manual network interruption test passes; no REST traffic; README documents `websocat`, reconnect behavior, stale state and Noctalia/NEPTUN limitations.

## 5. Execution order / Codex task batches

| Batch | Tasks | Expected output |
| --- | --- | --- |
| 01 | A01 | Protocol contract and working fixtures/test baseline |
| 02 | A02 | Stable single-process `websocat` transport |
| 03 | A03 + A04 | Pure parser and event store |
| 04 | A05 | Official-alert location resolver |
| 05 | A06 | WebSocket-only service end-to-end |
| 06 | A07 | Watchdog/reconnect/stale handling |
| 07 | A08 + A09 | Notifications and freshness UI |
| 08 | A10 | Regression, dead-code removal and release preparation |

**Dependencies:** A01 must pass its initial `alerts`-baseline check before A05/A06. A02–A04 before A06. A05 before A06. A06 before A07–A09. A10 last.

## 6. Definition of Done for the release

- [ ] No HTTP/REST requests are made to NEPTUN by the plugin.
- [ ] One `websocat` stream per service, independent of widget count.
- [ ] Every known frame type is handled correctly and validated.
- [ ] First confirmed official-alert status comes **only** from a validated `alerts` frame.
- [ ] Threat tracking and official alerts remain separate.
- [ ] Kyiv city and Kyiv Oblast remain separate; configuration migrates without manual edits.
- [ ] Reconnect resets freshness and resynchronizes from authoritative WS events.
- [ ] No false `clear` or notification on connection loss, partial sync or malformed frames.
- [ ] Missing `websocat` is reported clearly; no automatic installation.
- [ ] All existing display modes and locales continue to work.
- [ ] Tests and formatting checks pass; manual offline/recovery checks pass.
- [ ] README documents dependency, data-source limitations, and official-warning disclaimer.

## 7. Instructions for Codex

When starting any batch, **read this entire plan first**, then read the files involved and their callers. Implement **only the requested batch**, making the smallest coherent set of changes. Do not refactor unrelated modules or jump ahead to the next batch.

Requirements:

1. Prefer `--!strict`, explicit types and small testable modules. Follow existing formatting and repository conventions.
2. Respect the **WS-only constraint**: never introduce REST, polling fallbacks or a Rust service.
3. **Do not guess NEPTUN payload schemas**. Use A01 fixtures and documented/observed behavior; stop and report a blocking contract mismatch.
4. Do not assume `noctalia.runStream()` offers undocumented stream-control APIs.
5. Preserve public plugin behavior and user configuration except for changes explicitly in scope.
6. Add focused positive and negative tests; run the relevant checks.
7. At completion, report: files changed, behavior implemented, commands/tests executed and results, remaining risks/blockers, and a suggested Conventional Commit message.
8. If a task would violate a safety/data-freshness invariant, **stop and explain the issue instead of silently weakening the requirement**.

### Starting prompt to Codex

> Read `AIR_ALERT_V2_PLAN.md` in full. Study the current `air-alert` implementation and `tests/`. Implement **A01 only**: verify the WebSocket event contract with real samples where possible, specifically the delivery of a complete initial `alerts` event and its behavior after reconnect; add deterministic fixtures; repair the test harness baseline without changing production behavior. Do not implement A02 or later. Run tests and report the exact results, unresolved API questions and a Conventional Commit suggestion.

## References

- [NEPTUN developer API](https://neptun.in.ua/developers)
- [Noctalia v5 runtime API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/)
- [websocat manual](https://github.com/vi/websocat/blob/master/doc.md)
- [Air Alert source](https://github.com/Dmich98/noctalia-plugins/tree/master/air-alert)
