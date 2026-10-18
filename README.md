# Noctalia Plugins

Personal plugin source for Noctalia v5.

## Plugins

- **[Air Alert](air-alert/)** — oblast and district alerts in Ukraine powered by [NEPTUN](https://neptun.in.ua/). Requires plugin API 24 or newer. Supports English, Ukrainian, and Russian.

A single background service connects to NEPTUN over WebSocket after a location is selected and shares the status across all widget instances. It requires `websocat` in Noctalia's PATH and uses no alert HTTP polling or REST fallback. Region changes reuse the same stream and the latest synchronized official-alert set. The selection is saved in the plugin's data directory.
It sends a notification when validated data shows an alert starting or ending in the selected territory. Yellow and red alerts use critical urgency; clear notifications use normal urgency. Critical notifications stay visible for 15 seconds; normal notifications, including all-clears and inactive target updates, for 5 seconds. They show the widget icon, alert level, and available reasons and start time. The first result after launch or a location change establishes the baseline without a notification.

The same stream also sends labeled notifications about NEPTUN targets: **New target**, **Target update**, **Reported in selected region**, **Reported outside selected region**, **Data marked stale**, **Record closed**, and **Target lost**. Each target uses a compact card with a bold source title (or type) and count, reported place, and the source's short explanation when supplied. Direction is shown only as supplied in that explanation; numeric bearings and calculated destinations are omitted. Notifications put the title/count in the native bold summary beside the event kind. The count is omitted when the source does not supply it. The panel heading counts current source records; a record may describe several targets via its own `×N` count. Technical IDs, timestamps, repeated region names and field labels are hidden. Notifications keep the event kind in their heading. An oblast-wide selection includes its districts. A district selection includes that district and reports that name only its parent oblast; those broader reports show the reported oblast. Explicit reports for other districts are excluded. Kyiv city remains separate from Kyiv Oblast. Region and district names are mapped to catalog keys at the decoder boundary; the selected-region filter uses source territory metadata.

New, updated and newly local target notifications require an `active` track with a valid update time no more than seven minutes old, and not in the future. This seven-minute threshold is a local notification policy matching the observed SDK default. Changes to type/title, count, reported area/place, explanation or advisory status notify as **Target update** for the same ID. Heading-only and coordinate-only changes, identical packets and timestamp-only updates stay silent. A previously known target explicitly reported in the selected territory for the first time is labeled **Reported in selected region**. A fresh report placing a local target elsewhere is labeled **Reported outside selected region**; this describes source metadata rather than a confirmed boundary crossing.

A source status transition to `stale` or `resolved`, or an explicit stream `remove`, gets its own normal-priority notification for a previously local target. A closed or removed source record does not establish destruction of the target or an official all-clear. Missing or unknown territory metadata is not treated as leaving the region. Unknown target statuses remain unknown and do not produce an active-target notification.

Startup and reconnect snapshots are silent baselines. Changing the selected location does not announce already cached targets; later changes to those targets are still reported as updates. Removed IDs are forgotten, so a later reappearance can be labeled new again. After 45 seconds of stream silence, a fresh threat snapshot is required before more target notifications. Official-alert synchronization has a separate deadline and does not gate a healthy threat stream. No notification history is persisted.

New, updated and newly local UAV, FPV, missile, ballistic and guided-bomb targets use critical urgency. `advisory` observations, aviation/reconnaissance reports, unknown types, departures and inactive/removed records use normal urgency. Observations retain a separate label in the body alongside the event heading. Source attribution appears only in the panel footer; notifications and feed labels omit the provider name and do not change the official siren status shown in the bar. They describe source reports, without predicting an arrival time or treating a reported place as a confirmed destination. Reload the plugin to activate the target event notifications.

Under **Settings → Plugins → Air Alert**, **Threat notifications** offers **New threats only** and **New threats + updates** (default). New-only includes new IDs and targets first reported in the selected region. The second mode also includes detail updates, departures and stale/closed/removed records. The panel always continues to update live, and official siren notifications work in both modes. Switching modes does not replay cached targets. This is a shared plugin setting, not a per-widget option.

## Installation

Install `websocat` with your system package manager (`websocat --version` should work), then restart or reload the plugin if it was already enabled.

Open **Settings → Plugins → Add source** and add this repository as a Git source, or its local checkout as a path source. Enable **Air Alert**, then add its widget to your bar.

Left-click the widget to choose a location when unconfigured or view the current status after selection. Right-click it to choose another location. Select an oblast and optionally a district, then click **Save location**. The status panel links to the NEPTUN source website. Kyiv city and Kyiv Oblast are separate choices.

In the location picker, **Detect with Noctalia** uses the same IP geolocation endpoint as Noctalia's Location service (`https://api.noctalia.dev/geolocate`). It runs only when pressed and sends no coordinates to NEPTUN. The plugin matches the returned coordinates locally against bundled NEPTUN oblast and district boundaries. Review or correct the proposed region and district, then save; detection alone never changes the active location. IP location can point to a provider or VPN exit rather than your actual position. There is no background location tracking, and Noctalia's global location settings are not changed. An unavailable service, invalid coordinates, an ambiguous boundary, or a point outside the supported territory leaves the saved selection unchanged. When only the oblast can be matched, the picker proposes the whole region explicitly.

A district selection includes alerts for that district and alerts covering its whole oblast. Neighboring district alerts do not activate it. Selecting **Entire region** keeps the existing aggregation of every district in that oblast. Existing saved oblast selections remain valid; new district selections use `raion:`-prefixed keys in the same config file. Older plugin versions do not support those keys and will ask for a new selection.

In the widget settings, choose **Icon only**, **Icon and status** (default), or **Icon, status and region**. **Colored** paints both the text and Flightradar24 icon with the status color. **Monochrome** keeps the text neutral; after an alert ends, its icon stays green for 15 seconds before returning to the base color. Tooltips show the region and status in every mode. During an alert, they also show its level and declared time in Kyiv time (`DD.MM.YYYY HH:MM`), or "Unknown" if no valid time was supplied. The status panel uses the same format for declared and updated times and shows alert duration in hours and minutes when the start time is known. It refreshes on shared status updates.

For a whole-region selection, the status combines NEPTUN's `oblasts` alerts with active `raions` alerts belonging to that oblast. Kyiv city remains separate from Kyiv Oblast. The status panel keeps the alert icon beside the official siren status. Its former reasons section now shows **Current NEPTUN threats** for the selected territory, using the same compact title/count, place and short source text as target notifications; the bar keeps its Flightradar24 icon. An initial clear result uses the base icon color immediately in monochrome mode. Loading, errors, and unknown alert levels use a neutral icon color. The service retains validated `updatedAt`, `since`, and `reasons` values; the tooltip displays `since` when available.

Before the first validated official-alert set, the widget shows loading. A reconnect snapshot or 45 seconds without a validated stream message marks the last confirmed status as stale. The widget uses neutral colors; its tooltip and details panel retain the previous alert level and start time, and the panel hides the running duration until synchronization recovers. A previously clear status is also explicitly stale, never green. A fresh official-alert set is required to restore current status. Heartbeats alone cannot establish or restore official-alert synchronization. Initial synchronization has its own 45-second deadline even while heartbeats arrive; if no official baseline has ever arrived, expiry shows data unavailable. Missing `websocat` and rejected stream startup show translated errors; reload the plugin after fixing them.

The current-threat panel list comes from the same shared service as notifications and updates while the panel is open. It includes active matching reports with valid, non-future update times no older than seven minutes. Source `remove`, `stale` and `resolved` events remove a target immediately; the service also expires old reports on its local timer even if no target event arrives. After stream silence, the list is hidden behind an unavailable/synchronizing message until a new threat snapshot arrives. Loading, unavailable and a synchronized empty list have different messages. An empty list means no current NEPTUN reports for the selected territory, not an official all-clear. Threats can be displayed while the official-alert baseline is still loading or unavailable. Multiple panels share the same stream and selection.

NEPTUN is a third-party data source. Follow official local alerts; this widget does not replace them.

## Development

Run the regression suite with `python3 tests/run.py` (requires the Luau CLI), or
`python3 tests/run.py /path/to/luau`. Run fixture integrity and process checks with
`python3 -m unittest discover -s tests -p 'test_*.py' -v`.

Check the new WebSocket modules with the editor-compatible Luau analyzer:
`luau-lsp analyze --flag:LuauSolverV2=false --definitions=noctalia.d.luau air-alert/alerts/events.luau air-alert/alerts/realtime-store.luau air-alert/alerts/status.luau air-alert/alerts/state.luau air-alert/ui/presentation.luau air-alert/service.luau`.

The planned WebSocket migration is documented in the
[protocol and transport observations](docs/neptun-ws-protocol.md), including
sanitized recordings, the approved shell supervisor, event decoder, realtime store and location projection.
A06 connects the WebSocket pipeline to the service. Live manual testing can start now;
[manual checks](docs/neptun-ws-protocol.md#manual-noctalia-checks-after-a06) cover startup, region changes, multiple widgets and reload.
The WebSocket client sends protocol pings every 10 seconds and drops connections without a pong for 30 seconds, allowing the same supervisor to reconnect after a silent network failure. Reload an already running plugin once to apply these transport options.

A07 preserves visible last-known details on stale data. A permanently exited stream has no host exit callback: the plugin marks data stale/unavailable without launching another supervisor. Reload the plugin to restart it.

The bundled geographic data in `locations/boundaries.luau` preserves the exact
polygon coordinates and interior rings from NEPTUN's `oblasts.geojson` (27
features) and `raions.geojson` (136 features), captured on 2026-10-17. District
parent keys in `locations/raions.luau` were checked against the oblast polygons
and all 69 official district-parent pairs in the recorded WebSocket baseline.
The geolocation request uses the host HTTP API (available at plugin API 24),
which honors offline mode and has a 30-second request timeout in the checked
host source. The API response was checked live for numeric `lat` and `lng`;
IP, city and other response fields are neither persisted nor logged.

Manual checks for location detection: open the picker from each widget, detect
and correct a district, save and reload the plugin; confirm both widgets and
the status panel show the saved district. Close the picker or change the region
while detection is pending and verify a delayed result is ignored. Try offline
mode and a VPN/outside-Ukraine result; the previous selection should remain.
Check that all picker controls and error text fit, and compare a district-only
alert with an oblast-wide alert in each display/color mode.

Manual checks for target notifications: with two widgets sharing one selection,
confirm a new local target produces one **New target** message. Change its
reported place, description or count and check for **Target update** for the same
target. Identical packets and timestamp-only updates should stay silent. Check
explicit source moves into/out of the selected scope, `stale`/`resolved` status
changes, and removal: inactive messages use normal urgency and last-reported
wording. Reconnect snapshots and A → B → A location changes must not replay
cached targets. Check a whole-oblast report while a district is selected and
an explicit neighboring-district report. Confirm observations are labeled and
use normal urgency, no numeric bearings are generated, and target notifications
do not change the official siren status.

Manual checks for the current-threat panel: open details, receive a snapshot
and change the place/description/count of a local target while the panel remains
open. Confirm the same target updates in place, a removed/closed/stale
track disappears, and report expiry removes it without another target event.
Check whole-oblast reports versus neighboring districts and switch the selected
territory with two widgets. Disconnect/reconnect: old targets must not appear
current during synchronization. Check the loading and empty messages, scrolling
with several long reports: only the threat list should scroll, while the region, siren status, threat heading, update time and source link stay fixed. The heading shows **Threats · N**, with a divider below it and separators only between targets. Both panels use the shared **Panel mode** setting under **Settings → Plugins → Air Alert**: **Floating** (default) or **Attached**. Changes apply on the next opening, including transitions between location selection and status, and keep the opening widget as the anchor. Floating panels use Noctalia's native outer border from `[shell.panel]`; attached panels use its native attached appearance. API 24 uses separate native entries for the attached variants; the existing panel IDs remain the floating entries. It is 600 px tall, with a 240 px threat viewport that grows into remaining space; check that at least one and a half typical cards are visible.

The compact target cards share one formatter between the panel and notifications.
Observations retain a short label; oblast-only reports show the oblast name without a district-unknown note. Event headings distinguish closed, lost and stale records. Detail lines use
bullets in both notifications and the status panel; there is no extra
last-known-data line. Filtering, expiry and notification urgency stay the same.

Manual checks for emphasis and notification mode: confirm the panel shows a bold
target title with `×N` only when the count is supplied and a current record count. Check that target
notifications show the type/count in the bold heading without repeating it in
the body. Change the plugin notification mode, receive a new target and then an
update/closure, and confirm only the selected classes notify while the panel
continues to update in both modes.

Manual direction check: confirm the same source description appears as a bullet in the
panel and notification, with no generated degrees or destination estimate. A heading-only
update must stay silent; changing the source description must notify in new-and-updates mode.

Manual panel-mode check: switch **Panel mode** between Floating and Attached, then
open status and location selection from each of two widgets. Save a location and verify
the transition keeps the chosen mode and the opening widget. Floating mode should use
the native shell outline; Attached should join the bar. Reload the plugin once after
updating the manifest. Explicit IPC panel IDs and Noctalia's per-entry shell overrides
continue to refer to their individual native entries.
