-- Features.lua -- merchant tools (sell junk / repair), new-item tracking,
-- and an "owned count" line in item tooltips. All guarded so a failure here
-- can never break the core bag window.
local ADDON, NS = ...
local C = NS.C

local GetItemInfo = function(...)
    if C and C.GetItemInfo then return C.GetItemInfo(...) end
    if _G.C_Item and _G.C_Item.GetItemInfo then return _G.C_Item.GetItemInfo(...) end
    if _G.GetItemInfo then return _G.GetItemInfo(...) end
    return nil
end
local GetItemFamily = function(...)
    if C and C.GetItemFamily then return C.GetItemFamily(...) end
    if _G.C_Item and _G.C_Item.GetItemFamily then return _G.C_Item.GetItemFamily(...) end
    if _G.GetItemFamily then return _G.GetItemFamily(...) end
    return 0
end

-- ===========================================================================
-- New-item tracking. We snapshot item counts; when an itemID's count rises we
-- flag it as "new" until the bag window is closed.
-- ===========================================================================
NS.newItemTimestamps = {}
local counts = {}
local loginTime = nil
local primed = false
local ticker = nil

local function checkNewItemsExpiration()
    if not NS.newItemTimestamps then return end
    local anyExpired = false
    local now = GetTime()
    for id, t in pairs(NS.newItemTimestamps) do
        if now - t >= 120 then
            NS.newItemTimestamps[id] = nil
            anyExpired = true
        end
    end
    if anyExpired then
        if NS.main and NS.main:IsShown() and NS.MySack and NS.MySack.UpdateContents then
            NS.main.needsResort = true
            NS.MySack:UpdateContents(NS.main)
        end
        if NS.bank and NS.bank:IsShown() and NS.MySack and NS.MySack.UpdateContents then
            NS.bank.needsResort = true
            NS.MySack:UpdateContents(NS.bank)
        end
    end
    local count = 0
    for _ in pairs(NS.newItemTimestamps) do count = count + 1 end
    if count == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function startExpirationTicker()
    if not ticker and C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(2, checkNewItemsExpiration)
    end
end

local function snapshot()
    local cur = {}
    local bags = (C and C.BACKPACK_BAGS) or { 0, 1, 2, 3, 4 }
    for _, bag in ipairs(bags) do
        local n = C.NumSlots(bag) or 0
        for slot = 1, n do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID then
                cur[info.itemID] = (cur[info.itemID] or 0) + (info.count or 1)
            end
        end
    end
    return cur
end

function NS.ScanNew()
    local cur = snapshot()
    local now = GetTime()
    local inGrace = (not loginTime) or (now - loginTime < 6.0)

    if primed and not inGrace and next(counts) then
        local added = false
        for id, qty in pairs(cur) do
            if qty > (counts[id] or 0) then
                NS.newItemTimestamps[id] = now
                added = true
            end
        end
        if added then
            startExpirationTicker()
        end
    end

    counts = cur
    if not inGrace and next(cur) then
        primed = true
    end

    if _G.MySackCharDB then
        _G.MySackCharDB.bagCounts = counts
    end
end

function NS.IsNewItem(itemID)
    if not itemID or not NS.newItemTimestamps then return false end
    local t = NS.newItemTimestamps[itemID]
    if t and (GetTime() - t < 120) then
        return true
    else
        if t then NS.newItemTimestamps[itemID] = nil end
        return false
    end
end

function NS.ClearNew()
    -- Do not clear timestamps on close; let items run their full 2-minute duration.
end

-- ===========================================================================
-- Merchant tools
-- ===========================================================================
-- True if an item must never be sold. Profession-tool detection is shared with
-- the "Professions" category (NS.Cat.IsProfessionTool) so the two never drift.
-- Recipes/formulas are always excluded from auto-sell.
local function isProtected(itemID, classID, subclassID, subType, name)
    if itemID and NS.db.userProtect and NS.db.userProtect[itemID] then return true end
    if name then
        local lowerName = name:lower()
        if lowerName:find("lockbox") or 
           lowerName:find("junkbox") or 
           (lowerName:find("locked") and (lowerName:find("chest") or lowerName:find("box") or lowerName:find("safe"))) then
            return true
        end
    end
    local IC = Enum and Enum.ItemClass or {}
    if classID == (IC.Recipe or 9) then return true end  -- never auto-sell formulas or recipes
    if not NS.db.protectTools then return false end
    return NS.Cat.IsProfessionTool(itemID, classID, subclassID, subType)
