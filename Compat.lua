-- Compat.lua -- API compatibility layer so MySack runs on Classic Era, TBC, Wrath, and Modern (Midnight / Retail) clients.
local ADDON, NS = ...
local C = {}
NS.C = C

-- ---------------------------------------------------------------------------
-- Item API: Modern clients (Patch 11.0+ / Midnight / WoW Forever) moved global
-- GetItem* functions to C_Item.* namespace. Polyfill globals for compatibility.
-- ---------------------------------------------------------------------------
local CI = _G.C_Item
if CI then
    pcall(function()
        if not _G.GetItemInfo and CI.GetItemInfo then
            _G.GetItemInfo = CI.GetItemInfo
        end
        if not _G.GetItemFamily and CI.GetItemFamily then
            _G.GetItemFamily = CI.GetItemFamily
        end
        if not _G.GetItemIcon and (CI.GetItemIconByID or CI.GetItemIcon) then
            _G.GetItemIcon = CI.GetItemIconByID or CI.GetItemIcon
        end
        if not _G.GetItemCount and CI.GetItemCount then
            _G.GetItemCount = CI.GetItemCount
        end
        if not _G.GetItemQualityColor and CI.GetItemQualityColor then
            _G.GetItemQualityColor = CI.GetItemQualityColor
        end
        if not _G.GetItemInventoryType and CI.GetItemInventoryType then
            _G.GetItemInventoryType = CI.GetItemInventoryType
        end
    end)
end

function C.GetItemFamily(item)
    if not item then return 0 end
    if CI and CI.GetItemFamily then
        local ok, fam = pcall(CI.GetItemFamily, item)
        if ok and fam then return fam end
    end
    if _G.GetItemFamily then
        local ok, fam = pcall(_G.GetItemFamily, item)
        if ok and fam then return fam end
    end
    return 0
end

function C.GetItemInfo(item)
    if not item then return nil end
    if CI and CI.GetItemInfo then
        local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p = pcall(CI.GetItemInfo, item)
        if ok and a ~= nil then return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p end
    end
    if _G.GetItemInfo then
        local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p = pcall(_G.GetItemInfo, item)
        if ok and a ~= nil then return a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p end
    end
    return nil
end

function C.GetItemIcon(item)
    if not item then return nil end
    if CI and CI.GetItemIconByID then
        local ok, icon = pcall(CI.GetItemIconByID, item)
        if ok and icon then return icon end
    end
    if CI and CI.GetItemIcon then
        local ok, icon = pcall(CI.GetItemIcon, item)
        if ok and icon then return icon end
    end
    if _G.GetItemIcon then
        local ok, icon = pcall(_G.GetItemIcon, item)
        if ok and icon then return icon end
    end
    return nil
end

function C.GetItemCount(item)
    if not item then return 0 end
    if CI and CI.GetItemCount then
        local ok, count = pcall(CI.GetItemCount, item)
        if ok and count then return count end
    end
    if _G.GetItemCount then
        local ok, count = pcall(_G.GetItemCount, item)
        if ok and count then return count end
    end
    return 0
end

function C.GetItemQualityColor(quality)
    if not quality then return 1, 1, 1, "ffffffff" end
    if CI and CI.GetItemQualityColor then
        local ok, r, g, b, hex = pcall(CI.GetItemQualityColor, quality)
        if ok and r then return r, g, b, hex end
    end
    if _G.GetItemQualityColor then
        local ok, r, g, b, hex = pcall(_G.GetItemQualityColor, quality)
        if ok and r then return r, g, b, hex end
    end
    return 1, 1, 1, "ffffffff"
end

function C.GetItemInventoryType(item)
    if not item then return nil end
    if CI and CI.GetItemInventoryType then
        local ok, invType = pcall(CI.GetItemInventoryType, item)
        if ok and invType then return invType end
    end
    if _G.GetItemInventoryType then
        local ok, invType = pcall(_G.GetItemInventoryType, item)
        if ok and invType then return invType end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Container API: newer clients expose C_Container.*; older expose globals.
-- ---------------------------------------------------------------------------
local CC = _G.C_Container

function C.NumSlots(bag)
    if CC and CC.GetContainerNumSlots then return CC.GetContainerNumSlots(bag) or 0 end
    if _G.GetContainerNumSlots then return _G.GetContainerNumSlots(bag) or 0 end
    return 0
end

