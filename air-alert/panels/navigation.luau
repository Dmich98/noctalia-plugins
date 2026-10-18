--!strict

export type Request = { owner: string, panelId: string }

local stateKey = "panelRequest"
local ownerKey = "panelOwner"

local function fullId(panelId: string): string
    local suffix = noctalia.getConfig("panel_placement") == "attached" and "-attached" or ""
    return "dmich/air-alert:" .. panelId .. suffix
end

local function open(panelId: string): ()
    local targetId = fullId(panelId)
    local owner: string? = noctalia.state.get(ownerKey)
    if owner then
        noctalia.state.set(stateKey, { owner = owner, panelId = targetId })
    else
        noctalia.togglePanel(targetId)
    end
end

return { stateKey = stateKey, ownerKey = ownerKey, fullId = fullId, open = open }
