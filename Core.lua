-- Core.lua -- main frame, item buttons, layout, search and events.
local ADDON, NS = ...
local C   = NS.C
local Cat = NS.Cat

local GetItemInfo = function(...)
    if C and C.GetItemInfo then return C.GetItemInfo(...) end
    if _G.C_Item and _G.C_Item.GetItemInfo then return _G.C_Item.GetItemInfo(...) end
    if _G.GetItemInfo then return _G.GetItemInfo(...) end
    return nil
end
local GetItemIcon = function(...)
    if C and C.GetItemIcon then return C.GetItemIcon(...) end
    if _G.C_Item and (_G.C_Item.GetItemIconByID or _G.C_Item.GetItemIcon) then
        return (_G.C_Item.GetItemIconByID and _G.C_Item.GetItemIconByID(...)) or _G.C_Item.GetItemIcon(...)
    end
    if _G.GetItemIcon then return _G.GetItemIcon(...) end
    return nil
end
local GetDetailedItemLevelInfo = (_G.C_Item and _G.C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo

local MySack = CreateFrame("Frame")
NS.MySack = MySack
_G.MySack = MySack

-- ---------------------------------------------------------------------------
-- Defaults / settings (populated from SavedVariables in Options.lua).
-- ---------------------------------------------------------------------------
NS.defaults = {
    columns         = 14,
    iconSize        = 37,
    iconSpacing     = 4,
    scale           = 1.0,
    bankColumns     = 14,
    bankIconSize    = 37,
    bankScale       = 1.0,
    replaceBags     = true,
    showJunkCoin    = true,
    borderOpacity   = 1.0,
    borderThickness = 2,
    showItemLevel   = true,
    newItemGlow     = true,
    questBorder     = true,
    autoCompare     = true,
    autoSellJunk    = false,
    autoRepair      = false,
    useGuildRepair  = true,
    point           = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -40, 80 },
    bankPoint       = { "TOPLEFT", nil, "TOPLEFT", 40, -104 },
    categoryOrder   = nil,
    overrides       = {},
    -- additional feature defaults (added for full Config/Features support)
    groupSpacing     = 2,
    compactLayout    = true,
    autoSellQuality  = 0,
    autoSellMaxIlvl  = 0,
    sellEquipment    = false,
    sellConsumables  = false,
    sellTradeGoods   = false,
    sellOther        = false,
    protectTools     = true,
    autoDrop         = false,
    autoDropWhite    = false,
    autoDropMaxValue = 0,
    autoOpenClams    = true,
    autoFillQuiver   = true,
    showFreeSlotsOnBackpack = true,

    userProtect      = {},
    customCategories = {},
    hiddenCategories = {},
}

local function S() return NS.db or {} end          -- profile settings (fallback to prevent nil during early init)
local function Sc() return NS.charDB end      -- per-character data

-- ===========================================================================
-- Bag bar: small icons of the equipped bags so you can swap them.
-- ===========================================================================
local function isBankBagLocked(bagID)
    if not bagID then return false end
    if C.IsReagentBag and C.IsReagentBag(bagID) then return false end
    local minBankBag = 5
    if _G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.ReagentBag then
        minBankBag = 6
    elseif _G.CharacterReagentBag0Slot or _G.REAGENTBAG_CONTAINER then
        minBankBag = 6
    end
    if bagID < minBankBag or bagID > (minBankBag + 6) then return false end
    local numPurchased = 0
    if NS.bankOpen then
        numPurchased = (C.GetNumBankSlots and C.GetNumBankSlots()) or (GetNumBankSlots and GetNumBankSlots()) or 0
    else
        local DB = _G.MySackDB
        local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
        local c = DB and DB.itemData and DB.itemData[key]
        numPurchased = c and c.bankNumSlotsPurchased or 0
    end
    return (bagID - (minBankBag - 1)) > numPurchased
end

local bagInvSlot = C.bagInvSlot
local isSpecialtyBag = C.isSpecialtyBag

local function PlaceOrSwapBag(f, bagID)
    if bagID == 0 then
        local msg = "The Backpack cannot be replaced."
        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
            _G.UIErrorsFrame:AddMessage(msg, 1.0, 0.2, 0.2, 1.0)
        end
        print("|cff66ccffMySack|r: " .. msg)
        return
    end

    if bagID == -1 then
        local msg = "The primary bank container cannot be replaced."
        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
            _G.UIErrorsFrame:AddMessage(msg, 1.0, 0.2, 0.2, 1.0)
        end
        print("|cff66ccffMySack|r: " .. msg)
        return
    end

    local s = bagInvSlot(bagID)
    if not s then return end

    -- In Classic WoW, a bag cannot be replaced if it still contains items.
    local numSlots = C.NumSlots(bagID)
    local isEmpty = true
    if numSlots and numSlots > 0 then
        for slot = 1, numSlots do
            if C.ItemInfo(bagID, slot) then
                isEmpty = false
                break
            end
        end
    end

    if not isEmpty then
        local msg = string.format("Bag %d is not empty! In Classic WoW, you must empty a bag before replacing it.", bagID)
        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
            _G.UIErrorsFrame:AddMessage(msg, 1.0, 0.2, 0.2, 1.0)
        end
        print("|cff66ccffMySack|r: " .. msg .. " Items have been highlighted for you.")
        if f.highlightedBag ~= bagID then
            MySack:ToggleBagHighlight(f, bagID)
        end
        return
    end

    if _G.PutItemInBag then
        PutItemInBag(s)
    end
    local hasCursor = (CursorHasItem and CursorHasItem()) or (GetCursorInfo and GetCursorInfo() == "item")
    if hasCursor then
        if _G.PickupBagFromSlot then
            PickupBagFromSlot(s)
        end
    end
    hasCursor = (CursorHasItem and CursorHasItem()) or (GetCursorInfo and GetCursorInfo() == "item")
    if hasCursor then
        if _G.PickupInventoryItem then
            PickupInventoryItem(s)
        end
    end
end

