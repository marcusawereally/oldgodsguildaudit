local ADDON_NAME = ...

local Audit = CreateFrame("Frame")
local rows = {}
local results = {}
local pendingCalendarCreates = {}
local calendarDraftInvitees = {}
local calendarSelectedDate
local calendarEventTypeIndex = 2
local calendarContinueReady = true
local calendarContinueAt
local calendarContinueTicker
local guildBankOpen = false
local bankLogTimer
local bankInventoryTimer
local bankInventoryQueryState
local bankOpenSessionId
local bankViewMode = "ledger"
local bankKindFilter = "all"
local bankDirectionFilter = "all"
local rosterSearchMode = "all"
local rosterEventFilter = "all"
local rosterEventPageNumber = 1
local ROSTER_EVENT_PAGE_SIZE = 100
local rosterCaptureTimer
local rosterDiscrepancyState
local selectedRosterMember
local rosterRemoveArmedName
local lastGuildEventQuery = 0
local selectedCopyText = ""
local lastApplicantRequest = 0
local pendingGuildRemoveName
local pendingGuildRemoveQueue = {}
local pendingGuildRemoveQueueIndex = 0
local prepareGuildRemoveQueue
local clearGuildRemoveBinding
local recruitingCandidates = {}
local sessionInvitedPlayers = {}
local sessionInviteCount = 0
local whoRequestPending = false
local whoTimeoutTimer
local whoFriendsFrameSuppressed = false
local whoSearchQueue = {}
local whoSearchSeen = {}
local whoCurrentSearch
local whoScanActive = false
local whoQueriesCompleted = 0
local whoQueriesTimedOut = 0
local whoQueriesFailed = 0
local whoScanLabel = ""
local whoScanLogLines = {}
local whoQuerySentAt
local whoContinueReady = false
local whoContinueAt
local whoContinueTicker
local defaultQuietZoneNames
local pendingRecruitingScan
local pendingRecruitingWarning

local DEFAULT_QUIET_ZONE_IDS = {
    -- Battlegrounds
    2597, 6665, 3358, 4710, 4384, 3820, 8485, 6126, 3277, 5449, 5031, 7107, 9136, 6051, 10176,
    -- Arenas
    8008, 4406, 6732, 3968, 4378, 7816, 6296, 3698, 3702, 8624, 14436,
    -- Raids
    3456, 3428, 2677, 3429, 2717, 2159, 1977,
    -- Dungeons
    1477, 2057, 2557, 1337, 2017, 2100, 1176, 1584, 722, 209, 491, 796,
}

local DEFAULTS = {
    minimumMembers = 980,
    inactiveDays = 28,
    guildRealm = "",
    motdPrefix = "Welcome to the Old Gods - ",
    donationsTabName = "Donations",
    discordNmiUrl = "https://discord.com/channels/259402227637026828/532799532820594688",
    discordPromoUrl = "https://discord.com/channels/259402227637026828/1437573461315686510",
    eventTitle = "Old Gods Weekly Dungeon",
    eventHour = 19,
    eventMinute = 0,
    theme = "dark",
    debugEnabled = false,
    minimap = { angle = 225, enabled = true },
    floatingIcon = { enabled = true, x = 200, y = 0 },
    manual = {
        officerMeeting = false,
        newMemberInfo = false,
        missingPromotions = false,
    },
    manualPasses = {},
    reports = {},
    currentAudit = {},
    auditData = {},
    feedback = { submissions = {} },
    recruitingLogs = {},
    recruiting = {
        ignoreQuietZones = true,
        customQuietZones = {},
        antiSpamDays = 7,
        inviteHistory = {},
        ignoredRealmWarnings = {},
        connectedRealmConfig = {},
        realmCache = {},
    },
    calendar = {
        templates = {},
        events = {},
    },
    bank = {
        transactions = {},
        seenTransactions = {},
        snapshots = {},
        currentInventory = {},
        verifiedGuildRealms = {},
    },
    chat = {
        enabled = true,
        customChannels = { "OGLFM", "KEYGODS", "BASIC", "RR", "SMC" },
        messages = {},
    },
    roster = {
        snapshots = {},
        events = {},
        seenGuildEvents = {},
    },

}

local PURGE_ANNOUNCEMENTS = {
    "The Void hungers. Today's purge is beginning. Those lost beyond their chapter inactivity limit may now be claimed.",
    "The feeding begins. The Void has marked those beyond their chapter inactivity limit.",
    "The Void stirs. I am beginning today's purge of souls gone silent for 28+ days.",
    "The gates of the Void are open. Inactive souls of 28+ days are about to be offered.",
    "The Void demands tribute. Today's chapter inactivity purge is now beginning.",
    "The whispers have named the absent. The purge begins for those beyond their chapter inactivity limit.",
    "The Void is hungry again. Time to purge those who have vanished for 28+ days.",
    "The Old Gods awaken. Those beyond their chapter inactivity limit may soon join the Void.",
    "The hour of feeding has arrived. Today's 28+ day inactive purge is beginning.",
    "The Void has counted the missing. I am beginning the purge of members inactive 28+ days.",
    "The whispers grow louder. Souls beyond their chapter inactivity limit are being prepared for the Void.",
    "The darkness calls. Today's purge begins now for members inactive 28+ days.",
    "The Void remembers those who do not return. The chapter inactivity purge is beginning.",
    "The ritual begins. Members lost to inactivity for 28+ days may now be sacrificed to the Void.",
    "The Void must be fed. I am beginning today's purge of those beyond their chapter inactivity limit.",
}

local function copyDefaults(source, destination)
    for key, value in pairs(source) do
        if type(value) == "table" then
            destination[key] = destination[key] or {}
            copyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end
end

-- Never inspect, format, persist, or forward restricted API data.
local function isPublicValue(value)
    return not (issecretvalue and issecretvalue(value))
end

local function isPublicString(value)
    return isPublicValue(value) and type(value) == "string"
end

local function isPublicTable(value)
    return isPublicValue(value) and type(value) == "table"
        and not (issecrettable and issecrettable(value))
end

local function shortName(name)
    if not isPublicString(name) then return "Unknown" end
    return name and name:match("^([^-]+)") or "Unknown"
end


local function trim(value)
    if not isPublicString(value) then return "" end
    return (value or ""):match("^%s*(.-)%s*$")
end


