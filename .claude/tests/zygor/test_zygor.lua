--[[
    Offline suite for Modules/ZygorUpgrades.lua.

        .claude/tests/autosell/run.sh .claude/tests/zygor/test_zygor.lua

    Tier: Medium - one contract at the boundary with a third-party addon the project does not own,
    so ZGV is faked here (the only thing that is). Each row names the bug it would catch; the rows
    are one table because they are one contract: GetUpgradePercent returns a number only when
    Zygor says "upgrade", and never raises.
]]

local IM = { modules = {}, debugLines = {} }
function IM:RegisterModule(name, module) self.modules[name] = module end
function IM:Debug(...) table.insert(self.debugLines, table.concat({ ... }, " ")) end

local chunk = assert(loadfile("Modules/ZygorUpgrades.lua"))
chunk("InventoryManager", IM)
local ZygorUpgrades = assert(IM.modules.ZygorUpgrades, "module did not register")

-- Zygor's IsUpgrade returns: isUpgrade, slot, change, score, comment
local function zygor(opts)
    opts = opts or {}
    local calls = 0
    local results = opts.results or { { true, 16, 23, 100, "ok" } }
    local z = {
        calls = function() return calls end,
        ItemScore = {
            Upgrades = {
                IsEnabled = opts.isEnabled or function() return true end,
                IsUpgrade = opts.isUpgrade or function()
                    calls = calls + 1
                    local r = results[math.min(calls, #results)]
                    return r[1], r[2], r[3], r[4], r[5]
                end,
            },
        },
        db = { profile = { markupgrades = opts.markupgrades ~= false } },
    }
    return z
end

local LINK = "|cff0070dd|Hitem:12345::::::::80:::::|h[Test Sword]|h|r"

local rows = {
    -- Bug: a player without Zygor gets a Lua error on every bag update.
    { "no Zygor installed", function() return nil end, true, nil },
    -- Bug: Zygor loaded but restructured (a rename in a Zygor patch) errors on every slot.
    { "Zygor without ItemScore", function() return {} end, true, nil },
    { "Upgrades missing IsEnabled", function()
        local z = zygor(); z.ItemScore.Upgrades.IsEnabled = nil; return z end, true, nil },
    -- Bug: an error inside Zygor's own scoring kills our overlay update for the whole bag.
    { "Zygor's IsUpgrade throws", function()
        return zygor({ isUpgrade = function() error("zygor broke") end }) end, true, nil },
    -- Bug: we show upgrades the user turned off in Zygor's options.
    { "Zygor gear advice off / max-level cutoff", function()
        return zygor({ isEnabled = function() return false end }) end, true, nil },
    { "Zygor 'mark upgrades in bags' off", function()
        return zygor({ markupgrades = false }) end, true, nil },
    -- Bug: a non-upgrade shows a percent.
    { "not an upgrade", function()
        return zygor({ results = { { false, 16, 0, 100, "not upgrade slot 1 final" } } }) end, true, nil },
    -- Bug: a protected quest item (Zygor returns 999999) shows as a +999% gear upgrade.
    { "protected quest item", function()
        return zygor({ results = { { true, 16, 999999, 0, "quest item" } } }) end, true, nil },
    -- Bug: the first sighting of any item shows nothing, because Zygor's first IsUpgrade call
    -- only starts its item load and answers "not scored".
    { "retries once after 'not scored'", function()
        return zygor({ results = { { false, nil, 0, 0, "not scored" }, { true, 16, 18, 100, "ok" } } })
    end, true, 18 },
    -- Bug: an item Zygor never scores loops or hammers Zygor.
    { "gives up after one retry", function()
        return zygor({ results = { { false, nil, 0, 0, "not scored" } } }) end, true, nil, 2 },
    -- Bug: a percent wider than the slot.
    { "clamps huge values", function()
        return zygor({ results = { { true, 16, 5000, 100, "ok" } } }) end, true, 999 },
    -- Bug: every material and consumable in the bag is sent through Zygor.
    { "non-equippable item never reaches Zygor", function() return zygor() end, false, nil, 0 },
    -- The happy path.
    { "upgrade returns Zygor's percent", function() return zygor() end, true, 23, 1 },
}

local failures = 0
for _, row in ipairs(rows) do
    local name, build, equippable, want, wantCalls = row[1], row[2], row[3], row[4], row[5]
    ZGV = build()
    C_Item = { IsEquippableItem = function() return equippable end }

    local ok, got = pcall(ZygorUpgrades.GetUpgradePercent, ZygorUpgrades, LINK)
    local calls = ZGV and ZGV.calls and ZGV.calls() or nil

    local pass = ok and got == want and (wantCalls == nil or calls == wantCalls)
    if pass then
        print("ok    " .. name)
    else
        failures = failures + 1
        print(string.format("FAIL  %s (raised=%s got=%s want=%s calls=%s wantCalls=%s)",
            name, tostring(not ok), tostring(got), tostring(want), tostring(calls), tostring(wantCalls)))
    end
end

ZGV = nil
print(string.format("\n%d rows, %d failed", #rows, failures))
os.exit(failures == 0 and 0 or 1)
