--[[
    Minimal WoW client stub, enough to load the REAL Core.lua, Database.lua, Filters.lua,
    Modules/AutoSell.lua and Modules/MailHelper.lua under stock Lua 5.1.

        .claude/tests/autosell/run.sh

    Loading the real files rather than re-describing them is the whole point of this stub. A
    version that stubbed `ShouldAutoSell` to `return true` and hand-copied Database.lua's defaults
    made the quality floor, the pre-sale re-check and the defaults themselves untestable by
    construction: a mutation battery deleted the consent gate, the pre-sale ShouldAutoSell
    re-check, the slot identity check, OnAccept's approved-list binding and the autoSellEnabled
    master toggle, and the suite stayed green.

    It stubs behaviour, not semantics: timers are queued and drained by hand, so tests control
    time rather than sleep, and the static popup runs the addon's own OnAccept/OnCancel/OnHide
    rather than letting a test call the handler underneath them. Nothing here is loaded by the
    addon.
]]

local Stub = {}

-- ---------------------------------------------------------------- globals --

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

date = os.date
strsplit = function(sep, str) return str end

local _clock = 1000
function GetTime() return _clock end
function Stub.AdvanceClock(seconds) _clock = _clock + (seconds or 1) end

-- ----------------------------------------------------------------- timers --

local _timers = {}

C_Timer = {
    After = function(delay, fn)
        table.insert(_timers, { delay = delay, fn = fn, cancelled = false })
    end,
    NewTimer = function(delay, fn)
        local timer = { delay = delay, fn = fn, cancelled = false }
        table.insert(_timers, timer)
        timer.Cancel = function(self) self.cancelled = true end
        return timer
    end,
    NewTicker = function(_, _)
        -- Repeating tickers (the item-info cache sweep) never fire here; nothing under test
        -- depends on cache expiry.
        return { Cancel = function() end }
    end,
}

-- Run every timer currently queued (and anything they queue, up to a depth bound).
function Stub.DrainTimers(maxRounds)
    maxRounds = maxRounds or 50
    for _ = 1, maxRounds do
        if #_timers == 0 then return end
        local batch = _timers
        _timers = {}
        for _, timer in ipairs(batch) do
            if not timer.cancelled then timer.fn() end
        end
    end
end

function Stub.PendingTimerCount()
    local n = 0
    for _, t in ipairs(_timers) do
        if not t.cancelled then n = n + 1 end
    end
    return n
end

-- Drop queued timers WITHOUT running them. Tests that call this are asserting something about a
-- state reached before the timers come due; a test that discards a timer carrying the behaviour
-- it is meant to exercise proves nothing, which is how the MERCHANT_SHOW re-fire hole survived a
-- suite that claimed to cover it.
function Stub.ClearTimers() _timers = {} end

-- ----------------------------------------------------------------- frames --

-- A frame that answers anything. Explicit methods are the ones code under test actually depends
-- on; everything else returns a fresh stub so chained UI setup (CreateFontString():SetPoint())
-- does not need enumerating.
local _frameMeta
local function _NewFrame(name)
    local frame = {
        _scripts = {},
        _events = {},
        _shown = false,
        _name = name,
    }
    return setmetatable(frame, _frameMeta)
end

local _frameMethods = {
    SetScript = function(self, key, fn) self._scripts[key] = fn end,
    GetScript = function(self, key) return self._scripts[key] end,
    HookScript = function(self, key, fn) self._scripts[key] = fn end,
    RegisterEvent = function(self, event) self._events[event] = true end,
    UnregisterEvent = function(self, event) self._events[event] = nil end,
    UnregisterAllEvents = function(self) self._events = {} end,
    Show = function(self) self._shown = true end,
    Hide = function(self) self._shown = false end,
    IsShown = function(self) return self._shown end,
    IsVisible = function(self) return self._shown end,
    GetName = function(self) return self._name end,
    CreateFontString = function() return _NewFrame() end,
    CreateTexture = function() return _NewFrame() end,
}

_frameMeta = {
    __index = function(t, key)
        local explicit = _frameMethods[key]
        if explicit then return explicit end
        -- Unknown member: a no-op method returning a fresh stub, so chains keep working.
        local fn = function() return _NewFrame() end
        rawset(t, key, fn)
        return fn
    end,
}

