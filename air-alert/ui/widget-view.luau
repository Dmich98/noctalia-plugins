--!strict

local locations = require("../locations/catalog.luau")
local alertState = require("../alerts/state.luau")
local alertDisplay = require("./alert-display.luau")
local alertTooltip = require("./alert-tooltip.luau")

type Presentation = {
    text: string,
    glyph: string,
    tooltip: string | { alertTooltip.TooltipRow },
    color: string?,
}

local function statusPresentation(
    location: locations.Location?,
    state: alertState.AlertState?
): Presentation
    if not location then
        local text = noctalia.tr("location.choose")
        return { text = text, glyph = "map-pin", tooltip = text }
    end

    state = alertState.matchesLocation(state, location) and state or nil
    local locationName = locations.displayName(location)
    if not state or state.loading then
        return {
            text = noctalia.tr("status.loading"),
            glyph = "loader",
            tooltip = locationName .. "\n" .. noctalia.tr("status.loading_details"),
        }
    end
    if state.error then
        return {
            text = noctalia.tr("status.unavailable"),
            glyph = state.errorKind == "decode" and "alert-circle" or "wifi-off",
            tooltip = locationName .. "\n" .. state.error,
        }
    end
    if state.active == nil then
        local text = noctalia.tr("status.unavailable")
        return { text = text, glyph = "wifi-off", tooltip = locationName .. "\n" .. text }
    end

    local appearance = alertDisplay.statusAppearance(state.active, state.level)
    local text = state.active
            and noctalia.tr(
                "widget.alert",
                {
                    level = alertDisplay.formatAlertLevel(
                        state.level or noctalia.tr("level.unknown")
                    ),
                } :: { [string]: string | number | boolean }
            )
        or noctalia.tr("widget.safe")
    return {
        text = text,
        glyph = appearance.glyph,
        color = appearance.color,
        tooltip = alertTooltip.formatAlertTooltip(locationName, state),
    }
end

local function displayText(location: locations.Location?, text: string): string
    local mode = noctalia.getConfig("display_mode")
    if mode == "icon" then
        return ""
    end
    if mode == "status" or not location then
        return text
    end
    return locations.displayName(location) .. " · " .. text
end

local function render(location: locations.Location?, state: alertState.AlertState?): ()
    local presentation = statusPresentation(location, state)
    barWidget.setText(displayText(location, presentation.text))
    barWidget.setGlyph(presentation.glyph)
    barWidget.setTooltip(presentation.tooltip)
    local widgetColor = noctalia.getConfig("color_mode") == "colored" and presentation.color
        or "on_surface"
    barWidget.setColor(widgetColor)
    barWidget.setGlyphColor(widgetColor)
end

return { render = render }
