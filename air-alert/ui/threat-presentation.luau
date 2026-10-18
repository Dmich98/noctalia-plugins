--!strict

local events = require("../alerts/events.luau")
local threats = require("../alerts/threats.luau")
local catalog = require("../locations/catalog.luau")

local criticalByType: { [string]: boolean } = {
    uav = true,
    fpv = true,
    missile = true,
    ballistic = true,
    kab = true,
    mig31k = false,
    recon = false,
    unknown = false,
}

local function details(threat: events.Threat): { string }
    local location = catalog.find(threat.locationKey)
    local locationName = location and catalog.displayName(location) or noctalia.tr("time.unavailable")
    local typeName = noctalia.tr("threat.type.unknown")
    if criticalByType[threat.type] ~= nil then
        typeName = noctalia.tr("threat.type." .. threat.type)
    else
        typeName ..= ": " .. threat.type
    end
    if threat.title and criticalByType[threat.type] ~= nil then
        typeName = threat.title
    end
    if threat.count then
        typeName ..= " ×" .. tostring(threat.count)
    end
    if threat.advisory == true then
        typeName ..= " · " .. noctalia.tr("threat.observation")
    end
    local place = locationName
    if location and location.oblastKey then
        place = location.name
    end
    if threat.areaOnly ~= true then
        place = threat.locality or threat.district or place
    end
    local lines = { typeName, "• " .. place }
    if threat.explanationShort then
        table.insert(lines, "• " .. threat.explanationShort)
    end
    return lines
end

local function forThreat(threat: events.Threat, change: threats.Change): (string, string, string)
    local active = change == "new" or change == "update" or change == "entered"
    local lines = details(threat)
    local summary = lines[1] .. " · " .. noctalia.tr("threat.event." .. change)
    table.remove(lines, 1)
    local urgency = "normal"
    if active and threat.advisory ~= true and criticalByType[threat.type] == true then
        urgency = "critical"
    end
    return summary, table.concat(lines, "\n"), urgency
end

return { forThreat = forThreat, details = details }
