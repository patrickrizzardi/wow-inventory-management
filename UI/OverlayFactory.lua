--[[
    InventoryManager - UI/OverlayFactory.lua
    Shared overlay factory for item button visual indicators.

    Creates and manages overlay frames for item buttons with three visual states:
    - LOCK (red): Protected/whitelisted items that won't be sold
    - SELL (green): Items that will be auto-sold at vendor
    - UNSELLABLE (gray): Items with no vendor value

    OVERLAY HIERARCHY (layered from back to front):
    - ARTWORK layer (level 7): Shade overlay (tint, covers entire button)
    - OVERLAY layer (level 1): Glow effects (outer border, 4px wide)
    - OVERLAY layer (level 2): Border frames (inner bright 2px border)
    - OVERLAY layer (level 3): Icons (lock/coin/X icons, 14x14)

    USAGE:
        local overlay = IM.UI.OverlayFactory:Create(itemButton)
        IM.UI.OverlayFactory:ShowLock(overlay, true)
        IM.UI.OverlayFactory:Update(overlay, itemButton, bagID, slotID)

    @module UI.OverlayFactory
]]

local addonName, IM = ...

-- Initialize UI namespace if needed
IM.UI = IM.UI or {}

local OverlayFactory = {}
IM.UI.OverlayFactory = OverlayFactory

-- Constants
local BORDER_THICKNESS = 2
local GLOW_THICKNESS = 4

-- Icon textures
local LOCK_ICON = "Interface\\PetBattles\\PetBattle-LockIcon"
local SELL_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local UNSELLABLE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local ICON_BG = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- Colors (can be overridden by theme system later)
local COLORS = {
    lock = {
        shade = { 0.4, 0, 0, 0.4 },
        glow = { 0.8, 0.2, 0.2, 0.4 },
        border = { 1, 0.3, 0.3, 1 },
    },
    sell = {
        shade = { 0, 0.4, 0, 0.4 },
        glow = { 0.2, 0.8, 0.2, 0.4 },
        border = { 0.3, 1, 0.3, 1 },
    },
    unsellable = {
        shade = { 0.3, 0.3, 0.3, 0.3 },
        border = { 0.4, 0.4, 0.4, 0.8 },
    },
    mail = {
        shade = { 0.2, 0.3, 0.5, 0.4 },
        glow = { 0.3, 0.5, 0.9, 0.4 },
        border = { 0.4, 0.6, 1, 1 },
    },
    iconBg = { 0, 0, 0, 0.7 },
}

-- Mail icon
local MAIL_ICON = "Interface\\Icons\\INV_Letter_15"

-- Cache of overlay frames keyed by item button
local _overlayCache = {}

--[[
    Creates the four border textures for a given state (lock/sell/unsellable).

    @param overlay Frame - The parent overlay frame
    @param prefix string - Texture name prefix (e.g., "lock", "sell")
    @param color table - {r, g, b, a} color values
    @param layer number - Texture layer (1 for glow, 2 for border)
    @param thickness number - Border thickness in pixels
    @param offset number - Offset from edge (negative for outward)
    @returns table - Table with Top, Bottom, Left, Right texture references
]]
local function _createBorderTextures(overlay, prefix, color, layer, thickness, offset)
    offset = offset or 0
    local textures = {}

    -- Top border
    textures.Top = overlay:CreateTexture(nil, "OVERLAY", nil, layer)
    textures.Top:SetHeight(thickness)
    textures.Top:SetPoint("TOPLEFT", offset, -offset)
    textures.Top:SetPoint("TOPRIGHT", -offset, -offset)
    textures.Top:SetColorTexture(unpack(color))
    textures.Top:Hide()

    -- Bottom border
    textures.Bottom = overlay:CreateTexture(nil, "OVERLAY", nil, layer)
    textures.Bottom:SetHeight(thickness)
    textures.Bottom:SetPoint("BOTTOMLEFT", offset, offset)
    textures.Bottom:SetPoint("BOTTOMRIGHT", -offset, offset)
    textures.Bottom:SetColorTexture(unpack(color))
    textures.Bottom:Hide()

    -- Left border
    textures.Left = overlay:CreateTexture(nil, "OVERLAY", nil, layer)
    textures.Left:SetWidth(thickness)
    textures.Left:SetPoint("TOPLEFT", offset, -offset)
    textures.Left:SetPoint("BOTTOMLEFT", offset, offset)
    textures.Left:SetColorTexture(unpack(color))
    textures.Left:Hide()

    -- Right border
    textures.Right = overlay:CreateTexture(nil, "OVERLAY", nil, layer)
    textures.Right:SetWidth(thickness)
    textures.Right:SetPoint("TOPRIGHT", -offset, -offset)
    textures.Right:SetPoint("BOTTOMRIGHT", -offset, offset)
    textures.Right:SetColorTexture(unpack(color))
    textures.Right:Hide()

    return textures
