--!strict
--!nolint FunctionUnused

local locationPanel = require("./panels/location-panel.luau")

function onOpen(): ()
    locationPanel.onOpen()
end