local function BuildBagBar(f, bags)
    f.bagBar = {}
    local x = 12
    local lastButton
    for _, bagID in ipairs(bags) do
        local b = CreateFrame("Button", f:GetName().."BagSlot"..bagID, f)
        b:SetSize(22, 22)
        b:SetPoint("BOTTOMLEFT", x, 13)
        b.bagID = bagID
        b.icon = b:CreateTexture(nil, "BACKGROUND")
        b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = b:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        border:SetPoint("TOPLEFT", -4, 4); border:SetPoint("BOTTOMRIGHT", 4, -4)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        local sel = b:CreateTexture(nil, "OVERLAY")
        sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        sel:SetBlendMode("ADD")
        sel:SetVertexColor(1, 0.85, 0.1, 1)
        sel:SetPoint("TOPLEFT", -2, 2)
        sel:SetPoint("BOTTOMRIGHT", 2, -2)
        sel:Hide()
        b.selectedGlow = sel
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local slot = bagInvSlot(self.bagID)
            local isBankFrame = (f:GetName() == "MySackBankFrame")
            local isLocked = isBankFrame and isBankBagLocked(self.bagID)
            if isLocked then
                GameTooltip:SetText("Locked Bank Bag Slot", 1, 0.2, 0.2)
                GameTooltip:AddLine("Click to open Banker window and purchase this slot.", 1, 1, 1)
                local cost = (C.GetBankSlotCost and C.GetBankSlotCost()) or (GetBankSlotCost and GetBankSlotCost())
                if cost and cost > 0 then
                    local costStr = GetCoinTextureString and GetCoinTextureString(cost) or (math.floor(cost / 10000) .. "g")
                    GameTooltip:AddLine("Cost: " .. costStr, 1, 1, 1)
                end
            elseif self.bagID == 0 then
                GameTooltip:SetText("Backpack")
                if f.highlightedBag == 0 then
                    GameTooltip:AddLine("|cffffcc00[Highlighted]|r Left-Click to unhighlight.", 1, 0.85, 0)
                else
                    GameTooltip:AddLine("Left-Click to highlight items in this bag.", 0.2, 0.8, 1)
                end
            elseif self.bagID == -1 then
                GameTooltip:SetText("Bank")
                if f.highlightedBag == -1 then
                    GameTooltip:AddLine("|cffffcc00[Highlighted]|r Left-Click to unhighlight.", 1, 0.85, 0)
                else
                    GameTooltip:AddLine("Left-Click to highlight items in this bag.", 0.2, 0.8, 1)
                end
            elseif self.bagID == -2 or (C.KEYRING and self.bagID == C.KEYRING) then
                GameTooltip:SetText("Keyring")
                GameTooltip:AddLine("Click to open your keyring.", 0.7, 0.7, 0.7)
            elseif slot then
                local hasBag = false
                local ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", slot)
                local txt = _G["GameTooltipTextLeft1"] and _G["GameTooltipTextLeft1"]:GetText()
                if ok and txt and txt ~= "" and txt ~= "Empty Bag Slot" and txt ~= "Vendor" and txt ~= "Auction" then
                    hasBag = true
                end
                if not hasBag then
                    local bLink = GetInventoryItemLink("player", slot)
                    local bStr = bLink and (bLink:match("|H(item:[^|]+)|h") or bLink:match("(item:[%-?%d:]+)"))
                    if bStr then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, bStr)
                    elseif bLink then
                        pcall(GameTooltip.SetHyperlink, GameTooltip, bLink)
                    end
                    local txt2 = _G["GameTooltipTextLeft1"] and _G["GameTooltipTextLeft1"]:GetText()
                    if txt2 and txt2 ~= "" and txt2 ~= "Empty Bag Slot" and txt2 ~= "Vendor" and txt2 ~= "Auction" then
                        hasBag = true
                    end
                end
                if not hasBag then
                    local bID = GetInventoryItemID("player", slot)
                    if bID and GameTooltip.SetItemByID then
                        pcall(GameTooltip.SetItemByID, GameTooltip, bID)
                        local txt3 = _G["GameTooltipTextLeft1"] and _G["GameTooltipTextLeft1"]:GetText()
                        if txt3 and txt3 ~= "" and txt3 ~= "Empty Bag Slot" and txt3 ~= "Vendor" and txt3 ~= "Auction" then
                            hasBag = true
                        end
                    end
                end
                if not hasBag then
                    if C.IsReagentBag and C.IsReagentBag(self.bagID) then
                        GameTooltip:SetText("Equip Reagent Bag")
                        GameTooltip:AddLine("Drag a reagent bag here to equip it.", 0.7, 0.7, 0.7)
                    else
                        GameTooltip:SetText("Empty Bag Slot")
                        GameTooltip:AddLine("Drag a bag here to equip it.", 0.7, 0.7, 0.7)
                    end
                else
                    if C.IsReagentBag and C.IsReagentBag(self.bagID) then
                        GameTooltip:AddLine("Reagent Bag", 0.3, 0.9, 0.5)
                    end
                    local CC = _G.C_Container
                    local flag = _G.LE_BAG_FILTER_FLAG_IGNORE_CLEANUP
                    if flag then
                        local isIgnored = false
                        if CC and CC.GetBagSlotFlag then
                            isIgnored = CC.GetBagSlotFlag(self.bagID, flag)
                        elseif _G.GetBagSlotFlag then
                            isIgnored = _G.GetBagSlotFlag(self.bagID, flag)
                        end
                        if isIgnored then
                            GameTooltip:AddLine("|cffff5555Ignored during Sort Cleanup|r", 1, 0.3, 0.3)
                        else
                            GameTooltip:AddLine("|cff55ff55Included in Sort Cleanup|r", 0.3, 1, 0.3)
                        end
                        GameTooltip:AddLine("Right-Click to toggle ignore cleanup.", 0.5, 0.8, 1)
                    end
                    if f.highlightedBag == self.bagID then
                        GameTooltip:AddLine("|cffffcc00[Highlighted]|r Left-Click to unhighlight.", 1, 0.85, 0)
                    else
                        GameTooltip:AddLine("Left-Click to highlight items in this bag.", 0.2, 0.8, 1)
                    end
                    GameTooltip:AddLine("Drag a new bag here to replace.", 0.7, 0.7, 0.7)
                end
            elseif C.IsReagentBag and C.IsReagentBag(self.bagID) then
                GameTooltip:SetText("Equip Reagent Bag")
                GameTooltip:AddLine("Drag a reagent bag here to equip it.", 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if bagID == -2 or (C.KEYRING and bagID == C.KEYRING) then
            b:SetScript("OnClick", function(self)
                if ToggleBag then ToggleBag(C.KEYRING or -2)
                elseif ToggleKeyRing then ToggleKeyRing() end
            end)
        elseif bagID == 0 or bagID == -1 then
            b:SetScript("OnClick", function(self, button)
                if button == "LeftButton" then
                    local hasCursorItem = (CursorHasItem and CursorHasItem()) or (GetCursorInfo and GetCursorInfo() == "item")
                    if hasCursorItem then
                        PlaceOrSwapBag(f, self.bagID)
                    else
                        MySack:ToggleBagHighlight(f, self.bagID)
                    end
                end
            end)
            b:SetScript("OnReceiveDrag", function(self)
                PlaceOrSwapBag(f, self.bagID)
            end)
        else
            -- Bag swapping uses unprotected functions, so custom handlers are safe.
            b:SetScript("OnClick", function(self, button)
                local isBankFrame = (f:GetName() == "MySackBankFrame")
                local isLocked = isBankFrame and isBankBagLocked(self.bagID)
                if isLocked then
                    if NS.bankOpen then
                        -- Check if we are on legacy Classic Era where PurchaseSlot() is unprotected and native:
                        local isLegacyUnprotected = C.hasNativePurchaseSlot and not (_G.C_Bank and _G.C_Bank.PurchaseBankTab) and not _G.PurchaseBankTab
                        if isLegacyUnprotected and _G.StaticPopupDialogs and _G.StaticPopupDialogs["CONFIRM_BUY_BANK_SLOT"] then
                            StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
                            return
                        end

                        -- On modern / Camelot / Retail / WoW Forever clients, purchasing a bank slot/tab is a
                        -- protected action (C_Bank.PurchaseBankTab) that cannot be invoked from an addon-triggered
                        -- StaticPopup (which taints OnAccept and triggers ADDON_ACTION_FORBIDDEN).
                        -- Bring Blizzard's native BankFrame to the front so the player can click Purchase directly.
                        if _G.BankFrame then
                            _G.BankFrame:SetAlpha(1)
                            _G.BankFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                            _G.BankFrame:Raise()
                            _G.BankFrame:Show()
                            -- ShowUIPanel omitted to prevent UIParentPanelManager / BankFrame taint
                        end
                        local msg = "Default Banker window opened. Click the 'Purchase' button on the Banker window to buy this bank slot."
                        if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
                            _G.UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0, 1.0)
                        end
                        print("|cff66ccffMySack|r: " .. msg)
                    else
                        print("|cff66ccffMySack|r: You must visit a banker to purchase bank bag slots.")
                    end
                    return
                end

                if button == "RightButton" then
                    local slot = bagInvSlot(self.bagID)
                    if slot and GetInventoryItemTexture("player", slot) then
                        local CC = _G.C_Container
                        local flag = _G.LE_BAG_FILTER_FLAG_IGNORE_CLEANUP
                        if flag then
                            local current = false
                            if CC and CC.GetBagSlotFlag then
                                current = CC.GetBagSlotFlag(self.bagID, flag)
                                CC.SetBagSlotFlag(self.bagID, flag, not current)
                            elseif _G.GetBagSlotFlag then
                                current = _G.GetBagSlotFlag(self.bagID, flag)
                                _G.SetBagSlotFlag(self.bagID, flag, not current)
                            end
                            local state = not current and "|cffff5555Ignored|r" or "|cff55ff55Sorted|r"
                            print("|cff66ccffMySack|r: Bag " .. self.bagID .. " is now " .. state .. " during sort cleanup.")
                            if GameTooltip:GetOwner() == self then
                                self:GetScript("OnEnter")(self)
                            end
                        end
                    end
                else
                    local hasCursorItem = (CursorHasItem and CursorHasItem()) or (GetCursorInfo and GetCursorInfo() == "item")
                    if hasCursorItem then
                        PlaceOrSwapBag(f, self.bagID)
                    else
                        MySack:ToggleBagHighlight(f, self.bagID)
                    end
                end
            end)
            b:SetScript("OnDragStart", function(self)
                local isBankFrame = (f:GetName() == "MySackBankFrame")
                local isLocked = isBankFrame and isBankBagLocked(self.bagID)
                if isLocked then return end

                local numSlots = C.NumSlots(self.bagID)
                local isEmpty = true
                if numSlots and numSlots > 0 then
                    for slot = 1, numSlots do
                        if C.ItemInfo(self.bagID, slot) then
                            isEmpty = false
                            break
                        end
                    end
                end
                if not isEmpty then
                    local msg = string.format("Cannot remove Bag %d because it is not empty!", self.bagID)
                    if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
                        _G.UIErrorsFrame:AddMessage(msg, 1.0, 0.2, 0.2, 1.0)
                    end
                    print("|cff66ccffMySack|r: " .. msg .. " Items have been highlighted for you.")
                    if f.highlightedBag ~= self.bagID then
                        MySack:ToggleBagHighlight(f, self.bagID)
                    end
                    return
                end

                local s = bagInvSlot(self.bagID)
                if s then
                    if _G.PickupBagFromSlot then
                        PickupBagFromSlot(s)
                    elseif _G.PickupInventoryItem then
                        PickupInventoryItem(s)
                    end
                end
            end)
            b:SetScript("OnReceiveDrag", function(self)
                local isBankFrame = (f:GetName() == "MySackBankFrame")
                local isLocked = isBankFrame and isBankBagLocked(self.bagID)
                if isLocked then return end
                PlaceOrSwapBag(f, self.bagID)
            end)
        end
        f.bagBar[bagID] = b
        lastButton = b
        x = x + 25
    end
    f.lastBagButton = lastButton
end

local function UpdateBagBar(f)
    if not f.bagBar then return end
    local isBankFrame = (f:GetName() == "MySackBankFrame")
    for bagID, b in pairs(f.bagBar) do
        local isLocked = isBankFrame and isBankBagLocked(bagID)
        if isLocked then
            b.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
            b.icon:SetDesaturated(true)
            b.icon:SetVertexColor(0.8, 0.3, 0.3)
        elseif bagID == 0 then
            b.icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
            b.icon:SetDesaturated(false)
            b.icon:SetVertexColor(1, 1, 1)
        elseif bagID == -1 then
            b.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
            b.icon:SetDesaturated(false)
            b.icon:SetVertexColor(1, 1, 1)
        elseif bagID == -2 or (C.KEYRING and bagID == C.KEYRING) then
            b.icon:SetTexture("Interface\\ContainerFrame\\KeyRing-Bag-Icon")
            b.icon:SetDesaturated(false)
            b.icon:SetVertexColor(1, 1, 1)
        else
            local s = bagInvSlot(bagID)
            local tex = nil
            if s then
                local link = GetInventoryItemLink("player", s)
                local id = link and tonumber(link:match("item:(%d+)"))
                if id then
                    if C_Item and C_Item.GetItemIconByID then
                        tex = C_Item.GetItemIconByID(id)
                    elseif GetItemIcon then
                        tex = GetItemIcon(id)
                    end
                end
                if not tex then
                    tex = GetInventoryItemTexture("player", s)
                end
            end

            if tex then
                b.icon:SetTexture(tex)
                b.icon:SetDesaturated(false)
                b.icon:SetVertexColor(1, 1, 1)
            elseif C.IsReagentBag and C.IsReagentBag(bagID) then
                local blizz = _G.CharacterReagentBag0Slot
                local atlas = nil
                if blizz then
                    if blizz.GetNormalTexture and blizz:GetNormalTexture() and blizz:GetNormalTexture().GetAtlas then
                        atlas = blizz:GetNormalTexture():GetAtlas()
                    end
                    if not atlas and blizz.icon and blizz.icon.GetAtlas then
                        atlas = blizz.icon:GetAtlas()
                    end
                end
                if atlas and b.icon.SetAtlas then
                    b.icon:SetAtlas(atlas)
                    b.icon:SetDesaturated(false)
                    b.icon:SetVertexColor(1, 1, 1)
                else
                    local rTex = blizz and ((blizz.icon and blizz.icon:GetTexture()) or (_G["CharacterReagentBag0SlotIcon"] and _G["CharacterReagentBag0SlotIcon"]:GetTexture()) or (blizz.GetNormalTexture and blizz:GetNormalTexture() and blizz:GetNormalTexture():GetTexture()))
                    if rTex then
                        b.icon:SetTexture(rTex)
                        b.icon:SetDesaturated(false)
                        b.icon:SetVertexColor(1, 1, 1)
                    else
                        b.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10_Green")
                        b.icon:SetDesaturated(false)
                        b.icon:SetVertexColor(0.8, 0.9, 0.8)
                    end
                end
            else
                b.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
                b.icon:SetDesaturated(true)
                b.icon:SetVertexColor(0.4, 0.4, 0.4)
            end
        end
        if b.selectedGlow then
            if f.highlightedBag == bagID then
                b.selectedGlow:Show()
            else
                b.selectedGlow:Hide()
            end
        end
    end
    if NS.UpdateBackpackButtonFreeSlots then
        pcall(NS.UpdateBackpackButtonFreeSlots)
    end
