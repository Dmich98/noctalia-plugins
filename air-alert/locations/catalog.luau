--!strict

export type Location = {
    locationKey: string,
    locationName: string,
    locationType: "oblast" | "raion",
    oblast: string?,
}

local function loadLocations(): ({ Location }, string?)
    local raw, readError = noctalia.readFile("locations/catalog.json")
    if not raw then
        return {}, readError
    end
    local data, decodeError = noctalia.json.decode(raw)
    if not data then
        return {}, decodeError
    end
    return data :: { Location }, nil
end

local function displayName(location: Location): string
    local key = "locations." .. location.locationKey
    local name = noctalia.tr(key)
    return name ~= key and name or location.locationName
end

return { loadLocations = loadLocations, displayName = displayName }
