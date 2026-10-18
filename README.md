# Noctalia Plugins

Plugins for Noctalia v5.

## Air Alert

Air raid alerts and current threats for Ukrainian oblasts and districts, powered by
[NEPTUN](https://neptun.in.ua/). Supports English, Ukrainian and Russian.

### Requirements

**The plugin requires external dependencies; they are not installed automatically.**

- Noctalia with plugin API 24 or newer and its `noctalia` command in `PATH`.
- **`websocat`** in Noctalia's `PATH` for live updates. Install it with your system
  package manager before enabling the plugin.
- `xdg-open` (usually provided by `xdg-utils`) to open the source website.

### Installation

1. In **Settings → Plugins → Add source**, add
   `https://github.com/Dmich98/noctalia-plugins` as a Git source.
2. Enable **Air Alert** and add its widget to the bar.
3. Select an oblast and optionally a district, then save. You can also detect your
   location through Noctalia; check the suggested location before saving.

Left-click for status and current threats; right-click to change your location.

### Settings

- Widget: display mode and colored or monochrome appearance.
- Plugin: notifications for new threats only or new threats and updates.
- Plugin: floating or attached panels; one mode applies to both panels.

NEPTUN is a third-party source. Follow official local alerts; this plugin does not
replace them.