-- Diagnostics are snapshots of the values consumed by Refresh, not new API reads.
function Audit:DebugValue(label, value, seen, indent)
    if not self.debugCapturing then return end
    local lines = self.auditDebugLines
    indent = indent or ""
    local prefix = indent .. label .. ": "
    if not isPublicValue(value) then
        lines[#lines + 1] = prefix .. "<restricted by WoW>"
    elseif type(value) == "table" then
        if not isPublicTable(value) then
            lines[#lines + 1] = prefix .. "<restricted table>"
            return
        end
        seen = seen or {}
        if seen[value] then lines[#lines + 1] = prefix .. "<table already shown>"; return end
        seen[value] = true
        local keys = {}
        for key in pairs(value) do
            if isPublicValue(key) and (type(key) == "number" or type(key) == "string") then keys[#keys + 1] = key end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then return a < b end
            return type(a) == "number"
        end)
        lines[#lines + 1] = prefix .. (#keys == 0 and "{}" or "")
        for _, key in ipairs(keys) do self:DebugValue("[" .. tostring(key) .. "]", value[key], seen, indent .. "  ") end
    else
        local text = value == nil and "<nil / unavailable>" or tostring(value)
        if type(value) == "string" then
            text = value == "" and '""' or value:gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
        elseif type(value) == "function" then text = "<callback>" end
        lines[#lines + 1] = prefix .. text
    end
end

function Audit:DebugValues(section, ...)
    if not self.debugCapturing then return end
    if section then
        self.auditDebugLines[#self.auditDebugLines + 1] = ""
        self.auditDebugLines[#self.auditDebugLines + 1] = section
    end
    for i = 1, select("#", ...), 2 do
        local label, value = select(i, ...)
        self:DebugValue(label, value)
    end
end

local function normalizeRealmKey(realmName)
    return trim(realmName):lower():gsub("[^%w]", "")
end

local function recruitingCharacterIdentity()
    local playerName, playerRealm = UnitFullName("player")
    playerName = trim(playerName)
    if playerName == "" then playerName = trim(UnitName("player")) end
    playerRealm = trim(playerRealm)
    if playerRealm == "" then playerRealm = trim(GetNormalizedRealmName and GetNormalizedRealmName()) end
    if playerRealm == "" then playerRealm = trim(GetRealmName and GetRealmName()) end
    return playerName .. "-" .. playerRealm, playerRealm
end

local function recruitingRealmCache()
    local character, characterRealm = recruitingCharacterIdentity()
    local guildName = trim(GetGuildInfo("player"))
    local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local region = GetCurrentRegion and GetCurrentRegion() or 0
    local key = table.concat({tostring(region), character:lower(), guildName:lower(), tostring(clubId or "")}, "|")
    local recruiting = OldGodsGuildAuditDB.recruiting
    recruiting.realmCache = recruiting.realmCache or {}
    recruiting.realmCache[key] = recruiting.realmCache[key] or {}
    local cache = recruiting.realmCache[key]
    cache.characterRealm = characterRealm
    cache.guildName = guildName
    return cache, key
end

local function recruitingGuildRealm()
    local guildName, _, _, guildRealm = GetGuildInfo("player")
    if trim(guildName) == "" then return nil, "unavailable" end
    local cache = recruitingRealmCache()
    local sameRealm = guildRealm == nil
    guildRealm = trim(guildRealm)
    if guildRealm ~= "" then
        cache.guildRealm = guildRealm
        cache.checkedAt = GetServerTime()
        -- Retained for existing exports; never read as an account-wide fallback.
        OldGodsGuildAuditDB.guildRealm = guildRealm
        return guildRealm, "guild API"
    end
    if trim(cache.guildRealm) ~= "" then return cache.guildRealm, "saved guild data" end
    -- The optional realm is omitted for a same-realm guild. Only use this
    -- fallback once the API has actually supplied the current guild name.
    if sameRealm and trim(cache.characterRealm) ~= "" then
        cache.guildRealm = trim(GetRealmName and GetRealmName())
        if cache.guildRealm == "" then cache.guildRealm = cache.characterRealm end
        cache.checkedAt = GetServerTime()
        return cache.guildRealm, "same-realm guild API"
    end
    return nil, "unavailable"
end

local function connectedRealmLookup()
    local cache = recruitingRealmCache()
    local getter = C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms or GetAutoCompleteRealms
    local ok, realms
    if getter then ok, realms = pcall(getter) end
    local source = "saved connected realms"
    if ok and type(realms) == "table" and next(realms) then
        local names = {}
        for _, realm in ipairs(realms) do
            if trim(realm) ~= "" then names[#names + 1] = realm end
        end
        if #names > 0 then
            cache.connectedRealms = names
            cache.connectedCheckedAt = GetServerTime()
            source = "WoW connected realms API"
        end
    end
    local lookup = {}
    local playerKey = normalizeRealmKey(cache.characterRealm)
    if playerKey ~= "" then lookup[playerKey] = "player" end
    for _, realm in ipairs(cache.connectedRealms or {}) do
        local key = normalizeRealmKey(realm)
        if key ~= "" then lookup[key] = "player" end
    end
    return lookup, { source = source, schemaVersion = 2 }
end

local function realmsAreConnected(leftRealm, rightRealm)
    local left = normalizeRealmKey(leftRealm)
    local right = normalizeRealmKey(rightRealm)
    if left == "" or right == "" then return false end
    if left == right then return true end
    local lookup = connectedRealmLookup()
    return lookup[left] ~= nil and lookup[left] == lookup[right]
end

local function recruitingRealmIgnoreKey()
    local _, key = recruitingRealmCache()
    return key .. "|" .. normalizeRealmKey(recruitingGuildRealm())
end

local function recruitingRealmWarning()
    local character, characterRealm = recruitingCharacterIdentity()
    local guildRealm = recruitingGuildRealm()
    -- Refresh/cache the live group even for an exact realm match.
    connectedRealmLookup()
    local ignored = OldGodsGuildAuditDB.recruiting.ignoredRealmWarnings[recruitingRealmIgnoreKey()] == true
    if not guildRealm or guildRealm == "" then
        return "|cffff3030Recruiting warning: Blizzard has not supplied the guild realm yet. Open the guild roster and try again.|r", ignored
    end
    if realmsAreConnected(characterRealm, guildRealm) or (OldGodsChapterSettings and OldGodsChapterSettings.IsOpenRealm(characterRealm)) then return nil, false end
    return string.format("|cffff3030Recruiting warning: %s is on %s, outside the connected-realm group for guild realm %s.|r", character, characterRealm, guildRealm), ignored
end

-- Display aliases apply only to the MOTD audit, never to stored guild identity.
local MOTD_REALM_ALIASES = {
    ["397395211"] = "Aegwynn",
}

local function motdAuditRealm(guildRealm)
    local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    local alias = clubId and MOTD_REALM_ALIASES[tostring(clubId)]
    return alias or guildRealm, alias and "guild club ID alias" or "guild realm", clubId
end

local function expectedGuildMotd(guildRealm)
    local guildName = trim(GetGuildInfo("player"))
    if guildName == "" or trim(guildRealm) == "" then return nil end
    return "Welcome to " .. guildName .. " - " .. guildRealm
end

local function guildMotdChecks(motd, guildName, guildRealm)
    local function normalize(value) return trim(value):gsub("%s+", " "):lower() end
    local text = normalize(motd)
    -- Fold guild names only; preserve realm and invite comparisons.
    local function foldGuildO(value)
        for _, letter in ipairs({"Ø", "ø", "Ó", "ó", "Ò", "ò", "Ô", "ô", "Ö", "ö", "Õ", "õ", "Ō", "ō", "Ŏ", "ŏ", "Ő", "ő"}) do value = value:gsub(letter, "o") end
        for _, mark in ipairs({"́", "̀", "̂", "̈", "̃", "̄", "̆", "̋"}) do value = value:gsub("o" .. mark, "o"):gsub("O" .. mark, "o") end
        return value
    end
    local function findPart(value, offset, guild)
        local searchText = guild and foldGuildO(text) or text
        value = normalize(value)
        if guild then value = foldGuildO(value) end
        if value == "" then return nil end
        while true do
            local first, last = searchText:find(value, offset, true)
            if not first then return nil end
            local before, after = searchText:sub(first - 1, first - 1), searchText:sub(last + 1, last + 1)
            if (first == 1 or before:match("[%s%p]")) and (after == "" or after:match("[%s%p]")) then return last + 1 end
            offset = first + 1
        end
    end
    local hasGuild = findPart(guildName, 1, true) ~= nil
    local hasRealm = findPart(guildRealm, 1) ~= nil
    local hasDiscord = findPart("discord.gg/oldgods", 1) ~= nil
    return hasGuild and hasRealm, hasDiscord, hasGuild, hasRealm
end

function Audit:BeginDebugSnapshot()
    self.auditDebugLines = {}
    self.debugCapturing = OldGodsGuildAuditDB.debugEnabled == true
    if not self.debugCapturing then return end
    local playerName = UnitName("player")
    local _, playerRealm = recruitingCharacterIdentity()
    local guildName, guildRankName, guildRankIndex, apiGuildRealm = GetGuildInfo("player")
    local guildRealm, realmSource = recruitingGuildRealm()
    local lookup, config = connectedRealmLookup()
    local cache, cacheKey = recruitingRealmCache()
    self:DebugValues(nil, "Player Name", playerName, "Player Realm", playerRealm,
        "Guild Name", guildName, "Guild Realm", guildRealm)
    self.auditDebugLines[#self.auditDebugLines + 1] = "Guild Connected Realms:"
    if guildRealm and lookup[normalizeRealmKey(guildRealm)] then
        local names, seen = {}, {}
        for _, name in ipairs(cache.connectedRealms or {}) do
            local key = normalizeRealmKey(name)
            if key ~= "" and not seen[key] then names[#names + 1] = name; seen[key] = true end
        end
        for _, name in ipairs({guildRealm, playerRealm}) do
            local key = normalizeRealmKey(name)
            if key ~= "" and not seen[key] then names[#names + 1] = name; seen[key] = true end
        end
        table.sort(names)
        for _, name in ipairs(names) do self.auditDebugLines[#self.auditDebugLines + 1] = "  - " .. name end
        if not cache.connectedRealms then
            self.auditDebugLines[#self.auditDebugLines + 1] = "  - Connected-realm list unavailable; only the known realm is shown."
        end
    else
        self.auditDebugLines[#self.auditDebugLines + 1] = "  - Unavailable: WoW's player realm group does not identify this guild's group."
    end
    self:DebugValues("Identity sources", "addonVersion", C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "unavailable", "capturedAt", GetServerTime(), "guildRankName", guildRankName, "guildRankIndex", guildRankIndex,
        "apiGuildRealm", apiGuildRealm, "realmSource", realmSource, "connectedRealmSource", config.source,
        "cacheKey", cacheKey, "realmCache", cache)
end

local function normalizeRecruitName(name)
    local normalized = trim(name or ""):lower():gsub("%s+", "")
    local playerName, realmName = normalized:match("^(.-)%-(.+)$")
    if not playerName then
        playerName = normalized
        realmName = (GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName() or "unknown"):lower():gsub("%s+", "")
    end
    return playerName .. "-" .. realmName
end

local function pruneInviteHistory()
    if not OldGodsGuildAuditDB or not OldGodsGuildAuditDB.recruiting then return 0 end
    local recruiting = OldGodsGuildAuditDB.recruiting
    recruiting.inviteHistory = recruiting.inviteHistory or {}
    local days = tonumber(recruiting.antiSpamDays) or 7
    if days <= 0 then return 0 end
    local cutoff = time() - (days * 86400)
    local removed = 0
    for normalizedName, invitedAt in pairs(recruiting.inviteHistory) do
        if type(invitedAt) ~= "number" or invitedAt < cutoff then
            recruiting.inviteHistory[normalizedName] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function getInviteHistoryCount()
    local history = OldGodsGuildAuditDB and OldGodsGuildAuditDB.recruiting and OldGodsGuildAuditDB.recruiting.inviteHistory or {}
    local count = 0
    for _ in pairs(history) do count = count + 1 end
    return count
end

local function isLeaderRank(rankName, rankIndex)
    local rank = (rankName or ""):lower()
    return (type(rankIndex)=="number" and rankIndex>=0 and rankIndex<=4) or rank:find("officer", 1, true) or rank:find("guild master", 1, true) or rank == "gm"
end

local function daysOffline(index, online)
    if online then return 0 end
    local years, months, days, hours = GetGuildRosterLastOnline(index)
    Audit:DebugValues(nil, "lastOnline.years", years, "lastOnline.months", months, "lastOnline.days", days, "lastOnline.hours", hours)
    if not years then return nil end
    return (years * 365) + (months * 30) + days + ((hours or 0) / 24)
end

-- Calendar splits its 10-point category into two checks.
local function auditScore()
    local earned, total = 0, 0
    for _, result in ipairs(results) do
        total = total + result.points
        if result.passed == true then earned = earned + result.points end
    end
    return total > 0 and earned * 100 / total or 0, earned, total
end

local function addResult(key, title, passed, summary, items, actions, points, allowManual)
    points = (key == "dungeon" or key == "meeting") and 5 or (points or 10)
    Audit:DebugValues("Result: " .. key, "rawPassed", passed, "manualPasses[" .. key .. "]", OldGodsGuildAuditDB.manualPasses[key], "allowManual", allowManual ~= false)
    local manualOverride = allowManual ~= false and passed == nil and OldGodsGuildAuditDB and OldGodsGuildAuditDB.manualPasses[key]
    if manualOverride then
        passed = true
        summary = (summary or "") .. " (manually marked passed)"
    end
    Audit:DebugValues(nil, "title", title, "passed", passed, "summary", summary, "items", items, "actions", actions, "points", points or 10, "manualOverride", manualOverride)
    results[#results + 1] = {
        key = key,
        title = title,
        passed = passed,
        summary = summary,
        items = items or {},
        actions = actions or {},
        points = points or 10,
        manualOverride = manualOverride,
        allowManual = allowManual ~= false,
    }
end

local function showCopyBox(text)
    selectedCopyText = text
    Audit:ShowThemedDialog("OLD_GODS_AUDIT_COPY", nil, text)
end

StaticPopupDialogs.OLD_GODS_AUDIT_COPY = {
    text = "Press Ctrl+C to copy the selected text.",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 260,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self, data)
        self.EditBox:SetText(data or selectedCopyText)
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
}

-- External Discord URLs cannot be launched by addon code; provide a focused copy field.
StaticPopupDialogs.OLD_GODS_AUDIT_DISCORD_CHANNEL = {
    text = "%s\nCopy the URL into your browser, review the channel, then mark it checked.\nUse Ctrl+C (Command+C on Mac).",
    button1 = "Mark Checked",
    button2 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 360,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self, data)
        local link = OldGodsGuildAuditDB[data.urlKey]
        self.EditBox:SetText(link and link ~= "" and link or ("Configure " .. data.urlKey .. " in SavedVariables."))
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    OnAccept = function(self, data)
        OldGodsGuildAuditDB.manual[data.flag] = true
        Audit:Refresh()
    end,
    EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
}

local function openGuildRoster()
    if ToggleGuildFrame then ToggleGuildFrame() elseif GuildFrame then GuildFrame:Show() end
end

function Audit:OpenGuildInformation()
    if InCombatLockdown() then print("Old Gods Audit: Leave combat to open Guild Information."); return end
    if not (CommunitiesFrame and CommunitiesFrame:IsShown()) then openGuildRoster() end
    local attempts = 0
    local function selectInformation()
        if InCombatLockdown() then return end
        attempts = attempts + 1
        local tab = CommunitiesFrame and CommunitiesFrame.GuildInfoTab
        if tab and tab.Click and CommunitiesFrame:IsShown() then tab:Click(); return end
        if attempts < 10 then C_Timer.After(0.1, selectInformation)
        else print("Old Gods Audit: Select Guild Information in the guild window to view the MOTD.") end
    end
    C_Timer.After(0.1, selectInformation)
end

local function openCalendar()
    if ToggleCalendar then ToggleCalendar() elseif CalendarFrame then CalendarFrame:Show() end
end

local function openGuildBank()
    if GuildBankFrame then GuildBankFrame:Show() else print("Old Gods Audit: Open the guild bank at a banker to scan it.") end
end

local function openRecruitment()
    if not CommunitiesFrame then
        if ToggleGuildFrame then ToggleGuildFrame() end
    else
        CommunitiesFrame:Show()
    end
    print("Old Gods Audit: Open Guild & Communities > Guild Finder / Recruitment.")
end

local function scanRoster()
    local total = GetNumGuildMembers() or 0
    local minimum = OldGodsChapterSettings and OldGodsChapterSettings.Policy().minimum or OldGodsGuildAuditDB.minimumMembers
    Audit:DebugValues("Roster", "total", total, "minimumMembers", OldGodsGuildAuditDB.minimumMembers, "inactiveDays", OldGodsGuildAuditDB.inactiveDays)
    addResult("members", "Guild members count", total >= minimum,
        string.format("%d / %d members", total, minimum))

    local inactive, inactiveNames, missingNotes, badOfficerNotes = {}, {}, {}, {}
    for index = 1, total do
        local name, rankName, rankIndex, _, _, _, publicNote, _, online, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
        Audit:DebugValues("Roster member " .. index, "index", index, "name", name, "rankName", rankName, "rankIndex", rankIndex, "publicNote", publicNote, "online", online, "guid", guid)
        if name then
            local memberName = name
            local plainName = shortName(name)
            local offline = daysOffline(index, online)
            Audit:DebugValues(nil, "memberName", memberName, "plainName", plainName, "offlineDays", offline)
            if (OldGodsChapterSettings and OldGodsChapterSettings.IsInactive(rankIndex, offline))
                or (not OldGodsChapterSettings and rankIndex ~= 0 and rankIndex ~= 1 and offline and offline >= 28) then
                inactive[#inactive + 1] = {
                    text = string.format("%s — %.0f days inactive", name, offline),
                    actions = {{ label = "Kick", secureGuildRemove = memberName }},
                }
                inactiveNames[#inactiveNames + 1] = memberName
            end

            local note = trim(publicNote)
            Audit:DebugValues(nil, "trimmedNote", note, "isLeaderRank", isLeaderRank(rankName, rankIndex))
            if isLeaderRank(rankName, rankIndex) then
                if not (OldGodsChapterSettings and OldGodsChapterSettings.NoteValid(note, rankIndex, true) or (not OldGodsChapterSettings and (note:lower():match("^discord:%s*%S+") or note:lower():match("^disc:%s*%S+") or note:lower():match("^discord%s*%-%s*%S+")))) then
                    badOfficerNotes[#badOfficerNotes + 1] = {
                        text = string.format("%s (%s) — note is '%s'", name, rankName or "Officer", note),
                        actions = {{ label = "Open roster", callback = openGuildRoster }},
                    }
                end
            end
            if note == "" or (OldGodsChapterSettings and not OldGodsChapterSettings.NoteValid(note, rankIndex, false)) then
                missingNotes[#missingNotes + 1] = {
                    text = string.format("%s — note is '%s'", name, note),
                    actions = {
                        { label = "Copy Main", callback = function() showCopyBox(OldGodsChapterSettings and OldGodsChapterSettings.NoteText(plainName, "Main") or (plainName .. "-Main")) end },
                        { label = "Copy Alt", callback = function() showCopyBox(OldGodsChapterSettings and OldGodsChapterSettings.NoteText(plainName, "Alt") or (plainName .. "-Alt")) end },
                    },
                }
            end
        end
    end

    Audit:DebugValues("Roster findings", "inactive", inactive, "inactiveNames", inactiveNames, "missingNotes", missingNotes, "badOfficerNotes", badOfficerNotes, "pendingGuildRemoveQueue", pendingGuildRemoveQueue)
    local inactiveActions = {}
    if #inactiveNames > 0 then
        inactiveActions[1] = {
            label = #pendingGuildRemoveQueue > 0 and "Cancel Kick Queue" or "Queue Inactive Kicks",
            width = 170,
            callback = function()
                if #pendingGuildRemoveQueue > 0 then
                    clearGuildRemoveBinding("Inactive kick queue cancelled.")
                    Audit:Refresh()
                elseif prepareGuildRemoveQueue then
                    prepareGuildRemoveQueue(inactiveNames)
                end
            end,
        }
        inactiveActions[2] = { label = "Announce Purge", securePurgeAnnouncement = true, width = 155 }
    end
    addResult("inactive", "Members meet the 28-day inactivity rule", #inactive == 0,
        #inactive == 0 and "No inactive members found" or (#inactive .. " members need review"), inactive, inactiveActions)
    addResult("officerNotes", "Officer public notes include Discord names", #badOfficerNotes == 0,
        #badOfficerNotes == 0 and "Officer notes match" or (#badOfficerNotes .. " officer notes need attention"), badOfficerNotes)
    addResult("memberNotes", "Member public notes match chapter rules", #missingNotes == 0,
        #missingNotes == 0 and "All members have a public note" or (#missingNotes .. " public notes need attention"), missingNotes)
end

local function scanMotd()
    local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
    local guildRealm, realmSource = recruitingGuildRealm()
    local guildName = GetGuildInfo("player")
    local motdRealm, motdRealmSource, guildClubId = motdAuditRealm(guildRealm)
    local expected = (guildName or "[guild name]") .. " ... " .. (motdRealm or "[guild realm]") .. " ... discord.gg/oldgods"
    local ok, hasDiscord, hasGuild, hasRealm = guildMotdChecks(motd, guildName, motdRealm)
    Audit:RecordAuditEvidence("motd", {source="GetGuildRosterMOTD", known=GetGuildRosterMOTD~=nil and isPublicString(motd), text=GetGuildRosterMOTD and isPublicString(motd) and motd or nil, realm=motdRealm})
    local missing = {}
    if not hasGuild then missing[#missing+1] = "guild name: " .. (guildName or "unavailable") end
    if not hasRealm then missing[#missing+1] = "realm: " .. (motdRealm or "unavailable") end
    if not hasDiscord then missing[#missing+1] = "Discord invite: discord.gg/oldgods" end
    ok = ok and hasDiscord
    Audit:DebugValues("MOTD", "motd", motd, "guildName", guildName, "guildRealm", guildRealm, "realmSource", realmSource, "motdRealm", motdRealm, "motdRealmSource", motdRealmSource, "guildClubId", guildClubId, "requiredContent", expected, "ok", ok, "hasDiscord", hasDiscord)
    local function copyMotdDebug()
        local guildName, guildRankName, guildRankIndex, apiGuildRealm = GetGuildInfo("player")
        local lines = {
            "Old Gods Guild Audit - MOTD diagnostics",
            "addonVersion=" .. tostring(GetAddOnMetadata and GetAddOnMetadata("OldGodsGuildAudit", "Version") or "unknown"),
            "guildName=" .. string.format("%q", guildName or ""),
            "guildRankName=" .. string.format("%q", guildRankName or ""),
            "guildRankIndex=" .. tostring(guildRankIndex),
            "GetGuildInfoRealm=" .. string.format("%q", apiGuildRealm or ""),
            "GetRealmName=" .. string.format("%q", GetRealmName and GetRealmName() or ""),
            "GetNormalizedRealmName=" .. string.format("%q", GetNormalizedRealmName and GetNormalizedRealmName() or ""),
            "savedGuildRealm=" .. string.format("%q", OldGodsGuildAuditDB.guildRealm or ""),
            "resolvedGuildRealm=" .. string.format("%q", guildRealm or ""),
            "motdRealm=" .. string.format("%q", motdRealm or ""),
            "motdRealmSource=" .. string.format("%q", motdRealmSource),
            "guildClubId=" .. tostring(guildClubId),
            "realmSource=" .. string.format("%q", realmSource or ""),
            "requiredContent=" .. string.format("%q", expected or ""),
            "hasDiscordInvite=" .. tostring(hasDiscord),
            "requiredContentAnywhere=" .. string.format("%q", expected or ""),
            "rawMotd=" .. string.format("%q", motd or ""),
            "motdLength=" .. tostring(#(motd or "")),
            "finalResult=" .. tostring(ok),
        }
        showCopyBox(table.concat(lines, "\n"))
    end
    addResult("motd", "MOTD contains guild name, realm, and Discord invite", ok,
        ok and "All required content is present, in any order. Extra wording is allowed." or ("Missing " .. table.concat(missing, "; ")),
        {}, {{ label = "Open Guild Information", callback = function() Audit:OpenGuildInformation() end, width = 190 }, { label = "Copy MOTD Debug", callback = copyMotdDebug, width = 150, debugOnly = true }}, nil, false)
end

local function scanRecruitment()
    Audit:DebugValues("Recruitment", "C_ClubFinder available", C_ClubFinder ~= nil, "GetClubRecruitmentSettings available", C_ClubFinder and C_ClubFinder.GetClubRecruitmentSettings ~= nil)
    local items = {}
    local passed = nil
    local capturedRemaining, capturedDays, capturedDelisted
    local timingSource="C_ClubFinder.GetClubRecruitmentSettings"
    local summary = "Open Recruitment through Blizzard's Guild window and confirm at least 26 days remain"
    local function copyRecruitmentDebug()
        local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        local settings
        local lines = {
            "Old Gods Guild Audit - Recruitment diagnostics",
            "clubId=" .. tostring(clubId),
            "clubFinderAvailable=" .. tostring(C_ClubFinder ~= nil),
            "clubFinderEnabled=" .. tostring(C_ClubFinder and C_ClubFinder.IsEnabled and C_ClubFinder.IsEnabled()),
            "expirationHelperAvailable=" .. tostring(type(ClubFinderGetClubPostingExpirationTime) == "function"),
        }
        if C_ClubFinder and C_ClubFinder.GetClubRecruitmentSettings then
            local ok, value = pcall(C_ClubFinder.GetClubRecruitmentSettings)
            lines[#lines + 1] = "settingsCallSucceeded=" .. tostring(ok)
            settings = ok and value or nil
            if not ok then lines[#lines + 1] = "settingsError=" .. tostring(value) end
        end
        if type(settings) == "table" then
            local keys = {}
            for key in pairs(settings) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, key in ipairs(keys) do
                lines[#lines + 1] = string.format("settings.%s=%s", tostring(key), tostring(settings[key]))
            end
        else
            lines[#lines + 1] = "settings=" .. tostring(settings)
        end
        if clubId and C_ClubFinder and C_ClubFinder.HasPostingBeenDelisted then
            local ok, value = pcall(C_ClubFinder.HasPostingBeenDelisted, clubId)
            lines[#lines + 1] = (ok and "delisted=" or "delistedError=") .. tostring(value)
        end
        if clubId and type(ClubFinderGetClubPostingExpirationTime) == "function" then
            local ok, value = pcall(ClubFinderGetClubPostingExpirationTime, clubId)
            lines[#lines + 1] = (ok and "expirationDays=" or "expirationError=") .. tostring(value)
        end
        showCopyBox(table.concat(lines, "\n"))
    end
    if C_ClubFinder and C_ClubFinder.GetClubRecruitmentSettings and C_Club and C_Club.GetGuildClubId then
        local clubId = C_Club.GetGuildClubId()
        local ok, settings = pcall(C_ClubFinder.GetClubRecruitmentSettings)
        settings = ok and isPublicTable(settings) and settings or nil
        local remaining = settings and (settings.secondsRemaining or settings.timeRemaining)
        Audit:DebugValues(nil, "clubId", clubId, "settings", settings, "remainingSeconds", remaining)
        if isPublicValue(remaining) and type(remaining)=="number" and remaining>=0 then
            capturedRemaining=remaining
            local days = math.floor(remaining / 86400)
            Audit:DebugValues(nil, "days", days, "minimumDays", 26)
            passed = days >= 26
            summary = string.format("Recruitment listing: %d days remaining", days)
        end
    end
    if capturedRemaining==nil and Audit.postingReadReady and type(ClubFinderGetClubPostingExpirationTime)=="function" then
        local clubId=C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        local ok, days=pcall(ClubFinderGetClubPostingExpirationTime,clubId)
        if ok and isPublicValue(days) and type(days)=="number" then
            capturedDays=math.max(0,days);timingSource="ClubFinderGetClubPostingExpirationTime"
            passed=capturedDays>=26;summary=string.format("Recruitment listing: %.0f days remaining",capturedDays)
        end
    end
    if C_ClubFinder and C_ClubFinder.HasPostingBeenDelisted and C_Club and C_Club.GetGuildClubId then
        local clubId=C_Club.GetGuildClubId()
        local ok, delisted=pcall(C_ClubFinder.HasPostingBeenDelisted,clubId)
        if ok and isPublicValue(delisted) and type(delisted)=="boolean" then capturedDelisted=delisted end
        if capturedDelisted then passed=false;summary="Recruitment posting has been delisted" end
    end
    Audit:RecordAuditEvidence("recruitment", {source=timingSource, postingStatusSource="C_ClubFinder.HasPostingBeenDelisted", delisted=capturedDelisted, known=capturedRemaining~=nil or capturedDays~=nil or capturedDelisted==true, daysRemaining=capturedDays, secondsRemaining=capturedRemaining, expiresAt=capturedRemaining and (GetServerTime()+capturedRemaining) or nil})
    addResult("recruitment", "Recruitment message remains active", passed, summary, items,
        {
            { label = "Copy Recruitment Debug", callback = copyRecruitmentDebug, width = 180, debugOnly = true },
        })
end

local function scanApplications()
    local applicants, known = {}, false
    Audit:DebugValues("Applications", "RequestApplicantList available", C_ClubFinder and C_ClubFinder.RequestApplicantList ~= nil, "lastApplicantRequest", lastApplicantRequest)
    if C_ClubFinder and C_ClubFinder.RequestApplicantList and C_Club and C_Club.GetGuildClubId then
        local clubId = C_Club.GetGuildClubId()
        Audit:DebugValue("clubId", clubId)
        if clubId then
            if GetTime() - lastApplicantRequest > 5 then
                lastApplicantRequest = GetTime()
                local guildRequestType = Enum and Enum.ClubFinderRequestType and Enum.ClubFinderRequestType.Guild or 1
                Audit:DebugValues(nil, "lastApplicantRequest", lastApplicantRequest, "guildRequestType", guildRequestType)
                C_ClubFinder.RequestApplicantList(guildRequestType)
            end
            local list = C_ClubFinder.ReturnClubApplicantList and C_ClubFinder.ReturnClubApplicantList(clubId)
            Audit:DebugValue("applicantList", list)
            if isPublicTable(list) then
                known = Audit.applicantReadReady==true
                for _, applicant in ipairs(list) do
                    if not isPublicTable(applicant) then known=false
                    else
                        local status,closed=applicant.requestStatus,applicant.closed
                        local statuses=Enum and Enum.PlayerClubRequestStatus
                        local statusKnown=false
                        if statuses and isPublicValue(status) then
                            for _,value in pairs(statuses) do if value==status then statusKnown=true;break end end
                        end
                        if not isPublicValue(closed) or not statusKnown then known=false
                        elseif not (closed==true or (type(closed)=="number" and closed~=0)) and status==statuses.Pending then
                            applicants[#applicants + 1] = { text = isPublicString(applicant.name) and applicant.name or (isPublicString(applicant.playerName) and applicant.playerName or "Pending applicant") }
                        end
                    end
                end
            end
        end
    end
    Audit:DebugValues(nil, "applicants", applicants, "known", known)
    Audit:RecordAuditEvidence("applications", {source="C_ClubFinder.ReturnClubApplicantList", known=known, pendingCount=known and #applicants or nil})
    local applicationPass
    if known then applicationPass=#applicants==0 end
    addResult("applications", "No guild applications awaiting review", applicationPass,
        known and (#applicants == 0 and "No pending applications" or (#applicants .. " pending applications")) or "Open Recruitment through Blizzard's Guild window to load applications",
        applicants, {})
end

local function scanBank()
    local items, scanned = {}, false
    local tabIndex = OldGodsChapterSettings and OldGodsChapterSettings.DonationsTab() or 1
    local tabLabel = "Tab " .. tabIndex
    Audit:DebugValue("donationsTabIndex", tabIndex)
    Audit:DebugValues("Bank", "bankOpenSessionId", bankOpenSessionId, "donationsTabName", OldGodsGuildAuditDB.donationsTabName, "manualPasses.bank before clearing", OldGodsGuildAuditDB.manualPasses.bank)
    OldGodsGuildAuditDB.manualPasses.bank = nil
    local currentSnapshot
    if bankOpenSessionId then
        for _, snapshot in pairs(OldGodsGuildAuditDB.bank.currentInventory or {}) do
            if snapshot.id == bankOpenSessionId then currentSnapshot = snapshot; break end
        end
    end
    Audit:DebugValue("currentSnapshot", currentSnapshot)
    if currentSnapshot then
        for _, tab in ipairs(currentSnapshot.tabs or {}) do
            local tabName = tab.name
            Audit:DebugValue("tabName", tabName)
            if tab.index == tabIndex then
                tabLabel = tabLabel .. " — " .. (tabName or "Unnamed")
                scanned = true
                for _, item in ipairs(tab.items or {}) do
                    local link = item.itemLink
                    local isPetCage = link and (link:find("|Hbattlepet:", 1, true) or tonumber(item.itemID) == 82800 or link:find("|Hitem:82800:", 1, true) or link:find("[Pet Cage]", 1, true))
                    Audit:DebugValues(nil, "item.slot", item.slot, "item.itemID", item.itemID, "link", link, "isPetCage", isPetCage)
                    if link and not isPetCage then
                        items[#items + 1] = { text = string.format("Slot %d: %s", item.slot or 0, link) }
                    end
                end
            end
        end
    end
    local passed
    if scanned then passed = #items == 0 end
    Audit:DebugValues(nil, "scanned", scanned, "items", items, "passed", passed)
    addResult("bank", "Donations tab contains only battle pet cages", passed,
        scanned and (tabLabel .. (#items == 0 and ": Donations tab is clean" or ": Clean out the Donations tab"))
            or (currentSnapshot and (tabLabel .. " is missing or unreadable. Check Chapter > Bank and bank permissions.") or "Bank information has not been read this session. Open the guild bank to refresh, then click Refresh."),
        items, {{ label = "Open bank", callback = openGuildBank }}, 10, false)
end

local function calendarTimePlusDays(daysAhead)
    local now = time()
    local date = date("*t", now + (daysAhead * 86400))
    return { year = date.year, month = date.month, monthDay = date.day, weekday = date.wday, hour = date.hour, minute = date.min }
end

local function scanCalendar()
    local hasDungeon, hasMeeting, loaded = false, false, false
    local dungeonCount, meetingCount = 0, 0
    local types=Enum and Enum.CalendarEventType
    local dungeonType=types and types.Dungeon or CALENDAR_EVENTTYPE_DUNGEON
    local meetingType=types and types.Meeting or CALENDAR_EVENTTYPE_MEETING
    local fromDate, toDate = calendarTimePlusDays(0), calendarTimePlusDays(42)
    Audit:DebugValues("Calendar", "C_Calendar available", C_Calendar ~= nil, "hasDungeon", hasDungeon, "hasMeeting", hasMeeting, "loaded", loaded)
    if C_Calendar then
        if not Audit.capturingForUpload then C_Calendar.OpenCalendar() end
        local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
        Audit:DebugValue("clubId", clubId)
        if isPublicValue(clubId) and clubId and C_Calendar.GetClubCalendarEvents then
            Audit:DebugValues(nil, "fromDate", fromDate, "toDate", toDate)
            local events = C_Calendar.GetClubCalendarEvents(clubId, fromDate, toDate)
            Audit:DebugValue("events", events)
            if isPublicTable(events) then
                loaded = type(dungeonType)=="number" and type(meetingType)=="number"
                for _, event in ipairs(events) do
                    if isPublicTable(event) and isPublicValue(event.eventType) then
                        if event.eventType == dungeonType then dungeonCount=dungeonCount+1 end
                        if event.eventType == meetingType then meetingCount=meetingCount+1 end
                        hasDungeon = hasDungeon or event.eventType == dungeonType
                        hasMeeting = hasMeeting or event.eventType == meetingType
                    else
                        loaded = false
                    end
                end
            end
        end
    end
    Audit:DebugValues(nil, "Dungeon event type", Enum and Enum.CalendarEventType and Enum.CalendarEventType.Dungeon, "Meeting event type", Enum and Enum.CalendarEventType and Enum.CalendarEventType.Meeting, "hasDungeon", hasDungeon, "hasMeeting", hasMeeting, "loaded", loaded)
    loaded=loaded and Audit.calendarReadReady==true
    local function calendarDay(d) return string.format("%04d-%02d-%02d",d.year,d.month,d.monthDay) end
    Audit:RecordAuditEvidence("calendar", {source="C_Calendar.GetClubCalendarEvents", known=loaded, fromDate=calendarDay(fromDate), throughDate=calendarDay(toDate), dungeonCount=loaded and dungeonCount or nil, meetingCount=loaded and meetingCount or nil})
    addResult("dungeon", "At least one weekly dungeon event is scheduled", loaded and hasDungeon or nil,
        loaded and (hasDungeon and "Dungeon event found" or "No dungeon event found in the next 6 weeks") or "Calendar information is unavailable or restricted. Open Calendar, then Refresh when restrictions clear.",
        {}, {
            { label = "Open Calendar", callback = openCalendar },
            { label = "Open Calendar Tool", callback = function() Audit:SelectTab("Calendar") end },
        })
    local manual = OldGodsGuildAuditDB.manual.officerMeeting
    Audit:DebugValue("manual.officerMeeting", manual)
    addResult("meeting", "Officer meeting scheduled OR Discord meeting notes pinned", hasMeeting or manual,
        hasMeeting and "Officer meeting found on calendar" or (manual and "Discord pinned notes marked checked" or "Check calendar or pinned Officer thread notes"),
        {}, {{ label = "Mark Checked", callback = function()
            OldGodsGuildAuditDB.manual.officerMeeting = true
            Audit:Refresh()
        end }})
end

local function scanDiscordReminder()
    Audit:RecordAuditEvidence("acknowledgements", {source="officerAcknowledgement", officerMeeting=OldGodsGuildAuditDB.manual.officerMeeting==true, newMemberInfo=OldGodsGuildAuditDB.manual.newMemberInfo==true, missingPromotions=OldGodsGuildAuditDB.manual.missingPromotions==true})
    local checks = {
        { key = "nmi", flag = "newMemberInfo", title = "New Member Info", url = "discordNmiUrl" },
        { key = "missingPromotions", flag = "missingPromotions", title = "Missing In Game Promotions", url = "discordPromoUrl" },
    }
    local actions, statuses = {}, {}
    local allChecked = true
    for _, check in ipairs(checks) do
        local flag, url, title = check.flag, check.url, check.title
        local checked = OldGodsGuildAuditDB.manual[flag] == true
        allChecked = allChecked and checked
        statuses[#statuses + 1] = title .. (checked and ": reviewed" or ": review Discord requests and complete required in-game updates")
        Audit:DebugValues("Discord reminder: " .. check.key, "manual." .. flag, checked, "url", OldGodsGuildAuditDB[url])
        actions[#actions + 1] = { label = title, width = 160, callback = function()
            Audit:ShowThemedDialog("OLD_GODS_AUDIT_DISCORD_CHANNEL", title, {flag = flag, urlKey = url})
        end }
    end
    addResult("nmi", "New Member Info / Missing In Game", allChecked,
        table.concat(statuses, "; "), {}, actions, 10, false)
end
local function createButton(parent, label, callback, width, name, secure)
    local button = CreateFrame("Button", name, parent, secure and "SecureActionButtonTemplate,BackdropTemplate" or "BackdropTemplate")
    button:SetSize(width or 105, 26)
    button:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER")
    button:SetFontString(text)
    button:SetText(label)
    if secure then button:HookScript("PostClick",callback); OldGodsRecruiting:Attach(button)
    else button:SetScript("OnClick", callback) end
    Audit.buttons = Audit.buttons or {}
    Audit.buttons[#Audit.buttons + 1] = button
    if OldGodsUI then OldGodsUI.Help(button, label) end
    if label:find("JSON") or label:find("Debug") or label == "Copy Last Scan Log" then
        button.oldGodsDebugOnly = true
        button:HookScript("OnShow", function(self) if not OldGodsGuildAuditDB.debugEnabled then self:Hide() end end)
    end
    return button
end
if OldGodsUI then OldGodsUI.Button = createButton end

local PURGE_ANNOUNCEMENT_MACRO = "OGGA_Announce"
local PURGE_ANNOUNCEMENT_BINDING = "CTRL-SHIFT-A"
local purgeAnnouncementBindingOwner = CreateFrame("Frame", "OldGodsGuildAuditAnnounceBindingOwner", UIParent)

local function preparePurgeAnnouncement(message)
    if InCombatLockdown and InCombatLockdown() then return false, "Leave combat before preparing the announcement macro." end
    if IsInGuild and not IsInGuild() then return false, "You are not currently in a guild." end
    if not GetMacroIndexByName or not CreateMacro or not EditMacro or not SetOverrideBindingMacro then return false, "WoW's macro or binding functions are unavailable." end
    local macroText = "/g " .. message
    local index = GetMacroIndexByName(PURGE_ANNOUNCEMENT_MACRO)
    if not index or index == 0 then
        local accountMacros = GetNumMacros and select(1, GetNumMacros()) or 0
        if MAX_ACCOUNT_MACROS and accountMacros >= MAX_ACCOUNT_MACROS then return false, "Your General Macros list is full. Free one macro slot and try again." end
        index = CreateMacro(PURGE_ANNOUNCEMENT_MACRO, "INV_MISC_QUESTIONMARK", macroText)
    else
        EditMacro(index, PURGE_ANNOUNCEMENT_MACRO, "INV_MISC_QUESTIONMARK", macroText)
    end
    index = index or GetMacroIndexByName(PURGE_ANNOUNCEMENT_MACRO)
    if not index or index == 0 then return false, "WoW did not create the announcement macro." end
    if ClearOverrideBindings then ClearOverrideBindings(purgeAnnouncementBindingOwner) end
    local assigned, bindingError = pcall(SetOverrideBindingMacro, purgeAnnouncementBindingOwner, true, PURGE_ANNOUNCEMENT_BINDING, index)
    if not assigned then return false, tostring(bindingError) end
    return true
end

local function createPurgeAnnouncementButton(parent, width)
    local message = (OldGodsChapterSettings and OldGodsChapterSettings.Policy().announcement) or PURGE_ANNOUNCEMENTS[math.random(1, #PURGE_ANNOUNCEMENTS)]
    local button = createButton(parent, "Arm Announcement", function(self)
        local prepared, reason = preparePurgeAnnouncement(message)
        if not prepared then print("Old Gods Audit: Could not prepare purge announcement. " .. tostring(reason)); return end
        self:SetText("Announcement Ready")
        print("Old Gods Audit: Purge announcement is bound to Ctrl+Shift+A. Press Ctrl+Shift+A once to post it to guild chat.")
    end, width or 155)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Prepare Purge Announcement")
        GameTooltip:AddLine(message, 1, 1, 1, true)
        GameTooltip:AddLine("Click to bind this message to Ctrl+Shift+A.", 0.65, 0.8, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local TEMP_GUILD_REMOVE_MACRO = "OGGA_Kick"
local GUILD_REMOVE_BINDING = "CTRL-SHIFT-K"
local function cleanupKeyLabel() local label=((OldGodsGuildAuditDB or {}).cleanupKey or GUILD_REMOVE_BINDING):gsub("%-", "+"); return label end
local guildRemoveBindingOwner = CreateFrame("Frame", "OldGodsGuildAuditKickBindingOwner", UIParent)
local pendingGuildRemoveReset
local pendingGuildRemoveBatch = {}
local pendingGuildRemoveBatchEnd = 0

local function validMacroMemberName(name)
    return isPublicString(name) and name ~= "" and not name:find("[%s/%c]")
end

local function buildGuildRemoveBatch(names, startIndex)
    local body, batch = "/stopmacro [combat]", {}
    local lastIndex = startIndex - 1
    for index = startIndex, #names do
        local name = names[index]
        if not validMacroMemberName(name) then return nil, nil, nil, "Invalid member name in kick queue." end
        local line = "\n/gremove " .. name
        if #body + #line > 255 then break end
        body = body .. line
        batch[#batch + 1] = name
        lastIndex = index
    end
    if #batch == 0 then return nil, nil, nil, "No complete kick command fits in the 255-byte macro." end
    return body, batch, lastIndex
end

clearGuildRemoveBinding = function(message)
    if InCombatLockdown and InCombatLockdown() then
        print("Old Gods Audit: Leave combat before cancelling the kick binding.")
        return
    end
    if ClearOverrideBindings then ClearOverrideBindings(guildRemoveBindingOwner) end
    wipe(pendingGuildRemoveBatch)
    pendingGuildRemoveBatchEnd = 0
    pendingGuildRemoveName = nil
    wipe(pendingGuildRemoveQueue)
    pendingGuildRemoveQueueIndex = 0
    local reset = pendingGuildRemoveReset
    pendingGuildRemoveReset = nil
    if reset then reset() end
    if message then print("Old Gods Audit: " .. message) end
end

if OldGodsChapterSettings then
    OldGodsChapterSettings.OnChanged = function()
        OldGodsRecruiting:Cancel("Chapter rules changed. Prepare the invite batch again.")
        if Audit.UpdateRecruitingPopulation then Audit:UpdateRecruitingPopulation() end
        if InCombatLockdown() then Audit.chapterRulesChangedInCombat = true; return end
        clearGuildRemoveBinding()
        if Audit.frame then Audit:Refresh() end
    end
end

local function prepareGuildRemoveMacro(macroText)
    if not GetMacroIndexByName or not CreateMacro or not EditMacro then return nil, "WoW's macro functions are unavailable." end
    local index = GetMacroIndexByName(TEMP_GUILD_REMOVE_MACRO)
    if not index or index == 0 then
        local accountMacros = GetNumMacros and select(1, GetNumMacros()) or 0
        if MAX_ACCOUNT_MACROS and accountMacros >= MAX_ACCOUNT_MACROS then return nil, "Your General Macros list is full. Free one macro slot and try again." end
        index = CreateMacro(TEMP_GUILD_REMOVE_MACRO, "INV_MISC_QUESTIONMARK", macroText)
    else
        EditMacro(index, TEMP_GUILD_REMOVE_MACRO, "INV_MISC_QUESTIONMARK", macroText)
    end
    index = index or GetMacroIndexByName(TEMP_GUILD_REMOVE_MACRO)
    if not index or index == 0 then return nil, "WoW did not create the temporary macro." end
    return index
end

local function bindGuildRemoveTarget(memberName, remaining)
    if OldGodsRosterTools then OldGodsRosterTools:Cancel() end
    if InCombatLockdown and InCombatLockdown() then return false, "Leave combat before preparing kick macros." end
    if not SetOverrideBindingMacro then return false, "Temporary macro bindings are unavailable." end
    local names = remaining or (#pendingGuildRemoveQueue > 0 and pendingGuildRemoveQueue or { memberName })
    local startIndex = remaining and 1 or (#pendingGuildRemoveQueue > 0 and pendingGuildRemoveQueueIndex or 1)
    local body, batch, lastIndex, reason = buildGuildRemoveBatch(names, startIndex)
    if not body then return false, reason end
    local macroIndex
    macroIndex, reason = prepareGuildRemoveMacro(body)
    if not macroIndex then return false, reason end
    if ClearOverrideBindings then ClearOverrideBindings(guildRemoveBindingOwner) end
    local assigned, bindingError = pcall(SetOverrideBindingMacro, guildRemoveBindingOwner, true, ((OldGodsGuildAuditDB or {}).cleanupKey or GUILD_REMOVE_BINDING), macroIndex)
    if not assigned then return false, tostring(bindingError) end
    pendingGuildRemoveBatch = batch
    if not remaining then pendingGuildRemoveBatchEnd = lastIndex end
    pendingGuildRemoveName = batch[1]
    return true
end

local function advanceGuildRemoveQueue()
    pendingGuildRemoveQueueIndex = pendingGuildRemoveBatchEnd + 1
    local nextName = pendingGuildRemoveQueue[pendingGuildRemoveQueueIndex]
    if not nextName then
        clearGuildRemoveBinding(("Inactive kick queue complete; temporary Ctrl+Shift+K binding cleared."):gsub("Ctrl%+Shift%+K", cleanupKeyLabel()))
        Audit:Refresh()
        return
    end
    local bound, reason = bindGuildRemoveTarget(nextName)
    if not bound then
        clearGuildRemoveBinding("Could not prepare the next inactive member: " .. tostring(reason))
        Audit:Refresh()
        return
    end
    print(string.format(("Old Gods Audit: Kick batch %d-%d/%d ready (%d members): %s. Press Ctrl+Shift+K once, then wait for the roster update."):gsub("Ctrl%+Shift%+K", cleanupKeyLabel()), pendingGuildRemoveQueueIndex, pendingGuildRemoveBatchEnd, #pendingGuildRemoveQueue, #pendingGuildRemoveBatch, table.concat(pendingGuildRemoveBatch, ", ")))
    Audit:Refresh()
end

prepareGuildRemoveQueue = function(memberNames)
    if InCombatLockdown and InCombatLockdown() then print("Old Gods Audit: Leave combat before preparing the inactive kick queue."); return end
    if not CanGuildRemove or not CanGuildRemove() then print("Old Gods Audit: You do not have permission to remove guild members."); return end
    clearGuildRemoveBinding()
    for _, memberName in ipairs(memberNames or {}) do pendingGuildRemoveQueue[#pendingGuildRemoveQueue + 1] = memberName end
    if #pendingGuildRemoveQueue == 0 then print("Old Gods Audit: No inactive members are available to queue."); return end
    pendingGuildRemoveQueueIndex = 1
    local bound, reason = bindGuildRemoveTarget(pendingGuildRemoveQueue[1])
    if not bound then clearGuildRemoveBinding("Could not start the inactive kick queue: " .. tostring(reason)); return end
    print(string.format(("Old Gods Audit: Inactive kick queue armed with %d members. First batch contains %d: %s. Ctrl+Shift+K runs this batch; wait for the roster update before pressing again. Cancel Kick Queue stops the queue."):gsub("Ctrl%+Shift%+K", cleanupKeyLabel()), #pendingGuildRemoveQueue, #pendingGuildRemoveBatch, table.concat(pendingGuildRemoveBatch, ", ")))
    Audit:Refresh()
end

local function createTwoClickGuildRemoveButton(parent, memberName, width)
    local buttonWidth = width or 160
    local prepared = false
    local prepareButton
    prepareButton = createButton(parent, "Prepare Kick", function()
        if prepared then clearGuildRemoveBinding("Temporary kick key cleared."); return end
        if InCombatLockdown and InCombatLockdown() then print("Old Gods Audit: Leave combat before preparing a guild-removal macro."); return end
        if not CanGuildRemove or not CanGuildRemove() then print("Old Gods Audit: You do not have permission to remove guild members."); return end
        clearGuildRemoveBinding()
        local bound, reason = bindGuildRemoveTarget(memberName)
        if not bound then print(("Old Gods Audit: Could not assign Ctrl+Shift+K. Run "):gsub("Ctrl%+Shift%+K", cleanupKeyLabel()) .. TEMP_GUILD_REMOVE_MACRO .. " manually. " .. tostring(reason)); return end
        prepared = true
        pendingGuildRemoveReset = function()
            prepared = false
            if prepareButton then prepareButton:SetText("Prepare Kick") end
        end
        prepareButton:SetText("Cancel Kick Key")
        print("Old Gods Audit: " .. TEMP_GUILD_REMOVE_MACRO .. (" is temporarily bound to Ctrl+Shift+K for "):gsub("Ctrl%+Shift%+K", cleanupKeyLabel()) .. memberName .. (". Press Ctrl+Shift+K once, or click Cancel Kick Key."):gsub("Ctrl%+Shift%+K", cleanupKeyLabel()))
    end, buttonWidth)
    return prepareButton
end
local THEMES = {
    dark = { window = {0.035, 0.045, 0.065, 0.98}, panel = {0.065, 0.08, 0.11, 0.98}, card = {0.085, 0.105, 0.14, 0.96}, border = {0.20, 0.28, 0.38, 1}, button = {0.10, 0.14, 0.19, 1}, accent = {0.12, 0.42, 0.78, 1}, text = {0.92, 0.95, 1, 1}, muted = {0.67, 0.73, 0.82, 1} },
    light = { window = {0.90, 0.92, 0.95, 0.99}, panel = {0.97, 0.98, 1, 0.99}, card = {1, 1, 1, 0.98}, border = {0.55, 0.62, 0.70, 1}, button = {0.80, 0.84, 0.89, 1}, accent = {0.30, 0.60, 0.92, 1}, text = {0.08, 0.10, 0.14, 1}, muted = {0.30, 0.35, 0.42, 1} },
    purple = { window = {0.094118, 0.062745, 0.156863, 0.98}, panel = {0.129412, 0.086275, 0.215686, 0.98}, card = {0.172549, 0.109804, 0.282353, 0.96}, border = {0.533333, 0.345098, 0.784314, 1}, button = {0.219608, 0.156863, 0.407843, 1}, accent = {0.345098, 0.156863, 0.533333, 1}, text = {0.941176, 0.909804, 0.988235, 1}, muted = {0.768627, 0.658824, 0.909804, 1} },
    hotPink = { window = {0.22, 0.015, 0.12, 1}, panel = {0.34, 0.02, 0.19, 1}, card = {0.27, 0.015, 0.15, 1}, border = {1, 0.15, 0.60, 1}, button = {0.50, 0.015, 0.27, 1}, accent = {0.65, 0.02, 0.34, 1}, text = {1, 0.94, 0.98, 1}, muted = {1, 0.70, 0.85, 1} },
    hotDogStand = { window = {1, 0.05, 0.02, 1}, panel = {1, 0.90, 0, 1}, card = {1, 0.97, 0.20, 1}, border = {0, 0, 0, 1}, button = {1, 0.80, 0, 1}, accent = {1, 0.35, 0, 1}, text = {0, 0, 0, 1}, muted = {0.25, 0.10, 0, 1} },
}

local THEME_ORDER = { "dark", "light", "purple", "hotPink", "hotDogStand" }
local THEME_NAMES = { dark = "Dark", light = "Light", purple = "Crown Purple", hotPink = "Hot Pink", hotDogStand = "Hot Dog Stand" }

function Audit:CycleTheme()
    local current = THEMES[OldGodsGuildAuditDB.theme] and OldGodsGuildAuditDB.theme or "dark"
    for i, name in ipairs(THEME_ORDER) do
        if name == current then
            OldGodsGuildAuditDB.theme = THEME_ORDER[(i % #THEME_ORDER) + 1]
            break
        end
    end
    self:ApplyTheme()
end

function Audit:ApplyCompactTheme()
    local frame = self.compactRecruiting
    if not frame then return end
    local colors = THEMES[OldGodsGuildAuditDB.theme] or THEMES.dark
    frame:SetBackdropColor(unpack(colors.window))
    frame:SetBackdropBorderColor(unpack(colors.border))
    for _, name in ipairs({"Bg", "Background", "TitleBg", "TitleBackground", "NineSlice", "Inset", "TopTileStreaks"}) do
        if frame[name] then frame[name]:SetAlpha(0) end
    end
    for _, text in ipairs({frame.TitleText, frame.population, frame.populationDetail, frame.keys, frame.status}) do
        text:SetTextColor(unpack(colors.text))
    end
    for _, line in ipairs(frame.lines) do line:SetTextColor(unpack(colors.text)) end
    for _, button in ipairs({frame.search, frame.invite, frame.expand, frame.candidatePrevious, frame.candidateNext}) do
        button:SetBackdropColor(unpack(colors.button))
        button:SetBackdropBorderColor(unpack(colors.border))
        button:GetFontString():SetTextColor(unpack(colors.text))
    end
end

-- Only addon-owned windows are registered here; Blizzard's shared popups are untouched.
OldGodsTheme = { windows = setmetatable({}, { __mode = "k" }) }
function OldGodsTheme.Colors()
    local colors=THEMES[(OldGodsGuildAuditDB or {}).theme] or THEMES.dark
    local danger={dark={1,0.40,0.42,1},light={0.65,0.04,0.08,1},purple={1,0.55,0.70,1},hotPink={1,0.60,0.58,1},hotDogStand={0.65,0.03,0.03,1}}
    colors.danger=danger[(OldGodsGuildAuditDB or {}).theme] or danger.dark
    return colors
end
function OldGodsTheme.ApplyWindow(window)
    local colors = THEMES[OldGodsGuildAuditDB.theme] or THEMES.dark
    -- GetChildren returns one Lua value per child. Large, long-lived windows
    -- can overflow the VM's return-value stack before a table is constructed.
    -- Snapshot one frame at a time, also excluding anything styling creates.
    local children = {}
    local frame = EnumerateFrames()
    while frame do
        if not frame.IsForbidden or not frame:IsForbidden() then
            local parent = frame:GetParent()
            if parent then
                children[parent] = children[parent] or {}
                local siblings = children[parent]
                siblings[#siblings + 1] = frame
            end
        end
        frame = EnumerateFrames(frame)
    end
    local function backdrop(widget, color)
        if not widget.SetBackdrop then Mixin(widget, BackdropTemplateMixin) end
        widget:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
        widget:SetBackdropColor(unpack(color))
        widget:SetBackdropBorderColor(unpack(colors.border))
    end
    local function style(widget)
        if widget.oldGodsStatusIndicator then return end
        if widget.oldGodsTextOnly then
            widget:GetFontString():SetTextColor(unpack(colors.muted))
            return
        end
        local isButton = widget:IsObjectType("Button") and not widget:IsObjectType("CheckButton")
        local isEdit = widget:IsObjectType("EditBox")
        local isCheck = widget:IsObjectType("CheckButton")
        if widget:IsObjectType("Slider") then
            backdrop(widget,colors.card)
            local thumb=widget.GetThumbTexture and widget:GetThumbTexture()
            for _,region in ipairs({widget:GetRegions()}) do if region:IsObjectType("Texture") and region~=thumb then region:SetAlpha(0) end end
            if thumb then thumb:SetColorTexture(unpack(colors.border)); thumb:SetAlpha(1) end
        end
        if widget==window.CloseButton and widget.SetFontString then
            local label=widget:GetFontString()
            if not label then label=widget:CreateFontString(nil,"OVERLAY","GameFontNormal"); label:SetPoint("CENTER"); widget:SetFontString(label) end
            widget:SetText("×")
        end
        if isButton or isEdit or isCheck then
            -- Remove the native skin while retaining highlight and disabled state feedback.
            if not widget.oldGodsSkinRemoved then
                if not widget.GetBackdrop or not widget:GetBackdrop() then
                    for _, region in ipairs({widget:GetRegions()}) do
                        if region:IsObjectType("Texture") and not region.oldGodsAsset then region:SetAlpha(0) end
                    end
                end
                widget.oldGodsSkinRemoved = true
            end
            backdrop(widget, isEdit and colors.card or colors.button)
            if OldGodsUI and widget.HookScript and not widget.oldGodsHelpHooked then
                local label=widget.GetText and widget:GetText()
                if label and label~="" then OldGodsUI.Help(widget,label) end
            end
            if isCheck then
                widget:SetCheckedTexture("Interface/Buttons/WHITE8X8")
                widget:GetCheckedTexture():SetVertexColor(unpack(colors.accent or {0.22,0.58,0.96,1}))
            elseif isButton and not widget.oldGodsIcon then
                widget:SetHighlightTexture("Interface/Buttons/WHITE8X8", "BLEND")
                widget:GetHighlightTexture():SetVertexColor(1,1,1)
                widget:GetHighlightTexture():SetAlpha(0.12)
                widget:SetDisabledTexture("Interface/Buttons/WHITE8X8")
                widget:GetDisabledTexture():SetVertexColor(0,0,0)
                widget:GetDisabledTexture():SetAlpha(0.4)
            elseif isEdit then
                widget:SetTextColor(unpack(colors.text))
            end
        end
        for _, region in ipairs({widget:GetRegions()}) do
            if region:IsObjectType("FontString") then region:SetTextColor(unpack(colors.text)) end
        end
        if widget.oldGodsIcon then widget:RefreshIcon(OldGodsTheme.Colors()) end
        if widget.oldGodsRosterRow then
            OldGodsRosterTools:StyleRow(widget,false)
            if widget.lines[3] then widget.lines[3]:SetText(Audit:ClassColoredRosterName(widget.oldGodsRosterMember)) end
        end
    end
    for _, name in ipairs({"Bg", "Background", "TitleBg", "TitleBackground", "NineSlice", "Inset", "TopTileStreaks"}) do
        if window[name] then window[name]:SetAlpha(0) end
    end
    backdrop(window, colors.window)
    local pending, visited = {window}, {}
    while #pending > 0 do
        local widget = table.remove(pending)
        if not visited[widget] then
            visited[widget] = true
            style(widget)
            for _, child in ipairs(children[widget] or {}) do pending[#pending + 1] = child end
        end
    end
end
function OldGodsTheme.RegisterWindow(window)
    OldGodsTheme.windows[window] = true
    OldGodsTheme.ApplyWindow(window)
end

function Audit:ShowThemedDialog(key, title, data)
    local definition = StaticPopupDialogs[key]
    self.dialogs = self.dialogs or {}
    local window = self.dialogs[key]
    if not window then
        window = CreateFrame("Frame", key .. "Window", UIParent, "BasicFrameTemplateWithInset,BackdropTemplate")
        self.dialogs[key] = window
        window:SetSize(500, 240); window:SetPoint("CENTER"); window:SetFrameStrata("FULLSCREEN_DIALOG")
        window:SetClampedToScreen(true); window:SetMovable(true); window:EnableMouse(true)
        window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart", window.StartMoving)
        window:SetScript("OnDragStop", window.StopMovingOrSizing)
        window.body = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        window.body:SetPoint("TOPLEFT", 20, -42); window.body:SetWidth(460); window.body:SetJustifyH("LEFT")
        window.EditBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
        window.EditBox:SetPoint("TOPLEFT", 20, -143); window.EditBox:SetSize(460, 30)
        window.EditBox:SetAutoFocus(false); window.EditBox:SetMaxLetters(0)
        window.EditBox:SetTextInsets(6,6,0,0)
        window.EditBox:SetScript("OnEscapePressed", function() window:Hide() end)
        window:SetScript("OnHide", function() window.EditBox:ClearFocus() end)
        window.accept = createButton(window, definition.button1, function()
            local currentData = window.data
            window:Hide()
            if definition.OnAccept then definition.OnAccept(window, currentData) end
        end, 140)
        window.accept:SetPoint("BOTTOMRIGHT", -20, 18)
        if definition.button2 then
            window.cancel = createButton(window, definition.button2, function() window:Hide() end, 110)
            window.cancel:SetPoint("RIGHT", window.accept, "LEFT", -10, 0)
        end
        UISpecialFrames[#UISpecialFrames + 1] = key .. "Window"
    end
    window.data = data
    window.TitleText:SetText(title or "Copy text")
    window.body:SetText(title and string.format(definition.text, title) or definition.text)
    window:Show()
    definition.OnShow(window, data)
    OldGodsTheme.RegisterWindow(window)
end

function Audit:ApplyTheme()
    local themeName = THEMES[OldGodsGuildAuditDB.theme] and OldGodsGuildAuditDB.theme or "dark"
    local colors = THEMES[themeName]
    if self.frame.Bg then self.frame.Bg:SetColorTexture(unpack(colors.window)) end
    if self.frame.NineSlice then self.frame.NineSlice:SetAlpha(0) end
    if self.frame.TopTileStreaks then self.frame.TopTileStreaks:SetAlpha(0) end
    if self.frame.Inset then self.frame.Inset:SetAlpha(0) end
    if self.frame.PortraitContainer then self.frame.PortraitContainer:SetAlpha(0) end
    self.header:SetBackdropColor(unpack(colors.panel))
    self.header:SetBackdropBorderColor(unpack(colors.border))
    self.contentBackground:SetBackdropColor(unpack(colors.panel))
    self.contentBackground:SetBackdropBorderColor(unpack(colors.border))
    self.title:SetTextColor(unpack(colors.text))
    self.score:SetTextColor(unpack(colors.muted))
    for _, button in ipairs(self.buttons or {}) do
        button:SetBackdropColor(unpack(colors.button))
        button:SetBackdropBorderColor(unpack(colors.border))
        button:GetFontString():SetTextColor(unpack(colors.text))
    end
    for _, page in ipairs(self.pages or {}) do
        page:SetBackdropColor(unpack(colors.card))
        page:SetBackdropBorderColor(unpack(colors.border))
        page.heading:SetTextColor(unpack(colors.text))
        page.body:SetTextColor(unpack(colors.muted))
        for _, text in ipairs(page.extraTexts or {}) do text:SetTextColor(unpack(colors.text)) end
    end
    if self.tabButtons and self.currentTab and self.tabButtons[self.currentTab] then
        self.tabButtons[self.currentTab]:SetBackdropColor(unpack(colors.accent or {0.22, 0.58, 0.96, 1}))
    end
    for _, row in ipairs(rows) do
        row:SetBackdropColor(unpack(colors.card))
        row:SetBackdropBorderColor(unpack(colors.border))
        row.title:SetTextColor(unpack(colors.text))
        row.summary:SetTextColor(unpack(colors.muted))
        for _, line in ipairs(row.lines or {}) do line:SetTextColor(unpack(colors.text)) end
    end
    if self.themeButton.RefreshLabel then self.themeButton:RefreshLabel() end
    self:ApplyCompactTheme()
    for window in pairs(OldGodsTheme.windows) do OldGodsTheme.ApplyWindow(window) end
    if self.debugButton then self.debugButton:SetText("π") end
    for _, button in ipairs(self.buttons or {}) do
        if button.oldGodsDebugOnly then
            local visible=OldGodsGuildAuditDB.debugEnabled == true
            if button.oldGodsHelpKey=="Copy Calendar JSON" then visible=visible and self.calendarPage and self.calendarPage.formVisible end
            if button.oldGodsHelpKey=="Copy Last Scan Log" then visible=visible and self.recruitingPage and self.recruitingPage.currentSubtab=="Search" end
            button:SetShown(visible)
        end
    end
    if self.frame then OldGodsTheme.ApplyWindow(self.frame) end
    if self.tabButtons and self.tabButtons[self.currentTab] then self.tabButtons[self.currentTab]:SetBackdropColor(unpack(colors.accent or {0.22,0.58,0.96,1})) end
    if self.recruitingPage and self.recruitingPage.realmResetButton then
        self.recruitingPage.realmResetButton:SetShown(OldGodsGuildAuditDB.debugEnabled and self.recruitingPage.currentSubtab == "Search")
    end
end

local AUDIT_SECTION_MAX_HEIGHT = 480

function Audit:Render()
    for _, row in ipairs(rows) do row:Hide() end

    wipe(rows)
    local canvas = self.canvas
    local y = -8
    local passedPoints = 0
    for _, result in ipairs(results) do if result.passed then passedPoints = passedPoints + result.points end end
    self.score:SetText(string.format("Score: %.1f%%", auditScore()))

    for _, result in ipairs(results) do
        local row = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
        row:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        rows[#rows + 1] = row
        row:SetPoint("TOPLEFT", 6, y)
        row:SetPoint("RIGHT", -10, 0)
        -- Keep the border on the bounded viewport, never on tall list content.
        local content = CreateFrame("Frame", nil, row)
        content:SetAllPoints(row)
        local status = result.passed == true and "|cff35d06fPASS|r" or (result.passed == false and "|cffff5656FIX|r" or "|cffffc247CHECK|r")
        local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetWidth(430)
        title:SetJustifyH("LEFT")
        title:SetText(string.format("• %s  [%s]", result.title, status))
        row.title = title
        local summary = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -5)
        summary:SetWidth(430)
        summary:SetJustifyH("LEFT")
        summary:SetText(result.summary or "")
        row.summary = summary
        row.lines = {}
        local innerY = -42
        for _, item in ipairs(result.items) do
            local line = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetPoint("TOPLEFT", 32, innerY)
            line:SetWidth(410)
            line:SetJustifyH("LEFT")
            line:SetText("- " .. item.text)
            row.lines[#row.lines + 1] = line
            local x = 450
            for _, action in ipairs(item.actions or {}) do
                if not action.debugOnly or OldGodsGuildAuditDB.debugEnabled then
                    local button
                    if action.secureGuildRemove then
                        button = createTwoClickGuildRemoveButton(content, action.secureGuildRemove, 160)
                        x = math.max(365, x - 85)
                    else
                        button = createButton(content, action.label, action.callback, 88)
                    end
                    button:SetPoint("TOPLEFT", x, innerY + 5)
                    x = x + (action.secureGuildRemove and 164 or 92)
                end
            end
            innerY = innerY - 27
        end
        if result.passed == nil and result.allowManual then
            result.actions[#result.actions + 1] = {
                label = "Mark Pass",
                callback = function()
                    OldGodsGuildAuditDB.manualPasses[result.key] = true
                    Audit:Refresh()
                end,
            }
        elseif result.manualOverride then
            result.actions[#result.actions + 1] = {
                label = "Undo Manual",
                callback = function()
                    OldGodsGuildAuditDB.manualPasses[result.key] = nil
                    Audit:Refresh()
                end,
            }
        end
        local actionRows = 0
        if #result.actions > 0 then
            local columns = 3
            local visibleActionIndex = 0
            for _, action in ipairs(result.actions) do
                if not action.debugOnly or OldGodsGuildAuditDB.debugEnabled then
                    visibleActionIndex = visibleActionIndex + 1
                    local column = (visibleActionIndex - 1) % columns
                    local actionRow = math.floor((visibleActionIndex - 1) / columns)
                    local button
                    if action.securePurgeAnnouncement then
                        button = createPurgeAnnouncementButton(content, action.width or 155)
                    else
                        button = createButton(content, action.label, action.callback, action.width or 125)
                    end
                    button:SetPoint("TOPRIGHT", -14 - (column * 175), -10 - (actionRow * 30))
                    actionRows = math.max(actionRows, actionRow + 1)
                end
            end
        end
        local actionHeight = actionRows > 0 and (18 + (actionRows * 30)) or 0
        local height = math.max(54, -innerY + 8, actionHeight)
        local visibleHeight = math.min(height, AUDIT_SECTION_MAX_HEIGHT)
        row:SetHeight(visibleHeight)
        if height > AUDIT_SECTION_MAX_HEIGHT then
            local scroll = CreateFrame("ScrollFrame", nil, row, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 0, -2)
            scroll:SetPoint("BOTTOMRIGHT", -28, 2)
            content:SetParent(scroll)
            content:ClearAllPoints()
            content:SetSize(canvas:GetWidth() - 16 - 28, height)
            scroll:SetScrollChild(content)
        end
        y = y - visibleHeight - 7
    end
    canvas:SetHeight(math.max(-y, 530))
    self:ApplyTheme()
end

function Audit:BeginAuditEvidence()
    local guildName, _, rank, guildRealm = GetGuildInfo("player")
    local policy=OldGodsChapterSettings.Policy()
    self.auditEvidence = {policy={minimum=policy.minimum or 980, officerPrefix=policy.officerPrefix or "Disc:", donationsTab=policy.donationsTab or 1, revision=policy.revision or 0}, schemaVersion=1, guildName=guildName, guildRealm=recruitingGuildRealm() or guildRealm or GetNormalizedRealmName() or GetRealmName(),
        gameVersion=OldGodsGameProfile or "retail", capturedAt=GetServerTime(), capturedBy=OldGodsChapterSettings.CharacterKey(), capturedRank=rank}
end
function Audit:RecordAuditEvidence(section, data)
    if self.auditEvidence then self.auditEvidence[section]=data end
end
function Audit:ScheduleAuditCapture()
    if self.auditCaptureScheduled then return end
    self.auditCaptureScheduled=true
    C_Timer.After(1,function()
        self.auditCaptureScheduled=nil
        if OldGodsGuildAuditDB then Audit:CaptureCurrentAudit() end
    end)
end
function Audit:RequestAuditSources()
    if not self:CanAccessAudit() then return end
    if not InCombatLockdown() then
        self.auditSourcesRequested=true
        if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
        if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        if C_ClubFinder and C_ClubFinder.RequestPostingInformationFromClubId and C_Club and C_Club.GetGuildClubId then
            local clubId=C_Club.GetGuildClubId();if clubId then pcall(C_ClubFinder.RequestPostingInformationFromClubId,clubId) end
        end
        if C_ClubFinder and C_ClubFinder.RequestApplicantList then
            pcall(C_ClubFinder.RequestApplicantList,Enum and Enum.ClubFinderRequestType and Enum.ClubFinderRequestType.Guild or 1)
        end
    end
    self:ScheduleAuditCapture()
end

function Audit:BuildReport()
    local lines = {}
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    for _, result in ipairs(results) do
        local status = result.passed == true and "PASS" or (result.passed == false and "FIX" or "CHECK")
        lines[#lines + 1] = string.format("[%s] %s - %s", status, result.title, result.summary or "")
    end
    local reportText = string.format("Old Gods Guild Audit - %s\nScore: %.1f%%\n\n%s",
        timestamp, auditScore(), table.concat(lines, "\n"))
    local guildName, _, _, guildRealm = GetGuildInfo("player")
    return { timestamp=timestamp, text=reportText, capturedAt=GetServerTime(), guildName=guildName,
        guildRealm=recruitingGuildRealm() or guildRealm or GetNormalizedRealmName() or GetRealmName(), gameVersion=OldGodsGameProfile or "retail" }
end

function Audit:SaveReport()
    local report = self:BuildReport()
    table.insert(OldGodsGuildAuditDB.reports, 1, report)
    while #OldGodsGuildAuditDB.reports > 50 do table.remove(OldGodsGuildAuditDB.reports) end
    print("Old Gods Audit: Report saved to SavedVariables at " .. report.timestamp .. ". It will be written to disk on logout or /reload.")
end

function Audit:SelectTab(tabName)
    self:UpdateDebugVisibility()
    if tabName ~= "Special" then self:ClearSpazzyBinding() end
    if tabName == "Debug" and not OldGodsGuildAuditDB.debugEnabled then tabName = "Audit" end

    if tabName == "Audit" and not self:CanAccessAudit() then tabName = "Recruiting" end
    if self.chapterPage then self.chapterPage:SetShown(tabName == "Chapter"); if tabName == "Chapter" then self.chapterPage.Load() end end
    self.currentTab = tabName
    self.scroll:SetShown(tabName == "Audit")
    self.recruitingPage:SetShown(tabName == "Recruiting")
    self.calendarPage:SetShown(tabName == "Calendar")
    self.bankPage:SetShown(tabName == "Bank")
    self.rosterPage:SetShown(tabName == "Roster")
    self.eventLogPage:SetShown(tabName == "Event Log")
    self.feedbackPage:SetShown(tabName == "Feedback")
    if self.debugPage then self.debugPage:SetShown(tabName == "Debug") end
    if self.specialPage then self.specialPage:SetShown(tabName == "Special") end
    for name, button in pairs(self.tabButtons) do
        button:SetEnabled(name ~= tabName and (name ~= "Audit" or self:CanAccessAudit()))
    end
    if tabName == "Audit" then
        self:Refresh()
    elseif tabName == "Debug" then
        self:RenderDebugPage()
        self:ApplyTheme()
    elseif tabName == "Roster" then
        self:RenderRosterPage()
        self:ApplyTheme()
    elseif tabName == "Event Log" then
        self:RenderRosterEventPage()
        self:ApplyTheme()
    else
        self:ApplyTheme()
    end
end
function Audit:BuildFeedbackPage(page)
    page.extraTexts = page.extraTexts or {}
    page.body:SetText("Send a bug report, suggestion, or feature request through the desktop companion.")
    local types = { "Bug", "Feedback", "Feature request" }
    local typeIndex = 1
    local typeButton = OldGodsUI.Dropdown(page, "Feedback type", {{"Bug","Bug"},{"Feedback","Feedback"},{"Feature request","Feature request"}}, function() return page.feedbackType or "Bug" end, function(value) page.feedbackType=value end, 240)
    typeButton:SetPoint("TOPLEFT", 24, -92)
    page.feedbackType = types[typeIndex]
    local titleLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal"); titleLabel:SetPoint("TOPLEFT", 24, -138); titleLabel:SetText("Title")
    local title = CreateFrame("EditBox", nil, page, "InputBoxTemplate"); title:SetSize(780, 28); title:SetPoint("TOPLEFT", 24, -158); title:SetAutoFocus(false); title:SetMaxLetters(160); title:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local descriptionLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal"); descriptionLabel:SetPoint("TOPLEFT", 24, -202); descriptionLabel:SetText("What happened or what would you like to suggest?")
    local description = CreateFrame("EditBox", nil, page, "InputBoxTemplate"); description:SetSize(780, 110); description:SetPoint("TOPLEFT", 24, -222); description:SetAutoFocus(false); description:SetMultiLine(true); description:SetMaxLetters(4000); description:SetFontObject("ChatFontNormal"); description:SetTextInsets(6, 6, 6, 6); description:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local stepsLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormal"); stepsLabel:SetPoint("TOPLEFT", 24, -346); stepsLabel:SetText("Steps to reproduce (optional)")
    local steps = CreateFrame("EditBox", nil, page, "InputBoxTemplate"); steps:SetSize(780, 82); steps:SetPoint("TOPLEFT", 24, -366); steps:SetAutoFocus(false); steps:SetMultiLine(true); steps:SetMaxLetters(3000); steps:SetFontObject("ChatFontNormal"); steps:SetTextInsets(6, 6, 6, 6); steps:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    page.feedbackInputs={title,description,steps}
    local status = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); status:SetPoint("TOPLEFT", 170, -470); status:SetWidth(635); status:SetJustifyH("LEFT"); status:SetText("Feedback is sent after WoW writes SavedVariables and the companion uploads the next snapshot.")
    local submit = createButton(page, "Queue feedback", function()
        local feedbackTitle, feedbackDescription = trim(title:GetText() or ""), trim(description:GetText() or "")
        if feedbackTitle == "" or feedbackDescription == "" then status:SetText("Enter both a title and description."); return end
        local player = recruitingCharacterIdentity()
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version")) or "unknown"
        local createdAt = GetServerTime()
        local sourceId = table.concat({ player, tostring(createdAt), tostring(math.random(100000, 999999)) }, "|")
        local submissions = OldGodsGuildAuditDB.feedback.submissions
        submissions[#submissions + 1] = { schemaVersion = 1, id = sourceId, type = page.feedbackType, title = feedbackTitle, description = feedbackDescription, stepsToReproduce = trim(steps:GetText() or ""), applicationVersion = version, submittedBy = player, createdAt = createdAt, syncStatus = "pendingUpload" }
        while #submissions > 100 do table.remove(submissions, 1) end
        title:SetText(""); description:SetText(""); steps:SetText("")
        status:SetText("Feedback queued. Use /reload or log out so WoW writes SavedVariables, then let the companion sync.")
        print("Old Gods Audit: Feedback queued. Use /reload or log out, then let the desktop companion sync it.")
    end, 135)
    OldGodsUI.Help(title,"Feedback title"); OldGodsUI.Help(description,"Feedback description"); OldGodsUI.Help(steps,"Reproduction steps")
    submit:SetPoint("TOPLEFT", 24, -462)
    page.extraTexts[#page.extraTexts + 1] = titleLabel; page.extraTexts[#page.extraTexts + 1] = descriptionLabel; page.extraTexts[#page.extraTexts + 1] = stepsLabel; page.extraTexts[#page.extraTexts + 1] = status
end
function Audit:Refresh()
    self:UpdateDebugVisibility()
    if not self:CanAccessAudit() then
        wipe(results)
        for _, row in ipairs(rows) do row:Hide() end
        return
    end
    self:BeginDebugSnapshot()
    wipe(results)
    local inGuild = IsInGuild()
    self:DebugValues("Audit start", "IsInGuild", inGuild)
    if not inGuild then
        addResult("guild", "Guild data", false, "This character is not in a guild")
        self:Render()
        self:FinishDebugSnapshot()
        return
    end
    C_GuildInfo.GuildRoster()
    self:BeginAuditEvidence()
    scanRoster()
    scanMotd()
    scanRecruitment()
    scanApplications()
    scanBank()
    scanCalendar()
    scanDiscordReminder()
    OldGodsGuildAuditDB.currentAudit = self:BuildReport()
    OldGodsGuildAuditDB.auditData = self.auditEvidence
    self:Render()
    self:FinishDebugSnapshot()
end

function Audit:CaptureCurrentAudit()
    -- Never carry another character/guild's account-wide result into this upload.
    OldGodsGuildAuditDB.currentAudit = {}
    OldGodsGuildAuditDB.auditData = {}
    self.auditEvidence = nil
    if not self:CanAccessAudit() or not IsInGuild() or (GetNumGuildMembers() or 0)<1 then return end
    self:BeginDebugSnapshot()
    wipe(results)
    self.capturingForUpload = true
    self:BeginAuditEvidence()
    self:CaptureRosterSnapshot(true)
    scanRoster()
    scanMotd()
    scanRecruitment()
    scanApplications()
    scanBank()
    scanCalendar()
    scanDiscordReminder()
    self.capturingForUpload = nil
    OldGodsGuildAuditDB.currentAudit = self:BuildReport()
    OldGodsGuildAuditDB.auditData = self.auditEvidence
    self:FinishDebugSnapshot()
end

local function normalizeZoneName(name)
    local normalized = trim(name or ""):lower()
    normalized = normalized:gsub("%s+", " ")
    return normalized
end

local function getDefaultQuietZoneNames()
    if defaultQuietZoneNames then return defaultQuietZoneNames end
    defaultQuietZoneNames = {}
    for _, areaID in ipairs(DEFAULT_QUIET_ZONE_IDS) do
        local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)
        if name and name ~= "" then defaultQuietZoneNames[normalizeZoneName(name)] = name end
    end
    return defaultQuietZoneNames
end

local function isQuietZone(area)
    if not area or area == "" then return false end
    local lookup = normalizeZoneName(area)
    if OldGodsChapterSettings and OldGodsChapterSettings.IsQuietZoneRemoved(area) then return false end
    if getDefaultQuietZoneNames()[lookup] then return true end
    for _, customName in ipairs(OldGodsChapterSettings and OldGodsChapterSettings.QuietZones() or OldGodsGuildAuditDB.recruiting.customQuietZones) do
        if normalizeZoneName(customName) == lookup then return true end
    end
    return false
end

-- Recheck changing rules at display/invite time, not just when /who returns.
OldGodsFeedback.RecruitingBlockReason = function(info)
    if isQuietZone(info.area) then return "In a protected quiet zone" end
    if trim(info.fullGuildName)~="" then return "Already in a guild" end
    local key=normalizeRecruitName(info.fullName)
    if sessionInvitedPlayers[key] then return "Already invited this session" end
    local stamp=(OldGodsGuildAuditDB.recruiting.inviteHistory or {})[key]
    if stamp and time()-stamp < (tonumber(OldGodsGuildAuditDB.recruiting.antiSpamDays) or 7)*86400 then return "Invited within the seven-day anti-spam window" end
end

-- Share the existing built-in/custom zone rules with applicant notifications.
OldGodsChapterSettings.IsPlayerInQuietZone = function()
    return isQuietZone(GetRealZoneText and GetRealZoneText())
        or isQuietZone(GetZoneText and GetZoneText())
        or isQuietZone(GetSubZoneText and GetSubZoneText())
end

function Audit:PurgeQuietZoneCandidates()
    local removed = 0
    for index = #recruitingCandidates, 1, -1 do
        if isQuietZone(recruitingCandidates[index].area) then
            table.remove(recruitingCandidates, index)
            removed = removed + 1
        end
    end

    return removed
end

-- Status details stay live while hovered, including the /who throttle countdown.
function Audit:UpdateRecruitingStatus()
    local page=self.recruitingPage
    if not page or not page.statusIndicator then return end
    local indicator=page.statusIndicator
    local exhausted=self.recruitingSearchFinished == true and not whoScanActive
    indicator.dot:SetVertexColor(exhausted and 1 or 0.2,exhausted and 0.25 or 0.85,0.25,1)
    local heading=exhausted and "Search finished — no searches remaining" or "More searches available"
    local phase="Click Search to find candidates."
    if whoScanActive then
        if whoRequestPending then phase="Waiting for results: "..(whoCurrentSearch and whoCurrentSearch.query or "current search")
        elseif whoContinueReady then phase="Click Continue Search to search the next group."
        else phase=string.format("Continue Search unlocks in %d seconds.",math.max(0,math.ceil((whoContinueAt or GetTime())-GetTime()))) end
    elseif exhausted then phase="All queued searches have been attempted. Click Search to start again." end
    local nextCandidate=OldGodsRecruiting.batch and OldGodsRecruiting.batch[1] or self:NextRecruitingCandidate()
    indicator.tooltipTitle=heading
    indicator.tooltipText=table.concat({whoScanLabel~="" and whoScanLabel or "All zones",phase,
        string.format("%d candidates | %d searches completed | %d queued | %d timed out | %d failed",#recruitingCandidates,whoQueriesCompleted, #whoSearchQueue,whoQueriesTimedOut,whoQueriesFailed),
        string.format("Quiet-zone filtering required | Session invitations: %d | Seven-day history: %d",sessionInviteCount,getInviteHistoryCount()),
        nextCandidate and ("Next invite: "..nextCandidate.fullName) or "Next invite: none",
        pendingRecruitingWarning or "",self.recruitingNotice or "",OldGodsRecruiting.message or "",
        "Candidates come from this character's /who results. Quiet zones, bans and invitation history still apply."},"\n")
    if indicator.tooltipShown and GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(indicator)) then
        GameTooltip:SetOwner(indicator,"ANCHOR_RIGHT"); GameTooltip:SetText(indicator.tooltipTitle)
        GameTooltip:AddLine(indicator.tooltipText,1,1,1,true); GameTooltip:Show()
    end
end

function Audit:RenderRecruitingCandidates()
    OldGodsRecruiting:Refresh()
    self:UpdateRecruitingPopulation()
    local visible = self:VisibleRecruitingCandidates()
    self:RenderCompactRecruiting(visible)
    local page = self.recruitingPage
    if not page then return end
    if page.IsVisible and not page:IsVisible() then return end
    for _, line in ipairs(page.candidateLines) do line:Hide() end
    page.candidateRows = page.candidateRows or {}
    if page.allZonesButton then
        local remaining=math.max(0,math.ceil((whoContinueAt or GetTime())-GetTime()))
        page.allZonesButton:SetText(not whoScanActive and "Search" or (not whoRequestPending and not whoContinueReady and remaining>0) and string.format("Continue Search (%ds)",remaining) or "Continue Search")
        page.allZonesButton:SetEnabled(not InCombatLockdown() and (not whoScanActive or (not whoRequestPending and whoContinueReady)))
    end
    if page.inviteButton then page.inviteButton:SetEnabled(not InCombatLockdown() and self:NextRecruitingCandidate()~=nil) end
    if page.realmOverrideButton then page.realmOverrideButton:SetShown(pendingRecruitingScan~=nil) end
    if page.realmResetButton then page.realmResetButton:SetShown(OldGodsGuildAuditDB.debugEnabled == true); page.realmResetButton:SetEnabled(not whoScanActive) end
    self:UpdateRecruitingStatus()
    local content, candidateY = page.candidateContent or page, 0
    local colors = THEMES[OldGodsGuildAuditDB.theme] or THEMES.dark
    for slot, candidate in ipairs(self:RecruitingPageSlice(visible,page)) do
        local row=page.candidateRows[slot]
        if not row then
            row={}
            row.line=content:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            row.line:SetJustifyH("LEFT")
            row.quiet=createButton(content,"Report Zone",function() if row.candidate then Audit:AddQuietZone(row.candidate.area) end end,105)
            page.candidateRows[slot]=row
            for _,widget in ipairs({row.line,row.quiet}) do page.candidateLines[#page.candidateLines+1]=widget end
            page.extraTexts[#page.extraTexts+1]=row.line
        end
        row.candidate=candidate
        row.line:ClearAllPoints(); row.line:SetPoint("TOPLEFT",8,-6-candidateY)
        row.line:SetWidth(math.max(400,content:GetWidth()-130))
        row.line:SetHeight(20); row.line:SetMaxLines(1); row.line:SetWordWrap(false)
        row.line:SetText(string.format("%d. %s - Level %d %s - %s",(page.candidatePage-1)*50+slot,candidate.fullName,candidate.level or 0,candidate.classStr or "Unknown",candidate.area or "Unknown"))
        row.line:SetTextColor(unpack(colors.text)); row.line:Show()
        row.quiet:ClearAllPoints(); row.quiet:SetPoint("TOPRIGHT",-8,-2-candidateY)
        row.quiet:SetShown(candidate.area~=nil and candidate.area~="")
        for _,button in ipairs({row.quiet}) do
            button:SetBackdropColor(unpack(colors.button)); button:SetBackdropBorderColor(unpack(colors.border)); button:GetFontString():SetTextColor(unpack(colors.text))
        end
        candidateY=candidateY+28
    end
    if page.candidateContent then page.candidateContent:SetHeight(math.max(1,candidateY)) end
end

function Audit:RecruitingPageSlice(visible,frame)
    local pages=math.max(1,math.ceil(#visible/50))
    frame.candidatePage=math.max(1,math.min(frame.candidatePage or 1,pages))
    if frame.candidatePrevious then frame.candidatePrevious:SetEnabled(frame.candidatePage>1) end
    if frame.candidateNext then frame.candidateNext:SetEnabled(frame.candidatePage<pages) end
    if frame.candidatePageLabel then frame.candidatePageLabel:SetText(string.format("Page %d/%d",frame.candidatePage,pages)) end
    local shown={}
    for i=(frame.candidatePage-1)*50+1,math.min(frame.candidatePage*50,#visible) do shown[#shown+1]=visible[i] end
    return shown
end

-- The API call remains on the click; coalesce only the visual refresh.
function Audit:ScheduleRecruitingRender()
    if self.recruitingRenderPending then return end
    self.recruitingRenderPending=true
    C_Timer.After(0,function() self.recruitingRenderPending=nil; self:RenderRecruitingCandidates() end)
end

function Audit:VisibleRecruitingCandidates()
    local visible = {}
    for _, candidate in ipairs(recruitingCandidates) do
        visible[#visible+1]=candidate
    end
    return visible
end

function Audit:UpdateRecruitingPopulation()
    local headline = OldGodsFeedback.Population()
    for _, frame in pairs({self.recruitingPage, self.compactRecruiting}) do
        if frame.population then frame.population:SetText(headline) end
        if frame.populationDetail then frame.populationDetail:Hide() end
    end
end

function Audit:NextRecruitingCandidate()
    for _, candidate in ipairs(recruitingCandidates) do
        local state=OldGodsFeedback.Eligibility(candidate)
        if state~="Blocked" then return candidate end
    end
end

OldGodsFeedback.OnChanged = function() OldGodsRecruiting:Cancel("Recruiting rules changed. Prepare the invite batch again."); Audit:RenderRecruitingCandidates() end

function Audit:RecordRecruitingIssue(kind, name, reason)
    local guildName, _, _, realm = GetGuildInfo("player")
    if not guildName or not OldGodsGuildAuditDB.roster then return end
    realm = realm or GetNormalizedRealmName()
    local guildKey = guildName .. "-" .. realm
    local events = OldGodsGuildAuditDB.roster.events
    local stamp = GetServerTime()
    local last = events[#events]
    if last and last.type == kind and last.player == name and last.details == reason and stamp-(last.timestamp or 0)<60 then return end
    events[#events+1]={schemaVersion=1,id=table.concat({guildKey,kind,name,tostring(stamp),tostring(#events+1)},"|"),
        timestamp=stamp,guildKey=guildKey,guildName=guildName,realm=realm,type=kind,player=name,details=reason,
        category="Recruiting",source="addonRecruiting",detectedBy=UnitName("player"),syncStatus="pendingUpload"}
    while #events>5000 do table.remove(events,1) end
end

function Audit:RenderCompactRecruiting(visible)
    local frame = self.compactRecruiting
    if not frame or not frame:IsShown() then return end
    self:UpdateRecruitingPopulation()
    visible = visible or self:VisibleRecruitingCandidates()
    local nextCandidate = OldGodsRecruiting.batch and OldGodsRecruiting.batch[1] or self:NextRecruitingCandidate()
    local remaining = whoContinueAt and math.max(0, math.ceil(whoContinueAt - GetTime())) or 0
    frame.search:SetText(not whoScanActive and "Search" or (not whoRequestPending and not whoContinueReady and remaining>0) and string.format("Continue Search (%ds)",remaining) or "Continue Search")
    frame.search:SetEnabled(not InCombatLockdown() and (not whoScanActive or (not whoRequestPending and whoContinueReady)))
    frame.invite:SetEnabled(not InCombatLockdown() and nextCandidate ~= nil)
    frame.status:SetText(pendingRecruitingWarning and (pendingRecruitingWarning .. " Review the realm warning in the full Recruiting tab.")
        or string.format("%d candidates | %d invited this session\nNext: %s", #visible, sessionInviteCount, nextCandidate and nextCandidate.fullName or "none"))
    local candidateY = 0
    for _, line in ipairs(frame.lines) do line:Hide() end
    for i, candidate in ipairs(self:RecruitingPageSlice(visible,frame)) do
        local line = frame.lines[i]
        if not line then
            line = frame.content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            line:SetWidth(300); line:SetJustifyH("LEFT")
            frame.lines[i] = line
        end
        line:SetHeight(20); line:SetMaxLines(1); line:SetWordWrap(false)
        line:SetText(string.format("%s - %d %s - %s",candidate.fullName,candidate.level or 0,candidate.classStr or "",candidate.area or "")); line:Show()
        line:ClearAllPoints(); line:SetPoint("TOPLEFT",4,-candidateY)
        candidateY = candidateY + 28
    end
    frame.content:SetHeight(math.max(1,candidateY))
    self:ApplyCompactTheme()
end

function Audit:UpdateRecruitingBindings()
    if InCombatLockdown() then self.recruitingBindingsPending = true; return end
    self.recruitingBindingsPending = nil
    local frame = self.compactRecruiting
    if not frame then return end
    ClearOverrideBindings(frame)
    if frame:IsShown() then
        SetOverrideBindingClick(frame,true,"CTRL-SHIFT-I","OldGodsCompactInvite","LeftButton")
        SetOverrideBindingClick(frame,true,"CTRL-SHIFT-S","OldGodsCompactSearch","LeftButton")
    end
end

function Audit:ToggleCompactRecruiting()
    if InCombatLockdown() then print("Old Gods Audit: Leave combat before opening or closing recruiting."); return end
    if not self.compactRecruiting then
        local frame = CreateFrame("Frame","OldGodsCompactRecruiting",UIParent,"BasicFrameTemplateWithInset,BackdropTemplate")
        self.compactRecruiting = frame
        frame:SetFrameStrata("FULLSCREEN")
        frame:SetToplevel(true)
        frame:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8", edgeFile="Interface/Buttons/WHITE8X8", edgeSize=1})
        frame:SetSize(360,455); frame:SetPoint("CENTER"); frame:SetClampedToScreen(true)
        frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart",frame.StartMoving); frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
        frame.TitleText:SetText("Old Gods — Recruiting")
        frame.population=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        frame.population:SetPoint("TOPLEFT",12,-34); frame.population:SetWidth(325); frame.population:SetJustifyH("LEFT")
        frame.populationDetail=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        frame.populationDetail:SetPoint("TOPLEFT",12,-59); frame.populationDetail:SetWidth(325); frame.populationDetail:SetJustifyH("LEFT")
        frame.expand=createButton(frame,"Open Full Recruiter",function() end,180)
        frame.expand:SetSize(180,24); frame.expand:SetPoint("BOTTOMLEFT",12,12); frame.expand:SetText("Open Full Recruiter")
        frame.expand:SetScript("OnClick",function()
            if InCombatLockdown() then return end
            frame:Hide(); Audit.frame:Show(); Audit:SelectTab("Recruiting")
        end)
        frame.lines = {}
        frame.candidatePrevious=createButton(frame,"<",function() frame.candidatePage=math.max(1,(frame.candidatePage or 1)-1); Audit:RenderCompactRecruiting() end,60)
        frame.candidatePrevious:SetPoint("BOTTOMLEFT",202,12)
        frame.candidateNext=createButton(frame,">",function() frame.candidatePage=(frame.candidatePage or 1)+1; Audit:RenderCompactRecruiting() end,60)
        frame.candidateNext:SetPoint("BOTTOMLEFT",270,12)
        frame.search = createButton(frame,"Search",function() end,152,"OldGodsCompactSearch")
        frame.search:SetSize(152,26); frame.search:SetPoint("TOPLEFT",12,-89)
        frame.search:SetScript("OnClick",function() if frame:IsShown() and not InCombatLockdown() then Audit:ContinueWhoScan() end end)
        frame.invite = createButton(frame,"Prepare Invite",function() OldGodsRecruiting:Clicked() end,152,"OldGodsCompactInvite",true)
        frame.invite:SetSize(152,26); frame.invite:SetPoint("LEFT",frame.search,"RIGHT",10,0)
        frame.keys = frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        frame.keys:SetPoint("TOPLEFT",12,-120); frame.keys:SetText("Ctrl+Shift+S: search     Ctrl+Shift+I: invite batch")
        frame.status = frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        frame.status:SetPoint("TOPLEFT",12,-143); frame.status:SetWidth(325); frame.status:SetHeight(55); frame.status:SetJustifyH("LEFT")
        frame.scroll = CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
        frame.scroll:SetPoint("TOPLEFT",12,-202); frame.scroll:SetPoint("BOTTOMRIGHT",-32,47)
        frame.content = CreateFrame("Frame",nil,frame.scroll); frame.content:SetSize(305,1); frame.scroll:SetScrollChild(frame.content)
        frame:SetScript("OnShow",function() Audit:UpdateRecruitingBindings(); Audit:RenderCompactRecruiting() end)
        frame:SetScript("OnHide",function() Audit:UpdateRecruitingBindings() end)
        frame:Hide()
    end
    local opening = not self.compactRecruiting:IsShown()
    if opening and self.frame then self.frame:Hide() end
    self.compactRecruiting:SetShown(opening)
end

function Audit:AddQuietZone(zoneName)
    local ok,message
    if OldGodsChapterSettings.CanManageQuiet() then
        ok,message=OldGodsChapterSettings.SetQuietZone(zoneName,false)
        if ok then self:PurgeQuietZoneCandidates(); self:RenderRecruitingCandidates() end
    else ok,message=OldGodsChapterSettings.ReportZone(zoneName) end
    self.recruitingNotice=message
    if self.quietZonesPage then
        self.quietZonesPage.quietStatus:SetText(message)
        if ok then self.quietZonesPage.zoneInput:SetText("") end
    end
    self:UpdateRecruitingStatus()
    self:RenderQuietZones()
end
function Audit:RenderQuietZones()
    local page=self.quietZonesPage
    if not page or not page.quietContent then return end
    for _,widget in ipairs(page.quietDynamicWidgets or {}) do widget:Hide() end
    page.quietDynamicWidgets=page.quietDynamicWidgets or {}
    page.quietTexts=page.quietTexts or {}; page.quietButtons=page.quietButtons or {}
    local textIndex,buttonIndex=0,0
    local function text(value,y)
        textIndex=textIndex+1
        local t=page.quietTexts[textIndex]
        if not t then t=page.quietContent:CreateFontString(nil,"OVERLAY","GameFontHighlight"); page.quietTexts[textIndex]=t; page.quietDynamicWidgets[#page.quietDynamicWidgets+1]=t end
        t:ClearAllPoints(); t:SetPoint("TOPLEFT",8,y); t:SetWidth(570); t:SetJustifyH("LEFT"); t:SetText(value); t:Show()
        return math.max(28,t:GetStringHeight()+12)
    end
    local function button(label,y,fn)
        buttonIndex=buttonIndex+1
        local b=page.quietButtons[buttonIndex]
        if not b then b=createButton(page.quietContent,label,fn,140); page.quietButtons[buttonIndex]=b; page.quietDynamicWidgets[#page.quietDynamicWidgets+1]=b end
        b:SetText(label); b:SetScript("OnClick",fn); b:ClearAllPoints(); b:SetPoint("TOPLEFT",610,y+5); b:Show()
        b:SetEnabled(OldGodsChapterSettings.CanManageQuiet())
    end
    local y=-10
    text("Pending zone reports (approval requires guild rank 0–4)",y); y=y-38
    local reports=(OldGodsGuildAuditDB.quietZoneReports or {})[OldGodsChapterSettings.Key()] or {}
    local approved={}
    for _,zone in ipairs(OldGodsChapterSettings.QuietZones()) do approved[zone:lower()]=true end
    for _,report in ipairs(reports) do
        if not approved[report.zone:lower()] then
            local zone=report.zone
            local rowHeight=math.max(38,text(zone.." — reported by "..report.author,y))
            button("Approve Zone",y,function()
                local ok,message=OldGodsChapterSettings.SetQuietZone(zone,false); page.quietStatus:SetText(message)
                if ok then Audit:PurgeQuietZoneCandidates(); Audit:RenderQuietZones(); Audit:RenderRecruitingCandidates() end
            end); y=y-rowHeight
        end
    end
    text("Approved chapter quiet zones",y); y=y-38
    for _,zone in ipairs(OldGodsChapterSettings.QuietZones()) do
        local name=zone
        local rowHeight=math.max(38,text(name,y)); button("Remove Zone",y,function()
            local ok,message=OldGodsChapterSettings.SetQuietZone(name,true); page.quietStatus:SetText(message)
            if ok then Audit:RenderQuietZones() end
        end); y=y-rowHeight
    end
    text("Default quiet zones",y); y=y-38
    local names={}; for _,name in pairs(getDefaultQuietZoneNames()) do names[#names+1]=name end; table.sort(names)
    for _,zone in ipairs(names) do
        local name=zone
        local removed=OldGodsChapterSettings.IsQuietZoneRemoved(name)
        local rowHeight=math.max(38,text(name..(removed and " (removed)" or ""),y))
        button(removed and "Add Zone" or "Remove Zone",y,function()
            local ok,message=OldGodsChapterSettings.SetQuietZone(name,not removed)
            page.quietStatus:SetText(message)
            if ok then Audit:PurgeQuietZoneCandidates(); Audit:RenderQuietZones(); Audit:RenderRecruitingCandidates() end
        end); y=y-rowHeight
    end
    page.quietContent:SetHeight(-y+10)
    if OldGodsTheme then OldGodsTheme.ApplyWindow(page.quietContent) end
end
local function restoreBlizzardWhoUI()
    if C_FriendList and C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(false)
    end
    if whoFriendsFrameSuppressed and FriendsFrame then
        FriendsFrame:RegisterEvent("WHO_LIST_UPDATE")
    end
    whoFriendsFrameSuppressed = false
end

local function suppressBlizzardWhoUI()
    if FriendsFrame and not FriendsFrame:IsShown() then
        FriendsFrame:UnregisterEvent("WHO_LIST_UPDATE")
        whoFriendsFrameSuppressed = true
    end
    C_FriendList.SetWhoToUi(true)
end

local function addWhoScanLog(message)
    whoScanLogLines[#whoScanLogLines + 1] = string.format("[%s] %s", date("%H:%M:%S"), message)
end

local function currentWhoLogText()
    return table.concat(whoScanLogLines, "\n")
end

local function buildWhoQuery(minLevel, maxLevel, filter, className)
    local query = string.format("%d-%d", minLevel, maxLevel)
    if className then query = query .. ' c-"' .. className:gsub('"', '') .. '"' end
    if filter and filter ~= "" then query = query .. " " .. filter end
    return query
end

local function getWhoClassNames()
    local names, seen = {}, {}
    for classID = 1, 13 do
        local name
        if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
            local info = C_CreatureInfo.GetClassInfo(classID)
            name = info and (info.className or info.name)
        elseif GetClassInfo then
            name = GetClassInfo(classID)
        end
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    return names
end

function Audit:StartWhoContinueCooldown(seconds)
    whoContinueReady = false
    whoContinueAt = GetTime() + seconds
    addWhoScanLog(string.format("COOLDOWN seconds=%d queued=%d manualContinue=true", seconds, #whoSearchQueue))
    if whoContinueTicker then whoContinueTicker:Cancel(); whoContinueTicker = nil end
    self:RenderRecruitingCandidates()
    whoContinueTicker = C_Timer.NewTicker(1, function(ticker)
        if not whoScanActive or whoRequestPending then
            ticker:Cancel()
            whoContinueTicker = nil
            return
        end
        if GetTime() >= whoContinueAt then
            whoContinueReady = true
            whoContinueAt = nil
            ticker:Cancel()
            whoContinueTicker = nil
            addWhoScanLog(string.format("READY queued=%d waitingForManualClick=true", #whoSearchQueue))
            Audit:RenderRecruitingCandidates()
            return
        end
        Audit:RenderRecruitingCandidates()
    end)
end

function Audit:ContinueWhoScan()
    if not whoScanActive then
        self:SearchRealmLevels()
    elseif whoRequestPending then
        print("Old Gods Audit: Waiting for the current /who result.")
    elseif not whoContinueReady then
        print("Old Gods Audit: Wait for the Continue Search countdown.")
    else
        addWhoScanLog(string.format("MANUAL_CONTINUE queued=%d", #whoSearchQueue))
        whoContinueReady = false
        self:RunNextWhoSearch()
    end
end

function Audit:FinishWhoScan(message)
    whoRequestPending = false
    self.recruitingSearchFinished=true
    whoScanActive = false
    whoContinueReady = false
    whoContinueAt = nil
    if whoContinueTicker then whoContinueTicker:Cancel(); whoContinueTicker = nil end
    whoCurrentSearch = nil
    restoreBlizzardWhoUI()
    table.sort(recruitingCandidates, function(left, right) return left.fullName < right.fullName end)
    self:RenderRecruitingCandidates()
    local finalMessage = message or string.format("Scan complete: %d candidates; %d queries completed; %d timed out; %d failed after retry.", #recruitingCandidates, whoQueriesCompleted, whoQueriesTimedOut, whoQueriesFailed)
    self.recruitingNotice=finalMessage
    self:UpdateRecruitingStatus()
    addWhoScanLog(finalMessage)
    OldGodsGuildAuditDB.recruitingLogs = OldGodsGuildAuditDB.recruitingLogs or {}
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local logText = string.format("Old Gods Guild Audit Recruiting Scan - %s\n%s", timestamp, currentWhoLogText())
    table.insert(OldGodsGuildAuditDB.recruitingLogs, 1, { timestamp = timestamp, text = logText })
    while #OldGodsGuildAuditDB.recruitingLogs > 20 do table.remove(OldGodsGuildAuditDB.recruitingLogs) end
    print("Old Gods Audit: Recruiting diagnostic log saved. Use Copy Last Scan Log, then /reload to write SavedVariables to disk.")
end

function Audit:RunNextWhoSearch()
    if not whoScanActive or whoRequestPending then return end
    whoCurrentSearch = table.remove(whoSearchQueue, 1)
    if not whoCurrentSearch then
        self:FinishWhoScan()
        return
    end
    whoRequestPending = true
    suppressBlizzardWhoUI()
    self:RenderRecruitingCandidates()
    local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or 1
    whoQuerySentAt = GetTime()
    addWhoScanLog(string.format("SEND query=%q retry=%d queued=%d", whoCurrentSearch.query, whoCurrentSearch.retryCount or 0, #whoSearchQueue))
    C_FriendList.SendWho(whoCurrentSearch.query, origin)
    if whoTimeoutTimer then whoTimeoutTimer:Cancel() end
    whoTimeoutTimer = C_Timer.NewTimer(20, function()
        if not whoRequestPending then return end
        whoRequestPending = false
        whoQueriesTimedOut = whoQueriesTimedOut + 1
        addWhoScanLog(string.format("TIMEOUT query=%q elapsed=%.2fs attempt=%d", whoCurrentSearch and whoCurrentSearch.query or "unknown", whoQuerySentAt and (GetTime() - whoQuerySentAt) or 0, (whoCurrentSearch and whoCurrentSearch.retryCount or 0) + 1))
        restoreBlizzardWhoUI()
        whoTimeoutTimer = nil
        whoCurrentSearch.retryCount = (whoCurrentSearch.retryCount or 0) + 1
        if whoCurrentSearch.retryCount <= 1 then
            table.insert(whoSearchQueue, 1, whoCurrentSearch)
            Audit.recruitingNotice="A search timed out. It will be retried once after the cooldown."
        else
            whoQueriesFailed = whoQueriesFailed + 1
            Audit.recruitingNotice="A search failed again and was skipped; it was not counted as completed."
        end
        if #whoSearchQueue > 0 then Audit:StartWhoContinueCooldown(12) else Audit:FinishWhoScan() end
    end)
end

function Audit:StartWhoSearch(query, label, minLevel, maxLevel, filter)
    if not C_FriendList or not C_FriendList.SendWho then
        print("Old Gods Audit: The Who API is unavailable.")
        return
    end
    if whoScanActive or whoRequestPending then
        print("Old Gods Audit: A /who scan is already running.")
        return
    end
    OldGodsRecruiting:Cancel()
    wipe(recruitingCandidates)
    wipe(whoSearchQueue)
    self.reviewedInviteCandidate = nil
    wipe(whoSearchSeen)
    local prunedHistory = pruneInviteHistory()
    whoQueriesCompleted = 0
    whoQueriesTimedOut = 0
    whoQueriesFailed = 0
    wipe(whoScanLogLines)
    local version, build, buildDate, tocVersion = GetBuildInfo()
    addWhoScanLog(string.format("START scope=%q player=%s realm=%s WoW=%s build=%s toc=%s", label or "Recruiting scan", UnitName("player") or "unknown", GetRealmName() or "unknown", version or "unknown", build or "unknown", tocVersion or "unknown"))
    local character, characterRealm = recruitingCharacterIdentity()
    local guildRealm = recruitingGuildRealm()
    local realmWarning, realmWarningIgnored = recruitingRealmWarning()
    local _, connectedConfig = connectedRealmLookup()
    addWhoScanLog(string.format("REALM_CHECK character=%q characterRealm=%q guildRealm=%q connected=%s override=%s configSource=%q configVersion=%s", character, characterRealm or "unknown", guildRealm or "unknown", tostring(realmsAreConnected(characterRealm, guildRealm)), tostring(realmWarning ~= nil and realmWarningIgnored), connectedConfig and connectedConfig.source or "missing", tostring(connectedConfig and connectedConfig.schemaVersion or 0)))
    addWhoScanLog(string.format("ANTI_SPAM retained=%d pruned=%d days=%d", getInviteHistoryCount(), prunedHistory, tonumber(OldGodsGuildAuditDB.recruiting.antiSpamDays) or 7))
    self.recruitingSearchFinished=false; self.recruitingNotice=nil
    if self.recruitingPage then self.recruitingPage.candidatePage=1 end
    if self.compactRecruiting then self.compactRecruiting.candidatePage=1 end
    whoScanLabel = label or "Recruiting scan"
    whoScanActive = true
    whoSearchQueue[1] = { query = query, label = label, minLevel = minLevel, maxLevel = maxLevel, filter = filter }
    self:RenderRecruitingCandidates()
    self:RunNextWhoSearch()
end

function Audit:CanStartRecruitingScan(scanType)
    local warning, ignored = recruitingRealmWarning()
    if warning and not ignored then
        pendingRecruitingScan = scanType
        pendingRecruitingWarning = warning
        self:RenderRecruitingCandidates()
        return false
    end
    pendingRecruitingScan = nil
    pendingRecruitingWarning = nil
    return true
end

function Audit:IgnoreRecruitingRealmWarning()
    local scanType = pendingRecruitingScan
    if not scanType then return end
    OldGodsGuildAuditDB.recruiting.ignoredRealmWarnings[recruitingRealmIgnoreKey()] = true
    pendingRecruitingScan = nil
    pendingRecruitingWarning = nil
    print("Old Gods Audit: Recruiting realm warning ignored for this character and guild realm.")
    if scanType == "current" then self:SearchCurrentZone() else self:SearchRealmLevels() end
end

function Audit:ResetRecruitingRealmCache()
    if whoScanActive then
        print("Old Gods Audit: Finish the current recruiting scan before resetting realm data.")
        return
    end
    OldGodsGuildAuditDB.recruiting.realmCache = {}
    OldGodsGuildAuditDB.recruiting.connectedRealmConfig = {}
    OldGodsGuildAuditDB.recruiting.ignoredRealmWarnings = {}
    OldGodsGuildAuditDB.guildRealm = ""
    if OldGodsGuildAuditDB.bank then OldGodsGuildAuditDB.bank.verifiedGuildRealms = {} end
    pendingRecruitingScan = nil
    pendingRecruitingWarning = nil
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    self:RenderRecruitingCandidates()
    print("Old Gods Audit: Saved realm data and overrides cleared. The next check reads current WoW data.")
end

function Audit:SearchCurrentZone()
    if not self:CanStartRecruitingScan("current") then return end
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    if not zone or zone == "" then
        print("Old Gods Audit: Could not determine the current zone.")
        return
    end
    zone = zone:gsub('"', '')
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 90
    local filter = 'z-"' .. zone .. '"'
    self:StartWhoSearch(buildWhoQuery(1, maxLevel, filter), "Current zone: " .. zone, 1, maxLevel, filter)
end

function Audit:SearchRealmLevels()
    if not self:CanStartRecruitingScan("all") then return end
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 90
    self:StartWhoSearch(buildWhoQuery(1, maxLevel), "All zones: levels 1-" .. maxLevel, 1, maxLevel)
end

function Audit:ProcessWhoResults()
    restoreBlizzardWhoUI()
    local count, total = C_FriendList.GetNumWhoResults()
    count = count or 0
    total = total or count
    addWhoScanLog(string.format("RESULT query=%q elapsed=%.2fs shown=%d total=%d", whoCurrentSearch and whoCurrentSearch.query or "unknown", whoQuerySentAt and (GetTime() - whoQuerySentAt) or 0, count, total))
    local quietExcluded = {}
    local sessionExcluded = 0
    local historyExcluded = 0
    local realmExcluded = 0
    local guildedExcluded = 0
    local duplicateExcluded = 0
    local accepted = 0
    local guildRealm = recruitingGuildRealm()
    local _, realmFilterOverridden = recruitingRealmWarning()
    local inviteHistory = OldGodsGuildAuditDB.recruiting.inviteHistory or {}
    for index = 1, count do
        local info = C_FriendList.GetWhoInfo(index)
        if info and info.fullName and trim(info.fullGuildName) ~= "" then
            guildedExcluded = guildedExcluded + 1
        elseif info and info.fullName then
            local normalizedName = normalizeRecruitName(info.fullName)
            local candidateRealm = normalizedName:match("%-(.+)$")
            if not realmFilterOverridden and not realmsAreConnected(candidateRealm, guildRealm) and not (OldGodsChapterSettings and OldGodsChapterSettings.IsOpenRealm(candidateRealm)) then
                realmExcluded = realmExcluded + 1
            elseif isQuietZone(info.area) then
                local area = info.area or "Unknown"
                quietExcluded[area] = (quietExcluded[area] or 0) + 1
            elseif sessionInvitedPlayers[normalizedName] then
                sessionExcluded = sessionExcluded + 1
            elseif inviteHistory[normalizedName] then
                historyExcluded = historyExcluded + 1
            elseif not whoSearchSeen[normalizedName] then
                whoSearchSeen[normalizedName] = true
                local ban = OldGodsFeedback.Banned(info.fullName)
                if ban then self:RecordRecruitingIssue("blocked",info.fullName,"Recruitment blocked by ban: " .. ban.reason) end
                recruitingCandidates[#recruitingCandidates + 1] = info
                accepted = accepted + 1
            else
                duplicateExcluded = duplicateExcluded + 1
            end
        end
    end
    if realmFilterOverridden then addWhoScanLog(string.format("REALM_OVERRIDE candidateFilter=bypassed guildRealm=%q", guildRealm or "unknown")) end
    addWhoScanLog(string.format("CANDIDATES accepted=%d guilded=%d realm=%d session=%d antiSpam=%d duplicate=%d", accepted, guildedExcluded, realmExcluded, sessionExcluded, historyExcluded, duplicateExcluded))
    for area, excludedCount in pairs(quietExcluded) do
        addWhoScanLog(string.format("QUIET excluded=%d zone=%q", excludedCount, area))
    end
    if realmExcluded > 0 then addWhoScanLog(string.format("CONNECTED_REALM excluded=%d guildRealm=%q", realmExcluded, guildRealm or "unknown")) end
    if sessionExcluded > 0 then addWhoScanLog(string.format("SESSION_INVITED excluded=%d", sessionExcluded)) end
    if historyExcluded > 0 then addWhoScanLog(string.format("ANTI_SPAM excluded=%d", historyExcluded)) end

    local search = whoCurrentSearch
    local capped = count >= 50 or total > count
    addWhoScanLog(string.format("DECISION query=%q capped=%s", search and search.query or "unknown", tostring(capped)))
    if capped and search and search.minLevel and search.maxLevel then
        if search.minLevel < search.maxLevel then
            local middle = math.floor((search.minLevel + search.maxLevel) / 2)
            addWhoScanLog(string.format("SPLIT levels=%d-%d into %d-%d and %d-%d", search.minLevel, search.maxLevel, search.minLevel, middle, middle + 1, search.maxLevel))
            whoSearchQueue[#whoSearchQueue + 1] = {
                query = buildWhoQuery(search.minLevel, middle, search.filter),
                minLevel = search.minLevel, maxLevel = middle, filter = search.filter,
            }
            whoSearchQueue[#whoSearchQueue + 1] = {
                query = buildWhoQuery(middle + 1, search.maxLevel, search.filter),
                minLevel = middle + 1, maxLevel = search.maxLevel, filter = search.filter,
            }
        elseif not search.className then
            local classNames = getWhoClassNames()
            addWhoScanLog(string.format("SPLIT level=%d into %d class queries", search.minLevel, #classNames))
            for _, className in ipairs(classNames) do
                whoSearchQueue[#whoSearchQueue + 1] = {
                    query = buildWhoQuery(search.minLevel, search.maxLevel, search.filter, className),
                    minLevel = search.minLevel, maxLevel = search.maxLevel,
                    filter = search.filter, className = className,
                }
            end
        end
    end

    whoQueriesCompleted = whoQueriesCompleted + 1
    table.sort(recruitingCandidates, function(left, right) return left.fullName < right.fullName end)
    self:RenderRecruitingCandidates()
    if #whoSearchQueue > 0 then
        self:StartWhoContinueCooldown(8)
    else
        self:FinishWhoScan()
    end
end
function Audit:InviteNextCandidate()
    OldGodsRecruiting:Clicked()
end

function Audit:RecordRecruitingInvite(candidate)
    local normalizedName = normalizeRecruitName(candidate.fullName)
    if not sessionInvitedPlayers[normalizedName] then
        sessionInvitedPlayers[normalizedName] = true
        sessionInviteCount = sessionInviteCount + 1
    end
    OldGodsGuildAuditDB.recruiting.inviteHistory[normalizedName] = time()
    local guildName, _, _, guildRealm = GetGuildInfo("player")
    guildName = guildName or "Unknown Guild"
    guildRealm = guildRealm or (GetNormalizedRealmName and GetNormalizedRealmName()) or "UnknownRealm"
    local guildKey = guildName .. "-" .. guildRealm
    local recruiterName, recruiterRealm = UnitFullName("player")
    recruiterRealm = recruiterRealm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    local recruiter = recruiterName and (recruiterName .. (recruiterRealm ~= "" and ("-" .. recruiterRealm) or "")) or ""
    local invitedAt = GetServerTime()
    local recruitEvent = {
        schemaVersion = 1,
        id = table.concat({ guildKey or "", "recruitinvite", recruiter, candidate.fullName, tostring(invitedAt) }, "|"),
        timestamp = invitedAt, guildKey = guildKey, guildName = guildName, realm = guildRealm,
        type = "recruit", rawType = "recruitinvite", player = candidate.fullName,
        actor = recruiter, target = candidate.fullName, details = "Guild invitation requested (acceptance not confirmed)",
        detectedBy = recruiter, source = "addonRecruitInvite", syncStatus = "pendingUpload",
    }
    local eventList = OldGodsGuildAuditDB.roster.events
    eventList[#eventList + 1] = recruitEvent
    while #eventList > 5000 do table.remove(eventList, 1) end
    addWhoScanLog(string.format("INVITE session-recorded name=%q", candidate.fullName))
    for index, entry in ipairs(recruitingCandidates) do if entry == candidate then table.remove(recruitingCandidates, index); break end end
end

OldGodsRecruiting.getCandidates=function() return recruitingCandidates end
OldGodsRecruiting.onAttempt=function(candidate) Audit:RecordRecruitingInvite(candidate) end
OldGodsRecruiting.changed=function() Audit:ScheduleRecruitingRender() end

local CALENDAR_EVENT_TYPES = {
    { name = "Raid", key = "Raid", legacy = "CALENDAR_EVENTTYPE_RAID" },
    { name = "Dungeon", key = "Dungeon", legacy = "CALENDAR_EVENTTYPE_DUNGEON" },
    { name = "PVP", key = "PvP", legacy = "CALENDAR_EVENTTYPE_PVP" },
    { name = "Meeting", key = "Meeting", legacy = "CALENDAR_EVENTTYPE_MEETING" },
    { name = "Other", key = "Other", legacy = "CALENDAR_EVENTTYPE_OTHER" },
}

local function calendarEventTypeId(name)
    for _,item in ipairs(CALENDAR_EVENT_TYPES) do
        if item.name == name then
            local value = Enum and Enum.CalendarEventType and Enum.CalendarEventType[item.key]
            if value == nil then value = _G[item.legacy] end
            if type(value) == "number" and value >= 0 and value % 1 == 0 then return value end
            return nil
        end
    end
end

local function copyStringList(source)
    local copy = {}
    for _, value in ipairs(source or {}) do copy[#copy + 1] = value end
    return copy
end

local function calendarDateWithOffset(baseDate, days)
    local stamp = time({ year = baseDate.year, month = baseDate.month, day = baseDate.day, hour = 12 }) + ((days or 0) * 86400)
    local result = date("*t", stamp)
    return { year = result.year, month = result.month, day = result.day }
end

local function calendarDateText(value)
    return string.format("%04d-%02d-%02d", value.year, value.month, value.day)
end

local function calendarToday()
    local value = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if value then return { year=value.year, month=value.month, day=value.monthDay } end
    return date("*t")
end

function Audit:CalendarDaysInMonth(year, month)
    if month == 2 then return (year % 400 == 0 or (year % 4 == 0 and year % 100 ~= 0)) and 29 or 28 end
    return (month == 4 or month == 6 or month == 9 or month == 11) and 30 or 31
end

function Audit:SelectCalendarDatePart(part, value)
    if part ~= "day" and part ~= "month" and part ~= "year" then return end
    calendarSelectedDate[part] = value
    calendarSelectedDate.day = math.min(calendarSelectedDate.day, self:CalendarDaysInMonth(calendarSelectedDate.year, calendarSelectedDate.month))
    self:RenderCalendarDraft()
end

local function jsonEscape(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
    return '"' .. value .. '"'
end

local function inviteesJson(invitees)
    local values = {}
    for _, invitee in ipairs(invitees or {}) do values[#values + 1] = jsonEscape(invitee) end
    return "[" .. table.concat(values, ",") .. "]"
end

local function calendarEventsJson()
    local calendar = OldGodsGuildAuditDB.calendar or { templates = {}, events = {} }
    local templateJson = {}
    for _, template in ipairs(calendar.templates or {}) do
        templateJson[#templateJson + 1] = string.format('{"schemaVersion":%d,"id":%s,"name":%s,"eventType":%s,"eventTypeId":%d,"startDate":%s,"hour":%d,"minute":%d,"description":%s,"locked":%s,"invitees":%s,"repeatEnabled":%s,"repeatEveryDays":%d,"occurrences":%d,"source":%s,"syncStatus":%s,"updatedAt":%d}',
            template.schemaVersion or 1, jsonEscape(template.id), jsonEscape(template.name), jsonEscape(template.eventType), template.eventTypeId,
            jsonEscape(template.startDate), template.hour, template.minute, jsonEscape(template.description), tostring(template.locked), inviteesJson(template.invitees), tostring(template.repeatEnabled and true or false),
            template.repeatEveryDays or 0, template.occurrences or 1, jsonEscape(template.source), jsonEscape(template.syncStatus), template.updatedAt)
    end
    local eventJson = {}
    for _, event in ipairs(calendar.events or {}) do
        eventJson[#eventJson + 1] = string.format('{"id":%s,"templateId":%s,"name":%s,"eventType":%s,"eventTypeId":%d,"date":%s,"hour":%d,"minute":%d,"description":%s,"locked":%s,"invitees":%s,"source":%s,"syncStatus":%s,"createdAt":%d}',
            jsonEscape(event.id), jsonEscape(event.templateId), jsonEscape(event.name), jsonEscape(event.eventType), event.eventTypeId,
            jsonEscape(event.date), event.hour, event.minute, jsonEscape(event.description), tostring(event.locked), inviteesJson(event.invitees),
            jsonEscape(event.source), jsonEscape(event.syncStatus), event.createdAt)
    end
    return string.format('{"schemaVersion":1,"generatedAt":%d,"calendarTemplates":[%s],"calendarEvents":[%s]}', time(), table.concat(templateJson, ","), table.concat(eventJson, ","))
end

function Audit:SetCalendarFormVisible(visible)
    local page = self.calendarPage
    if not page then return end
    page.formVisible = visible and true or false
    for _, widget in ipairs(page.formWidgets or {}) do widget:SetShown(page.formVisible) end
end

function Audit:StartCalendarContinueCooldown(seconds)
    calendarContinueReady = false
    calendarContinueAt = GetTime() + seconds
    if calendarContinueTicker then calendarContinueTicker:Cancel() end
    self:RenderCalendarDraft()
    calendarContinueTicker = C_Timer.NewTicker(1, function(ticker)
        if #pendingCalendarCreates == 0 or not Audit.calendarPage.formVisible then ticker:Cancel(); calendarContinueTicker = nil; calendarContinueAt = nil; return end
        if GetTime() >= calendarContinueAt then calendarContinueReady = true; calendarContinueAt = nil; ticker:Cancel(); calendarContinueTicker = nil end
        Audit:RenderCalendarDraft()
    end)
end

function Audit:NewCalendarEvent()
    local page = self.calendarPage
    if calendarContinueTicker then calendarContinueTicker:Cancel(); calendarContinueTicker = nil end
    calendarContinueReady = true; calendarContinueAt = nil
    wipe(pendingCalendarCreates); wipe(calendarDraftInvitees)
    local tomorrow = calendarDateWithOffset(calendarToday(), 1)
    calendarSelectedDate = { year = tomorrow.year, month = tomorrow.month, day = tomorrow.day }
    calendarEventTypeIndex = 2
    page.nameInput:SetText(""); page.descriptionInput:SetText(""); page.hourInput:SetText("7"); page.minuteInput:SetText("00")
    page.isPM = true; page.ampmButton:SetText("PM"); page.lockCheck:SetChecked(false); page.repeatCheck:SetChecked(false)
    page.repeatDaysInput:SetText("7"); page.occurrencesInput:SetText("6"); page.inviteeInput:SetText("")
    self:SetCalendarFormVisible(true)
    page.status:SetText("Enter event details, then click Add Event. Select Repeat only for multiple dates.")
    self:RenderCalendarDraft()
end

function Audit:RenderCalendarDraft()
    local page = self.calendarPage
    if not page or not page.formBuilt then return end
    page.dateText:SetText("Event date: " .. calendarDateText(calendarSelectedDate))
    for part, dropdown in pairs(page.dateDropdowns or {}) do dropdown:OverrideText(tostring(calendarSelectedDate[part])) end
    if page.typeButton.RefreshLabel then page.typeButton:RefreshLabel() else page.typeButton:SetText(CALENDAR_EVENT_TYPES[calendarEventTypeIndex].name) end
    if page.ampmButton.RefreshLabel then page.ampmButton:RefreshLabel() end
    page.inviteeList:SetText(#calendarDraftInvitees > 0 and ("Invitees: " .. table.concat(calendarDraftInvitees, ", ")) or "Invitees: none")
    local repeats = page.repeatCheck:GetChecked() and true or false
    page.repeatDaysInput:SetEnabled(repeats); page.occurrencesInput:SetEnabled(repeats)
    page.repeatDaysInput:SetAlpha(repeats and 1 or 0.45); page.occurrencesInput:SetAlpha(repeats and 1 or 0.45)
    local remaining = #pendingCalendarCreates
    if remaining > 0 then
        local nextEvent = pendingCalendarCreates[1]
        if calendarContinueReady then
            page.createButton:SetText("Continue"); page.createButton:SetEnabled(true)
            page.status:SetText(string.format("Ready: add %s to %s. Click Continue. %d occurrence(s) remain.", nextEvent.name, nextEvent.date, remaining))
        else
            local wait = calendarContinueAt and math.max(0, math.ceil(calendarContinueAt - GetTime())) or 0
            page.createButton:SetText(string.format("Wait %ds", wait)); page.createButton:SetEnabled(false)
            page.status:SetText(string.format("Event added. Wait %d second(s) before continuing. %d occurrence(s) remain.", wait, remaining))
        end
    else
        page.createButton:SetText(repeats and "Add Repeating Events" or "Add Event"); page.createButton:SetEnabled(true)
    end
end

function Audit:AddCalendarDraftInvitee()
    local page = self.calendarPage
    local name = trim(page.inviteeInput:GetText())
    if name == "" then page.status:SetText("Enter a player name before pressing Add Invitee."); return end
    local lookup = name:lower()
    for _, existing in ipairs(calendarDraftInvitees) do
        if existing:lower() == lookup then page.status:SetText(name .. " is already in the invitee list."); return end
    end
    calendarDraftInvitees[#calendarDraftInvitees + 1] = name
    page.inviteeInput:SetText("")
    self:RenderCalendarDraft()
end

function Audit:StartCalendarSeries()
    local page = self.calendarPage
    local title = trim(page.nameInput:GetText())
    local description = page.descriptionInput:GetText() or ""
    local hour12 = tonumber(page.hourInput:GetText())
    local minute = tonumber(page.minuteInput:GetText())
    local repeats = page.repeatCheck:GetChecked() and true or false
    local repeatDays = repeats and (tonumber(page.repeatDaysInput:GetText()) or 7) or 0
    local occurrences = repeats and (tonumber(page.occurrencesInput:GetText()) or 6) or 1
    if title == "" then page.status:SetText("Event Name is required."); return end
    if #description > 255 then page.status:SetText("Description must be 255 characters or fewer."); return end
    if not hour12 or hour12 < 1 or hour12 > 12 then page.status:SetText("Hour must be from 1 through 12."); return end
    if not minute or minute < 0 or minute > 59 then page.status:SetText("Minute must be from 0 through 59."); return end
    if repeats and (repeatDays < 1 or repeatDays > 365) then page.status:SetText("Repeat Every must be from 1 through 365 days."); return end
    if repeats and (occurrences < 2 or occurrences > 52) then page.status:SetText("Repeating occurrences must be from 2 through 52."); return end
    hour12, minute, repeatDays, occurrences = math.floor(hour12), math.floor(minute), math.floor(repeatDays), math.floor(occurrences)
    local hour24 = hour12 % 12
    if page.isPM then hour24 = hour24 + 12 end
    local eventType = CALENDAR_EVENT_TYPES[calendarEventTypeIndex]
    local typeId = eventType and calendarEventTypeId(eventType.name)
    if typeId == nil then page.status:SetText("The selected event type is unavailable in this WoW client. No event was created."); return end
    local templateId = string.format("calendar-template-%d", time())
    local template = {
        schemaVersion = 1, id = templateId, name = title, eventType = eventType.name, eventTypeId = typeId,
        hour = hour24, minute = minute, description = description, locked = page.lockCheck:GetChecked() and true or false,
        invitees = copyStringList(calendarDraftInvitees), repeatEnabled = repeats, repeatEveryDays = repeatDays, occurrences = occurrences,
        startDate = calendarDateText(calendarSelectedDate), source = "local", syncStatus = "pendingUpload", updatedAt = time(),
    }
    table.insert(OldGodsGuildAuditDB.calendar.templates, 1, template)
    while #OldGodsGuildAuditDB.calendar.templates > 50 do table.remove(OldGodsGuildAuditDB.calendar.templates) end
    wipe(pendingCalendarCreates)
    for occurrence = 1, occurrences do
        local eventDate = calendarDateWithOffset(calendarSelectedDate, repeats and ((occurrence - 1) * repeatDays) or 0)
        pendingCalendarCreates[#pendingCalendarCreates + 1] = {
            templateId = templateId, name = title, eventType = eventType.name, eventTypeId = typeId,
            date = calendarDateText(eventDate), year = eventDate.year, month = eventDate.month, day = eventDate.day,
            hour = hour24, minute = minute, description = description, locked = template.locked,
            invitees = copyStringList(calendarDraftInvitees), source = "local", syncStatus = "pendingUpload",
        }
    end
    calendarContinueReady = true
    self:CreateNextCalendarEvent()
end

function Audit:CreateNextCalendarEvent()
    local page = self.calendarPage
    local event = pendingCalendarCreates[1]
    if not event then page.status:SetText("Event creation is complete. Click New Event to start another."); return end
    if not calendarContinueReady then
        local wait = calendarContinueAt and math.max(0, math.ceil(calendarContinueAt - GetTime())) or 0
        page.status:SetText(string.format("Please wait %d second(s) before continuing.", wait)); return
    end
    if C_Calendar and C_Calendar.OpenCalendar then C_Calendar.OpenCalendar() end
    if InCombatLockdown() or not C_Calendar or not C_Calendar.CanAddEvent or not C_Calendar.CanAddEvent() then
        page.status:SetText("Calendar creation is unavailable. Leave combat, open Calendar once, then click again."); return
    end
    -- Resolve by the selected name again for each occurrence; never reuse old numeric IDs.
    local typeId = calendarEventTypeId(event.eventType)
    if typeId == nil then page.status:SetText("The selected event type is unavailable in this WoW client. No event was created."); return end
    event.eventTypeId = typeId
    C_Calendar.CreateGuildSignUpEvent()
    C_Calendar.EventSetTitle(event.name); C_Calendar.EventSetDate(event.month, event.day, event.year)
    C_Calendar.EventSetTime(event.hour, event.minute); C_Calendar.EventSetType(event.eventTypeId)
    C_Calendar.EventSetDescription(event.description)
    if event.locked then C_Calendar.EventSetLocked() else C_Calendar.EventClearLocked() end
    for _, invitee in ipairs(event.invitees) do C_Calendar.EventInvite(invitee) end
    C_Calendar.AddEvent()
    table.remove(pendingCalendarCreates, 1)
    event.id = string.format("calendar-event-%d-%02d%02d", time(), event.hour, event.minute); event.createdAt = time()
    table.insert(OldGodsGuildAuditDB.calendar.events, 1, event)
    while #OldGodsGuildAuditDB.calendar.events > 500 do table.remove(OldGodsGuildAuditDB.calendar.events) end
    if #pendingCalendarCreates > 0 then
        self:StartCalendarContinueCooldown(8)
    else
        calendarContinueReady = true; calendarContinueAt = nil; self:RenderCalendarDraft()
        page.status:SetText("Event creation is complete. Click New Event to clear the form and begin another.")
    end
end

function Audit:BuildCalendarPage(page)
    page.extraTexts = page.extraTexts or {}; page.formWidgets = {}; page.formBuilt = true; page.formVisible = false
    local tomorrow = calendarDateWithOffset(calendarToday(), 1)
    calendarSelectedDate = { year = tomorrow.year, month = tomorrow.month, day = tomorrow.day }
    local function track(widget) page.formWidgets[#page.formWidgets + 1] = widget; return widget end
    local function label(text, x, y)
        local value = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        value:SetPoint("TOPLEFT", x, y); value:SetText(text); page.extraTexts[#page.extraTexts + 1] = value
        return track(value)
    end
    local function input(width, x, y, maxLetters)
        local value = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
        value:SetSize(width, 26); value:SetPoint("TOPLEFT", x, y); value:SetAutoFocus(false); value:SetMaxLetters(maxLetters or 255)
        return track(value)
    end
    page.body:SetText("Create one-time or repeating guild signup events. Click New Event to open a clean event form.")
    page.newEventButton = createButton(page, "New Event", function() Audit:NewCalendarEvent() end, 120); page.newEventButton:SetPoint("TOPRIGHT", -24, -24)
    label("Event Name", 24, -105); page.nameInput = input(360, 24, -125, 100)
    label("Event Type", 410, -105)
    page.typeButton = track(OldGodsUI.Dropdown(page, "Event type", (function() local choices={} for i,item in ipairs(CALENDAR_EVENT_TYPES) do choices[#choices+1]={i,item.name} end return choices end)(), function() return calendarEventTypeIndex end, function(value) calendarEventTypeIndex=value; Audit:RenderCalendarDraft() end, 190)); page.typeButton:SetPoint("TOPLEFT", 410, -124)
    page.dateText = label("", 555, -170)
    page.dateDropdowns = {}
    for i, part in ipairs({"day", "month", "year"}) do
        local selectedPart = part
        label(part == "day" and "Day" or part == "month" and "Month" or "Year", 24+(i-1)*86, -170)
        local dropdown=track(createButton(page,tostring(calendarSelectedDate[selectedPart]).." v",function(button)
            local first,last=1,selectedPart=="day" and Audit:CalendarDaysInMonth(calendarSelectedDate.year,calendarSelectedDate.month) or 12
            if selectedPart=="year" then first=calendarToday().year; local maximum=C_Calendar and C_Calendar.GetMaxCreateDate and C_Calendar.GetMaxCreateDate(); last=maximum and maximum.year or first+1 end
            local choices={}; for value=first,last do choices[#choices+1]={value,tostring(value)} end
            OldGodsUI.Choose(button,choices,function(value) Audit:SelectCalendarDatePart(selectedPart,value) end)
        end,80))
        dropdown:SetPoint("TOPLEFT",24+(i-1)*86,-192)
        function dropdown:OverrideText(value) self:SetText(value.." v") end
        OldGodsUI.Help(dropdown,selectedPart,"Choose the event "..selectedPart..". Dates use the WoW calendar.")
        page.dateDropdowns[part] = dropdown
    end
    label("Hour", 290, -170); page.hourInput = input(50, 290, -192, 2); page.hourInput:SetText("7")
    label("Minute", 355, -170); page.minuteInput = input(55, 355, -192, 2); page.minuteInput:SetText("00")
    page.isPM = true; page.ampmButton = track(OldGodsUI.Dropdown(page, "Time", {{false,"AM"},{true,"PM"}}, function() return page.isPM end, function(value) page.isPM=value; Audit:RenderCalendarDraft() end, 100)); page.ampmButton:SetPoint("TOPLEFT", 430, -192)
    label("Description (255 characters maximum)", 24, -235); page.descriptionInput = input(740, 24, -255, 255)
    page.lockCheck = track(CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")); page.lockCheck:SetPoint("TOPLEFT", 24, -296)
    local lockText = page.lockCheck.Text or page.lockCheck.text; if lockText then lockText:SetText("Lock Event") end
    page.repeatCheck = track(CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")); page.repeatCheck:SetPoint("TOPLEFT", 160, -296)
    local repeatText = page.repeatCheck.Text or page.repeatCheck.text; if repeatText then repeatText:SetText("Repeat") end
    page.repeatCheck:SetScript("OnClick", function() Audit:RenderCalendarDraft() end)
    label("Every", 280, -298); page.repeatDaysInput = input(45, 325, -295, 3); page.repeatDaysInput:SetText("7")
    label("days", 380, -298); label("Occurrences", 425, -298); page.occurrencesInput = input(45, 510, -295, 2); page.occurrencesInput:SetText("6")
    label("Invitee Player Name", 24, -345); page.inviteeInput = input(260, 24, -365, 100)
    local addInvitee = track(createButton(page, "Add Invitee", function() Audit:AddCalendarDraftInvitee() end, 120)); addInvitee:SetPoint("LEFT", page.inviteeInput, "RIGHT", 10, 0)
    local clearInvitees = track(createButton(page, "Clear Invitees", function() wipe(calendarDraftInvitees); Audit:RenderCalendarDraft() end, 125)); clearInvitees:SetPoint("LEFT", addInvitee, "RIGHT", 8, 0)
    page.inviteeList = label("Invitees: none", 24, -405); page.inviteeList:SetWidth(800); page.inviteeList:SetJustifyH("LEFT")
    page.createButton = track(createButton(page, "Add Event", function() if #pendingCalendarCreates > 0 then Audit:CreateNextCalendarEvent() else Audit:StartCalendarSeries() end end, 175)); page.createButton:SetPoint("TOPLEFT", 24, -440)
    local exportJson = track(createButton(page, "Copy Calendar JSON", function() showCopyBox(calendarEventsJson()) end, 175)); exportJson:SetPoint("LEFT", page.createButton, "RIGHT", 10, 0)
    local open = track(createButton(page, "Open WoW Calendar", openCalendar, 165)); open:SetPoint("LEFT", exportJson, "RIGHT", 10, 0)
    page.status = label("", 24, -485); page.status:SetWidth(820); page.status:SetJustifyH("LEFT")
    for key,labelText in pairs({nameInput="Event name",hourInput="Hour",minuteInput="Minute",descriptionInput="Description",repeatDaysInput="Repeat interval",occurrencesInput="Occurrences",inviteeInput="Invitee",lockCheck="Lock Event",repeatCheck="Repeat"}) do OldGodsUI.Help(page[key],labelText) end
    self:RenderCalendarDraft(); self:SetCalendarFormVisible(false)
end

local function currentGuildIdentity()
    local guildName = GetGuildInfo("player")
    local guildRealm = recruitingGuildRealm()
    guildName = guildName or "No Guild"
    local scannerRealm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
    local expectedMotd = expectedGuildMotd(guildRealm)
    local motdMatches = guildMotdChecks(motd, guildName, guildRealm)
    local motdRealm = motdMatches and guildRealm or nil
    local status, warning = "verified", nil
    if guildName == "No Guild" or not guildRealm or guildRealm == "" then
        status, warning = "unverified", "Blizzard did not provide a guild realm. Open the guild roster and refresh."
        guildRealm = guildRealm or "UnknownGuildRealm"
    elseif not motdMatches then
        status, warning = "mismatch", "Guild identity warning: expected MOTD '" .. expectedMotd .. "'."
    end
    local verified = OldGodsGuildAuditDB.bank.verifiedGuildRealms
    local _, verificationKey = recruitingRealmCache()
    local priorRealm = verified[verificationKey]
    if priorRealm and normalizeRealmKey(priorRealm) ~= normalizeRealmKey(guildRealm) then
        status, warning = "changed", string.format("Guild identity warning: Blizzard guild realm changed from %s to %s.", priorRealm, guildRealm)
    elseif motdMatches then
        verified[verificationKey] = guildRealm
    end
    return {
        guildKey = guildName .. "-" .. guildRealm, guildName = guildName, guildRealm = guildRealm,
        scannerRealm = scannerRealm, motd = motd, motdRealm = motdRealm,
        identityStatus = status, identityWarning = warning,
    }
end

local function currentGuildKey()
    local identity = currentGuildIdentity()
    return identity.guildKey, identity.guildName, identity.guildRealm, identity
end

local function bankAbsoluteTimestamp(year, month, day, hour)
    local hoursAgo = (((tonumber(year) or 0) * 365 + (tonumber(month) or 0) * 30 + (tonumber(day) or 0)) * 24) + (tonumber(hour) or 0)
    return GetServerTime() - (hoursAgo * 3600)
end

local function bankItemID(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)")) or link:match("battlepet:(%d+)")
end

local function bankBaseKey(record)
    return table.concat({ record.guildKey or "", record.kind or "", record.type or "", record.player or "", tostring(record.itemID or ""), tostring(record.amount or record.count or 0), tostring(record.tab or 0), tostring(record.toTab or 0), tostring(math.floor((record.timestamp or 0) / 3600)) }, "|")
end

function Audit:StoreBankBatch(records)
    local db = OldGodsGuildAuditDB.bank
    local occurrences = {}
    local added = 0
    for _, record in ipairs(records) do
        local base = bankBaseKey(record)
        occurrences[base] = (occurrences[base] or 0) + 1
        record.id = base .. ":" .. occurrences[base]
        if not db.seenTransactions[record.id] then
            db.seenTransactions[record.id] = true
            db.transactions[#db.transactions + 1] = record
            added = added + 1
        end
    end
    table.sort(db.transactions, function(left, right) return (left.timestamp or 0) > (right.timestamp or 0) end)
    while #db.transactions > 10000 do table.remove(db.transactions) end
    return added
end

function Audit:CaptureGuildBankLogs()
    if not guildBankOpen then return end
    local guildKey, guildName, realmName, identity = currentGuildKey()
    if identity.identityStatus == "unverified" then
        if self.bankPage and self.bankPage.status then self.bankPage.status:SetText(identity.identityWarning) end
        return
    end
    local scanner = UnitName("player") or "Unknown"
    local scannedAt = GetServerTime()
    local records = {}
    for tab = 1, GetNumGuildBankTabs() do
        local tabName, _, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            local count = GetNumGuildBankTransactions(tab) or 0
            for index = 1, count do
                local txType, player, itemLink, quantity, fromTab, toTab, year, month, day, hour = GetGuildBankTransaction(tab, index)
                if txType and player then
                    records[#records + 1] = {
                        schemaVersion = 2, guildKey = guildKey, guildName = guildName, realm = realmName, guildRealm = realmName,
                        scannerRealm = identity.scannerRealm, motd = identity.motd, motdRealm = identity.motdRealm,
                        identityStatus = identity.identityStatus, identityWarning = identity.identityWarning,
                        kind = "item", type = txType, player = player, itemLink = itemLink, itemID = bankItemID(itemLink),
                        count = quantity or 1, tab = fromTab or tab, tabName = tabName, toTab = toTab,
                        timestamp = bankAbsoluteTimestamp(year, month, day, hour), scannedAt = scannedAt, scannedBy = scanner,
                        source = "guildBankLog", syncStatus = "pendingUpload",
                    }
                end
            end
        end
    end
    local moneyCount = GetNumGuildBankMoneyTransactions and GetNumGuildBankMoneyTransactions() or 0
    for index = 1, moneyCount do
        local txType, player, amount, year, month, day, hour = GetGuildBankMoneyTransaction(index)
        if txType and player then
            records[#records + 1] = {
                schemaVersion = 2, guildKey = guildKey, guildName = guildName, realm = realmName, guildRealm = realmName,
                scannerRealm = identity.scannerRealm, motd = identity.motd, motdRealm = identity.motdRealm,
                identityStatus = identity.identityStatus, identityWarning = identity.identityWarning,
                kind = "gold", type = txType, player = player, amount = amount or 0,
                timestamp = bankAbsoluteTimestamp(year, month, day, hour), scannedAt = scannedAt, scannedBy = scanner,
                source = "guildBankMoneyLog", syncStatus = "pendingUpload",
            }
        end
    end
    local added = self:StoreBankBatch(records)
    if self.bankPage and self.bankPage.status then
        self.bankPage.status:SetText(identity.identityWarning or string.format("Ledger refreshed: %d new transaction(s), %d stored for %s.", added, #OldGodsGuildAuditDB.bank.transactions, guildKey))
    end
    self:RenderBankPage()
end

-- Guild-bank cages may have only an item:82800 link. Keep the original link and
-- capture public tooltip pet metadata for the website's level-specific pickup list.
function Audit:CaptureBankPetDetails(tab, slot, item)
    if not isPublicString(item.itemLink) or not item.itemLink:find("|Hitem:82800:", 1, true) then return end
    if not C_TooltipInfo or not C_TooltipInfo.GetGuildBankItem then return end
    local ok, data = pcall(C_TooltipInfo.GetGuildBankItem, tab, slot)
    if not ok or not isPublicTable(data) then return end
    local species, level, name = data.battlePetSpeciesID, data.battlePetLevel, data.battlePetName
    if not isPublicValue(species) or not isPublicValue(level) then return end
    if type(species) ~= "number" or species <= 0 or species % 1 ~= 0 then return end
    if type(level) ~= "number" or level < 1 or level > 25 or level % 1 ~= 0 then return end
    item.battlePetSpeciesID, item.battlePetLevel = species, level
    if isPublicString(name) then item.battlePetName = name end
end
function Audit:CaptureGuildBankInventory()
    if not guildBankOpen then return end
    local guildKey, guildName, realmName, identity = currentGuildKey()
    if identity.identityStatus == "unverified" then
        if self.bankPage and self.bankPage.status then self.bankPage.status:SetText(identity.identityWarning) end
        return
    end
    local snapshot = {
        schemaVersion = 2, id = bankOpenSessionId or ("bank-open-" .. GetServerTime()), guildKey = guildKey,
        guildName = guildName, realm = realmName, guildRealm = realmName, scannerRealm = identity.scannerRealm,
        motd = identity.motd, motdRealm = identity.motdRealm, identityStatus = identity.identityStatus,
        identityWarning = identity.identityWarning, capturedAt = GetServerTime(), capturedBy = UnitName("player") or "Unknown",
        bankMoney = GetGuildBankMoney and GetGuildBankMoney() or 0, tabs = {}, source = "guildBankSnapshot", syncStatus = "pendingUpload",
    }
    for tab = 1, GetNumGuildBankTabs() do
        local tabName, icon, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            local tabRecord = { index = tab, name = tabName or ("Tab " .. tab), icon = icon, items = {} }
            for slot = 1, 98 do
                local itemLink = GetGuildBankItemLink(tab, slot)
                if itemLink then
                    local texture, count, locked = GetGuildBankItemInfo(tab, slot)
                    tabRecord.items[#tabRecord.items + 1] = {
                        slot = slot, itemID = bankItemID(itemLink), itemLink = itemLink, count = count or 1,
                        texture = texture, locked = locked and true or false,
                    }
                    self:CaptureBankPetDetails(tab, slot, tabRecord.items[#tabRecord.items])
                end
            end
            snapshot.tabs[#snapshot.tabs + 1] = tabRecord
        end
    end
    OldGodsGuildAuditDB.bank.currentInventory[guildKey] = snapshot
    local replaced = false
    for index, existing in ipairs(OldGodsGuildAuditDB.bank.snapshots) do
        if existing.id == snapshot.id and existing.guildKey == guildKey then OldGodsGuildAuditDB.bank.snapshots[index] = snapshot; replaced = true; break end
    end
    if not replaced then table.insert(OldGodsGuildAuditDB.bank.snapshots, 1, snapshot) end
    while #OldGodsGuildAuditDB.bank.snapshots > 100 do table.remove(OldGodsGuildAuditDB.bank.snapshots) end
    self:RenderBankPage()
end

function Audit:ScheduleBankLogCapture()
    if bankLogTimer then bankLogTimer:Cancel() end
    bankLogTimer = C_Timer.NewTimer(0.6, function() bankLogTimer = nil; Audit:CaptureGuildBankLogs() end)
end

function Audit:ScheduleBankInventoryCapture()
    if bankInventoryTimer then bankInventoryTimer:Cancel() end
    bankInventoryTimer = C_Timer.NewTimer(0.8, function() bankInventoryTimer = nil; Audit:CaptureGuildBankInventory() end)
end

function Audit:ContinueBankInventoryQuery()
    local state = bankInventoryQueryState
    if not state or not guildBankOpen then return end
    if state.timer then state.timer:Cancel(); state.timer = nil end
    state.index = state.index + 1
    local tab = state.tabs[state.index]
    if not tab then
        bankInventoryQueryState = nil
        self:ScheduleBankInventoryCapture()
        return
    end
    state.waitingForTab = tab
    QueryGuildBankTab(tab)
    state.timer = C_Timer.NewTimer(2.5, function()
        if bankInventoryQueryState == state and state.waitingForTab == tab then
            state.waitingForTab = nil
            Audit:ContinueBankInventoryQuery()
        end
    end)
end

function Audit:StartBankInventoryQuery()
    if bankInventoryQueryState and bankInventoryQueryState.timer then bankInventoryQueryState.timer:Cancel() end
    local tabs = {}
    for tab = 1, GetNumGuildBankTabs() do
        local _, _, viewable = GetGuildBankTabInfo(tab)
        if viewable then tabs[#tabs + 1] = tab end
    end
    bankInventoryQueryState = { tabs = tabs, index = 0 }
    self:ContinueBankInventoryQuery()
end

local function isGuildBankVisible()
    return GuildBankFrame and GuildBankFrame:IsShown()
end

function Audit:BeginGuildBankSession(source)
    if guildBankOpen then return end
    guildBankOpen = true
    bankOpenSessionId = string.format("bank-open-%d-%s", GetServerTime(), UnitName("player") or "unknown")
    if self.bankPage and self.bankPage.status then
        self.bankPage.status:SetText("Guild bank detected (" .. (source or "event") .. "). Loading logs and inventory...")
    end
    C_Timer.After(0.2, function()
        if guildBankOpen then Audit:QueryGuildBankData() end
    end)
end

function Audit:EndGuildBankSession()
    guildBankOpen = false
    self:ClearSpazzyBinding()
    if bankLogTimer then bankLogTimer:Cancel(); bankLogTimer = nil end
    if bankInventoryTimer then bankInventoryTimer:Cancel(); bankInventoryTimer = nil end
    if bankInventoryQueryState and bankInventoryQueryState.timer then bankInventoryQueryState.timer:Cancel() end
    bankInventoryQueryState = nil
    self:RenderBankPage()
end
function Audit:QueryGuildBankData()
    if not guildBankOpen and isGuildBankVisible() then
        self:BeginGuildBankSession("visible frame")
        return
    end
    if not guildBankOpen then
        if self.bankPage and self.bankPage.status then self.bankPage.status:SetText("Open the guild bank at a banker to capture logs and inventory.") end
        return
    end
    for tab = 1, GetNumGuildBankTabs() do
        local _, _, viewable = GetGuildBankTabInfo(tab)
        if viewable then QueryGuildBankLog(tab) end
    end
    QueryGuildBankLog((MAX_GUILDBANK_TABS or 8) + 1)
    self:ScheduleBankLogCapture()
    self:StartBankInventoryQuery()
end

local function bankRecordMatches(record, searchText)
    local guildKey = currentGuildKey()
    if record.guildKey ~= guildKey then return false end
    if bankKindFilter ~= "all" and record.kind ~= bankKindFilter then return false end
    if bankDirectionFilter ~= "all" and record.type ~= bankDirectionFilter then return false end
    if searchText ~= "" then
        local haystack = table.concat({ record.player or "", record.itemLink or "", record.tabName or "", record.type or "" }, " "):lower()
        if not haystack:find(searchText, 1, true) then return false end
    end
    return true
end

local function bankMoneyText(amount)
    if issecretvalue and issecretvalue(amount) then return "Unknown" end
    local copper=tonumber(amount or 0)
    if not copper or copper~=copper or copper==math.huge or copper==-math.huge then return "Unknown" end
    local sign=copper<0 and "-" or ""
    copper=math.floor(math.abs(copper))
    local gold=math.floor(copper/10000)
    local silver=math.floor(copper/100)%100
    return string.format("%s%dg %ds %dc",sign,gold,silver,copper%100)
end

function Audit:RenderBankPage()
    local page = self.bankPage
    if not page or not page.bankBuilt then return end
    for _, widget in ipairs(page.dynamicWidgets) do widget:Hide() end
    wipe(page.dynamicWidgets)
    local parent = page.content
    page.linePool = page.linePool or {}
    local function acquireLine(index, font)
        local line = page.linePool[index]
        if not line then
            line = parent:CreateFontString(nil, "OVERLAY", font)
            page.linePool[index] = line
        end
        line:Show()
        return line
    end
    local y = -4
    local shown = 0
    local searchText = trim(page.searchInput:GetText()):lower()
    local identity = currentGuildIdentity()
    local identitySuffix = identity.identityWarning and (" " .. identity.identityWarning) or ""
    if bankViewMode == "ledger" then
        for _, record in ipairs(OldGodsGuildAuditDB.bank.transactions) do
            if bankRecordMatches(record, searchText) then
                shown = shown + 1
                local line = acquireLine(shown, "GameFontHighlightSmall")
                line:SetPoint("TOPLEFT", 6, y); line:SetWidth(790); line:SetJustifyH("LEFT")
                local detail = record.kind == "gold" and bankMoneyText(record.amount) or string.format("%dx %s", record.count or 1, record.itemLink or ("Item " .. tostring(record.itemID or "?")))
                line:SetText(string.format("%s | %s | %s | %s | %s", date("%Y-%m-%d %H:00", record.timestamp), record.type:upper(), record.player, detail, record.tabName or "Guild Money"))
                page.dynamicWidgets[#page.dynamicWidgets + 1] = line; y = y - 24
            end
        end
        page.status:SetText(string.format("Ledger: %d matching of %d stored transaction(s). Bank %s.%s", shown, #OldGodsGuildAuditDB.bank.transactions, guildBankOpen and "OPEN" or "closed", identitySuffix))
    else
        local guildKey = currentGuildKey()
        local snapshot = OldGodsGuildAuditDB.bank.currentInventory[guildKey]
        if snapshot then
            for _, tab in ipairs(snapshot.tabs or {}) do
                for _, item in ipairs(tab.items or {}) do
                    local haystack = ((item.itemLink or "") .. " " .. (tab.name or "")):lower()
                    if searchText == "" or haystack:find(searchText, 1, true) then
                        shown = shown + 1
                        local line = acquireLine(shown, "GameFontHighlightSmall")
                        line:SetPoint("TOPLEFT", 6, y); line:SetWidth(790); line:SetJustifyH("LEFT")
                        line:SetText(string.format("%s | Slot %d | %dx %s", tab.name, item.slot, item.count or 1, item.itemLink or ("Item " .. tostring(item.itemID or "?"))))
                        page.dynamicWidgets[#page.dynamicWidgets + 1] = line; y = y - 24
                    end
                end
            end
            page.status:SetText(string.format("Inventory snapshot: %d matching item stack(s), captured %s.%s", shown, date("%Y-%m-%d %H:%M", snapshot.capturedAt), identitySuffix))
        else
            page.status:SetText("No inventory snapshot yet. Open the guild bank to capture one." .. identitySuffix)
        end
    end
    parent:SetHeight(math.max(1, -y + 10))
    page.viewButton:RefreshLabel()
    page.kindButton:RefreshLabel()
    page.directionButton:RefreshLabel()
    self:ApplyTheme()
end

local BANK_JSON_FIELDS = true
local function bankJson()
    local db = OldGodsGuildAuditDB.bank
    local guildKey = currentGuildKey()
    local records = {}
    for _, record in ipairs(db.transactions) do
        if record.guildKey == guildKey then
            records[#records + 1] = string.format('{"id":%s,"guildKey":%s,"kind":%s,"type":%s,"player":%s,"itemID":%s,"itemLink":%s,"count":%d,"amount":%d,"tab":%d,"tabName":%s,"toTab":%d,"timestamp":%d,"scannedAt":%d,"scannedBy":%s,"source":%s,"syncStatus":%s}',
                jsonEscape(record.id), jsonEscape(record.guildKey), jsonEscape(record.kind), jsonEscape(record.type), jsonEscape(record.player), record.itemID and tostring(record.itemID) or "null", jsonEscape(record.itemLink), record.count or 0, record.amount or 0, record.tab or 0, jsonEscape(record.tabName), record.toTab or 0, record.timestamp or 0, record.scannedAt or 0, jsonEscape(record.scannedBy), jsonEscape(record.source), jsonEscape(record.syncStatus))
        end
    end
    local snapshot = db.currentInventory[guildKey]
    local tabs = {}
    if snapshot then
        for _, tab in ipairs(snapshot.tabs or {}) do
            local items = {}
            for _, item in ipairs(tab.items or {}) do
                items[#items + 1] = string.format('{"slot":%d,"itemID":%s,"itemLink":%s,"count":%d,"locked":%s}', item.slot, item.itemID and tostring(item.itemID) or "null", jsonEscape(item.itemLink), item.count or 1, tostring(item.locked))
            end
            tabs[#tabs + 1] = string.format('{"index":%d,"name":%s,"items":[%s]}', tab.index, jsonEscape(tab.name), table.concat(items, ","))
        end
    end
    local identity = currentGuildIdentity()
    return string.format('{"schemaVersion":2,"generatedAt":%d,"guildKey":%s,"guildName":%s,"guildRealm":%s,"scannerRealm":%s,"motd":%s,"motdRealm":%s,"identityStatus":%s,"identityWarning":%s,"transactions":[%s],"inventory":{"capturedAt":%d,"bankMoney":%d,"tabs":[%s]}}', GetServerTime(), jsonEscape(guildKey), jsonEscape(identity.guildName), jsonEscape(identity.guildRealm), jsonEscape(identity.scannerRealm), jsonEscape(identity.motd), jsonEscape(identity.motdRealm), jsonEscape(identity.identityStatus), jsonEscape(identity.identityWarning), table.concat(records, ","), snapshot and snapshot.capturedAt or 0, snapshot and snapshot.bankMoney or 0, table.concat(tabs, ","))
end

function Audit:BuildBankPage(page)
    page.bankBuilt = true; page.extraTexts = page.extraTexts or {}; page.dynamicWidgets = {}
    page.heading:Hide(); page.body:Hide()
    page.searchInput = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    page.searchInput:SetSize(250, 27); page.searchInput:SetPoint("TOPLEFT", 24, -14); page.searchInput:SetAutoFocus(false); page.searchInput:SetMaxLetters(100)
    page.searchInput:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Audit:RenderBankPage() end)
    OldGodsUI.Help(page.searchInput,"Bank search")
    local search = createButton(page, "Search", function() Audit:RenderBankPage() end, 85); search:SetPoint("LEFT", page.searchInput, "RIGHT", 8, 0)
    page.kindButton = OldGodsUI.Dropdown(page, "Kind", {{"all","All"},{"gold","Gold"},{"item","Items"}}, function() return bankKindFilter end, function(value) bankKindFilter=value; Audit:RenderBankPage() end, 140)
    page.kindButton:SetPoint("LEFT",search,"RIGHT",8,0)
    page.directionButton = OldGodsUI.Dropdown(page, "Type", {{"all","All"},{"deposit","Deposit"},{"withdraw","Withdrawal"},{"move","Move"},{"repair","Repair"},{"withdrawForTab","Tab purchase"}}, function() return bankDirectionFilter end, function(value) bankDirectionFilter=value; Audit:RenderBankPage() end,180)
    page.directionButton:SetPoint("LEFT",page.kindButton,"RIGHT",8,0)
    page.viewButton = OldGodsUI.Dropdown(page, "View", {{"ledger","Transactions"},{"inventory","Inventory"}}, function() return bankViewMode end, function(value) bankViewMode=value; Audit:RenderBankPage() end,185)
    page.viewButton:SetPoint("TOPLEFT", 24, -54)
    local refresh = createButton(page, "Capture Now", function() Audit:QueryGuildBankData() end, 120); refresh:SetPoint("LEFT", page.viewButton, "RIGHT", 8, 0)
    local export = createButton(page, "Copy Bank JSON", function() showCopyBox(bankJson()) end, 140); export:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    page.status = page:CreateFontString(nil, "OVERLAY", "GameFontNormal"); page.status:SetPoint("TOPLEFT", 24, -95); page.status:SetWidth(830); page.status:SetJustifyH("LEFT"); page.extraTexts[#page.extraTexts + 1] = page.status
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate"); page.scroll:SetPoint("TOPLEFT", 24, -124); page.scroll:SetPoint("BOTTOMRIGHT", -42, 20)
    page.content = CreateFrame("Frame", nil, page.scroll); page.content:SetSize(810, 1); page.scroll:SetScrollChild(page.content)
    self:RenderBankPage()
end

local function rosterGuildKey()
    local guildName, _, _, realmName = GetGuildInfo("player")
    realmName = realmName or GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    return string.format("%s-%s", guildName or "NoGuild", realmName), guildName or "No Guild", realmName
end

local function normalizeRosterMemberName(name)
    local parts = {}
    for part in tostring(name or ""):gmatch("[^-]+") do parts[#parts + 1] = part end
    while #parts >= 3 do
        local last = parts[#parts]:lower()
        local previous = parts[#parts - 1]:lower()
        local repeatedBeforeTruncation = #parts >= 4 and previous == parts[#parts - 2]:lower()
        if last == previous or repeatedBeforeTruncation then table.remove(parts) else break end
    end
    return table.concat(parts, "-")
end

local function normalizeRosterNamesInText(value)
    return tostring(value or ""):gsub("[%w']+%-%S+", function(token)
        local trailing = token:match("([,;%)%]]+)$") or ""
        local name = trailing ~= "" and token:sub(1, -#trailing - 1) or token
        return normalizeRosterMemberName(name) .. trailing
    end)
end

local function cleanupStoredRosterRecord(record)
    local changed = 0
    for _, field in ipairs({ "player", "actor", "target", "detectedBy" }) do
        if record[field] then
            local normalized = normalizeRosterMemberName(record[field])
            if normalized ~= record[field] then record[field] = normalized; changed = changed + 1 end
        end
    end
    for _, state in pairs({ before = record.before, after = record.after }) do
        if type(state) == "table" and state.name then
            local normalized = normalizeRosterMemberName(state.name)
            if normalized ~= state.name then state.name = normalized; changed = changed + 1 end
        end
    end
    if record.details then
        local details = {}
        for segment in tostring(record.details):gmatch("[^;]+") do
            segment = trim(segment)
            local beforeName, afterName = segment:match("^name:%s*(.-)%s+%-%>%s+(.-)%s*$")
            if beforeName and afterName then
                beforeName = normalizeRosterMemberName(beforeName)
                afterName = normalizeRosterMemberName(afterName)
                if beforeName ~= afterName then details[#details + 1] = "name: " .. beforeName .. " -> " .. afterName end
            else
                details[#details + 1] = normalizeRosterNamesInText(segment)
            end
        end
        local normalized = table.concat(details, "; ")
        if normalized ~= record.details then record.details = normalized; changed = changed + 1 end
    end
    return changed
end

function Audit:StartRosterNameCleanup()
    local roster = OldGodsGuildAuditDB and OldGodsGuildAuditDB.roster
    if not roster or (roster.nameCleanupVersion or 0) >= 2 then return end
    for _, snapshot in pairs(roster.snapshots or {}) do
        for _, member in pairs(snapshot.members or {}) do
            if member.name then member.name = normalizeRosterMemberName(member.name) end
        end
    end
    local events, cleanedEvents, index, changed, removed = roster.events or {}, {}, 1, 0, 0
    local function processBatch()
        local last = math.min(#events, index + 49)
        for eventIndex = index, last do
            local record = events[eventIndex]
            changed = changed + cleanupStoredRosterRecord(record)
            if record.source == "guildRosterComparison" and record.type == "change" and trim(record.details) == "" then
                removed = removed + 1
            else
                cleanedEvents[#cleanedEvents + 1] = record
            end
        end
        index = last + 1
        if index <= #events then
            C_Timer.After(0, processBatch)
        else
            roster.events = cleanedEvents
            roster.nameCleanupVersion = 2
            print(string.format("Old Gods Audit: roster cleanup complete; corrected %d stored field(s) and removed %d false name-change event(s). Run /reload once to write the compact SavedVariables file.", changed, removed))
        end
    end
    processBatch()
end

local function readRosterSnapshot()
    if not IsInGuild() then return nil end
    local expected = GetNumGuildMembers() or 0
    if expected < 1 then return nil end
    local guildKey, guildName, realmName = rosterGuildKey()
    local snapshot = { schemaVersion = 1, guildKey = guildKey, guildName = guildName, realm = realmName, capturedAt = GetServerTime(), members = {} }
    snapshot.ranks = {}
    if GuildControlGetNumRanks and GuildControlGetRankName then
        for index = 1, math.min(GuildControlGetNumRanks() or 0, 20) do
            local rankName = GuildControlGetRankName(index)
            if rankName then snapshot.ranks[#snapshot.ranks + 1] = { index = index - 1, name = rankName } end
        end
    end
    local readCount = 0
    for index = 1, expected do
        local name, rankName, rankIndex, level, classDisplayName, zone, publicNote, officerNote, online, status, classFileName, achievementPoints, achievementRank, isMobile, canSoR, reputation, guid = GetGuildRosterInfo(index)
        if name then
            name = normalizeRosterMemberName(name)
            local key = guid or name:lower()
            snapshot.members[key] = {
                guid = guid, name = name, rankName = rankName or "", rankIndex = rankIndex,
                level = level or 0, className = classDisplayName or "", classFile = classFileName or "",
                zone = zone or "", publicNote = publicNote or "", officerNote = officerNote or "",
                online = online and true or false, status = status or 0, achievementPoints = achievementPoints or 0,
                reputation = reputation, isMobile = isMobile and true or false,
                offlineDays = OldGodsRosterTools and OldGodsRosterTools:OfflineDays(index, online) or nil,
            }
            readCount = readCount + 1
        end
    end
    if readCount < expected then return nil end
    snapshot.memberCount = readCount
    return snapshot
end

local function requestGuildEventLog()
    if not IsInGuild() or not QueryGuildEventLog then return end
    local now = GetTime()
    if lastGuildEventQuery > 0 and now - lastGuildEventQuery < 10 then return end
    lastGuildEventQuery = now
    QueryGuildEventLog()
end

function Audit:CleanupRosterEventDuplicates()
    if not OldGodsGuildAuditDB.roster then return 0 end
    local events = OldGodsGuildAuditDB.roster.events or {}
    local cleaned, seen, removed = {}, {}, 0
    for _, record in ipairs(events) do
        if record.source == "guildEventLog" then
            local stableID = table.concat({
                record.guildKey or "", record.rawType or record.type or "", record.actor or "", record.target or "",
                record.rankName or "", tostring(math.floor((record.timestamp or 0) / 3600)),
            }, "|")
            if not seen[stableID] then
                seen[stableID] = true
                record.id = stableID
                cleaned[#cleaned + 1] = record
            else
                removed = removed + 1
            end
        else
            cleaned[#cleaned + 1] = record
        end
    end
    table.sort(cleaned, function(left, right) return (left.timestamp or 0) > (right.timestamp or 0) end)
    OldGodsGuildAuditDB.roster.events = cleaned
    OldGodsGuildAuditDB.roster.seenGuildEvents = seen
    return removed
end
function Audit:ImportGuildEventLog()
    if not GetNumGuildEvents or not GetGuildEventInfo or not OldGodsGuildAuditDB.roster then return end
    local duplicatesRemoved = self:CleanupRosterEventDuplicates()
    local guildKey, guildName, realmName = rosterGuildKey()
    local events = OldGodsGuildAuditDB.roster.events
    local seen = OldGodsGuildAuditDB.roster.seenGuildEvents
    local added = 0
    for index = 1, (GetNumGuildEvents() or 0) do
        local rawType, player1, player2, rankName, year, month, day, hour = GetGuildEventInfo(index)
        if rawType then
            player1 = player1 and normalizeRosterMemberName(player1)
            player2 = player2 and normalizeRosterMemberName(player2)
            local timestamp = bankAbsoluteTimestamp(year, month, day, hour)
            local id = table.concat({ guildKey, rawType, player1 or "", player2 or "", rankName or "", tostring(math.floor(timestamp / 3600)) }, "|")
            if not seen[id] then
                local eventType, player, details
                if rawType == "join" then
                    eventType, player, details = "join", player1 or "Unknown", "Joined the guild"
                elseif rawType == "invite" then
                    eventType, player = "join", player2 or "Unknown"
                    details = string.format("Invited to the guild by %s", player1 or "Unknown")
                elseif rawType == "quit" then
                    eventType, player, details = "leave", player1 or "Unknown", "Left the guild"
                elseif rawType == "remove" then
                    eventType, player = "leave", player2 or "Unknown"
                    details = string.format("Removed from the guild by %s", player1 or "Unknown")
                elseif rawType == "promote" then
                    eventType, player = "change", player2 or "Unknown"
                    details = string.format("Promoted by %s%s", player1 or "Unknown", rankName and (" to " .. rankName) or "")
                elseif rawType == "demote" then
                    eventType, player = "change", player2 or "Unknown"
                    details = string.format("Demoted by %s%s", player1 or "Unknown", rankName and (" to " .. rankName) or "")
                end
                if eventType then
                    table.insert(events, 1, {
                        schemaVersion = 1, id = id, timestamp = timestamp, guildKey = guildKey, guildName = guildName, realm = realmName,
                        type = eventType, rawType = rawType, player = player, actor = player1, target = player2, rankName = rankName,
                        details = details, detectedBy = UnitName("player") or "Unknown", source = "guildEventLog", syncStatus = "pendingUpload",
                    })
                    seen[id] = true
                    added = added + 1
                end
            end
        end
    end
    table.sort(events, function(left, right) return (left.timestamp or 0) > (right.timestamp or 0) end)
    while #events > 5000 do table.remove(events) end
    if self.eventLogPage and self.eventLogPage.status and (added > 0 or duplicatesRemoved > 0) then
        self.eventLogPage.status:SetText(string.format("Imported %d guild event(s); removed %d duplicate(s).", added, duplicatesRemoved))
    end
    if self.currentTab == "Event Log" then self:RenderRosterEventPage() end
end
local function addRosterEvent(eventType, member, details, before, after, snapshot)
    local events = OldGodsGuildAuditDB.roster.events
    table.insert(events, 1, {
        schemaVersion = 1, id = string.format("roster-%d-%s-%s", GetServerTime(), eventType, (member.guid or member.name or "unknown")),
        timestamp = GetServerTime(), guildKey = snapshot.guildKey, guildName = snapshot.guildName, realm = snapshot.realm,
        type = eventType, player = member.name or "Unknown", guid = member.guid, details = details,
        before = before, after = after, detectedBy = UnitName("player") or "Unknown",
        source = "guildRosterComparison", syncStatus = "pendingUpload",
    })
    while #events > 5000 do table.remove(events) end
end

function Audit:CaptureRosterSnapshot(quiet)
    local snapshot = readRosterSnapshot()
    if not snapshot then return end
    local previous = OldGodsGuildAuditDB.roster.snapshots[snapshot.guildKey]
    if previous and previous.members then
        local oldCount = previous.memberCount or 0
        local difference = math.abs((snapshot.memberCount or 0) - oldCount)
        local suspiciousThreshold = math.max(10, math.floor(oldCount * 0.10))
        if oldCount > 0 and difference >= suspiciousThreshold then
            local signature = snapshot.guildKey .. ":" .. tostring(snapshot.memberCount)
            if rosterDiscrepancyState and rosterDiscrepancyState.signature == signature then
                rosterDiscrepancyState.attempts = rosterDiscrepancyState.attempts + 1
            else
                rosterDiscrepancyState = { signature = signature, attempts = 1 }
            end
            if rosterDiscrepancyState.attempts < 3 then
                if self.rosterPage and self.rosterPage.status then
                    self.rosterPage.status:SetText(string.format("Roster changed unexpectedly by %d members. Verifying (%d/3)...", difference, rosterDiscrepancyState.attempts))
                end
                C_Timer.After(5, function()
                    if IsInGuild() then C_GuildInfo.GuildRoster(); Audit:ScheduleRosterCapture() end
                end)
                return
            end
        end
        rosterDiscrepancyState = nil
        for key, member in pairs(snapshot.members) do
            local old = previous.members[key]
            if not old then
                addRosterEvent("join", member, "Joined the guild", nil, member, snapshot)
            else
                old.name = normalizeRosterMemberName(old.name)
                local changes = {}
                local fields = {
                    { "name", "name" }, { "rankName", "rank" }, { "level", "level" }, { "className", "class" },
                    { "publicNote", "public note" }, { "officerNote", "officer note" },
                }
                for _, field in ipairs(fields) do
                    local keyName, label = field[1], field[2]
                    if old[keyName] ~= member[keyName] then
                        changes[#changes + 1] = string.format("%s: %s -> %s", label, tostring(old[keyName] or ""), tostring(member[keyName] or ""))
                    end
                end
                if #changes > 0 then addRosterEvent("change", member, table.concat(changes, "; "), old, member, snapshot) end
            end
        end
        for key, member in pairs(previous.members) do
            if not snapshot.members[key] then addRosterEvent("leave", member, "Left or was removed from the guild", member, nil, snapshot) end
        end
    end
    OldGodsGuildAuditDB.roster.snapshots[snapshot.guildKey] = snapshot
    if not quiet and self.currentTab == "Roster" then self:RenderRosterPage() end
    if not quiet and self.currentTab == "Event Log" then self:RenderRosterEventPage() end
end

function Audit:ScheduleRosterCapture()
    if rosterCaptureTimer then rosterCaptureTimer:Cancel() end
    rosterCaptureTimer = C_Timer.NewTimer(0.75, function()
        rosterCaptureTimer = nil
        Audit:CaptureRosterSnapshot()
    end)
end

local function clearPageWidgets(page)
    for _, widget in ipairs(page.dynamicWidgets or {}) do widget:Hide() end
    page.dynamicWidgets = {}
end

local function rosterSearchMatches(member, search)
    if OldGodsRosterTools then return OldGodsRosterTools:Matches(member, search, rosterSearchMode) end
    if search == "" then return true end
    local name = (member.name or ""):lower()
    local notes = ((member.publicNote or "") .. " " .. (member.officerNote or "")):lower()
    if rosterSearchMode == "name" then return name:find(search, 1, true) ~= nil end
    if rosterSearchMode == "notes" then return notes:find(search, 1, true) ~= nil end
    return name:find(search, 1, true) ~= nil or notes:find(search, 1, true) ~= nil
end

local function createSecureRosterButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,BackdropTemplate")
    button:SetSize(width or 105, 26)
    button:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    button:SetBackdropColor(0.18, 0.20, 0.24, 1); button:SetBackdropBorderColor(0.45, 0.50, 0.60, 1)
    local labelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("CENTER"); button:SetFontString(labelText); button:SetText(label)
    button:SetAttribute("type", "macro")
    return button
end

local guildRankBindingOwner = CreateFrame("Frame", "OldGodsGuildAuditRankBindingOwner", UIParent)
local pendingGuildRank

local function clearGuildRankBinding()
    if InCombatLockdown and InCombatLockdown() then
        if pendingGuildRank then pendingGuildRank.cancel = true end
        return
    end
    if ClearOverrideBindings then ClearOverrideBindings(guildRankBindingOwner) end
    pendingGuildRank = nil
end

function Audit:UpdatePendingGuildActions()
    if OldGodsRosterTools and OldGodsRosterTools.guildKey then OldGodsRosterTools:Update() end
    if InCombatLockdown and InCombatLockdown() then return end
    if pendingGuildRank and pendingGuildRank.cancel then clearGuildRankBinding() end
    if not pendingGuildRemoveName and not pendingGuildRank then return end
    local count = GetNumGuildMembers() or 0
    if count < 1 then return end
    local roster = {}
    for index = 1, count do
        local name, _, rank = GetGuildRosterInfo(index)
        -- Do not treat incomplete or restricted roster data as confirmed removal.
        if not isPublicString(name) or not isPublicValue(rank) or rank == nil then return end
        roster[name] = rank
    end
    if pendingGuildRank and roster[pendingGuildRank.name] ~= pendingGuildRank.rankIndex then
        clearGuildRankBinding()
        print("Old Gods Audit: Roster rank changed or member left; temporary rank binding cleared.")
    end
    if not pendingGuildRemoveName then return end
    local remaining = {}
    for _, name in ipairs(pendingGuildRemoveBatch) do
        if roster[name] ~= nil then remaining[#remaining + 1] = name
        else print("Old Gods Audit: Roster confirms "..name.." is no longer in the guild.") end
    end
    if #remaining == 0 then
        if #pendingGuildRemoveQueue > 0 then advanceGuildRemoveQueue()
        else clearGuildRemoveBinding(("Guild member removed; temporary Ctrl+Shift+K binding cleared."):gsub("Ctrl%+Shift%+K", cleanupKeyLabel())) end
    elseif #remaining < #pendingGuildRemoveBatch then
        local ok, reason = bindGuildRemoveTarget(remaining[1], remaining)
        if not ok then clearGuildRemoveBinding("Could not prepare remaining kick targets: " .. tostring(reason)); return end
        print("Old Gods Audit: Still in this kick batch: " .. table.concat(remaining, ", ") .. (". Ctrl+Shift+K is ready to retry these members, or cancel the queue."):gsub("Ctrl%+Shift%+K", cleanupKeyLabel()))
    end
end

function Audit:ConfigureRosterMemberActions(member)
    local page = self.rosterPage
    if not page or not page.rosterBuilt then return end
    if pendingGuildRank and (not member or member.name ~= pendingGuildRank.name) then clearGuildRankBinding() end
    selectedRosterMember = member
    page.focusedMember=member
    page.copyNameButton:SetEnabled(member~=nil)
    page.selectedText:SetText(member and ("Player: "..member.name) or "Click a player for notes and event history.")
end
function Audit:ClassColoredRosterName(member)
    local name = isPublicString(member.name) and member.name or "Unknown"
    local link=OldGodsCharacters and OldGodsCharacters:Link(member.name)
    if link then name=(link.role=="Main" and "[M] " or "[A] ")..name end
    -- Pastel class colors lose contrast on the two bright themes.
    if OldGodsGuildAuditDB.theme=="light" or OldGodsGuildAuditDB.theme=="hotDogStand" then return name end
    local classFile = member.classFile
    if not isPublicString(classFile) then return name end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    local hex = color and color.colorStr
    if isPublicString(hex) and hex:match("^%x%x%x%x%x%x%x%x$") then return "|c" .. hex .. name .. "|r" end
    return name
end
function Audit:RenderRosterPage()
    local page = self.rosterPage
    if not page or not page.rosterBuilt or not OldGodsGuildAuditDB.roster then return end
    clearPageWidgets(page)
    if page.modeButton.RefreshLabel then page.modeButton:RefreshLabel() end
    if OldGodsRosterTools then OldGodsRosterTools:SyncGuild(); OldGodsRosterTools:RenderControls() end
    local guildKey = rosterGuildKey()
    local snapshot = OldGodsGuildAuditDB.roster.snapshots[guildKey]
    local search = (page.searchInput:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local members = {}
    if snapshot then
        for _, member in pairs(snapshot.members or {}) do
            if OldGodsRosterTools and OldGodsRosterTools.selectedOnly then
                if OldGodsRosterTools.selected[OldGodsRosterTools:Key(member)] then members[#members + 1] = member end
            elseif rosterSearchMatches(member, search) and (not OldGodsRosterTools.inactiveDays or
                (member.offlineDays and member.offlineDays >= OldGodsRosterTools.inactiveDays and member.rankIndex and member.rankIndex >= 2)) then members[#members + 1] = member end
        end
        if OldGodsRosterTools and OldGodsRosterTools.selectedOnly then
            local shown = {}
            for _, member in ipairs(members) do shown[OldGodsRosterTools:Key(member)] = true end
            for key, member in pairs(OldGodsRosterTools.selected) do
                if not shown[key] then
                    members[#members + 1] = {name=member.name, guid=member.guid, rankName="No longer in roster", level=0, className="", publicNote="Uncheck this unavailable member", officerNote=""}
                end
            end
        end
        if OldGodsRosterTools then OldGodsRosterTools:Sort(members) else table.sort(members, function(a,b) return (a.name or "") < (b.name or "") end) end
    end
    -- Filter and sort the full snapshot before slicing; selection remains guild-wide.
    local tools = OldGodsRosterTools or {}
    local viewKey = table.concat({guildKey or "", search, rosterSearchMode or "all", tostring(tools.selectedOnly), tostring(tools.inactiveDays), tools.sortKey or "name", tostring(tools.sortDescending)}, "\031")
    if page.rosterViewKey ~= viewKey then
        page.rosterPageNumber = 1
        page.rosterViewKey = viewKey
    end
    local pageSize = 50
    local pageCount = math.max(1, math.ceil(#members / pageSize))
    page.rosterPageNumber = math.max(1, math.min(page.rosterPageNumber or 1, pageCount))
    local first = (page.rosterPageNumber - 1) * pageSize + 1
    local last = math.min(#members, first + pageSize - 1)
    if page.rosterFirst ~= first or page.rosterLastViewKey ~= viewKey then
        if page.scroll then page.scroll:SetVerticalScroll(0) end
    end
    page.rosterFirst, page.rosterLastViewKey = first, viewKey
    if page.rosterPrevious then page.rosterPrevious:SetEnabled(page.rosterPageNumber > 1) end
    if page.rosterNext then page.rosterNext:SetEnabled(page.rosterPageNumber < pageCount) end
    local y = -4
    page.rowPool = page.rowPool or {}
    for index = first, last do
        local slot = index - first + 1
        local member = members[index]
        local selectedMember = member
        local row = page.rowPool[slot]
        if not row then
            row = CreateFrame("Button", nil, page.content, "BackdropTemplate")
            row.lines = {}
            page.rowPool[slot] = row
        end
        row:Show()
        row:SetPoint("TOPLEFT", 0, y); row:SetSize(math.max(850,page.content:GetWidth()), 30)
        row:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        row.oldGodsRosterRow=true; row.oldGodsRosterMember=member
        if OldGodsRosterTools then
            local check = row.check
            if not check then
                check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.check = check
            end
            check:SetSize(26, 26); check:SetPoint("LEFT", 3, 0)
            if OldGodsUI then OldGodsUI.Help(check,"Select player") end
            check:SetChecked(OldGodsRosterTools.selected[OldGodsRosterTools:Key(member)] ~= nil)
            check:SetScript("OnClick", function(self) OldGodsRosterTools:Toggle(selectedMember, self:GetChecked()) end)
        end
        local x=34
        local values={name=self:ClassColoredRosterName(member),rankName=member.rankName,level=tostring(member.level or ""),className=member.className,zone=member.zone or "Unknown",achievementPoints=tostring(member.achievementPoints or "Unknown"),faction=member.faction or "Unknown",publicNote=member.publicNote or ""}
        for i,column in ipairs(OldGodsRosterTools.columns) do
            local line=row.lines[i]
            if not line then
                line=row:CreateFontString(nil,"OVERLAY","GameFontHighlight")
                row.lines[i]=line
            end
            line:SetPoint("LEFT",x,0); line:SetWidth(column[3]-6); line:SetJustifyH("LEFT"); line:SetText(values[column[1]] or ""); x=x+column[3]
        end
        OldGodsRosterTools:StyleRow(row,false)
        row:SetScript("OnEnter", function(self) OldGodsRosterTools:StyleRow(self,true); OldGodsRosterTools:Tooltip(self, selectedMember) end)
        row:SetScript("OnLeave", function(self) OldGodsRosterTools:StyleRow(self,false); if GameTooltip then GameTooltip:Hide() end end)
        row:SetScript("OnClick", function() Audit:ConfigureRosterMemberActions(selectedMember) end)
        page.dynamicWidgets[#page.dynamicWidgets + 1] = row
        y = y - 32
    end
    page.content:SetHeight(math.max(1, -y + 8))
    if snapshot then page.status:SetText(string.format("Showing %d–%d of %d matches (%d members) | Page %d/%d", #members > 0 and first or 0, last, #members, snapshot.memberCount or 0, page.rosterPageNumber, pageCount))
    else page.status:SetText("Waiting for a complete guild roster. Click Refresh Roster.") end
end

function Audit:ChangeRosterPage(delta)
    local page = self.rosterPage
    if not page then return end
    page.rosterPageNumber = (page.rosterPageNumber or 1) + delta
    self:RenderRosterPage()
end

function Audit:SearchRoster(clear)
    local page = self.rosterPage
    page.rosterPageNumber = 1
    if clear then page.searchInput:SetText("") end
    page.searchInput:ClearFocus()
    if trim(page.searchInput:GetText()) == "" then
        if page.scroll then page.scroll:SetVerticalScroll(0) end
        C_GuildInfo.GuildRoster(); self:ScheduleRosterCapture()
    end
    self:RenderRosterPage()
end

function Audit:BuildRosterPage(page)
    page.heading:Hide(); page.body:Hide(); page.rosterBuilt = true; page.extraTexts = page.extraTexts or {}; page.dynamicWidgets = {}
    page.body:SetText('Search, check players, then choose an action. Hover controls for help. Commas = OR; spaces = AND; quotes = phrases.')
    page.searchInput = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    page.searchInput:SetSize(220, 27); page.searchInput:SetPoint("TOPLEFT", 24, -24); page.searchInput:SetAutoFocus(false); page.searchInput:SetMaxLetters(1000)
    page.searchInput:SetScript("OnEnterPressed", function() Audit:SearchRoster(false) end)
    OldGodsUI.Help(page.searchInput,"Roster search")
    local searchButton = OldGodsRosterTools:IconButton(page, createButton, "Search", "search", function() Audit:SearchRoster(false) end); searchButton:SetPoint("LEFT", page.searchInput, "RIGHT", 8, 0)
    local clearSearch = OldGodsRosterTools:IconButton(page, createButton, "Clear search", "clear", function() Audit:SearchRoster(true) end); clearSearch:SetPoint("LEFT", searchButton, "RIGHT", 4, 0)
    page.modeButton = OldGodsUI.Dropdown(page, "Search fields", {{"all","All"},{"name","Name"},{"notes","Notes"}}, function() return rosterSearchMode end, function(value) rosterSearchMode=value; Audit:RenderRosterPage() end,180)
    page.modeButton:SetPoint("LEFT",clearSearch,"RIGHT",8,0)
    local refresh = OldGodsRosterTools:IconButton(page, createButton, "Refresh Roster", "refresh", function() C_GuildInfo.GuildRoster(); requestGuildEventLog(); Audit:ScheduleRosterCapture() end); refresh:SetPoint("LEFT", page.modeButton, "RIGHT", 8, 0)
    local characters=createButton(page,"My Characters",function() OldGodsCharacters:Open() end,130); characters:SetPoint("TOPRIGHT",-24,-24)
    local tools
    tools=createButton(page,"Player tools",function()
        OldGodsUI.Choose(tools,{{"public","Copy Public Note"},{"officer","Copy Officer Note"},{"roster","Open Roster"},{"bans","Open Ban List"}},function(value)
            local member=page.focusedMember
            if value=="roster" then openGuildRoster(); return end
            if not member then OldGodsRosterTools.message="Click a player before using their notes or ban history."; Audit:RenderRosterPage(); return end
            if value=="bans" then OldGodsFeedback.OpenBans(select(2,OldGodsFeedback.NameKey(member.name)))
            else showCopyBox(value=="public" and (member.publicNote or "") or (member.officerNote or "")) end
        end)
    end,110); tools:SetPoint("LEFT",refresh,"RIGHT",8,0)
    page.copyNameButton=createButton(page,"Copy Name",function() if page.focusedMember then showCopyBox(page.focusedMember.name) end end,95)
    page.copyNameButton:SetPoint("BOTTOMLEFT",24,36); page.copyNameButton:SetEnabled(false)
    page.selectedText=page:CreateFontString(nil,"OVERLAY","GameFontNormal")
    page.selectedText:SetPoint("LEFT",page.copyNameButton,"RIGHT",10,0); page.selectedText:SetWidth(650); page.selectedText:SetJustifyH("LEFT")
    page.selectedText:SetText("Click a player for notes and event history."); page.extraTexts[#page.extraTexts+1]=page.selectedText
    page.viewEvents=function(member)
        Audit.eventLogPage.searchInput:SetText(member and member.name or ""); Audit:SelectTab("Event Log")
    end
    if OldGodsRosterTools then
        OldGodsRosterTools.guildKey = rosterGuildKey
        OldGodsRosterTools.render = function() Audit:RenderRosterPage() end
        OldGodsRosterTools.clearOtherBindings = function() clearGuildRankBinding(); clearGuildRemoveBinding() end
        OldGodsRosterTools:BuildControls(page, createButton)
    end
    page.status = page:CreateFontString(nil, "OVERLAY", "GameFontNormal"); page.status:SetPoint("BOTTOMLEFT", 24, 12); page.status:SetWidth(550); page.status:SetJustifyH("LEFT"); page.extraTexts[#page.extraTexts + 1] = page.status
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate"); page.scroll:SetPoint("TOPLEFT", 24, -194); page.scroll:SetPoint("BOTTOMRIGHT", -42, 78)
    page.content = CreateFrame("Frame", nil, page.scroll); page.content:SetSize(850, 1); page.scroll:SetScrollChild(page.content)
    page.rosterPrevious = OldGodsRosterTools:IconButton(page,createButton,"Previous page","previous",function() Audit:ChangeRosterPage(-1) end)
    page.rosterPrevious:SetPoint("BOTTOMLEFT", 792, 6)
    page.rosterNext = OldGodsRosterTools:IconButton(page,createButton,"Next page","next",function() Audit:ChangeRosterPage(1) end)
    page.rosterNext:SetPoint("LEFT", page.rosterPrevious, "RIGHT", 8, 0)
    OldGodsUI.Help(page.rosterPrevious, "Previous page", "Show the previous 50 matching members. Checked players stay selected across pages.")
    OldGodsUI.Help(page.rosterNext, "Next page", "Show the next 50 matching members. Search and sorting cover the full guild roster.")
    OldGodsRosterTools:BuildTableHeader(page, createButton)

    page:HookScript("OnHide", clearGuildRankBinding)
    page:HookScript("OnHide", function() if OldGodsRosterTools then OldGodsRosterTools:Cancel() end end)
    self:RenderRosterPage()
end

local function rosterEventMatches(record, search, guildKey)
    if record.guildKey ~= guildKey then return false end
    if rosterEventFilter ~= "all" and record.type ~= rosterEventFilter then return false end
    if Audit.eventCategory and Audit.eventCategory ~= "All" and OldGodsFeedback.EventCategory(record) ~= Audit.eventCategory then return false end
    if Audit.eventPriority and Audit.eventPriority ~= "all" and OldGodsFeedback.EventStatus(record) ~= Audit.eventPriority then return false end
    if search == "" then return true end
    local label=record.type=="join" and "joined the guild" or record.type=="leave" and "left the guild" or ""
    return ((record.player or "") .. " " .. (record.details or "") .. " " .. (record.type or "") .. " " .. label):lower():find(search, 1, true) ~= nil
end

function Audit:RenderRosterEventPage()
    local page = self.eventLogPage
    if not page or not page.eventLogBuilt or not OldGodsGuildAuditDB.roster then return end
    clearPageWidgets(page)
    page.filterButton:RefreshLabel()
    local search = (page.searchInput:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local guildKey = rosterGuildKey()
    local matching = {}
    for _, record in ipairs(OldGodsGuildAuditDB.roster.events or {}) do
        if rosterEventMatches(record, search, guildKey) then matching[#matching + 1] = record end
    end
    table.sort(matching,function(a,b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    local pageCount = math.max(1, math.ceil(#matching / ROSTER_EVENT_PAGE_SIZE))
    rosterEventPageNumber = math.max(1, math.min(rosterEventPageNumber, pageCount))
    local first = ((rosterEventPageNumber - 1) * ROSTER_EVENT_PAGE_SIZE) + 1
    local last = math.min(#matching, first + ROSTER_EVENT_PAGE_SIZE - 1)
    local y = -4
    for index = first, last do
        local record = matching[index]
        local slot = index-first+1
        page.eventLines = page.eventLines or {}
        local line = page.eventLines[slot]
        if not line then
            line = page.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            page.eventLines[slot] = line
        end
        line:Show()
        local _, priority = OldGodsFeedback.EventStatus(record)
        line:SetPoint("TOPLEFT", 4, y); line:SetWidth(665); line:SetJustifyH("LEFT")
        line:SetText(string.format("|c%s[%s]|r %s | %s\n%s | %s | %s", priority.color, priority.label, OldGodsFeedback.EventCategory(record), date("%Y-%m-%d %H:%M:%S", record.timestamp), (record.type or "unknown"):upper(), record.player or "Unknown", record.details or ""))
        page.dynamicWidgets[#page.dynamicWidgets + 1] = line
        page.completionButtons = page.completionButtons or {}
        local done = page.completionButtons[slot]
        if not done then done=createButton(page.content,"Complete",nil,105); page.completionButtons[slot]=done end
        done:SetText(record.reviewStatus == "completed" and "Reopen" or "Complete")
        OldGodsUI.Help(done,record.reviewStatus == "completed" and "Reopen" or "Complete")
        done:SetScript("OnClick",function()
            if record.guildKey ~= rosterGuildKey() then Audit:RenderRosterEventPage(); return end
            OldGodsFeedback.SetEventCompleted(record); Audit:RenderRosterEventPage()
        end); done:ClearAllPoints(); done:SetPoint("TOPLEFT",690,y); done:SetEnabled(OldGodsChapterSettings.CanEdit()); done:Show()
        page.dynamicWidgets[#page.dynamicWidgets+1]=done
        y = y - math.max(40, line:GetStringHeight() + 12)
    end
    page.content:SetHeight(math.max(1, -y + 8))
    page.previousButton:SetEnabled(rosterEventPageNumber > 1)
    page.nextButton:SetEnabled(rosterEventPageNumber < pageCount)
    page.status:SetText(string.format("Showing %d-%d of %d matching event(s) | Page %d of %d | %d total stored.", #matching > 0 and first or 0, last, #matching, rosterEventPageNumber, pageCount, #(OldGodsGuildAuditDB.roster.events or {})))
end

function Audit:BuildRosterEventPage(page)
    page.eventLogBuilt = false; page.extraTexts = page.extraTexts or {}; page.dynamicWidgets = {}
    page.body:SetText("Red: attention | Amber: follow up | Blue: contact | Green: completed | Gray: information.\nReview status is saved locally; departures are not automatically misconduct.")
    page.searchInput = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    page.searchInput:SetSize(300, 27); page.searchInput:SetPoint("TOPLEFT", 24, -105); page.searchInput:SetAutoFocus(false); page.searchInput:SetMaxLetters(100)
    page.searchInput:SetScript("OnEnterPressed", function(self) self:ClearFocus(); rosterEventPageNumber = 1; Audit:RenderRosterEventPage() end)
    OldGodsUI.Help(page.searchInput,"Event search")
    local searchButton = createButton(page, "Search", function() rosterEventPageNumber = 1; Audit:RenderRosterEventPage() end, 85); searchButton:SetPoint("LEFT", page.searchInput, "RIGHT", 8, 0)
    page.filterButton = OldGodsUI.Dropdown(page, "Type", {{"all","All"},{"join","Joined"},{"leave","Left"},{"change","Changed"},{"recruit","Recruited"},{"blocked","Blocked"},{"failed","Failed"}}, function() return rosterEventFilter end, function(value) rosterEventFilter=value; rosterEventPageNumber=1; Audit:RenderRosterEventPage() end,170)
    page.filterButton:SetPoint("LEFT",searchButton,"RIGHT",8,0)
    local clear = createButton(page,"Clear",function() page.searchInput:SetText(""); page.searchInput:ClearFocus(); rosterEventPageNumber=1; Audit:RenderRosterEventPage() end,70)
    clear:SetPoint("TOPLEFT",485,-144)
    local refresh = createButton(page, "Refresh Events", function() C_GuildInfo.GuildRoster(); requestGuildEventLog(); Audit:ScheduleRosterCapture() end, 130); refresh:SetPoint("LEFT", page.filterButton, "RIGHT", 8, 0)
    page.previousButton = createButton(page, "Previous", function() rosterEventPageNumber = math.max(1, rosterEventPageNumber - 1); Audit:RenderRosterEventPage() end, 90); page.previousButton:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    page.nextButton = createButton(page, "Next", function() rosterEventPageNumber = rosterEventPageNumber + 1; Audit:RenderRosterEventPage() end, 75); page.nextButton:SetPoint("LEFT", page.previousButton, "RIGHT", 8, 0)
    local category=OldGodsUI.Dropdown(page,"Category",{{"All","All"},{"Membership","Membership"},{"Recruiting","Recruiting"},{"Notes","Notes"},{"Administration","Administration"}},function() return Audit.eventCategory or "All" end,function(value) Audit.eventCategory=value; rosterEventPageNumber=1; Audit:RenderRosterEventPage() end,205)
    category:SetPoint("TOPLEFT",24,-144)
    local priority=OldGodsUI.Dropdown(page,"Priority",{{"all","All"},{"attention","Attention"},{"followup","Follow up"},{"contact","Contact"},{"completed","Completed"},{"info","Information"}},function() return Audit.eventPriority or "all" end,function(value) Audit.eventPriority=value; rosterEventPageNumber=1; Audit:RenderRosterEventPage() end,240)
    priority:SetPoint("LEFT",category,"RIGHT",8,0)
    page.status = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    page.status:SetPoint("TOPLEFT", 24, -184); page.status:SetWidth(830); page.status:SetJustifyH("LEFT")
    page.extraTexts[#page.extraTexts + 1] = page.status
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", 24, -214); page.scroll:SetPoint("BOTTOMRIGHT", -42, 20)
    page.content = CreateFrame("Frame", nil, page.scroll)
    page.content:SetSize(810, 1); page.scroll:SetScrollChild(page.content)
    -- Saved events may exist at startup; render only after every required widget exists.
    page.eventLogBuilt = true
    self:RenderRosterEventPage()
end
function Audit:BuildRecruitingPage(page)
    page.heading:Hide(); page.body:Hide()
    page.extraTexts={}; page.candidateLines={}; page.currentSubtab="Search"
    page:HookScript("OnShow",function() Audit:RenderRecruitingCandidates() end)
    page.searchTab=createButton(page,"Search",function() Audit:RenderRecruitingCandidates() end,120)
    page.searchTab:SetPoint("TOPLEFT",24,-14); page.searchTab:SetEnabled(false); page.searchTab.oldGodsHelpKey="Recruiting search"
    local alerts=OldGodsUI.Dropdown(page,"Applicant alerts",{{"Sound","Sound"},{"Popup","Popup"},{"Both","Both"}},function() return OldGodsChapterSettings.Mode() end,function(value) OldGodsChapterSettings.Mode(value) end,230)
    alerts:SetPoint("LEFT",page.searchTab,"RIGHT",8,0)
    local bans=createButton(page,"Ban List",function() OldGodsFeedback.OpenBans() end,105); bans:SetPoint("LEFT",alerts,"RIGHT",8,0)
    local compact=createButton(page,"Compact Recruiter",function() Audit:ToggleCompactRecruiting() end,160); compact:SetPoint("LEFT",bans,"RIGHT",8,0)
    page.population=page:CreateFontString(nil,"OVERLAY","GameFontNormalHuge"); page.population:SetPoint("TOPLEFT",24,-52); page.population:SetWidth(700); page.population:SetJustifyH("LEFT")
    page.extraTexts={page.population}
    local indicator=CreateFrame("Button",nil,page); page.statusIndicator=indicator
    indicator:SetSize(24,24); indicator:SetPoint("TOPRIGHT",-24,-15); indicator.oldGodsHelpHooked=true; indicator.oldGodsStatusIndicator=true
    indicator.dot=indicator:CreateTexture(nil,"ARTWORK"); indicator.dot:SetAllPoints(); indicator.dot.oldGodsAsset=true
    if indicator.CreateMaskTexture then
        indicator.dot:SetColorTexture(1,1,1,1)
        local mask=indicator:CreateMaskTexture(); mask:SetAllPoints(indicator.dot)
        mask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask","CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
        indicator.dot:AddMaskTexture(mask); indicator.mask=mask
    else indicator.dot:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask") end
    indicator.lens=indicator:CreateTexture(nil,"OVERLAY"); indicator.lens:SetAllPoints()
    indicator.lens:SetTexture("Interface\\AddOns\\OldGodsGuildAudit\\Assets\\Icons\\status-lens.tga")
    indicator.lens.oldGodsAsset=true
    indicator:SetScript("OnEnter",function(self)
        self.tooltipShown=true
        if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_RIGHT") end
        Audit:UpdateRecruitingStatus()
    end)
    indicator:SetScript("OnLeave",function(self) self.tooltipShown=false; if GameTooltip then GameTooltip:Hide() end end)
    local elapsed=0
    indicator:SetScript("OnUpdate",function(_,delta) elapsed=elapsed+delta; if elapsed>=0.2 then elapsed=0; if indicator.tooltipShown then Audit:UpdateRecruitingStatus() end end end)
    page.candidatePrevious=createButton(page,"Previous",function() page.candidatePage=math.max(1,(page.candidatePage or 1)-1); Audit:RenderRecruitingCandidates() end,85); page.candidatePrevious:SetPoint("TOPLEFT",24,-90)
    page.candidateNext=createButton(page,"Next",function() page.candidatePage=(page.candidatePage or 1)+1; Audit:RenderRecruitingCandidates() end,70); page.candidateNext:SetPoint("LEFT",page.candidatePrevious,"RIGHT",8,0)
    page.candidatePageLabel=page:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); page.candidatePageLabel:SetPoint("LEFT",page.candidateNext,"RIGHT",8,0)
    page.candidateScroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate"); page.candidateScroll:SetPoint("TOPLEFT",24,-130); page.candidateScroll:SetPoint("BOTTOMRIGHT",-42,80)
    page.candidateContent=CreateFrame("Frame",nil,page.candidateScroll); page.candidateContent:SetSize(810,1); page.candidateScroll:SetScrollChild(page.candidateContent)
    local search=createButton(page,"Search",function() Audit:ContinueWhoScan() end,180); page.allZonesButton=search; search.oldGodsHelpKey="Recruiting search"; search:SetPoint("BOTTOM",page,"BOTTOM",-128,20)
    local invite=createButton(page,"Prepare Invite",function() OldGodsRecruiting:Clicked() end,130,nil,true); page.inviteButton=invite; invite:SetPoint("LEFT",search,"RIGHT",8,0)
    local clear=createButton(page,"Clear List",function() OldGodsRecruiting:Cancel(); wipe(recruitingCandidates); page.candidatePage=1; Audit:RenderRecruitingCandidates() end,110); clear:SetPoint("LEFT",invite,"RIGHT",8,0)
    local copyLog=createButton(page,"Copy Last Scan Log",function()
        local saved=OldGodsGuildAuditDB.recruitingLogs and OldGodsGuildAuditDB.recruitingLogs[1]
        local text=whoScanActive and currentWhoLogText() or (saved and saved.text)
        if text and text~="" then showCopyBox(text) else print("Old Gods Audit: No recruiting scan log is available yet.") end
    end,150); copyLog:SetPoint("BOTTOMLEFT",24,50)
    page.realmOverrideButton=createButton(page,"Ignore Warning for This Character",function() Audit:IgnoreRecruitingRealmWarning() end,285); page.realmOverrideButton:SetPoint("BOTTOMLEFT",24,50); page.realmOverrideButton:Hide()
    -- Keep diagnostic controls out of the centered action row.
    copyLog:ClearAllPoints(); copyLog:SetPoint("BOTTOMRIGHT",-24,50)
    page.realmResetButton=createButton(page,"Reset Saved Realms",function() Audit:ResetRecruitingRealmCache() end,170); page.realmResetButton:SetPoint("BOTTOMLEFT",317,50); page.realmResetButton:Hide()
end

function Audit:BuildQuietZonesPage(page)
    self.quietZonesPage=page
    page.Refresh=function() Audit:RenderQuietZones() end
    local instructions=page:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    instructions:SetPoint("TOPLEFT",0,0); instructions:SetWidth(810); instructions:SetJustifyH("LEFT")
    instructions:SetText("Report a quiet zone below. Guild ranks 0–4 approve changes; built-in zones are always protected.")
    page.zoneInput=CreateFrame("EditBox",nil,page,"InputBoxTemplate"); page.zoneInput:SetPoint("TOPLEFT",0,-48); page.zoneInput:SetSize(330,26); page.zoneInput:SetAutoFocus(false); page.zoneInput:SetMaxLetters(100)
    OldGodsUI.Help(page.zoneInput,"Zone name","Enter the exact zone name. Ranks 0�4 add it immediately; other members submit a report.")
    local report=createButton(page,OldGodsChapterSettings.CanManageQuiet() and "Add Zone" or "Report Zone",function() Audit:AddQuietZone(page.zoneInput:GetText()) end,125); report:SetPoint("LEFT",page.zoneInput,"RIGHT",8,0)
    local current=createButton(page,OldGodsChapterSettings.CanManageQuiet() and "Add Current Zone" or "Report Current Zone",function() Audit:AddQuietZone((GetRealZoneText and GetRealZoneText()) or GetZoneText()) end,175); current:SetPoint("LEFT",report,"RIGHT",8,0)
    page.quietStatus=page:CreateFontString(nil,"OVERLAY","GameFontHighlight"); page.quietStatus:SetPoint("TOPLEFT",0,-88); page.quietStatus:SetWidth(810); page.quietStatus:SetJustifyH("LEFT"); page.quietStatus:SetText("Pending reports do not change filtering until approved.")
    page.quietScroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate"); page.quietScroll:SetPoint("TOPLEFT",0,-120); page.quietScroll:SetPoint("BOTTOMRIGHT",-10,0)
    page.quietContent=CreateFrame("Frame",nil,page.quietScroll); page.quietContent:SetSize(790,1); page.quietScroll:SetScrollChild(page.quietContent)
    return page
end

function Audit:SpazzyStatus(message)
    if self.specialPage then self.specialPage.status:SetText(message) end
    print("Spazzy: " .. message)
end

function Audit:ClearSpazzyBinding()
    self.spazzyArmed = false
    self.spazzyPending = nil
    if InCombatLockdown and InCombatLockdown() then
        self.spazzyClearPending = true
        return
    end
    if self.spazzyBindingOwner and ClearOverrideBindings then ClearOverrideBindings(self.spazzyBindingOwner) end
    self.spazzyClearPending = nil
    if self.specialPage then self.specialPage.bindingStatus:SetText("F12 is not bound to Spazzy.") end
end

function Audit:BindSpazzy()
    if InCombatLockdown and InCombatLockdown() then self:SpazzyStatus("Leave combat before binding F12."); return end
    if not guildBankOpen or self.currentTab ~= "Special" or not self.frame:IsShown() then
        self:SpazzyStatus("Open the guild bank and the Special tab first."); return
    end
    if not GetMacroIndexByName or not GetMacroInfo or not CreateMacro or not SetOverrideBindingMacro then
        self:SpazzyStatus("WoW's macro or binding functions are unavailable."); return
    end
    local body = "/run OldGodsGuildAuditSpazzy()"
    local index = GetMacroIndexByName("Spazzy")
    if index and index > 0 then
        local _, _, existingBody = GetMacroInfo(index)
        if existingBody ~= body then
            self:SpazzyStatus("A different macro named Spazzy already exists. Rename that macro before binding this one."); return
        end
    else
        local count = GetNumMacros and GetNumMacros() or 0
        if MAX_ACCOUNT_MACROS and count >= MAX_ACCOUNT_MACROS then
            self:SpazzyStatus("Free one General Macro slot, then try again."); return
        end
        index = CreateMacro("Spazzy", "INV_Box_PetCarrier_01", body)
    end
    if not index or index == 0 then self:SpazzyStatus("WoW did not create the Spazzy macro."); return end
    self.spazzyBindingOwner = self.spazzyBindingOwner or CreateFrame("Frame")
    local ok, reason = pcall(SetOverrideBindingMacro, self.spazzyBindingOwner, true, "F12", index)
    if not ok then self:ClearSpazzyBinding(); self:SpazzyStatus("Could not bind F12: " .. tostring(reason)); return end
    self.spazzyClearPending = nil
    self.spazzyArmed = true
    self.specialPage.bindingStatus:SetText("F12: Spazzy - one pet per press. Closing the bank or leaving Special restores F12.")
    self:SpazzyStatus("F12 ready. Select bank tab " .. OldGodsChapterSettings.DonationsTab() .. " (Chapter > Bank), then press F12 once per pet.")
end

function Audit:MoveNextDonationPet()
    if InCombatLockdown and InCombatLockdown() then self:SpazzyStatus("Leave combat before moving pets."); return end
    if not guildBankOpen or self.currentTab ~= "Special" or not self.frame:IsShown() then
        self:SpazzyStatus("Open the guild bank and the Special tab first."); return
    end
    if not AutoStoreGuildBankItem or not GetGuildBankItemLink or not GetGuildBankItemInfo or not GetGuildBankTabInfo or not GetCurrentGuildBankTab then
        self:SpazzyStatus("Guild-bank item functions are unavailable."); return
    end
    if GetCursorInfo and GetCursorInfo() then self:SpazzyStatus("Clear the item or money on your cursor first."); return end
    local tabId = OldGodsChapterSettings.DonationsTab()
    if tabId > GetNumGuildBankTabs() then self:SpazzyStatus("Donations tab " .. tabId .. " is missing. Check Chapter > Bank."); return end
    local name, _, canView, _, _, withdrawals = GetGuildBankTabInfo(tabId)
    local label = "Tab " .. tabId .. " — " .. (name or "Unnamed")
    if not canView then self:SpazzyStatus(label .. " is not viewable."); return end
    if withdrawals == 0 then self:SpazzyStatus("No withdrawals remain for " .. label .. "."); return end
    if GetCurrentGuildBankTab() ~= tabId then
        self:SpazzyStatus("Select " .. label .. " in the guild bank and wait for its items to load."); return
    end
    if C_Container and C_Container.GetContainerNumFreeSlots then
        local free = 0
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local slots, family = C_Container.GetContainerNumFreeSlots(bag)
            if family == 0 then free = free + (slots or 0) end
        end
        if free == 0 then self:SpazzyStatus("Make room in a normal bag before moving another pet."); return end
    end
    local pending = self.spazzyPending
    if pending then
        local _, count, locked = GetGuildBankItemInfo(pending.tab, pending.slot)
        local link = GetGuildBankItemLink(pending.tab, pending.slot)
        if link == pending.link and (count or 0) >= pending.count then
            if locked or GetTime() - pending.at < 2 then
                self:SpazzyStatus("Waiting for the previous withdrawal. Press again after the bank updates."); return
            end
        end
        self.spazzyPending = nil
    end
    local lockedPets = false
    for slot = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
        local link = GetGuildBankItemLink(tabId, slot)
        if isPublicString(link) and (link:find("|Hbattlepet:", 1, true) or link:find("|Hitem:82800:", 1, true)) then
            local _, count, locked = GetGuildBankItemInfo(tabId, slot)
            if locked then
                lockedPets = true
            else
                self.spazzyPending = {tab = tabId, slot = slot, link = link, count = count or 1, at = GetTime()}
                -- One user click/keypress issues one native withdrawal; no timer moves items.
                AutoStoreGuildBankItem(tabId, slot)
                self:SpazzyStatus("Requested one pet from " .. label .. ", slot " .. slot .. ". Wait for it to reach your bag, then press again.")
                return
            end
        end
    end
    self:SpazzyStatus(lockedPets and "Pets are locked. Wait for the bank to update and try again." or "No caged pets found in " .. label .. ". If it just opened, wait for the items to load.")
end

-- The named WoW macro invokes this function from a hardware keypress.
function OldGodsGuildAuditSpazzy()
    if Audit.spazzyArmed then Audit:MoveNextDonationPet() end
end

function Audit:BuildSpecialPage(page)
    page.extraTexts = {}
    local function iconSetting(label, key, y)
        local check = CreateFrame("CheckButton",nil,page,"UICheckButtonTemplate")
        check:SetPoint("TOPLEFT",24,y); check:SetChecked(OldGodsGuildAuditDB[key].enabled)
        local text = check.Text or check.text
        if text then text:SetText(label) end
        check:SetScript("OnClick",function() OldGodsGuildAuditDB[key].enabled = check:GetChecked() and true or false; Audit:UpdateLauncherVisibility() end)
        check:SetScript("OnShow",function() check:SetChecked(OldGodsGuildAuditDB[key].enabled) end)
    end
    iconSetting("Show minimap icon", "minimap", -270)
    iconSetting("Show floating icon (drag to move)", "floatingIcon", -305)
    page.body:SetText("Spazzy uses the Donations tab number in Chapter > Bank. Open the guild bank and select that tab. Click Spazzy once per pet, or bind F12 and press it once per pet. Guild withdrawal limits still apply.")
    page.body:SetWidth(850)
    page.body:SetJustifyH("LEFT")
    local move = createButton(page, "Spazzy", function() Audit:MoveNextDonationPet() end, 130)
    move:SetPoint("TOPLEFT", 24, -130)
    local bind = createButton(page, "Bind F12", function() Audit:BindSpazzy() end, 130)
    bind:SetPoint("LEFT", move, "RIGHT", 10, 0)
    local clear = createButton(page, "Release F12", function() Audit:ClearSpazzyBinding() end, 130)
    clear:SetPoint("LEFT", bind, "RIGHT", 10, 0)
    page.bindingStatus = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.bindingStatus:SetPoint("TOPLEFT", 24, -176)
    page.bindingStatus:SetWidth(850)
    page.bindingStatus:SetJustifyH("LEFT")
    page.bindingStatus:SetText("F12 is not bound to Spazzy.")
    page.status = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    page.status:SetPoint("TOPLEFT", 24, -220)
    page.status:SetWidth(850)
    page.status:SetJustifyH("LEFT")
    page.status:SetText("Open the guild bank and select tab " .. OldGodsChapterSettings.DonationsTab() .. " (Chapter > Bank) to begin.")
    page.extraTexts = {page.bindingStatus, page.status}
end

function Audit:CanAccessAudit()
    -- Check this character's live chapter rank, never an account/other chapter role.
    local guild, _, rank = GetGuildInfo("player")
    return type(guild) == "string" and guild ~= "" and type(rank) == "number"
        and rank % 1 == 0 and rank >= 0 and rank <= 4
end

function Audit:UpdateDebugVisibility()
    local enabled = OldGodsGuildAuditDB.debugEnabled == true
    local canAudit = self:CanAccessAudit()
    if self.score then self.score:SetShown(canAudit) end
    for name, button in pairs(self.tabButtons or {}) do
        button:SetWidth(78)
        if name == "Audit" then button:SetShown(canAudit) end
        if name == "Chapter" then button:Show() end
        if name == "Debug" then button:SetShown(enabled) end
    end
    if not enabled and self.debugPage then
        self.debugPage:Hide()
        if self.currentTab == "Debug" then
            self.currentTab = "Audit"
            self.scroll:Show()
            self.tabButtons.Audit:SetEnabled(false)
        end
    end
    if not canAudit and self.scroll then
        self.scroll:Hide()
        if self.currentTab == "Audit" then
            self.currentTab = "Recruiting"
            self.recruitingPage:Show()
        end
    end
    for name, button in pairs(self.tabButtons or {}) do
        button:SetEnabled(name ~= self.currentTab and (name ~= "Audit" or canAudit))
    end
end

function Audit:FinishDebugSnapshot()
    local passedPoints = 0
    for _, result in ipairs(results) do if result.passed then passedPoints = passedPoints + result.points end end
    local percentage, earned, total = auditScore()
    self:DebugValues("Audit totals", "passedPoints", earned, "totalPoints", total, "percentage", percentage, "resultCount", #results)
    self.debugCapturing = false
    if self.debugPage then self:RenderDebugPage() end
end

function Audit:RenderDebugPage()
    local page = self.debugPage
    if not page then return end
    local lines = self.auditDebugLines or {}
    local count = math.max(1, math.ceil(#lines / 80))
    page.pageNumber = math.min(math.max(page.pageNumber or 1, 1), count)
    local first = (page.pageNumber - 1) * 80 + 1
    local shown = {}
    for i = first, math.min(first + 79, #lines) do shown[#shown + 1] = lines[i] end
    page.text:SetText(table.concat(shown, "\n"):gsub("|", "||"))
    page.content:SetHeight(math.max(page.text:GetStringHeight() + 16, 1))
    page.scroll:SetVerticalScroll(0)
    page.pageLabel:SetText(string.format("Page %d / %d - %d lines", page.pageNumber, count, #lines))
    page.previous:SetEnabled(page.pageNumber > 1)
    page.next:SetEnabled(page.pageNumber < count)
end

function Audit:BuildDebugPage(page)
    page.body:SetText("Values from the latest Audit refresh, in execution order. Restricted values are labeled.")
    page.body:SetWidth(850)
    page.extraTexts = {}
    local refresh = createButton(page, "Refresh Audit", function() page.pageNumber = 1; Audit:Refresh() end, 125)
    refresh:SetPoint("TOPLEFT", 24, -92)
    local copy = createButton(page, "Copy Snapshot", function() showCopyBox(table.concat(Audit.auditDebugLines or {}, "\n")) end, 135)
    copy:SetPoint("LEFT", refresh, "RIGHT", 8, 0)
    local reset = createButton(page, "Reset Saved Realms", function() Audit:ResetRecruitingRealmCache(); Audit:Refresh() end, 170)
    reset:SetPoint("LEFT", copy, "RIGHT", 8, 0)
    page.previous = createButton(page, "Previous", function() page.pageNumber = (page.pageNumber or 1) - 1; Audit:RenderDebugPage() end, 85)
    page.previous:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    page.next = createButton(page, "Next", function() page.pageNumber = (page.pageNumber or 1) + 1; Audit:RenderDebugPage() end, 70)
    page.next:SetPoint("LEFT", page.previous, "RIGHT", 8, 0)
    page.pageLabel = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.pageLabel:SetPoint("TOPLEFT", 24, -126)
    page.extraTexts[#page.extraTexts + 1] = page.pageLabel
    page.scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT", 24, -150)
    page.scroll:SetPoint("BOTTOMRIGHT", -42, 20)
    page.content = CreateFrame("Frame", nil, page.scroll)
    page.content:SetSize(820, 1)
    page.scroll:SetScrollChild(page.content)
    page.text = page.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.text:SetPoint("TOPLEFT", 4, -4)
    page.text:SetWidth(810)
    page.text:SetJustifyH("LEFT")
    page.text:SetJustifyV("TOP")
    page.extraTexts[#page.extraTexts + 1] = page.text
    page.pageNumber = 1
end

function Audit:ResizeLayout(width,height)
    -- Keep the existing dense controls usable at the minimum size; larger windows
    -- expand the anchored list viewports instead of scaling the fonts.
    if self.canvas then self.canvas:SetWidth(math.max(900,width-80)) end
    for _,page in ipairs(self.pages or {}) do
        if page.body then page.body:SetWidth(math.max(810,width-130)) end
        if page.content then page.content:SetWidth(math.max(810,width-170)) end
        if page.candidateContent then page.candidateContent:SetWidth(math.max(810,width-170)) end
        if page.quietContent then page.quietContent:SetWidth(math.max(790,width-190)) end
        for _,input in ipairs(page.feedbackInputs or {}) do input:SetWidth(math.max(780,width-200)) end
    end
    if self.rosterPage and self.rosterPage.content then self.rosterPage.content:SetWidth(math.max(850,width-130)) end
    if self.chapterPage and self.chapterPage.body then self.chapterPage.body:SetWidth(math.max(810,width-130)) end
end

function Audit:SaveWindowSize()
    local width,height=self.frame:GetSize()
    OldGodsGuildAuditDB.windowSize={width=math.max(980,math.min(2200,width)),height=math.max(690,math.min(1400,height))}
end

local function buildWindow()
    local frame = CreateFrame("Frame", "OldGodsGuildAuditFrame", UIParent, "ButtonFrameTemplate")
    Audit.frame = frame
    -- Keep the entire window and its inherited child layers above ordinary game panels.
    frame:SetFrameStrata("FULLSCREEN")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    local savedSize=OldGodsGuildAuditDB.windowSize or {}
    frame:SetSize(math.max(980,math.min(2200,tonumber(savedSize.width) or 980)),math.max(690,math.min(1400,tonumber(savedSize.height) or 690)))
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(980,690,2200,1400)
    elseif frame.SetMinResize then frame:SetMinResize(980,690); frame:SetMaxResize(2200,1400) end
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:HookScript("OnHide", function() Audit:ClearSpazzyBinding() end)
    frame:Hide()
    local titleParent = frame.TitleContainer or frame
    local title = titleParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER")
    title:SetText("Old Gods Guild Audit")
    Audit.title = title

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 14, -20)
    header:SetPoint("TOPRIGHT", -14, -88)
    header:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    header:SetFrameLevel(frame:GetFrameLevel())
    Audit.header = header

    local raffles = createButton(frame,"Raffles",function() OldGodsRaffles:Open() end,110)
    raffles:SetPoint("TOPLEFT",250,-28)
    local refresh = createButton(frame, "Refresh", function() Audit:Refresh() end, 100)
    refresh:SetPoint("TOPRIGHT", -42, -28)
    local themeButton = OldGodsUI.Dropdown(frame, "Theme", {{"dark","Dark"},{"light","Light"},{"purple","Crown Purple"},{"hotPink","Hot Pink"},{"hotDogStand","Hot Dog Stand"}}, function() return OldGodsGuildAuditDB.theme end, function(value) OldGodsGuildAuditDB.theme=value; Audit:ApplyTheme() end, 180)
    Audit.themeButton = themeButton
    themeButton:SetPoint("RIGHT", refresh, "LEFT", -8, 0)
    local debugButton = CreateFrame("Button", nil, frame)
    debugButton.oldGodsTextOnly = true
    debugButton:SetSize(18, 18)
    local debugLabel = debugButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugLabel:SetPoint("CENTER")
    debugButton:SetFontString(debugLabel)
    debugButton:SetText("π")
    debugButton:RegisterForClicks("LeftButtonUp")
    debugButton:SetScript("OnClick", function()
        if not (IsControlKeyDown() and IsShiftKeyDown()) then return end
        OldGodsGuildAuditDB.debugEnabled = not OldGodsGuildAuditDB.debugEnabled
        Audit:Refresh(); Audit:ApplyTheme()
    end)
    OldGodsUI.Help(debugButton, "π")
    debugButton:SetPoint("BOTTOMRIGHT", -5, 4)
    Audit.debugButton = debugButton
    Audit.score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Audit.score:SetPoint("TOPLEFT", 70, -35)

    local contentBackground = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    contentBackground:SetPoint("TOPLEFT", 14, -94)
    contentBackground:SetPoint("BOTTOMRIGHT", -14, 14)
    contentBackground:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    contentBackground:SetFrameLevel(frame:GetFrameLevel())
    Audit.contentBackground = contentBackground

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 26, -106)
    scroll:SetPoint("BOTTOMRIGHT", -38, 24)
    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetWidth(900)
    canvas:SetHeight(530)
    scroll:SetScrollChild(canvas)
    Audit.canvas = canvas
    Audit.scroll = scroll

    Audit.tabButtons = {}
    local previous
    for _, tabName in ipairs({"Audit", "Recruiting", "Calendar", "Bank", "Roster", "Event Log", "Feedback", "Special", "Chapter", "Debug"}) do
        local selectedTab = tabName
        local button = createButton(frame, selectedTab, function() Audit:SelectTab(selectedTab) end, 108)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
        else
            button:SetPoint("TOPLEFT", 24, -66)
        end
        Audit.tabButtons[selectedTab] = button
        previous = button
    end

    local function createPlaceholder(titleText, bodyText)
        local page = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        page:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
        page:SetPoint("TOPLEFT", 26, -106)
        page:SetPoint("BOTTOMRIGHT", -26, 24)
        local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        heading:SetPoint("TOPLEFT", 24, -24)
        heading:SetText(titleText)
        page.heading = heading
        local body = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -16)
        body:SetText(bodyText)
        page.body = body
        Audit.pages = Audit.pages or {}
        Audit.pages[#Audit.pages + 1] = page
        page:Hide()
        return page
    end
    Audit.recruitingPage = createPlaceholder("Recruiting", "Guild recruiting tools.")
    Audit:BuildRecruitingPage(Audit.recruitingPage)
    Audit.calendarPage = createPlaceholder("Calendar", "Calendar tools will be added here.")
    Audit:BuildCalendarPage(Audit.calendarPage)
    Audit.bankPage = createPlaceholder("Bank", "Guild bank tools will be added here.")
    Audit:BuildBankPage(Audit.bankPage)
    Audit.rosterPage = createPlaceholder("Roster", "Guild roster search.")
    Audit:BuildRosterPage(Audit.rosterPage)
    Audit.eventLogPage = createPlaceholder("Event Log", "Guild roster event history.")
    Audit:BuildRosterEventPage(Audit.eventLogPage)
    Audit.feedbackPage = createPlaceholder("Feedback", "Send feedback through the desktop companion.")
    Audit:BuildFeedbackPage(Audit.feedbackPage)
    Audit.specialPage = createPlaceholder("Special", "")
    Audit:BuildSpecialPage(Audit.specialPage)
    Audit.debugPage = createPlaceholder("Debug", "")
    Audit:BuildDebugPage(Audit.debugPage)
    Audit.chapterPage = createPlaceholder("Chapter settings", "")
    OldGodsChapterSettings.Build(Audit.chapterPage, function() Audit:Refresh() end, function(host) return Audit:BuildQuietZonesPage(host) end)
    local resize=CreateFrame("Button",nil,frame)
    resize:SetSize(20,20); resize:SetPoint("BOTTOMRIGHT",-24,3)
    local grip=resize:CreateFontString(nil,"OVERLAY","GameFontNormal"); grip:SetAllPoints(); grip:SetText("◢")
    resize:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" and not InCombatLockdown() then frame:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp",function()
        frame:StopMovingOrSizing(); Audit:SaveWindowSize(); Audit:ResizeLayout(frame:GetSize())
        if Audit.currentTab=="Roster" then Audit:RenderRosterPage() end
        if Audit.currentTab=="Recruiting" then Audit:RenderRecruitingCandidates() end
    end)
    OldGodsUI.Help(resize,"Resize window","Drag to resize. The smallest size preserves the existing controls. Size is remembered after /reload.")
    frame:SetScript("OnSizeChanged",function(_,width,height) Audit:ResizeLayout(width,height) end)
    Audit:ResizeLayout(frame:GetSize())
    Audit:UpdateDebugVisibility()
    Audit:SelectTab("Audit")
    Audit:ApplyTheme()
end

function Audit:ToggleWindow()
    if not self.frame then buildWindow() end
    self.frame:SetShown(not self.frame:IsShown())
    if self.frame:IsShown() then self:Refresh() end
end

function Audit:UpdateMinimapButtonPosition()
    local angle = math.rad(tonumber(OldGodsGuildAuditDB.minimap.angle) or 225)
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * (Minimap:GetWidth() / 2 + 8),
        math.sin(angle) * (Minimap:GetHeight() / 2 + 8))
end

function Audit:CreateMinimapButton()
    if self.minimapButton then return end
    local button = CreateFrame("Button", "OldGodsGuildAuditMinimapButton", Minimap)
    self.minimapButton = button
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface/Icons/INV_Misc_Eye_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    button:SetScript("OnClick", function(_, mouse) if mouse == "RightButton" then Audit:ToggleCompactRecruiting() else Audit:ToggleWindow() end end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Old Gods Guild Audit")
        GameTooltip:AddLine("Left-click: full addon. Right-click: compact recruiter.", 1, 1, 1)
        GameTooltip:AddLine("Drag to move around the minimap.", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            if not centerX or not centerY then return end
            local scale = Minimap:GetEffectiveScale()
            -- Normalize each axis so dragging also follows a resized minimap.
            x = (x / scale - centerX) / (Minimap:GetWidth() / 2 + 8)
            y = (y / scale - centerY) / (Minimap:GetHeight() / 2 + 8)
            OldGodsGuildAuditDB.minimap.angle = math.deg(math.atan2(y, x)) % 360
            Audit:UpdateMinimapButtonPosition()
        end)
    end)
    local function stopDragging(self) self:SetScript("OnUpdate", nil) end
    button:SetScript("OnDragStop", stopDragging)
    button:SetScript("OnHide", stopDragging)
    Minimap:HookScript("OnSizeChanged", function() Audit:UpdateMinimapButtonPosition() end)
    self:UpdateMinimapButtonPosition()
    button:SetShown(OldGodsGuildAuditDB.minimap.enabled)
end

function Audit:UpdateLauncherVisibility()
    if self.minimapButton then self.minimapButton:SetShown(OldGodsGuildAuditDB.minimap.enabled) end
    if self.floatingButton then self.floatingButton:SetShown(OldGodsGuildAuditDB.floatingIcon.enabled) end
end

function Audit:CreateFloatingButton()
    if self.floatingButton then return end
    local button = CreateFrame("Button","OldGodsGuildAuditFloatingButton",UIParent)
    self.floatingButton = button
    button:SetSize(36,36); button:SetClampedToScreen(true); button:SetMovable(true)
    button:SetPoint("CENTER",UIParent,"CENTER",OldGodsGuildAuditDB.floatingIcon.x,OldGodsGuildAuditDB.floatingIcon.y)
    button:SetNormalTexture("Interface/Icons/INV_Misc_Eye_01")
    button:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square","ADD")
    button:RegisterForClicks("LeftButtonUp","RightButtonUp"); button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart",button.StartMoving)
    button:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local x,y=self:GetCenter(); local cx,cy=UIParent:GetCenter()
        if x and cx then OldGodsGuildAuditDB.floatingIcon.x=x-cx; OldGodsGuildAuditDB.floatingIcon.y=y-cy end
    end)
    button:SetScript("OnClick",function(_,mouse) if mouse=="RightButton" then Audit:ToggleCompactRecruiting() else Audit:ToggleWindow() end end)
    button:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine("Old Gods Guild Audit")
        GameTooltip:AddLine("Left-click: full addon. Right-click: compact recruiter.",1,1,1)
        GameTooltip:AddLine("Drag to move. Disable icons in Special.",1,1,1); GameTooltip:Show()
    end)
    button:SetScript("OnLeave",function() GameTooltip:Hide() end)
    self:UpdateLauncherVisibility()
end

SLASH_OLDGODSGUILDAUDIT1 = "/oga"
SLASH_OLDGODSGUILDAUDIT2 = "/oldgodsaudit"
SlashCmdList.OLDGODSGUILDAUDIT = function(value)
    local command, option = trim(value):lower():match("^(%S+)%s*(%S*)$")
    if command == "recruit" then Audit:ToggleCompactRecruiting()
    elseif command == "minimap" or command == "floating" then
        local key = command == "minimap" and "minimap" or "floatingIcon"
        if option == "on" then OldGodsGuildAuditDB[key].enabled = true
        elseif option == "off" then OldGodsGuildAuditDB[key].enabled = false
        else OldGodsGuildAuditDB[key].enabled = not OldGodsGuildAuditDB[key].enabled end
        Audit:UpdateLauncherVisibility()
    else Audit:ToggleWindow() end
end

local function normalizedChatChannel(value)
    return trim(value):lower():gsub("[^%w]", "")
end

function Audit:CaptureAllowedChat(event, ...)
    if not OldGodsGuildAuditDB or not OldGodsGuildAuditDB.chat or not OldGodsGuildAuditDB.chat.enabled then return end
    local message, author, _, channelName, _, _, _, _, channelBaseName = ...
    if not isPublicString(message) or not isPublicString(author) then return end
    local channelType, storedChannel = nil, ""
    if event == "CHAT_MSG_GUILD" then channelType = "guild"
    elseif event == "CHAT_MSG_OFFICER" then channelType = "officer"
    elseif event == "CHAT_MSG_CHANNEL" then
        if not isPublicValue(channelBaseName) or not isPublicValue(channelName) then return end
        local candidate = channelBaseName or channelName or ""
        local wanted = normalizedChatChannel(candidate)
        for _, allowed in ipairs(OldGodsGuildAuditDB.chat.customChannels or {}) do
            if normalizedChatChannel(allowed) == wanted then channelType = "channel"; storedChannel = allowed; break end
        end
    end
    if not channelType or trim(message) == "" or trim(author) == "" then return end
    local guildName, _, _, guildRealm = GetGuildInfo("player")
    if not isPublicValue(guildName) or not isPublicValue(guildRealm) then return end
    guildName = guildName or "Unknown Guild"; guildRealm = guildRealm or "UnknownRealm"
    local timestamp = GetServerTime()
    local records = OldGodsGuildAuditDB.chat.messages
    records[#records + 1] = {
        schemaVersion = 1, id = table.concat({ guildName .. "-" .. guildRealm, channelType, storedChannel, author, tostring(timestamp), message }, "|"),
        timestamp = timestamp, guildKey = guildName .. "-" .. guildRealm, channelType = channelType,
        channelName = storedChannel, author = author, text = message, source = "wowChatEvent", syncStatus = "pendingUpload",
    }
    while #records > 10000 do table.remove(records, 1) end
end

Audit:RegisterEvent("PLAYER_LOGOUT")
Audit:RegisterEvent("ADDON_LOADED")
Audit:RegisterEvent("WHO_LIST_UPDATE")
Audit:RegisterEvent("GUILD_ROSTER_UPDATE")
Audit:RegisterEvent("PLAYER_GUILD_UPDATE")
Audit:RegisterEvent("PLAYER_REGEN_ENABLED")
Audit:RegisterEvent("PLAYER_REGEN_DISABLED")
Audit:RegisterEvent("GUILD_EVENT_LOG_UPDATE")
Audit:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
Audit:RegisterEvent("GUILDBANKFRAME_OPENED")
Audit:RegisterEvent("GUILDBANKFRAME_CLOSED")
Audit:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
Audit:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
Audit:RegisterEvent("GUILDBANKLOG_UPDATE")
Audit:RegisterEvent("GUILDBANK_UPDATE_MONEY")
Audit:RegisterEvent("CLUB_FINDER_RECRUITS_UPDATED")
Audit:RegisterEvent("CLUB_FINDER_RECRUITMENT_POST_RETURNED")
Audit:RegisterEvent("CLUB_FINDER_APPLICATIONS_UPDATED")
Audit:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
Audit:RegisterEvent("CHAT_MSG_GUILD")
Audit:RegisterEvent("CHAT_MSG_OFFICER")
Audit:RegisterEvent("CHAT_MSG_CHANNEL")
Audit:SetScript("OnEvent", function(self, event, arg1, ...)
    if event=="CALENDAR_UPDATE_EVENT_LIST" then self.calendarReadReady=true end
    local guildRequestType=Enum and Enum.ClubFinderRequestType and Enum.ClubFinderRequestType.Guild or 1
    if event=="CLUB_FINDER_RECRUITS_UPDATED" and (arg1==nil or arg1==guildRequestType) then self.applicantReadReady=true end
    if event=="CLUB_FINDER_RECRUITMENT_POST_RETURNED" and (arg1==nil or arg1==guildRequestType) then self.postingReadReady=true end
    if OldGodsGuildAuditDB and self.frame then
        if event=="PLAYER_GUILD_UPDATE" then
            self.calendarReadReady=nil;self.applicantReadReady=nil;self.postingReadReady=nil;self.auditSourcesRequested=nil
            C_Timer.After(1,function() Audit:RequestAuditSources() end)
        end
        if not self.auditSourcesRequested and not InCombatLockdown() and (event=="GUILD_ROSTER_UPDATE" or event=="PLAYER_REGEN_ENABLED") then self:RequestAuditSources() end
        if event=="GUILD_ROSTER_UPDATE" or event=="PLAYER_GUILD_UPDATE" or event=="CALENDAR_UPDATE_EVENT_LIST" or event=="CLUB_FINDER_APPLICATIONS_UPDATED" or event=="CLUB_FINDER_RECRUITS_UPDATED" or event=="CLUB_FINDER_RECRUITMENT_POST_RETURNED" then self:ScheduleAuditCapture() end
    end
    if event == "PLAYER_LOGOUT" then
        self:CaptureCurrentAudit()
    elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" or event == "CHAT_MSG_CHANNEL" then
        self:CaptureAllowedChat(event, arg1, ...)
    elseif event == "WHO_LIST_UPDATE" then
        if whoRequestPending then
            addWhoScanLog(string.format("EVENT WHO_LIST_UPDATE query=%q elapsed=%.2fs", whoCurrentSearch and whoCurrentSearch.query or "unknown", whoQuerySentAt and (GetTime() - whoQuerySentAt) or 0))
            whoRequestPending = false
            if whoTimeoutTimer then whoTimeoutTimer:Cancel(); whoTimeoutTimer = nil end
            C_Timer.After(0.75, function() self:ProcessWhoResults() end)
        end
    elseif event == "GUILDBANKFRAME_OPENED" then
        self:BeginGuildBankSession("legacy event")
    elseif event == "GUILDBANKFRAME_CLOSED" then
        self:EndGuildBankSession()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.GuildBanker then
        self:BeginGuildBankSession("Retail interaction event")
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" and Enum and Enum.PlayerInteractionType and arg1 == Enum.PlayerInteractionType.GuildBanker then
        self:EndGuildBankSession()
    elseif event == "GUILDBANKLOG_UPDATE" then
        if guildBankOpen then self:ScheduleBankLogCapture() end
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        if guildBankOpen and bankInventoryQueryState and bankInventoryQueryState.waitingForTab then
            bankInventoryQueryState.waitingForTab = nil
            self:ContinueBankInventoryQuery()
        elseif guildBankOpen then
            self:ScheduleBankInventoryCapture()
        end
    elseif event == "GUILDBANK_UPDATE_MONEY" then
        if guildBankOpen then self:ScheduleBankInventoryCapture() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        self:UpdateDebugVisibility()
        recruitingGuildRealm()
        self:UpdateRecruitingPopulation()
        self:ScheduleRosterCapture()
        C_Timer.After(0.75, function() self:UpdatePendingGuildActions() end)
    elseif event == "PLAYER_GUILD_UPDATE" then
        OldGodsRecruiting:Cancel("Guild changed. Prepare the invite batch again.")
        self:UpdateDebugVisibility()
        if OldGodsRosterTools and OldGodsRosterTools.guildKey then OldGodsRosterTools:SyncGuild() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        OldGodsRecruiting:Cancel("Recruiting paused for combat. Prepare the batch again afterwards.")
        self:RenderCompactRecruiting()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OldGodsRecruiting:Refresh()
        self:UpdateRecruitingBindings()
        self:RenderCompactRecruiting()
        if Audit.chapterRulesChangedInCombat then Audit.chapterRulesChangedInCombat = nil; clearGuildRemoveBinding() end
        if self.spazzyClearPending then self:ClearSpazzyBinding() end
        self:UpdatePendingGuildActions()
    elseif event == "GUILD_EVENT_LOG_UPDATE" then
        self:ImportGuildEventLog()
    elseif event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        OldGodsGuildAuditDB = OldGodsGuildAuditDB or {}
        copyDefaults(DEFAULTS, OldGodsGuildAuditDB)
        OldGodsGuildAuditDB.gameVersion = OldGodsGameProfile or "retail"
        -- These reminders must be acknowledged again for each login/reload.
        OldGodsGuildAuditDB.manual.officerMeeting = false
        OldGodsGuildAuditDB.manual.newMemberInfo = false
        OldGodsGuildAuditDB.manual.missingPromotions = false
        OldGodsGuildAuditDB.manualPasses.meeting = nil
        OldGodsGuildAuditDB.manualPasses.nmi = nil
        OldGodsGuildAuditDB.manualPasses.missingPromotions = nil
        self:StartRosterNameCleanup()
        pruneInviteHistory()
        if OldGodsGuildAuditDB.discordNmiUrl == "" then OldGodsGuildAuditDB.discordNmiUrl = DEFAULTS.discordNmiUrl end
        if OldGodsGuildAuditDB.discordPromoUrl == "" then OldGodsGuildAuditDB.discordPromoUrl = DEFAULTS.discordPromoUrl end
        buildWindow()
        self:CreateMinimapButton()
        self:CreateFloatingButton()
        C_GuildInfo.GuildRoster()
        requestGuildEventLog()
        C_Timer.After(5,function() Audit:RequestAuditSources() end)
    elseif self.frame and self.frame:IsShown() then
        C_Timer.After(0.25, function() if self.frame:IsShown() then self:Refresh() end end)
    end
end)
