--!strict

local locations = require("../locations/catalog.luau")
local alertTime = require("./time.luau")

export type AlertRegion = {
    key: string,
    name: string,
    oblast: string,
    since: string,
    level: string,
    reasons: { string }?,
}

export type AlertsResponse = {
    raions: { AlertRegion },
    oblasts: { AlertRegion },
}

local function isArray(value: any, validItem: (any) -> boolean): boolean
    if typeof(value) ~= "table" then
        return false
    end
    local count = 0
    for index, item in pairs(value) do
        if
            typeof(index) ~= "number"
            or index % 1 ~= 0
            or index < 1
            or index > #value
            or not validItem(item)
        then
            return false
        end
        count += 1
    end
    return count == #value
end

local function isAlert(value: any): boolean
    return typeof(value) == "table"
        and typeof(value.key) == "string"
        and value.key ~= ""
        and typeof(value.name) == "string"
        and typeof(value.oblast) == "string"
        and typeof(value.since) == "string"
        and typeof(value.level) == "string"
        and value.level ~= ""
        and (
            value.reasons == nil
            or isArray(value.reasons, function(reason: any): boolean
                return typeof(reason) == "string"
            end)
        )
end

local function parseAlertsResponse(body: string): (AlertsResponse?, string?)
    local data, err = noctalia.json.decode(body)

    if not data or err then
        return nil, err or "Empty response"
    end

    if typeof(data) ~= "table" then
        return nil, "Expected an alerts object"
    end

    if not isArray(data.oblasts, isAlert) or not isArray(data.raions, isAlert) then
        return nil, "Invalid oblasts or raions alerts"
    end

    return data :: AlertsResponse, nil
end

local function resolveLocationAlert(
    data: AlertsResponse,
    location: locations.Location
): AlertRegion?
    local result: AlertRegion? = nil
    local reasons: { string } = {}
    local seen: { [string]: boolean } = {}
    local levels: { [string]: number } = { yellow = 1, red = 2 }

    local function include(alert: AlertRegion): ()
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

return {
    parseAlertsResponse = parseAlertsResponse,
    resolveLocationAlert = resolveLocationAlert,
}