end

local function typeAllowed(classID)
    local IC = Enum and Enum.ItemClass or {}
    if classID == (IC.Armor or 4) or classID == (IC.Weapon or 2) then
        return NS.db.sellEquipment
    elseif classID == (IC.Consumable or 0) then
        return NS.db.sellConsumables
    elseif classID == (IC.Tradegoods or 7) or classID == (IC.ItemEnhancement or 8) then
        return NS.db.sellTradeGoods
    else
        return NS.db.sellOther
    end
end

local function sellJunk()
    local total, count = 0, 0
    local maxQ = (NS.db and NS.db.autoSellQuality) or 0
    local maxIlvl = (NS.db and NS.db.autoSellMaxIlvl) or 0
    for _, bag in ipairs(C.BACKPACK_BAGS) do
        local n = C.NumSlots(bag)
        for slot = 1, n do
            local info = C.ItemInfo(bag, slot)
            local q = info and info.quality or nil
            if info and q and q <= maxQ and not info.noValue and info.link then
                local name, _, _, iLevel, _, _, subType, _, _, _, sellPrice, classID, subclassID = GetItemInfo(info.link)
                local ilvlOK = (maxIlvl == 0) or (not iLevel) or (iLevel <= maxIlvl)
                if sellPrice and sellPrice > 0 and ilvlOK and typeAllowed(classID)
                   and not isProtected(info.itemID, classID, subclassID, subType, name) then
                    total = total + sellPrice * (info.count or 1)
                    count = count + 1
                    C.UseItem(bag, slot)
                end
            end
        end
    end
    if total > 0 then
        print("|cff66ccffMySack|r sold "..count.." item(s) for "..GetCoinTextureString(total))
    else
        print("|cff66ccffMySack|r nothing matched the sell filter.")
    end
    return total
end
NS.SellJunk = sellJunk

local function repairAll()
    if not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost = GetRepairAllCost and GetRepairAllCost() or 0
    if cost <= 0 then return end
    local useGuild = NS.db.useGuildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
    RepairAllItems(useGuild and true or false)
    print("|cff66ccffMySack|r repaired for "..GetCoinTextureString(cost)..(useGuild and " (guild funds)" or ""))
end
NS.RepairAll = repairAll

-- Merchant buttons attached to the bag window (shown only at a vendor).
local function ensureMerchantButtons()
    local f = NS.main
    if not f or f.msSellBtn then return end

    local rep = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rep:SetSize(62, 20); rep:SetText("Repair")
    rep:SetPoint("BOTTOMRIGHT", -14, 35)
    rep:SetScript("OnClick", repairAll)
    rep:Hide()
    f.msRepairBtn = rep

    local sell = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sell:SetSize(72, 20); sell:SetText("Sell Junk")
    sell:SetPoint("RIGHT", rep, "LEFT", -4, 0)
    sell:SetScript("OnClick", sellJunk)
    sell:Hide()
    f.msSellBtn = sell
end

local function showMerchantButtons(show)
    local f = NS.main
    if not f then return end
    ensureMerchantButtons()
    local canRepair = show and CanMerchantRepair and CanMerchantRepair()
    if f.msSellBtn then
        f.msSellBtn:ClearAllPoints()
        if canRepair then
            f.msSellBtn:SetPoint("RIGHT", f.msRepairBtn, "LEFT", -4, 0)
        else
            f.msSellBtn:SetPoint("BOTTOMRIGHT", -14, 35)
        end
        f.msSellBtn:SetShown(show)
    end
    if f.msRepairBtn then
        f.msRepairBtn:SetShown(canRepair)
    end
end

-- ===========================================================================
-- Auto-drop: when bags are completely full, destroy the single lowest-value
-- grey (and optionally white) item to free one slot. Heavily guarded.
-- ===========================================================================
local function bagsFree()
    local free = 0
    for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
        local n = C.NumSlots(bag)
        for slot = 1, n do
            if not C.ItemInfo(bag, slot) then free = free + 1 end
        end
    end
    return free
