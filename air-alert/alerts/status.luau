--!strict

local events = require("./events.luau")
local realtime = require("./realtime-store.luau")
local catalog = require("../locations/catalog.luau")
local alertTime = require("./time.luau")

export type Projection =
    { kind: "unsupported" }
    | { kind: "unknown" }
    | { kind: "current", alert: events.OblastAlert?, updatedAt: string?, syncedAtMs: number }
    | { kind: "stale", alert: events.OblastAlert?, updatedAt: string?, syncedAtMs: number }

-- A nil alert means absence only within a complete, validated collection.
local function forLocation(data: events.Alerts, location: catalog.Location): events.OblastAlert?
    local locationKey = location.key
    local oblastKey = location.oblastKey or locationKey
    local result: events.OblastAlert? = nil
    local reasons: { string } = {}
    local seenReasons: { [string]: boolean } = {}
    local earliest: number? = nil
    local allTimesKnown = true

    local function include(alert: events.OblastAlert): ()
        local selected: events.OblastAlert = result or { key = locationKey, level = alert.level }
        if result then
            local current = selected.level
            local currentKnown = current == "red" or current == "yellow"
            local incomingKnown = alert.level == "red" or alert.level == "yellow"
            -- Missing classification dominates; unfamiliar levels remain unfamiliar.
            if
                current ~= nil
                and (
                    alert.level == nil
                    or (currentKnown and not incomingKnown)
                    or (current == "yellow" and alert.level == "red")
                    or (
                        not currentKnown
                        and not incomingKnown
                        and alert.level ~= nil
                        and alert.level < current
                    )
                )
            then
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
        if alert.key == oblastKey then
            include(alert)
        end
    end
    for _, alert in ipairs(data.raions) do
        if
            alert.oblastKey == oblastKey
            and (not location.sourceKey or alert.key == location.sourceKey)
        then
            include(alert)
        end
    end
    local selected = result
    if selected then
        table.sort(reasons)
        selected.reasons = reasons
        if not allTimesKnown then
            selected.since = nil
        end
    end
    return selected
end

local function project(source: realtime.AlertState, locationKey: string): Projection
    local location = catalog.find(locationKey)
    if not location then
        return { kind = "unsupported" }
    end
    if source.kind == "unknown" then
        return { kind = "unknown" }
    end
    -- An unrecognized territory in the official set cannot establish a safe absence.
    for _, alert in ipairs(source.data.oblasts) do
        local territory = catalog.find(alert.key)
        if not territory or territory.oblastKey then
            return { kind = "unknown" }
        end
    end
    for _, alert in ipairs(source.data.raions) do
        local parent = catalog.find(alert.oblastKey)
        if not parent or parent.oblastKey then
            return { kind = "unknown" }
        end
        if location.oblastKey then
            local territory = catalog.find("raion:" .. alert.key)
            if not territory or territory.oblastKey ~= alert.oblastKey then
                return { kind = "unknown" }
            end
        end
    end
    local alert = forLocation(source.data, location)
    if source.kind == "stale" then
        return {
            kind = "stale",
            alert = alert,
            updatedAt = source.data.updatedAt,
            syncedAtMs = source.syncedAtMs,
        }
    end
    return {
        kind = "current",
        alert = alert,
        updatedAt = source.data.updatedAt,
        syncedAtMs = source.syncedAtMs,
    }
end

return { project = project }
