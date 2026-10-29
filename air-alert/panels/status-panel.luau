--!strict
local alertState = require("../alerts/state.luau")
local threatState = require("../alerts/threat-state.luau")
local threatPresentation = require("../ui/threat-presentation.luau")
local catalog = require("../locations/catalog.luau")
local store = require("../locations/store.luau")
local navigation = require("./navigation.luau")
local presentation = require("../ui/presentation.luau")
local displayTime = require("../ui/time.luau")

local selected: catalog.Location? = nil
local current: alertState.State? = nil
local currentThreats: threatState.State? = nil
local isOpen = false

local function openSource(): ()
    if not noctalia.runAsync("xdg-open https://neptun.in.ua/") then
        noctalia.log("Could not open NEPTUN website")
    end
end

local function detailRow(label: string, value: string): UiNode
    return ui.row({ justify = "space_between", gap = 12 }, {
        ui.label({ text = label, color = "on_surface_variant" }),
        ui.label({ text = value, textAlign = "end" }),
    })
end

local function render(): ()
    if not isOpen then
        return
    end
    local location = selected
    if not location then
        navigation.open("location-picker")
        return
    end
    local state = alertState.forLocation(current, location.key)
    local view = presentation.forState(state)
    local children: { UiNode } = {
        ui.label({
            text = catalog.displayName(location),
            fontSize = 20,
            fontWeight = "bold",
            maxLines = 2,
        }),
        ui.separator({}),
        ui.row({ gap = 10, align = "center", paddingV = 12 }, {
            ui.glyph({ name = view.glyph, size = 28, color = view.color }),
            ui.label({ text = view.text, fontSize = 20, fontWeight = "bold", color = view.color }),
        }),
    }
    local details: alertState.LastKnown? = nil
    if state.kind == "stale" then
        table.insert(
            children,
            ui.label({
                text = noctalia.tr("label.last_known"),
                fontSize = 12,
                color = "on_surface_variant",
                maxLines = 2,
            })
        )
        table.insert(
            children,
            ui.label({ text = view.detail, color = "on_surface_variant", maxLines = 2 })
        )
        details = state.lastKnown
    elseif state.kind == "alert" then
        details = state
    end
    if details and details.kind == "alert" then
        table.insert(
            children,
            detailRow(noctalia.tr("label.level"), presentation.levelDetail(details.level))
        )
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.since"),
                displayTime.formatKyivTimestamp(details.since) or noctalia.tr("time.unavailable")
            )
        )
        if state.kind == "alert" then
            table.insert(
                children,
                detailRow(
                    noctalia.tr("label.duration"),
                    displayTime.formatDuration(state.since) or noctalia.tr("time.unavailable")
                )
            )
        end
    elseif state.kind == "error" then
        table.insert(
            children,
            ui.label({ text = view.detail, color = "on_surface_variant", maxLines = 2 })
        )
    end
    local targets = threatState.forLocation(currentThreats, location.key)
    local threatTitle = noctalia.tr("threat.panel_title")
    if targets.kind == "current" then
        local substitutions: { [string]: string | number | boolean } = { count = #targets.threats }
        threatTitle = noctalia.tr("threat.panel_title_count", substitutions)
    end
    table.insert(
        children,
        ui.label({
            key = "current-threats-title",
            text = threatTitle,
            fontSize = 16,
            fontWeight = "bold",
        })
    )
    table.insert(children, ui.separator({ key = "current-threats-divider" }))
    local threatChildren: { UiNode } = {}
    if targets.kind == "current" and #targets.threats > 0 then
        for index, threat in ipairs(targets.threats) do
            local lines = threatPresentation.details(threat)
            table.insert(
                threatChildren,
                ui.column({ gap = 2 }, {
                    ui.label({
                        key = "current-threat-title:" .. threat.id,
                        text = lines[1],
                        fontWeight = "bold",
                        maxLines = 2,
                    }),
                    ui.label({
                        key = "current-threat:" .. threat.id,
                        text = table.concat(lines, "\n", 2),
                        maxLines = 5,
                        color = "on_surface_variant",
                    }),
                })
            )
            if index < #targets.threats then
                table.insert(threatChildren, ui.separator({}))
            end
        end
    else
        local message = "threat.panel_loading"
        if targets.kind == "current" then
            message = "threat.panel_empty"
        elseif targets.kind == "unavailable" then
            message = "threat.panel_unavailable"
        end
        table.insert(
            threatChildren,
            ui.label({
                key = "current-threats-status",
                text = noctalia.tr(message),
                maxLines = 3,
                color = "on_surface_variant",
            })
        )
    end
    table.insert(
        children,
        ui.scroll({ key = "current-threats-scroll", flexGrow = 1 }, {
            ui.column({ gap = 8 }, threatChildren),
        })
    )
    if
        (state.kind == "alert" or state.kind == "clear" or state.kind == "stale")
        and state.updatedAt
    then
        table.insert(children, ui.separator({}))
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.updated"),
                displayTime.formatKyivTimestamp(state.updatedAt) or noctalia.tr("time.unavailable")
            )
        )
    end
    table.insert(
        children,
        ui.row({ gap = 4, align = "center" }, {
            ui.label({
                text = noctalia.tr("label.source"),
                fontSize = 12,
                color = "on_surface_variant",
            }),
            ui.button({
                key = "source-link",
                text = "NEPTUN",
                glyph = "external-link",
                fontSize = 12,
                variant = "ghost",
                controlSize = "sm",
                tooltip = "https://neptun.in.ua/",
                onClick = openSource,
            }),
        })
    )
    panel.render(ui.column({ flexGrow = 1, gap = 8 }, children))
end

local function onOpen(): ()
    isOpen = true
    selected = store.load()
    current = noctalia.state.get(alertState.key)
    currentThreats = noctalia.state.get(threatState.key)
    render()
end

local function onClose(): ()
    isOpen = false
    -- Noctalia restores the retained tree before onOpen; start content sizing from an empty tree.
    panel.render(ui.column({}))
end

local function update(): ()
    render()
end

noctalia.state.watch(alertState.key, function(state: alertState.State): ()
    current = state
    render()
end)

noctalia.state.watch(threatState.key, function(state: threatState.State): ()
    currentThreats = state
    render()
end)

noctalia.state.watch(store.stateKey, function(key: string?): ()
    selected = catalog.find(key)
    current = noctalia.state.get(alertState.key)
    currentThreats = noctalia.state.get(threatState.key)
    render()
end)

return { onOpen = onOpen, onClose = onClose, update = update }