end

--[[
    Creates an icon with background circle.

    @param overlay Frame - Parent overlay frame
    @param iconTexture string - Path to icon texture
    @param anchorPoint string - Corner to anchor ("TOPLEFT" or "BOTTOMRIGHT")
    @returns table - { bg = texture, icon = texture }
]]
local function _createIcon(overlay, iconTexture, anchorPoint)
    local result = {}

    -- Background circle
    result.bg = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    result.bg:SetSize(18, 18)
    result.bg:SetTexture(ICON_BG)
    result.bg:SetVertexColor(unpack(COLORS.iconBg))
    result.bg:Hide()

    -- Icon
    result.icon = overlay:CreateTexture(nil, "OVERLAY", nil, 3)
    result.icon:SetSize(14, 14)
    result.icon:SetTexture(iconTexture)
    result.icon:Hide()

    -- Position based on anchor
    if anchorPoint == "TOPLEFT" then
        result.bg:SetPoint("TOPLEFT", 1, -1)
        result.icon:SetPoint("TOPLEFT", 3, -3)
    elseif anchorPoint == "BOTTOMRIGHT" then
        result.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        result.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    end

    return result
end

--[[
    Creates a pulsing animation group for an overlay.

    @param overlay Frame - Parent frame for the animation
    @returns AnimationGroup - The created animation group
]]
local function _createPulseAnimation(overlay)
    local animGroup = overlay:CreateAnimationGroup()
    animGroup:SetLooping("BOUNCE")

    local fade = animGroup:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.5)
    fade:SetDuration(0.5)
    fade:SetSmoothing("IN_OUT")

    return animGroup
end

--[[
    Creates a complete overlay frame for an item button with all visual states.

    The overlay includes three mutually exclusive visual states:
    - Lock: Red borders + shade + lock icon (pulsing)
    - Sell: Green borders + shade + coin icon (pulsing)
    - Unsellable: Gray borders + shade + X icon (static)

    @param itemButton Frame - The WoW item button to attach overlay to
    @returns Frame - The overlay frame with all textures and animations

    TIME COMPLEXITY: O(1) - creates fixed number of textures
    SPACE COMPLEXITY: O(1) per overlay - fixed structure
]]
function OverlayFactory:Create(itemButton)
    -- Return cached overlay if exists
    if _overlayCache[itemButton] then
        return _overlayCache[itemButton]
    end

    -- Create main overlay frame
    local overlay = CreateFrame("Frame", nil, itemButton)
    overlay:SetAllPoints(itemButton)
    overlay:SetFrameLevel(itemButton:GetFrameLevel() + 10)

    -- ============ LOCK STATE (red) ============

    -- Lock shade (covers entire button)
    overlay.lockShade = overlay:CreateTexture(nil, "ARTWORK", nil, 7)
    overlay.lockShade:SetAllPoints()
    overlay.lockShade:SetColorTexture(unpack(COLORS.lock.shade))
    overlay.lockShade:Hide()

    -- Lock glow (outer, dimmer)
    overlay.lockGlow = _createBorderTextures(overlay, "lockGlow", COLORS.lock.glow, 1, GLOW_THICKNESS, -1)

    -- Lock border (inner, bright)
    overlay.lockBorder = _createBorderTextures(overlay, "lockBorder", COLORS.lock.border, 2, BORDER_THICKNESS, 0)

    -- Lock icon (top-left)
    overlay.lockIconSet = _createIcon(overlay, LOCK_ICON, "TOPLEFT")

    -- Lock animation
    overlay.lockAnimGroup = _createPulseAnimation(overlay)

    -- ============ SELL STATE (green) ============

    -- Sell shade
    overlay.sellShade = overlay:CreateTexture(nil, "ARTWORK", nil, 7)
    overlay.sellShade:SetAllPoints()
    overlay.sellShade:SetColorTexture(unpack(COLORS.sell.shade))
    overlay.sellShade:Hide()

    -- Sell glow (outer, dimmer)
    overlay.sellGlow = _createBorderTextures(overlay, "sellGlow", COLORS.sell.glow, 1, GLOW_THICKNESS, -1)

    -- Sell border (inner, bright)
    overlay.sellBorder = _createBorderTextures(overlay, "sellBorder", COLORS.sell.border, 2, BORDER_THICKNESS, 0)

    -- Sell icon (top-left, same position as lock)
    overlay.sellIconSet = _createIcon(overlay, SELL_ICON, "TOPLEFT")

    -- Sell animation
    overlay.sellAnimGroup = _createPulseAnimation(overlay)

    -- ============ UNSELLABLE STATE (gray) ============

    -- Unsellable shade
    overlay.unsellableShade = overlay:CreateTexture(nil, "ARTWORK", nil, 7)
    overlay.unsellableShade:SetAllPoints()
    overlay.unsellableShade:SetColorTexture(unpack(COLORS.unsellable.shade))
    overlay.unsellableShade:Hide()

    -- Unsellable border (no glow, just border)
    overlay.unsellableBorder = _createBorderTextures(overlay, "unsellableBorder", COLORS.unsellable.border, 2, BORDER_THICKNESS, 0)

    -- Unsellable icon (bottom-right, different from lock/sell)
    overlay.unsellableIconSet = _createIcon(overlay, UNSELLABLE_ICON, "BOTTOMRIGHT")

    -- ============ MAIL STATE (blue) ============

    -- Mail shade
    overlay.mailShade = overlay:CreateTexture(nil, "ARTWORK", nil, 7)
    overlay.mailShade:SetAllPoints()
    overlay.mailShade:SetColorTexture(unpack(COLORS.mail.shade))
    overlay.mailShade:Hide()

    -- Mail glow (outer, dimmer)
    overlay.mailGlow = _createBorderTextures(overlay, "mailGlow", COLORS.mail.glow, 1, GLOW_THICKNESS, -1)

    -- Mail border (inner, bright)
    overlay.mailBorder = _createBorderTextures(overlay, "mailBorder", COLORS.mail.border, 2, BORDER_THICKNESS, 0)

    -- Mail icon (top-left)
    overlay.mailIconSet = _createIcon(overlay, MAIL_ICON, "TOPLEFT")

    -- Mail animation
    overlay.mailAnimGroup = _createPulseAnimation(overlay)

    -- Start hidden
    overlay:Hide()

    -- Cache and return
    _overlayCache[itemButton] = overlay
    return overlay
