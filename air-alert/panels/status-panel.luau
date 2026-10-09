--!strict
local alertState = require("../alerts/state.luau")
local catalog = require("../locations/catalog.luau")
local store = require("../locations/store.luau")
local navigation = require("./navigation.luau")
local presentation = require("../ui/presentation.luau")
local displayTime = require("../ui/time.luau")

local selected: catalog.Location? = nil
local current: alertState.State? = nil
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
    if state.kind == "alert" then
        table.insert(children, detailRow(noctalia.tr("label.level"), view.detail))
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.since"),
                displayTime.formatKyivTimestamp(state.since) or noctalia.tr("time.unavailable")
            )
        )
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.duration"),
                displayTime.formatDuration(state.since) or noctalia.tr("time.unavailable")
            )
        )
        if state.reasons and #state.reasons > 0 then
            table.insert(
                children,
                ui.label({ text = noctalia.tr("label.reasons"), fontSize = 16, fontWeight = "bold" })
            )
            for _, reason in ipairs(state.reasons) do
                local reasonChildren: { UiNode } = {}
                local glyph = presentation.glyphForReason(reason)
                if glyph then
                    table.insert(reasonChildren, ui.glyph({ name = glyph, size = 20 }))
                end
                table.insert(
                    reasonChildren,
                    ui.label({ text = reason, maxLines = 3, color = "on_surface_variant" })
                )
                table.insert(
                    children,
                    ui.row(
                        { gap = 12, align = "center", paddingH = 12, paddingV = 4 },
                        reasonChildren
                    )
                )
            end
        end
    elseif state.kind == "error" then
        table.insert(
            children,
            ui.label({ text = view.detail, color = "on_surface_variant", maxLines = 2 })
        )
    end
    if (state.kind == "alert" or state.kind == "clear") and state.updatedAt then
        table.insert(children, ui.separator({}))
        table.insert(
            children,
            detailRow(
                noctalia.tr("label.updated"),
                displayTime.formatKyivTimestamp(state.updatedAt) or noctalia.tr("time.unavailable")
            )
        )
    end
    panel.render(ui.column({ flexGrow = 1, gap = 10 }, {
        ui.scroll({ flexGrow = 1 }, { ui.column({ gap = 8 }, children) }),
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
        }),
    }))
end

local function onOpen(): ()
    isOpen = true
    selected = store.load()
    current = noctalia.state.get(alertState.key)
    render()
end

local function onClose(): ()
    isOpen = false
end

local function update(): ()
    render()
end

noctalia.state.watch(alertState.key, function(state: alertState.State): ()
    current = state
    render()
end)

noctalia.state.watch(store.stateKey, function(key: string?): ()
    selected = catalog.find(key)
    current = nil
    render()
end)

return { onOpen = onOpen, onClose = onClose, update = update }