end

local sorting = false
local sortingBank = false

local function consolidateStacks(isBank)
    if InCombatLockdown() then return false end
    if CursorHasItem() then return false end

    local bags = isBank and C.BANK_BAGS or C.BACKPACK_BAGS
    local partials = {}

    for _, bag in ipairs(bags) do
        if not isBank or not isBankBagLocked(bag) then
            local n = C.NumSlots(bag)
            for slot = 1, n do
                local info = C.ItemInfo(bag, slot)
                if info and info.itemID and info.link and not info.locked then
                    local _, _, _, _, _, _, _, maxStack = GetItemInfo(info.link)
                    if maxStack and info.count < maxStack then
                        partials[info.itemID] = partials[info.itemID] or {}
                        table.insert(partials[info.itemID], {
                            bag = bag,
                            slot = slot,
                            count = info.count,
                            maxStack = maxStack,
                        })
                    end
                end
            end
        end
    end

    for itemID, list in pairs(partials) do
        if #list > 1 then
            -- Merge smaller stacks first to maximize freed slots
            table.sort(list, function(a, b) return a.count < b.count end)
            local src = list[1]
            local dest = list[2]

            C.PickupItem(src.bag, src.slot)
            if CursorHasItem() then
                C.PickupItem(dest.bag, dest.slot)
                ClearCursor()
                return true
            end
        end
    end
    return false
end

local function runSortSequence(isBank)
    if InCombatLockdown() then
        sorting = false
        sortingBank = false
        return
    end

    local merged = consolidateStacks(isBank)
    if merged then
        if isBank then sortingBank = true else sorting = true end
    else
        if isBank then
            sortingBank = false
            if C.SortBankBags then C.SortBankBags() end
        else
            sorting = false
            if C.SortBags then C.SortBags() end
        end
        print("|cff66ccffMySack|r sorting bags...")
        if C_Timer and C_Timer.After then
            C_Timer.After(0.25, function()
                local f = isBank and NS.bank or NS.main
                if f and f:IsShown() then MySack:Render(f) end
            end)
        else
            local f = isBank and NS.bank or NS.main
            if f then MySack:Render(f) end
        end
    end
end

function NS.ApplySavedPosition(f)
    if not f then return end
    local isBank = (f:GetName() == "MySackBankFrame" or f == NS.bank)
    local db = NS.db or {}
    local p = isBank and db.bankPoint or db.point
    if not p then
        p = isBank and { "TOPLEFT", nil, "TOPLEFT", 40, -104 } or { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -40, 80 }
    end
    f:ClearAllPoints()
    f:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
end

