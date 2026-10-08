--!strict
--!nolint FunctionUnused

local locations = require("./locations/catalog.luau")
local locationStore = require("./locations/store.luau")
local panelNavigation = require("./panels/navigation.luau")

local catalog, catalogError = locations.loadLocations()
local selectedLocation: locations.Location? = nil
local saveError: string? = nil
local renderPicker: () -> ()

local function selectLocation(location: locations.Location): ()
    local saved, err = locationStore.saveLocation(location)
    if not saved then
        saveError = noctalia.tr("error.save")
        if err then
            noctalia.log(err)
        end
        renderPicker()
        return
    end
    panelNavigation.requestPanel("alert-details")
end

renderPicker = function(): ()
    local options = { noctalia.tr("location.choose") }
    local selectedIndex = 0
    for index, location in ipairs(catalog) do
        table.insert(options, locations.displayName(location))
        if
            selectedLocation
            and selectedLocation.locationKey == location.locationKey
            and selectedLocation.locationType == location.locationType
        then
            selectedIndex = index
        end
    end
    local children: { UiNode } = {
        ui.select({
            key = "location",
            options = options,
            selectedIndex = selectedIndex,
            enabled = #catalog > 0,
            controlSize = "sm",
            onChange = function(index: string)
                local location = catalog[tonumber(index) or 0]
                if location then
                    selectLocation(location)
                end
            end,
        }),
    }
    local err = saveError or (catalogError and noctalia.tr("error.catalog"))
    if err then
        table.insert(children, ui.label({ text = err, color = "error", maxLines = 1 }))
    end
    panel.render(ui.column({ gap = 8 }, children))
end

function onOpen(): ()
    selectedLocation = locationStore.loadLocation()
    saveError = nil
    renderPicker()
end