function C.NumFreeSlots(bag)
    if CC and CC.GetContainerNumFreeSlots then
        local free, fam = CC.GetContainerNumFreeSlots(bag)
        return free or 0, fam or 0
    end
    if _G.GetContainerNumFreeSlots then
        local free, fam = _G.GetContainerNumFreeSlots(bag)
        return free or 0, fam or 0
    end
    local total = C.NumSlots(bag) or 0
    local free = 0
    for s = 1, total do
        if not C.ItemInfo(bag, s) then free = free + 1 end
    end
    return free, 0
end

-- Returns a normalized table or nil for an empty slot:
--   { icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID }
function C.ItemInfo(bag, slot)
    if CC and CC.GetContainerItemInfo then
        local t = CC.GetContainerItemInfo(bag, slot)
        if not t then return nil end
        t.icon     = t.iconFileID
        t.count    = t.stackCount
        t.locked   = t.isLocked
        t.readable = t.isReadable
        t.lootable = t.hasLoot
        t.link     = t.hyperlink
        t.filtered = t.isFiltered
        t.noValue  = t.hasNoValue
        t.bag      = bag
        t.slot     = slot
        return t
    end
    if _G.GetContainerItemInfo then
        local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = _G.GetContainerItemInfo(bag, slot)
        if not icon and not itemID then return nil end
        return {
            icon = icon, count = count, locked = locked, quality = quality,
            readable = readable, lootable = lootable, link = link,
            filtered = filtered, noValue = noValue, itemID = itemID,
            bag = bag, slot = slot,
        }
    end
    return nil
end

function C.ItemLink(bag, slot)
    if CC and CC.GetContainerItemLink then return CC.GetContainerItemLink(bag, slot) end
    if _G.GetContainerItemLink then return _G.GetContainerItemLink(bag, slot) end
    return nil
end

function C.ItemCooldown(bag, slot)
    if CC and CC.GetContainerItemCooldown then return CC.GetContainerItemCooldown(bag, slot) end
    if _G.GetContainerItemCooldown then return _G.GetContainerItemCooldown(bag, slot) end
    return 0, 0, 0
end

function C.ItemQuestInfo(bag, slot)
    if CC and CC.GetContainerItemQuestInfo then
        local t = CC.GetContainerItemQuestInfo(bag, slot)
        if type(t) == "table" then return t.isQuestItem, t.questID, t.isActive end
        return t
    end
    if _G.GetContainerItemQuestInfo then return _G.GetContainerItemQuestInfo(bag, slot) end
    return nil
end

function C.TargetItem(bag, slot)
    if CC and CC.TargetContainerItem then return CC.TargetContainerItem(bag, slot) end
    if _G.TargetContainerItem then return _G.TargetContainerItem(bag, slot) end
    return C.PickupItem(bag, slot)
end

function C.PickupItem(bag, slot)
    if CC and CC.PickupContainerItem then return CC.PickupContainerItem(bag, slot) end
    if _G.PickupContainerItem then return _G.PickupContainerItem(bag, slot) end
end

function C.UseItem(bag, slot)
    if InCombatLockdown() then return false end
    local originalHandler = geterrorhandler()
    seterrorhandler(function() end)
    local ok, res
    if CC and CC.UseContainerItem then
        ok, res = pcall(CC.UseContainerItem, bag, slot)
    elseif _G.UseContainerItem then
        ok, res = pcall(_G.UseContainerItem, bag, slot)
    end
    seterrorhandler(originalHandler)
    return ok and res or nil
end

function C.ContainerToInvSlot(bag)
    if CC and CC.ContainerIDToInventoryID then return CC.ContainerIDToInventoryID(bag) end
    if _G.ContainerIDToInventoryID then return _G.ContainerIDToInventoryID(bag) end
    return nil
end

function C.SortBags()
    if CC and CC.SortBags then return CC.SortBags() end
    if _G.SortBags then return _G.SortBags() end
end

function C.SortBankBags()
    if CC and CC.SortBankBags then return CC.SortBankBags() end
    if _G.SortBankBags then return _G.SortBankBags() end
end

-- Quality border colouring helper (the global signature varies across clients).
function C.SetButtonQuality(button, quality, link)
    if _G.SetItemButtonQuality then
        _G.SetItemButtonQuality(button, quality, link)
        return
    end
    local border = button.IconBorder
    if not border then return end
    if quality and quality > 1 and _G.BAG_ITEM_QUALITY_COLORS and _G.BAG_ITEM_QUALITY_COLORS[quality] then
        local c = _G.BAG_ITEM_QUALITY_COLORS[quality]
        border:SetVertexColor(c.r, c.g, c.b)
        border:Show()
    else
        border:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Bag id sets:
