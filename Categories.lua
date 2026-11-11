-- Categories.lua -- classifies items into display categories.
-- Uses item classID/subclassID (locale-independent) plus quality, never text matching.
local ADDON, NS = ...
local C = NS.C
local Cat = {}
NS.Cat = Cat

local GetItemInfo = function(...)
    if C and C.GetItemInfo then return C.GetItemInfo(...) end
    if _G.C_Item and _G.C_Item.GetItemInfo then return _G.C_Item.GetItemInfo(...) end
    if _G.GetItemInfo then return _G.GetItemInfo(...) end
    return nil
end

    -- Stable category keys. Order here is the default top-to-bottom display order.
-- Customs and user reordering are handled dynamically via settings.
Cat.ORDER = {
    "FAVORITE",       -- user-pinned items (handled via overrides)
    "NEW",            -- recently acquired (optional, off by default)
    "EQUIPMENT",      -- armor + weapons
    "SOULBOUND_GEAR", -- soulbound equipment (armor + weapons)
    "PROFESSION",     -- profession tools, rods, fishing poles
    "CONSUMABLE",     -- food, potions, elixirs, scrolls
    "TRADE",          -- trade goods / crafting mats
    "GEM",            -- gems
    "GLYPH",          -- glyphs (Wrath+)
    "RECIPE",         -- recipes / patterns
    "QUEST",          -- quest items
    "REAGENT",        -- class reagents / ammo / projectiles / quivers
    "QUIVER",         -- Specialty bags contents / empty slots
    "CONTAINER",      -- bags
    "MISC",           -- everything else
    "JUNK",           -- poor quality (grey)
    "EMPTY",          -- free slots
}

Cat.NAMES = {
    FAVORITE       = "Favorites",
    NEW            = "New",
    SOULBOUND_GEAR = "Soulbound Gear",
    EQUIPMENT      = "Equipment",
    PROFESSION = "Professions",
    CONSUMABLE = "Consumables",
    TRADE      = "Trade Goods",
    GEM        = "Gems",
    GLYPH      = "Glyphs",
    RECIPE     = "Recipes",
    QUEST      = "Quest",
    REAGENT    = "Reagents",
    QUIVER     = "Quiver / Specialty Bags",
    CONTAINER  = "Bags",
    MISC       = "Miscellaneous",
    JUNK       = "Junk",
    EMPTY      = "Free Space",
}

-- Returns merged names (built-in + custom from settings)
function Cat.GetAllNames(settings)
    local n = {}
    for k, v in pairs(Cat.NAMES) do n[k] = v end
    if settings and settings.customCategories then
        for k, def in pairs(settings.customCategories) do
            if def and def.name then n[k] = def.name end
        end
    end
    return n
end

function Cat.GetName(key, settings)
    local names = Cat.GetAllNames(settings)
    return names[key] or key
end

-- Enum.ItemClass values are stable across clients. Fall back to integers in case
-- the Enum table is unavailable on very old builds.
local IC = _G.Enum and _G.Enum.ItemClass or {}
local CLASS = {
    Consumable      = IC.Consumable      or 0,
    Container       = IC.Container       or 1,
    Weapon          = IC.Weapon          or 2,
    Gem             = IC.Gem             or 3,
    Armor           = IC.Armor           or 4,
    Reagent         = IC.Reagent         or 5,
    Projectile      = IC.Projectile      or 6,
    Tradegoods      = IC.Tradegoods      or 7,
    ItemEnhancement = IC.ItemEnhancement or 8,
    Recipe          = IC.Recipe          or 9,
    Quiver          = IC.Quiver          or 11,
    Questitem       = IC.Questitem       or 12,
    Key             = IC.Key             or 13,
    Miscellaneous   = IC.Miscellaneous   or 15,
    Glyph           = IC.Glyph           or 16,
}

-- Profession tools, enchanting rods and fishing poles. Item IDs are stable
-- across all game versions; the subclass rule below is the locale-independent
-- backstop (weapon subclass 14 = Miscellaneous tools, 20 = Fishing Poles).
Cat.PROFESSION_TOOLS = {
    [2901]=true,  -- Mining Pick
    [5956]=true,  -- Blacksmith Hammer
    [6219]=true,  -- Arclight Spanner
    [10498]=true, -- Gyromatic Micro-Adjustor
    [40772]=true, -- Gnomish Army Knife
    [7005]=true,  -- Skinning Knife
    [6256]=true,[6365]=true,[6366]=true,[6367]=true,[19022]=true,[19970]=true,[25978]=true,[30662]=true, -- fishing poles
    [6217]=true,[6218]=true,[6338]=true,[6339]=true,[11128]=true,[11130]=true,[11144]=true,              -- rods
    [22461]=true,[22462]=true,[22463]=true,                                                              -- TBC rods
}

