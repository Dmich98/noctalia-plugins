--!strict
--!nolint FunctionUnused

local alertsApi = require("./alerts/api.luau")
local alerts = require("./alerts/status.luau")
local alertState = require("./alerts/state.luau")
local locations = require("./locations/catalog.luau")
local locationStore = require("./locations/store.luau")

local selectedLocation: locations.Location? = locationStore.loadLocation()
local previousState: alertState.AlertState? = noctalia.state.get(alertState.stateKey)
local lastSuccessAt = alertState.matchesLocation(previousState, selectedLocation)
        and previousState
        and previousState.lastSuccessAt
    or nil
local initialized = false
local generation = 0
local pendingRequest: number? = nil

local function publishError(location: locations.Location, kind: alertsApi.ErrorKind): ()
    noctalia.state.set(alertState.stateKey, {
        location = location,
        lastSuccessAt = lastSuccessAt,
        error = noctalia.tr("error." .. kind),
        errorKind = kind,
        loading = false,
    })
end

function update(): ()
    noctalia.setUpdateInterval(30000)
    local location = selectedLocation
    if not location then
        noctalia.state.set(alertState.stateKey, { loading = false })
        return
    end
    if not initialized then
        initialized = true
        noctalia.state.set(alertState.stateKey, {
            location = location,
            loading = true,
            lastSuccessAt = lastSuccessAt,
        })
    end
    if pendingRequest then
        return
    end
    generation += 1
    local requestId = generation
    pendingRequest = requestId
    local accepted = alertsApi.fetchAlerts(
        function(data: alertsApi.AlertsResponse?, kind: alertsApi.ErrorKind?): ()
            -- A location change invalidates the old request, even after switching back.
            if pendingRequest ~= requestId then
                return
            end
            pendingRequest = nil
            if not data then
                publishError(location, kind or "decode")
                return
            end
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
        end
    )
    if not accepted then
        pendingRequest = nil
        publishError(location, "request")
    end
end

noctalia.state.watch(locationStore.stateKey, function(location: locations.Location?): ()
    selectedLocation = location
    pendingRequest = nil
    lastSuccessAt = nil
    initialized = false
    update()
end)
