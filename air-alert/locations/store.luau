--!strict

local catalog = require("./catalog.luau")
local stateKey = "selectedLocation"

local function configPath(): (string?, string?)
    local directory, err = noctalia.pluginDataDir()
    if not directory then
        return nil, err
    end
    return directory .. "/config.json", nil
end

local function load(): catalog.Location?
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
    local data, decodeError = noctalia.json.decode(raw)
    if typeof(data) ~= "table" or decodeError then
        noctalia.log(decodeError or "Invalid location config")
        return nil
    end
    if typeof(data.locationKey) ~= "string" then
        noctalia.log("Invalid saved location key")
        return nil
    end
    local location = catalog.find(data.locationKey)
    if not location then
        noctalia.log("Unsupported saved location key")
    end
    return location
end

local function save(location: catalog.Location): (boolean, string?)
    local supported = catalog.find(location.key)
    if not supported then
        return false, "Unsupported location"
    end
    local path, pathError = configPath()
    if not path then
        return false, pathError
    end
    -- Keep the previous config.json format readable after this rewrite.
    local raw, encodeError = noctalia.json.encode({
        locationKey = supported.key,
        locationName = supported.name,
        locationType = "oblast",
    })
    if not raw then
        return false, encodeError
    end
    local temporaryPath = path .. ".tmp"
    local written, writeError = noctalia.writeFile(temporaryPath, raw)
    if not written then
        noctalia.removeFile(temporaryPath)
        return false, writeError
    end
    local renamed, renameError = noctalia.renameFile(temporaryPath, path)
    if not renamed then
        noctalia.removeFile(temporaryPath)
        return false, renameError
    end
    noctalia.state.set(stateKey, supported.key)
    return true, nil
end

return { stateKey = stateKey, load = load, save = save }