function CreateFrame(_, name, _, _)
    return _NewFrame(name)
end

Stub.NewFrame = _NewFrame

UIParent = _NewFrame("UIParent")
SettingsPanel = _NewFrame("SettingsPanel")
UISpecialFrames = {}
function HideUIPanel() end
function InterfaceOptions_AddCategory() end
Settings = {
    RegisterCanvasLayoutCategory = function() return { ID = 1 } end,
    RegisterAddOnCategory = function() end,
}

MerchantFrame = _NewFrame("MerchantFrame")
MerchantFrame.shown = true
MerchantFrame.IsShown = function(self) return self.shown end

-- ------------------------------------------------------------------ chat --

-- Core.lua prints through the global print(). Capture there rather than replacing IM:Print, so
-- tests read what the addon's own print path produced - which also means the global print() no
-- longer reaches stdout, so the suite reports through Stub.Say instead.
local _IM

Stub.Say = print

function print(...)
    if not _IM then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    table.insert(_IM.prints, line)
    if line:find("Error", 1, true) then table.insert(_IM.errors, line) end
end

-- ---------------------------------------------------------- static popups --

StaticPopupDialogs = {}
Stub.shownPopups = {}
Stub.activePopup = nil

-- Blizzard has a fixed number of popup slots and hands back nil when every one of them is held by
-- another addon. Set this to make the next Show fail that way: the addon's fail-closed branch is
-- unreachable otherwise, and an unreachable branch is indistinguishable from a deleted one.
Stub.refusePopup = false

-- Blizzard's signature is StaticPopup_Show(which, text_arg1, text_arg2, data). Both text args are
-- modelled because the addon uses both, and a stub that swallowed the second would let a
-- substitution the dialog depends on go missing without the suite noticing.
function StaticPopup_Show(which, arg1, arg2, data)
    if Stub.refusePopup then return nil end
    local dialog = { which = which, arg1 = arg1, arg2 = arg2, data = data }
    Stub.activePopup = dialog
    table.insert(Stub.shownPopups, dialog)
    return dialog
end

-- Blizzard's hide path runs OnHide. The old stub did not, so every test that hid a popup left the
-- addon's OnHide bookkeeping unexecuted and the gate it clears untested.
function StaticPopup_Hide(which)
    local dialog = Stub.activePopup
    if not dialog or dialog.which ~= which then return end
    Stub.activePopup = nil
    local definition = StaticPopupDialogs[which]
    if definition and definition.OnHide then definition.OnHide(dialog) end
end

local function _AnswerPopup(handlerName)
    local dialog = Stub.activePopup
    if not dialog then return false end
    local definition = StaticPopupDialogs[dialog.which]
    if definition[handlerName] then definition[handlerName](dialog) end
    -- The handler may already have hidden the dialog (and run OnHide) from inside itself.
    if Stub.activePopup == dialog then
        Stub.activePopup = nil
        if definition.OnHide then definition.OnHide(dialog) end
    end
    return true
end

--[[
    Press the dialog's buttons, or dismiss it with Escape. These are the only production entry
    points into the consent gate, so tests drive these instead of calling ConfirmApprovedSale.

    A missing dialog returns false rather than raising: an abort here ends the run at the first
    surprise and reports a fraction of the damage, so the caller turns the false into one named
    failure and the remaining checks still say which guards went with it.

    @return boolean - Was there a dialog to answer?
]]
function Stub.PopupAccept() return _AnswerPopup("OnAccept") end
function Stub.PopupCancel() return _AnswerPopup("OnCancel") end
function Stub.PopupEscape()
    local dialog = Stub.activePopup
    if not dialog then return false end
    StaticPopup_Hide(dialog.which)
    return true
end

function Stub.PopupOnScreen()
    return Stub.activePopup ~= nil
end

function Stub.PopupText()
    local dialog = Stub.activePopup
    return dialog and dialog.arg1 or nil
end

-- The dialog's second substitution, as the player would read it.
function Stub.PopupText2()
    local dialog = Stub.activePopup
    return dialog and dialog.arg2 or nil
end

