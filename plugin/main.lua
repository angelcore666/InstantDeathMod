-- basicaly default
local DEFAULTS = {
    enabled  = true,
    lethal   = 9.0,
    limbs    = 1.2,
    fade_in  = 0.0,
    black    = 5.0,
    fade_out = 0.5,
}

-- how dangerous a hit is on each body part (1.0 = as deadly as the head beacause this is the real world)
local VITAL = {
    ["Head"] = 1.0, ["Neck"] = 1.0, ["Spine"] = 0.9,
    ["Upper chest"] = 0.8, ["Chest"] = 0.8, ["Lower back"] = 0.7, ["Pelvis"] = 0.6,
    ["Left collarbone"] = 0.5, ["Right collarbone"] = 0.5,
}
local LIMB = {
    ["Left thigh"] = 0.35, ["Right thigh"] = 0.35,
    ["Left upper arm"] = 0.25, ["Right upper arm"] = 0.25,
    ["Left shin"] = 0.25, ["Right shin"] = 0.25,
    ["Left forearm"] = 0.2, ["Right forearm"] = 0.2,
    ["Left hand"] = 0.1, ["Right hand"] = 0.1,
}
local VEHICLE_FACTOR = 1.5
local BOARD_FACTOR = 0.5

local cfg = {}
for key, value in DEFAULTS do cfg[key] = value end

local function round(x, decimals)
    local m = 10 ^ decimals
    return math.floor(x * m + 0.5) / m
end

local function save(key)
    local v = cfg[key]
    if type(v) == "boolean" then v = if v then 1 else 0 end
    pcall(reskate.storage.set, key, v)
end

local function setting(key, new)
    if new ~= cfg[key] then
        cfg[key] = new
        save(key)
    end
end

reskate.on("load", function()
    for key, default in DEFAULTS do
        local ok, value = pcall(reskate.storage.get, key)
        if ok and type(value) == "number" then
            if type(default) == "boolean" then
                cfg[key] = (value == 1)
            else
                cfg[key] = value
            end
        end
    end
    reskate.log("[InstantDeath] loaded")
end)

-- State
local dead = false
local deathAt = 0
local teleported = false
local teleportedAt = 0
local damage = 0          -- 0 to 1 so death at 1
local worstHit = 0
local worstText = "-"
local lastDamage = 0
local lastWorst = "-"
local checkpoint = nil
local lastSave = 0

local function zoneWeight(bone)
    local w = VITAL[bone]
    if w then return w end
    w = LIMB[bone]
    if w then return w * cfg.limbs end
    return 0.2
end

local function resetFall()
    damage = 0
    worstHit = 0
    worstText = "-"
end

local function die()
    dead = true
    teleported = false
    deathAt = reskate.time.now()
    lastDamage = damage
    lastWorst = worstText
end

reskate.on("body_hit", function(e)
    if dead or not cfg.enabled then return end
    -- damage grows with the square of the speed (energy)
    local hit = zoneWeight(e.bone) * (e.impact / cfg.lethal) ^ 2
    if e.vehicle then
        hit *= VEHICLE_FACTOR
    elseif e.board then
        hit *= BOARD_FACTOR
    end
    damage += hit
    if hit > worstHit then
        worstHit = hit
        worstText = string.format("%s, %.1f m/s", e.bone, e.impact)
    end
    if damage >= 1 then die() end
end)

reskate.on("bail_end", function()
    if not dead then
        lastDamage = damage
        lastWorst = worstText
        resetFall()
    end
end)

reskate.on("tick", function()
    local now = reskate.time.now()

    if not dead then
        if now - lastSave > 500 and reskate.skater.state() == "riding" then
            local s = reskate.skater.get()
            if s then
                checkpoint = {pos = s.position, heading = s.heading}
                lastSave = now
            end
        end
        return
    end

    if not teleported and now - deathAt >= (cfg.fade_in + cfg.black) * 1000 then
        if checkpoint then
            local ok, why = reskate.skater.teleport(checkpoint.pos, checkpoint.heading)
            if not ok then
                reskate.log("teleport refused: " .. tostring(why), "warn")
                return
            end
        end
        teleported = true
        teleportedAt = now
    end

    if teleported and now - teleportedAt >= cfg.fade_out * 1000 then
        dead = false
        resetFall()
    end
end)

local function currentAlpha()
    if not dead then return 0 end
    local now = reskate.time.now()
    if teleported then
        local out = cfg.fade_out * 1000
        if out <= 0 then return 0 end
        return math.max(0, 1 - (now - teleportedAt) / out)
    end
    local fin = cfg.fade_in * 1000
    if fin <= 0 then return 1 end
    return math.min(1, (now - deathAt) / fin)
end

reskate.on("draw", function(d)
    local a = currentAlpha()
    if a <= 0 then return end
    local size = d:size()
    d:rect(
        vector.create(0, 0, 0),
        vector.create(size.x, size.y, 0),
        {colour = string.format("#000000%02x", math.floor(a * 255)), fill = true}
    )
end)
-- maybe i want to kms >w<
-- menu page uk uk
reskate.menu.page("Instant Death", function(ui)
    ui:card("INSTANT DEATH", "Black screen and respawn after a major fall")
    setting("enabled", ui:toggle("enabled", "Enabled", cfg.enabled, "Disable the plugin without uninstalling it."))

    ui:card("INJURIES")
    setting("lethal", round(ui:slider("lethal", "Lethal head impact", cfg.lethal, 3, 25, "%.1f m/s"), 1))
    ui:note("A single head hit at this speed kills. Chest and spine count a bit less, arms and legs much less. Twice as fast means four times the damage.")
    setting("limbs", round(ui:slider("limbs", "Arms and legs weight", cfg.limbs, 0, 2, "x%.1f"), 1))
    ui:info("Current fall", string.format("%.0f%%", damage * 100))
    ui:info("Last fall", string.format("%.0f%%", lastDamage * 100))
    ui:info("Worst hit", lastWorst)

    ui:card("BLACK SCREEN")
    setting("fade_in", round(ui:slider("fade_in", "Fade to black", cfg.fade_in, 0, 2, "%.1f s"), 1))
    setting("black", round(ui:slider("black", "Black screen duration", cfg.black, 0.5, 15, "%.1f s"), 1))
    setting("fade_out", round(ui:slider("fade_out", "Fade back", cfg.fade_out, 0, 3, "%.1f s"), 1))

    if ui:button("test", "Test", true) then die() end
    if ui:button("reset", "Reset to defaults") then
        for key, value in DEFAULTS do setting(key, value) end
    end
end)