--!strict

local events = require("./events.luau")
local time = require("./time.luau")
local catalog = require("../locations/catalog.luau")

-- Matches the SDK default observed on 2026-10-17; a report freshness policy, not a flight prediction.
local MAX_AGE_SECONDS = 420

export type Change = "new" | "update" | "entered" | "left" | "stale" | "resolved" | "removed"

local function matches(threat: events.Threat, selected: catalog.Location): boolean
    local location = catalog.find(threat.locationKey)
    if not location then
        return false
    end
    if location.key == selected.key or location.oblastKey == selected.key then
        return true
    end
    -- Province-only reports may concern any district; explicitly different districts do not.
    return selected.oblastKey ~= nil
        and location.key == selected.oblastKey
        and (threat.areaOnly == true or threat.district == nil)
end

local function isCurrent(threat: events.Threat, nowMs: number): boolean
    if threat.status ~= "active" then
        return false
    end
    local updatedAt = time.toUnixSeconds(threat.updatedAt)
    if not updatedAt then
        return false
    end
    local age = math.floor(nowMs / 1000) - updatedAt
    return age >= 0 and age <= MAX_AGE_SECONDS
end

local function forLocation(
    data: { [string]: events.Threat },
    selected: catalog.Location,
    nowMs: number
): { events.Threat }
    local result: { events.Threat } = {}
    for _, threat in pairs(data) do
        if matches(threat, selected) and isCurrent(threat, nowMs) then
            table.insert(result, threat)
        end
    end
    table.sort(result, function(a: events.Threat, b: events.Threat): boolean
        return a.id < b.id
    end)
    return result
end

local function classify(
    previous: events.Threat?,
    current: events.Threat?,
    selected: catalog.Location,
    nowMs: number
): Change?
    local wasLocal = previous ~= nil and matches(previous, selected)
    if not current then
        if wasLocal then
            return "removed"
        end
        return nil
    end
    if not matches(current, selected) then
        if wasLocal and current.locationKey and isCurrent(current, nowMs) then
            return "left"
        end
        return nil
    end
    if previous and wasLocal and previous.status ~= current.status then
        if current.status == "stale" then
            return "stale"
        elseif current.status == "resolved" then
            return "resolved"
        end
    end
    if not isCurrent(current, nowMs) then
        return nil
    end
    if not previous then
        return "new"
    elseif not wasLocal then
        return "entered"
    end
    -- Compare displayed content; coordinate, heading and timestamp-only changes stay silent.
    if
        previous.type ~= current.type
        or previous.title ~= current.title
        or previous.count ~= current.count
        or previous.locationKey ~= current.locationKey
        or previous.district ~= current.district
        or previous.locality ~= current.locality
        or previous.explanationShort ~= current.explanationShort
        or previous.status ~= current.status
        or (previous.advisory == true) ~= (current.advisory == true)
        or (previous.areaOnly == true) ~= (current.areaOnly == true)
    then
        return "update"
    end
    return nil
end

return {
    matches = matches,
    isCurrent = isCurrent,
    classify = classify,
    forLocation = forLocation,
}
