--!nocheck
-- sources is supplied by run.py; filesystem and HTTP never touch real user data.

local early = "2026-10-08T18:00:00Z"
local late = "2026-10-08T19:00:00.123Z"
local utcText = {
    [os.time({ year = 2026, month = 10, day = 8, hour = 18, min = 0, sec = 0 })] = early:sub(1, 19),
    [os.time({ year = 2026, month = 10, day = 8, hour = 19, min = 0, sec = 0 })] = late:sub(1, 19),
}

local function runtime()
    local env = setmetatable(
        { files = {}, values = {}, jsonValues = {}, requests = {}, panels = {} },
        { __index = getfenv() }
    )
    local watchers, modules = {}, {}
    env.noctalia = {
        tr = function(key, substitutions)
            local text = translations[key] or key
            return (
                text:gsub("{([^}]+)}", function(name)
                    local value = substitutions and substitutions[name]
                    return value ~= nil and tostring(value) or ("{" .. name .. "}")
                end)
            )
        end,
        pluginDataDir = function()
            return "/data"
        end,
        fileExists = function(path)
            return env.files[path] ~= nil
        end,
        readFile = function(path)
            return env.files[path], "missing file"
        end,
        writeFile = function(path, raw)
            env.files[path] = raw
            return not env.failWrite, env.failWrite and "write failed" or nil
        end,
        renameFile = function(from, to)
            if env.failRename then
                return false, "rename failed"
            end
            env.files[to], env.files[from] = env.files[from], nil
            return true
        end,
        removeFile = function(path)
            env.files[path] = nil
            return true
        end,
        log = function() end,
        setUpdateInterval = function() end,
        togglePanel = function(id)
            table.insert(env.panels, id)
        end,
        formatTime = function(pattern, seconds, timezone)
            env.timezone = timezone
            return timezone == "UTC" and (utcText[seconds] or "invalid") or "formatted"
        end,
        http = function(_, callback)
            if env.rejectRequest then
                return false
            end
            table.insert(env.requests, callback)
            return true
        end,
        json = {
            decode = function(raw)
                local value = env.jsonValues[raw]
                if value == nil then
                    return nil, "invalid JSON"
                end
                return value
            end,
            encode = function(value)
                env.jsonValues[value.locationKey] = table.clone(value)
                return value.locationKey
            end,
        },
        state = {
            get = function(key)
                return env.values[key]
            end,
            set = function(key, value)
                env.values[key] = value
            end,
            watch = function(key, callback)
                watchers[key] = callback
            end,
        },
    }
    env.barWidget = {
        setText = function(text)
            env.text = text
        end,
        setColor = function() end,
        setGlyphColor = function() end,
        setGlyph = function() end,
        setTooltip = function() end,
    }
    env.ui = setmetatable({}, {
        __index = function(_, kind)
            return function(props, children)
                return { kind = kind, props = props, children = children }
            end
        end,
    })
    env.emit = function(key, value)
        env.values[key] = value
        watchers[key](value)
    end
    env.require = function(path)
        if not modules[path] then
            local chunk = assert(loadstring(assert(sources[path]), path))
            setfenv(chunk, env)
            modules[path] = chunk()
        end
        return modules[path]
    end
    return env
end

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

env.jsonValues.response = data
assert(alerts.parseAlertsResponse("response") ~= nil)
assert(alerts.parseAlertsResponse("invalid JSON") == nil)
for _, invalid in ipairs({
    false,
    { oblasts = { false }, raions = {} },
    { oblasts = { first = direct }, raions = {} },
    { oblasts = { [2] = direct }, raions = {} },
    { oblasts = { { key = city.locationKey } }, raions = {} },
    { oblasts = { alert(city.locationKey, "red", early, { false }) }, raions = {} },
}) do
    env.jsonValues.response = invalid
    local parsed, err = alerts.parseAlertsResponse("response")
    assert(parsed == nil and err ~= nil)
end
env.jsonValues.response = { oblasts = {}, raions = {} }
assert(alerts.parseAlertsResponse("response") ~= nil)
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
assert(env.values.selectedLocation == city)
print("PASS save failures and persistence ordering")

env = runtime()
env.require("./widget.luau")
env.update()
assert(#env.requests == 0 and env.text == "Оберіть локацію")
env.emit("selectedLocation", city)
env.update()
assert(#env.requests == 1, "a tick must not overlap an in-flight request")
env.requests[1]({ ok = false, status = 0 })
assert(env.values.alertStatus.error ~= nil and env.text:find("Дані недоступні"))
env.update()
assert(#env.requests == 2, "retry after failure")
env.emit("selectedLocation", oblast)
assert(#env.requests == 3)
env.requests[2]({ ok = false, status = 0 })
assert(env.values.alertStatus.location == oblast and env.values.alertStatus.loading)
env.update()
assert(#env.requests == 3, "old callback must not clear the current request")
env.jsonValues.response = data
env.requests[3]({ ok = true, status = 200, body = "response" })
assert(env.values.alertStatus.active and env.values.alertStatus.level == "red")
env.update()
env.requests[4]({ ok = true, status = 200, body = "malformed" })
assert(env.values.alertStatus.error and env.values.alertStatus.active == nil)
env.rejectRequest = true
env.update()
assert(env.values.alertStatus.error ~= nil)
env.rejectRequest = false
env.update()
assert(#env.requests == 5, "a rejected request must not block the next retry")
env.emit("selectedLocation", nil)
env.requests[5]({ ok = true, status = 200, body = "response" })
assert(env.text == "Оберіть локацію" and env.values.alertStatus.location == nil)
env.emit("panelRequest", "dmich/air-alert:location-picker")
assert(env.panels[1] == "dmich/air-alert:location-picker")
print("PASS widget fallback, request lifecycle and navigation")

local view = env.require("./ui/status-view.luau")
local tree = view.renderStatusView(city, { location = city, loading = true })
assert(tree.children[4].children[2].props.text == "Отримання даних…")
print("PASS loading view")
