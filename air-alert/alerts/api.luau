--!strict

local alertTime = require("./time.luau")

export type OblastAlert = {
    key: string,
    level: string,
    since: string?,
    reasons: { string }?,
}
export type RaionAlert = OblastAlert & { oblastKey: string }
export type Response = { updatedAt: string?, oblasts: { OblastAlert }, raions: { RaionAlert } }
export type ErrorCode = "network" | "invalid"
export type Handler = (Response?, ErrorCode?) -> ()

local function parseReasons(value: any): ({ string }?, boolean)
    if value == nil then
        return nil, true
    end
    if typeof(value) ~= "table" then
        return nil, false
    end
    local reasons: { string } = {}
    local count = 0
    for index, reason in pairs(value) do
        if
            typeof(index) ~= "number"
            or index % 1 ~= 0
            or index < 1
            or typeof(reason) ~= "string"
        then
            return nil, false
        end
        count += 1
        reasons[index] = reason
    end
    return reasons, count == #value
end

-- NEPTUN supplies parent names for raions; map those source values to catalog keys here.
local oblastKeys: { [string]: string } = {
    ["Автономна Республіка Крим"] = "автономна республіка крим",
    ["Вінницька область"] = "вінницька",
    ["Волинська область"] = "волинська",
    ["Дніпропетровська область"] = "дніпропетровська",
    ["Донецька область"] = "донецька",
    ["Житомирська область"] = "житомирська",
    ["Закарпатська область"] = "закарпатська",
    ["Запорізька область"] = "запорізька",
    ["Івано-Франківська область"] = "івано-франківська",
    ["Київська область"] = "київська",
    ["Кіровоградська область"] = "кіровоградська",
    ["Луганська область"] = "луганська",
    ["Львівська область"] = "львівська",
    ["Миколаївська область"] = "миколаївська",
    ["Одеська область"] = "одеська",
    ["Полтавська область"] = "полтавська",
    ["Рівненська область"] = "рівненська",
    ["Сумська область"] = "сумська",
    ["Тернопільська область"] = "тернопільська",
    ["Харківська область"] = "харківська",
    ["Херсонська область"] = "херсонська",
    ["Хмельницька область"] = "хмельницька",
    ["Черкаська область"] = "черкаська",
    ["Чернівецька область"] = "чернівецька",
    ["Чернігівська область"] = "чернігівська",
    ["м. Київ"] = "м. київ",
    ["Севастополь"] = "севастополь",
}

local function parse(body: string): (Response?, string?)
    local decoded: any, decodeError = noctalia.json.decode(body)
    if typeof(decoded) ~= "table" or decodeError then
        return nil, decodeError or "Expected an object"
    end
    if typeof(decoded.oblasts) ~= "table" then
        return nil, "Missing oblasts array"
    end
    if typeof(decoded.raions) ~= "table" then
        return nil, "Missing raions array"
    end
    local oblasts: { OblastAlert } = {}
    local count = 0
    local seen: { [string]: boolean } = {}
    for index, item in pairs(decoded.oblasts) do
        if
            typeof(index) ~= "number"
            or index % 1 ~= 0
            or index < 1
            or typeof(item) ~= "table"
            or typeof(item.key) ~= "string"
            or item.key == ""
            or typeof(item.level) ~= "string"
            or item.level == ""
            or seen[item.key]
        then
            return nil, "Invalid oblast alert"
        end
        local reasons, validReasons = parseReasons(item.reasons)
        if not validReasons then
            return nil, "Invalid alert reasons"
        end
        seen[item.key] = true
        count += 1
        oblasts[index] = {
            key = item.key,
            level = item.level,
            since = alertTime.keepValid(item.since),
            reasons = reasons,
        }
    end
    if count ~= #decoded.oblasts then
        return nil, "Sparse oblasts array"
    end
    local raions: { RaionAlert } = {}
    count = 0
    seen = {}
    for index, item in pairs(decoded.raions) do
        if
            typeof(index) ~= "number"
            or index % 1 ~= 0
            or index < 1
            or typeof(item) ~= "table"
            or typeof(item.key) ~= "string"
            or item.key == ""
            or typeof(item.level) ~= "string"
            or item.level == ""
            or typeof(item.oblast) ~= "string"
            or not oblastKeys[item.oblast]
            or seen[item.key]
        then
            return nil, "Invalid raion alert"
        end
        local reasons, validReasons = parseReasons(item.reasons)
        if not validReasons then
            return nil, "Invalid raion alert reasons"
        end
        seen[item.key] = true
        count += 1
        raions[index] = {
            key = item.key,
            oblastKey = oblastKeys[item.oblast],
            level = item.level,
            since = alertTime.keepValid(item.since),
            reasons = reasons,
        }
    end
    if count ~= #decoded.raions then
        return nil, "Sparse raions array"
    end
    return { updatedAt = alertTime.keepValid(decoded.updatedAt), oblasts = oblasts, raions = raions }, nil
end

local function fetch(onResult: Handler): boolean
    return noctalia.http({
        url = "https://neptun.in.ua/api/v1/alerts",
        method = "GET",
        headers = { "Accept: application/json" },
    }, function(response: HttpResponse): ()
        if not response.ok or response.status ~= 200 then
            onResult(nil, "network")
            return
        end
        local data, err = parse(response.body)
        if not data then
            noctalia.log("Invalid NEPTUN response: " .. (err or "unknown error"))
            onResult(nil, "invalid")
            return
        end
        onResult(data, nil)
    end)
end

return { parse = parse, fetch = fetch }
