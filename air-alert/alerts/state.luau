--!strict

local locations = require("../locations/catalog.luau")

export type AlertState = {
    location: locations.Location?,
    active: boolean?,
    since: string?,
    level: string?,
    reasons: { string }?,
    oblast: string?,
    lastSuccessAt: number?,
    error: string?,
    loading: boolean,
}

local function matchesLocation(state: AlertState?, location: locations.Location?): boolean
    local previous = state and state.location
    return previous ~= nil
        and location ~= nil
        and previous.locationKey == location.locationKey
        and previous.locationType == location.locationType
end

return { stateKey = "alertStatus", matchesLocation = matchesLocation }
