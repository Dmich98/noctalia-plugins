--!nocheck

for _, case in ipairs({
    { value = "floating", suffix = "" },
    { value = "attached", suffix = "-attached" },
    { value = "unknown", suffix = "" },
    { suffix = "" },
}) do
    local env = runtime()
    env.config.panel_placement = case.value
    local navigation = env.require("./panels/navigation.luau")
    for _, id in ipairs({ "alert-details", "location-picker" }) do
        local expected = "dmich/air-alert:" .. id .. case.suffix
        assert(navigation.fullId(id) == expected)
        navigation.open(id)
        assert(env.panels[#env.panels] == expected, "ownerless navigation follows the common mode")
    end
end

local first = runtime()
first.config.panel_placement = "attached"
local second = runtime(first.shared)
local picker = runtime(first.shared)
-- All entry runtimes read the same plugin-scoped configuration in the host.
second.config, picker.config = first.config, first.config
first.require("./widget.luau")
second.require("./widget.luau")
picker.require("./location-panel-entry.luau")
first.onClick()
assert(first.panels[1] == "dmich/air-alert:location-picker-attached")
assert(#second.panels == 0)
picker.onOpen()
local function control(key)
    return assert(findNode(picker.tree, function(node)
        return node.props and node.props.key == key
    end)).props
end
local location = control("location")
location.onChange(tostring(assert(table.find(location.options, "Київська область")) - 1))
control("save-location").onClick()
picker.flush()
assert(first.panels[2] == "dmich/air-alert:alert-details-attached")
assert(#second.panels == 0, "panel transitions return to the owning widget")

second.onRightClick()
assert(second.panels[1] == "dmich/air-alert:location-picker-attached")
first.config.panel_placement = "floating"
control("save-location").onClick()
picker.flush()
assert(second.panels[2] == "dmich/air-alert:alert-details")
assert(#first.panels == 2, "changing mode preserves the most recent owner")
first.onRightClick()
assert(first.panels[3] == "dmich/air-alert:location-picker")
first.onClick()
assert(first.panels[4] == "dmich/air-alert:alert-details")
assert(first.streamAttempts == 0 and second.streamAttempts == 0 and picker.streamAttempts == 0)
print("PASS common panel mode, both panels, live setting changes, transitions and widget ownership")
