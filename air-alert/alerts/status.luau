--!strict

local locations = require("../locations/catalog.luau")
local alertTime = require("./time.luau")
local alertsApi = require("./api.luau")

local function resolveLocationAlert(
    data: alertsApi.AlertsResponse,
    location: locations.Location
): alertsApi.AlertRegion?
    local result: alertsApi.AlertRegion? = nil
    local reasons: { string } = {}
    local seen: { [string]: boolean } = {}
    local levels: { [string]: number } = { yellow = 1, red = 2 }

    local function include(alert: alertsApi.AlertRegion): ()
        if not result then
            result = table.clone(alert)
        else
            if (levels[alert.level] or 0) > (levels[result.level] or 0) then
                result.level = alert.level
            end
            local start = alertTime.parseSince(alert.since)
            local previousStart = alertTime.parseSince(result.since)
            -- An unknown start must not become a made-up duration for the whole region.
            if not start or not previousStart then
                result.since = ""
            elseif start < previousStart then
                result.since = alert.since
            end
        end
        for _, reason in ipairs(alert.reasons or {}) do
            if not seen[reason] then
                seen[reason] = true
                table.insert(reasons, reason)
            end
        end
    end

    local regions = location.locationType == "raion" and data.raions or data.oblasts
    for _, alert in ipairs(regions) do
        if alert.key == location.locationKey then
            include(alert)
        end
    end
    if location.locationType == "oblast" and location.locationName:find("область") then
        for _, alert in ipairs(data.raions) do
            if alert.oblast == location.locationName then
                include(alert)
            end
        end
    end
    if result then
        result.key = location.locationKey
        result.name = location.locationName
        result.reasons = reasons
    end
    return result
end

return { resolveLocationAlert = resolveLocationAlert }
