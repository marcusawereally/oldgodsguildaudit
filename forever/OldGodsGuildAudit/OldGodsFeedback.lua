-- Officer feedback: chapter-local bans, review statuses and recruitment helpers.
OldGodsFeedback = {}
local F = OldGodsFeedback
local function public(v) return not (issecretvalue and issecretvalue(v)) end
local function text(v) return public(v) and type(v) == "string" and v:match("^%s*(.-)%s*$") or "" end
local function now() return GetServerTime() end
function F.GuildKey()
    local guild, _, _, realm = GetGuildInfo("player")
    if not guild then return nil end
    return guild .. "-" .. (realm or GetNormalizedRealmName()):gsub("[%s%-]", "")
end
function F.NameKey(name, requireRealm)
    name = text(name)
    if name == "" or name:find("[|%c]") then return nil end
    local character, realm = name:match("^([^%s%-]+)%-(.+)$")
    if not character then
        if requireRealm or name:find("[%s%-]") then return nil end
        character, realm = name, GetNormalizedRealmName()
    end
    realm = text(realm):gsub("[%s%-]", "")
    if realm == "" then return nil end
    return (character .. "-" .. realm):lower(), character .. "-" .. realm
end
function F.Store()
    local key = F.GuildKey()
    if not key or not OldGodsGuildAuditDB then return nil end
    OldGodsGuildAuditDB.banLists = OldGodsGuildAuditDB.banLists or {}
    OldGodsGuildAuditDB.banLists[key] = OldGodsGuildAuditDB.banLists[key] or {}
    return OldGodsGuildAuditDB.banLists[key]
end
function F.Banned(name, guid)
    local bans = F.Store()
    if not bans then return nil end
    local key = F.NameKey(name)
    if key and bans[key] then return bans[key] end
    if public(guid) and type(guid) == "string" and guid ~= "" then
        for _, ban in pairs(bans) do if ban.guid == guid then return ban end end
    end
end
function F.AddBan(name, reason, metadata, deferRefresh)
    local bans = F.Store()
    if not bans or not OldGodsChapterSettings.CanEdit() then return false, "Lead Officer or higher is required in the current guild." end
    local key, display = F.NameKey(name, true)
    reason = text(reason)
    if not key or #display > 100 then return false, "Enter Character-Realm (including the realm)." end
    if reason == "" or #reason > 300 or reason:find("[|%c]") then return false, "Enter a reason of 1-300 characters, without pipes or line breaks." end
    if bans[key] or F.Banned(display, metadata and metadata.guid) then return false, "Already banned; existing details were preserved." end
    metadata = metadata or {}
    bans[key] = {name=display, reason=reason, timestamp=metadata.timestamp or now(),
        officer=metadata.officer or UnitName("player"), source=metadata.source or "Manual", guid=metadata.guid,
        importedAt=metadata.source == "GRM" and now() or nil}
    if F.OnChanged and not deferRefresh then F.OnChanged() end
    return true, "Ban added. Addon outreach and invitations are blocked."
end
function F.RemoveBan(name)
    local bans = F.Store()
    if not bans or not OldGodsChapterSettings.CanEdit() then return false end
    local key = F.NameKey(name, true)
    if not key then return false end
    bans[key] = nil
    if F.OnChanged then F.OnChanged() end
    return true
