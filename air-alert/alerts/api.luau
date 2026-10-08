--!strict

export type AlertsResponseHandler = (HttpResponse) -> ()

local function fetchAlerts(onResponse: AlertsResponseHandler): boolean
    return noctalia.http({
        url = "https://neptun.in.ua/api/v1/alerts",
        method = "GET",
        headers = {
            "Accept: application/json",
        },
    }, onResponse)
end

return {
    fetchAlerts = fetchAlerts,
}
