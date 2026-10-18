--!nocheck

local NOW = 1792281600
local cases = {}
for _, case in ipairs(wsFixtures.threats) do
    cases[case.name] = case.raw
end
local function createService()
    local service = runtime()
    service.now = NOW
    service.files["/data/config.json"] = "saved"
    service.jsonValues.saved = { locationKey = "raion:бориспільський" }
    for raw, value in pairs(wsJsonValues) do
        service.jsonValues[raw] = value
    end
    service.require("./service.luau")
    service.update()
    return service
end
local function push(service, name)
    service.streams[1].onLine(assert(cases[name], name))
    service.flush()
end
local function openPanel(service)
    local panel = runtime(service.shared)
    panel.now = service.now
    panel.require("./status-panel-entry.luau")
    panel.onOpen()
    return panel
end
local function node(panel, key)
    return findNode(panel.tree, function(child)
        return child.props and child.props.key == key
    end)
end
local function target(panel, id)
    return node(panel, "current-threat:" .. id)
end
local service = createService()
local panel = openPanel(service)
local other = openPanel(service)
assert(service.values.currentThreats.kind == "loading")
assert(node(panel, "current-threats-status").props.text == panel.noctalia.tr("threat.panel_loading"))
push(service, "snapshot")
assert(service.values.currentThreats.kind == "current" and #service.values.currentThreats.threats == 1)
assert(target(panel, "baseline-local") and target(other, "baseline-local"))
assert(not target(panel, "baseline-outside"))
assert(#service.notifications == 0, "snapshot targets are visible without new-target notifications")
push(service, "empty-alerts")
assert(service.values.alertStatus.kind == "clear" and target(panel, "baseline-local"))
push(service, "local")
assert(target(panel, "new-local").props.text == "• Бориспіль\n• БпЛА курсом на Бориспіль")
local title = node(panel, "current-threat-title:new-local").props
assert(title.text == "Шахед ×2" and title.fontWeight == "bold")
assert(node(panel, "current-threats-title").props.text == "Загрози · 2")
local scroll = assert(node(panel, "current-threats-scroll"))
assert(scroll.kind == "scroll" and scroll.props.flexGrow == 1 and scroll.props.height == 240)
assert(node(panel, "current-threats-divider").kind == "separator")
assert(findNode(scroll, function(child)
    return child.props and child.props.key == "current-threat:new-local"
end))
assert(not findNode(scroll, function(child)
    return child.props and (child.props.key == "current-threats-title"
        or child.props.key == "source-link"
        or child.props.text == "Бориспільський район · Київська область")
end), "header and footer must stay outside the threat scroller")
local separators = 0
findNode(scroll, function(child)
    if child.kind == "separator" then separators += 1 end
    return false
end)
assert(separators == 1, "two threats have only the separator between them")
push(service, "update-local")
assert(target(panel, "new-local").props.text:find("Гнідин", 1, true))
assert(not target(panel, "new-local").props.text:find("°", 1, true))
assert(target(panel, "new-local").props.text == target(other, "new-local").props.text)
local unchanged = service.values.currentThreats
push(service, "update-local")
service.update()
assert(service.values.currentThreats == unchanged, "unchanged target lists must not republish every tick")
push(service, "other-district")
assert(not target(panel, "other-district"))
push(service, "broad")
assert(target(panel, "broad").props.text:find("Київська область", 1, true))
assert(not target(panel, "broad").props.text:find("район не уточнено", 1, true))
push(service, "advisory")
assert(node(panel, "current-threat-title:advisory").props.text:find("Спостереження", 1, true))
for _, name in ipairs({ "old", "future", "stale", "resolved", "no-time", "no-status", "unknown-status" }) do
    push(service, name)
    assert(not target(panel, name), name)
end
push(service, "stale-known")
assert(not target(panel, "new-local"))
push(service, "resolved-known")
assert(not target(panel, "new-local"))
push(service, "local")
assert(target(panel, "new-local"))
push(service, "remove")
assert(not target(panel, "new-local"), "removed targets disappear from an already open panel")
assert(not findNode(panel.tree, function(child)
    return child.kind == "label" and child.props.text == "Причини"
end), "static official reasons are replaced by the current stream section")
print("PASS live panel snapshots, updates, removal, source flags and independent siren status")

local catalog = service.require("./locations/catalog.luau")
local store = service.require("./locations/store.luau")
assert(store.save(catalog.find("raion:львівський")))
service.flush()
assert(service.values.currentThreats.locationKey == "raion:львівський")
assert(target(panel, "baseline-outside") and not target(panel, "baseline-local"))
assert(target(other, "baseline-outside") and not target(other, "advisory"))
assert(store.save(catalog.find("raion:бориспільський")))
service.flush()
assert(target(panel, "baseline-local") and not target(panel, "baseline-outside"))
assert(service.streamAttempts == 1 and panel.streamAttempts == 0 and other.streamAttempts == 0)
assert(#service.requests == 0 and #panel.requests == 0 and #other.requests == 0)
panel.onClose()
local closedTree = panel.tree
push(service, "empty-snapshot")
assert(panel.tree == closedTree, "closed panels do not render in response to target updates")
panel.onOpen()
assert(not target(panel, "baseline-local"))
assert(node(panel, "current-threats-status").props.text == panel.noctalia.tr("threat.panel_empty"))
local threatState = panel.require("./alerts/threat-state.luau")
assert(threatState.forLocation({ kind = "current", locationKey = "other", threats = {} }, "selected").kind == "loading")
print("PASS panel location changes, multiple panels, closed/reopened panel and scope guards")

local silent = createService()
local silentPanel = openPanel(silent)
push(silent, "snapshot")
assert(target(silentPanel, "baseline-local"))
silent.now = NOW + 45
silent.update()
silent.flush()
assert(silent.values.currentThreats.kind == "unavailable")
assert(not target(silentPanel, "baseline-local"))
assert(node(silentPanel, "current-threats-status").props.text == silentPanel.noctalia.tr("threat.panel_unavailable"))
push(silent, "local")
assert(silent.values.currentThreats.kind == "unavailable", "upserts alone cannot restore lost snapshot synchronization")
push(silent, "snapshot")
assert(silent.values.currentThreats.kind == "current" and target(silentPanel, "baseline-local"))
print("PASS unavailable stream hides outdated targets until a new threat snapshot")

local expiring = createService()
local expiringPanel = openPanel(expiring)
push(expiring, "snapshot")
local heartbeat
for _, raw in ipairs(wsFixtures["session-1"]) do
    if assert(expiring.require("./alerts/events.luau").decode(raw)).type == "heartbeat" then
        heartbeat = raw
        break
    end
end
for age = 15, 420, 15 do
    expiring.now = NOW + age
    expiring.streams[1].onLine(heartbeat)
    expiring.update()
    expiring.flush()
end
assert(target(expiringPanel, "baseline-local"), "a seven-minute-old active report is still within the policy")
expiring.now = NOW + 421
expiring.update()
expiring.flush()
assert(expiring.values.currentThreats.kind == "current")
assert(#expiring.values.currentThreats.threats == 0 and not target(expiringPanel, "baseline-local"))
assert(node(expiringPanel, "current-threats-status").props.text == expiringPanel.noctalia.tr("threat.panel_empty"))
assert(expiring.values.alertStatus.kind == "error", "threat and official-alert synchronization remain independent")
print("PASS local expiry removes targets from a healthy stream without waiting for another target event")

local failed = runtime()
failed.files["/data/config.json"] = "saved"
failed.jsonValues.saved = { locationKey = "київська" }
failed.executables = {}
failed.require("./service.luau")
failed.update()
assert(failed.values.currentThreats.kind == "unavailable")
local failedPanel = openPanel(failed)
assert(node(failedPanel, "current-threats-status").props.text == failedPanel.noctalia.tr("threat.panel_unavailable"))
assert(failed.streamAttempts == 0)
print("PASS startup failures do not appear as an empty current threat list")
