# Noctalia Plugins

Personal plugin source for Noctalia v5.

## Plugins

- **[Air Alert](air-alert/)** — oblast-level alerts in Ukraine powered by [NEPTUN](https://neptun.in.ua/). Requires plugin API 24 or newer. Supports English, Ukrainian, and Russian.

A single background service polls NEPTUN every 30 seconds after an oblast is selected and shares the status across all widget instances. The selection is saved in the plugin's data directory.
It sends a notification when validated data shows an alert starting or ending in the selected oblast. Yellow alerts use normal urgency, red alerts use critical urgency, and notifications show the widget icon, alert level, and available reasons and start time. The first result after launch or a location change establishes the baseline without a notification.

## Installation

Open **Settings → Plugins → Add source** and add this repository as a Git source, or its local checkout as a path source. Enable **Air Alert**, then add its widget to your bar.

Left-click the widget to choose an oblast when unconfigured or view the current status after selection. Right-click it to choose another oblast. The status panel links to the NEPTUN source website. Kyiv city and Kyiv Oblast are separate choices.

In the widget settings, choose **Icon only**, **Icon and status** (default), or **Icon, status and region**. **Colored** paints both the text and Flightradar24 icon with the status color. **Monochrome** keeps the text neutral; after an alert ends, its icon stays green for 15 seconds before returning to the base color. Tooltips show the region and status in every mode. During an alert, they also show its level and declared time in Kyiv time (`DD.MM.YYYY HH:MM`), or "Unknown" if no valid time was supplied. The status panel uses the same format for declared and updated times and shows alert duration in hours and minutes when the start time is known. It refreshes on shared status updates.

The status combines NEPTUN's `oblasts` alerts with active `raions` alerts belonging to the selected oblast. Kyiv city remains separate from Kyiv Oblast. The status panel keeps the alert icon beside the status and lists available causes under a heading, with neutral drone or rocket icons for recognized reasons; the bar keeps its Flightradar24 icon. An initial clear result uses the base icon color immediately in monochrome mode. Loading, errors, and unknown alert levels use a neutral icon color. The service retains validated `updatedAt`, `since`, and `reasons` values; the tooltip displays `since` when available.
