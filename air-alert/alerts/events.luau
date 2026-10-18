--!strict

local time = require("./time.luau")
local catalog = require("../locations/catalog.luau")

-- Ordinary table types support the legacy analyzer. Runtime freeze remains authoritative;
-- casts after freezing bridge the new solver's read-only inference without skipping validation.
export type List<T> = { [number]: T }
export type Threat = {
    id: string,
    type: string,
    updatedAt: string?,
    advisory: boolean?,
    areaOnly: boolean?,
    locationKey: string?,
    title: string?,
    district: string?,
    locality: string?,
    explanationShort: string?,
    status: string?,
    heading: number?,
    confidenceLevel: string?,
    count: number?,
}
export type OblastAlert = {
    key: string,
    level: string?,
    since: string?,
    reasons: List<string>?,
}
export type RaionAlert = OblastAlert & { oblastKey: string }
export type Alerts = {
    raions: List<RaionAlert>,
    oblasts: List<OblastAlert>,
    updatedAt: string?,
    version: number?,
}
export type Event =
    { type: "snapshot", ts: string, data: { threats: List<Threat> } }
    | { type: "upsert", ts: string, data: Threat }
    | { type: "remove", ts: string, data: { id: string } }
    | { type: "alerts", ts: string, data: Alerts }
    | { type: "heartbeat", ts: string }
export type ErrorCode = "oversized" | "json" | "envelope" | "payload"

local MAX_MESSAGE_BYTES = 61440
local MAX_JSON_DEPTH = 64
-- The catalog contains explicit NEPTUN source names and keys, not translated labels.
local oblastKeys: { [string]: string } = {}
for _, location in ipairs(catalog.all) do
    oblastKeys[location.name] = location.key
end
local districtKeys: { [string]: string } = {}
for _, location in ipairs(catalog.raions) do
    districtKeys[location.name] = location.key
end

local function text(value: any): string?
    if typeof(value) == "string" and value:find("%S") then
        return value
    end
    return nil
end

-- Resolve only explicit source attributes, never locality text or inferred flight paths.
local function threatLocation(value: any): string?
    if
        (value.region ~= nil and typeof(value.region) ~= "string")
        or (value.district ~= nil and typeof(value.district) ~= "string")
    then
        return nil
    end
    local region = text(value.region)
    local oblastKey = region and oblastKeys[region]
    local district = catalog.find(districtKeys[text(value.district) or ""])
    if region and not oblastKey then
        return nil
    end
    if district then
        if oblastKey and district.oblastKey ~= oblastKey then
            return nil
        end
        return value.areaOnly == true and district.oblastKey or district.key
    end
    return oblastKey
end

-- Host JSON decoding loses array/object identity and removes null values.
-- Boolean guards at both array ends preserve identity and expose trailing nulls.
local function tagArrays(raw: string): string?
    local parts: { string } = {}
    local quoted, escaped, nul = false, false, false
    local depth = 0
    for index = 1, #raw do
        local char = raw:sub(index, index)
        if quoted then
            table.insert(parts, char)
            if escaped then
                escaped = false
            elseif char == "\\" then
                escaped = true
                nul = nul or raw:sub(index + 1, index + 5) == "u0000"
            elseif char == '"' then
                quoted = false
                if nul then
                    local following = raw:find("%S", index + 1)
                    -- The host passes object keys to a NUL-terminated C API.
                    if following and raw:sub(following, following) == ":" then
                        return nil
                    end
                end
            end
        elseif char == '"' then
            quoted = true
            nul = false
            table.insert(parts, char)
        elseif char == "[" then
            depth += 1
            if depth > MAX_JSON_DEPTH then
                return nil
            end
            local following = index + 1
            while raw:sub(following, following):match("%s") do
                following += 1
            end
            table.insert(parts, raw:sub(following, following) == "]" and "[true" or "[true,")
        elseif char == "]" then
            depth -= 1
            table.insert(parts, ",true]")
        else
            if char == "{" then
                depth += 1
                if depth > MAX_JSON_DEPTH then
                    return nil
                end
            elseif char == "}" then
                depth -= 1
            end
            table.insert(parts, char)
        end
    end
    return table.concat(parts)
end

local function arrayLength(value: any): number?
    if typeof(value) ~= "table" then
        return nil
    end
    local count = 0
    for index in pairs(value) do
        if typeof(index) ~= "number" or index < 1 or index % 1 ~= 0 then
            return nil
        end
        count += 1
    end
    for index = 1, count do
        if value[index] == nil then
            return nil
        end
    end
    if count < 2 or value[1] ~= true or value[count] ~= true then
        return nil
    end
    return count - 2
end

local function threat(value: any): Threat?
    if
        typeof(value) ~= "table"
        or typeof(value.id) ~= "string"
        or value.id == ""
        or typeof(value.type) ~= "string"
        or value.type == ""
        or (value.advisory ~= nil and typeof(value.advisory) ~= "boolean")
        or (value.areaOnly ~= nil and typeof(value.areaOnly) ~= "boolean")
    then
        return nil
    end
    local parsed: Threat = {
        id = value.id,
        type = value.type,
        updatedAt = time.keepValid(value.updatedAt),
        advisory = value.advisory,
        areaOnly = value.areaOnly,
        locationKey = threatLocation(value),
        title = text(value.title),
        district = text(value.district),
        locality = text(value.locality),
        explanationShort = text(value.explanationShort),
        status = text(value.status),
        confidenceLevel = text(value.confidenceLevel),
    }
    if typeof(value.heading) == "number" and value.heading >= 0 and value.heading < 360 then
        parsed.heading = value.heading
    end
    if
        typeof(value.count) == "number"
        and value.count > 0
        and value.count < math.huge
        and value.count % 1 == 0
    then
        parsed.count = value.count
    end
    table.freeze(parsed)
    return parsed :: Threat
