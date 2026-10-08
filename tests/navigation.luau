--!nocheck

do
    local polling = runtime()
    local first, second = runtime(polling.shared), runtime(polling.shared)
    local picker, details = runtime(polling.shared), runtime(polling.shared)
    polling.require("./service.luau")
    first.require("./widget.luau")
    second.require("./widget.luau")
    picker.require("./location-panel.luau")
    details.require("./status-panel.luau")
    polling.update()
    polling.flush()
    first.onClick()
    picker.onOpen()
    assert(#first.panels == 1 and #second.panels == 0)

    -- The real picker saves the selection; state.set must reach every subscriber.
    local options = picker.tree.children[1].props
    local index = table.find(options.options, "Київська область")
    assert(index ~= nil)
    options.onChange(tostring(index - 1))
    polling.flush()
    assert(#polling.requests == 1 and #first.requests == 0 and #second.requests == 0)
    assert(first.text == second.text and first.text:find("Отримання даних"))
    assert(#first.panels == 2 and first.panels[2] == "dmich/air-alert:alert-details")
    assert(#second.panels == 0, "the other widget must not toggle the panel")

    details.onOpen()
    polling.jsonValues.response = data
    polling.requests[1]({ ok = true, status = 200, body = "response" })
    polling.flush()
    assert(first.text == second.text and first.glyph == "alert-octagon")
    local statusTree = details.tree.children[1].children[1]
    assert(statusTree.children[4].children[2].props.text == "Повітряна тривога")
    first.update()
    second.update()
    polling.update()
    polling.update()
    assert(#polling.requests == 2, "all widgets share one in-flight poll")
    assert(#first.requests == 0 and #second.requests == 0)

    details.showPicker()
    polling.flush()
    assert(#first.panels == 3 and #second.panels == 0)
    second.onClick()
    details.showPicker()
    polling.flush()
    assert(#first.panels == 3 and #second.panels == 2, "panel ownership follows the clicked widget")
    first.close()
    assert(polling.values.panelOwner ~= nil, "closing another widget must not clear the owner")
    second.close()
    assert(polling.values.panelOwner == nil)
    details.showPicker()
    assert(
        details.panels[1] == "dmich/air-alert:location-picker",
        "navigation works without a widget"
    )
    print("PASS two widgets, saved selection, shared polling and panel ownership")
end

do
    local polling = runtime()
    polling.require("./service.luau")
    polling.emit("selectedLocation", oblast)
    polling.emit("selectedLocation", city)
    polling.emit("selectedLocation", oblast)
    assert(#polling.requests == 3)
    polling.jsonValues.latest = data
    polling.requests[3]({ ok = true, status = 200, body = "latest" })
    polling.flush()
    assert(polling.values.alertStatus.active == true)
    polling.jsonValues.older = { oblasts = {}, raions = {} }
    polling.requests[1]({ ok = true, status = 200, body = "older" })
    polling.requests[2]({ ok = false, status = 0 })
    polling.flush()
    assert(
        polling.values.alertStatus.active == true,
        "old requests cannot overwrite the latest state after switching back"
    )
    polling.update()
    assert(#polling.requests == 4, "old callbacks cannot block later polls")
    print("PASS request generations reject delayed responses after switching back")
end
