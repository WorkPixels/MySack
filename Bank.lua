-- Bank.lua -- mirrors the main window for the bank, and visually replaces
-- Blizzard's default bank frame WITHOUT making the game think the bank is closed
-- (the deposit-on-right-click logic checks the bank frame's visibility).
local ADDON, NS = ...
local C = NS.C

-- Hide the default bank UI by setting zero alpha without breaking UIPanel points
local function tameBlizzBank()
    local bf = _G.BankFrame
    if not bf then return end
    bf:SetAlpha(0)
    bf:EnableMouse(false)
end

local function onBankOpened()
    if NS.bankOpen and NS.bank and NS.bank:IsShown() then return end
    local MySack = NS.MySack
    NS.bankOpen = true
    tameBlizzBank()
    if C.RefreshBags then C.RefreshBags() end
    if NS.bank then
        NS.bank.bagList = C.BANK_BAGS
        if NS.BuildBagBar then NS.BuildBagBar(NS.bank, C.BANK_BAGS) end
    end

    -- Defer opening MySack so Blizzard's BankFrame:OnShow completes cleanly and untainted!
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            tameBlizzBank()
            if not NS.bank then return end
            local bp = (NS.db and NS.db.bankPoint) or { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
            NS.bank:ClearAllPoints()
            NS.bank:SetPoint(bp[1], bp[2] or UIParent, bp[3], bp[4], bp[5])
            NS.bank:Show()
            if MySack and MySack.Render then MySack:Render(NS.bank) end
            if NS.db and NS.db.replaceBags then
                if NS.main and NS.db and NS.db.point then
                    local mp = NS.db.point
                    NS.main:ClearAllPoints()
                    NS.main:SetPoint(mp[1], mp[2] or UIParent, mp[3], mp[4], mp[5])
                end
                if MySack and MySack.Open then MySack:Open() end
            end
        end)
        C_Timer.After(0.15, function()
            if NS.bank and NS.bank:IsShown() and MySack and MySack.UpdateContents then
                MySack:UpdateContents(NS.bank)
            end
        end)
        C_Timer.After(0.4, function()
            if NS.bank and NS.bank:IsShown() and MySack and MySack.UpdateContents then
                MySack:UpdateContents(NS.bank)
            end
        end)
    else
        tameBlizzBank()
        if NS.bank then
            local bp = (NS.db and NS.db.bankPoint) or { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
            NS.bank:ClearAllPoints()
            NS.bank:SetPoint(bp[1], bp[2] or UIParent, bp[3], bp[4], bp[5])
            NS.bank:Show()
            if MySack and MySack.Render then MySack:Render(NS.bank) end
        end
        if NS.db and NS.db.replaceBags and MySack and MySack.Open then
            MySack:Open()
        end
    end
end

local function onBankClosed()
    local MySack = NS.MySack
    NS.bankOpen = false
    -- Do NOT auto-hide: leave MySack bank window visible with cached contents (TBag-like offline view).
    -- User closes it with the X if desired. Snapshot/render handled in Features.
    if NS.bank and NS.bank:IsShown() and MySack and MySack.UpdateContents then
        NS.bank.needsResort = true
        MySack:UpdateContents(NS.bank)
    end
end

function NS.BuildBank()
    local f = _G.MySackBankFrame
    if not f and NS.CreateContainerPublic then
        f = NS.CreateContainerPublic("MySackBankFrame", C.BANK_BAGS, "MySack Bank")
    end
    NS.bank = f
    if f then
        f:HookScript("OnHide", function()
            -- Only close the real bank if it is currently open (prevents re-closing on cached view hide)
            if NS.bankOpen and _G.CloseBankFrame then CloseBankFrame() end
        end)
        local p = (NS.db and NS.db.bankPoint) or { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
        f:ClearAllPoints()
        f:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
    end
    if _G.BankFrame and not NS.bankFrameHooked then
        NS.bankFrameHooked = true
        _G.BankFrame:HookScript("OnShow", onBankOpened)
        _G.BankFrame:HookScript("OnHide", onBankClosed)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("BANKFRAME_OPENED")
watcher:RegisterEvent("BANKFRAME_CLOSED")
pcall(watcher.RegisterEvent, watcher, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
pcall(watcher.RegisterEvent, watcher, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
pcall(watcher.RegisterEvent, watcher, "PLAYERBANKBAGSLOTS_CHANGED")
pcall(watcher.RegisterEvent, watcher, "PLAYERBANKSLOTS_CHANGED")
pcall(watcher.RegisterEvent, watcher, "BANKFRAME_TAB_PURCHASED")
pcall(watcher.RegisterEvent, watcher, "REAGENTBANK_PURCHASED")
watcher:SetScript("OnEvent", function(_, event, arg1)
    local MySack = NS.MySack
    local bankerType = (_G.Enum and _G.Enum.PlayerInteractionType and _G.Enum.PlayerInteractionType.Banker) or 8
    if event == "BANKFRAME_OPENED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and arg1 == bankerType) then
        onBankOpened()
    elseif event == "BANKFRAME_CLOSED" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and arg1 == bankerType) then
        onBankClosed()
    elseif event == "PLAYERBANKBAGSLOTS_CHANGED" or event == "PLAYERBANKSLOTS_CHANGED" or event == "BANKFRAME_TAB_PURCHASED" or event == "REAGENTBANK_PURCHASED" then
        tameBlizzBank()
        if C.RefreshBags then C.RefreshBags() end
        if NS.bank then
            NS.bank.bagList = C.BANK_BAGS
            if NS.BuildBagBar then NS.BuildBagBar(NS.bank, C.BANK_BAGS) end
        end
        if _G.BankFrame then _G.BankFrame:SetFrameStrata("MEDIUM") end
        if NS.bank and NS.bank:IsShown() and MySack and MySack.Render then MySack:Render(NS.bank) end
    end
end)