function Cat.IsProfessionTool(itemID, classID, subclassID, subType)
    if itemID and Cat.PROFESSION_TOOLS[itemID] then return true end
    local IC = _G.Enum and _G.Enum.ItemClass or {}
    if classID == (IC.Weapon or 2) then
        -- Numeric subclass: 14 = Miscellaneous (tools), 20 = Fishing Poles.
        if subclassID == 14 or subclassID == 20 then return true end
        -- Locale text fallback (covers clients whose subclass id differs).
        if subType then
            local s = subType:lower()
            if s == "miscellaneous" or s:find("fishing") then return true end
        end
    end
    return false
end

-- Map an item classID to a default category key.
local CLASS_TO_CAT = {
    [CLASS.Armor]       = "EQUIPMENT",
    [CLASS.Weapon]      = "EQUIPMENT",
    [CLASS.Consumable]  = "CONSUMABLE",
    [CLASS.Tradegoods]  = "TRADE",
    [CLASS.ItemEnhancement] = "TRADE",
    [CLASS.Gem]         = "GEM",
    [CLASS.Glyph]       = "GLYPH",
    [CLASS.Recipe]      = "RECIPE",
    [CLASS.Questitem]   = "QUEST",
    [CLASS.Reagent]     = "REAGENT",
    [CLASS.Projectile]  = "REAGENT",
    [CLASS.Quiver]      = "REAGENT",
    [CLASS.Container]   = "CONTAINER",
    [CLASS.Key]         = "MISC",
    [CLASS.Miscellaneous] = "MISC",
}

