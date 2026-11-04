-- Config.lua -- tabbed settings window (gear button / "/msk config").
local ADDON, NS = ...
local C = NS.C

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

local win
local tabs, tabButtons = {}, {}
local checks = {}

-- ---------------------------------------------------------------------------
-- Widget builders (parent-relative)
-- ---------------------------------------------------------------------------
local function makeSlider(parent, key, label, min, max, step, x, y, setter, fmt)
    local s = CreateFrame("Slider", "MySackCfg"..key, parent, "OptionsSliderTemplate")
    s:SetWidth(220); s:SetHeight(16)
    s:SetPoint("TOPLEFT", x, y)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    _G[s:GetName().."Low"]:SetText(tostring(min))
    _G[s:GetName().."High"]:SetText(tostring(max))
    s.titleFS = _G[s:GetName().."Text"]
    s.label, s.fmt = label, fmt
    s:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val/step + 0.5) * step
        val = math.floor(val*100 + 0.5)/100
        setter(val)
        self.titleFS:SetText(self.label..": "..(self.fmt and self.fmt(val) or val))
        if NS.main then NS.MySack:Render(NS.main) end
        if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
    end)
    return s
end

local function makeCheck(parent, key, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", "MySackCfg"..key, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    _G[cb:GetName().."Text"]:SetText(label)
    cb.get, cb.set = get, set
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        if NS.main then NS.MySack:Render(NS.main) end
        if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
    end)
    checks[#checks+1] = cb
    return cb
end

local function header(parent, text, x, y, w)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y); h:SetText(text); h:SetTextColor(1, 0.82, 0)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetPoint("TOPLEFT", x, y - 17); line:SetSize(w or 480, 1)
    return h
end

-- ---------------------------------------------------------------------------
-- Tab framework
-- ---------------------------------------------------------------------------
local function selectTab(i)
    for j, fr in ipairs(tabs) do fr:SetShown(j == i) end
    for j, b in ipairs(tabButtons) do
        if j == i then b:LockHighlight() b:GetFontString():SetTextColor(1, 0.82, 0)
        else b:UnlockHighlight() b:GetFontString():SetTextColor(1, 1, 1) end
    end
end

