--!strict

local locations = require("./catalog.luau")
local stateKey = "selectedLocation"

local function configPath(): (string?, string?)
    local directory, err = noctalia.pluginDataDir()
    if not directory then
        return nil, err
    end
    return directory .. "/config.json", nil
end

local function loadLocation(): locations.Location?
    local path, pathError = configPath()
    if not path then
        noctalia.log(pathError or "Cannot open plugin data directory")
        return nil
    end
    if not noctalia.fileExists(path) then
        return nil
    end
    local raw, readError = noctalia.readFile(path)
    if not raw then
        noctalia.log(readError or "Cannot read selected location")
        return nil
    end
    local data, err = noctalia.json.decode(raw)
    if typeof(data) ~= "table" or err then
        noctalia.log(err or "Invalid location config")
        return nil
    end
    if
        typeof(data.locationKey) ~= "string"
        or data.locationKey == ""
        or typeof(data.locationName) ~= "string"
        or (data.locationType ~= "oblast" and data.locationType ~= "raion")
    then
        noctalia.log("Invalid saved location")
        return nil
    end
    return data :: locations.Location
end

local function saveLocation(location: locations.Location): (boolean, string?)
    local path, pathError = configPath()
    if not path then
        return false, pathError
    end
    local raw, encodeError = noctalia.json.encode(location)
    if not raw then
        return false, encodeError
    end
    local temporaryPath = path .. ".tmp"
    local saved, writeError = noctalia.writeFile(temporaryPath, raw)
    if not saved then
        noctalia.removeFile(temporaryPath)
        return false, writeError
    end
    local renamed, renameError = noctalia.renameFile(temporaryPath, path)
    if not renamed then
        noctalia.removeFile(temporaryPath)
        return false, renameError
    end
    noctalia.state.set(stateKey, location)
    return true, nil
end

return { stateKey = stateKey, loadLocation = loadLocation, saveLocation = saveLocation }
