--!strict
--!nolint FunctionUnused

local statusPanel = require("./panels/status-panel.luau")

function onOpen(): ()
    statusPanel.onOpen()
end

function onClose(): ()
    statusPanel.onClose()
end

function update(): ()
    statusPanel.update()
end
