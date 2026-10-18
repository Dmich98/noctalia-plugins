--!nocheck

local env = runtime()
env.files["/data/config.json"] = "saved"
env.jsonValues.saved = { locationKey = "київська" }
local widget = runtime(env.shared)
local panelEnv = runtime(env.shared)
env.require("./service.luau")
widget.require("./widget.luau")
panelEnv.require("./status-panel-entry.luau")
env.update()
panelEnv.onOpen()
send(env, "yellow-metadata")
env.flush()
local live = env.values.alertStatus
assert(live.kind == "alert")
env.now = 45
env.update()
env.flush()
local stale = env.values.alertStatus
assert(stale.kind == "stale", "expiry must retain explicit last-known status")
assert(stale.lastKnown.kind == "alert" and stale.lastKnown.level == "yellow")
assert(stale.lastKnown.since == live.since and stale.lastKnown.reasons[1] == "Дрони")
assert(stale.updatedAt == live.updatedAt and stale.syncedAtMs == 0)
assert(widget.text == "Дані застаріли" and widget.glyphColor == "on_surface_variant")
assert(
    tooltipValue(widget.tooltip, "Останній підтверджений стан")
        == "Повітряна тривога"
)
assert(tooltipValue(widget.tooltip, "Рівень") == "Жовтий рівень")
assert(findNode(panelEnv.tree, function(node)
    return node.kind == "label" and node.props.text == "Жовтий рівень"
end))
assert(not findNode(panelEnv.tree, function(node)
    return node.kind == "label" and node.props.text == "Триває"
end), "a stale alert must not imply an ongoing confirmed duration")
assert(#env.notifications == 0)
local unchanged = env.values.alertStatus
env.now = 60
env.update()
assert(env.values.alertStatus == unchanged and env.streamAttempts == 1)
send(env, "snapshot-empty")
env.flush()
assert(env.values.alertStatus.kind == "stale")
send(env, "yellow-metadata")
env.flush()
assert(env.values.alertStatus.kind == "alert" and #env.notifications == 0)
send(env, "empty")
env.flush()
assert(#env.notifications == 1)
send(env, "snapshot-empty")
env.flush()
assert(env.values.alertStatus.kind == "stale" and env.values.alertStatus.lastKnown.kind == "clear")
widget.config.color_mode = "colored"
widget.update()
assert(widget.color == "on_surface_variant" and widget.glyphColor == "on_surface_variant")
assert(
    env.require("./locations/store.luau")
        .save(env.require("./locations/catalog.luau").find("м. київ"))
)
env.flush()
assert(
    env.values.alertStatus.locationKey == "м. київ" and env.values.alertStatus.kind == "stale"
)
assert(env.values.alertStatus.lastKnown.kind == "clear" and #env.notifications == 1)
send(env, "city-only")
env.flush()
assert(env.values.alertStatus.kind == "alert" and #env.notifications == 1)
assert(env.streamAttempts == 1)
print("PASS visible stale alert/clear details, region changes and unchanged reconnect recovery")

local initial = runtime()
initial.files["/data/config.json"] = "saved"
initial.jsonValues.saved = { locationKey = "київська" }
initial.require("./service.luau")
initial.update()
local heartbeat
for _, raw in ipairs(wsFixtures["session-1"]) do
    for key, value in pairs(wsJsonValues) do
        initial.jsonValues[key] = value
    end
    local event = assert(initial.require("./alerts/events.luau").decode(raw))
    if event.type == "heartbeat" then
        heartbeat = raw
        break
    end
end
send(initial, "snapshot-empty")
for _, now in ipairs({ 15, 30, 44 }) do
    initial.now = now
    initial.streams[1].onLine(heartbeat)
    initial.update()
    assert(initial.values.alertStatus.kind == "loading")
end
initial.now = 45
initial.update()
assert(
    initial.values.alertStatus.kind == "error",
    "heartbeats cannot hide a missing official baseline"
)
for _ = 1, 100 do
    initial.now += 1
    initial.update()
end
assert(initial.streamAttempts == 1, "a dead supervisor must never trigger a second stream")
send(initial, "snapshot-empty")
assert(initial.values.alertStatus.kind == "loading")
send(initial, "empty")
assert(initial.values.alertStatus.kind == "clear" and #initial.notifications == 0)
print("PASS independent initial synchronization deadline and permanently silent stream")

local active = runtime()
active.files["/data/config.json"] = "saved"
active.jsonValues.saved = { locationKey = "київська" }
active.require("./service.luau")
active.update()
send(active, "red")
for _, now in ipairs({ 15, 30, 45, 60 }) do
    active.now = now
    active.streams[1].onLine(heartbeat)
    active.update()
    assert(
        active.values.alertStatus.kind == "alert",
        "live heartbeats preserve a synchronized baseline"
    )
end
assert(#active.notifications == 0 and active.streamAttempts == 1)
active.now = 105
active.update()
assert(active.values.alertStatus.kind == "stale")
send(active, "malformed-json")
assert(
    active.values.alertStatus.kind == "stale" and active.values.alertStatus.lastKnown.level == "red"
)
print("PASS regular heartbeat liveness and malformed-message isolation while stale")
