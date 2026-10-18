--!nocheck

local env = runtime()
for raw, value in pairs(wsJsonValues) do
    env.jsonValues[raw] = value
end
local events = env.require("./alerts/events.luau")
local reducer = env.require("./alerts/realtime-store.luau")
local status = env.require("./alerts/status.luau")
local presentation = env.require("./ui/presentation.luau")
local catalog = env.require("./locations/catalog.luau")
local model = reducer.new()
local projections = {}
local emptyEvent

assert(status.project(model.alerts, "київська").kind == "unknown")
assert(status.project(model.alerts, "unsupported").kind == "unsupported")
for _, raw in ipairs(wsFixtures["session-1"]) do
    local event = assert(events.decode(raw))
    if event.type ~= "alerts" then
        reducer.apply(model, event, 1)
        assert(status.project(model.alerts, "київська").kind == "unknown")
    end
end

for index, case in ipairs(wsFixtures.projection) do
    local event = assert(events.decode(case.raw))
    reducer.apply(model, event, index)
    if case.name == "empty" then
        emptyEvent = event
    end
    for key, expected in pairs(case.expected) do
        local projection = status.project(model.alerts, key)
        if expected == "unknown" or expected == "unsupported" then
            assert(projection.kind == expected, case.name)
        else
            assert(projection.kind == "current", case.name)
            assert(projection.syncedAtMs == index and projection.updatedAt == event.data.updatedAt)
            if expected == "clear" then
                assert(projection.alert == nil, case.name)
            else
                local alert = assert(projection.alert, case.name)
                assert(alert.key == key, case.name)
                if expected == "missing" then
                    assert(alert.level == nil, case.name)
                else
                    assert(alert.level == expected, case.name)
                end
                local view = presentation.forState({
                    kind = "alert",
                    locationKey = key,
                    level = alert.level,
                })
                if expected == "missing" then
                    assert(view.detail == env.noctalia.tr("level.unknown"))
                    assert(view.color == "on_surface_variant" and view.glyph == "alert-triangle")
                end
            end
        end
        projections[case.name .. ":" .. key] = projection
    end
    -- Snapshot replacement invalidates both active and empty official baselines.
    reducer.apply(model, { type = "snapshot", ts = event.ts, data = { threats = {} } }, 100)
    local stale = status.project(model.alerts, "київська")
    if case.name ~= "unmapped-territory" then
        assert(stale.kind == "stale" and stale.syncedAtMs == index, case.name)
        local previous = projections[case.name .. ":київська"]
        assert((stale.alert == nil) == (previous.alert == nil), case.name)
        if stale.alert then
            assert(stale.alert.level == previous.alert.level)
        end
    else
        assert(stale.kind == "unknown")
    end
end

local combined = projections["city-and-raions:київська"].alert
local reordered = projections["raions-reordered:київська"].alert
assert(combined.since == "2026-10-17T10:00:00Z" and reordered.since == combined.since)
assert(table.concat(combined.reasons, ",") == "Дрони,Ракети")
assert(table.concat(reordered.reasons, ",") == table.concat(combined.reasons, ","))
assert(projections["missing-start:київська"].alert.since == nil)

reducer.apply(model, assert(emptyEvent), 200)
for _, location in ipairs(catalog.all) do
    local projection = status.project(model.alerts, location.key)
    assert(projection.kind == "current" and projection.alert == nil)
end
assert(#env.requests == 0 and env.streamAttempts == 0 and next(env.values) == nil)
print("PASS WS location projection, Kyiv separation, severity, freshness and empty baseline")
