-- Options.lua -- settings init, profiles, slash commands, bag-replacement hooks,
-- right-click category assignment.
local ADDON, NS = ...
local C = NS.C

-- ---------------------------------------------------------------------------
-- Defaults merge helper
-- ---------------------------------------------------------------------------
local function deepDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            deepDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function deepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do t[k] = deepCopy(v) end
    return t
end

local SHARED = "Default"

local function CharKey()
    local realm = GetRealmName() or "Realm"
    return (UnitName("player") or "Unknown") .. " - " .. realm
end
NS.GetCharKey = CharKey

-- ---------------------------------------------------------------------------
-- SavedVariables init (called from PLAYER_LOGIN before frames are built).
--
-- Layout:
--   MySackDB.profiles[<name>] = { ...settings... }   (account-wide store)
--   MySackCharDB.profile      = <name>               (which profile this char uses)
-- Every character defaults to the SHARED ("Default") profile, but can switch to
-- its own named profile for independent settings/position.
-- ---------------------------------------------------------------------------
function NS.InitSettings()
    _G.MySackDB = _G.MySackDB or {}
    _G.MySackCharDB = _G.MySackCharDB or {}
    local DB = _G.MySackDB

    -- Migrate a pre-1.1 flat config (settings stored at the top level) into a
    -- named "Default" profile so existing users keep their setup.
    if DB.columns ~= nil and not DB.profiles then
        local migrated = {}
        for _, k in ipairs({ "columns","iconSize","iconSpacing","scale","replaceBags",
                             "showJunkCoin","point","bankPoint","categoryOrder","overrides" }) do
            migrated[k] = DB[k]
            DB[k] = nil
        end
        DB.profiles = { [SHARED] = migrated }
    end

    DB.profiles = DB.profiles or {}
    DB.profiles[SHARED] = DB.profiles[SHARED] or {}
    deepDefaults(DB.profiles[SHARED], NS.defaults)

    -- Resolve this character's active profile.
    local CDB = _G.MySackCharDB
    local name = CDB.profile or SHARED
    if not DB.profiles[name] then name = SHARED end
    CDB.profile = name

    deepDefaults(DB.profiles[name], NS.defaults)
    NS.db = DB.profiles[name]
    NS.db.overrides = NS.db.overrides or {}
    NS.db.customCategories = NS.db.customCategories or {}
    NS.db.hiddenCategories = NS.db.hiddenCategories or {}
    DB.itemData = DB.itemData or {}  -- cross-character bag+bank counts: [charKey] = {bags={}, bank={}, updated=0}

    -- Purge any conflicting legacy custom soulbound gear category
    if NS.db.customCategories and NS.db.customCategories["CUST_SOULDBOUND_GEAR"] then
        NS.db.customCategories["CUST_SOULDBOUND_GEAR"] = nil
    end

    if not NS.db.categoryOrder or #NS.db.categoryOrder == 0 then
        NS.db.categoryOrder = {}
        for _, k in ipairs(NS.Cat.ORDER) do table.insert(NS.db.categoryOrder, k) end
    else
        for i = #NS.db.categoryOrder, 1, -1 do
            if NS.db.categoryOrder[i] == "CUST_SOULDBOUND_GEAR" then
                table.remove(NS.db.categoryOrder, i)
            end
        end
        local hasSoulbound = false
        for _, k in ipairs(NS.db.categoryOrder) do
            if k == "SOULBOUND_GEAR" then hasSoulbound = true; break end
        end
        if not hasSoulbound then
            local equipIdx = nil
            for i, k in ipairs(NS.db.categoryOrder) do
                if k == "EQUIPMENT" then equipIdx = i; break end
            end
            if equipIdx then
                table.insert(NS.db.categoryOrder, equipIdx, "SOULBOUND_GEAR")
            else
                table.insert(NS.db.categoryOrder, 1, "SOULBOUND_GEAR")
            end
        end
        for i = #NS.db.categoryOrder, 1, -1 do
            if NS.db.categoryOrder[i] == "EMPTY" then
                table.remove(NS.db.categoryOrder, i)
            end
        end
        table.insert(NS.db.categoryOrder, "EMPTY")
    end

    -- Migrate legacy/centered positions to default screen edges (Bank on left, Bags on bottom-right)
    local function isCentered(pt)
        if not pt or not pt[1] then return true end
        if pt[1] == "CENTER" then return true end
        if pt[1] == "LEFT" and pt[4] and pt[4] > 200 and pt[4] < 600 then return true end
        if pt[1] == "RIGHT" and pt[4] and pt[4] < -200 and pt[4] > -600 then return true end
        return false
    end
    if isCentered(NS.db.point) then
        NS.db.point = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -40, 80 }
    end
    if isCentered(NS.db.bankPoint) then
        NS.db.bankPoint = { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
    end

    NS.charDB = CDB
    NS.activeProfile = name
end

-- Switch the current character to a profile, creating it if needed.
--   name: a profile name, or the special tokens "char" / "shared".
--   copyCurrent: when creating, seed it from the current profile's settings.
function NS.SetProfile(name, copyCurrent)
    local DB = _G.MySackDB
    if name == "shared" then name = SHARED end
    if name == "char" then name = CharKey() end
    if not name or name == "" then return false, "no name" end

    if not DB.profiles[name] then
        DB.profiles[name] = copyCurrent and deepCopy(NS.db) or {}
        deepDefaults(DB.profiles[name], NS.defaults)
        DB.profiles[name].overrides = DB.profiles[name].overrides or {}
    end

    _G.MySackCharDB.profile = name
    NS.db = DB.profiles[name]
    NS.activeProfile = name

    -- Re-apply position and redraw.
    local MySack = NS.MySack
    if not InCombatLockdown() then
        if NS.main then
            NS.main:ClearAllPoints()
            local p = NS.db.point
            NS.main:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
            if MySack:IsOpen() then MySack:Render(NS.main) end
        end
        if NS.bank then
            NS.bank:ClearAllPoints()
            local p = NS.db.bankPoint
            NS.bank:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
        end
    end
    if NS.RefreshCategoriesList then NS.RefreshCategoriesList() end
    return true, name
end

local function ListProfiles()
    local DB = _G.MySackDB
    local names = {}
    for k in pairs(DB.profiles) do names[#names+1] = k end
    table.sort(names)
    return names
end

-- Category management (TBag-like: custom buckets + reorder + hide)
function NS.AddCustomCategory(name)
    if not name or name == "" then return nil end
    -- Safe trim (old "name:trim and ..." was invalid Lua syntax and caused the "arguments expected near 'and'" error)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or name
    local key = "CUST_" .. (name or ""):upper():gsub("[^A-Z0-9_]", "")
    if key == "CUST_" then key = "CUST_" .. tostring(GetTime()):gsub("%.", "") end
    NS.db.customCategories = NS.db.customCategories or {}
    if not NS.db.customCategories[key] then
        NS.db.customCategories[key] = { name = name }
    end
    NS.db.categoryOrder = NS.db.categoryOrder or {}
    local found = false
    for _, k in ipairs(NS.db.categoryOrder) do if k == key then found = true break end end
    if not found then table.insert(NS.db.categoryOrder, key) end
    return key
end

function NS.MoveCategory(key, dir)
    local order = NS.db.categoryOrder or {}
    for i, k in ipairs(order) do
        if k == key then
            local ni = i + (dir or 0)
            if ni >= 1 and ni <= #order then
                order[i], order[ni] = order[ni], order[i]
            end
            return true
        end
    end
    return false
end

function NS.ToggleCategoryHidden(key)
    NS.db.hiddenCategories = NS.db.hiddenCategories or {}
    if NS.db.hiddenCategories[key] then
        NS.db.hiddenCategories[key] = nil
    else
        NS.db.hiddenCategories[key] = true
    end
end

function NS.DeleteCustomCategory(key)
    if not key or not NS.db.customCategories or not NS.db.customCategories[key] then return end
    NS.db.customCategories[key] = nil
    if NS.db.hiddenCategories then NS.db.hiddenCategories[key] = nil end
    if NS.db.categoryOrder then
        for i = #NS.db.categoryOrder, 1, -1 do
            if NS.db.categoryOrder[i] == key then table.remove(NS.db.categoryOrder, i) end
        end
    end
    if NS.db.overrides then
        for id, cat in pairs(NS.db.overrides) do
            if cat == key then NS.db.overrides[id] = nil end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Replace the default bags via safe hooksecurefunc (prevents ADDON_ACTION_BLOCKED).
-- ---------------------------------------------------------------------------
function NS.InitHooks()
    local MySack = NS.MySack
    C = C or NS.C
    if not NS.db.replaceBags then return end

    -- Safe Blizzard container hider: parent Blizzard's frames to a hidden container.
    -- Parent to ContainerFrameContainer (native Blizzard container parent) so it stays within the container tree.
    local Parent = _G.ContainerFrameContainer or UIParent
    local hiddenParent = NS.hiddenContainerParent
    if not hiddenParent then
        hiddenParent = CreateFrame("Frame", "MySackHiddenContainer", Parent)
        hiddenParent:SetAllPoints()
        hiddenParent:Hide()
        NS.hiddenContainerParent = hiddenParent
    end

    -- Suppress Blizzard tutorials and disable combined bags CVar so Blizzard's combined bag never interferes
    if C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, "combinedBags", "0")
    end
    if LE_FRAME_TUTORIAL_EQUIP_REAGENT_BAG and C_CVar and C_CVar.SetCVarBitfield then
        pcall(C_CVar.SetCVarBitfield, "closedInfoFrames", LE_FRAME_TUTORIAL_EQUIP_REAGENT_BAG, true)
        pcall(C_CVar.SetCVarBitfield, "closedInfoFrames", LE_FRAME_TUTORIAL_HUD_REVAMP_BAG_CHANGES, true)
        pcall(C_CVar.SetCVarBitfield, "closedInfoFrames", LE_FRAME_TUTORIAL_BAG_SLOTS_AUTHENTICATOR, true)
        pcall(C_CVar.SetCVarBitfield, "closedInfoFrames", LE_FRAME_TUTORIAL_MOUNT_EQUIPMENT_SLOT_FRAME, true)
        pcall(C_CVar.SetCVarBitfield, "closedInfoFrames", LE_FRAME_TUTORIAL_UPGRADEABLE_ITEM_IN_SLOT, true)
    end

    local function tameBlizzFrames()
        if not NS.db or not NS.db.replaceBags then return end
        if InCombatLockdown and InCombatLockdown() then return end
        local maxFrames = _G.NUM_CONTAINER_FRAMES or 13
        for i = 1, maxFrames do
            local cf = _G["ContainerFrame" .. i]
            if cf and cf:GetParent() ~= hiddenParent then
                cf:SetParent(hiddenParent)
            end
        end
        if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags:GetParent() ~= hiddenParent then
            _G.ContainerFrameCombinedBags:SetParent(hiddenParent)
        end
    end

    tameBlizzFrames()

    -- Ensure dynamically created or updated container frames stay tamed
    local maxFrames = _G.NUM_CONTAINER_FRAMES or 13
    for i = 1, maxFrames do
        local cf = _G["ContainerFrame" .. i]
        if cf then
            hooksecurefunc(cf, "SetID", function(frame)
                if NS.db and NS.db.replaceBags and not (InCombatLockdown and InCombatLockdown()) then
                    if frame:GetParent() ~= hiddenParent then
                        frame:SetParent(hiddenParent)
                    end
                end
            end)
        end
    end
    if _G.ContainerFrameCombinedBags then
        hooksecurefunc(_G.ContainerFrameCombinedBags, "Show", function(frame)
            if NS.db and NS.db.replaceBags and not (InCombatLockdown and InCombatLockdown()) then
                if frame:GetParent() ~= hiddenParent then
                    frame:SetParent(hiddenParent)
                end
            end
        end)
    end

    local function openAll()
        if not NS.db or not NS.db.replaceBags then return end
        MySack:Open()
    end

    local function closeAll()
        if not NS.db or not NS.db.replaceBags then return end
        MySack:Close()
    end

    -- Debounced toggle: ensures pressing 'B' toggles MySack instantaneously on the very FIRST
    -- keypress without double-firing if both ToggleBackpack and ToggleAllBags trigger.
    local lastToggleTime = 0
    local function safeToggle()
        if not NS.db or not NS.db.replaceBags then return end
        if debugstack():find("Manager") then return end
        local now = GetTime()
        if (now - lastToggleTime) < 0.05 then return end
        lastToggleTime = now
        MySack:Toggle()
    end

    -- Hook bag toggle APIs securely!
    -- DO NOT hook or overwrite OpenAllBags, OpenBag, etc., as Blizzard's UIParentPanelManager
    -- calls them internally when opening Bank, Mail, and Merchant windows. Hooking them
    -- taints UIParentPanelManager, which taints BankFrame and breaks UseContainerItem().
    -- NPC window auto-open is handled safely via npcWatcher below.
    if hooksecurefunc then
        hooksecurefunc("ToggleAllBags", function()
            safeToggle()
        end)
        hooksecurefunc("ToggleBackpack", function()
            local stack = debugstack()
            if not stack:find("ToggleAllBags") then
                safeToggle()
            end
        end)
        hooksecurefunc("ToggleBag", function(bagID)
            local keyringID = (C and C.KEYRING) or -2
            if bagID == -2 or bagID == keyringID or (_G.KEYRING_CONTAINER and bagID == _G.KEYRING_CONTAINER) then
                return
            end
            local stack = debugstack()
            if not stack:find("ToggleAllBags") and not stack:find("ToggleBackpack") then
                safeToggle()
            end
        end)
    end

    -- Event listener for NPC interactions where bags should automatically open and close
    local npcWatcher = CreateFrame("Frame")
    npcWatcher:RegisterEvent("MERCHANT_SHOW")
    npcWatcher:RegisterEvent("MERCHANT_CLOSED")
    npcWatcher:RegisterEvent("MAIL_SHOW")
    npcWatcher:RegisterEvent("MAIL_CLOSED")
    npcWatcher:RegisterEvent("AUCTION_HOUSE_SHOW")
    npcWatcher:RegisterEvent("AUCTION_HOUSE_CLOSED")
    npcWatcher:RegisterEvent("TRADE_SHOW")
    npcWatcher:RegisterEvent("TRADE_CLOSED")
    npcWatcher:SetScript("OnEvent", function(_, event)
        if not NS.db.replaceBags then return end
        if event == "MERCHANT_SHOW" or event == "MAIL_SHOW" or event == "AUCTION_HOUSE_SHOW" or event == "TRADE_SHOW" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, openAll)
            else
                openAll()
            end
        elseif event == "MERCHANT_CLOSED" or event == "MAIL_CLOSED" or event == "AUCTION_HOUSE_CLOSED" or event == "TRADE_CLOSED" then
            closeAll()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Alt + Right-click an item to assign it to a category.
-- ---------------------------------------------------------------------------
local assignMenu
function NS.MySack:OnItemRightClick(btn)
    if not IsAltKeyDown() then return false end
    local data = btn.mysackData
    if not data or not data.itemID then return false end

    local itemID = data.itemID
    local Cat = NS.Cat

    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(btn, function(owner, root)
            root:CreateTitle("Assign to category")
            local assignable = Cat.GetAssignableCategories(NS.db) or {}
            for _, key in ipairs(assignable) do
                local catName = Cat.GetName(key, NS.db)
                local isChecked = function() return NS.db.overrides[itemID] == key end
                local setSelected = function()
                    NS.db.overrides[itemID] = key
                    NS.MySack:Render(NS.main)
                    if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
                end
                root:CreateRadio(catName, isChecked, setSelected)
            end
            root:CreateDivider()
            root:CreateButton("|cffff5555Clear assignment|r", function()
                NS.db.overrides[itemID] = nil
                NS.MySack:Render(NS.main)
                if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
            end)
        end)
        return true
    end

    if not assignMenu then
        assignMenu = CreateFrame("Frame", "MySackAssignMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(assignMenu, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.isTitle = true; info.notCheckable = true
        info.text = "Assign to category"
        UIDropDownMenu_AddButton(info, level)
        local assignable = Cat.GetAssignableCategories(NS.db) or {}
        for _, key in ipairs(assignable) do
            local i = UIDropDownMenu_CreateInfo()
            i.text = Cat.GetName(key, NS.db)
            i.checked = (NS.db.overrides[itemID] == key)
            i.func = function()
                NS.db.overrides[itemID] = key
                CloseDropDownMenus()
                NS.MySack:Render(NS.main)
                if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
            end
            UIDropDownMenu_AddButton(i, level)
        end
        local clear = UIDropDownMenu_CreateInfo()
        clear.text = "|cffff5555Clear assignment|r"
        clear.notCheckable = true
        clear.func = function()
            NS.db.overrides[itemID] = nil
            CloseDropDownMenus()
            NS.MySack:Render(NS.main)
            if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
        end
        UIDropDownMenu_AddButton(clear, level)
    end, "MENU")
    ToggleDropDownMenu(1, nil, assignMenu, "cursor", 0, 0)
    return true
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local PREFIX = "|cff66ccffMySack|r "

local function handleProfile(arg)
    local sub, rest = arg:match("^(%S*)%s*(.-)$")
    if sub == "" or sub == "list" then
        print(PREFIX.."active profile: |cffffd100"..(NS.activeProfile or "?").."|r")
        print(PREFIX.."profiles: "..table.concat(ListProfiles(), ", "))
        print(PREFIX.."use: /msk profile <name> | char | shared | copy <name> | delete <name>")
    elseif sub == "char" then
        local _, n = NS.SetProfile("char", true)
        print(PREFIX.."this character now uses its own profile: |cffffd100"..n.."|r")
    elseif sub == "shared" then
        NS.SetProfile("shared")
        print(PREFIX.."this character now uses the shared |cffffd100Default|r profile")
    elseif sub == "copy" then
        if rest == "" then print(PREFIX.."usage: /msk profile copy <name>") return end
        local ok, n = NS.SetProfile(rest, true)
        print(PREFIX.."copied current settings into |cffffd100"..n.."|r and switched to it")
    elseif sub == "delete" then
        if rest == "" or rest == "Default" then print(PREFIX.."cannot delete that profile") return end
        if _G.MySackDB.profiles[rest] then
            _G.MySackDB.profiles[rest] = nil
            if NS.activeProfile == rest then NS.SetProfile("shared") end
            print(PREFIX.."deleted profile |cffffd100"..rest.."|r")
        else
            print(PREFIX.."no such profile: "..rest)
        end
    else
        -- switch to (or create) a named profile
        local _, n = NS.SetProfile(sub)
        print(PREFIX.."switched to profile |cffffd100"..n.."|r")
    end
end

function NS.InitOptions()
    SLASH_MYSACK1 = "/mysack"
    SLASH_MYSACK2 = "/msk"
    SlashCmdList["MYSACK"] = function(msg)
        msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local cmd, arg = msg:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()
        local db = NS.db
        if cmd == "" or cmd == "toggle" then
            NS.MySack:Toggle()
        elseif cmd == "config" or cmd == "options" or cmd == "opt" then
            if NS.ToggleConfig then NS.ToggleConfig() end
        elseif cmd == "profile" or cmd == "profiles" then
            handleProfile(arg)
        elseif cmd == "cols" or cmd == "columns" then
            local n = tonumber(arg)
            if n and n >= 4 and n <= 32 then db.columns = n; NS.MySack:Render(NS.main); print(PREFIX.."columns = "..n)
            else print(PREFIX.."usage: /msk cols <4-32>") end
        elseif cmd == "size" then
            local n = tonumber(arg)
            if n and n >= 20 and n <= 64 then db.iconSize = n; NS.MySack:Render(NS.main); print(PREFIX.."icon size = "..n)
            else print(PREFIX.."usage: /msk size <20-64>") end
        elseif cmd == "scale" then
            local n = tonumber(arg)
            if n and n >= 0.5 and n <= 2 then db.scale = n; NS.MySack:Render(NS.main); print(PREFIX.."scale = "..n)
            else print(PREFIX.."usage: /msk scale <0.5-2.0>") end
        elseif cmd == "protect" or cmd == "unprotect" then
            local infoType, itemID, link = GetCursorInfo()
            if infoType == "item" and itemID then
                itemID = tonumber(itemID) or itemID
                NS.db.userProtect = NS.db.userProtect or {}
                if cmd == "protect" then
                    NS.db.userProtect[itemID] = true
                    print(PREFIX..(link or "item").." will never be sold.")
                else
                    NS.db.userProtect[itemID] = nil
                    print(PREFIX..(link or "item").." removed from the protect list.")
                end
                ClearCursor()
                if NS.RefreshProtectList then NS.RefreshProtectList() end
            else
                print(PREFIX.."pick up an item first, then type /msk "..cmd.." (it returns to your bag).")
            end
        elseif cmd == "debug" then
            local CC = _G.C_Container
            print(PREFIX.."ContainerToInvSlot IDs:")
            for i = 1, 4 do
                local s1 = CC and CC.ContainerIDToInventoryID and CC.ContainerIDToInventoryID(i)
                local s2 = _G.ContainerIDToInventoryID and _G.ContainerIDToInventoryID(i)
                local name = "Bag"..(i-1).."Slot"
                local s3 = GetInventorySlotInfo(name)
                print(string.format("  Bag %d: C_Container=%s, Global=%s, SlotInfo(%s)=%s", i, tostring(s1), tostring(s2), name, tostring(s3)))
            end
            print(PREFIX.."Equipped Bag links:")
            for i = 19, 35 do
                local link = GetInventoryItemLink("player", i)
                local tex = GetInventoryItemTexture("player", i)
                print(string.format("  Slot %d: Link=%s, Texture=%s", i, tostring(link or "nil"), tostring(tex or "nil")))
            end
            local btn = _G.MySackClamButton
            if btn then
                print(PREFIX.."MySackClamButton attributes:")
                print(string.format("  Shown: %s, FrameLevel: %d", tostring(btn:IsShown()), btn:GetFrameLevel()))
                print(string.format("  type1: %s, macrotext1: %s", tostring(btn:GetAttribute("type1")), tostring(btn:GetAttribute("macrotext1"))))
                print(string.format("  itemBag: %s, itemSlot: %s", tostring(btn.itemBag or "nil"), tostring(btn.itemSlot or "nil")))
            else
                print(PREFIX.."MySackClamButton is NIL")
            end
        elseif cmd == "sort" then
            if NS.C.SortBags then NS.C.SortBags() end; print(PREFIX.."sorting bags...")
        elseif cmd == "reset" then
            db.point = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -40, 80 }
            db.bankPoint = { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
            if NS.main then
                NS.main:ClearAllPoints()
                local p = db.point
                NS.main:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
            end
            if NS.bank then
                NS.bank:ClearAllPoints()
                local p = db.bankPoint
                NS.bank:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
            end
            NS.MySack:Open()
            print(PREFIX.."position reset to default screen edges (Bank: left, Bags: bottom-right).")
        elseif cmd == "bank" then
            if NS.bank then
                NS.bank:ClearAllPoints()
                local p = NS.db.bankPoint or { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
                NS.bank:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
                NS.bank:Show()
                if NS.MySack.Render then NS.MySack:Render(NS.bank) end
                print(PREFIX.."showing bank view (uses cached data when away from banker)")
            end
        elseif cmd == "help" then
            print(PREFIX.."commands:")
            print("  /msk                toggle the bag window")
            print("  /msk cols <n>       items per row (4-32)")
            print("  /msk size <n>       icon size (20-64)")
            print("  /msk scale <n>      window scale (0.5-2.0)")
            print("  /msk reset          reset window position")
            print("  /msk config         open the settings panel")
            print("  /msk protect        protect the item on your cursor from selling")
            print("  /msk profile        show/list profiles")
            print("  /msk profile char   give this character its own profile")
            print("  /msk profile shared use the shared Default profile")
            print("  /msk profile <name> switch to / create a named profile")
            print("  /msk bank           show bank view (cached when away from banker, like TBag)")
            print("  Drag an item onto a category title to assign its category")
        else
            print(PREFIX.."unknown command. Try /msk help")
        end
    end
end