end

-- Find the single lowest-value grey/white item eligible to be destroyed.
local function findDropCandidate()
    local maxQ = NS.db.autoDropWhite and 1 or 0
    local cap = NS.db.autoDropMaxValue or 0
    local QUEST = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
    local best
    for _, bag in ipairs(C.BACKPACK_BAGS) do
        local n = C.NumSlots(bag)
        for slot = 1, n do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID and info.quality and info.quality <= maxQ and not info.locked then
                local name, _, _, _, _, _, subType, _, _, _, sellPrice, classID, subclassID = GetItemInfo(info.link)
                if not name then
                    -- Item data not cached yet; request it and skip so we never
                    -- mis-judge its vendor value as zero this pass.
                    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(info.itemID) end
                else
                    local isQuest = C.ItemQuestInfo(bag, slot)
                    local protected = isProtected(info.itemID, classID, subclassID, subType)
                    -- Only items that actually have a vendor sell value are eligible.
                    if not isQuest and classID ~= QUEST and not protected and sellPrice and sellPrice > 0 then
                        local count = info.count or 1
                        local total = sellPrice * count
                        -- Rank by per-item vendor price (lowest first); the cap still
                        -- guards against destroying a whole stack worth a lot.
                        if cap == 0 or total <= cap then
                            if not best or sellPrice < best.unit
                               or (sellPrice == best.unit and total < best.total) then
                                best = { bag = bag, slot = slot, unit = sellPrice, total = total, link = info.link }
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

