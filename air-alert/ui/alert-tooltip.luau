--!strict

local alerts = require("../alerts/status.luau")
local alertDisplay = require("./alert-display.luau")
local alertTime = require("../alerts/time.luau")

export type TooltipRow = { key: string, value: string }

local function formatAlertTooltip(locationName: string, alert: alerts.AlertRegion?): { TooltipRow }
    local rows: { TooltipRow } = {
        { key = noctalia.tr("label.location"), value = locationName },
    }

    if alert then
        table.insert(
            rows,
            { key = noctalia.tr("label.status"), value = noctalia.tr("status.alert") }
        )
        table.insert(
            rows,
            { key = noctalia.tr("label.level"), value = alertDisplay.formatAlertLevel(alert.level) }
        )
        local since = alertTime.parseSince(alert.since)
        table.insert(rows, {
            key = noctalia.tr("label.since"),
            value = since and alertTime.formatTime(since) or noctalia.tr("time.unavailable"),
        })
    else
        table.insert(
            rows,
            { key = noctalia.tr("label.status"), value = noctalia.tr("status.safe") }
        )
    end

    return rows
end

return {
    formatAlertTooltip = formatAlertTooltip,
}
