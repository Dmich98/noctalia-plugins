--!strict
local catalog = require("../locations/catalog.luau")
local store = require("../locations/store.luau")
local geolocation = require("../locations/geolocation.luau")
local navigation = require("./navigation.luau")

local selected: catalog.Location? = nil
local saveError = false
local locating = false
local geoMessage: string? = nil
local generation = 0
local isOpen = false
local render: () -> ()

local function cancelLookup(): ()
    generation += 1
    locating = false
    geoMessage = nil
end

local function choose(location: catalog.Location?): ()
    cancelLookup()
    selected = location
    saveError = false
    render()
end

local function save(): ()
    local location = selected
    if not location then
        return
    end
    cancelLookup()
    local saved, err = store.save(location)
    if not saved then
        if err then
            noctalia.log(err)
        end
        saveError = true
        render()
        return
    end
    navigation.open("alert-details")
end

local function locate(): ()
    if locating then
        return
    end
    cancelLookup()
    locating = true
    saveError = false
    local requestGeneration = generation
    render()
    geolocation.locate(function(location: catalog.Location?, err: geolocation.ErrorCode?): ()
        if not isOpen or generation ~= requestGeneration then
            return
        end
        locating = false
        if location then
            selected = location
            geoMessage = "location.geo_found"
        else
            geoMessage = "location.geo_" .. (err or "invalid")
        end
        render()
    end)
end

render = function(): ()
    if not isOpen then
        return
    end
    local options = { noctalia.tr("location.choose") }
    local selectedIndex = 0
    local oblastKey = selected and (selected.oblastKey or selected.key)
    for index, location in ipairs(catalog.all) do
        table.insert(options, catalog.displayName(location))
        if oblastKey == location.key then
            selectedIndex = index
        end
    end
    local children: { UiNode } = {
        ui.label({
            text = noctalia.tr("panel.location_title"),
            fontSize = 20,
            fontWeight = "bold",
        }),
        ui.button({
            key = "geolocate",
            text = noctalia.tr(locating and "location.geo_loading" or "location.geolocate"),
            enabled = not locating,
            controlSize = "sm",
            onClick = locate,
        }),
        ui.label({ text = noctalia.tr("label.location"), color = "on_surface_variant" }),
        ui.select({
            key = "location",
            options = options,
            selectedIndex = selectedIndex,
            controlSize = "sm",
            onChange = function(index: string): ()
                choose(catalog.all[tonumber(index) or 0])
            end,
        }),
    }
    local raions: { catalog.Location } = {}
    local districtOptions = { noctalia.tr("location.whole_region") }
    local districtIndex = 0
    for _, location in ipairs(catalog.raions) do
        if location.oblastKey == oblastKey then
            table.insert(raions, location)
            table.insert(districtOptions, location.name)
            if selected and selected.key == location.key then
                districtIndex = #raions
            end
        end
    end
    if #raions > 0 then
        table.insert(
            children,
            ui.select({
                key = "district",
                options = districtOptions,
                selectedIndex = districtIndex,
                controlSize = "sm",
                onChange = function(index: string): ()
                    local number = tonumber(index)
                    if not number then
                        return
                    end
                    choose(number == 0 and catalog.find(oblastKey) or raions[number])
                end,
            })
        )
    end
    table.insert(
        children,
        ui.label({
            text = noctalia.tr(geoMessage or "location.geo_hint"),
            color = "on_surface_variant",
            maxLines = 4,
        })
    )
    if saveError then
        table.insert(children, ui.label({ text = noctalia.tr("error.save"), color = "error" }))
    end
    table.insert(
        children,
        ui.button({
            key = "save-location",
            text = noctalia.tr("location.save"),
            enabled = selected ~= nil and not locating,
            controlSize = "sm",
            onClick = save,
        })
    )
    panel.render(ui.column({ gap = 8 }, children))
end

local function onOpen(): ()
    cancelLookup()
    isOpen = true
    selected = store.load()
    saveError = false
    render()
end

local function onClose(): ()
    isOpen = false
    cancelLookup()
end

noctalia.state.watch(store.stateKey, function(key: string?): ()
    cancelLookup()
    selected = catalog.find(key)
    saveError = false
    render()
end)

return { onOpen = onOpen, onClose = onClose }