-- DeleteCursorItem is a protected function and can only run from a hardware
-- event, so the actual destruction happens when the player clicks Destroy.
StaticPopupDialogs["MYSACK_AUTODROP"] = {
    text = "MySack: your bags are full.\n\nDestroy %s to free a slot?",
    button1 = "Destroy",
    button2 = CANCEL,
    OnAccept = function()
        local best = findDropCandidate()
        if best then
            C.PickupItem(best.bag, best.slot)
            if _G.DeleteCursorItem then DeleteCursorItem() end
            print("|cffff3030MySack auto-drop:|r destroyed "..(best.link or "an item")..".")
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

local function autoDropIfFull()
    if not NS.db.autoDrop then return end
    if bagsFree() > 0 then return end
    if StaticPopup_Visible and StaticPopup_Visible("MYSACK_AUTODROP") then return end
    local best = findDropCandidate()
    if best then StaticPopup_Show("MYSACK_AUTODROP", best.link) end
end
NS.AutoDropIfFull = autoDropIfFull

-- ===========================================================================
-- Cross-character item tracking (bags + bank) like TBag.
-- Data lives in MySackDB.itemData[charKey] = {
--   bags = {[itemID]=count}, bank = {[itemID]=count},
--   bankSnapshot = {[bagID]={[slot]={icon,count,quality,link,itemID,...}}},
--   bankNumSlots = {[bagID]=n},
--   updated = time
-- }
-- ===========================================================================
local function snapshotBank()
    if not NS.bankOpen then return end  -- do not clear persisted snapshot when away from bank
    local DB = _G.MySackDB
    if not DB then return end
    DB.itemData = DB.itemData or {}
    local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    DB.itemData[key] = DB.itemData[key] or { bags = {}, bank = {}, bankSnapshot = {}, bankNumSlots = {} }
    local data = DB.itemData[key]

    data.bank = {}
    data.bankSnapshot = {}
    data.bankNumSlots = {}
    data.bankNumSlotsPurchased = (C.GetNumBankSlots and C.GetNumBankSlots()) or (GetNumBankSlots and GetNumBankSlots()) or 0

    for _, bag in ipairs(C.BANK_BAGS or {}) do
        local n = C.NumSlots(bag) or 0
        data.bankNumSlots[bag] = n
        data.bankSnapshot[bag] = {}
        for slot = 1, n do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID then
                data.bankSnapshot[bag][slot] = {
                    icon = info.icon,
                    count = info.count,
                    quality = info.quality,
                    link = info.link,
                    itemID = info.itemID,
                    locked = info.locked,
                }
                data.bank[info.itemID] = (data.bank[info.itemID] or 0) + (info.count or 1)
            end
        end
    end
    data.updated = time()
end
NS.SnapshotBank = snapshotBank

local function updateItemCounts()
    local DB = _G.MySackDB
    if not DB then return end
    DB.itemData = DB.itemData or {}
    if DB.itemData[nil] then DB.itemData[nil] = nil end
    local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    DB.itemData[key] = DB.itemData[key] or { bags = {}, bank = {}, bankSnapshot = {}, bankNumSlots = {} }
    local data = DB.itemData[key]
    data.money = GetMoney()

    -- scan current bags (0-4) for counts and per-slot snapshot
    data.bags = {}
    data.bagsSnapshot = {}
    data.bagsNumSlots = {}
    for _, bag in ipairs(C.BACKPACK_BAGS) do
        local n = C.NumSlots(bag) or 0
        data.bagsNumSlots[bag] = n
        data.bagsSnapshot[bag] = {}
        for slot = 1, n do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID then
                data.bagsSnapshot[bag][slot] = {
                    icon = info.icon,
                    count = info.count,
                    quality = info.quality,
                    link = info.link,
                    itemID = info.itemID,
                }
                data.bags[info.itemID] = (data.bags[info.itemID] or 0) + (info.count or 1)
            end
        end
    end

    -- full bank snapshot (counts + per-slot data) only while at bank
    if NS.bankOpen then
        snapshotBank()
    end
    -- previous bank snapshot/counts are retained for offline/cached view
end
NS.UpdateItemCounts = updateItemCounts

function NS.GetBagSnapshotItem(charKey, bag, slot)
    local DB = _G.MySackDB
    if not DB or not DB.itemData then return nil end
    local c = DB.itemData[charKey]
    if not c or not c.bagsSnapshot then return nil end
    local b = c.bagsSnapshot[bag]
    return b and b[slot] or nil
end

function NS.GetBankSnapshotItem(bag, slot)
    local DB = _G.MySackDB
    if not DB or not DB.itemData then return nil end
    local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    local c = DB.itemData[key]
    if not c or not c.bankSnapshot then return nil end
    local b = c.bankSnapshot[bag]
    return b and b[slot] or nil
end

local function scanMailbox()
    local DB = _G.MySackDB
    if not DB then return end
    DB.itemData = DB.itemData or {}
    local key = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    DB.itemData[key] = DB.itemData[key] or { bags = {}, bank = {}, bankSnapshot = {}, bankNumSlots = {} }
    local data = DB.itemData[key]

    data.mail = {}

    local numItems = GetInboxNumItems() or 0
    for i = 1, numItems do
        for attachIndex = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local name, itemID, texture, count = GetInboxItem(i, attachIndex)
            if itemID and count and count > 0 then
                data.mail[itemID] = (data.mail[itemID] or 0) + count
            end
        end
    end
end

local function getOwnedCounts(itemID)
    local DB = _G.MySackDB
    if not DB or not DB.itemData then return 0, 0, 0, {} end

    local curBags, curBank, curMail = 0, 0, 0
    local myKey = NS.GetCharKey and NS.GetCharKey() or (UnitName("player") or "Unknown")
    local alts = {}  -- key -> total count on that alt (bags + bank + mail)

    for key, cdata in pairs(DB.itemData) do
        local b = (cdata.bags and cdata.bags[itemID]) or 0
        local k = (cdata.bank and cdata.bank[itemID]) or 0
        local m = (cdata.mail and cdata.mail[itemID]) or 0
        local tot = b + k + m
        if key == myKey then
            curBags = curBags + b
            curBank = curBank + k
            curMail = curMail + m
        elseif tot > 0 then
            alts[key] = tot
        end
    end
    return curBags, curBank, curMail, alts
end

-- ===========================================================================
-- Tooltip: show how many of an item you hold (bags + bank, this char + per-alt).
-- ===========================================================================
local function countInBags(itemID)  -- keep for backward compat (bags only, current char)
    local total = 0
    for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
        local n = C.NumSlots(bag)
        for slot = 1, n do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID == itemID then total = total + (info.count or 1) end
        end
    end
    return total
end

local function addOwnedTooltipLines(self, itemID)
    if not itemID then return end
    local bags, bank, mail, alts = getOwnedCounts(itemID)
    local other = 0
    for _, c in pairs(alts) do other = other + c end
    local total = bags + bank + mail + other
    if total > 0 then
        self:AddLine(string.format("|cff66ccffMySack: %d total|r", total))
        if bags + bank + mail > 0 then
            local details = {}
            if bags > 0 then table.insert(details, string.format("%d in bags", bags)) end
            if bank > 0 then table.insert(details, string.format("%d in bank", bank)) end
            if mail > 0 then table.insert(details, string.format("%d in mail", mail)) end
            local detailStr = table.concat(details, ", ")
            local name = UnitName("player")
            self:AddDoubleLine(string.format("  |cfffd9b1a%s|r", name), string.format("|cffffffff%d|r  (|cffaaaaaa%s|r)", bags + bank + mail, detailStr))
        end

        local altKeys = {}
        for k in pairs(alts) do table.insert(altKeys, k) end
        table.sort(altKeys)

        for _, key in ipairs(altKeys) do
            local cnt = alts[key]
            local shortName = key:match("^[^ -]+") or key
            local altRealm = key:match(" - (.+)$")
            local curRealm = GetRealmName()
            if altRealm and altRealm ~= curRealm then
                shortName = shortName .. " (" .. altRealm .. ")"
            end
            self:AddDoubleLine(string.format("  |cff44aaff%s|r", shortName), string.format("|cffffffff%d|r", cnt))
        end
        self:Show()
    end
end

local function hookTooltip()
    local function handleTooltipLegacy(self)
        local _, link = self.GetItem and self:GetItem()
        if not link then return end
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then addOwnedTooltipLines(self, itemID) end
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            local itemID = data and data.id
            if not itemID and tooltip and tooltip.GetItem then
                local _, link = tooltip:GetItem()
                itemID = link and tonumber(link:match("item:(%d+)"))
            end
            if itemID then
                addOwnedTooltipLines(tooltip, itemID)
            end
        end)
    else
        if GameTooltip and GameTooltip.HookScript then
            pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", handleTooltipLegacy)
        end
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", handleTooltipLegacy)
        end
    end
