--[[
    InventoryManager - Modules/CurrencySearch.lua
    Adds a search bar to Blizzard's Currency tab (Character Frame > Currency).
]]

local addonName, IM = ...

local CurrencySearch = {}
IM:RegisterModule("CurrencySearch", CurrencySearch)

local _searchBox = nil
local _searchFilter = ""

function CurrencySearch:OnEnable()
    IM:Debug("[CurrencySearch] OnEnable called")

    -- Hook when CharacterFrame shows
    IM:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(2, function()
            self:TrySetup()
        end)
    end)

    -- Also try on addon loaded
    IM:RegisterEvent("ADDON_LOADED", function(event, addon)
        if addon == "Blizzard_TokenUI" then
            C_Timer.After(0.5, function()
                self:TrySetup()
            end)
        end
    end)

    IM:Debug("[CurrencySearch] Module enabled")
end

-- Get the keybind for opening character frame, or default to C
function CurrencySearch:GetCharacterKeybind()
    local key = GetBindingKey("TOGGLECHARACTER0")
    if key then
        return key
    end
    -- Fallback
    return "C"
end

function CurrencySearch:TrySetup()
    if _searchBox then return end

    -- Find the TokenFrame - it's inside CharacterFrame
    local tokenFrame = TokenFrame or (CharacterFrame and CharacterFrame.TokenFrame)
    if not tokenFrame then
        IM:Debug("[CurrencySearch] TokenFrame not found yet")
        return
    end

    IM:Debug("[CurrencySearch] Setting up search bar")

    -- Create search box
    local searchBox = CreateFrame("EditBox", "InventoryManagerCurrencySearch", tokenFrame, "SearchBoxTemplate")
    searchBox:SetSize(140, 20)

    -- Position below the header area, left side
    searchBox:SetPoint("TOPLEFT", tokenFrame, "TOPLEFT", 70, -35)
    searchBox:SetAutoFocus(false)
    searchBox.Instructions:SetText("Search currencies...")

    local debounceTimer = nil
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        -- Hide/show placeholder based on text content
        local text = self:GetText()
        if self.Instructions then
            self.Instructions:SetShown(text == "")
        end

        if userInput then
            if debounceTimer then debounceTimer:Cancel() end
            debounceTimer = C_Timer.NewTimer(0.15, function()
                _searchFilter = text:lower()
                CurrencySearch:ApplyFilter()
            end)
        end
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText("")
        _searchFilter = ""
        CurrencySearch:ApplyFilter()
    end)

    _searchBox = searchBox

    -- Hook ScrollBox updates to reapply filter
    if tokenFrame.ScrollBox then
        hooksecurefunc(tokenFrame.ScrollBox, "Update", function()
            if _searchFilter ~= "" then
                C_Timer.After(0.05, function()
                    CurrencySearch:ApplyFilter()
                end)
            end
        end)
    end

    IM:Debug("[CurrencySearch] Search bar created")
end

function CurrencySearch:ApplyFilter()
    local tokenFrame = TokenFrame or (CharacterFrame and CharacterFrame.TokenFrame)
    if not tokenFrame or not tokenFrame.ScrollBox then return end

    local scrollBox = tokenFrame.ScrollBox

    -- Get all visible frames from the ScrollBox
    local view = scrollBox:GetView()
    if not view then return end

    -- Iterate through the frames using ScrollBox API
    scrollBox:ForEachFrame(function(frame)
        self:FilterCurrencyFrame(frame)
    end)
end

function CurrencySearch:FilterCurrencyFrame(frame)
    if not frame then return end

    -- Try multiple ways to get the currency name
    local nameText = nil

    -- Method 1: Direct Name fontstring (most common)
    if frame.Name and frame.Name.GetText then
        nameText = frame.Name:GetText()
    end

    -- Method 2: Check for currency data on the frame
    if not nameText and frame.GetData then
        local data = frame:GetData()
        if data then
            -- TWW currency frames store currencyID in data
            if data.currencyID then
                local info = C_CurrencyInfo.GetCurrencyInfo(data.currencyID)
                if info then
                    nameText = info.name
                end
            elseif data.name then
                nameText = data.name
            end
        end
    end

    -- Method 3: Check for currencyID directly
    if not nameText and frame.currencyID then
        local info = C_CurrencyInfo.GetCurrencyInfo(frame.currencyID)
        if info then
            nameText = info.name
        end
    end

    -- Method 4: Text fontstring
    if not nameText and frame.Text and frame.Text.GetText then
        nameText = frame.Text:GetText()
    end

    -- If no search filter, show everything
    if _searchFilter == "" then
        frame:Show()
        self:ResetFrame(frame)
        return
    end

    -- Apply filter if we found a name
    if nameText and nameText ~= "" then
        local matches = nameText:lower():find(_searchFilter, 1, true)
        if matches then
            -- Show match with highlight
            frame:Show()
            if frame.Name and frame.Name.SetTextColor then
                frame.Name:SetTextColor(1, 1, 0) -- Yellow
            end
            if frame.SetAlpha then
                frame:SetAlpha(1)
            end
        else
            -- Dim non-match (don't hide - causes spacing issues with ScrollBox)
            if frame.Name and frame.Name.SetTextColor then
                frame.Name:SetTextColor(0.4, 0.4, 0.4) -- Gray
            end
            if frame.SetAlpha then
                frame:SetAlpha(0.3)
            end
        end
    end
end

function CurrencySearch:ResetFrame(frame)
    if not frame then return end

    -- Ensure visible
    frame:Show()

    -- Reset text color
    if frame.Name and frame.Name.SetTextColor then
        frame.Name:SetTextColor(1, 1, 1)
    end

    -- Reset alpha
    if frame.SetAlpha then
        frame:SetAlpha(1)
    end
end