-- Classic / TBC: backpack 0, bags 1-4, keyring -2; bank -1 + 5-11.
-- Modern (DF / TWW / Midnight): backpack 0, bags 1-4, reagent bag 5; bank -1 + 6-12.
-- ---------------------------------------------------------------------------
function C.IsReagentBag(bagID)
    if not bagID then return false end
    if _G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.ReagentBag then
        return bagID == _G.Enum.BagIndex.ReagentBag
    end
    if _G.REAGENTBAG_CONTAINER then
        return bagID == _G.REAGENTBAG_CONTAINER
    end
    if _G.CharacterReagentBag0Slot and bagID == 5 then
        return true
    end
    return false
end

function C.RefreshBags()
    local reagentBagID = (_G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.ReagentBag)
        or _G.REAGENTBAG_CONTAINER
        or (_G.CharacterReagentBag0Slot and 5)

    if reagentBagID then
        C.BACKPACK_BAGS = { 0, 1, 2, 3, 4, reagentBagID }
        local bankBags = { (_G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.Bank) or -1 }
        for i = 1, 7 do
            local key = "BankBag_" .. i
            if _G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex[key] then
                table.insert(bankBags, _G.Enum.BagIndex[key])
            else
                table.insert(bankBags, 5 + i)
            end
        end
        C.BANK_BAGS = bankBags
    else
        C.BACKPACK_BAGS = { 0, 1, 2, 3, 4 }
        C.BANK_BAGS     = { -1, 5, 6, 7, 8, 9, 10, 11 }
    end
end
C.RefreshBags()

C.KEYRING        = -2
C.BANK_CONTAINER = -1

-- True when the keyring exists on this client.
function C.HasKeyring()
    if _G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.Keyring then
        return true
    end
    if _G.GetKeyRingSize ~= nil or _G.HasKey ~= nil or _G.ToggleKeyRing ~= nil then
        return true
    end
    if _G.KEYRING_CONTAINER and _G.KEYRING_CONTAINER ~= -1 and _G.KEYRING_CONTAINER ~= C.BANK_CONTAINER then
        return true
    end
    return false
end

function C.bagInvSlot(bagID)
    if not bagID or bagID == 0 or bagID == -1 or bagID == -2 or (C.KEYRING and bagID == C.KEYRING) then return nil end
    local s = C.ContainerToInvSlot(bagID)
    if s then return s end

    local function safeSlotInfo(n)
        local ok, id = pcall(GetInventorySlotInfo, n)
        return ok and id or nil
    end

    if C.IsReagentBag and C.IsReagentBag(bagID) then
        if _G.CharacterReagentBag0Slot and _G.CharacterReagentBag0Slot.GetID then
            local ok, id = pcall(_G.CharacterReagentBag0Slot.GetID, _G.CharacterReagentBag0Slot)
            if ok and id then return id end
        end
        local id = safeSlotInfo("ReagentBag0Slot")
        if id then return id end
        return nil
    end

    local minBankBag = 5
    if _G.Enum and _G.Enum.BagIndex and _G.Enum.BagIndex.ReagentBag then
        minBankBag = 6
    elseif _G.CharacterReagentBag0Slot or _G.REAGENTBAG_CONTAINER then
        minBankBag = 6
    end

    if bagID >= 1 and bagID <= 4 then
        local id = safeSlotInfo("Bag" .. (bagID - 1) .. "Slot")
        if id then return id end
        return 30 + bagID
    elseif bagID >= minBankBag and bagID <= (minBankBag + 6) then
        local bankSlotIndex = bagID - (minBankBag - 1)
        if _G.BankButtonIDToInvSlotID then
            local ok, id = pcall(_G.BankButtonIDToInvSlotID, bankSlotIndex, 1)
            if ok and id then return id end
        end
        local id = safeSlotInfo("BankBagSlot" .. bankSlotIndex) or safeSlotInfo("Bag" .. (bagID - 1) .. "Slot")
        if id then return id end
        return 63 + bagID
    end
    return nil
end

