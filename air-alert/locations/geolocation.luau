--!strict

local catalog = require("./catalog.luau")

export type ErrorCode = "request" | "network" | "invalid" | "outside"

local function locate(onResult: (catalog.Location?, ErrorCode?) -> ()): ()
    -- Same IP lookup used by Noctalia's LocationService; no coordinates are sent.
    local accepted = noctalia.http(
        { url = "https://api.noctalia.dev/geolocate" },
        function(response: HttpResponse): ()
            if not response.ok or response.status < 200 or response.status >= 300 then
                onResult(nil, "network")
                return
            end
            local data: any, err = noctalia.json.decode(response.body)
            if
                err
                or typeof(data) ~= "table"
                or typeof(data.lat) ~= "number"
                or typeof(data.lng) ~= "number"
                or data.lat ~= data.lat
                or data.lng ~= data.lng
                or math.abs(data.lat) > 90
                or math.abs(data.lng) > 180
            then
                onResult(nil, "invalid")
                return
            end
            -- Load the boundary asset only when the user requests geolocation.
            local geometry = require("./geometry.luau")
            local location = geometry.resolve(data.lat, data.lng)
            if not location then
                onResult(nil, "outside")
                return
            end
            onResult(location, nil)
        end
    )
    if not accepted then
        onResult(nil, "request")
    end
end

return { locate = locate }
