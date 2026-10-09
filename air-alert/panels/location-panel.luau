--!strict
local catalog = require("../locations/catalog.luau")
local store = require("../locations/store.luau")
local navigation = require("./navigation.luau")

local selected: catalog.Location? = nil
local saveError = false
local render: () -> ()

render = function(): ()
    local options = { noctalia.tr("location.choose") }
    local selectedIndex = 0
    for index, location in ipairs(catalog.all) do
        table.insert(options, catalog.displayName(location))
        if selected and selected.key == location.key then
            selectedIndex = index
        end
    end
    local children: { UiNode } = {
        ui.label({
            text = noctalia.tr("panel.location_title"),
            fontSize = 20,
            fontWeight = "bold",
        }),
        ui.label({ text = noctalia.tr("label.location"), color = "on_surface_variant" }),
        ui.select({
            key = "location",
            options = options,
            selectedIndex = selectedIndex,
            controlSize = "sm",
            onChange = function(index: string): ()
                local location = catalog.all[tonumber(index) or 0]
                if not location then
                    return
                end
                local saved, err = store.save(location)
                if not saved then
                    if err then
                        noctalia.log(err)
                    end
                    saveError = true
                    render()
                    return
                end
                selected = location
                saveError = false
                navigation.open("alert-details")
            end,
        }),
    }
    if saveError then
        table.insert(children, ui.label({ text = noctalia.tr("error.save"), color = "error" }))
    end
    panel.render(ui.column({ gap = 8 }, children))
end

local function onOpen(): ()
    selected = store.load()
    saveError = false
    render()
end

return { onOpen = onOpen }