-- Returns the category key for an item.
--   data:      normalized container info table (may be nil for empty slot)
--   overrides: table keyed by itemID -> category key (user assignments)
function Cat.Classify(data, overrides, settings)
    if not data or (not data.itemID and not data.link and not data.icon) then
        return "EMPTY"
    end

    -- 1. User override always wins.
    if overrides and data.itemID and overrides[data.itemID] then
        return overrides[data.itemID]
    end

    -- 2. Check recently acquired (within 2 minutes).
    local hidden = (settings and settings.hiddenCategories) or {}
    if not hidden["NEW"] and data.itemID and NS.IsNewItem and NS.IsNewItem(data.itemID) then
        return "NEW"
    end

    -- 3. Evaluate custom category rules.
    if settings and settings.customCategories and NS.MatchSearch then
        local order = settings.categoryOrder or {}
        for _, key in ipairs(order) do
            local def = settings.customCategories[key]
            if def and def.rule and def.rule ~= "" then
                if NS.MatchSearch(def.rule, data) then
                    return key
                end
            end
        end
    end

    -- Special items
    if data.itemID == 6948 then return "MISC" end -- Hearthstone

    local link = data.link
    local itemType, subType, equipSlot, classID, subclassID

    -- Query GetItemInfo by link or itemID
    if link then
        local _, _, _, _, _, iType, sType, _, eqLoc, _, _, cID, scID = GetItemInfo(link)
        itemType, subType, equipSlot, classID, subclassID = iType, sType, eqLoc, cID, scID
    end
    if (not classID or not itemType or not equipSlot) and data.itemID then
        local _, _, _, _, _, iType, sType, _, eqLoc, _, _, cID, scID = GetItemInfo(data.itemID)
        itemType = itemType or iType
        subType = subType or sType
        equipSlot = equipSlot or eqLoc
        classID = classID or cID
        subclassID = subclassID or scID
    end

    -- Instant info fallback if GetItemInfo was not yet cached
    if (not classID or not itemType or not equipSlot) and data.itemID and _G.C_Item and _G.C_Item.GetItemInfoInstant then
        local ok, _, iType, iSubType, iEqLoc, _, iCID, iSCID = pcall(_G.C_Item.GetItemInfoInstant, link or data.itemID)
        if ok then
            itemType = itemType or iType
            subType = subType or iSubType
            equipSlot = equipSlot or iEqLoc
            classID = classID or iCID
            subclassID = subclassID or iSCID
        end
    end

    -- Profession tools / rods / fishing poles get their own category.
    if Cat.IsProfessionTool(data.itemID, classID, subclassID, subType) then
        return "PROFESSION"
    end

    -- Junk: poor quality goes to its own bucket regardless of class.
    if data.quality == 0 then return "JUNK" end

    -- Equipment: strictly wearable armor, weapons, and accessories with a valid equip slot
    local isArmorOrWeapon = (classID == 4 or classID == 2 or itemType == "Armor" or itemType == "Weapon")
    local hasEquipSlot = (equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_NON_EQUIP" and equipSlot ~= "INVTYPE_BAG" and equipSlot ~= "INVTYPE_QUIVER")
    local isGear = isArmorOrWeapon and hasEquipSlot

    if isGear then
        local isBound = data.isBound
        if isBound == nil and data.bag and data.slot and _G.C_Item and _G.C_Item.IsBound and _G.ItemLocation then
            local ok, loc = pcall(_G.ItemLocation.CreateFromBagAndSlot, _G.ItemLocation, data.bag, data.slot)
            if ok and loc and loc:IsValid() then
                local ok2, b = pcall(_G.C_Item.IsBound, loc)
                if ok2 then isBound = b end
            end
        end
        if isBound == nil and NS.GetItemTooltipText then
            local tt = NS.GetItemTooltipText(link or data.itemID, data.bag, data.slot)
            if tt and tt ~= "" then
                local boundWord = (_G.ITEM_SOULBOUND and _G.ITEM_SOULBOUND:lower()) or "soulbound"
                isBound = tt:find(boundWord, 1, true) ~= nil or tt:find("soulbound", 1, true) ~= nil
            end
        end
        if isBound then
            if hidden["SOULBOUND_GEAR"] then
                return "EQUIPMENT"
            end
            return "SOULBOUND_GEAR"
        end
        return "EQUIPMENT"
    end

    -- Category mapping by numeric classID or localized itemType
    if classID == 0 or itemType == "Consumable" then return "CONSUMABLE" end
    if classID == 7 or classID == 8 or itemType == "Trade Goods" or itemType == "Item Enhancement" then return "TRADE" end
    if classID == 3 or itemType == "Gem" then return "GEM" end
    if classID == 9 or itemType == "Recipe" then return "RECIPE" end
    if classID == 12 or itemType == "Quest" then return "QUEST" end
    if classID == 5 or classID == 6 or classID == 11 or itemType == "Reagent" or itemType == "Projectile" or itemType == "Quiver" then return "REAGENT" end
    if classID == 1 or itemType == "Container" then return "CONTAINER" end
    if classID == 16 or itemType == "Glyph" then return "GLYPH" end
    if classID == 13 or itemType == "Key" then return "MISC" end
    if classID == 15 or itemType == "Miscellaneous" then return "MISC" end
    -- Class-based fallback table
    if classID and CLASS_TO_CAT[classID] then
        local cat = CLASS_TO_CAT[classID]
        if cat == "EQUIPMENT" and not hasEquipSlot then
            return "MISC"
        end
        return cat
    end

    return "MISC"
end

-- Ordered, de-duplicated category list honouring user order + customs + hidden.
-- Pass full settings table (NS.db) or nil for defaults.
function Cat.BuildOrder(settings)
    local seen, out = {}, {}
    local userOrder = settings and settings.categoryOrder
    local hidden = (settings and settings.hiddenCategories) or {}
    local customs = (settings and settings.customCategories) or {}
    local names = Cat.GetAllNames(settings)

    if userOrder then
        for _, key in ipairs(userOrder) do
            if key ~= "EMPTY" and not hidden[key] and not seen[key] and names[key] then
                seen[key] = true
                out[#out + 1] = key
            end
        end
    end
    for _, key in ipairs(Cat.ORDER) do
        if key ~= "EMPTY" and not hidden[key] and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    -- append any stray custom categories
    for key in pairs(customs) do
        if key ~= "EMPTY" and not hidden[key] and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    -- EMPTY is ALWAYS the final category!
    if not hidden["EMPTY"] then
        out[#out + 1] = "EMPTY"
    end
    return out
end

-- Return list of keys that are safe to assign items to (exclude special buckets)
function Cat.GetAssignableCategories(settings)
    local order = Cat.BuildOrder(settings)
    local res = {}
    local skip = { EMPTY = true, NEW = true }
    for _, key in ipairs(order) do
        if not skip[key] then table.insert(res, key) end
    end
    return res
end

return Cat
