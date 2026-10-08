# Noctalia Plugins

Personal plugin source for Noctalia v5.

## Plugins

- **[Air Alert](air-alert/)** — air raid alerts in Ukraine powered by [NEPTUN](https://neptun.in.ua/), with region and location selection. Requires plugin API 22 or newer. Supports English, Ukrainian, and Russian.

A single background service polls NEPTUN every 30 seconds and shares the status across all widget instances.

## Installation

Open **Settings → Plugins → Add source** and add this repository as a Git source, or its local checkout as a path source. Enable **Air Alert**, then add its widget to your bar.

Click the widget to view alert details or change your location.

In the widget settings, choose **Icon only**, **Icon and status**, or **Icon, location and status** (default). Tooltips show details in every mode.

Choose **Colored** to use red or yellow for alerts and green when no alert is active, or **Monochrome** (default) to keep the theme colors.
