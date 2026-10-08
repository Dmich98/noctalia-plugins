--!strict
--!nolint FunctionUnused

local alerts = require("./alerts/status.luau")
local alertsApi = require("./alerts/api.luau")
local alertTooltip = require("./ui/alert-tooltip.luau")
local locations = require("./locations/catalog.luau")
local locationStore = require("./locations/store.luau")
local alertState = require("./alerts/state.luau")
local alertDisplay = require("./ui/alert-display.luau")
local panelNavigation = require("./panels/navigation.luau")

local selectedLocation: locations.Location? = locationStore.loadLocation()

local previousState: alertState.AlertState? = noctalia.state.get(alertState.stateKey)
local lastSuccessAt: number? = alertState.matchesLocation(previousState, selectedLocation)
        and previousState
        and previousState.lastSuccessAt
    or nil
local pendingLocation: locations.Location? = nil

local function render(
    text: string,
    glyph: string,
    tooltip: (string | { alertTooltip.TooltipRow })?
): ()
    local location = selectedLocation
    barWidget.setText(location and (locations.displayName(location) .. " · " .. text) or text)
    barWidget.setGlyph(glyph)
    barWidget.setTooltip(tooltip)
end

local function renderNoLocationSelected(): ()
    render(noctalia.tr("location.choose"), "map-pin", noctalia.tr("location.choose"))
end

local function renderSelectedLocation(data: alerts.AlertsResponse, location: locations.Location): ()
    local alert = alerts.resolveLocationAlert(data, location)
    lastSuccessAt = os.time()
    local state: alertState.AlertState = {
        location = location,
        active = alert ~= nil,
        since = alert and alert.since,
        level = alert and alert.level,
        reasons = alert and alert.reasons,
        oblast = alert and alert.oblast,
        lastSuccessAt = lastSuccessAt,
        loading = false,
    }
    noctalia.state.set(alertState.stateKey, state)
    local appearance = alertDisplay.statusAppearance(alert ~= nil, alert and alert.level)
    render(
        alert
                and noctalia.tr(
                    "widget.alert",
                    { level = alertDisplay.formatAlertLevel(alert.level) } :: { [string]: string | number | boolean }
                )
            or noctalia.tr("widget.safe"),
        appearance.glyph,
        alertTooltip.formatAlertTooltip(locations.displayName(location), alert)
    )
end

local function renderError(location: locations.Location, message: string, glyph: string): ()
    local state: alertState.AlertState = {
        location = location,
        lastSuccessAt = lastSuccessAt,
        error = message,
        loading = false,
    }
    noctalia.state.set(alertState.stateKey, state)
    render(
        noctalia.tr("status.unavailable"),
        glyph,
        locations.displayName(location) .. "\n" .. message
    )
end

local function handleAlertsResponse(response: HttpResponse, location: locations.Location): ()
    -- Ignore responses requested before the user changed the location.
    if location ~= selectedLocation then
        return
    end
    if not response.ok or response.status ~= 200 then
        renderError(location, noctalia.tr("error.fetch"), "wifi-off")
        return
    end

    local data, err = alerts.parseAlertsResponse(response.body)

    if not data or err then
        renderError(location, noctalia.tr("error.decode"), "alert-circle")
        return
    end

    renderSelectedLocation(data, location)
end

local initialized: boolean = false

function update(): ()
    noctalia.setUpdateInterval(30000)
    local location = selectedLocation
    if not location then
        noctalia.state.set(alertState.stateKey, { loading = false })
        renderNoLocationSelected()
        return
    end

    if not initialized then
        initialized = true
        noctalia.state.set(
            alertState.stateKey,
            { location = location, loading = true, lastSuccessAt = lastSuccessAt }
        )
        render(
            noctalia.tr("status.loading"),
            "loader",
            locations.displayName(location) .. "\n" .. noctalia.tr("status.loading_details")
        )
    end

    if pendingLocation == location then
        return
    end
    pendingLocation = location
    local accepted = alertsApi.fetchAlerts(function(response: HttpResponse)
        if pendingLocation ~= location then
            return
        end
        pendingLocation = nil
        handleAlertsResponse(response, location)
    end)
    if not accepted then
        pendingLocation = nil
        renderError(location, noctalia.tr("error.request"), "wifi-off")
    end
end

local function handleLocationChanged(location: locations.Location?): ()
    selectedLocation = location
    lastSuccessAt = nil
    initialized = false
    update()
end

noctalia.state.watch(locationStore.stateKey, handleLocationChanged)

-- Opening from the widget preserves its bar anchor when switching panels.
noctalia.state.watch(panelNavigation.stateKey, function(panelId: string): ()
    noctalia.togglePanel(panelId)
end)

function onClick(): ()
    local panelId = selectedLocation and "alert-details" or "location-picker"
    noctalia.togglePanel("dmich/air-alert:" .. panelId)
end
