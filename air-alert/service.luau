--!strict
--!nolint FunctionUnused

local api = require("./alerts/api.luau")
local status = require("./alerts/status.luau")
local alertState = require("./alerts/state.luau")
local catalog = require("./locations/catalog.luau")
local store = require("./locations/store.luau")
local notification = require("./notification.luau")

local selected = store.load()
local needsInitialLoading = true
local lastKnownActive: boolean? = nil
local clearHighlightUntilMs: number? = nil
local nextRequestId = 0
local pending: number? = nil
local pendingSince: number? = nil
local REQUEST_TIMEOUT_SECONDS = 90
local CLEAR_HIGHLIGHT_MS = 15000

local function publish(state: alertState.State): ()
    noctalia.state.set(alertState.key, state)
end

local function refresh(): ()
    local location = selected
    if not location then
        publish({ kind = "unconfigured" })
        return
    end
    if pending then
        -- A request that never calls back must not block later updates forever.
        if pendingSince and os.time() - pendingSince >= REQUEST_TIMEOUT_SECONDS then
            pending = nil
            pendingSince = nil
            publish({ kind = "error", locationKey = location.key, code = "timeout" })
        end
        return
    end

    nextRequestId += 1
    local requestId = nextRequestId
    pending = requestId
    pendingSince = os.time()
    if needsInitialLoading then
        publish({ kind = "loading", locationKey = location.key })
        needsInitialLoading = false
    end
    local accepted = api.fetch(function(data: api.Response?, errorCode: api.ErrorCode?): ()
        if pending ~= requestId then
            return
        end
        pending = nil
        pendingSince = nil
        if not data then
            local code: alertState.ErrorCode = errorCode or "invalid"
            publish({
                kind = "error",
                locationKey = location.key,
                code = code,
            })
            return
        end
        local alert = status.forLocation(data, location.key)
        local active = alert ~= nil
        local nextState: alertState.State
        if alert then
            clearHighlightUntilMs = nil
            nextState = {
                kind = "alert",
                locationKey = location.key,
                level = alert.level,
                updatedAt = data.updatedAt,
                since = alert.since,
                reasons = alert.reasons,
            }
        else
            if lastKnownActive == true then
                clearHighlightUntilMs = noctalia.nowMs() + CLEAR_HIGHLIGHT_MS
            end
            nextState = {
                kind = "clear",
                locationKey = location.key,
                updatedAt = data.updatedAt,
                highlightUntilMs = clearHighlightUntilMs,
            }
        end
        publish(nextState)
        if lastKnownActive ~= nil and lastKnownActive ~= active then
            notification.send(catalog.displayName(location), nextState)
        end
        lastKnownActive = active
    end)
    if not accepted then
        pending = nil
        pendingSince = nil
        publish({ kind = "error", locationKey = location.key, code = "request" })
    end
end

function update(): ()
    noctalia.setUpdateInterval(30000)
    refresh()
end

noctalia.state.watch(store.stateKey, function(key: string?): ()
    pending = nil
    pendingSince = nil
    selected = catalog.find(key)
    needsInitialLoading = true
    lastKnownActive = nil
    clearHighlightUntilMs = nil
    refresh()
end)