end

-- ===========================================================================
-- Auto-open clams (with security error suppression)
-- ===========================================================================
local CLAM_IDS = {
    [4655] = true,   -- Small Barnacled Clam
    [5523] = true,   -- Thick-shelled Clam
    [7973] = true,   -- Big-mouth Clam
    [15846] = true,  -- Soft-shelled Clam
    [24476] = true,  -- Jagged Clam
    [35586] = true,  -- Giant Clam
    [167873] = true, -- Sanak Clam
    [169701] = true, -- Tenebrous Clam
    [184654] = true, -- Silvergill Clam
}

local lastClamOpenTime = 0
local function autoOpenClams()
    if not NS.db or not NS.db.autoOpenClams then return end
    if InCombatLockdown() then return end

    local now = GetTime()
    if now - lastClamOpenTime < 1.2 then return end

    -- Check if we have at least 1 free slot
    local freeSlots = 0
    for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
        local n = C.NumSlots(bag)
        for slot = 1, n do
            if not C.ItemInfo(bag, slot) then
                freeSlots = freeSlots + 1
            end
        end
    end
    if freeSlots < 1 then return end

    for _, bag in ipairs({ 0, 1, 2, 3, 4 }) do
        local n = C.NumSlots(bag)
        for slot = 1, n do
            local info = C.ItemInfo(bag, slot)
            if info and info.itemID and not info.locked then
                local isClam = CLAM_IDS[info.itemID]
                if not isClam and info.link then
                    local name, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(info.link)
                    if name and classID ~= 0 and classID ~= 9 then
                        local lowerName = name:lower()
                        if lowerName:find("clam") and not (lowerName:find("meat") or lowerName:find("chowder") or lowerName:find("soup") or lowerName:find("recipe") or lowerName:find("surprise")) then
                            isClam = true
                        end
                    end
                end

                if isClam then
                    lastClamOpenTime = now
                    
                    -- Temporarily override error handler to suppress protected function LUA errors
                    local originalHandler = geterrorhandler()
                    seterrorhandler(function(msg)
                        -- Silently swallow the secure execution exception
                    end)
                    
                    pcall(C.UseItem, bag, slot)
                    
                    -- Restore original error handler
                    seterrorhandler(originalHandler)
                    return
                end
            end
        end
    end