end

local function alert(value: any): OblastAlert?
    if
        typeof(value) ~= "table"
        or typeof(value.key) ~= "string"
        or value.key == ""
        or (value.level ~= nil and (typeof(value.level) ~= "string" or value.level == ""))
    then
        return nil
    end
    local reasons: List<string>? = nil
    if value.reasons ~= nil then
        local length = arrayLength(value.reasons)
        if not length then
            return nil
        end
        local parsed: { string } = {}
        for index = 1, length do
            local reason = value.reasons[index + 1]
            if typeof(reason) ~= "string" then
                return nil
            end
            table.insert(parsed, reason)
        end
        table.sort(parsed)
        reasons = table.freeze(parsed)
    end
    return {
        key = value.key,
        level = value.level,
        since = time.keepValid(value.since),
        reasons = reasons,
    }
end

local function alerts(value: any): Alerts?
    if typeof(value) ~= "table" then
        return nil
    end
    local raionCount, oblastCount = arrayLength(value.raions), arrayLength(value.oblasts)
    if not raionCount or not oblastCount then
        return nil
    end
    local version = value.version
    if
        version ~= nil
        and (typeof(version) ~= "number" or version < 0 or version % 1 ~= 0 or version == math.huge)
    then
        return nil
    end
    local oblasts: { OblastAlert } = {}
    local raions: { RaionAlert } = {}
    local seen: { [string]: boolean } = {}
    for index = 1, oblastCount do
        local parsed = alert(value.oblasts[index + 1])
        if not parsed or seen[parsed.key] then
            return nil
        end
        seen[parsed.key] = true
        table.freeze(parsed)
        table.insert(oblasts, parsed :: OblastAlert)
    end
    seen = {}
    for index = 1, raionCount do
        local source = value.raions[index + 1]
        local parsed = alert(source)
        if not parsed or typeof(source.oblast) ~= "string" then
            return nil
        end
        local oblastKey = oblastKeys[source.oblast]
        if not oblastKey or seen[parsed.key] then
            return nil
        end
        seen[parsed.key] = true
        local raion: RaionAlert = {
            key = parsed.key,
            level = parsed.level,
            since = parsed.since,
            reasons = parsed.reasons,
            oblastKey = oblastKey,
        }
        table.freeze(raion)
        table.insert(raions, raion)
    end
    table.sort(oblasts, function(a: OblastAlert, b: OblastAlert): boolean
        return a.key < b.key
    end)
    table.sort(raions, function(a: RaionAlert, b: RaionAlert): boolean
        return a.key < b.key
    end)
    local parsed: Alerts = {
        raions = table.freeze(raions),
        oblasts = table.freeze(oblasts),
        version = version,
        updatedAt = time.keepValid(value.updatedAt),
    }
    table.freeze(parsed)
    return parsed :: Alerts
end

local function freezeEvent(event: Event): Event
    table.freeze(event)
    return event
end

local function decode(raw: string): (Event?, ErrorCode?)
    if #raw > MAX_MESSAGE_BYTES then
        return nil, "oversized"
    end
    local tagged = tagArrays(raw)
    if not tagged then
        return nil, "json"
    end
    local value: any, err = noctalia.json.decode(tagged)
    if err then
        return nil, "json"
    end
    if typeof(value) ~= "table" or typeof(value.type) ~= "string" then
        return nil, "envelope"
    end
    local kind = value.type
    if
        kind ~= "snapshot"
        and kind ~= "upsert"
        and kind ~= "remove"
        and kind ~= "alerts"
        and kind ~= "heartbeat"
    then
        return nil, nil
    end
    local ts = time.keepValid(value.ts)
    if not ts then
        return nil, "envelope"
    end
    if kind == "heartbeat" then
        return freezeEvent({ type = "heartbeat", ts = ts }), nil
    elseif kind == "upsert" then
        local parsed = threat(value.data)
        if parsed then
            return freezeEvent({ type = "upsert", ts = ts, data = parsed }), nil
        end
    elseif kind == "remove" then
        if
            typeof(value.data) == "table"
            and typeof(value.data.id) == "string"
            and value.data.id ~= ""
        then
            local data: { id: string } = { id = value.data.id }
            table.freeze(data)
            return freezeEvent({ type = "remove", ts = ts, data = data :: { id: string } }), nil
        end
    elseif kind == "alerts" then
        local parsed = alerts(value.data)
        if parsed then
            return freezeEvent({ type = "alerts", ts = ts, data = parsed }), nil
        end
    elseif typeof(value.data) == "table" then
        local length = arrayLength(value.data.threats)
        if length then
            local threats: { Threat } = {}
            local seen: { [string]: boolean } = {}
            for index = 1, length do
                local parsed = threat(value.data.threats[index + 1])
                if not parsed or seen[parsed.id] then
                    return nil, "payload"
                end
                seen[parsed.id] = true
                table.insert(threats, parsed)
            end
            local data: { threats: { Threat } } = { threats = table.freeze(threats) }
            table.freeze(data)
            return freezeEvent({
                type = "snapshot",
                ts = ts,
                data = data :: { threats: List<Threat> },
            }),
                nil
        end
    end
    return nil, "payload"
end

return { decode = decode }