end
function F.PreviewGRM()
    local preview = {guildKey=F.GuildKey(), rows={}, added=0, duplicates=0, unresolved=0}
    if not preview.guildKey or not GRM or not GRM.GetGuild or not GRM.GetFormerMembers then
        return nil, "Load Guild Roster Manager on this character, then try again."
    end
    -- Explicit current-guild key: never import whichever chapter GRM last displayed.
    local ok, current = pcall(GRM.GetGuild, preview.guildKey)
    local okFormer, former = pcall(GRM.GetFormerMembers, preview.guildKey)
    if not ok or not okFormer or (type(current) ~= "table" and type(former) ~= "table") then
        return nil, "GRM has no readable data for this guild. Open GRM and refresh its roster."
    end
    local seen, guids = {}, {}
    for _, source in ipairs({current or {}, former or {}}) do
        for _, player in pairs(source) do
            if type(player) == "table" and type(player.bannedInfo) == "table" and player.bannedInfo[1] == true then
                local key, display = F.NameKey(player.name, true)
                local reason = text(player.reasonBanned)
                local guid = text(player.GUID)
                local state = "New"
                if not key or #display > 100 or #reason > 300 or reason:find("[|%c]") then state = "Unresolved"
                elseif seen[key] or (guid ~= "" and guids[guid]) or F.Banned(display, guid) then state = "Duplicate" end
                if key then seen[key] = true end
                if guid ~= "" then guids[guid] = true end
                preview.rows[#preview.rows+1] = {name=display or text(player.name), reason=reason ~= "" and reason or "Imported GRM ban (no reason recorded)",
                    officer=text(player.bannedInfo[4]), timestamp=tonumber(player.bannedInfo[2]) or 0, source="GRM", guid=guid, state=state}
                if state == "New" then preview.added=preview.added+1 elseif state == "Duplicate" then preview.duplicates=preview.duplicates+1 else preview.unresolved=preview.unresolved+1 end
            end
        end
    end
    table.sort(preview.rows, function(a,b) return a.name < b.name end)
    return preview
end
function F.ImportGRM(preview)
    if not preview or preview.guildKey ~= F.GuildKey() then return false, "Guild changed. Preview the import again." end
    if not OldGodsChapterSettings.CanEdit() then return false, "Lead Officer or higher is required." end
    local added = 0
    for _, row in ipairs(preview.rows) do
        if row.state == "New" and F.AddBan(row.name, row.reason, row, true) then added=added+1 end
    end
    if added > 0 and F.OnChanged then F.OnChanged() end
    return true, string.format("Imported %d bans. Existing records preserved; unresolved rows were not imported.", added)
end
function F.Population()
    local goal = tonumber(OldGodsChapterSettings.Policy().minimum) or 980
    local count = GetNumGuildMembers and GetNumGuildMembers()
    if not public(count) or type(count) ~= "number" or count <= 0 or not F.GuildKey() then return "Guild population pending", "Goal: " .. goal .. " characters" end
    return string.format("%d / %d = %d%%", count, goal, math.floor(count / goal * 100 + 0.5)),
        string.format("%d characters needed | Includes offline toons", math.max(0, goal-count))
end
function F.Faction(info)
    local raceID = public(info.raceID) and info.raceID or nil
    -- WhoInfo supplies localized raceStr, not raceID. Shared races stay Unknown.
    if not raceID and C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetFactionInfo then
        if not F.raceFactions then
            F.raceFactions = {}
            for id=1,100 do
                local ok,race=pcall(C_CreatureInfo.GetRaceInfo,id)
                if ok and type(race)=="table" and text(race.raceName)~="" then
                    local factionOK,faction=pcall(C_CreatureInfo.GetFactionInfo,id)
                    local group=factionOK and type(faction)=="table" and text(faction.groupTag) or "Unknown"
                    if group~="Alliance" and group~="Horde" then group="Unknown" end
                    local key=race.raceName:lower()
                    if F.raceFactions[key] and F.raceFactions[key]~=group then group="Unknown" end
                    F.raceFactions[key]=group
                end
            end
        end
        return F.raceFactions[text(info.raceStr):lower()] or "Unknown"
    end
    if type(raceID) == "number" and C_CreatureInfo and C_CreatureInfo.GetFactionInfo then
        local ok, faction = pcall(C_CreatureInfo.GetFactionInfo, raceID)
        if ok and type(faction) == "table" and public(faction.groupTag) then
            if faction.groupTag == "Alliance" or faction.groupTag == "Horde" then return faction.groupTag end
        end
    end
    return "Unknown"
end
function F.Eligibility(info)
    local blocked=F.RecruitingBlockReason and F.RecruitingBlockReason(info)
    if blocked then return "Blocked",blocked end
    local ban = F.Banned(info.fullName, info.guid)
    if ban then return "Blocked", "Banned: " .. ban.reason end
    local faction = F.Faction(info)
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Unknown" then return "Review", "Faction unknown; WoW checks the invitation" end
    if faction ~= mine then return "Review", "Cross-faction invite may require another route" end
    return "Eligible", "Same faction; WoW makes the final invite check"
