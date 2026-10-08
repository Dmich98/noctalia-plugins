--!strict
--!nolint FunctionUnused

local locations = require("./locations/catalog.luau")
local locationStore = require("./locations/store.luau")
local alertState = require("./alerts/state.luau")
local widgetView = require("./ui/widget-view.luau")
local navigation = require("./panels/navigation.luau")

local selectedLocation: locations.Location? = locationStore.loadLocation()
local currentState: alertState.AlertState? = noctalia.state.get(alertState.stateKey)
-- Keep the table alive: its identity distinguishes widgets, including on the same bar.
local owner = {}

function update(): ()
    noctalia.setUpdateInterval(30000)
    widgetView.render(selectedLocation, currentState)
end

noctalia.state.watch(locationStore.stateKey, function(location: locations.Location?): ()
    selectedLocation = location
    update()
end)

noctalia.state.watch(alertState.stateKey, function(state: alertState.AlertState): ()
    currentState = state
    update()
end)

noctalia.state.watch(navigation.stateKey, function(request: navigation.PanelRequest): ()
    if request.owner == tostring(owner) then
        noctalia.togglePanel(request.panelId)
    end
end)

function onClick(): ()
    noctalia.state.set(navigation.ownerKey, tostring(owner))
    local panelId = selectedLocation and "alert-details" or "location-picker"
    noctalia.togglePanel("dmich/air-alert:" .. panelId)
end

function onExit(): ()
    if noctalia.state.get(navigation.ownerKey) == tostring(owner) then
        noctalia.state.set(navigation.ownerKey, nil)
    end
end
