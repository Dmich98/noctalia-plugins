--!strict
--!nolint FunctionUnused

local alertState = require("./alerts/state.luau")
local catalog = require("./locations/catalog.luau")
local store = require("./locations/store.luau")
local navigation = require("./panels/navigation.luau")
local view = require("./ui/widget-view.luau")

local selected = store.load()
local current: alertState.State? = noctalia.state.get(alertState.key)
-- Identity is unique per widget instance, including widgets on the same bar.
local owner = {}

function update(): ()
    view.render(selected, current)
end

noctalia.state.watch(store.stateKey, function(key: string?): ()
    selected = catalog.find(key)
    current = nil
    update()
end)

noctalia.state.watch(alertState.key, function(state: alertState.State): ()
    current = state
    update()
end)

noctalia.state.watch(navigation.stateKey, function(request: navigation.Request): ()
    if request.owner == tostring(owner) then
        noctalia.togglePanel(request.panelId)
    end
end)

local function openPanel(panelId: string): ()
    noctalia.state.set(navigation.ownerKey, tostring(owner))
    noctalia.togglePanel("dmich/air-alert:" .. panelId)
end

function onClick(): ()
    openPanel(selected and "alert-details" or "location-picker")
end

function onRightClick(): ()
    openPanel("location-picker")
end

function onExit(): ()
    if noctalia.state.get(navigation.ownerKey) == tostring(owner) then
        noctalia.state.set(navigation.ownerKey, nil)
    end
end