-- ===========================================================================
-- Container frame factory. Used for both the backpack window and the bank.
-- ===========================================================================
local function CreateContainer(name, bagList, titleText)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f.bagList = bagList
    f.buttons = {}              -- flat pool of item buttons
    f.headers = {}              -- category header fontstrings (pool)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:Hide()
    if name and _G.UISpecialFrames then tinsert(_G.UISpecialFrames, name) end
    f:HookScript("OnShow", function(self)
        if NS.ApplySavedPosition then
            NS.ApplySavedPosition(self)
        end
    end)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    end

    -- Title bar (drag handle)
    local title = CreateFrame("Frame", nil, f)
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetPoint("TOPRIGHT", -8, -8)
    title:SetHeight(24)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and NS.ToggleConfig then
            local ok, err = pcall(NS.ToggleConfig)
            if not ok then print("|cffff4444MySack config error:|r "..tostring(err)) end
        end
    end)
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, _, rp, x, y = f:GetPoint()
        local isBank = (f:GetName() == "MySackBankFrame" or f == NS.bank)
        local store = isBank and S().bankPoint or S().point
        if not store then
            store = {}
            if isBank then
                if NS.db then NS.db.bankPoint = store end
            else
                if NS.db then NS.db.point = store end
            end
        end
        store[1], store[2], store[3], store[4], store[5] = p, nil, rp, x, y
    end)
    f.title = title

    local tt = title:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tt:SetPoint("LEFT", 26, 0)
    tt:SetText(titleText)
    f.titleText = tt

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetFrameLevel(f:GetFrameLevel() + 10) -- Ensure it receives clicks over the title drag frame
    close:SetScript("OnClick", function() f:Hide() end)

    -- Money display (placed on far right)
    local money = CreateFrame("Frame", name and (name.."Money"), f, "SmallMoneyFrameTemplate")
    if money then
        money:SetPoint("BOTTOMRIGHT", -12, 13)
        if money.SetType then MoneyFrame_SetType(money, "PLAYER") end
        money:EnableMouse(true)
        f.money = money
    end

    -- Treasure Chest / Gold Overview Button (placed to the left of money)
    local goldb = CreateFrame("Button", nil, f)
    goldb:SetSize(18, 18)
    goldb:SetPoint("RIGHT", money, "LEFT", -4, 0)
    goldb:SetNormalTexture("Interface\\Icons\\INV_Box_01")
    goldb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    goldb:RegisterForClicks("LeftButtonUp")
    goldb:SetFrameLevel(f:GetFrameLevel() + 20)

    local function showGoldTooltip(owner)
        local DB = _G.MySackDB
        if not DB then return end
        DB.itemData = DB.itemData or {}

        local myKey = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
        DB.itemData[myKey] = DB.itemData[myKey] or {}
        DB.itemData[myKey].money = GetMoney()

        GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
        GameTooltip:ClearLines()

        local totalMoney = 0
        local charList = {}

        for key, cdata in pairs(DB.itemData) do
            local m = cdata.money or 0
            totalMoney = totalMoney + m
            table.insert(charList, { key = key, money = m })
        end

        table.sort(charList, function(a, b)
            if a.key == myKey then return true end
            if b.key == myKey then return false end
            return a.money > b.money
        end)

        GameTooltip:AddLine("Account Gold Overview", 1, 0.82, 0)
        GameTooltip:AddLine(" ")

        local function formatCoin(amt)
            if GetCoinTextureString then
                return GetCoinTextureString(amt)
            end
            local g = math.floor(amt / 10000)
            local s = math.floor((amt % 10000) / 100)
            local c = amt % 100
            local str = ""
            if g > 0 then str = str .. g .. "g " end
            if s > 0 or g > 0 then str = str .. s .. "s " end
            str = str .. c .. "c"
            return str
        end

        for _, info in ipairs(charList) do
            local shortName = info.key:match("^[^ -]+") or info.key
            local altRealm = info.key:match(" - (.+)$")
            local curRealm = GetRealmName()
            if altRealm and altRealm ~= curRealm then
                shortName = shortName .. " (" .. altRealm .. ")"
            end

            local isMe = (info.key == myKey)
            local nameStr = isMe and string.format("|cfffd9b1a%s|r", shortName) or string.format("|cff44aaff%s|r", shortName)
            local moneyStr = formatCoin(info.money)

            GameTooltip:AddDoubleLine("  " .. nameStr, moneyStr)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Total Gold:", formatCoin(totalMoney), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end

    if money then
        money:SetScript("OnEnter", function(self) showGoldTooltip(self) end)
        money:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    goldb:SetScript("OnEnter", function(self) showGoldTooltip(self) end)
    goldb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    goldb:SetScript("OnClick", function()
        local DB = _G.MySackDB
        if not DB then return end
        DB.itemData = DB.itemData or {}

        local myKey = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
        DB.itemData[myKey] = DB.itemData[myKey] or {}
        DB.itemData[myKey].money = GetMoney()

        local totalMoney = 0
        local charList = {}

        for key, cdata in pairs(DB.itemData) do
            local m = cdata.money or 0
            totalMoney = totalMoney + m
            table.insert(charList, { key = key, money = m })
        end

        table.sort(charList, function(a, b)
            if a.key == myKey then return true end
            if b.key == myKey then return false end
            return a.money > b.money
        end)

        local function formatCoinText(amt)
            local g = math.floor(amt / 10000)
            local s = math.floor((amt % 10000) / 100)
            local c = amt % 100
            return string.format("%dg %ds %dc", g, s, c)
        end

        print("|cff66ccffMySack Gold Overview:|r Total across account: " .. formatCoinText(totalMoney))
        for _, info in ipairs(charList) do
            local shortName = info.key:match("^[^ -]+") or info.key
            local isMe = (info.key == myKey)
            local nameStr = isMe and string.format("|cfffd9b1a%s|r", shortName) or string.format("|cff44aaff%s|r", shortName)
            print(string.format("  %s: %s", nameStr, formatCoinText(info.money)))
        end
    end)
    f.goldButton = goldb

    -- Free-slot text
    local free = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    free:SetPoint("BOTTOMLEFT", 14, 34)
    f.freeText = free

    -- Bank button (main window only) at bottom to open the bank view
    if name == "MySackFrame" then
      local bankb = CreateFrame("Button", nil, f)
      bankb:SetSize(18, 18)
      bankb:SetPoint("RIGHT", goldb, "LEFT", -4, 0)
      bankb:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_08")
      bankb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      bankb:RegisterForClicks("LeftButtonUp")
      bankb:SetFrameLevel(f:GetFrameLevel() + 20)
      bankb:SetScript("OnClick", function()
        if not NS.bank then
          print("|cffff4444MySack:|r Bank window not available.")
          return
        end
        NS.bank:ClearAllPoints()
        local p = NS.db.bankPoint or { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
        NS.bank:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
        NS.bank:Show()
        if MySack and MySack.Render then
          MySack:Render(NS.bank)
        end
      end)
      bankb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bank")
        if NS.bankOpen then
          GameTooltip:AddLine("Bank is currently open.", 0.8, 1, 0.8)
        else
          GameTooltip:AddLine("Open when at a banker to populate contents.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
      end)
      bankb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f.bankButton = bankb
    end

    -- Bags button (bank window only) at bottom to go back to bags view
    if name == "MySackBankFrame" then
      local bagsb = CreateFrame("Button", nil, f)
      bagsb:SetSize(18, 18)
      bagsb:SetPoint("RIGHT", goldb, "LEFT", -4, 0)
      bagsb:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_09")
      bagsb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      bagsb:RegisterForClicks("LeftButtonUp")
      bagsb:SetFrameLevel(f:GetFrameLevel() + 20)
      bagsb:SetScript("OnClick", function()
        if NS.main then
          NS.main:Show()
          if MySack and MySack.Render then MySack:Render(NS.main) end
        end
      end)
      bagsb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Bags")
        GameTooltip:Show()
      end)
      bagsb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f.bagsButton = bagsb

      local blizzb = CreateFrame("Button", nil, f)
      blizzb:SetSize(18, 18)
      blizzb:SetPoint("RIGHT", bagsb, "LEFT", -4, 0)
      blizzb:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
      blizzb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      blizzb:RegisterForClicks("LeftButtonUp")
      blizzb:SetFrameLevel(f:GetFrameLevel() + 20)
      blizzb:SetScript("OnClick", function()
        if not NS.bankOpen then
          print("|cff66ccffMySack|r: You must visit a banker to open the default banker window.")
          return
        end
        if _G.BankFrame then
          local currentAlpha = _G.BankFrame:GetAlpha()
          if currentAlpha == 0 or not _G.BankFrame:IsShown() then
            _G.BankFrame:SetAlpha(1)
            _G.BankFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            _G.BankFrame:Show()
            -- ShowUIPanel omitted to prevent UIParentPanelManager / BankFrame taint
            print("|cff66ccffMySack|r: Default Banker window shown (use this to buy bank slots or manage tabs).")
          else
            _G.BankFrame:SetAlpha(0)
            _G.BankFrame:SetFrameStrata("MEDIUM")
            print("|cff66ccffMySack|r: Default Banker window hidden.")
          end
        end
      end)
      blizzb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Toggle Default Banker Window")
        GameTooltip:AddLine("Show or hide Blizzard's native bank frame to purchase bank slots or manage tabs.", 1, 1, 1)
        GameTooltip:Show()
      end)
      blizzb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f.blizzBankButton = blizzb
    end

    -- Search box
    local search = CreateFrame("EditBox", name and (name.."Search"), f, "InputBoxTemplate")
    search:SetAutoFocus(false)
    search:SetHeight(20)
    search:SetWidth(140)
    search:SetPoint("TOPRIGHT", -42, -10)
    search:SetFrameLevel(f:GetFrameLevel() + 20)
    search:SetScript("OnTextChanged", function(self) f.searchText = (self:GetText() or ""):lower(); MySack:ApplySearch(f) end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local sl = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sl:SetPoint("LEFT", search, "LEFT", 4, 0)
    sl:SetText("Search")
    search.placeholder = sl
    search:SetScript("OnEditFocusGained", function() sl:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then sl:Show() end end)
    f.search = search

    -- Settings button: a small cog at the top-left of the window, clear of the
    -- search/sort cluster so nothing can intercept its clicks.
    local cfg = CreateFrame("Button", nil, f)
    cfg:SetSize(20, 20)
    cfg:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -9)
    cfg:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    cfg:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    cfg:RegisterForClicks("LeftButtonUp")
    cfg:SetFrameLevel(f:GetFrameLevel() + 20)
    cfg:SetScript("OnClick", function()
        if not NS.ToggleConfig then print("|cffff4444MySack:|r settings module not loaded.") return end
        local ok, err = pcall(NS.ToggleConfig)
        if not ok then print("|cffff4444MySack config error:|r "..tostring(err)) end
    end)
    cfg:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("MySack settings")
        GameTooltip:Show()
    end)
    cfg:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.configButton = cfg

    -- Sort button (finishes the search/sort cluster mentioned in docs)
    local sortb = CreateFrame("Button", nil, f)
    sortb:SetSize(18, 18)
    sortb:SetPoint("TOPRIGHT", search, "TOPLEFT", -4, -1)
    sortb:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    sortb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    sortb:RegisterForClicks("LeftButtonUp")
    sortb:SetFrameLevel(f:GetFrameLevel() + 20)
    sortb:SetScript("OnClick", function()
        local isBank = (f == NS.bank)
        runSortSequence(isBank)
    end)
    sortb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sort bags")
        GameTooltip:Show()
    end)
    sortb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.sortButton = sortb

    -- Alt Character Inspector Dropdown button (placed to the left of sort button)
    local charb = CreateFrame("Button", nil, f)
    charb:SetSize(18, 18)
    charb:SetPoint("TOPRIGHT", sortb, "TOPLEFT", -4, 0)
    charb:SetNormalTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    charb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    charb:RegisterForClicks("LeftButtonUp")
    charb:SetFrameLevel(f:GetFrameLevel() + 20)
    charb:SetScript("OnClick", function(self)
        if NS.ShowCharacterMenu then NS.ShowCharacterMenu(self, f) end
    end)
    charb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Switch Character View")
        GameTooltip:AddLine("Click to view cached inventory or bank of your alts.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    charb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.charButton = charb

    -- Deposit Reagents button (Bank window only, placed to the left of character button)
    if name == "MySackBankFrame" then
        local depb = CreateFrame("Button", nil, f)
        depb:SetSize(18, 18)
        depb:SetPoint("TOPRIGHT", charb, "TOPLEFT", -4, 0)
        depb:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_10")
        depb:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        depb:RegisterForClicks("LeftButtonUp")
        depb:SetFrameLevel(f:GetFrameLevel() + 20)
        depb:SetScript("OnClick", function()
            if NS.DepositReagentsToBank then NS.DepositReagentsToBank() end
        end)
        depb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Deposit Reagents & Trade Goods")
            GameTooltip:AddLine("Automatically moves trade goods, herbs, ores, gems, and recipes into your bank.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        depb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.depositButton = depb
    end

    if name == "MySackFrame" then
        local mainBags = {}
        for _, b in ipairs(C.BACKPACK_BAGS) do
            if b ~= -1 and b ~= C.BANK_CONTAINER then
                table.insert(mainBags, b)
            end
        end
        if C.HasKeyring and C.HasKeyring() then
            table.insert(mainBags, C.KEYRING or -2)
        end
        BuildBagBar(f, mainBags)
    elseif name == "MySackBankFrame" then
        BuildBagBar(f, C.BANK_BAGS)
    end

    -- Resize grip (bottom-right corner). Dragging it changes how many items per row.
    f:SetResizable(true)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -6, 6)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip.sizing = false
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to resize (items per row)")
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(self)
        self.sizing = true
        -- Re-anchor to TOPLEFT so the window grows rightward/downward instead of
        -- from the center (which made resizing feel jumpy).
        local left, top = f:GetLeft(), f:GetTop()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self.sizing = false
        local isBank = (f:GetName() == "MySackBankFrame" or f == NS.bank)
        local store = isBank and S().bankPoint or S().point
        local p, _, rp, x, y = f:GetPoint()
        if not store then
            store = {}
            if isBank then
                if NS.db then NS.db.bankPoint = store end
            else
                if NS.db then NS.db.point = store end
            end
        end
        store[1], store[2], store[3], store[4], store[5] = p, nil, rp, x, y
    end)
    grip:SetScript("OnUpdate", function(self)
        if not self.sizing then return end
        local set = S()
        if not set then return end
        local isBank = (f == NS.bank)
        local iconSize = isBank and (set.bankIconSize or set.iconSize) or set.iconSize
        local currentCols = isBank and (set.bankColumns or set.columns) or set.columns
        local scale = f:GetEffectiveScale()
        local cx = GetCursorPosition() / scale
        local width = cx - f:GetLeft()
        local cols = math.floor((width - 14 - 8) / (iconSize + set.iconSpacing))
        cols = math.max(4, math.min(32, cols))
        if cols ~= currentCols then
            if isBank then
                set.bankColumns = cols
            else
                set.columns = cols
            end
            MySack:Render(f)
            if NS.RefreshConfig then NS.RefreshConfig() end
        end
    end)
    f.grip = grip

    return f
end

