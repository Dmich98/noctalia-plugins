--!strict
--!nolint FunctionUnused

local transport = require("./alerts/transport.luau")
local events = require("./alerts/events.luau")
local realtime = require("./alerts/realtime-store.luau")
local status = require("./alerts/status.luau")
local alertState = require("./alerts/state.luau")
local catalog = require("./locations/catalog.luau")
local store = require("./locations/store.luau")
local notification = require("./notification.luau")
local threats = require("./alerts/threats.luau")
local threatState = require("./alerts/threat-state.luau")

local selected = store.load()
local model = realtime.new()
local startResult: transport.StartResult? = nil
local startedAtMs: number? = nil
local awaitingBaselineAtMs: number? = nil
local lastKnownActive: boolean? = nil
local clearHighlightUntilMs: number? = nil
local freshnessExpired = false
local threatBaselineReady = false
local publishedThreats: threatState.State? = nil
local CLEAR_HIGHLIGHT_MS = 15000
-- Observed heartbeats are 15 seconds apart; allow three missed intervals.
local STREAM_SILENCE_MS = 45000
local BASELINE_TIMEOUT_MS = 45000

local function renderThreats(): ()
    local location = selected
    local nextState: threatState.State
    if not location then
        nextState = { kind = "unconfigured" }
    elseif startResult == "missing_dependency" or startResult == "launch_failed" then
        nextState = { kind = "unavailable", locationKey = location.key }
    elseif not threatBaselineReady then
        if model.session == 0 and not freshnessExpired then
            nextState = { kind = "loading", locationKey = location.key }
        else
            nextState = { kind = "unavailable", locationKey = location.key }
        end
    else
        nextState = {
            kind = "current",
            locationKey = location.key,
            threats = threats.forLocation(model.threats, location, noctalia.nowMs()),
        }
    end
    local previous = publishedThreats
    if previous and previous.kind == nextState.kind then
        if previous.kind == "unconfigured" and nextState.kind == "unconfigured" then
            return
        elseif
            previous.kind ~= "unconfigured"
            and previous.locationKey == nextState.locationKey
        then
            if previous.kind == "current" and nextState.kind == "current" then
                local same = #previous.threats == #nextState.threats
                for index, threat in ipairs(nextState.threats) do
                    same = same and previous.threats[index] == threat
                end
                if same then
                    return
                end
            else
                return
            end
        end
    end
    publishedThreats = nextState
    noctalia.state.set(threatState.key, nextState)
end

local function publish(state: alertState.State): ()
    noctalia.state.set(alertState.key, state)
end

local function renderStatus(): ()
    local location = selected
    if not location then
        publish({ kind = "unconfigured" })
        return
    end
    local code: alertState.ErrorCode? = nil
    if startResult == "missing_dependency" then
        code = "dependency"
    elseif startResult == "launch_failed" then
        code = "stream"
    end
    if code then
        publish({ kind = "error", locationKey = location.key, code = code })
        return
    end
    local projection = status.project(model.alerts, location.key)
    if projection.kind == "unsupported" then
        publish({ kind = "unconfigured" })
        return
    elseif projection.kind == "unknown" then
        if freshnessExpired then
            publish({ kind = "error", locationKey = location.key, code = "network" })
        elseif model.alerts.kind == "current" then
            publish({ kind = "error", locationKey = location.key, code = "invalid" })
        else
            publish({ kind = "loading", locationKey = location.key })
        end
        return
    elseif projection.kind == "stale" then
        local lastKnown: alertState.LastKnown = { kind = "clear" }
        local alert = projection.alert
        if alert then
            lastKnown = {
                kind = "alert",
                level = alert.level,
                since = alert.since,
                reasons = alert.reasons,
            }
        end
        publish({
            kind = "stale",
            locationKey = location.key,
            lastKnown = lastKnown,
            updatedAt = projection.updatedAt,
            syncedAtMs = projection.syncedAtMs,
        })
        return
    end

    local alert = projection.alert
    local active = alert ~= nil
    local nextState: alertState.State
    if alert then
        clearHighlightUntilMs = nil
        nextState = {
            kind = "alert",
            locationKey = location.key,
            level = alert.level,
            updatedAt = projection.updatedAt,
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
            updatedAt = projection.updatedAt,
            highlightUntilMs = clearHighlightUntilMs,
        }
    end
    publish(nextState)
    if lastKnownActive ~= nil and lastKnownActive ~= active then
        notification.send(catalog.displayName(location), nextState)
    end
    lastKnownActive = active
end

local function expireIfNeeded(nowMs: number): boolean
    local lastActivity = model.lastMessageAtMs or startedAtMs
    if startResult ~= "started" or not lastActivity then
        return false
    end
    local silent = nowMs - lastActivity >= STREAM_SILENCE_MS
    if silent then
        threatBaselineReady = false
    end
    if freshnessExpired then
        return false
    end
    local syncExpired = awaitingBaselineAtMs ~= nil
        and nowMs - awaitingBaselineAtMs >= BASELINE_TIMEOUT_MS
    if not silent and not syncExpired then
        return false
    end
    freshnessExpired = true
    local previous = model.alerts
    if previous.kind == "current" then
        model.alerts = { kind = "stale", data = previous.data, syncedAtMs = previous.syncedAtMs }
    end
    return true
end

local function onLine(raw: string, receivedAtMs: number): ()
    local event, err = events.decode(raw)
    if not event then
        if err then
            noctalia.log("Ignored invalid NEPTUN stream message: " .. err)
        end
        return
    end
    local expired = expireIfNeeded(receivedAtMs)
    local previousThreat: events.Threat? = nil
    if event.type == "upsert" or event.type == "remove" then
        previousThreat = model.threats[event.data.id]
    end
    local changed = realtime.apply(model, event, receivedAtMs)
    -- Heartbeats and tracks cannot restore an expired official-alert baseline.
    if event.type == "alerts" then
        freshnessExpired = false
        awaitingBaselineAtMs = nil
    elseif event.type == "snapshot" then
        freshnessExpired = false
        awaitingBaselineAtMs = receivedAtMs
        threatBaselineReady = true
    elseif event.type == "upsert" or event.type == "remove" then
        local location = selected
        if threatBaselineReady and location then
            local current = model.threats[event.data.id]
            local change: threats.Change? = threats.classify(previousThreat, current, location, receivedAtMs)
            local details = current or previousThreat
            if change and details then
                notification.sendThreat(details, change)
            end
        end
    end
    if expired or (changed and (event.type == "alerts" or event.type == "snapshot")) then
        renderStatus()
    end
    renderThreats()
end

local function ensureStarted(): ()
    if not selected or startResult then
        return
    end
    startedAtMs = noctalia.nowMs()
    awaitingBaselineAtMs = startedAtMs
    startResult = transport.start(onLine)
    if startResult ~= "started" then
        renderStatus()
    end
end

function update(): ()
    -- Local liveness checks only: no polling or subprocess retries here.
    noctalia.setUpdateInterval(1000)
    if not startResult then
        renderStatus()
        ensureStarted()
    end
    if expireIfNeeded(noctalia.nowMs()) then
        renderStatus()
    end
    renderThreats()
end

noctalia.state.watch(store.stateKey, function(key: string?): ()
    selected = catalog.find(key)
    lastKnownActive = nil
    clearHighlightUntilMs = nil
    expireIfNeeded(noctalia.nowMs())
    renderStatus()
    ensureStarted()
    renderThreats()
end)
