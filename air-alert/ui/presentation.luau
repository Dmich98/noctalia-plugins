--!strict

local alertState = require("../alerts/state.luau")
local displayTime = require("./time.luau")

export type View = { text: string, glyph: string, color: string, detail: string }
export type TooltipRow = { key: string, value: string }

local levels: { [string]: { color: string, label: string } } = {
    red = { color = "#ef4444", label = "level.red" },
    yellow = { color = "#facc15", label = "level.yellow" },
}

local reasonGlyphs: { [string]: string } = {
    ["Дронова загроза (жовтий рівень)"] = "drone",
    ["Ракетна загроза (червоний рівень)"] = "rocket",
    ["Дрони"] = "drone",
    ["Ракети"] = "rocket",
}

local displayModes: { [string]: (string, string?) -> string } = {
    icon = function(_status: string, _region: string?): string
        return ""
    end,
    status = function(status: string, _region: string?): string
        return status
    end,
    location_status = function(status: string, region: string?): string
        return status .. (region and " · " .. region or "")
    end,
}

local function widgetText(mode: string?, status: string, region: string?): string
    return (displayModes[mode or ""] or displayModes.status)(status, region)
end

local function forState(state: alertState.State): View
    if state.kind == "unconfigured" then
        local text = noctalia.tr("location.choose")
        return { text = text, glyph = "map-pin", color = "on_surface_variant", detail = text }
    end
    if state.kind == "loading" then
        local text = noctalia.tr("status.loading")
        return { text = text, glyph = "loader", color = "on_surface_variant", detail = text }
    end
    if state.kind == "error" then
        return {
            text = noctalia.tr("status.unavailable"),
            glyph = "wifi-off",
            color = "on_surface_variant",
            detail = noctalia.tr("error." .. state.code),
        }
    end
    if state.kind == "clear" then
        local text = noctalia.tr("status.safe")
        return { text = text, glyph = "shield-check", color = "#22c55e", detail = text }
    end
    local knownLevel = levels[state.level]
    if knownLevel then
        return {
            text = noctalia.tr("status.alert"),
            glyph = "alert-triangle",
            color = knownLevel.color,
            detail = noctalia.tr(knownLevel.label),
        }
    end
    local unknown = noctalia.tr("level.unknown")
    return {
        text = noctalia.tr("status.alert") .. " · " .. unknown,
        glyph = "alert-triangle",
        color = "on_surface_variant",
        detail = unknown .. ": " .. state.level,
    }
end

local function tooltipRows(
    locationName: string?,
    state: alertState.State,
    view: View
): { TooltipRow }
    local rows: { TooltipRow } = {}
    if locationName then
        table.insert(rows, { key = noctalia.tr("label.location"), value = locationName })
    end
    table.insert(rows, {
        key = noctalia.tr("label.status"),
        value = state.kind == "alert" and noctalia.tr("status.alert") or view.text,
    })
    if state.kind == "alert" then
        table.insert(rows, { key = noctalia.tr("label.level"), value = view.detail })
        table.insert(rows, {
            key = noctalia.tr("label.since"),
            value = displayTime.formatKyivTimestamp(state.since) or noctalia.tr("time.unavailable"),
        })
    elseif state.kind == "error" then
        table.insert(rows, { key = noctalia.tr("label.reason"), value = view.detail })
    end
    return rows
end

local function glyphForReason(reason: string): string?
    return reasonGlyphs[reason]
end

return {
    widgetGlyph = "brand-flightradar24",
    forState = forState,
    glyphForReason = glyphForReason,
    tooltipRows = tooltipRows,
    widgetText = widgetText,
}