local charMenuFrame
function NS.ShowCharacterMenu(anchorButton, hostFrame)
    if not charMenuFrame then
        charMenuFrame = CreateFrame("Frame", "MySackCharMenuFrame", UIParent, "BackdropTemplate")
        charMenuFrame:SetFrameStrata("TOOLTIP")
        charMenuFrame:SetClampedToScreen(true)
        charMenuFrame:EnableMouse(true)
        if charMenuFrame.SetBackdrop then
            charMenuFrame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
        end
        charMenuFrame.buttons = {}
        
        local closeTrigger = CreateFrame("Button", nil, charMenuFrame)
        closeTrigger:SetAllPoints(UIParent)
        closeTrigger:SetFrameLevel(charMenuFrame:GetFrameLevel() - 1)
        closeTrigger:SetScript("OnClick", function() charMenuFrame:Hide() end)
    end

    if charMenuFrame:IsShown() then
        charMenuFrame:Hide()
        return
    end

    for _, b in ipairs(charMenuFrame.buttons) do b:Hide() end

    local DB = _G.MySackDB
    if not DB or not DB.itemData then return end

    local menuItems = {}
    local currentKey = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")

    table.insert(menuItems, {
        text = "Current Character (" .. currentKey .. ")",
        func = function()
            hostFrame.viewingAltKey = nil
            hostFrame.titleText:SetText(hostFrame == NS.bank and "MySack - Bank" or "MySack")
            if MySack and MySack.Render then MySack:Render(hostFrame) end
            charMenuFrame:Hide()
        end
    })

    for charKey, _ in pairs(DB.itemData) do
        if charKey ~= currentKey and charKey ~= "nil" then
            local displayName = charKey
            table.insert(menuItems, {
                text = "Alt: " .. displayName,
                func = function()
                    hostFrame.viewingAltKey = charKey
                    hostFrame.titleText:SetText((hostFrame == NS.bank and "MySack Bank - " or "MySack - ") .. displayName)
                    if MySack and MySack.Render then MySack:Render(hostFrame) end
                    charMenuFrame:Hide()
                end
            })
        end
    end

    local itemHeight = 22
    local totalHeight = #menuItems * itemHeight + 12
    charMenuFrame:SetSize(220, totalHeight)
    charMenuFrame:ClearAllPoints()
    charMenuFrame:SetPoint("TOPRIGHT", anchorButton, "BOTTOMRIGHT", 0, -4)

    for i, item in ipairs(menuItems) do
        local btn = charMenuFrame.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, charMenuFrame)
            btn:SetHeight(itemHeight)
            btn:SetPoint("LEFT", 6, 0)
            btn:SetPoint("RIGHT", -6, 0)
            
            local font = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            font:SetPoint("LEFT", 8, 0)
            btn.text = font

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetColorTexture(1, 1, 1, 0.15)
            hl:SetAllPoints()

            charMenuFrame.buttons[i] = btn
        end

        btn:SetPoint("TOPLEFT", charMenuFrame, "TOPLEFT", 6, -6 - (i - 1) * itemHeight)
        btn.text:SetText(item.text)
        btn:SetScript("OnClick", item.func)
        btn:Show()
    end

    charMenuFrame:Show()
end

-- ===========================================================================
-- Item button helpers
-- ===========================================================================
local blizzardButtonPool = nil

local function GetPooledBlizzardButton()
    if blizzardButtonPool == nil then
        blizzardButtonPool = {}
        local maxFrames = _G.NUM_CONTAINER_FRAMES or 13
        for c = 1, maxFrames do
            for i = 1, 36 do
                local item = _G[("ContainerFrame%dItem%d"):format(c, i)]
                if item then
                    item:SetID(0)
                    item:ClearAllPoints()
                    table.insert(blizzardButtonPool, item)
                end
            end
        end
    end
    if #blizzardButtonPool > 0 then
        return table.remove(blizzardButtonPool)
    end
    return nil
end

local function GetOrCreateDummyBag(f, bagID)
    f.dummyBags = f.dummyBags or {}
    if not f.dummyBags[bagID] then
        local dummy = CreateFrame("Frame", f:GetName().."DummyBag"..bagID, f)
        dummy:SetID(bagID)
        dummy.IsCombinedBagContainer = function() return false end
        f.dummyBags[bagID] = dummy
    end
    return f.dummyBags[bagID]
end

local function GetOrCreateButton(f, index, bagID)
    local btn = f.buttons[index]
    local dummyBag = GetOrCreateDummyBag(f, bagID or 0)
    if not btn then
        btn = GetPooledBlizzardButton()
        local nm
        if btn then
            nm = btn:GetName()
            btn:SetParent(dummyBag)
        else
            nm = f:GetName().."Item"..index
            btn = CreateFrame("ItemButton", nm, dummyBag, "ContainerFrameItemButtonTemplate")
        end
        btn:SetFrameLevel(f:GetFrameLevel() + 5)  -- ensure clicks go to item buttons over other elements

        -- Ensure texture reference aliases and suppress default cyan glow
        btn.icon = btn.icon or _G[nm.."IconTexture"] or btn:CreateTexture(nil, "BORDER")
        btn.Count = btn.Count or _G[nm.."Count"] or btn:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
        if btn.NewItemTexture then btn.NewItemTexture:Hide() end
        if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide() end
        if _G[nm.."NewItemTexture"] then _G[nm.."NewItemTexture"]:Hide() end
        if _G[nm.."BattlepayItemTexture"] then _G[nm.."BattlepayItemTexture"]:Hide() end

        -- Custom right-click modifiers (Alt-click category selector, Ctrl-click junk protection).
        -- Hook OnModifiedClick instead of OnMouseDown!
        -- ContainerFrameItemButtonMixin:OnClick only calls OnModifiedClick when a modifier (Alt/Ctrl/Shift)
        -- is down. For normal (unmodified) right-clicks, OnModifiedClick is NEVER called, leaving
        -- normal right-clicks 100% untainted and avoiding ADDON_ACTION_BLOCKED on UseContainerItem.
        if btn.OnModifiedClick then
            hooksecurefunc(btn, "OnModifiedClick", function(self, button)
                if button == "RightButton" and self.mysackData then
                    if IsAltKeyDown() then
                        if NS.MySack.OnItemRightClick then
                            NS.MySack:OnItemRightClick(self)
                        end
                    elseif IsControlKeyDown() then
                        local id = self.mysackData.itemID
                        if id then
                            NS.db.userProtect = NS.db.userProtect or {}
                            if NS.db.userProtect[id] then
                                NS.db.userProtect[id] = nil
                                print("|cff66ccffMySack|r removed from protected list.")
                            else
                                NS.db.userProtect[id] = true
                                print("|cff66ccffMySack|r item protected from auto-sell.")
                            end
                            if NS.RefreshProtectList then NS.RefreshProtectList() end
                            if NS.main then NS.MySack:Render(NS.main) end
                        end
                    end
                end
            end)
        elseif btn.HookScript then
            btn:HookScript("OnMouseDown", function(self, button)
                if button == "RightButton" and self.mysackData and (IsAltKeyDown() or IsControlKeyDown()) then
                    if IsAltKeyDown() then
                        if NS.MySack.OnItemRightClick and NS.MySack:OnItemRightClick(self) then
                            return
                        end
                    elseif IsControlKeyDown() then
                        local id = self.mysackData.itemID
                        if id then
                            NS.db.userProtect = NS.db.userProtect or {}
                            if NS.db.userProtect[id] then
                                NS.db.userProtect[id] = nil
                                print("|cff66ccffMySack|r removed from protected list.")
                            else
                                NS.db.userProtect[id] = true
                                print("|cff66ccffMySack|r item protected from auto-sell.")
                            end
                            if NS.RefreshProtectList then NS.RefreshProtectList() end
                            if NS.main then NS.MySack:Render(NS.main) end
                        end
                    end
                end
            end)
        end

        -- Cache overlay for offline bank or alt bag views.
        -- When viewing live bags, this overlay is hidden so Blizzard's native
        -- ContainerFrameItemButtonTemplate scripts handle tooltips and clicks without taint.
        local overlay = CreateFrame("Button", nm.."CacheOverlay", btn)
        overlay:SetAllPoints(btn)
        overlay:SetFrameLevel(btn:GetFrameLevel() + 2)
        overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        overlay:EnableMouse(true)
        overlay:Hide()

        overlay:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            local data = parent and parent.mysackData
            if not data then return end
            GameTooltip:SetOwner(parent, "ANCHOR_RIGHT")
            local link = data.link or (data.itemID and select(2, GetItemInfo(data.itemID)))
            local itemID = data.itemID or (link and tonumber(link:match("item:(%d+)")))

            local function HasValidItemText()
                local txt = _G["GameTooltipTextLeft1"] and _G["GameTooltipTextLeft1"]:GetText()
                return txt and txt ~= "" and txt ~= "Vendor" and txt ~= "Auction"
            end

            if link then
                local itemStr = link:match("|H(item:[^|]+)|h") or link:match("(item:[%-?%d:]+)")
                if itemStr then
                    pcall(GameTooltip.SetHyperlink, GameTooltip, itemStr)
                end
                if not HasValidItemText() then
                    pcall(GameTooltip.SetHyperlink, GameTooltip, link)
                end
            end
            if not HasValidItemText() and itemID and GameTooltip.SetItemByID then
                pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
            end
            GameTooltip:Show()
            if GameTooltip_ShowCompareItem then
                pcall(GameTooltip_ShowCompareItem, GameTooltip)
            end
        end)

        overlay:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if GameTooltip_HideShoppingTooltips then
                GameTooltip_HideShoppingTooltips(GameTooltip)
            end
            if _G.ShoppingTooltip1 then _G.ShoppingTooltip1:Hide() end
            if _G.ShoppingTooltip2 then _G.ShoppingTooltip2:Hide() end
        end)

        overlay:SetScript("OnClick", function(self, button)
            local parent = self:GetParent()
            if not parent then return end
            if button == "RightButton" and parent.mysackData then
                if IsAltKeyDown() and NS.MySack.OnItemRightClick and NS.MySack:OnItemRightClick(parent) then
                    return
                end
                if IsControlKeyDown() then
                    local id = parent.mysackData.itemID
                    if id then
                        NS.db.userProtect = NS.db.userProtect or {}
                        if NS.db.userProtect[id] then
                            NS.db.userProtect[id] = nil
                            print("|cff66ccffMySack|r removed from protected list.")
                        else
                            NS.db.userProtect[id] = true
                            print("|cff66ccffMySack|r item protected from auto-sell.")
                        end
                        if NS.RefreshProtectList then NS.RefreshProtectList() end
                        if NS.main then NS.MySack:Render(NS.main) end
                    end
                    return
                end
            end
            if button == "LeftButton" and IsModifiedClick() then
                local link = parent.mysackData and parent.mysackData.link
                if link and HandleModifiedItemClick then
                    HandleModifiedItemClick(link)
                end
            end
        end)

        btn.cacheOverlay = overlay

        f.buttons[index] = btn
    else
        btn:SetParent(dummyBag)
    end
    return btn
end