end

local function autoFillQuiver()
    if InCombatLockdown() then return end
    if CursorHasItem() then return end
    if NS.db and NS.db.autoFillQuiver == false then return end

    -- Do not move arrows while bags are open so player can freely move arrows out of quiver
    if NS.main and NS.main:IsShown() then return end
    if _G.ContainerFrame1 and _G.ContainerFrame1:IsShown() then return end

    -- Also do not move arrows if bank, merchant, trade, or mail is open
    if NS.bankOpen or (_G.BankFrame and _G.BankFrame:IsShown()) then return end
    if _G.MerchantFrame and _G.MerchantFrame:IsShown() then return end
    if _G.TradeFrame and _G.TradeFrame:IsShown() then return end
    if _G.MailFrame and _G.MailFrame:IsShown() then return end

    -- 1. Find all equipped quivers/ammo pouches
    local quivers = {}
    for _, bag in ipairs({ 1, 2, 3, 4 }) do
        if C.isSpecialtyBag(bag) then
            local slot = C.bagInvSlot(bag)
            local link = slot and GetInventoryItemLink("player", slot)
            local family = link and (C.GetItemFamily and C.GetItemFamily(link) or (GetItemFamily and GetItemFamily(link)))
            if family and family > 0 then
                table.insert(quivers, { bag = bag, family = family })
            end
        end
    end

    if #quivers == 0 then return end

    -- 2. Find empty slots in these quivers
    local emptyQuiverSlots = {}
    for _, q in ipairs(quivers) do
        local n = C.NumSlots(q.bag)
        for slot = 1, n do
            if not C.ItemInfo(q.bag, slot) then
                table.insert(emptyQuiverSlots, { bag = q.bag, slot = slot, family = q.family })
            end
        end
    end

    if #emptyQuiverSlots == 0 then return end

    local band = bit and bit.band or function(a, b) return a == b end

    -- 3. Find matching ammo in general bags
    for _, bag in ipairs(C.BACKPACK_BAGS) do
        if not C.isSpecialtyBag(bag) then
            local n = C.NumSlots(bag)
            for slot = 1, n do
                local info = C.ItemInfo(bag, slot)
                if info and info.itemID and info.link and not info.locked then
                    local family = (C.GetItemFamily and C.GetItemFamily(info.link)) or (GetItemFamily and GetItemFamily(info.link)) or 0
                    if family > 0 then
                        -- Check if this ammo family matches any of our empty quiver slots
                        for _, eq in ipairs(emptyQuiverSlots) do
                            if band(family, eq.family) > 0 then
                                C.PickupItem(bag, slot)
                                if CursorHasItem() then
                                    C.PickupItem(eq.bag, eq.slot)
                                    ClearCursor()
                                    return -- Move one stack at a time
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
NS.AutoFillQuiver = autoFillQuiver

local depositingReagents = false

local function depositNextReagent()
    if not NS.bankOpen or InCombatLockdown() or CursorHasItem() then
        depositingReagents = false
        return false
    end
    local REAGENT_CLASS_IDS = {
        [7] = true,  -- Trade Goods
        [5] = true,  -- Reagents
        [3] = true,  -- Gems
        [9] = true,  -- Recipes / Plans
    }

    local targetBag, targetSlot
    for _, b in ipairs(C.BANK_BAGS or {}) do
        local n = C.NumSlots(b) or 0
        for s = 1, n do
            if not C.ItemInfo(b, s) then
                targetBag, targetSlot = b, s
                break
            end
        end
        if targetBag then break end
    end

    if not targetBag then
        depositingReagents = false
        return false
    end

    for _, bag in ipairs(C.BACKPACK_BAGS) do
        if not C.isSpecialtyBag(bag) then
            local n = C.NumSlots(bag) or 0
            for slot = 1, n do
                local info = C.ItemInfo(bag, slot)
                if info and info.itemID and info.link and not info.locked then
                    local _, _, _, _, _, _, _, _, _, _, _, classID = GetItemInfo(info.link)
                    if classID and REAGENT_CLASS_IDS[classID] then
                        C.PickupItem(bag, slot)
                        if CursorHasItem() then
                            C.PickupItem(targetBag, targetSlot)
                            ClearCursor()
                            return true
                        end
                    end
                end
            end
        end
    end

    depositingReagents = false
    return false
