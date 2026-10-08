--!nocheck

local service = runtime()
env = runtime(service.shared)
service.require("./service.luau")
env.require("./widget.luau")
service.update()
service.flush()
service.update()
service.flush()
assert(#service.requests == 0 and env.text == "Оберіть локацію")
env.emit("selectedLocation", city)
service.update()
service.flush()
assert(#service.requests == 1, "a tick must not overlap an in-flight request")
service.requests[1]({ ok = false, status = 0 })
service.flush()
assert(env.values.alertStatus.error ~= nil and env.text:find("Дані недоступні"))
service.update()
service.flush()
assert(#service.requests == 2, "retry after failure")
env.emit("selectedLocation", oblast)
assert(#service.requests == 3)
service.requests[2]({ ok = false, status = 0 })
service.flush()
assert(
    env.values.alertStatus.location.locationKey == oblast.locationKey
        and env.values.alertStatus.loading
)
service.update()
service.flush()
assert(#service.requests == 3, "old callback must not clear the current request")
env.jsonValues.response = data
service.requests[3]({ ok = true, status = 200, body = "response" })
service.flush()
assert(env.values.alertStatus.active and env.values.alertStatus.level == "red")
service.update()
service.flush()
service.requests[4]({ ok = true, status = 200, body = "malformed" })
service.flush()
assert(env.values.alertStatus.error and env.values.alertStatus.active == nil)
service.rejectRequest = true
service.update()
service.flush()
assert(env.values.alertStatus.error ~= nil)
service.rejectRequest = false
service.update()
service.flush()
assert(#service.requests == 5, "a rejected request must not block the next retry")
env.emit("selectedLocation", nil)
service.requests[5]({ ok = true, status = 200, body = "response" })
service.flush()
assert(env.text == "Оберіть локацію" and env.values.alertStatus.location == nil)
env.onClick()
env.require("./panels/navigation.luau").requestPanel("location-picker")
env.flush()
assert(env.panels[2] == "dmich/air-alert:location-picker")
print("PASS widget fallback, request lifecycle and navigation")

for _, mode in { "icon", "status", "location_status" } do
    local polling = runtime()
    local widget = runtime(polling.shared)
    polling.require("./service.luau")
    widget.config.display_mode = mode
    widget.require("./widget.luau")
    polling.update()
    polling.flush()
    widget.update()
    assert(widget.text == (mode == "icon" and "" or "Оберіть локацію"))
    widget.emit("selectedLocation", oblast)
    assert(
        widget.text
            == (
                mode == "icon" and ""
                or mode == "status" and "Отримання даних…"
                or "Київська область · Отримання даних…"
            )
    )
    widget.jsonValues.response = data
    polling.requests[1]({ ok = true, status = 200, body = "response" })
    polling.flush()
    local status = "Тривога · Червоний рівень"
    assert(
        widget.text
            == (
                mode == "icon" and ""
                or mode == "status" and status
                or "Київська область · " .. status
            )
    )
    assert(widget.glyph == "alert-octagon" and widget.tooltip ~= nil)
    polling.update()
    polling.flush()
    widget.update()
    polling.requests[2]({ ok = false, status = 0 })
    polling.flush()
    assert(
        widget.text
            == (
                mode == "icon" and ""
                or mode == "status" and "Дані недоступні"
                or "Київська область · Дані недоступні"
            )
    )
    assert(widget.glyph == "wifi-off" and widget.tooltip:find("Київська область"))
end
print("PASS widget display modes across selection, loading, alerts and errors")

for _, colorMode in { "monochrome", "colored" } do
    local polling = runtime()
    local widget = runtime(polling.shared)
    polling.require("./service.luau")
    widget.config.color_mode = colorMode
    widget.require("./widget.luau")
    polling.update()
    polling.flush()
    widget.update()
    assert(widget.color == "on_surface" and widget.glyphColor == "on_surface")
    widget.emit("selectedLocation", oblast)
    assert(widget.color == "on_surface" and widget.glyphColor == "on_surface")
    local scenarios = {
        { response = data, color = "#ef4444" },
        { response = { oblasts = {}, raions = { data.raions[1] } }, color = "#facc15" },
        { response = { oblasts = {}, raions = {} }, color = "#22c55e" },
    }
    for index, scenario in scenarios do
        if index > 1 then
            polling.update()
            polling.flush()
            widget.update()
        end
        widget.jsonValues.response = scenario.response
        polling.requests[index]({ ok = true, status = 200, body = "response" })
        polling.flush()
        local expected = colorMode == "colored" and scenario.color or "on_surface"
        assert(widget.color == expected and widget.glyphColor == expected)
    end
    polling.update()
    polling.flush()
    widget.update()
    polling.requests[4]({ ok = false, status = 0 })
    polling.flush()
    assert(
        widget.color == "on_surface" and widget.glyphColor == "on_surface",
        "errors must clear status colors"
    )
    widget.emit("selectedLocation", nil)
    assert(widget.color == "on_surface" and widget.glyphColor == "on_surface")
end
print("PASS widget status colors and theme fallback")

local view = env.require("./ui/status-view.luau")
local tree = view.renderStatusView(city, { location = city, loading = true })
assert(tree.children[4].children[2].props.text == "Отримання даних…")
print("PASS loading view")