local function EnsureOverlays(btn)
    if btn.msOverlaysBuilt then return end
    btn.msOverlaysBuilt = true
    local il = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    il:SetPoint("TOPLEFT", 2, -2)
    btn.msIlvl = il
    local qb = btn:CreateTexture(nil, "OVERLAY")
    qb:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    qb:SetBlendMode("ADD"); qb:SetAlpha(0.7); qb:SetVertexColor(1, 0.9, 0.1)
    qb:SetPoint("CENTER"); qb:SetSize(btn:GetWidth()*1.55, btn:GetHeight()*1.55); qb:Hide()
    btn.msQuest = qb
    local rc = btn:CreateTexture(nil, "OVERLAY")
    rc:SetTexture("Interface\\Icons\\INV_Scroll_03")
    rc:SetPoint("BOTTOMLEFT", 2, 2); rc:SetSize(12, 12); rc:Hide()
    btn.msRecipe = rc
    local ng = btn:CreateTexture(nil, "OVERLAY")
    ng:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    ng:SetBlendMode("ADD"); ng:SetVertexColor(0.2, 1, 0.2)
    ng:SetPoint("CENTER"); ng:SetSize(btn:GetWidth()*1.55, btn:GetHeight()*1.55); ng:Hide()
    btn.msNew = ng
    local bh = btn:CreateTexture(nil, "OVERLAY")
    bh:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    bh:SetBlendMode("ADD")
    bh:SetVertexColor(1, 0.85, 0.1, 0.95)
    bh:SetPoint("TOPLEFT", -2, 2)
    bh:SetPoint("BOTTOMRIGHT", 2, -2)
    bh:Hide()
    btn.msBagHighlight = bh
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn.msBg = bg
    local edges = {}
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        local e = btn:CreateTexture(nil, "OVERLAY", nil, 2)
        e:SetColorTexture(1, 1, 1, 1)
        edges[k] = e
    end
    edges.top:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    edges.top:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    edges.bottom:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    edges.bottom:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    edges.left:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    edges.left:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    edges.right:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, 0)
    edges.right:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn.msEdges = edges
end



local function GetSlotDataForFrame(f, bag, slot)
    local isBankFrame = (f == NS.bank)
    local offlineBank = isBankFrame and not NS.bankOpen
    local myKey = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    local viewingAlt = f.viewingAltKey and (f.viewingAltKey ~= myKey)
    local activeKey = viewingAlt and f.viewingAltKey or myKey

    if viewingAlt then
        local DB = _G.MySackDB
        local cdata = DB and DB.itemData and DB.itemData[activeKey]
        if isBankFrame then
            local snap = cdata and cdata.bankSnapshot
            return snap and snap[bag] and snap[bag][slot] or nil
        else
            if NS.GetBagSnapshotItem then
                local item = NS.GetBagSnapshotItem(activeKey, bag, slot)
                if item then return item end
            end
            return f.altBagSlots and f.altBagSlots[bag] and f.altBagSlots[bag][slot] or nil
        end
    elseif offlineBank and NS.GetBankSnapshotItem then
        return NS.GetBankSnapshotItem(bag, slot)
    end
    return C.ItemInfo(bag, slot)
end

local function UpdateButton(f, btn, bag, slot, cachedData)
    local dummyBag = GetOrCreateDummyBag(f, bag)
    if btn:GetParent() ~= dummyBag then
        btn:SetParent(dummyBag)
    end
    btn:SetID(slot or 0)
    if btn.SetBagID then
        btn:SetBagID(bag or 0)
    else
        btn:SetAttribute("bagid", bag or 0)
    end
    btn.bagID = bag or 0
    btn.containerFrame = dummyBag

    btn.mysackBag = bag
    btn.mysackSlot = slot
    btn.mysackData = cachedData or C.ItemInfo(bag, slot)
    local data = btn.mysackData
    EnsureOverlays(btn)

    if data then
        btn.icon:SetTexture(data.icon)
        btn.icon:SetDesaturated(data.locked and true or false)
        btn.icon:Show()
        if (data.count or 1) > 1 then btn.Count:SetText(data.count); btn.Count:Show()
        else btn.Count:SetText(""); btn.Count:Hide() end
        btn.hasItem = true
        btn:SetAlpha(1)

        local set = S()
        if (set.showItemLevel ~= false) and data.link then
            local _, _, quality, iLevel, _, _, _, _, equipSlot = GetItemInfo(data.link)
            local lvl = iLevel
            if GetDetailedItemLevelInfo then local d = GetDetailedItemLevelInfo(data.link); if d and d > 0 then lvl = d end end
            if equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_BAG" and lvl and lvl > 1 then
                btn.msIlvl:SetText(lvl)
                local qcol = (_G.BAG_ITEM_QUALITY_COLORS and _G.BAG_ITEM_QUALITY_COLORS[data.quality or 1]) or (_G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[data.quality or 1])
                if qcol then btn.msIlvl:SetTextColor(qcol.r, qcol.g, qcol.b) else btn.msIlvl:SetTextColor(1,1,1) end
                btn.msIlvl:Show()
            else btn.msIlvl:SetText(""); btn.msIlvl:Hide() end
        elseif btn.msIlvl then btn.msIlvl:SetText(""); btn.msIlvl:Hide() end

        if (set.questBorder ~= false) and data.link then
            local isQuest = C.ItemQuestInfo(bag, slot)
            local _, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(data.link)
            if isQuest or classID == 12 then btn.msQuest:Show() else btn.msQuest:Hide() end
        elseif btn.msQuest then btn.msQuest:Hide() end

        if data.link then
            local _, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(data.link)
            if classID == 9 then btn.msRecipe:Show() else btn.msRecipe:Hide() end
        elseif btn.msRecipe then btn.msRecipe:Hide() end

        if set.newItemGlow and NS.IsNewItem and NS.IsNewItem(data.itemID, bag, slot) then
            btn.msNew:Show()
        elseif btn.msNew then btn.msNew:Hide() end
    else
        btn.icon:SetTexture(nil); btn.icon:Hide()
        btn.Count:SetText(""); btn.Count:Hide()
        btn.hasItem = false
        if btn.msIlvl then btn.msIlvl:Hide() end
        if btn.msQuest then btn.msQuest:Hide() end
        if btn.msRecipe then btn.msRecipe:Hide() end
        if btn.msNew then btn.msNew:Hide() end
    end

    if btn.NewItemTexture then btn.NewItemTexture:Hide() end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide() end
    local nm = btn:GetName()
    if _G[nm.."NewItemTexture"] then _G[nm.."NewItemTexture"]:Hide() end
    if _G[nm.."BattlepayItemTexture"] then _G[nm.."BattlepayItemTexture"]:Hide() end

    -- Quality-colored border (our own; opacity + thickness configurable).
    if btn.msBg then btn.msBg:Show() end
    if btn.msEdges then
        local r, g, b = 0.5, 0.5, 0.5
        if data then
            local q = data.quality
            if q and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q] then
                r, g, b = _G.ITEM_QUALITY_COLORS[q].r, _G.ITEM_QUALITY_COLORS[q].g, _G.ITEM_QUALITY_COLORS[q].b
            else
                r, g, b = 0.85, 0.85, 0.85
            end
        end
        local set = S()
        local a = set.borderOpacity or 1
        local t = set.borderThickness or 2
        for k, e in pairs(btn.msEdges) do
            e:SetColorTexture(r, g, b, a)
            if k == "top" or k == "bottom" then e:SetHeight(t) else e:SetWidth(t) end
            if a <= 0 or t <= 0 then e:Hide() else e:Show() end
        end
    end

    if btn.Cooldown then
        if data then
            local start, duration, enable = C.ItemCooldown(bag, slot)
            CooldownFrame_Set(btn.Cooldown, start, duration, enable)
        else
            btn.Cooldown:Hide()
        end
    end

    -- Toggle cache overlay: only shown when viewing offline bank or alt inventories.
    -- When viewing active player bags, overlay is hidden so Blizzard's native
    -- ContainerFrameItemButtonTemplate scripts run completely untainted.
    if btn.cacheOverlay then
        if f.isCachedView then
            btn.cacheOverlay:Show()
        else
            btn.cacheOverlay:Hide()
        end
    end
end

