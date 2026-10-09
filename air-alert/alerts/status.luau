--!strict

local api = require("./api.luau")
local alertTime = require("./time.luau")

local function forLocation(data: api.Response, locationKey: string): api.OblastAlert?
    local result: api.OblastAlert? = nil
    local reasons: { string } = {}
    local seenReasons: { [string]: boolean } = {}
    local earliest: number? = nil
    local allTimesKnown = true

    local function include(alert: api.OblastAlert): ()
        local selected: api.OblastAlert = result or { key = locationKey, level = alert.level }
        if result then
            local current = selected.level
            local currentKnown = current == "red" or current == "yellow"
            local incomingKnown = alert.level == "red" or alert.level == "yellow"
            if (currentKnown and not incomingKnown) or (current == "yellow" and alert.level == "red") then
                selected.level = alert.level
            end
        end
        result = selected
        local start = alertTime.toUnixSeconds(alert.since)
        if not start then
            allTimesKnown = false
        elseif not earliest or start < earliest then
            earliest = start
            selected.since = alert.since
        end
        for _, reason in ipairs(alert.reasons or {}) do
            if not seenReasons[reason] then
                seenReasons[reason] = true
                table.insert(reasons, reason)
            end
        end
    end

    for _, alert in ipairs(data.oblasts) do
        if alert.key == locationKey then
            include(alert)
        end
    end
    for _, alert in ipairs(data.raions) do
        if alert.oblastKey == locationKey then
            include(alert)
        end
    end
    local selected = result
    if selected then
        selected.reasons = reasons
        if not allTimesKnown then
            selected.since = nil
        end
    end
    return selected
end

return { forLocation = forLocation }