end

--[[
    Shows or hides the lock state (red borders, shade, lock icon, pulsing animation).

    @param overlay Frame - Overlay frame created by OverlayFactory:Create()
    @param show boolean - true to show, false to hide
]]
function OverlayFactory:ShowLock(overlay, show)
    if show then
        overlay.lockShade:Show()
        overlay.lockGlow.Top:Show()
        overlay.lockGlow.Bottom:Show()
        overlay.lockGlow.Left:Show()
        overlay.lockGlow.Right:Show()
        overlay.lockBorder.Top:Show()
        overlay.lockBorder.Bottom:Show()
        overlay.lockBorder.Left:Show()
        overlay.lockBorder.Right:Show()
        overlay.lockIconSet.bg:Show()
        overlay.lockIconSet.icon:Show()
        if overlay.lockAnimGroup and not overlay.lockAnimGroup:IsPlaying() then
            overlay.lockAnimGroup:Play()
        end
    else
        overlay.lockShade:Hide()
        overlay.lockGlow.Top:Hide()
        overlay.lockGlow.Bottom:Hide()
        overlay.lockGlow.Left:Hide()
        overlay.lockGlow.Right:Hide()
        overlay.lockBorder.Top:Hide()
        overlay.lockBorder.Bottom:Hide()
        overlay.lockBorder.Left:Hide()
        overlay.lockBorder.Right:Hide()
        overlay.lockIconSet.bg:Hide()
        overlay.lockIconSet.icon:Hide()
        if overlay.lockAnimGroup then
            overlay.lockAnimGroup:Stop()
        end
    end
end

