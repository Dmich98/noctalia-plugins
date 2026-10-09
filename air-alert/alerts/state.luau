--!strict

export type ErrorCode = "network" | "invalid" | "request" | "timeout"
-- clear.highlightUntilMs is a local presentation deadline, not NEPTUN's alert end time.
export type State =
    { kind: "unconfigured" }
    | { kind: "loading", locationKey: string }
    | { kind: "clear", locationKey: string, updatedAt: string?, highlightUntilMs: number? }
    | {
        kind: "alert",
        locationKey: string,
        level: string,
        updatedAt: string?,
        since: string?,
        reasons: { string }?,
    }
    | { kind: "error", locationKey: string, code: ErrorCode }

local function forLocation(state: State?, locationKey: string?): State
    if not locationKey then
        return { kind = "unconfigured" }
    end
    if not state or state.kind == "unconfigured" or state.locationKey ~= locationKey then
        return { kind = "loading", locationKey = locationKey }
    end
    return state
end

return { key = "alertStatus", forLocation = forLocation }