local function GetOrCreateHeader(f, index)
    local h = f.headers[index]
    if not h then
        h = CreateFrame("Button", nil, f)
        h:SetHeight(16)
        h:EnableMouse(true)
        h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h.text:SetPoint("LEFT", 0, 0)
        h.text:SetJustifyH("LEFT")
        h:SetScript("OnReceiveDrag", function(self) MySack:AssignCursorToCategory(self.catKey) end)
        h:SetScript("OnClick", function(self) MySack:AssignCursorToCategory(self.catKey) end)
        h:SetScript("OnEnter", function(self)
            if self.catKey and self.catKey ~= "EMPTY" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Drag an item here to add it to: "..(Cat.GetName(self.catKey, S()) or self.catKey))
                GameTooltip:AddLine("Drop it on Free Space to clear an assignment.", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.headers[index] = h
    end
    return h
end

-- ===========================================================================
-- Layout: collect items, group by category, place buttons.
-- ===========================================================================
function MySack:Render(f)
    if not f or not f:IsShown() then return end
    f.pendingRender = false
    local set = S()
    local overrides = set.overrides
    local isBankFrame = (f == NS.bank)
    local size, spacing, cols
    if isBankFrame then
        size = set.bankIconSize or set.iconSize
        spacing = set.iconSpacing
        cols = set.bankColumns or set.columns
    else
        size = set.iconSize
        spacing = set.iconSpacing
        cols = set.columns
    end

    -- Bank cached/offline support (TBag-style): use persisted snapshot when away from banker
    local offlineBank = isBankFrame and not NS.bankOpen
    local myKey = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    local viewingAlt = f.viewingAltKey and (f.viewingAltKey ~= myKey)
    local activeKey = viewingAlt and f.viewingAltKey or myKey
    f.isCachedView = (viewingAlt or offlineBank) and true or false

    if viewingAlt and not isBankFrame then
        local DB = _G.MySackDB
        local cdata = DB and DB.itemData and DB.itemData[activeKey]
        if cdata and cdata.bags and (not cdata.bagsSnapshot or not NS.GetBagSnapshotItem) then
            f.altBagSlots = {}
            local slotIdx = 1
            for itemID, count in pairs(cdata.bags) do
                local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or (GetItemIcon and GetItemIcon(itemID))
                local link = select(2, GetItemInfo(itemID)) or ("item:" .. itemID)
                local quality = select(3, GetItemInfo(itemID)) or 1
                local bag = math.floor((slotIdx - 1) / 16)
                local slot = ((slotIdx - 1) % 16) + 1
                f.altBagSlots[bag] = f.altBagSlots[bag] or {}
                f.altBagSlots[bag][slot] = {
                    icon = icon, count = count, quality = quality, link = link, itemID = itemID
                }
                slotIdx = slotIdx + 1
            end
        end
    end

    local shortChar = activeKey:match("^[^ -]+") or activeKey
    if isBankFrame then
        if viewingAlt then
            f.titleText:SetText("MySack Bank (" .. shortChar .. ")")
        else
            f.titleText:SetText(offlineBank and "MySack Bank (cached)" or "MySack Bank")
        end
    else
        if viewingAlt then
            f.titleText:SetText("MySack (" .. shortChar .. ")")
        else
            f.titleText:SetText("MySack")
        end
    end

    -- 1. Gather all occupied + empty slots, grouped by category.
    local groups = {}      -- catKey -> { {bag,slot,data}, ... }
    local emptyCount = 0
    local function add(cat, entry)
        groups[cat] = groups[cat] or {}
        table.insert(groups[cat], entry)
    end

    for _, bag in ipairs(f.bagList) do
        local n
        if offlineBank then
            local DB = _G.MySackDB
            local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
            local ns = DB and DB.itemData and DB.itemData[key] and DB.itemData[key].bankNumSlots
            n = (ns and ns[bag]) or C.NumSlots(bag) or 0
        elseif viewingAlt and not isBankFrame then
            local DB = _G.MySackDB
            local cdata = DB and DB.itemData and DB.itemData[activeKey]
            local ns = cdata and cdata.bagsNumSlots
            n = (ns and ns[bag]) or 16
        else
            n = C.NumSlots(bag)
        end
        for slot = 1, n do
            local data = GetSlotDataForFrame(f, bag, slot)
            local cat
            if isSpecialtyBag(bag) then
                cat = "QUIVER"
            else
                cat = Cat.Classify(data, overrides, set)
            end
            local h = set.hiddenCategories or {}
            if h[cat] then cat = "MISC" end
            if cat == "EMPTY" then emptyCount = emptyCount + 1 end
            add(cat, { bag = bag, slot = slot, data = data })
        end
    end

    -- 2. Sort items within each category by quality desc then name.
    for _, list in pairs(groups) do
        table.sort(list, function(a, b)
            local da, db = a.data, b.data
            if not da and not db then return false end
            if not da then return false end
            if not db then return true end
            if (da.quality or 0) ~= (db.quality or 0) then return (da.quality or 0) > (db.quality or 0) end
            return (da.link or "") < (db.link or "")
        end)
    end

    -- 3. Shelf-pack categories: small categories share a row instead of each
    --    taking a full-width block, which removes most of the dead space.
    local order = Cat.BuildOrder(set)  -- pass full settings for customs/hidden support
    local left, top = 14, 40
    local btnIndex, hdrIndex = 0, 0
    local colW = size + spacing
    local headerH = 14
    local catGapX, catGapY = 1, (set.groupSpacing or 2)   -- gaps in columns (X) and pixels (Y)

    for _, b in ipairs(f.buttons) do b:Hide() end
    for _, h in ipairs(f.headers) do h:Hide() end

    local compact = set.compactLayout ~= false
    local shelfX = 0      -- columns already used on the current shelf
    local shelfY = top    -- pixel top of the current shelf
    local shelfH = 0      -- tallest block height on the current shelf
    local usedCols = 0

    for _, cat in ipairs(order) do
        local list = groups[cat]
        if list and #list > 0 then
            local n = #list
            local itemCols = math.min(n, cols)
            local itemRows = math.ceil(n / itemCols)

            hdrIndex = hdrIndex + 1
            local h = GetOrCreateHeader(f, hdrIndex)
            h.catKey = cat
            h.text:SetText((Cat.GetName(cat, set) or cat) .. "  |cff808080(" .. n .. ")|r")
            local blockCols
            if compact then
                -- Reserve enough width for either the item grid or the header text.
                local textCols = math.ceil((h.text:GetStringWidth() + 6) / colW)
                blockCols = math.min(cols, math.max(itemCols, textCols))
            else
                blockCols = itemCols
            end
            local blockH = headerH + itemRows * colW

            -- Wrap to a new shelf if not compact, or if this block does not fit.
            if shelfX > 0 and (not compact or (shelfX + blockCols) > cols) then
                shelfY = shelfY + shelfH + catGapY
                shelfX = 0
                shelfH = 0
            end

            local blockX = left + shelfX * colW
            h:SetSize(blockCols * colW, headerH)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", f, "TOPLEFT", blockX, -shelfY)
            h:Show()

            local rowY = shelfY + headerH
            local cx, col = blockX, 0
            for _, entry in ipairs(list) do
                btnIndex = btnIndex + 1
                local btn = GetOrCreateButton(f, btnIndex, entry.bag)
                btn:SetSize(size, size)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", f, "TOPLEFT", cx, -rowY)
                UpdateButton(f, btn, entry.bag, entry.slot, entry.data)
                btn:Show()
                col = col + 1
                if col >= itemCols then
                    col = 0; cx = blockX; rowY = rowY + colW
                else
                    cx = cx + colW
                end
            end

            shelfH = math.max(shelfH, blockH)
            if compact then
                shelfX = shelfX + blockCols + catGapX
                usedCols = math.max(usedCols, math.min(shelfX - catGapX, cols))
            else
                usedCols = math.max(usedCols, blockCols)
                shelfY = shelfY + shelfH + catGapY
                shelfX = 0
                shelfH = 0
            end
        end
    end

    -- 4. Resize frame to contents.
    local height = shelfY + shelfH + 55
    local width  = math.max(left + usedCols * colW + 8, 300)
    f:SetSize(width, height)
    if isBankFrame then
        f:SetScale(set.bankScale or set.scale)
    else
        f:SetScale(set.scale)
    end

    -- 5. Free-slot text
    local total, freeTotal = 0, 0
    local isBankFrame = (f == NS.bank)
    local offlineBank = isBankFrame and not NS.bankOpen
    if offlineBank then
        local DB = _G.MySackDB
        local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
        local snap = (DB and DB.itemData and DB.itemData[key] and DB.itemData[key].bankSnapshot) or {}
        local numSnap = (DB and DB.itemData and DB.itemData[key] and DB.itemData[key].bankNumSlots) or {}
        for _, bag in ipairs(f.bagList) do
            if not isSpecialtyBag(bag) then
                local n = numSnap[bag] or C.NumSlots(bag) or 0
                total = total + n
                local occ = 0
                if snap[bag] then for _ in pairs(snap[bag]) do occ = occ + 1 end end
                freeTotal = freeTotal + (n - occ)
            end
        end
        f.freeText:SetText(string.format("|cffffd100%d|r free / %d slots (cached)", freeTotal, total))
    else
        for _, bag in ipairs(f.bagList) do
            if not isSpecialtyBag(bag) then
                local n = C.NumSlots(bag)
                total = total + n
                for slot = 1, n do
                    if not C.ItemInfo(bag, slot) then freeTotal = freeTotal + 1 end
                end
            end
        end
        f.freeText:SetText(string.format("|cffffd100%d|r free / %d slots", freeTotal, total))
    end
    UpdateBagBar(f)

    if f.money and MoneyFrame_Update then MoneyFrame_Update(f.money:GetName(), GetMoney()) end

    self:ApplySearch(f)
end

function MySack:UpdateContents(f)
    if not f or not f:IsShown() then return end

    local isBankFrame = (f == NS.bank)
    local offlineBank = isBankFrame and not NS.bankOpen
    local myKey = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    local viewingAlt = f.viewingAltKey and (f.viewingAltKey ~= myKey)
    f.isCachedView = (viewingAlt or offlineBank) and true or false

    if f.buttons then
        for _, btn in ipairs(f.buttons) do
            if btn:IsShown() and btn.mysackBag and btn.mysackSlot then
                local data = GetSlotDataForFrame(f, btn.mysackBag, btn.mysackSlot)
                UpdateButton(f, btn, btn.mysackBag, btn.mysackSlot, data)
            end
        end
    end

    local total, freeTotal = 0, 0
    if offlineBank then
        local DB = _G.MySackDB
        local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
        local snap = (DB and DB.itemData and DB.itemData[key] and DB.itemData[key].bankSnapshot) or {}
        local numSnap = (DB and DB.itemData and DB.itemData[key] and DB.itemData[key].bankNumSlots) or {}
        for _, bag in ipairs(f.bagList) do
            if not isSpecialtyBag(bag) then
                local n = numSnap[bag] or C.NumSlots(bag) or 0
                total = total + n
                local occ = 0
                if snap[bag] then for _ in pairs(snap[bag]) do occ = occ + 1 end end
                freeTotal = freeTotal + (n - occ)
            end
        end
        f.freeText:SetText(string.format("|cffffd100%d|r free / %d slots (cached)", freeTotal, total))
    else
        for _, bag in ipairs(f.bagList) do
            if not isSpecialtyBag(bag) then
                local n = C.NumSlots(bag) or 0
                total = total + n
                for slot = 1, n do
                    if not C.ItemInfo(bag, slot) then freeTotal = freeTotal + 1 end
                end
            end
        end
        f.freeText:SetText(string.format("|cffffd100%d|r free / %d slots", freeTotal, total))
    end
    UpdateBagBar(f)

    if f.money and MoneyFrame_Update then MoneyFrame_Update(f.money:GetName(), GetMoney()) end
    self:ApplySearch(f)
end

local scanTooltip
local function GetItemTooltipText(link, bag, slot)
    if _G.C_TooltipInfo then
        local data
        if bag and slot then
            data = _G.C_TooltipInfo.GetBagItem(bag, slot)
        elseif link then
            data = _G.C_TooltipInfo.GetHyperlink(link)
        end
        if data and data.lines then
            local text = ""
            for _, line in ipairs(data.lines) do
                if line.leftText then
                    text = text .. " " .. line.leftText
                end
            end
            return text:lower()
        end
    end

    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "MySackScanTooltip", nil, "GameTooltipTemplate")
        scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    scanTooltip:ClearLines()
    if bag and slot then
        if bag == -1 then
            local ok = pcall(scanTooltip.SetBagItem, scanTooltip, bag, slot)
            if not ok then
                local slotID = _G.BankButtonIDToInvSlotID and _G.BankButtonIDToInvSlotID(slot, 1) or (39 + slot)
                scanTooltip:SetInventoryItem("player", slotID)
            end
        else
            scanTooltip:SetBagItem(bag, slot)
        end
    elseif link then
        scanTooltip:SetHyperlink(link)
    else
        return ""
    end
    local text = ""
    for i = 1, scanTooltip:NumLines() do
        local left = _G["MySackScanTooltipTextLeft" .. i]
        if left then
            local t = left:GetText()
            if t then
                text = text .. " " .. t
            end
        end
    end
    return text:lower()
end

-- Search: fade buttons whose item name/type doesn't match.
local QUALITY_WORDS = { poor=0, junk=0, common=1, uncommon=2, rare=3, epic=4, legendary=5, artifact=6 }

local function MatchSingleSearch(q, data)
    if not data or not data.link then return false end
    q = q:gsub("^%s+",""):gsub("%s+$",""):lower()
    if q == "" then return true end
    local link = data.link
    local name, _, quality, iLevel, _, _, _, _, equipSlot, _, _, classID = GetItemInfo(link)
    name = (name or link):lower()

    local op, num = q:match("^([<>=])%s*(%d+)$")
    if op then
        local lvl = iLevel or 0
        if op == ">" then return lvl > tonumber(num) end
        if op == "<" then return lvl < tonumber(num) end
        return lvl == tonumber(num)
    end
    local lo, hi = q:match("^(%d+)%-(%d+)$")
    if lo then local lvl = iLevel or 0; return lvl >= tonumber(lo) and lvl <= tonumber(hi) end

    if QUALITY_WORDS[q] ~= nil then return (quality or 1) == QUALITY_WORDS[q] end

    local IC = Enum and Enum.ItemClass or {}
    local KW = {
        armor = IC.Armor or 4, weapon = IC.Weapon or 2, consumable = IC.Consumable or 0,
        potion = IC.Consumable or 0, food = IC.Consumable or 0, trade = IC.Tradegoods or 7,
        reagent = IC.Reagent or 5, recipe = IC.Recipe or 9, gem = IC.Gem or 3,
        quest = IC.Questitem or 12, bag = IC.Container or 1, container = IC.Container or 1,
    }
    if KW[q] ~= nil and classID ~= nil and classID == KW[q] then return true end
    if q == "equip" or q == "gear" then return equipSlot ~= nil and equipSlot ~= "" end

    if name:find(q, 1, true) ~= nil then return true end

    -- Fall back to checking the tooltip text (using specific bag/slot if available)
    local tooltipText = GetItemTooltipText(link, data.bag, data.slot)
    return tooltipText:find(q, 1, true) ~= nil
end

function NS.MatchSearch(q, data)
    if not q or q == "" then return true end
    if not data or not data.link then return false end
    if q:find(",") then
        for part in q:gmatch("[^,]+") do
            part = part:gsub("^%s+",""):gsub("%s+$","")
            if part ~= "" and MatchSingleSearch(part, data) then
                return true
            end
        end
        return false
    else
        return MatchSingleSearch(q, data)
    end
end

function MySack:ApplyVisualFilters(f)
    if not f or not f.buttons then return end
    local q = f.searchText
    local hasQuery = q and q ~= ""
    local hlBag = f.highlightedBag

    for _, btn in ipairs(f.buttons) do
        if btn:IsShown() then
            local matchesBag = (hlBag == nil) or (btn.mysackBag == hlBag)
            local matchesSearch = true
            if hasQuery then
                matchesSearch = btn.hasItem and NS.MatchSearch(q, btn.mysackData)
            end

            if matchesBag and matchesSearch then
                btn:SetAlpha(1)
                if hlBag ~= nil and btn.hasItem and btn.msBagHighlight then
                    btn.msBagHighlight:Show()
                elseif btn.msBagHighlight then
                    btn.msBagHighlight:Hide()
                end
            else
                btn:SetAlpha(0.2)
                if btn.msBagHighlight then
                    btn.msBagHighlight:Hide()
                end
            end
        end
    end

    if f.bagBar then
        for bagID, b in pairs(f.bagBar) do
            if b.selectedGlow then
                if hlBag == bagID then
                    b.selectedGlow:Show()
                else
                    b.selectedGlow:Hide()
                end
            end
        end
    end
end

function MySack:ApplySearch(f)
    self:ApplyVisualFilters(f)
end

function MySack:ToggleBagHighlight(f, bagID)
    if not f then return end
    if f.highlightedBag == bagID then
        f.highlightedBag = nil
    else
        f.highlightedBag = bagID
    end
    self:ApplyVisualFilters(f)
    if GameTooltip:GetOwner() and f.bagBar and f.bagBar[bagID] and GameTooltip:GetOwner() == f.bagBar[bagID] then
        f.bagBar[bagID]:GetScript("OnEnter")(f.bagBar[bagID])
    end
end

-- Assign the item currently on the cursor to a category (used by category
-- header drop targets). Dropping on "Free Space" clears any assignment.
function MySack:AssignCursorToCategory(catKey)
    if not catKey then return end
    local infoType, itemID = GetCursorInfo()
    if infoType ~= "item" or not itemID then return end
    itemID = tonumber(itemID) or itemID
    if catKey == "EMPTY" or catKey == "JUNK" then
        S().overrides[itemID] = nil
    else
        S().overrides[itemID] = catKey
    end
    ClearCursor()
    if NS.main then self:Render(NS.main) end
    if NS.bank and NS.bank:IsShown() then self:Render(NS.bank) end
end

-- ===========================================================================
-- Show / hide / toggle
-- ===========================================================================
local function ApplyPoint(f, pt)
    if not f or not pt then return end
    f:ClearAllPoints()
    f:SetPoint(pt[1], pt[2] or UIParent, pt[3], pt[4], pt[5])
end

function MySack:Open()
    if not NS.main then return end
    NS.main:Show()
    if NS.main.needsResort ~= false or not NS.main.isRendered then
        self:Render(NS.main)
        NS.main.needsResort = false
        NS.main.isRendered = true
    else
        self:UpdateContents(NS.main)
    end
end

function MySack:Close()
    if NS.main then
        NS.main:Hide()
        NS.main.needsResort = true
    end
    if NS.ClearNew then NS.ClearNew() end
end

function MySack:Toggle()
    if NS.main and NS.main:IsShown() then self:Close() else self:Open() end
end

function MySack:IsOpen()
    return NS.main and NS.main:IsShown()
end

-- ===========================================================================
-- Events
-- ===========================================================================
local dirty = false
MySack:RegisterEvent("PLAYER_LOGIN")
MySack:RegisterEvent("BAG_UPDATE")
MySack:RegisterEvent("BAG_UPDATE_COOLDOWN")
MySack:RegisterEvent("ITEM_LOCK_CHANGED")
MySack:RegisterEvent("PLAYER_MONEY")
MySack:RegisterEvent("BAG_UPDATE_DELAYED")
MySack:RegisterEvent("PLAYER_REGEN_ENABLED")
MySack:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
MySack:RegisterEvent("PLAYER_REGEN_DISABLED")

MySack:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if C.RefreshBags then C.RefreshBags() end
        if NS.InitSettings then NS.InitSettings() end
        NS.main = CreateContainer("MySackFrame", C.BACKPACK_BAGS, "MySack")
        NS.main.needsResort = true
        NS.main:HookScript("OnHide", function()
            NS.main.needsResort = true
            if NS.main.highlightedBag ~= nil then
                NS.main.highlightedBag = nil
                MySack:ApplyVisualFilters(NS.main)
            end
            if NS.bank and NS.bank:IsShown() then
                NS.bank:Hide()
            end
            if NS.AutoFillQuiver then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.1, function() pcall(NS.AutoFillQuiver) end)
                else
                    pcall(NS.AutoFillQuiver)
                end
            end
        end)
        if NS.BuildBank then NS.BuildBank() end
        if NS.bank then
            NS.bank.needsResort = true
            NS.bank:HookScript("OnHide", function()
                NS.bank.needsResort = true
                if NS.bank.highlightedBag ~= nil then
                    NS.bank.highlightedBag = nil
                    MySack:ApplyVisualFilters(NS.bank)
                end
            end)
        end
        if NS.InitHooks then NS.InitHooks() end
        if NS.InitOptions then NS.InitOptions() end
        ApplyPoint(NS.main, S().point)
        if NS.bank then
            ApplyPoint(NS.bank, S().bankPoint)
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then
        if self:IsOpen() then self:UpdateContents(NS.main) end
        if NS.bank and NS.bank:IsShown() then self:UpdateContents(NS.bank) end
    elseif event == "PLAYER_MONEY" then
        if NS.main and NS.main.money and self:IsOpen() then MoneyFrame_Update(NS.main.money:GetName(), GetMoney()) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self:IsOpen() then self:UpdateContents(NS.main) end
        if NS.bank and NS.bank:IsShown() then self:UpdateContents(NS.bank) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        sorting = false
        sortingBank = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        if NS.bank and NS.bank:IsShown() then self:UpdateContents(NS.bank) end
    else
        -- BAG_UPDATE / ITEM_LOCK_CHANGED / delayed -> update visible button contents in-place
        -- (Layout re-sorting into categories only happens AFTER the bag is closed and reopened)
        if self:IsOpen() then
            self:UpdateContents(NS.main)
            NS.main.needsResort = true
        end
        if NS.bank and NS.bank:IsShown() then
            self:UpdateContents(NS.bank)
            NS.bank.needsResort = true
        end

        if sorting then
            runSortSequence(false)
        elseif sortingBank then
            runSortSequence(true)
        end
    end
end)

-- Expose the container factory so Bank.lua can build a matching window.
NS.CreateContainerPublic = CreateContainer

