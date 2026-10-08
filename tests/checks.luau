--!nocheck
local early = "2026-10-08T18:00:00Z"
local late = "2026-10-08T19:00:00.123Z"

local oblast = {
    locationKey = "київська",
    locationName = "Київська область",
    locationType = "oblast",
}
local city =
    { locationKey = "м. київ", locationName = "м. Київ", locationType = "oblast" }
local function alert(key, level, since, reasons)
    return {
        key = key,
        name = key,
        oblast = oblast.locationName,
        level = level,
        since = since,
        reasons = reasons,
    }
end
local data = {
    oblasts = {},
    raions = {
        alert("бориспільський", "yellow", early, { "дрони" }),
        alert("броварський", "red", late, { "дрони", "ракети" }),
    },
}

local env = runtime()
local alerts = env.require("./alerts/status.luau")
local result = assert(alerts.resolveLocationAlert(data, oblast))
assert(result.key == oblast.locationKey and result.level == "red" and result.since == early)
assert(
    #result.reasons == 2
        and result.reasons[1] == "дрони"
        and result.reasons[2] == "ракети"
)
assert(data.raions[1].level == "yellow", "aggregation must not mutate the response")
assert(
    alerts.resolveLocationAlert(data, city) == nil,
    "Kyiv city must not inherit Kyiv oblast alerts"
)
assert(alerts.resolveLocationAlert({ oblasts = {}, raions = {} }, oblast) == nil)
local direct = alert(city.locationKey, "red", early)
assert(alerts.resolveLocationAlert({ oblasts = { direct }, raions = {} }, city).level == "red")
assert(alerts.resolveLocationAlert(data, {
    locationKey = "броварський",
    locationName = "Броварський район",
    locationType = "raion",
}).since == late)
local mixed = { oblasts = { alert(oblast.locationKey, "yellow", early) }, raions = data.raions }
assert(alerts.resolveLocationAlert(mixed, oblast).level == "red")
local unknownStart =
    { oblasts = {}, raions = { alert("a", "yellow", "invalid"), alert("b", "red", early) } }
assert(alerts.resolveLocationAlert(unknownStart, oblast).since == "")
print("PASS location matching and oblast aggregation")

local alertsApi = env.require("./alerts/api.luau")
env.jsonValues.response = data
assert(alertsApi.parseAlertsResponse("response") ~= nil)
assert(alertsApi.parseAlertsResponse("invalid JSON") == nil)
for _, invalid in ipairs({
    false,
    { oblasts = { false }, raions = {} },
    { oblasts = { first = direct }, raions = {} },
    { oblasts = { [2] = direct }, raions = {} },
    { oblasts = { { key = city.locationKey } }, raions = {} },
    { oblasts = { alert(city.locationKey, "red", early, { false }) }, raions = {} },
}) do
    env.jsonValues.response = invalid
    local parsed, err = alertsApi.parseAlertsResponse("response")
    assert(parsed == nil and err ~= nil)
end
env.jsonValues.response = { oblasts = {}, raions = {} }
assert(alertsApi.parseAlertsResponse("response") ~= nil)
print("PASS response validation")

local time = env.require("./alerts/time.luau")
assert(time.parseSince(early) ~= nil and time.parseSince(late) ~= nil)
assert(time.parseSince("2026-02-31T18:00:00Z") == nil and time.parseSince("invalid") == nil)
assert(time.formatDuration(0, 59) == "Менше хвилини")
assert(time.formatDuration(0, 59 * 60) == "59 хв")
assert(time.formatDuration(0, 60 * 60) == "1 год 0 хв")
assert(time.formatDuration(0, 78 * 60) == "1 год 18 хв")
assert(time.formatDuration(1, 0) == "Час початку некоректний")
time.formatTime(0)
assert(env.timezone == "Europe/Kyiv")
print("PASS dates and durations")

env = runtime()
local store = env.require("./locations/store.luau")
env.files["/data/config.json"] = "previous"
for _, failure in ipairs({ "failWrite", "failRename" }) do
    env[failure] = true
    assert(not store.saveLocation(city))
    assert(
        env.files["/data/config.json"] == "previous" and env.files["/data/config.json.tmp"] == nil
    )
    assert(env.values.selectedLocation == nil)
    env[failure] = false
end
assert(store.saveLocation(city))
assert(store.loadLocation().locationKey == city.locationKey)
assert(env.values.selectedLocation.locationKey == city.locationKey)
print("PASS save failures and persistence ordering")