end

local function depositReagentsToBank()
    if not NS.bankOpen or InCombatLockdown() or CursorHasItem() then return end
    depositingReagents = true
    depositNextReagent()
end
NS.DepositReagentsToBank = depositReagentsToBank

-- ===========================================================================
-- Backpack Button Free Slot Tracker
-- Ensures MainMenuBarBackpackButton always displays total free bag slots
-- (excluding specialty bags like quivers/ammo pouches) rather than ammo counts.
-- ===========================================================================
local function GetBackpackCountFontString()
    local btn = _G.MainMenuBarBackpackButton
    if not btn then return nil end
    local fs = _G.MainMenuBarBackpackButtonCount or btn.Count or btn.count
    if not fs and btn.CreateFontString then
        fs = btn:CreateFontString(btn:GetName() and (btn:GetName().."Count"), "OVERLAY", "NumberFontNormal")
        fs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
        btn.Count = fs
    end
    return fs
end

local function GetMainBackpackFreeSlots()
    local freeTotal = 0
    local bags = (C and C.BACKPACK_BAGS) or { 0, 1, 2, 3, 4 }
    for _, bag in ipairs(bags) do
        if not (C.isSpecialtyBag and C.isSpecialtyBag(bag)) then
            local freeSlots, bagFamily = C.NumFreeSlots(bag)
            if freeSlots and (not bagFamily or bagFamily == 0) then
                freeTotal = freeTotal + freeSlots
            else
                local n = C.NumSlots(bag) or 0
                for slot = 1, n do
                    if not C.ItemInfo(bag, slot) then
                        freeTotal = freeTotal + 1
                    end
                end
            end
        end
    end
    return freeTotal
end

local inBackpackUpdate = false

local function UpdateBackpackButtonFreeSlots()
    if inBackpackUpdate then return end
    inBackpackUpdate = true

    local btn = _G.MainMenuBarBackpackButton
    local countFS = GetBackpackCountFontString()

    if btn and countFS then
        if NS.db and NS.db.showFreeSlotsOnBackpack == false then
            inBackpackUpdate = false
            return
        end

        local freeTotal = GetMainBackpackFreeSlots()
        local desired = tostring(freeTotal)
        if freeTotal == 0 then
            desired = (RED_FONT_COLOR_CODE or "|cffff2020") .. "0" .. (FONT_COLOR_CODE_CLOSE or "|r")
        end

        countFS:SetText(desired)
        countFS:Show()
        btn.freeSlots = freeTotal
        if btn.SetCountShown then
            pcall(btn.SetCountShown, btn, true)
        end
    end

    inBackpackUpdate = false
end
NS.UpdateBackpackButtonFreeSlots = UpdateBackpackButtonFreeSlots