--[[
    Shows or hides the sell state (green borders, shade, coin icon, pulsing animation).

    @param overlay Frame - Overlay frame created by OverlayFactory:Create()
    @param show boolean - true to show, false to hide
]]
function OverlayFactory:ShowSell(overlay, show)
    if show then
        overlay.sellShade:Show()
        overlay.sellGlow.Top:Show()
        overlay.sellGlow.Bottom:Show()
        overlay.sellGlow.Left:Show()
        overlay.sellGlow.Right:Show()
        overlay.sellBorder.Top:Show()
        overlay.sellBorder.Bottom:Show()
        overlay.sellBorder.Left:Show()
        overlay.sellBorder.Right:Show()
        overlay.sellIconSet.bg:Show()
        overlay.sellIconSet.icon:Show()
        if overlay.sellAnimGroup and not overlay.sellAnimGroup:IsPlaying() then
            overlay.sellAnimGroup:Play()
        end
    else
        overlay.sellShade:Hide()
        overlay.sellGlow.Top:Hide()
        overlay.sellGlow.Bottom:Hide()
        overlay.sellGlow.Left:Hide()
        overlay.sellGlow.Right:Hide()
        overlay.sellBorder.Top:Hide()
        overlay.sellBorder.Bottom:Hide()
        overlay.sellBorder.Left:Hide()
        overlay.sellBorder.Right:Hide()
        overlay.sellIconSet.bg:Hide()
        overlay.sellIconSet.icon:Hide()
        if overlay.sellAnimGroup then
            overlay.sellAnimGroup:Stop()
        end
    end
end

--[[
    Shows or hides the unsellable state (gray borders, shade, X icon, no animation).

    @param overlay Frame - Overlay frame created by OverlayFactory:Create()
    @param show boolean - true to show, false to hide
]]
function OverlayFactory:ShowUnsellable(overlay, show)
    if show then
        overlay.unsellableShade:Show()
        overlay.unsellableBorder.Top:Show()
        overlay.unsellableBorder.Bottom:Show()
        overlay.unsellableBorder.Left:Show()
        overlay.unsellableBorder.Right:Show()
        overlay.unsellableIconSet.bg:Show()
        overlay.unsellableIconSet.icon:Show()
    else
        overlay.unsellableShade:Hide()
        overlay.unsellableBorder.Top:Hide()
        overlay.unsellableBorder.Bottom:Hide()
        overlay.unsellableBorder.Left:Hide()
        overlay.unsellableBorder.Right:Hide()
        overlay.unsellableIconSet.bg:Hide()
        overlay.unsellableIconSet.icon:Hide()
    end
end

--[[
    Shows or hides the mail state (blue borders, shade, mail icon, pulsing animation).

    @param overlay Frame - Overlay frame created by OverlayFactory:Create()
    @param show boolean - true to show, false to hide
]]
function OverlayFactory:ShowMail(overlay, show)
    if show then
        overlay.mailShade:Show()
        overlay.mailGlow.Top:Show()
        overlay.mailGlow.Bottom:Show()
        overlay.mailGlow.Left:Show()
        overlay.mailGlow.Right:Show()
        overlay.mailBorder.Top:Show()
        overlay.mailBorder.Bottom:Show()
        overlay.mailBorder.Left:Show()
        overlay.mailBorder.Right:Show()
        overlay.mailIconSet.bg:Show()
        overlay.mailIconSet.icon:Show()
        if overlay.mailAnimGroup and not overlay.mailAnimGroup:IsPlaying() then
            overlay.mailAnimGroup:Play()
        end
    else
        overlay.mailShade:Hide()
        overlay.mailGlow.Top:Hide()
        overlay.mailGlow.Bottom:Hide()
        overlay.mailGlow.Left:Hide()
        overlay.mailGlow.Right:Hide()
        overlay.mailBorder.Top:Hide()
        overlay.mailBorder.Bottom:Hide()
        overlay.mailBorder.Left:Hide()
        overlay.mailBorder.Right:Hide()
        overlay.mailIconSet.bg:Hide()
        overlay.mailIconSet.icon:Hide()
        if overlay.mailAnimGroup then
            overlay.mailAnimGroup:Stop()
        end
    end
end

--[[
    Hides all overlay states (lock, sell, unsellable, mail) and stops animations.

    @param overlay Frame - Overlay frame to reset
]]
function OverlayFactory:HideAll(overlay)
    self:ShowLock(overlay, false)
    self:ShowSell(overlay, false)
    self:ShowUnsellable(overlay, false)
    self:ShowMail(overlay, false)
    overlay:Hide()
end

function OverlayFactory:SetDimmed(overlay, dimmed)
    if not overlay then return end
    overlay:SetAlpha(dimmed and 0.1 or 1)
end

