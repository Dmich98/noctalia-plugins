--!strict

local alertState = require("../alerts/state.luau")
local catalog = require("../locations/catalog.luau")
local presentation = require("./presentation.luau")

local function render(location: catalog.Location?, state: alertState.State?): ()
    local current = alertState.forLocation(state, location and location.key)
    local view = presentation.forState(current)
    local region = location and catalog.displayName(location)
    barWidget.setText(
        presentation.widgetText(noctalia.getConfig("display_mode"), view.text, region)
    )
    barWidget.setGlyph(presentation.widgetGlyph)
    local colored = noctalia.getConfig("color_mode") == "colored"
    barWidget.setColor(colored and view.color or "on_surface")
    local glyphColor = view.color
    local nextRenderMs = 30000
    if not colored and current.kind == "clear" then
        glyphColor = "on_surface"
        local remainingMs = (current.highlightUntilMs or 0) - noctalia.nowMs()
        if remainingMs > 0 then
            glyphColor = view.color
            nextRenderMs = remainingMs
        end
    end
    barWidget.setGlyphColor(glyphColor)
    barWidget.setTooltip(presentation.tooltipRows(region, current, view))
    noctalia.setUpdateInterval(nextRenderMs)
end

return { render = render }