function C.isSpecialtyBag(bagID)
    if not bagID or bagID == 0 or bagID == -1 or bagID == -2 or (C.KEYRING and bagID == C.KEYRING) then return false end
    -- The modern reagent bag holds trade reagents but is not a classic quiver/specialty container
    if C.IsReagentBag and C.IsReagentBag(bagID) then
        return false
    end
    local _, fam = C.NumFreeSlots(bagID)
    if fam and fam > 0 then return true end
    local slot = C.bagInvSlot(bagID)
    if not slot then return false end
    local link = GetInventoryItemLink("player", slot)
    if not link then return false end
    local family = C.GetItemFamily(link) or 0
    return family > 0
end

-- ---------------------------------------------------------------------------
-- Bank Slot Purchasing & Slot Cost Compatibility Layer
-- ---------------------------------------------------------------------------
function C.GetBankSlotCost()
    if _G.GetBankSlotCost then
        local ok, cost = pcall(_G.GetBankSlotCost)
        if ok and cost then return cost end
    end
    if _G.C_Bank then
        if _G.C_Bank.GetBankSlotCost then
            local ok, cost = pcall(_G.C_Bank.GetBankSlotCost)
            if ok and cost then return cost end
        end
        if _G.C_Bank.GetNextBankSlotCost then
            local ok, cost = pcall(_G.C_Bank.GetNextBankSlotCost)
            if ok and cost then return cost end
        end
        if _G.C_Bank.FetchNextPurchasableBankTabData and _G.Enum and _G.Enum.BankType and _G.Enum.BankType.Character then
            local ok, data = pcall(_G.C_Bank.FetchNextPurchasableBankTabData, _G.Enum.BankType.Character)
            if ok and data and data.tabCost then return data.tabCost end
        end
    end
    if _G.C_Container and _G.C_Container.GetBankSlotCost then
        local ok, cost = pcall(_G.C_Container.GetBankSlotCost)
        if ok and cost then return cost end
    end
    if _G.BankFrame and _G.BankFrame.nextSlotCost then
        return _G.BankFrame.nextSlotCost
    end
    return nil
end

function C.GetNumBankSlots()
    if _G.GetNumBankSlots then
        local ok, num, full = pcall(_G.GetNumBankSlots)
        if ok and num then return num, full end
    end
    if _G.C_Bank then
        if _G.C_Bank.GetNumBankSlots then
            local ok, num, full = pcall(_G.C_Bank.GetNumBankSlots)
            if ok and num then return num, full end
        end
        if _G.C_Bank.GetNumPurchasedBankSlots then
            local ok, num = pcall(_G.C_Bank.GetNumPurchasedBankSlots)
            if ok and num then return num end
        end
        if _G.C_Bank.FetchPurchasedBankTabData and _G.Enum and _G.Enum.BankType and _G.Enum.BankType.Character then
            local ok, tabs = pcall(_G.C_Bank.FetchPurchasedBankTabData, _G.Enum.BankType.Character)
            if ok and type(tabs) == "table" then return #tabs end
        end
    end
    if _G.C_Container and _G.C_Container.GetNumBankSlots then
        local ok, num, full = pcall(_G.C_Container.GetNumBankSlots)
        if ok and num then return num, full end
    end
    return 0, false
end

-- ---------------------------------------------------------------------------
-- Bank Slot Purchasing Compatibility Flag & Safe Polyfill
-- In modern 11.0+ / 12.0 clients, bank slot/tab purchasing is a protected
-- engine action (C_Bank.PurchaseBankTab) that Blizzard requires to be performed
-- directly by the player clicking the default Banker UI (to prevent taint).
-- ---------------------------------------------------------------------------
local origPurchaseSlot = _G.PurchaseSlot
C.hasNativePurchaseSlot = (origPurchaseSlot ~= nil and type(origPurchaseSlot) == "function")

function C.PurchaseBankSlot()
    if C.hasNativePurchaseSlot and origPurchaseSlot and type(origPurchaseSlot) == "function" then
        local ok = pcall(origPurchaseSlot)
        if ok then return true end
    end
    return false
end

-- Polyfill global PurchaseSlot if nil so Blizzard's legacy GameDialogDefs.lua:695
-- never throws an unhandled nil runtime error if invoked.
if not _G.PurchaseSlot then
    _G.PurchaseSlot = function()
        return false
    end
end

local bankEventFrame = CreateFrame("Frame")
bankEventFrame:RegisterEvent("PLAYER_LOGIN")
bankEventFrame:RegisterEvent("ADDON_LOADED")
bankEventFrame:SetScript("OnEvent", function()
    if not _G.PurchaseSlot then
        _G.PurchaseSlot = function()
            return false
        end
    end
end)

return C