--[[
    Updates an overlay based on the item's current state.

    Determines whether to show lock (red), sell (green), mail (blue),
    unsellable (gray), or no overlay based on:
    1. Is item whitelisted? → Show lock (red)
    2. Is item queued for mail? → Show mail (blue)
    3. Is item in junk list or should auto-sell? → Show sell (green)
    4. Does item have no vendor value? → Show unsellable (gray)
    5. Otherwise → Hide overlay

    @param itemButton Frame - The item button with the overlay
    @param bagID number - Bag ID (0-5 or reagent bag)
    @param slotID number - Slot ID within the bag

    TIME COMPLEXITY: O(1) for state checks, but Filters:ShouldAutoSell may be O(n)
]]
function OverlayFactory:Update(itemButton, bagID, slotID)
    local overlay = self:Create(itemButton)

    -- Get item in this slot
    local info = C_Container.GetContainerItemInfo(bagID, slotID)

    if not info or not info.itemID then
        self:HideAll(overlay)
        return
    end

    local itemID = info.itemID
    local isLocked = IM:IsWhitelisted(itemID)
    local isJunk = IM:IsJunk(itemID)

    -- Get overlay settings (with safe defaults)
    local showLockOverlay = IM.db and IM.db.global and IM.db.global.ui and IM.db.global.ui.showLockOverlay ~= false
    local showSellOverlay = IM.db and IM.db.global and IM.db.global.ui and IM.db.global.ui.showSellOverlay ~= false
    local showMailOverlay = IM.db and IM.db.global and IM.db.global.ui and IM.db.global.ui.showMailOverlay ~= false
    local showUnsellableIndicator = IM.db and IM.db.global and IM.db.global.ui and IM.db.global.ui.showUnsellableIndicator ~= false

    -- Check if item matches a mail rule (shows blue border anytime, not just at mailbox)
    local isMailRuleMatch = false
    if showMailOverlay and IM.modules.MailHelper and IM.modules.MailHelper.ItemMatchesAnyRule then
        isMailRuleMatch = IM.modules.MailHelper:ItemMatchesAnyRule(itemID)
    end

    -- Check if item is sellable
    local isSellable = false
    if showSellOverlay and not isLocked and not isMailRuleMatch then
        isSellable = IM.Filters:ShouldAutoSell(bagID, slotID, itemID, info.hyperlink)
    end

    -- Check if item is unsellable (no vendor value)
    local isUnsellable = false
    if showUnsellableIndicator then
        local itemName, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(info.hyperlink or itemID)
        if itemName then
            isUnsellable = (sellPrice == nil or sellPrice == 0)
        end
    end

    -- Apply appropriate state (mutually exclusive, priority order)
    if isLocked and showLockOverlay then
        self:ShowSell(overlay, false)
        self:ShowUnsellable(overlay, false)
        self:ShowMail(overlay, false)
        self:ShowLock(overlay, true)
        overlay:Show()
    elseif isMailRuleMatch and showMailOverlay then
        self:ShowLock(overlay, false)
        self:ShowSell(overlay, false)
        self:ShowUnsellable(overlay, false)
        self:ShowMail(overlay, true)
        overlay:Show()
    elseif (isSellable or isJunk) and showSellOverlay then
        self:ShowLock(overlay, false)
        self:ShowUnsellable(overlay, false)
        self:ShowMail(overlay, false)
        self:ShowSell(overlay, true)
        overlay:Show()
    elseif isUnsellable and showUnsellableIndicator then
        self:ShowLock(overlay, false)
        self:ShowSell(overlay, false)
        self:ShowMail(overlay, false)
        self:ShowUnsellable(overlay, true)
        overlay:Show()
    else
        self:HideAll(overlay)
    end
end

--[[
    Gets the cached overlay for an item button, or nil if not created yet.

    @param itemButton Frame - The item button to look up
    @returns Frame|nil - The overlay frame or nil
]]
function OverlayFactory:GetOverlay(itemButton)
    return _overlayCache[itemButton]
end

--[[
    Clears the overlay cache. Call when switching bag addons or on major UI reloads.
]]
function OverlayFactory:ClearCache()
    wipe(_overlayCache)
end

--[[
    Returns the color configuration table.
    Can be used by theme system to update colors dynamically.

    @returns table - The COLORS configuration table
]]
function OverlayFactory:GetColors()
    return COLORS
end

--[[
    Updates colors from theme system.

    @param newColors table - Table with lock, sell, unsellable color definitions
]]
function OverlayFactory:SetColors(newColors)
    if newColors.lock then
        COLORS.lock = newColors.lock
    end
    if newColors.sell then
        COLORS.sell = newColors.sell
    end
    if newColors.unsellable then
        COLORS.unsellable = newColors.unsellable
    end
    if newColors.iconBg then
        COLORS.iconBg = newColors.iconBg
    end

    -- Note: Existing overlays won't update colors until recreated
    -- For live theme switching, we'd need to update texture colors
end