local function newTab(label, idx, x)
    local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    b:SetSize(96, 22); b:SetPoint("TOPLEFT", x, -52)
    b:SetText(label)
    b:SetScript("OnClick", function() selectTab(idx) end)
    tabButtons[idx] = b
    local fr = CreateFrame("Frame", nil, win)
    fr:SetPoint("TOPLEFT", 20, -92)
    fr:SetPoint("BOTTOMRIGHT", -20, 44)
    fr:Hide()
    tabs[idx] = fr
    return fr
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function build()
    win = CreateFrame("Frame", "MySackConfigWindow", UIParent, "BackdropTemplate")
    win:SetSize(540, 530)
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetToplevel(true)
    win:SetPoint("CENTER")
    win:EnableMouse(true); win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 11, top = 11, bottom = 11 },
        })
    end
    tinsert(UISpecialFrames, "MySackConfigWindow")

    local titleBg = win:CreateTexture(nil, "ARTWORK")
    titleBg:SetColorTexture(1, 0.82, 0, 0.07)
    titleBg:SetPoint("TOPLEFT", 14, -14); titleBg:SetPoint("TOPRIGHT", -14, -14); titleBg:SetHeight(30)
    local t = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", 0, -19); t:SetText("MySack Settings"); t:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetFrameLevel(win:GetFrameLevel() + 10)
    close:SetScript("OnClick", function() win:Hide() end)

    checks = {}

    -- ===== TAB: Display (layout) =====
    local d = newTab("Display", 1, 18)
    header(d, "Bags Layout", 8, -8, 220)
    win.colSlider   = makeSlider(d, "Columns", "Columns", 4, 32, 1, 8, -38,  function(v) NS.db.columns = v end)
    win.sizeSlider  = makeSlider(d, "IconSize", "Icon Size", 20, 64, 1, 8, -78, function(v) NS.db.iconSize = v end)
    win.scaleSlider = makeSlider(d, "Scale", "Scale", 0.5, 2.0, 0.1, 8, -118, function(v) NS.db.scale = v end)

    header(d, "Bank Layout", 260, -8, 220)
    win.bankColSlider   = makeSlider(d, "BankColumns", "Columns", 4, 32, 1, 260, -38,  function(v) NS.db.bankColumns = v end)
    win.bankSizeSlider  = makeSlider(d, "BankIconSize", "Icon Size", 20, 64, 1, 260, -78, function(v) NS.db.bankIconSize = v end)
    win.bankScaleSlider = makeSlider(d, "BankScale", "Scale", 0.5, 2.0, 0.1, 260, -118, function(v) NS.db.bankScale = v end)

    header(d, "Global Options", 8, -168, 480)
    win.borderSlider= makeSlider(d, "BorderOpacity", "Border Opacity", 0, 1, 0.05, 8, -198, function(v) NS.db.borderOpacity = v end)
    win.thickSlider = makeSlider(d, "BorderThickness", "Border Thickness", 1, 6, 1, 8, -238, function(v) NS.db.borderThickness = v end)
    win.gapSlider   = makeSlider(d, "GroupSpacing", "Group Spacing", 0, 24, 1, 8, -278, function(v) NS.db.groupSpacing = v end)
    makeCheck(d, "Compact", "Compact layout (pack groups side-by-side)", 6, -314,
        function() return NS.db.compactLayout end, function(v) NS.db.compactLayout = v end)

    -- ===== TAB: Categories (TBag-like) =====
    local c = newTab("Categories", 2, 122)
    header(c, "Create custom categories, reorder, hide/show (affects layout)", 8, -8, 480)

    local catNewBox = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    catNewBox:SetSize(180, 20)
    catNewBox:SetPoint("TOPLEFT", 8, -32)
    catNewBox:SetAutoFocus(false)
    local catNewBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    catNewBtn:SetSize(80, 20)
    catNewBtn:SetPoint("LEFT", catNewBox, "RIGHT", 6, 0)
    catNewBtn:SetText("New Cat")
    local CAT_ROWS, CAT_ROW_H = 15, 18

    catNewBtn:SetScript("OnClick", function()
        local nm = catNewBox:GetText()
        if nm and nm ~= "" then
            NS.AddCustomCategory(nm)
            catNewBox:SetText("")
            
            -- Auto-scroll to show the new category
            local list = {}
            local order = (NS.Cat and NS.Cat.BuildOrder and NS.Cat.BuildOrder(NS.db)) or {}
            for _, k in ipairs(order) do
                if k ~= "EMPTY" then table.insert(list, k) end
            end
            win.catOffset = math.max(0, #list - CAT_ROWS)
            
            NS.RefreshCategoriesList()
            if NS.main then NS.MySack:Render(NS.main) end
            if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
            pcall(NS.RefreshConfig)
        end
    end)

    local catList = CreateFrame("Frame", nil, c)
    catList:SetPoint("TOPLEFT", 8, -60)
    catList:SetSize(500, CAT_ROWS * CAT_ROW_H)
    catList:EnableMouseWheel(true)
    win.catRows = {}
    win.catOffset = 0
    for i=1, CAT_ROWS do
        local row = CreateFrame("Frame", nil, catList)
        row:SetSize(500, CAT_ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i-1)*CAT_ROW_H)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetWidth(120)

        local ruleBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        ruleBox:SetSize(140, 16)
        ruleBox:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        ruleBox:SetAutoFocus(false)
        ruleBox:SetFontObject("ChatFontNormal")
        ruleBox:SetTextColor(0.8, 0.8, 0.8)
        ruleBox:SetScript("OnTextChanged", function(self)
            if row.key and NS.db.customCategories and NS.db.customCategories[row.key] then
                local txt = self:GetText() or ""
                NS.db.customCategories[row.key].rule = (txt ~= "") and txt or nil
            end
        end)
        ruleBox:SetScript("OnEditFocusLost", function(self)
            if NS.main then NS.MySack:Render(NS.main) end
            if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
        end)
        ruleBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        ruleBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        row.ruleBox = ruleBox

        local btnUp = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnUp:SetSize(22, 16); btnUp:SetPoint("LEFT", ruleBox, "RIGHT", 8, 0); btnUp:SetText("^")
        btnUp:SetScript("OnClick", function() if row.key then NS.MoveCategory(row.key, -1); NS.RefreshCategoriesList(); pcall(NS.RefreshConfig); if NS.main then NS.MySack:Render(NS.main) end if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end end end)

        local btnDown = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnDown:SetSize(22, 16); btnDown:SetPoint("LEFT", btnUp, "RIGHT", 2, 0); btnDown:SetText("v")
        btnDown:SetScript("OnClick", function() if row.key then NS.MoveCategory(row.key, 1); NS.RefreshCategoriesList(); pcall(NS.RefreshConfig); if NS.main then NS.MySack:Render(NS.main) end if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end end end)

        local btnHide = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnHide:SetSize(40, 16); btnHide:SetPoint("LEFT", btnDown, "RIGHT", 4, 0)
        btnHide:SetScript("OnClick", function()
            if row.key then
                NS.ToggleCategoryHidden(row.key)
                NS.RefreshCategoriesList()
                pcall(NS.RefreshConfig)
                if NS.main then NS.MySack:Render(NS.main) end
                if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
            end
        end)

        local btnDel = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        btnDel:SetSize(18, 18); btnDel:SetPoint("RIGHT", 0, 0)
        btnDel:SetScript("OnClick", function()
            if row.key and NS.db.customCategories and NS.db.customCategories[row.key] then
                NS.DeleteCustomCategory(row.key)
                NS.RefreshCategoriesList()
                pcall(NS.RefreshConfig)
                if NS.main then NS.MySack:Render(NS.main) end
                if NS.bank and NS.bank:IsShown() then NS.MySack:Render(NS.bank) end
            end
        end)

        row.hideBtn = btnHide
        row.delBtn = btnDel
        win.catRows[i] = row
    end
    catList:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, (win.catCount or 0) - CAT_ROWS)
        win.catOffset = math.min(maxOff, math.max(0, (win.catOffset or 0) - delta))
        NS.RefreshCategoriesList()
    end)
    win.catEmpty = catList:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.catEmpty:SetPoint("TOPLEFT", 2, -2)
    win.catEmpty:SetText("New custom cats above. ^/v reorder. Hide/Show. Drag items to headers or Alt+Right to assign.")

    -- ===== TAB: Items =====
    local it = newTab("Items", 3, 226)
    makeCheck(it, "Ilvl", "Show item level on gear", 6, -14,
        function() return NS.db.showItemLevel end, function(v) NS.db.showItemLevel = v end)
    makeCheck(it, "NewGlow", "Glow newly acquired items", 6, -40,
        function() return NS.db.newItemGlow end, function(v) NS.db.newItemGlow = v end)
    makeCheck(it, "Quest", "Highlight quest items", 6, -66,
        function() return NS.db.questBorder end, function(v) NS.db.questBorder = v end)
    makeCheck(it, "Replace", "Replace default bags (reload to apply)", 6, -92,
        function() return NS.db.replaceBags end, function(v) NS.db.replaceBags = v end)
    makeCheck(it, "AutoCompare", "Auto-compare equipment on hover", 6, -118,
        function() return NS.db.autoCompare end, function(v) NS.db.autoCompare = v end)
    makeCheck(it, "ShowFreeSlots", "Show free bag slots on main backpack button", 6, -144,
        function() return NS.db.showFreeSlotsOnBackpack end, function(v)
            NS.db.showFreeSlotsOnBackpack = v
            if NS.UpdateBackpackButtonFreeSlots then NS.UpdateBackpackButtonFreeSlots() end
        end)


    -- ===== TAB: Automation (sell + repair + drop) =====
    local a = newTab("Automation", 4, 330)
    header(a, "Merchant", 8, -8, 480)
    makeCheck(a, "AutoSell", "Auto-sell junk at merchants", 6, -28,
        function() return NS.db.autoSellJunk end, function(v) NS.db.autoSellJunk = v end)
    makeCheck(a, "AutoRepair", "Auto-repair at merchants", 6, -54,
        function() return NS.db.autoRepair end, function(v) NS.db.autoRepair = v end)
    makeCheck(a, "GuildRepair", "Use guild funds for repairs", 6, -80,
        function() return NS.db.useGuildRepair end, function(v) NS.db.useGuildRepair = v end)
    makeCheck(a, "ProtectTools", "Protect profession tools & rods", 6, -106,
        function() return NS.db.protectTools end, function(v) NS.db.protectTools = v end)
    makeCheck(a, "AutoOpenClams", "Auto-open clam shells in bags", 6, -132,
        function() return NS.db.autoOpenClams end, function(v) NS.db.autoOpenClams = v end)
    makeCheck(a, "AutoFillQuiver", "Auto-fill quiver (when bags closed)", 240, -132,
        function() return NS.db.autoFillQuiver end, function(v) NS.db.autoFillQuiver = v end)

    local sub = a:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 8, -164); sub:SetText("Auto-sell only these types (recipes/formulas always excluded):")
    makeCheck(a, "SellEquip", "Equipment", 6, -182,
        function() return NS.db.sellEquipment end, function(v) NS.db.sellEquipment = v end)
    makeCheck(a, "SellConsum", "Consumables", 180, -182,
        function() return NS.db.sellConsumables end, function(v) NS.db.sellConsumables = v end)
    makeCheck(a, "SellTrade", "Trade goods", 330, -182,
        function() return NS.db.sellTradeGoods end, function(v) NS.db.sellTradeGoods = v end)
    makeCheck(a, "SellOther", "Other (no recipes)", 6, -208,
        function() return NS.db.sellOther end, function(v) NS.db.sellOther = v end)

    local QNAME = { [0]="Poor (grey)", [1]="Common (white)", [2]="Uncommon (green)", [3]="Rare (blue)", [4]="Epic (purple)" }
    win.sellQualSlider = makeSlider(a, "SellQuality", "Auto-sell up to quality", 0, 4, 1, 8, -244,
        function(v) NS.db.autoSellQuality = v end, function(v) return QNAME[v] or v end)
    win.sellIlvlSlider = makeSlider(a, "SellMaxIlvl", "Max item level", 0, 300, 5, 280, -244,
        function(v) NS.db.autoSellMaxIlvl = v end, function(v) return v == 0 and "No limit" or v end)

    header(a, "Auto-drop (when bags full)", 8, -284, 480)
    makeCheck(a, "AutoDrop", "Offer to destroy lowest-value junk when full", 6, -304,
        function() return NS.db.autoDrop end, function(v) NS.db.autoDrop = v end)
    makeCheck(a, "AutoDropWhite", "Include common (white) items", 6, -330,
        function() return NS.db.autoDropWhite end, function(v) NS.db.autoDropWhite = v end)
    win.dropCapSlider = makeSlider(a, "DropCap", "Skip items worth over (silver)", 0, 200, 5, 8, -366,
        function(v) NS.db.autoDropMaxValue = v * 100 end, function(v) return v == 0 and "No limit" or v end)

    -- ===== TAB: Profiles =====
    local p = newTab("Profiles", 5, 434)
    win.profileLabel = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.profileLabel:SetPoint("TOPLEFT", 8, -12)
    local bShared = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    bShared:SetSize(120, 22); bShared:SetPoint("TOPLEFT", 8, -34)
    bShared:SetText("Use Shared")
    bShared:SetScript("OnClick", function() NS.SetProfile("shared"); NS.RefreshConfig() end)
    local bOwn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    bOwn:SetSize(150, 22); bOwn:SetPoint("LEFT", bShared, "RIGHT", 8, 0)
    bOwn:SetText("This Char's Own")
    bOwn:SetScript("OnClick", function() NS.SetProfile("char", true); NS.RefreshConfig() end)
    local reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    reset:SetSize(180, 22); reset:SetPoint("TOPLEFT", 8, -64)
    reset:SetText("Reset Window Position")
    reset:SetScript("OnClick", function()
        NS.db.point = { "BOTTOMRIGHT", nil, "BOTTOMRIGHT", -40, 80 }
        NS.db.bankPoint = { "TOPLEFT", nil, "TOPLEFT", 40, -104 }
        if not InCombatLockdown() then
            if NS.main then
                NS.main:ClearAllPoints()
                local p = NS.db.point
                NS.main:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
            end
            if NS.bank then
                NS.bank:ClearAllPoints()
                local p = NS.db.bankPoint
                NS.bank:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
            end
        end
        NS.MySack:Open()
        print("|cff66ccffMySack|r: Window positions reset to default (Bank on left, Bags on bottom-right).")
    end)

    header(p, "Protected Items (Ctrl+Right in bags; never auto-sold)", 8, -104, 480)
    local LIST_ROWS, ROW_H = 6, 18
    local listFrame = CreateFrame("Frame", nil, p)
    listFrame:SetPoint("TOPLEFT", 8, -124)
    listFrame:SetSize(500, LIST_ROWS * ROW_H)
    listFrame:EnableMouseWheel(true)
    win.protectRows = {}
    win.protectOffset = 0
    for i = 1, LIST_ROWS do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetSize(500, ROW_H); row:SetPoint("TOPLEFT", 0, -(i-1)*ROW_H)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 2, 0); row.text:SetJustifyH("LEFT"); row.text:SetWidth(460)
        local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1,1,1,0.08)
        local x = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        x:SetSize(20, 20); x:SetPoint("RIGHT", 2, 0)
        x:SetScript("OnClick", function()
            if row.itemID then NS.db.userProtect[row.itemID] = nil; NS.RefreshProtectList(); if NS.main then NS.MySack:Render(NS.main) end end
        end)
        row:SetScript("OnEnter", function(self)
            if self.itemID then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        win.protectRows[i] = row
    end
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, (win.protectCount or 0) - LIST_ROWS)
        win.protectOffset = math.min(maxOff, math.max(0, (win.protectOffset or 0) - delta))
        NS.RefreshProtectList()
    end)
    win.protectEmpty = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.protectEmpty:SetPoint("TOPLEFT", 2, -2)
    win.protectEmpty:SetText("None yet. Ctrl+Right-click an item in the bag window to protect it.")

    -- Footer hint (always visible)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 16); hint:SetPoint("BOTTOMRIGHT", -20, 16); hint:SetJustifyH("LEFT")
    hint:SetText("Search: armor/weapon/potion/epic/quest/>60/60-70.  Alt+Right or drag=assign cat.  Ctrl+Left=equip/try-on.  Ctrl+Right=protect.  Bank view remembers contents offline.")

    selectTab(1)
