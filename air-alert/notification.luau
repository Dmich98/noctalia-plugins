--!strict

local alertState = require("./alerts/state.luau")
local presentation = require("./ui/presentation.luau")
local displayTime = require("./ui/time.luau")

local events = require("./alerts/events.luau")
local threats = require("./alerts/threats.luau")
local threatPresentation = require("./ui/threat-presentation.luau")

local function deliver(summary: string, body: string, urgency: string): ()
    local payload, err = noctalia.json.encode({
        app_name = "Air Alert",
        summary = summary,
        body = body,
        urgency = urgency,
        icon = presentation.widgetGlyph,
        timeout_ms = urgency == "critical" and 15000 or 5000,
    })
    if not payload then
        noctalia.log("Could not encode alert notification: " .. (err or "unknown error"))
        return
    end
    local accepted = noctalia.runAsync(
        { "noctalia", "msg", "notification-show", payload },
        function(result)
            if result.exitCode ~= 0 then
                noctalia.log("Could not deliver alert notification: " .. result.stderr)
            end
        end
    )
    if not accepted then
        noctalia.log("Could not launch alert notification")
    end
end

local function send(locationName: string, state: alertState.State): ()
    local body = noctalia.tr("status.safe")
    local urgency = "normal"
    if state.kind == "alert" then
        local view = presentation.forState(state)
        body = noctalia.tr("status.alert") .. " · " .. view.detail
        if state.reasons and #state.reasons > 0 then
            body ..= "\n" .. noctalia.tr("label.reasons") .. ": " .. table.concat(state.reasons, ", ")
        end
        local since = displayTime.formatKyivTimestamp(state.since)
        if since then
            body ..= "\n" .. noctalia.tr("label.since") .. ": " .. since
        end
        if state.level == "yellow" or state.level == "red" then
            urgency = "critical"
        end
    end
    deliver(locationName, body, urgency)
end

local function sendThreat(threat: events.Threat, change: threats.Change): ()
    if
        noctalia.getConfig("threat_notifications") == "new_only"
        and change ~= "new"
        and change ~= "entered"
    then
        return
    end
    local summary, body, urgency = threatPresentation.forThreat(threat, change)
    deliver(summary, body, urgency)
end

return { send = send, sendThreat = sendThreat }