-- Blizzard's buyback capacity constant (FrameXML MerchantFrame.lua). Defined here so the addon's
-- derived buyback wording runs against a client value rather than falling into its own
-- constant-is-missing branch; tests that care set it to something other than the live 12, so a
-- number typed into the addon by hand cannot pass for a derived one.
BUYBACK_ITEMS_PER_PAGE = 12

-- ------------------------------------------------------------------ items --

-- itemID -> item info as GetItemInfo reports it. An itemID with no entry here is UNCACHED: every
-- GetItemInfo return is nil, which is the state a freshly logged-in client is in and the state
-- the quality floor has to fail closed on.
Stub.items = {}

-- Pass as `quality` to make GetItemInfo return a NAME but no quality. The client is not believed
-- to do this, which is exactly why the fail-closed branch guarding it needs a test: an untested
-- defensive branch is indistinguishable from a deletable one, and this one guards an asset.
Stub.NO_QUALITY = {}

function Stub.DefineItem(itemID, fields)
    fields = fields or {}
    Stub.items[itemID] = {
        name = fields.name or ("Item " .. tostring(itemID)),
        quality = (fields.quality ~= Stub.NO_QUALITY) and (fields.quality or 0) or nil,
        itemLevel = fields.itemLevel or 1,
        itemType = fields.itemType or "Miscellaneous",
        itemSubType = fields.itemSubType or "Junk",
        sellPrice = fields.sellPrice or 100,
        classID = fields.classID or 15,      -- Miscellaneous, excluded by no default category
        subclassID = fields.subclassID or 0,
        bindType = fields.bindType or 0,     -- unbound, so skipSoulbound does not protect it
    }
    return Stub.items[itemID]
end

local function _ItemIDFrom(idOrLink)
    if type(idOrLink) == "number" then return idOrLink end
    if type(idOrLink) == "string" then return tonumber(idOrLink:match("item:(%d+)")) end
    return nil
end

function Stub.ItemLink(itemID)
    return "|Hitem:" .. tostring(itemID) .. "|h[Item " .. tostring(itemID) .. "]|h"
end

function GetItemInfo(idOrLink)
    local item = Stub.items[_ItemIDFrom(idOrLink)]
    if not item then return nil end
    return item.name, Stub.ItemLink(_ItemIDFrom(idOrLink)), item.quality, item.itemLevel, 1,
        item.itemType, item.itemSubType, 1, "", "Interface\\Icons\\Temp", item.sellPrice,
        item.classID, item.subclassID, item.bindType
end

GetItemInfoInstant = function(idOrLink)
    local id = _ItemIDFrom(idOrLink)
    local item = Stub.items[id]
    if not item then return nil end
    return id, item.itemType, item.itemSubType, "", "Interface\\Icons\\Temp", item.classID, item.subclassID
end

-- ------------------------------------------------------------------- bags --

-- Stub.bags[bagID][slotID] = { itemID, stackCount, isLocked, isBound }
Stub.bags = {}
Stub.bagSlots = {}

function Stub.PutItem(bagID, slotID, entry)
    Stub.bags[bagID] = Stub.bags[bagID] or {}
    Stub.bags[bagID][slotID] = entry
    Stub.bagSlots[bagID] = math.max(Stub.bagSlots[bagID] or 0, slotID)
end

function Stub.ClearBags()
    Stub.bags = {}
    Stub.bagSlots = {}
end

NUM_BAG_SLOTS = 4
BACKPACK_CONTAINER = 0
Enum = { BagIndex = { ReagentBag = 5 }, ItemQuality = { Heirloom = 7 } }

C_Container = {
    GetContainerNumSlots = function(bagID) return Stub.bagSlots[bagID] or 0 end,
    GetContainerItemInfo = function(bagID, slotID)
        local bag = Stub.bags[bagID]
        local entry = bag and bag[slotID]
        if not entry then return nil end
        local item = Stub.items[entry.itemID]
        return {
            itemID = entry.itemID,
            stackCount = entry.stackCount or 1,
            hyperlink = Stub.ItemLink(entry.itemID),
            quality = item and item.quality,
            isLocked = entry.isLocked or false,
            isBound = entry.isBound or false,
        }
    end,
    UseContainerItem = function(bagID, slotID)
        Stub.sold = Stub.sold or {}
        local bag = Stub.bags[bagID]
        local entry = bag and bag[slotID]
        table.insert(Stub.sold, { bagID = bagID, slotID = slotID, itemID = entry and entry.itemID })
        local refused = Stub.refuseSale and entry and Stub.refuseSale[entry.itemID]
        if not refused and bag then
            bag[slotID] = nil
        end
        -- The bags keep changing while a queue is being worked through: loot lands, the player
        -- moves something. Tests hook here to make that happen at a real moment in the sequence
        -- rather than before the sale starts, which is the only window some guards cover.
        if Stub.onSell then Stub.onSell(bagID, slotID, entry and entry.itemID) end
    end,
    GetContainerNumFreeSlots = function() return 0 end,
}