end
function F.CandidateLabel(info)
    local faction = F.Faction(info)
    local color = faction == "Alliance" and "ff8ec6ff" or faction == "Horde" and "ffff979d" or "ffbec7d3"
    local state, reason = F.Eligibility(info)
    return "|c" .. color .. faction .. "|r | " .. state .. " - " .. reason
end
function F.EventCategory(record)
    if record.category == "Recruiting" then return "Recruiting" end
    if record.type == "recruit" then return "Recruiting" end
    if record.type == "join" or record.type == "leave" then return "Membership" end
    local before, after = record.before, record.after
    if before and after and (before.publicNote ~= after.publicNote or before.officerNote ~= after.officerNote) then return "Notes" end
    if (record.details or ""):lower():find("note:",1,true) then return "Notes" end
    return "Administration"
end
F.statuses = {
    attention={label="Needs attention", color="ffff979d"}, followup={label="Review / follow up", color="fff2c267"},
    contact={label="Contact / welcome", color="ff8ec6ff"}, completed={label="Completed", color="ff91dab0"}, info={label="Information", color="ffbec7d3"},
}
function F.EventStatus(record)
    local key = record.reviewStatus
    if not F.statuses[key] then
        key = record.type == "join" and "contact" or record.type == "leave" and "followup" or "info"
        if record.type == "blocked" or record.type == "failed" then key = "attention" end
        if F.EventCategory(record) == "Notes" then
            local after = record.after
            if after and not OldGodsChapterSettings.NoteValid(after.publicNote, after.rankIndex, (after.rankIndex or 99) <= 3) then key="followup" end
        end
    end
    return key, F.statuses[key]
end
function F.SetEventCompleted(record)
    if not OldGodsChapterSettings.CanEdit() then return end
    if record.reviewStatus == "completed" then record.reviewStatus=nil else record.reviewStatus="completed" end
    record.reviewedBy, record.reviewedAt = UnitName("player"), now()
end

-- Separate management dialog keeps the recruiter usable at its existing size.
function F.OpenBans(name)
    if not F.window then
        local w = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        F.window = w
        w:SetSize(700,560); w:SetPoint("CENTER"); w:SetFrameStrata("FULLSCREEN_DIALOG"); w:SetClampedToScreen(true)
        w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart",w.StartMoving); w:SetScript("OnDragStop",w.StopMovingOrSizing)
        w.TitleText:SetText("Old Gods - Ban List")
        local function label(value,x,y,width)
            local t=w:CreateFontString(nil,"OVERLAY","GameFontHighlight"); t:SetPoint("TOPLEFT",x,y); t:SetWidth(width); t:SetJustifyH("LEFT"); t:SetText(value); return t
        end
        local function input(x,y,width,max)
            local e=CreateFrame("EditBox",nil,w,"InputBoxTemplate"); e:SetPoint("TOPLEFT",x,y); e:SetSize(width,26); e:SetAutoFocus(false); e:SetMaxLetters(max); return e
        end
        local function button(value,x,y,width,fn)
            local b=CreateFrame("Button",nil,w,"UIPanelButtonTemplate"); b:SetSize(width,25); b:SetPoint("TOPLEFT",x,y); b:SetText(value); b:SetScript("OnClick",fn); return b
        end
        w.description=label("",18,-35,660)
        label("Character-Realm",22,-75,230); label("Reason",270,-75,400)
        w.name=input(22,-96,230,100); w.reason=input(270,-96,405,300)
        w.name:SetScript("OnTabPressed",function() w.reason:SetFocus() end)
        w.reason:SetScript("OnTabPressed",function() w.name:SetFocus() end)
        if OldGodsUI then OldGodsUI.Help(w.name,"Character-Realm","Enter the full character name and realm to ban."); OldGodsUI.Help(w.reason,"Reason") end
        button("Add Ban",22,-131,110,function()
            if w.guildKey ~= F.GuildKey() then F.OpenBans(); w.status:SetText("Guild changed. Review the name and try again."); return end
            local ok,message=F.AddBan(w.name:GetText(),w.reason:GetText()); w.status:SetText(message)
            if ok then w.preview=nil; w.confirm:Hide(); F.RenderBans() end
        end)
        button("Preview GRM Import",142,-131,175,function()
            local preview,error=F.PreviewGRM(); w.preview=preview
            w.status:SetText(error or string.format("Preview: %d new, %d duplicates, %d unresolved. Confirm imports only new rows.",preview.added,preview.duplicates,preview.unresolved))
            w.confirm:SetShown(preview ~= nil and preview.added > 0); F.RenderBans()
        end)
        w.confirm=button("Confirm Import",327,-131,135,function()
            local ok,message=F.ImportGRM(w.preview); w.status:SetText(message)
            if ok then w.preview=nil; w.confirm:Hide(); F.RenderBans() end
        end); w.confirm:Hide()
        button("Show Ban List",472,-131,135,function() w.preview=nil; w.confirm:Hide(); F.RenderBans() end)
        label("Search names, reasons or officers",22,-169,500)
        w.search=input(22,-191,650,100); w.search:SetScript("OnTextChanged",function() F.RenderBans() end)
        w.status=label("",22,-224,650)
        w.scroll=CreateFrame("ScrollFrame",nil,w,"UIPanelScrollFrameTemplate"); w.scroll:SetPoint("TOPLEFT",18,-267); w.scroll:SetPoint("BOTTOMRIGHT",-35,18)
        w.content=CreateFrame("Frame",nil,w.scroll); w.content:SetSize(640,1); w.scroll:SetScrollChild(w.content); w.rows={}
    end
    local w=F.window
    if OldGodsUI then OldGodsUI.Help(w.search,"Ban search") end
    w.guildKey=F.GuildKey(); w.preview=nil; w.confirm:Hide(); w.status:SetText("")
    w.description:SetText((w.guildKey or "No guild") .. "\nLocal ban list for this WoW account; one-way GRM import. Does not kick members or change GRM.")
    w.name:SetText(name or ""); w.reason:SetText(""); w.search:SetText(""); w:Show(); F.RenderBans()
