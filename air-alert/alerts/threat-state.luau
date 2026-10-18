--!strict

local events = require("./events.luau")

export type State =
    { kind: "unconfigured" }
    | { kind: "loading", locationKey: string }
    | { kind: "unavailable", locationKey: string }
    | { kind: "current", locationKey: string, threats: { events.Threat } }

local function forLocation(state: State?, locationKey: string): State
    if not state or state.kind == "unconfigured" or state.locationKey ~= locationKey then
        return { kind = "loading", locationKey = locationKey }
    end
    return state
end

return { key = "currentThreats", forLocation = forLocation }