-- --------------------------------------------------------- item locations --

-- Every location reports invalid, so Filters falls back to the container info above for bind
-- state and to GetItemInfo for item level. That keeps bind behaviour driven by the bag entries
-- tests write rather than by a second stubbed API.
ItemLocation = {
    CreateFromBagAndSlot = function() return { IsValid = function() return false end } end,
    CreateFromEquipmentSlot = function() return { IsValid = function() return false end } end,
}

C_Item = {
    IsBound = function() return false end,
    IsBoundToAccountUntilEquip = function() return false end,
    GetCurrentItemLevel = function() return nil end,
    RequestLoadItemDataByID = function() end,
}

C_TooltipInfo = { GetBagItem = function() return nil end }
C_EquipmentSet = {
    GetEquipmentSetIDs = function() return {} end,
    GetEquipmentSetInfo = function() return nil end,
    GetItemIDs = function() return {} end,
}
C_ToyBox = { GetToyInfo = function() return nil end }
C_TransmogCollection = { PlayerHasTransmog = function() return true end }
C_MerchantFrame = { IsSellAllJunkEnabled = function() return false end }

ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { hex = "|cffffffff" } end })

function UnitGUID() return nil end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function GetMoney() return 0 end
function GetCoinTextureString(copper) return tostring(copper) .. "c" end

SLASH_INVENTORYMANAGER1 = nil
SLASH_INVENTORYMANAGER2 = nil
SlashCmdList = {}

-- ------------------------------------------------------------ addon table --

local IM = {
    modules = {},
    prints = {},
    errors = {},
}
_IM = IM
Stub.IM = IM

-- Load a real addon file with the (addonName, IM) vararg the addon expects.
function Stub.LoadAddonFile(path)
    local chunk = assert(loadfile(path))
    return chunk("InventoryManager", IM)
end

-- Dispatch through Core.lua's own event frame, so the handler chain under test is the real one.
function Stub.Fire(event, ...)
    local handler = IM.eventFrame and IM.eventFrame:GetScript("OnEvent")
    if not handler then error("Core.lua has not installed its event handler", 2) end
    handler(IM.eventFrame, event, ...)
end

--[[
    Load the addon the way the client does: Core, Database, Filters, then the module under test,
    then ADDON_LOADED (which initialises the database and calls OnEnable on every module).

    Called once per test via Reset(). The consent grant lives in AutoSell.lua's file scope
    precisely so a /reload re-arms the confirm, so reloading the file is also the only honest way
    to get a clean slate between tests.
]]
function Stub.LoadAddon()
    IM.prints = {}
    IM.errors = {}
    _G.InventoryManagerDB = nil

    -- Core.lua keeps its handler table in a file-local, so a reload of Core is a full reset of the
    -- event registry as well.
    for key in pairs(IM) do
        if key ~= "prints" and key ~= "errors" then IM[key] = nil end
    end
    IM.modules = {}

    Stub.LoadAddonFile("Core.lua")
    Stub.LoadAddonFile("Database.lua")
    Stub.LoadAddonFile("Filters.lua")
    Stub.LoadAddonFile("Modules/AutoSell.lua")
    -- Real MailHelper, in .toc order after AutoSell. ShouldAutoSell's mail-rule tier is a no-op
    -- unless IM.modules.MailHelper is present, so without this file the mutation battery would
    -- report "changing a mail rule moves no verdict" - which is what the harness said while mail
    -- rules were silently outside the consent fingerprint.
    Stub.LoadAddonFile("Modules/MailHelper.lua")

    Stub.Fire("ADDON_LOADED", "InventoryManager")

    return IM
end

return Stub
