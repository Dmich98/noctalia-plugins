--!strict

local boundaries = require("./boundaries.luau")
local catalog = require("./catalog.luau")

type Boundary = boundaries.Boundary
local locations: { [string]: catalog.Location } = {}
for _, location in ipairs(catalog.all) do
    locations[location.key] = location
end
for _, location in ipairs(catalog.raions) do
    locations[location.key] = location
end

-- Decode only visited rings; reuse them across the uncertainty checks and later reports.
local parsedRings: { [string]: { number } } = {}
local function points(ring: string): { number }
    local cached = parsedRings[ring]
    if cached then
        return cached
    end
    local result: { number } = {}
    for longitude, latitude in ring:gmatch("([^,;]+),([^;]+)") do
        table.insert(result, assert(tonumber(longitude)))
        table.insert(result, assert(tonumber(latitude)))
    end
    parsedRings[ring] = result
    return result
end

-- nil means exactly on an edge: do not guess which territory owns the point.
-- Packed rings avoid compiling thousands of point tables within the host's 25 ms callback budget.
local function inRing(ring: string, x: number, y: number): boolean?
    local inside = false
    local coordinates = points(ring)
    for index = 3, #coordinates, 2 do
        local ax, ay = coordinates[index - 2], coordinates[index - 1]
        local bx, by = coordinates[index], coordinates[index + 1]
        local cross = (x - ax) * (by - ay) - (y - ay) * (bx - ax)
        if
            math.abs(cross) < 1e-10
            and x >= math.min(ax, bx)
            and x <= math.max(ax, bx)
            and y >= math.min(ay, by)
            and y <= math.max(ay, by)
        then
            return nil
        end
        if (ay > y) ~= (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax then
            inside = not inside
        end
    end
    return inside
end

local function contains(boundary: Boundary, x: number, y: number): boolean?
    local box = boundary.bounds
    if x < box[1] or y < box[2] or x > box[3] or y > box[4] then
        return false
    end
    for _, polygon in ipairs(boundary.polygons) do
        local exterior = inRing(polygon[1], x, y)
        if exterior == nil then
            return nil
        end
        if exterior then
            local inHole = false
            for index = 2, #polygon do
                local hole = inRing(polygon[index], x, y)
                if hole == nil then
                    return nil
                end
                inHole = inHole or hole
            end
            if not inHole then
                return true
            end
        end
    end
    return false
end

local function resolve(latitude: number, longitude: number): catalog.Location?
    if
        latitude ~= latitude
        or longitude ~= longitude
        or math.abs(latitude) > 90
        or math.abs(longitude) > 180
    then
        return nil
    end
    local oblast: catalog.Location? = nil
    local city: catalog.Location? = nil
    for _, boundary in ipairs(boundaries.oblasts) do
        local match = contains(boundary, longitude, latitude)
        if match == nil then
            return nil
        elseif match then
            if boundary.key == "м. київ" or boundary.key == "севастополь" then
                city = locations[boundary.key]
            elseif oblast then
                return nil
            else
                oblast = locations[boundary.key]
            end
        end
    end
    if city then
        return city
    end
    if not oblast then
        return nil
    end
    local raion: catalog.Location? = nil
    for _, boundary in ipairs(boundaries.raions) do
        local location = locations[boundary.key]
        if location and location.oblastKey == oblast.key then
            local match = contains(boundary, longitude, latitude)
            if match == nil or (match and raion ~= nil) then
                return nil
            elseif match then
                raion = location
            end
        end
    end
    return raion or oblast
end

return { resolve = resolve }