end
function F.RenderBans()
    local w=F.window
    if not w or not w.content then return end
    for _,row in ipairs(w.rows) do row:Hide() end
    local rows={}
    local search=text(w.search:GetText()):lower()
    for _,ban in pairs(w.preview and w.preview.rows or F.Store() or {}) do
        if (ban.name.." "..ban.reason.." "..(ban.officer or "")):lower():find(search,1,true) then rows[#rows+1]=ban end
    end
    table.sort(rows,function(a,b) return a.name<b.name end)
    local y=0
    for i,ban in ipairs(rows) do
        local row=w.rows[i]
        if not row then
            row=CreateFrame("Frame",nil,w.content); row:SetWidth(635)
            row.text=row:CreateFontString(nil,"OVERLAY","GameFontHighlight"); row.text:SetPoint("TOPLEFT",4,-4); row.text:SetWidth(500); row.text:SetJustifyH("LEFT")
            row.remove=CreateFrame("Button",nil,row,"UIPanelButtonTemplate"); row.remove:SetSize(115,24); row.remove:SetPoint("TOPRIGHT",0,-5)
            w.rows[i]=row
        end
        local when=ban.timestamp and ban.timestamp>0 and date("%Y-%m-%d",ban.timestamp) or "Date unknown"
        -- Escape pipes from third-party display fields; never execute imported data.
        row.text:SetText(string.format("%s%s\n%s\n%s | %s | %s",ban.state and (ban.state..": ") or "",ban.name,ban.reason,ban.officer ~= "" and (ban.officer or "Unknown officer") or "Unknown officer",when,ban.source or "Manual"):gsub("|","||"))
        row:SetHeight(math.max(76,row.text:GetStringHeight()+14)); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-y)
        row.remove:SetText("Remove Ban"); row.armed=false
        row.remove:SetShown(not w.preview and OldGodsChapterSettings.CanEdit())
        local name,guildKey=ban.name,w.guildKey
        row.remove:SetScript("OnClick",function()
            if guildKey ~= F.GuildKey() then F.OpenBans(); return end
            if not row.armed then row.armed=true; row.remove:SetText("Confirm Remove"); return end
            F.RemoveBan(name); F.RenderBans()
        end)
        row:Show(); y=y+row:GetHeight()+5
    end
    w.content:SetHeight(math.max(1,y))
    if OldGodsTheme then OldGodsTheme.RegisterWindow(w) end
end
