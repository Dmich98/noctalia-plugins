--!strict

export type AlertRegion = {
    key: string,
    name: string,
    oblast: string,
    since: string,
    level: string,
    reasons: { string }?,
}

export type AlertsResponse = {
    raions: { AlertRegion },
    oblasts: { AlertRegion },
}

local function isArray(value: any, validItem: (any) -> boolean): boolean
    if typeof(value) ~= "table" then
        return false
    end
    local count = 0
    for index, item in pairs(value) do
        if
            typeof(index) ~= "number"
            or index % 1 ~= 0
            or index < 1
            or index > #value
            or not validItem(item)
        then
            return false
        end
        count += 1
    end
    return count == #value
end

local function isAlert(value: any): boolean
    return typeof(value) == "table"
        and typeof(value.key) == "string"
        and value.key ~= ""
        and typeof(value.name) == "string"
        and typeof(value.oblast) == "string"
        and typeof(value.since) == "string"
        and typeof(value.level) == "string"
        and value.level ~= ""
        and (
            value.reasons == nil
            or isArray(value.reasons, function(reason: any): boolean
                return typeof(reason) == "string"
            end)
        )
end

local function parseAlertsResponse(body: string): (AlertsResponse?, string?)
    local data, err = noctalia.json.decode(body)

    if not data or err then
        return nil, err or "Empty response"
    end

    if typeof(data) ~= "table" then
        return nil, "Expected an alerts object"
    end

    if not isArray(data.oblasts, isAlert) or not isArray(data.raions, isAlert) then
        return nil, "Invalid oblasts or raions alerts"
    end

    return data :: AlertsResponse, nil
end

export type ErrorKind = "fetch" | "decode" | "request"
export type AlertsResponseHandler = (AlertsResponse?, ErrorKind?) -> ()

local function fetchAlerts(onResponse: AlertsResponseHandler): boolean
    return noctalia.http({
        url = "https://neptun.in.ua/api/v1/alerts",
        method = "GET",
        headers = { "Accept: application/json" },
    }, function(response: HttpResponse): ()
        if not response.ok or response.status ~= 200 then
            onResponse(nil, "fetch")
            return
        end
        local data = parseAlertsResponse(response.body)
        if not data then
            onResponse(nil, "decode")
            return
        end
        onResponse(data, nil)
    end)
end

return { parseAlertsResponse = parseAlertsResponse, fetchAlerts = fetchAlerts }
