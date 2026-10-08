--!strict
--!nolint FunctionUnused

local locations = require("./locations/catalog.luau")
local locationStore = require("./locations/store.luau")
local alertState = require("./alerts/state.luau")
local statusView = require("./ui/status-view.luau")
local panelNavigation = require("./panels/navigation.luau")

local selectedLocation: locations.Location? = nil
local currentState: alertState.AlertState? = nil
local isOpen = false
local function renderPanel(): ()
    if not isOpen then
        return
    end
    local location = selectedLocation
    local children: { UiNode } = {}
    if not location then
        return
    end
    local state = alertState.matchesLocation(currentState, location) and currentState or nil
    table.insert(
        children,
        ui.scroll({ flexGrow = 1 }, {
            statusView.renderStatusView(location, state),
        })
    )
    table.insert(
        children,
        ui.row({ gap = 4, align = "center" }, {
            ui.label({
                text = noctalia.tr("label.source"),
                fontSize = 12,
                color = "on_surface_variant",
            }),
            ui.button({
                text = "NEPTUN",
                glyph = "external-link",
                fontSize = 12,
                variant = "ghost",
                controlSize = "sm",
                onClick = "openSource",
            }),
        })
    )
    table.insert(
        children,
        ui.button({ text = noctalia.tr("location.change"), onClick = "showPicker" })
    )
    panel.render(ui.column({ flexGrow = 1, gap = 10 }, children))
end

function showPicker(): ()
    panelNavigation.requestPanel("location-picker")
end

function openSource(): ()
    noctalia.runAsync("xdg-open https://neptun.in.ua/")
end

function onOpen(): ()
    isOpen = true
    selectedLocation = locationStore.loadLocation()
    currentState = noctalia.state.get(alertState.stateKey)
    if not selectedLocation then
        showPicker()
        return
    end
    panel.setWantsSecondTicks(true)
    renderPanel()
end

function onClose(): ()
    isOpen = false
end

function update(): ()
    renderPanel()
end

local function handleStatusChanged(state: alertState.AlertState): ()
    currentState = state
    renderPanel()
end

local function handleLocationChanged(location: locations.Location?): ()
    selectedLocation = location
    renderPanel()
end

noctalia.state.watch(alertState.stateKey, handleStatusChanged)
noctalia.state.watch(locationStore.stateKey, handleLocationChanged)
