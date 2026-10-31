-- Chapter audit settings and applicant notifications requested by Infuriator.
OldGodsChapterSettings = {}
local S = OldGodsChapterSettings
local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") end
function S.Key()
    local id = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    return id and tostring(GetCurrentRegion()) .. ":" .. tostring(id) or nil
end
function S.CanEdit()
    local guild, _, rank = GetGuildInfo("player")
    return guild ~= nil and type(rank) == "number" and rank >= 0 and rank <= 3
end
function S.Policy()
    OldGodsGuildAuditDB.chapterPolicies = OldGodsGuildAuditDB.chapterPolicies or {}
    return OldGodsGuildAuditDB.chapterPolicies[S.Key() or ""] or {minimum=980, officerPrefix="Disc:", ranks={}}
end
function S.DonationsTab()
    return S.Policy().donationsTab or 1
end
function S.Days(rank)
    local row = S.Policy().ranks[tostring(rank)]
    return math.min(3650, math.max(1, tonumber(row and row.days) or 28))
end
function S.IsInactive(rank, offlineDays)
    return rank ~= 0 and rank ~= 1 and offlineDays ~= nil and offlineDays >= 28
end
function S.NoteValid(note, rank, officer)
    note = trim(note)
    if not officer then return note ~= "" end
    local lower = note:lower()
    local configured = trim(S.Policy().officerPrefix)
    -- Literal prefix, not an executable Lua pattern. A name must follow it.
    if configured ~= "" and lower:sub(1,#configured) == configured:lower()
        and trim(note:sub(#configured+1)) ~= "" then return true end
    return lower:match("^discord:%s*%S+") ~= nil or lower:match("^disc:%s*%S+") ~= nil or lower:match("^discord%s*%-%s*%S+") ~= nil
end
function S.NoteText(player, kind, policy)
    local p=policy or S.Policy()
    local format=p[kind == "Main" and "mainFormat" or "altFormat"] or "suffix-dash"
    if format == "prefix-colon" then return kind .. ": " .. player end
    if format == "suffix-colon" then return player .. ": " .. kind end
    return player .. "-" .. kind
end
function S.CanManageQuiet()
    local guild,_,rank=GetGuildInfo("player")
    return guild ~= nil and not (issecretvalue and issecretvalue(rank)) and type(rank)=="number" and rank%1==0 and rank>=0 and rank<=4
end
function S.IsOpenRealm(realm)
    local key=trim(realm):lower():gsub("[%s%-']", "")
    for _,name in ipairs(S.Policy().openRealms or {}) do if name:lower():gsub("[%s%-']", "") == key then return true end end
    return false
end
function S.IsQuietZoneRemoved(zone)
    local key=trim(zone):lower():gsub("%s+"," ")
    for _,name in ipairs(S.Policy().removedQuietZones or {}) do
        if trim(name):lower():gsub("%s+"," ")==key then return true end
    end
    return false
end
local function updateQuietZones(p,zone,remove)
    local key=trim(zone):lower():gsub("%s+"," ")
    for _,field in ipairs({"quietZones","removedQuietZones"}) do
        local list={}
        for _,name in ipairs(p[field] or {}) do
            if trim(name):lower():gsub("%s+"," ")~=key then list[#list+1]=name end
        end
        p[field]=list
    end
    local field=remove and "removedQuietZones" or "quietZones"
    p[field][#p[field]+1]=zone
end
function S.QuietZones()
    local zones, seen={},{}
    -- Keep existing local exclusions until leadership incorporates them into the shared policy.
    for _,list in ipairs({S.Policy().quietZones or {}, (OldGodsGuildAuditDB.recruiting or {}).customQuietZones or {}}) do
        for _,zone in ipairs(list) do if not S.IsQuietZoneRemoved(zone) and not seen[zone:lower()] then zones[#zones+1]=zone; seen[zone:lower()]=true end end
    end
    return zones
end
function S.Clone(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=S.Clone(item) end
    return result
end
function S.CopyPolicy() return S.Clone(S.Policy()) end
function S.Validate(p)
    if type(p) ~= "table" or type(p.minimum) ~= "number" or p.minimum % 1 ~= 0 or p.minimum < 980 or p.minimum > 1000 then return false, "Member target must be a whole number from 980 to 1000." end
    if type(p.officerPrefix) ~= "string" or #p.officerPrefix > 40 or p.officerPrefix:find("[|%c]") then return false, "Officer prefix allows at most 40 characters (no pipe or control characters). Blank keeps the standard Discord formats." end
    if p.donationsTab ~= nil and (type(p.donationsTab) ~= "number" or p.donationsTab % 1 ~= 0 or p.donationsTab < 1 or p.donationsTab > 8) then return false, "Donations tab must be a whole number from 1 to 8." end
    if type(p.ranks) ~= "table" then return false, "Missing rank settings." end
    for rank, row in pairs(p.ranks) do
        local n = tonumber(rank)
        if not n or n%1 ~= 0 or n < 0 or n > 19 or type(row) ~= "table" or type(row.days) ~= "number" or row.days%1 ~= 0 or row.days < 1 or row.days > 3650 then return false, "Each rank needs 1-3650 inactivity days. Ranks 0/1 are exempt from inactivity." end
        if type(row.prefix) ~= "string" or #row.prefix > 40 or row.prefix:find("[|\n\r]") then return false, "Rank prefixes allow at most 40 characters (no pipe or newline)." end
    end
    for _,key in ipairs({"mainFormat","altFormat"}) do
        local value=p[key]
        if value and value~="prefix-colon" and value~="suffix-colon" and value~="suffix-dash" then return false,"Choose a supported Main/Alt format." end
    end
    if p.announcement and (type(p.announcement)~="string" or #p.announcement>240 or p.announcement:find("[|%c]")) then return false,"Announcement must be one line, at most 240 bytes, without control characters or pipes." end
    for _,key in ipairs({"openRealms","quietZones","removedQuietZones"}) do
        if p[key] then
            if type(p[key])~="table" or #p[key]>50 then return false,"Use at most 50 realms or quiet zones." end
            local seen={}
            for i,name in pairs(p[key]) do
                if type(i)~="number" or i%1~=0 or i<1 or i>#p[key] or type(name)~="string" or trim(name)=="" or #name>100 or name:find("[|%c]") or seen[name:lower()] then return false,"Names must be unique, nonblank and at most 100 bytes." end
                seen[name:lower()]=true
            end
        end
    end
    return true
end
function S.Save(p)
    p=S.Clone(p)
    if not S.CanEdit() or not S.Key() then return false, "Only Lead Officer and higher can save chapter settings." end
    local ok, error = S.Validate(p)
    if not ok then return false, error end
    p.revision = math.max(GetServerTime(), (S.Policy().revision or 0)+1)
    p.author = S.CharacterKey()
    p.schemaVersion=3
    OldGodsGuildAuditDB.chapterPolicies[S.Key()] = p
    if S.OnChanged then S.OnChanged() end
    S.Broadcast()
    return true, "Chapter settings saved and shared with online guild members."
end
-- Bounded, non-executable guild messages; sender rank is checked from the roster.
local prefix, pending = "OGChapter3", {}
local outgoing, sending = {}, false
local function send(text)
    if not C_ChatInfo or not IsInGuild() then return end
    if not C_Timer or not C_Timer.After then C_ChatInfo.SendAddonMessage(prefix,text,"GUILD"); return end
    outgoing[#outgoing+1]=text
    if sending then return end
    sending=true
    local function nextMessage()
        local message=table.remove(outgoing,1)
        if not message then sending=false; return end
        if IsInGuild() then C_ChatInfo.SendAddonMessage(prefix,message,"GUILD") end
        C_Timer.After(0.2,nextMessage)
    end
    nextMessage()
end
function S.Broadcast()
    if not S.CanEdit() or not S.Key() then return end
    local p=S.Policy()
    if not p.revision or not S.Validate(p) then return end
    local header=S.Key().."|"..p.revision
    local records={}
    for i=0,19 do local row=p.ranks[tostring(i)]; if row then records[#records+1]="R|"..header.."|"..i.."|"..row.days.."|"..row.prefix end end
    records[#records+1]="F|"..header.."|"..(p.mainFormat or "suffix-dash").."|"..(p.altFormat or "suffix-dash")
    local announcement=p.announcement or ""
    local offset=1
    while offset<=#announcement do
        local last=math.min(offset+99,#announcement)
        while last<#announcement and announcement:byte(last+1)>=128 and announcement:byte(last+1)<192 do last=last-1 end
        records[#records+1]="A|"..header.."|"..announcement:sub(offset,last); offset=last+1
    end
    for _,name in ipairs(p.openRealms or {}) do records[#records+1]="O|"..header.."|"..name end
    for _,name in ipairs(p.quietZones or {}) do records[#records+1]="Z|"..header.."|"..name end
    for _,name in ipairs(p.removedQuietZones or {}) do records[#records+1]="X|"..header.."|"..name end
    send("B|"..header.."|"..#records.."|"..p.minimum.."|"..(p.donationsTab or 1).."|"..p.officerPrefix)
    for _,record in ipairs(records) do send(record) end
    send("E|"..header)
end
local function senderRank(sender)
    for i=1,(GetNumGuildMembers() or 0) do
        local name,_,rank=GetGuildRosterInfo(i)
        if name and type(rank)=="number" then
            if not name:find("-",1,true) then name=name.."-"..GetNormalizedRealmName() end
            if name:lower()==sender:lower() then return rank end
        end
    end
end
function S.ReportZone(zone)
    zone=trim(zone)
    if zone=="" or #zone>100 or zone:find("[|%c]") then return false,"Enter a zone name (up to 100 bytes)." end
    if not S.Key() then return false,"Join a guild before reporting a zone." end
    S.AddZoneReport(zone,S.CharacterKey())
    send("P|"..S.Key().."|"..zone)
    return true,"Zone reported to online leadership. It remains pending until approved."
end
function S.AddZoneReport(zone,author)
    OldGodsGuildAuditDB.quietZoneReports=OldGodsGuildAuditDB.quietZoneReports or {}
    local reports=OldGodsGuildAuditDB.quietZoneReports
    reports[S.Key()]=reports[S.Key()] or {}
    if #reports[S.Key()]>=50 then return end
    for _,report in ipairs(reports[S.Key()]) do if report.zone:lower()==zone:lower() then return end end
    table.insert(reports[S.Key()],{zone=zone,author=author})
end
function S.SetQuietZone(zone,remove)
    if not S.CanManageQuiet() then return false,"Only ranks 0–4 may change quiet zones." end
    zone=trim(zone)
    if zone=="" or #zone>100 or zone:find("[|%c]") then return false,"Enter a valid zone name." end
    local p=S.CopyPolicy()
    updateQuietZones(p,zone,remove)
    if not S.Validate(p) then return false,"The quiet-zone list is full or invalid." end
    local baseRevision=S.Policy().revision or 0
    p.revision=math.max(GetServerTime(),baseRevision+1); p.author=S.CharacterKey(); p.schemaVersion=3
    OldGodsGuildAuditDB.chapterPolicies[S.Key()]=p
    local legacy=(OldGodsGuildAuditDB.recruiting or {}).customQuietZones or {}
    for i=#legacy,1,-1 do if legacy[i]:lower()==zone:lower() then table.remove(legacy,i) end end
    send("ZC|"..S.Key().."|"..p.revision.."|"..baseRevision.."|"..(remove and "remove" or "add").."|"..zone)
    if S.OnChanged then S.OnChanged() end
    return true,remove and "Quiet zone removed and shared." or "Quiet zone approved and shared."
end
function S.Receive(message,channel,sender)
    if channel~="GUILD" or not S.Key() or type(message)~="string" or #message>255 then return end
    if message=="Q|"..tostring(S.Key()) then
        if not S.lastBroadcast or GetTime()-S.lastBroadcast>10 then S.lastBroadcast=GetTime(); S.Broadcast() end
        return
    end
    local rank=senderRank(sender)
    if not rank then return end
    local reportKey,zone=message:match("^P|([^|]+)|([^|]+)$")
    if reportKey==S.Key() and #zone<=100 and not zone:find("%c") then S.AddZoneReport(zone,sender); return end
    local key,rev,base,action,name=message:match("^ZC|([^|]+)|(%d+)|(%d+)|(%a+)|([^|]+)$")
    if key==S.Key() and rank<=4 and (action=="add" or action=="remove") and tonumber(rev)>(S.Policy().revision or 0) then
        if tonumber(base)~=(S.Policy().revision or 0) then send("Q|"..key); return end
        local p=S.CopyPolicy()
        updateQuietZones(p,name,action=="remove")
        p.revision=tonumber(rev); p.author=sender; p.schemaVersion=3
        if S.Validate(p) then OldGodsGuildAuditDB.chapterPolicies[key]=p; if S.OnChanged then S.OnChanged() end end
        return
    end
    if rank>3 then return end
    local kind,key,revision,rest=message:match("^(%u)|([^|]+)|(%d+)|?(.*)$")
    revision=tonumber(revision)
    if key~=S.Key() or not revision or revision<=(S.Policy().revision or 0) then return end
    if kind=="B" then
        local count,minimum,donationsTab,officerPrefix=rest:match("^(%d+)|(%d+)|(%d+)|(.*)$")
        if not count or tonumber(count)>174 then return end
        pending[sender]={expected=tonumber(count),received=0,minimum=tonumber(minimum),donationsTab=tonumber(donationsTab),officerPrefix=officerPrefix,ranks={},openRealms={},quietZones={},removedQuietZones={},revision=revision,author=sender,schemaVersion=3,started=GetTime()}
    elseif pending[sender] and pending[sender].revision==revision and GetTime()-pending[sender].started<60 then
        local p=pending[sender]
        if kind=="E" then
            if p.received==p.expected and S.Validate(p) then OldGodsGuildAuditDB.chapterPolicies[key]=p; if S.OnChanged then S.OnChanged() end end
            pending[sender]=nil; return
        elseif kind=="R" then
            local index,days,note=rest:match("^(%d+)|(%d+)|(.*)$")
            if not index or p.ranks[index] then pending[sender]=nil; return end
            p.ranks[index]={days=tonumber(days),prefix=note}
        elseif kind=="F" then p.mainFormat,p.altFormat=rest:match("^([^|]+)|([^|]+)$")
        elseif kind=="A" then p.announcement=(p.announcement or "")..rest
        elseif kind=="O" then table.insert(p.openRealms,rest)
        elseif kind=="Z" then table.insert(p.quietZones,rest)
        elseif kind=="X" then table.insert(p.removedQuietZones,rest)
        else pending[sender]=nil; return end
        p.received=p.received+1
    end
end
function S.ImportCompanion()
    local key=S.Key(); local p=key and (OldGodsChapterImports or {})[key]
    if not p or not S.Validate(p) or type(p.revision)~="number" or p.revision<=(S.Policy().revision or 0) then return false end
    OldGodsGuildAuditDB.chapterPolicies[key]=S.Clone(p)
    if S.CanEdit() then S.Broadcast() end
    return true
end
function S.CharacterKey() local name,realm=UnitFullName("player"); return tostring(name).."-"..tostring(realm or GetRealmName()) end
function S.Mode(value)
    OldGodsGuildAuditDB.applicantNotifications=OldGodsGuildAuditDB.applicantNotifications or {}
    local key=S.CharacterKey()
    if value == "Sound" or value == "Popup" or value == "Both" then OldGodsGuildAuditDB.applicantNotifications[key]=value end
    return OldGodsGuildAuditDB.applicantNotifications[key] or "Both"
end
local popupQueue, activePopup = {}, nil
local seen={}
function S.ShouldDeferApplicants()
    if InCombatLockdown() then return true end
    if IsInInstance then
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid" or kind == "scenario" or kind == "pvp" or kind == "arena") then return true end
    end
    return S.IsPlayerInQuietZone and S.IsPlayerInQuietZone() or false
end
function S.CheckApplicants()
    if S.ShouldDeferApplicants() and activePopup then
        table.insert(popupQueue,1,{activePopup.applicant,activePopup.clubId,"Popup"})
        activePopup:Hide()
    end
    if not CanGuildInvite or not CanGuildInvite() or not S.Key() or not C_ClubFinder then
        popupQueue={}; seen={}
        if activePopup then activePopup:Hide() end
        return
    end
    local id=C_Club.GetGuildClubId()
    local list=C_ClubFinder.ReturnClubApplicantList(id)
    if type(list) ~= "table" then return end
    local current={}
    for _,applicant in ipairs(list) do
        local guid=applicant.playerGUID
        if guid and not (issecretvalue and issecretvalue(guid)) and applicant.requestStatus == Enum.PlayerClubRequestStatus.Pending then
            local key=S.Key()..":"..tostring(guid)
            current[key]=applicant
            if not seen[key] then
                popupQueue[#popupQueue+1]={applicant,id,S.Mode()}
            end
        end
    end
    seen=current
    if activePopup and (activePopup.clubId~=id or not current[S.Key()..":"..tostring(activePopup.applicant.playerGUID)]) then activePopup:Hide() end
    -- Drop applications that were withdrawn, handled elsewhere, or belong to another guild.
    for i=#popupQueue,1,-1 do
        local item=popupQueue[i]
        local applicant=current[S.Key()..":"..tostring(item[1].playerGUID)]
        if item[2] ~= id or not applicant then table.remove(popupQueue,i) else item[1]=applicant end
    end
    if S.ShouldDeferApplicants() then return end
    while not activePopup and #popupQueue > 0 do
        local item=table.remove(popupQueue,1)
        local mode=item[3]
        if mode ~= "Popup" then PlaySound(SOUNDKIT.READY_CHECK,"Master") end
        if mode ~= "Sound" then S.ShowApplicant(item[1],item[2]) end
        print("Old Gods Audit: New guild applicant: "..tostring(item[1].name or "Unknown")..". Open Guild Finder to review.")
    end
end
function S.ShowApplicant(applicant,clubId)
    if activePopup or S.ShouldDeferApplicants() then popupQueue[#popupQueue+1]={applicant,clubId,"Popup"}; return end
    local f=CreateFrame("Frame",nil,UIParent,"BasicFrameTemplateWithInset")
    activePopup=f
    f.applicant, f.clubId = applicant, clubId
    f:SetScript("OnHide",function() activePopup=nil; C_Timer.After(0,S.CheckApplicants) end)
    f:SetSize(430,145); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving)
    f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f.TitleText:SetText("New guild applicant")
    local text=f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    text:SetPoint("TOPLEFT",18,-40); text:SetText(tostring(applicant.name).."\nClick Invite to approve this applicant.")
    local button=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    button:SetSize(130,26); button:SetPoint("BOTTOM",0,15); button:SetText("Invite")
    button:SetScript("OnClick",function()
        if S.ShouldDeferApplicants() or not CanGuildInvite() or C_Club.GetGuildClubId() ~= clubId then return end
        local stillPending=false
        for _,row in ipairs(C_ClubFinder.ReturnClubApplicantList(clubId) or {}) do if row.playerGUID == applicant.playerGUID and row.requestStatus == Enum.PlayerClubRequestStatus.Pending then stillPending=true end end
        if not stillPending then f:Hide(); return end
        if OldGodsFeedback and OldGodsFeedback.Banned(applicant.name, applicant.playerGUID) then
            print("Old Gods Audit: This applicant is on the Ban List. Review the ban before inviting.")
            return
        end
        local info=applicant
        if not info or not info.clubFinderGUID then return end
        local ok,result=pcall(C_ClubFinder.RespondToApplicant,info.clubFinderGUID,applicant.playerGUID,true,Enum.ClubFinderRequestType.Guild,applicant.name,false)
        if ok and result~=false then f:Hide() else print("Old Gods Audit: WoW blocked this approval. Use Guild Finder's Invite button.") end
    end)
    if OldGodsTheme then OldGodsTheme.RegisterWindow(f) end
end
function S.Build(page, refresh, buildQuietZones)
    local U=OldGodsUI
    page.body:SetWidth(810); page.body:SetJustifyH("LEFT")
    page.body:SetText("Chapter rules are shared in-game. Lead Officer and higher can edit general rules; ranks 0–4 manage quiet zones.")
    local scroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",22,-145); scroll:SetPoint("BOTTOMRIGHT",-32,75)
    local content=CreateFrame("Frame",nil,scroll); content:SetSize(810,550); scroll:SetScrollChild(content)
    local quietPage
    if buildQuietZones then
        quietPage=CreateFrame("Frame",nil,page)
        quietPage:SetPoint("TOPLEFT",22,-145); quietPage:SetPoint("BOTTOMRIGHT",-32,75)
        buildQuietZones(quietPage); quietPage:Hide()
    end
    local section,widgets,fields,loadedKey="General",{},{},nil
    local status=page:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    status:SetPoint("BOTTOMLEFT",185,20); status:SetWidth(650); status:SetJustifyH("LEFT")
    local save
    local function track(widget) widgets[#widgets+1]=widget; return widget end
    local function label(text,x,y)
        local t=track(content:CreateFontString(nil,"OVERLAY","GameFontHighlight")); t:SetPoint("TOPLEFT",x,y); t:SetWidth(770-x); t:SetJustifyH("LEFT"); t:SetText(text); return t
    end
    local function entry(text,x,y,value,width,max)
        label(text,x,y)
        local box=track(CreateFrame("EditBox",nil,content,"InputBoxTemplate")); box:SetSize(width or 240,26); box:SetPoint("TOPLEFT",x,y-25); box:SetAutoFocus(false); box:SetMaxLetters(max or 240); box:SetText(tostring(value or "")); U.Help(box,text)
        box:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        return box
    end
    local function show()
        for _,w in ipairs(widgets) do w:Hide() end; widgets={}
        scroll:SetShown(section~="Quiet Zones")
        if quietPage then quietPage:SetShown(section=="Quiet Zones") end
        if section=="Quiet Zones" then
            if quietPage and quietPage.Refresh then quietPage.Refresh() end
            return
        end
        local p=fields.policy
        if section=="General" then
            local input=entry("Member target (980–1000)",10,-10,p.minimum,180,4)
            input:SetScript("OnTextChanged",function(self) p.minimum=tonumber(self:GetText()) end)
            local prefixInput=entry("Officer Discord note prefix (blank = standard formats)",10,-80,p.officerPrefix or "",500,40)
            prefixInput:SetScript("OnTextChanged",function(self) p.officerPrefix=self:GetText() end)
            label("The custom prefix is literal and must be followed by a name. Standard Discord: name, Disc: name and discord - name remain accepted. Blank never permits an empty officer note.",10,-155)
            label("Audit inactivity: 28 days or more. Guild ranks 0 and 1 are exempt. Shorter cleanup settings do not change the audit score.",10,-245)
        elseif section=="Notes" then
            local function formats(kind,y)
                local key=kind=="Main" and "mainFormat" or "altFormat"
                local choices={{"suffix-dash","Playername-"..kind},{"suffix-colon","Playername: "..kind},{"prefix-colon",kind..": Playername"}}
                local preview=label("Preview: "..S.NoteText("Playername",kind,p),10,y-42)
                local drop=track(U.Dropdown(content,kind.." note format",choices,function() return p[key] or "suffix-dash" end,function(value) p[key]=value; preview:SetText("Preview: "..S.NoteText("Playername",kind,p)) end,410))
                drop:SetPoint("TOPLEFT",10,y)
            end
            formats("Main",-10); formats("Alt",-105)
        elseif section=="Cleanup" then
            label("Use Roster → Filter inactive to review chapter cleanup candidates. Audit always uses 28 days. Rank-specific cleanup days below are suggestions for your chapter.",10,-10)
            local key=track(U.Dropdown(content,"Cleanup key",{{"CTRL-SHIFT-K","Ctrl+Shift+K"},{"CTRL-ALT-K","Ctrl+Alt+K"},{"ALT-SHIFT-K","Alt+Shift+K"}},function() return OldGodsGuildAuditDB.cleanupKey or "CTRL-SHIFT-K" end,function(value)
                if InCombatLockdown() then status:SetText("Leave combat before changing the cleanup key."); return end
                if OldGodsRosterTools then OldGodsRosterTools:Cancel() end
                OldGodsGuildAuditDB.cleanupKey=value; if S.OnChanged then S.OnChanged() end
                status:SetText("Personal cleanup key saved. Chapter rules still require Save.")
            end,360)); key:SetPoint("TOPLEFT",10,-80)
            for i=0,(GuildControlGetNumRanks() or 0)-1 do
                local rank=tostring(i); local row=p.ranks[rank] or {days=28,prefix=""}; p.ranks[rank]=row
                local input=entry((GuildControlGetRankName(i+1) or rank)..(i<=1 and " — exempt" or " — cleanup days"),10,-135-i*65,row.days,180,4)
                input:SetScript("OnTextChanged",function(self) row.days=tonumber(self:GetText()) end)
            end
        elseif section=="Recruiting" then
            local input=entry("Open realms",10,-10,table.concat(p.openRealms or {},", "),750,2000)
            input:SetScript("OnTextChanged",function(self) p.openRealms={}; for name in self:GetText():gmatch("[^,]+") do table.insert(p.openRealms,trim(name)) end end)
            label("Approved Open Realms skip the realm warning. Invitations still obey bans, quiet zones, guild membership and the seven-day anti-spam history. Quiet-zone reports and approvals are in Chapter → Quiet Zones.",10,-100)
        elseif section=="Announcement" then
            local input=entry("Chapter cleanup announcement",10,-10,p.announcement or "Beginning chapter inactivity cleanup. Please contact an officer with questions.",750,240)
            p.announcement=input:GetText()
            local preview=label("Preview: "..p.announcement,10,-90)
            input:SetScript("OnTextChanged",function(self) p.announcement=self:GetText(); preview:SetText("Preview: "..self:GetText()) end)
            label("Arm Announcement prepares this text. Ctrl+Shift+A sends it once to guild chat. Saving does not send an announcement.",10,-180)
        elseif section=="Bank" then
            local input=entry("Donations tab number (1–8)",10,-10,p.donationsTab or 1,180,1)
            local preview=label("",10,-90)
            local function update()
                p.donationsTab=tonumber(input:GetText())
                local valid=p.donationsTab and p.donationsTab%1==0 and p.donationsTab>=1 and p.donationsTab<=8
                local name=valid and GetGuildBankTabInfo and GetGuildBankTabInfo(p.donationsTab)
                preview:SetText(name and ("Selected tab: "..p.donationsTab.." — "..name) or "Open the guild bank to check the selected tab name. The tab number is used regardless of spelling.")
            end
            input:SetScript("OnTextChanged",update); update()
        else
            local current=S.Policy()
            label("Policy author: "..(current.author or "Default rules").."\nVersion: "..tostring(current.revision or 0).."\nSaved rules broadcast to online members. Newer versions replace older versions; general edits require Lead Officer or higher.\n\nCompanion: /reload or log out, then use Sync chapter rules. Uploads require website chapter management access. Downloaded rules apply after /reload and only to their matching guild. Your SavedVariables are never overwritten.",10,-10)
            local request=track(U.Button(content,"Request latest rules",function() send("Q|"..tostring(S.Key())); status:SetText("Requested rules from online leadership.") end,220)); request:SetPoint("TOPLEFT",10,-220)
        end
        content:SetHeight(section=="Cleanup" and 170+(GuildControlGetNumRanks() or 0)*65 or 370); scroll:SetVerticalScroll(0)
        if OldGodsTheme then OldGodsTheme.ApplyWindow(page) end
    end
    for i,name in ipairs({"General","Notes","Cleanup","Recruiting","Quiet Zones","Announcement","Bank","Sharing"}) do
        local button=U.Button(page,name,function() section=name; show() end,100)
        button:SetPoint("TOPLEFT",22+(i-1)*106,-105)
    end
    save=U.Button(page,"Save chapter rules",function()
        if loadedKey~=S.Key() then status:SetText("Chapter changed. Reopen this tab before saving."); return end
        if not fields.policy.donationsTab then status:SetText("Choose a donations tab number from 1 to 8."); return end
        -- Quiet-zone approvals save immediately; do not replace them with the
        -- chapter editor's older snapshot when saving unrelated pending edits.
        fields.policy.quietZones=S.Clone(S.Policy().quietZones or {})
        fields.policy.removedQuietZones=S.Clone(S.Policy().removedQuietZones or {})
        local ok,message=S.Save(fields.policy); status:SetText(message); if ok then refresh() end
    end,150); save:SetPoint("BOTTOMLEFT",22,20)
    page.Load=function()
        loadedKey=S.Key(); fields.policy=S.CopyPolicy(); fields.policy.donationsTab=fields.policy.donationsTab or 1; fields.policy.ranks={}
        for key,row in pairs(S.Policy().ranks or {}) do fields.policy.ranks[key]={days=row.days,prefix=row.prefix or ""} end
        if fields.policy.officerPrefix == nil then fields.policy.officerPrefix="Disc:" end
        save:SetEnabled(S.CanEdit()); status:SetText(S.CanEdit() and "Save applies edits from every section." or "Read-only chapter rules. Leadership shares updates with you."); show()
    end
end
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN"); events:RegisterEvent("CHAT_MSG_ADDON"); events:RegisterEvent("CLUB_FINDER_APPLICATIONS_UPDATED"); events:RegisterEvent("PLAYER_REGEN_ENABLED"); events:RegisterEvent("CLUB_FINDER_RECRUITS_UPDATED"); events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD"); events:RegisterEvent("ZONE_CHANGED_NEW_AREA"); events:RegisterEvent("ZONE_CHANGED"); events:RegisterEvent("ZONE_CHANGED_INDOORS"); events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("CHALLENGE_MODE_START"); events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:SetScript("OnEvent",function(_,event,...)
    if not OldGodsGuildAuditDB then return end
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
        C_Timer.After(5,function() S.Policy(); S.ImportCompanion(); send("Q|"..tostring(S.Key())); if CanGuildInvite() then C_ClubFinder.RequestApplicantList(Enum.ClubFinderRequestType.Guild) end end)
        C_Timer.NewTicker(30,function() if IsInGuild() and CanGuildInvite() then C_ClubFinder.RequestApplicantList(Enum.ClubFinderRequestType.Guild) end end)
    elseif event == "PLAYER_GUILD_UPDATE" then
        send("Q|"..tostring(S.Key()))
    elseif event == "CHAT_MSG_ADDON" then local p,m,c,s=...; if p == prefix then S.Receive(m,c,s) end
    else S.CheckApplicants() end
end)
SLASH_OGAPPLICANTS1="/ogaalerts"
SlashCmdList.OGAPPLICANTS=function(value)
    if not CanGuildInvite() then print("Old Gods Audit: Guild invite permission is required."); return end
    local mode=trim(value):lower(); mode=mode=="sound" and "Sound" or mode=="popup" and "Popup" or mode=="both" and "Both" or nil
    print("Old Gods Audit: Applicant notifications: "..S.Mode(mode)..". Options: /ogaalerts sound, popup, or both.")
end
