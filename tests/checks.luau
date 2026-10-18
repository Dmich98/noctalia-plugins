--!nocheck

local function send(env, name)
    local raw
    for _, group in ipairs({ wsFixtures.service, wsFixtures.projection, wsFixtures.cases }) do
        for _, case in ipairs(group) do
            if case.name == name then
                raw = case.raw
            end
        end
    end
    assert(raw, name)
    for json, value in pairs(wsJsonValues) do
        env.jsonValues[json] = value
    end
    assert(env.streams[1]).onLine(raw)
end

local function findNode(node, matches)
    if matches(node) then
        return node
    end
    for _, child in ipairs(node.children or {}) do
        local found = findNode(child, matches)
        if found then
            return found
        end
    end
    return nil
end

local function tooltipValue(tooltip, key)
    for _, row in ipairs(tooltip) do
        if row.key == key then
            return row.value
        end
    end
    return nil
end

local env = runtime()
local catalog = env.require("./locations/catalog.luau")
local alertTime = env.require("./alerts/time.luau")
local displayTime = env.require("./ui/time.luau")

assert(#catalog.all == 27)
assert(catalog.find("м. київ") ~= nil and catalog.find("київська") ~= nil)
assert(catalog.find("unsupported") == nil)
assert(alertTime.keepValid("2026-10-09T15:56:37.318472794Z") ~= nil)
assert(alertTime.keepValid("2024-02-29T12:00:00+02:00") ~= nil)
assert(alertTime.keepValid("2026-02-29T12:00:00Z") == nil)
assert(alertTime.keepValid("2026-10-09T15:56:37") == nil)
assert(alertTime.toUnixSeconds("2026-10-09T15:56:37.318472794Z") == 1791561397)
assert(alertTime.toUnixSeconds("2024-02-29T12:00:00+02:00") == 1709200800)
assert(alertTime.toUnixSeconds("2026-02-29T12:00:00Z") == nil)
local kyivTimes = {
    [1768516200] = "16.01.2026 00:30",
    [1774744200] = "29.03.2026 02:30",
    [1774747800] = "29.03.2026 04:30",
    [1784151000] = "16.07.2026 00:30",
    [1792888200] = "25.10.2026 03:30",
    [1792891800] = "25.10.2026 03:30",
}
env.noctalia.formatTime = function(pattern, seconds, zone)
    assert(pattern == "%d.%m.%Y %H:%M" and zone == "Europe/Kyiv")
    return assert(kyivTimes[seconds])
end
for timestamp, formatted in pairs({
    ["2026-01-15T22:30:00Z"] = "16.01.2026 00:30",
    ["2026-03-29T00:30:00Z"] = "29.03.2026 02:30",
    ["2026-03-29T01:30:00Z"] = "29.03.2026 04:30",
    ["2026-07-15T21:30:00Z"] = "16.07.2026 00:30",
    ["2026-10-25T00:30:00Z"] = "25.10.2026 03:30",
    ["2026-10-25T01:30:00Z"] = "25.10.2026 03:30",
}) do
    assert(displayTime.formatKyivTimestamp(timestamp) == formatted)
end
assert(displayTime.formatKyivTimestamp("2026-02-29T12:00:00Z") == nil)
assert(displayTime.formatDuration(nil) == nil)
env.now = 1791553367
assert(displayTime.formatDuration("2026-10-09T13:42:48Z") == nil)
env.now = 1791553368
assert(displayTime.formatDuration("2026-10-09T13:42:48Z") == "0 год 0 хв")
env.now = 1791553427
assert(displayTime.formatDuration("2026-10-09T13:42:48Z") == "0 год 0 хв")
env.now = 1791553428
assert(displayTime.formatDuration("2026-10-09T13:42:48Z") == "0 год 1 хв")
env.now = 1791557033
assert(displayTime.formatDuration("2026-10-09T13:42:48Z") == "1 год 1 хв")

print("PASS catalog and time validation")

env = runtime()
local store = env.require("./locations/store.luau")
env.files["/data/config.json"] = "previous"
for _, failure in ipairs({ "failWrite", "failRename" }) do
    env[failure] = true
    assert(not store.save(catalog.find("м. київ")))
    assert(env.files["/data/config.json"] == "previous")
    assert(env.files["/data/config.json.tmp"] == nil)
    assert(env.values.selectedLocation == nil)
    env[failure] = false
end
env.jsonValues.previous = { locationKey = "unsupported" }
assert(store.load() == nil)
assert(store.save(catalog.find("м. київ")))
assert(store.load().key == "м. київ")
assert(env.values.selectedLocation == "м. київ")
print("PASS safe persistence and catalog validation")

local service = runtime()
local first = runtime(service.shared)
local second = runtime(service.shared)
local picker = runtime(service.shared)
local details = runtime(service.shared)
service.require("./service.luau")
first.require("./widget.luau")
second.require("./widget.luau")
picker.require("./location-panel-entry.luau")
details.require("./status-panel-entry.luau")
service.update()
service.flush()
assert(service.values.alertStatus.kind == "unconfigured")
assert(#service.requests == 0 and service.streamAttempts == 0)
first.update()
assert(first.text == "Оберіть область")
assert(first.glyph == "brand-flightradar24")
first.onClick()
assert(first.panels[1] == "dmich/air-alert:location-picker")
picker.onOpen()
assert(findNode(picker.tree, function(node)
    return node.props and node.props.text == "Оберіть регіон"
end) ~= nil)
assert(findNode(picker.tree, function(node)
    return node.kind == "label" and node.props.text == "Регіон"
end) ~= nil)
local select = assert(findNode(picker.tree, function(node)
    return node.props and node.props.key == "location"
end)).props
local index = assert(table.find(select.options, "Київська область")) - 1
select.onChange(tostring(index))
assert(service.values.selectedLocation == nil, "draft selection must not publish before saving")
assert(findNode(picker.tree, function(node)
    return node.props and node.props.key == "save-location"
end)).props.onClick()
service.flush()
assert(service.streamAttempts == 1 and service.values.alertStatus.kind == "loading")
assert(first.streamAttempts == 0 and second.streamAttempts == 0)
assert(first.text == second.text and first.text == "Отримання даних…")
assert(first.panels[2] == "dmich/air-alert:alert-details")
assert(#second.panels == 0)
details.onOpen()
assert(details.secondTicks == nil)
assert(findNode(details.tree, function(node)
    return node.props and node.props.text == "Стан повітряної тривоги"
end) == nil)
assert(findNode(details.tree, function(node)
    return node.kind == "label"
        and node.props.text == "Київська область"
        and node.props.fontWeight == "bold"
        and node.props.fontSize == 20
end) ~= nil)
assert(findNode(details.tree, function(node)
    return node.kind == "scroll"
end) ~= nil)
local sourceButton = assert(findNode(details.tree, function(node)
    return node.kind == "button" and node.props.key == "source-link"
end)).props
assert(sourceButton.text == "NEPTUN" and sourceButton.glyph == "external-link")
sourceButton.onClick()
assert(details.commands[1] == "xdg-open https://neptun.in.ua/")
assert(findNode(details.tree, function(node)
    return node.kind == "button" and node.props.key ~= "source-link"
end) == nil)
service.update()
assert(service.streamAttempts == 1, "ticks must not start additional streams")
print("PASS initial selection, loading and shared service")

send(service, "other-raion")
service.flush()
assert(service.values.alertStatus.kind == "clear", "another oblast's raion must not match")
assert(details.secondTicks == nil)
assert(service.values.alertStatus.updatedAt == "2026-10-09T15:56:37Z")
assert(#service.notifications == 0, "the first confirmed status is a baseline")
assert(first.glyph == "brand-flightradar24")
assert(first.glyphColor == "on_surface" and first.color == "on_surface")
assert(service.values.alertStatus.highlightUntilMs == nil)
first.config.color_mode = "colored"
first.update()
assert(first.glyphColor == "#22c55e" and first.color == "#22c55e")
assert(first.updateInterval == 30000)
first.config.color_mode = "monochrome"
first.update()
assert(first.glyphColor == "on_surface" and first.color == "on_surface")
assert(tooltipValue(first.tooltip, "Регіон") == "Київська область")
assert(tooltipValue(first.tooltip, "Статус") == "Тривоги немає")
assert(tooltipValue(first.tooltip, "Рівень") == nil)
assert(findNode(details.tree, function(node)
    return node.kind == "label" and node.props.text == "Причини"
end) == nil)
assert(findNode(details.tree, function(node)
    return node.kind == "label" and node.props.text == "09.10.2026 18:56"
end) ~= nil)

service.update()
assert(service.values.alertStatus.kind == "clear" and first.glyphColor == "on_surface")
details.now = 1791561480
send(service, "yellow-metadata")
service.flush()
local alert = service.values.alertStatus
assert(alert.kind == "alert" and alert.level == "yellow")
assert(details.secondTicks == nil)
assert(#service.notifications == 1)
assert(service.notifications[1].summary == "Київська область")
assert(
    service.notifications[1].body
        == "Повітряна тривога · Жовтий рівень\nПричини: Дрони\nОголошено: 09.10.2026 16:42"
)
assert(service.notifications[1].urgency == "critical")
assert(service.notifications[1].timeout_ms == 15000)
assert(service.notifications[1].icon == "brand-flightradar24")
assert(
    service.commands[1][1] == "noctalia"
        and service.commands[1][2] == "msg"
        and service.commands[1][3] == "notification-show"
)
assert(alert.since == "2026-10-09T13:42:48Z" and alert.reasons[1] == "Дрони")
assert(first.glyph == "brand-flightradar24")
assert(first.glyphColor == "#facc15" and first.color == "on_surface")
assert(tooltipValue(first.tooltip, "Статус") == "Повітряна тривога")
assert(tooltipValue(first.tooltip, "Рівень") == "Жовтий рівень")
assert(tooltipValue(first.tooltip, "Оголошено") == "09.10.2026 16:42")
assert(findNode(details.tree, function(node)
    return node.props and node.props.text == "Повітряна тривога"
end) ~= nil)
assert(findNode(details.tree, function(node)
    return node.kind == "glyph" and node.props.name == "alert-triangle"
end) ~= nil)
assert(findNode(details.tree, function(node)
    return node.kind == "label"
        and node.props.key == "current-threats-title"
        and node.props.text == "Актуальні загрози"
end))
assert(findNode(details.tree, function(node)
    return node.kind == "label"
        and node.props.key == "current-threats-status"
        and node.props.text == "Очікування даних про загрози…"
end), "official reasons do not substitute for the independent threat stream")
assert(findNode(details.tree, function(node)
    return node.kind == "label"
        and node.props.text == "09.10.2026 16:42"
        and node.props.textAlign == "end"
end) ~= nil)
assert(findNode(details.tree, function(node)
    return node.kind == "label" and node.props.text == "Триває"
end) ~= nil)
assert(findNode(details.tree, function(node)
    return node.kind == "label" and node.props.text == "2 год 15 хв"
end) ~= nil)
details.now += 1
details.update()
assert(findNode(details.tree, function(node)
    return node.kind == "label" and node.props.text == "2 год 15 хв"
end) ~= nil)
details.now += 47
details.emit(details.require("./alerts/state.luau").key, alert)
assert(findNode(details.tree, function(node)
    return node.kind == "label" and node.props.text == "2 год 16 хв"
end) ~= nil)
assert(findNode(details.tree, function(node)
    return node.kind == "label" and node.props.text == "09.10.2026 18:57"
end) ~= nil)
assert(findNode(details.tree, function(node)
    return node.kind == "button" and node.props.key == "source-link"
end) ~= nil)
local presentation = details.require("./ui/presentation.luau")
assert(
    presentation.forState({ kind = "alert", locationKey = "київська", level = "red" }).glyph
        == "alert-triangle"
)
assert(presentation.glyphForReason("Ракети") == "rocket")
assert(
    presentation.glyphForReason("Ракетна загроза (червоний рівень)")
        == "rocket"
)
assert(
    presentation.glyphForReason("Дронова загроза (жовтий рівень)")
        == "drone"
)
assert(presentation.glyphForReason("Інша причина") == nil)

first.config.display_mode = "icon"
first.update()
assert(first.text == "")
first.config.display_mode = "location_status"
first.update()
assert(first.text == "Повітряна тривога · Київська область")
first.config.color_mode = "colored"
first.update()
assert(first.color == "#facc15" and first.glyphColor == "#facc15")
first.config.color_mode = "monochrome"
first.config.display_mode = "status"
first.update()
assert(first.text == "Повітряна тривога")
assert(first.color == "on_surface" and first.glyphColor == "#facc15")

service.update()
assert(service.values.alertStatus.kind == "alert" and first.glyphColor == "#facc15")
send(service, "unknown-level")
service.flush()
assert(service.values.alertStatus.kind == "alert" and service.values.alertStatus.level == "purple")
assert(details.secondTicks == nil)
assert(#service.notifications == 1, "level changes do not change the alert status")
assert(first.text:find("Невідомий рівень"))
assert(tooltipValue(first.tooltip, "Рівень") == "Невідомий рівень: purple")
assert(tooltipValue(first.tooltip, "Оголошено") == "Невідомо")
assert(first.color == "on_surface" and first.glyphColor == "on_surface_variant")

service.update()
assert(service.values.alertStatus.kind == "alert" and first.glyphColor == "on_surface_variant")
send(service, "malformed-json")
service.flush()
assert(service.values.alertStatus.kind == "alert" and service.values.alertStatus.level == "purple")
assert(#service.notifications == 1, "invalid events cannot change alert activity")
print("PASS current status, metadata and invalid-event isolation")

local serviceStore = service.require("./locations/store.luau")
assert(serviceStore.save(catalog.find("м. київ")))
service.flush()
assert(service.values.alertStatus.kind == "clear" and first.glyphColor == "on_surface")
assert(serviceStore.save(catalog.find("київська")))
service.flush()
assert(service.values.alertStatus.kind == "alert" and service.values.alertStatus.level == "purple")
assert(service.streamAttempts == 1 and #service.notifications == 1)
assert(tooltipValue(first.tooltip, "Регіон") == "Київська область")
print("PASS immediate region changes including A → B → A without stream restart")

service.now = 45
service.update()
service.flush()
assert(service.values.alertStatus.kind == "stale")
assert(first.glyphColor == "on_surface_variant")
assert(tooltipValue(first.tooltip, "Рівень") == "Невідомий рівень: purple")
assert(#service.notifications == 1 and service.streamAttempts == 1)
send(service, "empty")
service.flush()
assert(service.values.alertStatus.kind == "clear" and #service.notifications == 2)
print("PASS silent stream becomes stale and a fresh baseline recovers")

second.config.display_mode = "icon"
second.update()
assert(
    second.text == ""
        and tooltipValue(second.tooltip, "Регіон") == "Київська область"
)
second.onRightClick()
assert(second.panels[1] == "dmich/air-alert:location-picker")
picker.onOpen()
local selectedPicker = assert(findNode(picker.tree, function(node)
    return node.props and node.props.key == "location"
end)).props
assert(selectedPicker.selectedIndex == index)
second.onClick()
assert(second.panels[2] == "dmich/air-alert:alert-details")
first.close()
assert(service.values.panelOwner ~= nil)
second.close()
assert(service.values.panelOwner == nil)
print("PASS icon mode and widget ownership")

local restarted = runtime()
restarted.files["/data/config.json"] = "saved"
restarted.jsonValues.saved =
    { locationKey = "м. київ", locationName = "old", locationType = "oblast" }
restarted.require("./service.luau")
restarted.update()
assert(restarted.streamAttempts == 1 and restarted.values.alertStatus.locationKey == "м. київ")
assert(restarted.files["/data/config.json"] == "saved")
print("PASS saved oblast starts loading on launch")

local notifying = runtime()
notifying.files["/data/config.json"] = "selected"
notifying.jsonValues.selected = { locationKey = "київська" }
local notifyingWidget = runtime(notifying.shared)
notifying.require("./service.luau")
notifyingWidget.require("./widget.luau")
notifying.update()
send(notifying, "red")
notifying.flush()
assert(#notifying.notifications == 0, "an active alert at startup is the baseline")
assert(notifyingWidget.glyphColor == "#ef4444")
notifying.update()
send(notifying, "yellow")
notifying.flush()
assert(#notifying.notifications == 0, "level changes do not notify")
notifying.update()
send(notifying, "snapshot-empty")
notifying.flush()
assert(#notifying.notifications == 0, "session boundaries do not notify")
notifying.update()
send(notifying, "empty")
notifying.flush()
assert(#notifying.notifications == 1)
assert(notifying.notifications[1].summary == "Київська область")
assert(notifying.notifications[1].body == "Тривоги немає")
assert(notifying.notifications[1].urgency == "normal")
assert(notifying.notifications[1].timeout_ms == 5000)
assert(notifying.notifications[1].icon == "brand-flightradar24")
assert(notifying.values.alertStatus.highlightUntilMs == 15000)
assert(notifyingWidget.glyphColor == "#22c55e")
assert(notifyingWidget.updateInterval == 15000)
notifyingWidget.config.color_mode = "colored"
notifyingWidget.update()
assert(notifyingWidget.color == "#22c55e" and notifyingWidget.glyphColor == "#22c55e")
assert(notifyingWidget.updateInterval == 30000)
notifyingWidget.now = 10
notifyingWidget.update()
assert(notifyingWidget.color == "#22c55e" and notifyingWidget.glyphColor == "#22c55e")
assert(notifyingWidget.updateInterval == 30000)
notifyingWidget.config.color_mode = "monochrome"
notifyingWidget.update()
assert(notifyingWidget.color == "on_surface")
assert(notifyingWidget.glyphColor == "#22c55e" and notifyingWidget.updateInterval == 5000)
local secondNotifyingWidget = runtime(notifying.shared)
secondNotifyingWidget.now = 10
secondNotifyingWidget.require("./widget.luau")
secondNotifyingWidget.update()
assert(secondNotifyingWidget.glyphColor == "#22c55e")
assert(secondNotifyingWidget.updateInterval == 5000)
notifying.now = 10
notifying.update()
send(notifying, "empty")
notifying.flush()
assert(#notifying.notifications == 1, "repeated clear results do not notify")
assert(notifying.values.alertStatus.highlightUntilMs == 15000)
assert(notifyingWidget.updateInterval == 5000, "a repeat does not restart the highlight")
notifyingWidget.now = 15
secondNotifyingWidget.now = 15
notifyingWidget.update()
secondNotifyingWidget.update()
assert(notifyingWidget.glyphColor == "on_surface")
assert(secondNotifyingWidget.glyphColor == "on_surface")
assert(notifyingWidget.updateInterval == 30000)
notifyingWidget.config.color_mode = "colored"
notifyingWidget.update()
assert(notifyingWidget.color == "#22c55e" and notifyingWidget.glyphColor == "#22c55e")
assert(notifyingWidget.updateInterval == 30000)
notifyingWidget.config.color_mode = "monochrome"
notifyingWidget.update()
assert(notifyingWidget.color == "on_surface" and notifyingWidget.glyphColor == "on_surface")
notifying.now = 15
notifying.update()
send(notifying, "red")
notifying.flush()
assert(#notifying.notifications == 2)
assert(
    notifying.notifications[2].body
        == "Повітряна тривога · Червоний рівень"
)
assert(notifying.notifications[2].urgency == "critical")
assert(notifying.notifications[2].timeout_ms == 15000)
assert(notifying.notifications[2].icon == "brand-flightradar24")
assert(notifyingWidget.glyphColor == "#ef4444")
assert(notifying.values.alertStatus.kind == "alert")
assert(notifying.require("./locations/store.luau").save(catalog.find("м. київ")))
notifying.flush()
assert(notifyingWidget.glyphColor == "on_surface")
send(notifying, "empty")
notifying.flush()
assert(notifying.values.alertStatus.highlightUntilMs == nil)
assert(notifyingWidget.glyphColor == "on_surface")
assert(#notifying.notifications == 2)
print("PASS alert transition notifications")

local unknownNotification = runtime()
unknownNotification.require("./notification.luau").send("Київська область", {
    kind = "alert",
    locationKey = "київська",
    level = "purple",
})
assert(
    unknownNotification.notifications[1].body
        == "Повітряна тривога · Невідомий рівень: purple"
)
assert(unknownNotification.notifications[1].urgency == "normal")
assert(#unknownNotification.commands == 1)

local raionService = runtime()
raionService.files["/data/config.json"] = "selected"
raionService.jsonValues.selected = { locationKey = "київська" }
raionService.require("./service.luau")
raionService.update()
send(raionService, "raions-only")
raionService.flush()
assert(raionService.values.alertStatus.kind == "alert")
assert(raionService.values.alertStatus.level == "red")
assert(#raionService.notifications == 0)
raionService.update()
send(raionService, "empty")
raionService.flush()
assert(raionService.values.alertStatus.kind == "clear")
assert(
    #raionService.notifications == 1
        and raionService.notifications[1].body == "Тривоги немає"
)
print("PASS raion-only alert and clear transition")

for _, checked in ipairs({
    service,
    first,
    second,
    picker,
    details,
    restarted,
    notifying,
    raionService,
}) do
    assert(#checked.requests == 0, "no HTTP calls in any entry")
end

for _, failure in ipairs({ "dependency", "stream" }) do
    local failed = runtime()
    local widget = runtime(failed.shared)
    failed.files["/data/config.json"] = "saved"
    failed.jsonValues.saved = { locationKey = "київська" }
    failed.executables.websocat = failure ~= "dependency"
    failed.rejectStream = failure == "stream"
    failed.require("./service.luau")
    widget.require("./widget.luau")
    failed.update()
    failed.flush()
    assert(failed.values.alertStatus.kind == "error" and failed.values.alertStatus.code == failure)
    assert(widget.glyphColor == "on_surface_variant")
    assert(
        tooltipValue(widget.tooltip, "Причина") == failed.noctalia.tr("error." .. failure)
    )
    failed.executables.websocat = true
    failed.rejectStream = false
    for _ = 1, 3 do
        failed.update()
    end
    assert(failed.require("./locations/store.luau").save(catalog.find("м. київ")))
    failed.flush()
    assert(failed.values.alertStatus.code == failure)
    assert(#failed.commandChecks == 1 and #failed.streams == 0 and #failed.notifications == 0)
end
print("PASS service launch failures remain visible without starting extra streams")

local waiting = runtime()
waiting.files["/data/config.json"] = "saved"
waiting.jsonValues.saved = { locationKey = "київська" }
waiting.require("./service.luau")
waiting.update()
send(waiting, "snapshot-one")
for _, raw in ipairs(wsFixtures["session-1"]) do
    local event = assert(waiting.require("./alerts/events.luau").decode(raw))
    if event.type == "heartbeat" then
        waiting.streams[1].onLine(raw)
    end
end
assert(waiting.values.alertStatus.kind == "loading" and #waiting.notifications == 0)
waiting.now = 44
waiting.update()
assert(waiting.values.alertStatus.kind == "loading")
send(waiting, "malformed-json")
waiting.now = 45
waiting.update()
assert(waiting.values.alertStatus.kind == "error")
assert(waiting.logs[#waiting.logs] == "Ignored invalid NEPTUN stream message: json")
send(waiting, "missing-level")
assert(waiting.values.alertStatus.kind == "alert" and waiting.values.alertStatus.level == nil)
assert(#waiting.notifications == 0, "the first official baseline still does not notify")
local unchanged = waiting.values.alertStatus
send(waiting, "missing-level")
assert(waiting.values.alertStatus == unchanged, "equivalent official sets do not republish state")
send(waiting, "snapshot-empty")
assert(waiting.values.alertStatus.kind == "stale" and #waiting.notifications == 0)
send(waiting, "missing-level")
assert(waiting.values.alertStatus.kind == "alert" and #waiting.notifications == 0)
waiting.now = 90
-- A heartbeat arriving before the next timer tick cannot conceal a long gap.
for _, raw in ipairs(wsFixtures["session-1"]) do
    local event = assert(waiting.require("./alerts/events.luau").decode(raw))
    if event.type == "heartbeat" then
        waiting.streams[1].onLine(raw)
    end
end
assert(waiting.values.alertStatus.kind == "stale")
assert(waiting.require("./locations/store.luau").save(catalog.find("м. київ")))
waiting.flush()
assert(waiting.values.alertStatus.kind == "stale")
send(waiting, "city-only")
assert(
    waiting.values.alertStatus.locationKey == "м. київ"
        and waiting.values.alertStatus.level == "yellow"
)
assert(#waiting.notifications == 0 and waiting.streamAttempts == 1)
send(waiting, "unmapped-territory")
assert(waiting.values.alertStatus.kind == "error" and waiting.values.alertStatus.code == "invalid")
assert(#waiting.notifications == 0)
print("PASS incomplete sync, malformed input, reconnect and heartbeat freshness gates")

-- Another runtime can publish the new projection before this runtime handles selection.
local reorderedWidget = runtime()
reorderedWidget.files["/data/config.json"] = "saved"
reorderedWidget.jsonValues.saved = { locationKey = "київська" }
local reorderedPanel = runtime(reorderedWidget.shared)
reorderedWidget.require("./widget.luau")
reorderedPanel.require("./status-panel-entry.luau")
reorderedPanel.onOpen()
reorderedWidget.emit(
    "alertStatus",
    { kind = "alert", locationKey = "м. київ", level = "yellow" }
)
reorderedWidget.emit("selectedLocation", "м. київ")
assert(
    reorderedWidget.text == "Повітряна тривога"
        and reorderedWidget.glyphColor == "#facc15"
)
assert(tooltipValue(reorderedWidget.tooltip, "Регіон") == "м. Київ")
assert(findNode(reorderedPanel.tree, function(node)
    return node.kind == "label" and node.props.text == "Жовтий рівень"
end) ~= nil)
print("PASS projection delivered before selection remains visible in widgets and panels")