local backpackHooked = false
local function InitBackpackSlotTracking()
    local btn = _G.MainMenuBarBackpackButton
    local countFS = GetBackpackCountFontString()
    if not countFS and not btn then return end

    if not backpackHooked then
        backpackHooked = true

        if countFS and countFS.SetText then
            hooksecurefunc(countFS, "SetText", function(self, text)
                if inBackpackUpdate then return end
                if NS.db and NS.db.showFreeSlotsOnBackpack == false then return end

                local freeTotal = GetMainBackpackFreeSlots()
                local desired = tostring(freeTotal)
                if freeTotal == 0 then
                    desired = (RED_FONT_COLOR_CODE or "|cffff2020") .. "0" .. (FONT_COLOR_CODE_CLOSE or "|r")
                end

                if text ~= desired then
                    inBackpackUpdate = true
                    self:SetText(desired)
                    self:Show()
                    inBackpackUpdate = false
                end
            end)
        end

        if countFS and countFS.Hide then
            hooksecurefunc(countFS, "Hide", function(self)
                if inBackpackUpdate then return end
                if NS.db and NS.db.showFreeSlotsOnBackpack == false then return end

                inBackpackUpdate = true
                self:Show()
                inBackpackUpdate = false
            end)
        end

        if _G.MainMenuBarBackpackButton_UpdateFreeSlots then
            hooksecurefunc("MainMenuBarBackpackButton_UpdateFreeSlots", UpdateBackpackButtonFreeSlots)
        end
        if _G.MainMenuBarBackpackButton_Update then
            hooksecurefunc("MainMenuBarBackpackButton_Update", UpdateBackpackButtonFreeSlots)
        end

        if btn then
            if btn.UpdateFreeSlots then
                hooksecurefunc(btn, "UpdateFreeSlots", UpdateBackpackButtonFreeSlots)
            end
            if btn.Update then
                hooksecurefunc(btn, "Update", UpdateBackpackButtonFreeSlots)
            end
            if btn.SetItemButtonCount then
                hooksecurefunc(btn, "SetItemButtonCount", function(self)
                    UpdateBackpackButtonFreeSlots()
                end)
            end
            if btn.SetCountShown then
                hooksecurefunc(btn, "SetCountShown", function(self, shown)
                    if not shown and (not NS.db or NS.db.showFreeSlotsOnBackpack ~= false) then
                        UpdateBackpackButtonFreeSlots()
                    end
                end)
            end
        end

        if _G.SetItemButtonCount then
            hooksecurefunc("SetItemButtonCount", function(button, count)
                if button == _G.MainMenuBarBackpackButton then
                    UpdateBackpackButtonFreeSlots()
                end
            end)
        end
    end

    UpdateBackpackButtonFreeSlots()
end

-- ===========================================================================
-- Events
-- ===========================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("BAG_CONTAINER_UPDATE")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("CVAR_UPDATE")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:RegisterEvent("MAIL_SHOW")
f:RegisterEvent("MAIL_INBOX_UPDATE")
f:RegisterEvent("PLAYER_MONEY")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        loginTime = GetTime()
        if _G.MySackCharDB and _G.MySackCharDB.bagCounts then
            for id, qty in pairs(_G.MySackCharDB.bagCounts) do
                counts[id] = qty
            end
        end
        if SetCVar then pcall(SetCVar, "displayFreeBagSlots", "1") end
        pcall(NS.ScanNew)
        pcall(hookTooltip)
        pcall(updateItemCounts)
        pcall(InitBackpackSlotTracking)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, UpdateBackpackButtonFreeSlots)
            C_Timer.After(0.5, UpdateBackpackButtonFreeSlots)
            C_Timer.After(1.5, UpdateBackpackButtonFreeSlots)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        pcall(InitBackpackSlotTracking)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.2, UpdateBackpackButtonFreeSlots)
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_MONEY" then
        pcall(NS.ScanNew)
        pcall(autoDropIfFull)
        pcall(updateItemCounts)
        pcall(autoOpenClams)
        pcall(UpdateBackpackButtonFreeSlots)
        if event == "BAG_UPDATE_DELAYED" then
            if depositingReagents then
                pcall(depositNextReagent)
            else
                pcall(autoFillQuiver)
            end
        end
    elseif event == "BAG_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_CONTAINER_UPDATE" then
        pcall(UpdateBackpackButtonFreeSlots)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        if arg1 == "player" then
            pcall(UpdateBackpackButtonFreeSlots)
        end
    elseif event == "CVAR_UPDATE" then
        if arg1 == "displayFreeBagSlots" then
            pcall(UpdateBackpackButtonFreeSlots)
        end
    elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
        pcall(updateItemCounts)
    elseif event == "BANKFRAME_CLOSED" then
        depositingReagents = false
        pcall(updateItemCounts)
        -- best-effort final snapshot using whatever is readable at close time
        pcall(snapshotBank)
        -- also fire an update so cached view (if shown) updates title/free
        if NS.bank and NS.bank:IsShown() and NS.MySack and NS.MySack.UpdateContents then
            NS.bank.needsResort = true
            pcall(NS.MySack.UpdateContents, NS.MySack, NS.bank)
        end
    elseif event == "MERCHANT_SHOW" then
        if NS.db and NS.db.autoSellJunk then pcall(sellJunk) end
        if NS.db and NS.db.autoRepair then pcall(repairAll) end
        showMerchantButtons(true)
    elseif event == "MERCHANT_CLOSED" then
        showMerchantButtons(false)
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        pcall(scanMailbox)
    end
end)
