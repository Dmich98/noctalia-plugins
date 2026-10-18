--!nocheck

local env = runtime()
for raw, value in pairs(wsJsonValues) do
    env.jsonValues[raw] = value
end
local events = env.require("./alerts/events.luau")
local reducer = env.require("./alerts/realtime-store.luau")
local cases = {}
for _, case in ipairs(wsFixtures.cases) do
    cases[case.name] = case
    local event, err = events.decode(case.raw)
    if case.expected == "accept" then
        assert(event and not err, case.name)
    elseif case.expected == "reject" then
        assert(not event and err, case.name)
    else
        assert(not event and not err, case.name)
    end
end

local function decoded(name)
    return assert(events.decode(assert(cases[name]).raw))
end

assert(decoded("missing-alert-metadata").data.oblasts[1].level == nil)
assert(decoded("unknown-alert-level").data.oblasts[1].level == "purple")
assert(decoded("upsert-same").data.advisory == false)
assert(decoded("upsert-same").data.areaOnly == false)
assert(decoded("upsert-changed").data.type == "future-threat")
assert(decoded("invalid-optional-times").data.updatedAt == nil)
assert(decoded("invalid-optional-times").data.oblasts[1].since == nil)
assert(decoded("invalid-threat-time").data.updatedAt == nil)
assert(decoded("alerts-two").data.raions[1].oblastKey == "київська")
local escaped = decoded("escaped-brackets").data.oblasts[1].reasons
assert(table.find(escaped, '[x] "quoted" \\ end'))
assert(table.find(escaped, '\\"[]'))
assert(table.find(escaped, "line\nnext"))
local immutable = decoded("alerts-two")
assert(not pcall(function()
    immutable.data.oblasts[1].level = "red"
end))
assert(not pcall(function()
    immutable.data.oblasts[2].reasons[1] = "changed"
end))

local heartbeatRaw
for _, raw in ipairs(wsFixtures["session-1"]) do
    local event = assert(events.decode(raw))
    if event.type == "heartbeat" then
        heartbeatRaw = raw
        break
    end
end
local heartbeat = assert(events.decode(heartbeatRaw))
local limitRaw = heartbeatRaw .. string.rep(" ", 61440 - #heartbeatRaw)
env.jsonValues[limitRaw] = env.jsonValues[heartbeatRaw]
assert(events.decode(limitRaw))
local originalDecode = env.noctalia.json.decode
env.noctalia.json.decode = function()
    error("oversized input must not reach the host decoder")
end
local oversized, oversizedError = events.decode(limitRaw .. " ")
assert(not oversized and oversizedError == "oversized")
local deep = '{"type":"heartbeat","extra":'
    .. string.rep("[", 65)
    .. "0"
    .. string.rep("]", 65)
    .. "}"
local nested, nestedError = events.decode(deep)
assert(not nested and nestedError == "json", "bound recursive host conversion before decoding")
env.noctalia.json.decode = originalDecode
print("PASS WS decoder fixtures, array identity, optional fields and message limit")

local model = reducer.new()
assert(model.alerts.kind == "unknown" and model.lastMessageAtMs == nil)
assert(not reducer.apply(model, heartbeat, 1))
assert(model.alerts.kind == "unknown" and model.lastMessageAtMs == 1)
assert(reducer.apply(model, decoded("snapshot-one"), 2))
assert(model.session == 1 and model.alerts.kind == "unknown")
local originalThreat = model.threats.a
assert(not reducer.apply(model, decoded("upsert-same"), 3))
assert(model.threats.a == originalThreat)
assert(not reducer.apply(model, decoded("remove-unknown"), 4))
assert(reducer.apply(model, decoded("upsert-changed"), 5))
assert(model.threats.a.advisory == true)
assert(reducer.apply(model, decoded("remove-a"), 6))
assert(not reducer.apply(model, decoded("remove-a"), 7))
assert(next(model.threats) == nil and model.alerts.kind == "unknown")

assert(reducer.apply(model, decoded("alerts-two"), 8))
assert(model.alerts.kind == "current" and model.alerts.syncedAtMs == 8)
local official = model.alerts.data
assert(not reducer.apply(model, decoded("alerts-reordered"), 9))
assert(model.alerts.data == official and model.alerts.syncedAtMs == 9)
assert(not reducer.apply(model, heartbeat, 10))
assert(model.alerts.data == official and model.alerts.syncedAtMs == 9)
assert(reducer.apply(model, decoded("snapshot-empty"), 11))
assert(model.session == 2 and next(model.threats) == nil)
assert(model.alerts.kind == "stale" and model.alerts.data == official)
assert(model.alerts.syncedAtMs == 9)
assert(not reducer.apply(model, heartbeat, 12))
assert(model.alerts.kind == "stale")
assert(reducer.apply(model, decoded("alerts-reordered"), 13))
assert(model.alerts.kind == "current" and model.alerts.syncedAtMs == 13)

-- An identical snapshot can be a new connection with cached data: never deduplicate it.
assert(reducer.apply(model, decoded("snapshot-empty"), 14))
assert(model.session == 3 and model.alerts.kind == "stale")
assert(reducer.apply(model, decoded("alerts-replacement"), 15))
assert(#model.alerts.data.raions == 0 and #model.alerts.data.oblasts == 1)
assert(model.alerts.data.oblasts[1].key == "київська")
assert(#official.raions == 1 and #official.oblasts == 2, "old data must remain unchanged")
assert(reducer.apply(model, decoded("empty-alerts"), 16))
assert(model.alerts.kind == "current" and #model.alerts.data.oblasts == 0)
assert(not reducer.apply(model, decoded("empty-alerts"), 17))
print("PASS WS store separation, replacement, duplicates and reconnect freshness")

local before = model.alerts
local activityBefore = model.lastMessageAtMs
for _, case in ipairs(wsFixtures.cases) do
    if case.expected ~= "accept" then
        local event = events.decode(case.raw)
        if event then
            reducer.apply(model, event, 1000)
        end
        assert(model.alerts == before and model.lastMessageAtMs == activityBefore, case.name)
    end
end

local function equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not equal(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local first, second = reducer.new(), reducer.new()
local receipt = 0
for session = 1, 2 do
    for _, raw in ipairs(wsFixtures["session-" .. session]) do
        local event = assert(events.decode(raw))
        receipt += 1
        local changed = reducer.apply(first, event, receipt)
        assert(reducer.apply(second, assert(events.decode(raw)), receipt) == changed)
        assert(equal(first, second))
        assert(first.lastMessageAtMs == receipt and first.lastMessageTs == event.ts)
        if event.type == "snapshot" then
            assert(first.alerts.kind == (session == 1 and "unknown" or "stale"))
        elseif event.type == "alerts" then
            assert(first.alerts.kind == "current")
            assert(#first.alerts.data.raions == 69 and #first.alerts.data.oblasts == 4)
        end
    end
end
assert(first.session == 2)
assert(#env.requests == 0 and env.streamAttempts == 0 and next(env.values) == nil)
print("PASS deterministic WS fixture replay and invalid-event isolation")
