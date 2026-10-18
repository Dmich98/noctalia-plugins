--!nocheck

local env = runtime()
local catalog = env.require("./locations/catalog.luau")
local geometry = env.require("./locations/geometry.luau")
assert(#catalog.raions == 136)
for _, location in ipairs(catalog.raions) do
    assert(catalog.find(location.key) == location)
    assert(catalog.find(location.oblastKey) and not catalog.find(location.oblastKey).oblastKey)
    assert(location.key == "raion:" .. location.sourceKey)
end
for _, case in ipairs({
    { 50.4501, 30.5234, "м. київ" },
    { 50.345, 30.955, "raion:бориспільський" },
    { 49.8397, 24.0297, "raion:львівський" },
    { 46.4825, 30.7233, "raion:одеський" },
    { 48.4647, 35.0462, "raion:дніпровський" },
    { 44.6167, 33.5254, "севастополь" },
}) do
    local location = assert(geometry.resolve(case[1], case[2]), case[3])
    assert(location.key == case[3], location.key .. " ~= " .. case[3])
end
for _, point in ipairs({ { 0, 0 }, { 91, 30 }, { 50, 181 }, { 0 / 0, 30 }, { math.huge, 30 } }) do
    assert(geometry.resolve(point[1], point[2]) == nil)
end
-- Exercise holes, multiple polygons, edges and overlapping districts independently of real geography.
local synthetic = runtime()
local requireModule = synthetic.require
local outer = "0,0;10,0;10,10;0,10;0,0"
local hole = "4,4;6,4;6,6;4,6;4,4"
local second = "20,20;30,20;30,30;20,30;20,20"
local fake = {
    oblasts = { { key = "київська", bounds = { 0, 0, 30, 30 }, polygons = { { outer, hole }, { second } } } },
    raions = { { key = "raion:бориспільський", bounds = { 0, 0, 30, 30 }, polygons = { { outer, hole }, { second } } } },
}
synthetic.require = function(path)
    return path == "./locations/boundaries.luau" and fake or requireModule(path)
end
local testGeometry = synthetic.require("./locations/geometry.luau")
assert(testGeometry.resolve(2, 2).key == "raion:бориспільський")
assert(testGeometry.resolve(25, 25).key == "raion:бориспільський")
assert(testGeometry.resolve(5, 5) == nil)
assert(testGeometry.resolve(0, 5) == nil)
assert(testGeometry.resolve(4, 5) == nil)
table.insert(fake.raions, { key = "raion:броварський", bounds = { 0, 0, 10, 10 }, polygons = { { outer } } })
assert(testGeometry.resolve(2, 2) == nil)
print("PASS geographic districts, Kyiv/Sevastopol, polygons, holes, borders and invalid coordinates")

local status = env.require("./alerts/status.luau")
local source = { kind = "current", syncedAtMs = 1, data = { oblasts = {}, raions = {} } }
local key = "raion:бориспільський"
assert(status.project(source, key).alert == nil)
source.data.raions = { { key = "броварський", oblastKey = "київська", level = "red" } }
assert(status.project(source, key).alert == nil, "neighboring district must not activate this district")
assert(status.project(source, "київська").alert.level == "red", "whole-oblast selection preserves aggregation")
table.insert(source.data.raions, { key = "бориспільський", oblastKey = "київська", level = "yellow" })
assert(status.project(source, key).alert.level == "yellow")
source.data.oblasts = { { key = "київська", level = "red" } }
assert(status.project(source, key).alert.level == "red", "whole-oblast alert includes selected district")
assert(status.project(source, "м. київ").alert == nil)
source.kind = "stale"
assert(status.project(source, key).kind == "stale")
source.data.raions = { { key = "new-district", oblastKey = "київська", level = "red" } }
assert(status.project(source, key).kind == "unknown", "unknown local district cannot establish clear")
print("PASS district projection, whole-oblast alerts, neighboring districts and stale/unknown state")

local store = env.require("./locations/store.luau")
assert(store.save(catalog.find(key)))
assert(store.load().key == key)
assert(env.jsonValues[key].locationType == "raion")
for _, failure in ipairs({ "failWrite", "failRename" }) do
    env[failure] = true
    assert(not store.save(catalog.find("м. київ")))
    assert(store.load().key == key and env.values.selectedLocation == key)
    assert(env.files["/data/config.json.tmp"] == nil)
    env[failure] = false
end

local picker = runtime()
picker.allowGeoHttp = true
picker.require("./location-panel-entry.luau")
local function control(key)
    return assert(findNode(picker.tree, function(node)
        return node.props and node.props.key == key
    end), key).props
end
local function response(index, value, ok, statusCode)
    picker.jsonValues.geo = value
    picker.requests[index].callback({ ok = ok ~= false, status = statusCode or 200, body = "geo" })
end
picker.onOpen()
assert(#picker.requests == 0)
control("geolocate").onClick()
assert(#picker.requests == 1 and not control("geolocate").enabled)
control("geolocate").onClick()
assert(#picker.requests == 1, "repeated clicks cannot overlap a pending lookup")
response(1, { lat = 50.345, lng = 30.955 })
assert(picker.values.selectedLocation == nil and picker.files["/data/config.json"] == nil)
assert(control("district").options[control("district").selectedIndex + 1] == "Бориспільський район")
control("save-location").onClick()
picker.flush()
assert(picker.values.selectedLocation == key)
assert(picker.require("./locations/store.luau").load().key == key)

-- A new choice, including A → B → A, invalidates an outstanding lookup.
picker.onOpen()
control("geolocate").onClick()
local oblast = control("location")
local kyiv = assert(table.find(oblast.options, "Київська область")) - 1
local lviv = assert(table.find(oblast.options, "Львівська область")) - 1
oblast.onChange(tostring(lviv))
control("location").onChange(tostring(kyiv))
response(2, { lat = 49.8397, lng = 24.0297 })
assert(control("location").selectedIndex == kyiv and control("district").selectedIndex == 0)
control("geolocate").onClick()
picker.onClose()
picker.onOpen()
response(3, { lat = 49.8397, lng = 24.0297 })
assert(control("district").options[control("district").selectedIndex + 1] == "Бориспільський район")

for _, case in ipairs({
    { value = { lat = "50", lng = 30 }, message = "location.geo_invalid" },
    { value = { lat = 0 / 0, lng = 30 }, message = "location.geo_invalid" },
    { value = { lat = 91, lng = 30 }, message = "location.geo_invalid" },
    { value = { lat = 50 }, message = "location.geo_invalid" },
    { value = {}, message = "location.geo_invalid" },
    { value = false, message = "location.geo_invalid" },
    { value = { lat = 0, lng = 0 }, message = "location.geo_outside" },
    { value = {}, ok = false, message = "location.geo_network" },
    { value = {}, status = 503, message = "location.geo_network" },
}) do
    control("geolocate").onClick()
    response(#picker.requests, case.value, case.ok, case.status)
    assert(findNode(picker.tree, function(node)
        return node.props and node.props.text == picker.noctalia.tr(case.message)
    end), case.message)
    assert(picker.values.selectedLocation == key, "failed detection must preserve saved location")
    assert(control("geolocate").enabled)
end
picker.rejectHttp = true
control("geolocate").onClick()
assert(control("geolocate").enabled)
assert(findNode(picker.tree, function(node)
    return node.props and node.props.text == picker.noctalia.tr("location.geo_request")
end))
assert(#picker.logs == 0, "no IP or coordinates should be logged")
print("PASS geolocation confirmation, errors, rejected lookup, lifecycle and A → B → A protection")

local service = runtime()
local first = runtime(service.shared)
local second = runtime(service.shared)
service.require("./service.luau")
first.require("./widget.luau")
second.require("./widget.luau")
local serviceCatalog = service.require("./locations/catalog.luau")
local serviceStore = service.require("./locations/store.luau")
assert(serviceStore.save(serviceCatalog.find(key)))
service.flush()
service.update()
for raw, value in pairs(wsJsonValues) do
    service.jsonValues[raw] = value
end
-- Replay the captured baseline containing an active Boryspil district alert.
service.streams[1].onLine(wsFixtures["session-1"][2])
service.flush()
assert(service.values.alertStatus.kind == "alert" and service.values.alertStatus.locationKey == key)
assert(tooltipValue(first.tooltip, "Регіон") == "Бориспільський район · Київська область")
assert(first.text == second.text and first.glyphColor == second.glyphColor)
assert(#service.notifications == 0)
assert(serviceStore.save(serviceCatalog.find("raion:львівський")))
service.flush()
assert(service.values.alertStatus.kind == "clear")
assert(service.streamAttempts == 1 and #service.requests == 0)
assert(serviceStore.save(serviceCatalog.find(key)))
service.flush()
assert(service.values.alertStatus.kind == "alert" and #service.notifications == 0)
assert(service.streamAttempts == 1 and first.streamAttempts == 0 and second.streamAttempts == 0)
local restarted = runtime(service.shared)
restarted.require("./widget.luau")
restarted.update()
assert(tooltipValue(restarted.tooltip, "Регіон") == "Бориспільський район · Київська область")
print("PASS saved districts across shared widgets, restart and A → B → A without reconnecting")
