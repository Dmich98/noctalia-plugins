--!strict

local events = require("./events.luau")

export type AlertState =
    { kind: "unknown" }
    | { kind: "current", data: events.Alerts, syncedAtMs: number }
    | { kind: "stale", data: events.Alerts, syncedAtMs: number }
export type Store = {
    session: number,
    threats: { [string]: events.Threat },
    alerts: AlertState,
    lastMessageAtMs: number?,
    lastMessageTs: string?,
}

local function new(): Store
    return { session = 0, threats = {}, alerts = { kind = "unknown" } }
end

local function sameThreat(a: events.Threat, b: events.Threat): boolean
    return a.id == b.id
        and a.type == b.type
        and a.updatedAt == b.updatedAt
        and a.advisory == b.advisory
        and a.areaOnly == b.areaOnly
        and a.locationKey == b.locationKey
        and a.title == b.title
        and a.district == b.district
        and a.locality == b.locality
        and a.explanationShort == b.explanationShort
        and a.status == b.status
        and a.heading == b.heading
        and a.confidenceLevel == b.confidenceLevel
        and a.count == b.count
end

local function sameAlert(a: events.OblastAlert, b: events.OblastAlert): boolean
    if a.key ~= b.key or a.level ~= b.level or a.since ~= b.since then
        return false
    end
    local left, right = a.reasons, b.reasons
    if not left or not right then
        return left == right
    end
    if #left ~= #right then
        return false
    end
    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end
    return true
end

local function sameAlerts(a: events.Alerts, b: events.Alerts): boolean
    if
        a.version ~= b.version
        or a.updatedAt ~= b.updatedAt
        or #a.oblasts ~= #b.oblasts
        or #a.raions ~= #b.raions
    then
        return false
    end
    for index = 1, #a.oblasts do
        if not sameAlert(a.oblasts[index], b.oblasts[index]) then
            return false
        end
    end
    for index = 1, #a.raions do
        local alert = a.raions[index]
        local other = b.raions[index]
        if alert.oblastKey ~= other.oblastKey or not sameAlert(alert, other) then
            return false
        end
    end
    return true
end

-- Accept only validated, frozen events from the decoder. This store owns its mutable map.
-- Return whether content/session/baseline changed; activity timestamps still advance on false.
local function apply(store: Store, event: events.Event, receivedAtMs: number): boolean
    store.lastMessageAtMs = receivedAtMs
    store.lastMessageTs = event.ts
    if event.type == "snapshot" then
        store.session += 1
        local threats: { [string]: events.Threat } = {}
        for index = 1, #event.data.threats do
            local threat = event.data.threats[index]
            threats[threat.id] = threat
        end
        store.threats = threats
        local previous = store.alerts
        if previous.kind ~= "unknown" then
            local stale: AlertState =
                { kind = "stale", data = previous.data, syncedAtMs = previous.syncedAtMs }
            store.alerts = stale
        end
        return true
    elseif event.type == "upsert" then
        local previous = store.threats[event.data.id]
        if previous and sameThreat(previous, event.data) then
            return false
        end
        store.threats[event.data.id] = event.data
        return true
    elseif event.type == "remove" then
        if not store.threats[event.data.id] then
            return false
        end
        store.threats[event.data.id] = nil
        return true
    elseif event.type == "alerts" then
        local previous = store.alerts
        if previous.kind == "current" and sameAlerts(previous.data, event.data) then
            previous.syncedAtMs = receivedAtMs
            return false
        end
        local current: AlertState =
            { kind = "current", data = event.data, syncedAtMs = receivedAtMs }
        store.alerts = current
        return true
    end
    return false
end

return { new = new, apply = apply }