end

function NS.RefreshProtectList()
    if not win or not win.protectRows then return end
    local ids = {}
    for id in pairs(NS.db.userProtect or {}) do ids[#ids+1] = id end
    table.sort(ids)
    win.protectCount = #ids
    win.protectEmpty:SetShown(#ids == 0)
    local maxOff = math.max(0, #ids - #win.protectRows)
    win.protectOffset = math.min(win.protectOffset or 0, maxOff)
    for i, row in ipairs(win.protectRows) do
        local id = ids[i + (win.protectOffset or 0)]
        if id then
            local name = GetItemInfo(id)
            if not name then
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
                name = "item:"..id
            end
            local icon = GetItemIcon and GetItemIcon(id)
            row.itemID = id
            row.text:SetText((icon and ("|T"..icon..":16:16:0:0|t ") or "")..name)
            row:Show()
        else
            row.itemID = nil; row:Hide()
        end
    end
end

function NS.RefreshCategoriesList()
    if not win or not win.catRows then return end
    local settings = NS.db or {}
    local order = (NS.Cat and NS.Cat.BuildOrder and NS.Cat.BuildOrder(settings)) or {}
    local hidden = settings.hiddenCategories or {}
    local customs = settings.customCategories or {}
    local names = (NS.Cat and NS.Cat.GetAllNames and NS.Cat.GetAllNames(settings)) or {}

    -- filter to show only those in order (already filtered)
    local list = {}
    for _, k in ipairs(order) do
        if k ~= "EMPTY" then table.insert(list, k) end
    end
    win.catCount = #list
    win.catEmpty:SetShown(#list == 0)

    local maxOff = math.max(0, #list - #win.catRows)
    win.catOffset = math.min(win.catOffset or 0, maxOff)

    for i, row in ipairs(win.catRows) do
        local idx = i + (win.catOffset or 0)
        local key = list[idx]
        if key then
            row.key = key
            local nm = names[key] or key
            local isCustom = customs[key] ~= nil
            local isHidden = hidden[key]
            row.name:SetText( (isHidden and "|cff888888" or "") .. (isCustom and "[C] " or "") .. nm .. (isHidden and " (hidden)|r" or "") )

            if isCustom then
                row.ruleBox:SetText(customs[key].rule or "")
                row.ruleBox:Show()
            else
                row.ruleBox:SetText("")
                row.ruleBox:Hide()
            end

            row.hideBtn:SetText(isHidden and "Show" or "Hide")
            row.delBtn:SetShown(isCustom)
            row:Show()
        else
            row.key = nil
            if row.ruleBox then row.ruleBox:Hide() end
            row:Hide()
        end
    end
end

function NS.RefreshConfig()
    if not win then return end
    local db = NS.db
    local function set(sl, lbl, v) sl:SetValue(v); sl.titleFS:SetText(lbl..": "..(sl.fmt and sl.fmt(v) or v)) end
    set(win.colSlider, "Columns", db.columns)
    set(win.sizeSlider, "Icon Size", db.iconSize)
    set(win.scaleSlider, "Scale", db.scale)
    set(win.bankColSlider, "Columns", db.bankColumns or db.columns)
    set(win.bankSizeSlider, "Icon Size", db.bankIconSize or db.iconSize)
    set(win.bankScaleSlider, "Scale", db.bankScale or db.scale)
    set(win.borderSlider, "Border Opacity", db.borderOpacity)
    set(win.thickSlider, "Border Thickness", db.borderThickness)
    set(win.gapSlider, "Group Spacing", db.groupSpacing or 2)
    set(win.sellQualSlider, "Auto-sell up to", db.autoSellQuality)
    set(win.sellIlvlSlider, "Max item level", db.autoSellMaxIlvl)
    set(win.dropCapSlider, "Skip items worth over (silver)", math.floor((db.autoDropMaxValue or 0)/100))
    for _, cb in ipairs(checks) do cb:SetChecked(cb.get()) end
    win.profileLabel:SetText("Active profile: |cffffd100"..(NS.activeProfile or "Default").."|r")
    if NS.RefreshProtectList then NS.RefreshProtectList() end
    if NS.RefreshCategoriesList then NS.RefreshCategoriesList() end
end

function NS.ToggleConfig()
    if not win then
        local ok, err = pcall(build)
        if not ok then print("|cffff4444MySack:|r could not build settings window: "..tostring(err)); return end
    end
    if win:IsShown() then
        win:Hide()
    else
        pcall(NS.RefreshConfig)
        win:ClearAllPoints(); win:SetPoint("CENTER")
        win:Show(); win:Raise()
    end
end

local function registerShortcut()
    local panel = CreateFrame("Frame", "MySackOptionsShortcut")
    panel.name = "MySack"
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText("MySack")
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(200, 26); b:SetPoint("TOPLEFT", 16, -56)
    b:SetText("Open MySack Settings")
    b:SetScript("OnClick", function() NS.ToggleConfig() end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "MySack")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if not win then
        local ok, err = pcall(build)
        if not ok then print("|cffff4444MySack:|r settings build failed at login: "..tostring(err)) end
    end
    pcall(registerShortcut)
end)
