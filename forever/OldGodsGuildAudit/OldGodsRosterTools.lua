-- Session-only selections; kicks use size-limited batches, rank changes stay single-target.
OldGodsRosterTools = {selected = {}, selectedOnly = false}
local T = OldGodsRosterTools
local function locked() return InCombatLockdown and InCombatLockdown() end
local function public(v) return not issecretvalue or not issecretvalue(v) end
local function text(v) return public(v) and tostring(v or ""):lower() or "" end
function T:OfflineDays(index, online)
    if public(online) and online then return 0 end
    if not GetGuildRosterLastOnline then return nil end
    local years, months, days, hours = GetGuildRosterLastOnline(index)
    for _, value in ipairs({years, months, days}) do if not public(value) or type(value) ~= "number" then return nil end end
    if not years or not months or not days or not public(hours) then return nil end
    return years * 365 + months * 30 + days + (hours or 0) / 24
end

function T:Matches(member, query, mode)
    local fields = {
        name = text(member.name), realm = text(text(member.name):match("%-(.+)$") or GetNormalizedRealmName()),
        notes = text(member.publicNote) .. " " .. text(member.officerNote),
        public = text(member.publicNote), officer = text(member.officerNote), rank = text(member.rankName),
        class = text(member.className) .. " " .. text(member.classFile), level = text(member.level),
        zone = text(member.zone), status = member.online and "online" or "offline",
        achievements = text(member.achievementPoints), reputation = text(member.reputation),
        mobile = member.isMobile and "yes" or "no", presence = member.status == 1 and "afk" or member.status == 2 and "dnd busy" or "available",
        inactive = member.offlineDays ~= nil and text(member.offlineDays) or "unknown", rankindex = text(member.rankIndex),
    }
    local link=OldGodsCharacters and OldGodsCharacters:Link(member.name)
    if link then fields.main=text(link.main); fields.relationship=text(link.role); fields.alts=text(table.concat(link.alts or {}," ")) end
    fields.server = fields.realm
    fields.lastonline = fields.inactive
    fields.status = fields.status .. " " .. fields.presence .. (member.isMobile and " mobile" or "")
    local all = {}
    for _, value in pairs(fields) do all[#all + 1] = value end
    local haystack = mode == "name" and fields.name or mode == "notes" and fields.notes or table.concat(all, " ")
    -- Commas OR groups; whitespace AND terms; quoted phrases preserve spaces/commas.
    local groups, group, token, quoted = {}, {}, "", false
    local function flush() if token ~= "" then group[#group + 1] = token; token = "" end end
    query = text(query)
    for i = 1, #query do
        local c = query:sub(i, i)
        if c == '"' then quoted = not quoted
        elseif not quoted and c == "," then flush(); if #group > 0 then groups[#groups + 1] = group end; group = {}
        elseif not quoted and c:match("%s") then flush()
        else token = token .. c end
    end
    flush(); if #group > 0 then groups[#groups + 1] = group end
    if #groups == 0 then return true end
    for _, terms in ipairs(groups) do
        local matches = true
        for _, term in ipairs(terms) do
            local field, value = term:match("^(%a+):(.*)$")
            local target = field and fields[field] or haystack
            local comparison, number = (value or ""):match("^([<>=]+)(%d+%.?%d*)$")
            if field and not fields[field] then matches = false
            elseif comparison then
                local actual, expected = tonumber(target), tonumber(number)
                local passed = actual and (comparison == ">=" and actual >= expected or comparison == "<=" and actual <= expected
                    or comparison == ">" and actual > expected or comparison == "<" and actual < expected or comparison == "=" and actual == expected)
                if not passed then matches = false end
            elseif not target:find(value or term, 1, true) then matches = false end
        end
        if matches then return true end
    end
    return false
end

function T:Key(member) return member.guid or member.name end
function T:Count() local n = 0; for _ in pairs(self.selected) do n = n + 1 end; return n end
function T:Refresh() if self.render then self.render() end end
function T:SyncGuild()
    local guild = self.guildKey()
    if guild ~= self.guild then self:Cancel(); self.selected = {}; self.guild = guild end
end
function T:Toggle(member, checked)
    self:Cancel()
    self.selected[self:Key(member)] = checked and {name=member.name, guid=member.guid} or nil
    self:Refresh()
end
function T:OwnsMacro(index)
    if not GetMacroBody then return false end
    local body = GetMacroBody(index)
    return body == "" or (type(body) == "string" and body:sub(-#"\n/run OldGodsRosterTools:Sent()") == "\n/run OldGodsRosterTools:Sent()")
end
function T:Cancel(message)
    if locked() then self.cancelPending = true; self.queue = nil; return end
    if self.owner then ClearOverrideBindings(self.owner) end
    local index = GetMacroIndexByName and GetMacroIndexByName("OGGA_Roster")
    if index and index > 0 and EditMacro and self:OwnsMacro(index) then EditMacro(index, "OGGA_Roster", "INV_MISC_QUESTIONMARK", "") end
    self.queue, self.current, self.waiting, self.cancelPending = nil, nil, nil, nil
    self.batch, self.batchEnd = nil, nil
    self.message = message or "Selection actions disarmed."
end

function T:LiveRoster()
    local count = GetNumGuildMembers() or 0
    if count == 0 then return nil end
    local roster = {}
    for i = 1, count do
        local name, _, rank, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if not public(name) or not public(rank) or not public(guid) or type(name) ~= "string" or type(rank) ~= "number" then return nil end
        roster[name] = {name=name, rank=rank, guid=guid}
    end
    return roster
end
function T:Eligible(member, action)
    if action == "invite" then
        return not OldGodsFeedback.Banned(member.name, member.guid)
            and member.name ~= (UnitName("player") .. "-" .. GetNormalizedRealmName())
            and (not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
    end
    local permission = action == "kick" and CanGuildRemove or action == "promote" and CanGuildPromote or CanGuildDemote
    local _, _, ownRank = GetGuildInfo("player")
    if not permission or not permission() or not public(ownRank) or type(ownRank) ~= "number" then return false end
    if member.rank <= ownRank then return false end
    if action == "promote" and member.rank - 1 <= ownRank then return false end
    if action == "demote" and member.rank >= (GuildControlGetNumRanks() or 0) - 1 then return false end
    return true
end
function T:PrepareNext(remaining)
    if locked() or not self.queue then return end
    local target = remaining and remaining[1] or self.queue[self.position]
    if not target then self:Cancel("Selection queue complete."); self:Refresh(); return end
    local roster = self:LiveRoster()
    local command = self.action == "invite" and "/invite" or self.action == "kick" and "/gremove" or "/g" .. self.action
    local body, suffix = "/stopmacro [combat]", "\n/run OldGodsRosterTools:Sent()"
    local batch, batchEnd = {}, self.position - 1
    local candidates, first = remaining or self.queue, remaining and 1 or self.position
    for i = first, #candidates do
        local candidate = candidates[i]
        local line = "\n" .. command .. " " .. candidate.name
        if #body + #line + #suffix > 255 then break end
        local live = roster and roster[candidate.name]
        if not live or (candidate.guid and candidate.guid ~= live.guid) or live.rank ~= candidate.rank or not self:Eligible(live, self.action) then
            self:Cancel("Queue stopped: target changed or is no longer eligible. Review selection and arm again."); self:Refresh(); return
        end
        body = body .. line
        batch[#batch + 1] = candidate
        batchEnd = i
        if self.action ~= "kick" then break end
    end
    if #batch == 0 then self:Cancel("Target name exceeds macro capacity."); self:Refresh(); return end
    body = body .. suffix
    local ok, reason = pcall(function()
        local index = GetMacroIndexByName("OGGA_Roster")
        if index == 0 then index = CreateMacro("OGGA_Roster", "INV_MISC_QUESTIONMARK", body)
        else
            assert(self:OwnsMacro(index), "A different OGGA_Roster macro exists. Rename it before arming.")
            EditMacro(index, "OGGA_Roster", "INV_MISC_QUESTIONMARK", body)
        end
        assert(index and index > 0, "Free one General Macro slot.")
        self.macroIndex = index
        self.owner = self.owner or CreateFrame("Frame", "OldGodsRosterQueueBinding", UIParent)
        SetOverrideBindingMacro(self.owner, true, self.key, index)
    end)
    if not ok then self:Cancel("Cannot arm macro: " .. tostring(reason)); self:Refresh(); return end
    self.current, self.waiting = target, false
    self.batch = batch
    if not remaining then self.batchEnd = batchEnd end
    if self.action == "kick" then
        self.message = string.format("Kick batch %d-%d/%d (%d remaining players) | %s once, then wait", self.position, self.batchEnd, #self.queue, #batch, self.key)
    else
        self.message = string.format("%s %d/%d: %s | %s once", self.action, self.position, #self.queue, target.name, self.key)
    end
    self:Refresh()
end
function T:Arm(action)
    if action ~= "kick" and action ~= "promote" and action ~= "demote" and action ~= "invite" then return end
    if locked() then self.message = "Leave combat before arming."; self:Refresh(); return end
    self:SyncGuild(); self:Cancel(); self.clearOtherBindings()
    local roster = self:LiveRoster()
    if not roster then self.message = "Refresh the complete guild roster before arming."; self:Refresh(); return end
    local queue = {}
    for key, member in pairs(self.selected) do
        local live = roster[member.name]
        if not live or (member.guid and member.guid ~= live.guid) or not self:Eligible(live, action)
            or live.name == "" or live.name:find("[%s/%c]") then
            self.message = "Cannot arm: " .. member.name .. " left, changed, or is not eligible. Uncheck and retry."
            self:Refresh(); return
        end
        queue[#queue + 1] = {name=live.name, guid=live.guid, rank=live.rank, selectionKey=key}
    end
    if #queue == 0 then self.message = "Check players before arming."; self:Refresh(); return end
    table.sort(queue, function(a,b) return a.name < b.name end)
    self.action, self.queue, self.position = action, queue, 1
    self.key = action == "kick" and ((OldGodsGuildAuditDB or {}).cleanupKey or "CTRL-SHIFT-K") or action == "promote" and "CTRL-SHIFT-P" or action == "invite" and "CTRL-SHIFT-G" or "CTRL-SHIFT-D"
    self:PrepareNext()
end
function T:Sent()
    if locked() or not self.current or self.waiting then return end
    -- Consume this macro before another keypress. Only a confirmed roster change advances it.
    ClearOverrideBindings(self.owner)
    local index = GetMacroIndexByName("OGGA_Roster")
    if index and index > 0 and self:OwnsMacro(index) then EditMacro(index, "OGGA_Roster", "INV_MISC_QUESTIONMARK", "") end
    self.waiting = true
    if self.action == "invite" then
        self.selected[self.current.selectionKey] = nil
        self.position = self.position + 1
        -- Never rewrite the running macro until its hardware event has finished.
        local queue = self.queue
        C_Timer.After(0, function() if self.queue == queue then self:PrepareNext() end end)
        self.message = "Group invite attempted: " .. self.current.name .. " (acceptance not tracked)."
        self:Refresh(); return
    end
    self.message = self.action == "kick" and string.format("Waiting for roster confirmation: %d kick targets. If rejected, cancel and review.", #self.batch)
        or "Waiting for roster confirmation: " .. self.current.name .. ". If rejected, cancel and review."
    C_GuildInfo.GuildRoster()
    self:Refresh()
end
function T:Update()
    if locked() then return end
    if self.cancelPending then self:Cancel(); self:Refresh(); return end
    self:SyncGuild()
    if not self.current then return end
    if self.action == "invite" and self.waiting then self:PrepareNext(); return end
    local roster = self:LiveRoster()
    if not roster then return end
    if self.action == "kick" then
        local remaining = {}
        for _, member in ipairs(self.batch) do
            local live = roster[member.name]
            if self.waiting and not live then
                print("Old Gods Audit: Roster confirms "..member.name.." is no longer in the guild.")
                self.selected[member.selectionKey] = nil
            elseif not live or live.rank ~= member.rank or (member.guid and member.guid ~= live.guid) or not self:Eligible(live, "kick") then
                self:Cancel("Queue stopped: roster or permissions changed. Review selection."); self:Refresh(); return
            else remaining[#remaining + 1] = member end
        end
        if self.waiting and #remaining == 0 then
            self.position = self.batchEnd + 1
            self:PrepareNext()
        elseif self.waiting and #remaining < #self.batch then
            -- Retry only this batch's survivors. Never mix in targets from the next batch.
            self:PrepareNext(remaining)
        end
        return
    end
    local live, current = roster[self.current.name], self.current
    local confirmed = self.action == "promote" and live and live.rank == current.rank - 1
        or self.action == "demote" and live and live.rank == current.rank + 1
    if self.waiting and confirmed and (not live or not current.guid or current.guid == live.guid) then
        self.selected[current.selectionKey] = nil
        self.position = self.position + 1
        self:PrepareNext()
    elseif not live or live.rank ~= current.rank or (current.guid and current.guid ~= live.guid) or not self:Eligible(live, self.action) then
        self:Cancel("Queue stopped: roster or permissions changed. Review selection."); self:Refresh()
    end
end

function T:StopBanPrompts()
    self.banReview = nil
    if self.banPrompt then self.banPrompt:Hide() end
end
function T:AddSelectedBans()
    self:SyncGuild(); self:Cancel(); self:StopBanPrompts()
    local members = {}
    for _, member in pairs(self.selected) do
        members[#members+1] = {name=member.name, guid=member.guid}
    end
    table.sort(members, function(a,b) return a.name < b.name end)
    self.banReview = {members=members, position=1, guild=self.guild, added=0, kept=0, skipped=0}
    self:NextBanPrompt()
end
function T:NextBanPrompt()
    local review = self.banReview
    if not review then return end
    if self.guildKey() ~= review.guild then self:StopBanPrompts(); return end
    local member = review.members[review.position]
    while member and OldGodsFeedback.Banned(member.name, member.guid) do
        review.kept=review.kept+1; review.position=review.position+1
        member=review.members[review.position]
    end
    if not member then
        self.message=string.format("Added %d bans; preserved %d existing; skipped %d. No guild removals performed.",review.added,review.kept,review.skipped)
        self:StopBanPrompts(); self:Refresh(); return
    end
    self:ShowBanPrompt(member, review.position, #review.members)
end
function T:ConfirmBanReason(reason)
    local review=self.banReview
    if not review then return end
    if self.guildKey() ~= review.guild then self:StopBanPrompts(); return end
    local member=review.members[review.position]
    if OldGodsFeedback.Banned(member.name,member.guid) then self:NextBanPrompt(); return end
    local ok,message=OldGodsFeedback.AddBan(member.name,reason,{guid=member.guid,source="Roster selection"},true)
    if not ok then return false,message end
    self.lastBanReason=reason
    review.added=review.added+1; review.position=review.position+1
    if OldGodsFeedback.OnChanged then OldGodsFeedback.OnChanged() end
    self:NextBanPrompt()
    return true
end
function T:SkipBanPrompt()
    local review=self.banReview
    if not review then return end
    review.skipped=review.skipped+1; review.position=review.position+1
    self:NextBanPrompt()
end
function T:ShowBanPrompt(member, position, total)
    if not self.banPrompt then
        local w=CreateFrame("Frame","OldGodsRosterBanPrompt",UIParent,"BasicFrameTemplateWithInset")
        self.banPrompt=w
        w:SetSize(540,260); w:SetPoint("CENTER"); w:SetFrameStrata("FULLSCREEN_DIALOG"); w:SetClampedToScreen(true)
        w.TitleText:SetText("Ban selected character")
        w.character=w:CreateFontString(nil,"OVERLAY","GameFontNormal")
        w.character:SetPoint("TOPLEFT",20,-42); w.character:SetWidth(500); w.character:SetJustifyH("LEFT")
        w.label=w:CreateFontString(nil,"OVERLAY","GameFontNormal")
        w.label:SetPoint("TOPLEFT",20,-74); w.label:SetText("Ban reason (required)")
        w.reason=CreateFrame("EditBox",nil,w,"InputBoxTemplate")
        w.reason:SetSize(490,28); w.reason:SetPoint("TOPLEFT",24,-98); w.reason:SetAutoFocus(false); w.reason:SetMaxLetters(300)
        OldGodsUI.Help(w.reason,"Ban reason","Enter a reason for this character. The last confirmed reason is filled in for reuse; edit it before confirming if needed.")
        w.status=w:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        w.status:SetPoint("TOPLEFT",20,-138); w.status:SetWidth(500); w.status:SetJustifyH("LEFT")
        local confirm=OldGodsUI.Button(w,"Confirm ban",function()
            local ok,message=self:ConfirmBanReason(w.reason:GetText())
            if ok==false then w.status:SetText(message) end
        end,140)
        confirm:SetPoint("BOTTOMRIGHT",-20,18)
        local skip=OldGodsUI.Button(w,"Skip character",function() self:SkipBanPrompt() end,140)
        skip:SetPoint("RIGHT",confirm,"LEFT",-8,0)
        local cancel=OldGodsUI.Button(w,"Cancel remaining",function() self:StopBanPrompts() end,150)
        cancel:SetPoint("RIGHT",skip,"LEFT",-8,0)
        w.reason:SetScript("OnEscapePressed",function() self:StopBanPrompts() end)
        w:SetScript("OnHide",function() self.banReview=nil; w.reason:ClearFocus() end)
        UISpecialFrames[#UISpecialFrames+1]="OldGodsRosterBanPrompt"
    end
    local w=self.banPrompt
    w.character:SetText(string.format("What is the reason for banning %s?",member.name))
    w.reason:SetText(self.lastBanReason or "")
    w.label:SetText(string.format("Ban reason (required) — character %d of %d",position,total))
    w.status:SetText("Confirm this character only. This does not remove them from the guild.")
    w:Show(); OldGodsTheme.RegisterWindow(w); w.reason:SetFocus(); w.reason:HighlightText()
end

function T:BuildControls(page, button)
    self.page = page
    local review = button(page, "Selected only", function()
        self.selectedOnly = not self.selectedOnly; self:Refresh()
    end, 110); review:SetPoint("TOPLEFT", 312, -69); self.reviewButton = review
    local clear = self:IconButton(page, button, "Clear selection", "deselect", function() self:Cancel(); self.selected = {}; self:Refresh() end)
    clear:SetPoint("TOPLEFT", 430, -64)
    local cancel = self:IconButton(page, button, "Disarm", "disarm", function() self:Cancel(); self.clearOtherBindings(); self:StopBanPrompts(); self:Refresh() end)
    cancel:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    self.selectionText = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.selectionText:SetPoint("LEFT", cancel, "RIGHT", 8, 0)
    page.extraTexts[#page.extraTexts + 1] = self.selectionText
    for i, item in ipairs({{"promote", "Arm Promote (P)"}, {"demote", "Arm Demote (D)"}, {"kick", "Arm Kick (K)"}, {"invite", "Arm Group Invite (G)"}}) do
        local action = item[1]
        local control = self:IconButton(page, button, item[2], action, function() self:Arm(action) end)
        control:SetPoint("TOPLEFT", 24 + (i-1)*40, -64)
    end
    local add = self:IconButton(page, button, "Add selected bans", "ban", function() self:AddSelectedBans() end)
    add:SetPoint("TOPLEFT",184,-64)
    local whisper = self:IconButton(page, button, "Whisper selected", "whisper", function()
        local members = {}; for _, member in pairs(self.selected) do members[#members+1]=member end
        table.sort(members, function(a,b) return a.name<b.name end)
        if #members~=1 then self.message="Select one player to open a whisper."; self:Refresh(); return end
        local member=members[1]
        if OldGodsFeedback.Banned(member.name,member.guid) then self.message="Outreach blocked by the Ban List."; self:Refresh(); return end
        local sendTell=ChatFrameUtil and ChatFrameUtil.SendTell or ChatFrame_SendTell
        if not sendTell then self.message="Whisper is unavailable in this client."; self:Refresh(); return end
        local ok=pcall(function()
            if securecallfunction then securecallfunction(sendTell,member.name) else sendTell(member.name) end
        end)
        self.message=ok and ("Whisper opened for "..member.name..".") or "Could not open whisper. Try Blizzard's roster menu."
        self:Refresh()
    end)
    whisper:SetPoint("TOPLEFT",224,-64)
    page.viewEventsButton=self:IconButton(page,button,"View Events","events",function()
        local member=page.focusedMember
        if page.viewEvents then page.viewEvents(member) end
    end)
    page.viewEventsButton:SetPoint("TOPLEFT",264,-64)
    self.queueText = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.queueText:SetPoint("TOPLEFT", 24, -141); self.queueText:SetWidth(830); self.queueText:SetJustifyH("LEFT")
    page.extraTexts[#page.extraTexts + 1] = self.queueText
end
function T:IconButton(page, button, label, texture, callback)
    return OldGodsAssets.Button(page,button,label,texture,callback)
end
function T:RenderControls()
    if not self.selectionText then return end
    self.selectionText:SetText(string.format("%d selected", self:Count()))
    self.reviewButton:SetText(self.selectedOnly and "Show all" or "Selected only")
    self.queueText:SetText(self.message or "Check players, review Selected only, then arm an action. Hover icons for help.")
end

function T:Tooltip(row, member)
    if not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(member.name or "Unknown")
    local link=OldGodsCharacters and OldGodsCharacters:Link(member.name)
    if link then
        GameTooltip:AddLine(link.role .. " | Main: " .. link.main, 0.8, 0.7, 1, true)
        GameTooltip:AddLine("Ownership source: " .. (link.source=="blizzard" and "Blizzard" or "Player-entered"),1,1,1)
        if #(link.alts or {})>0 then GameTooltip:AddLine("Other guild characters: " .. table.concat(link.alts,", "),1,1,1,true) end
    else GameTooltip:AddLine("Main / Alt: player has not linked this character.",0.7,0.7,0.7) end
    GameTooltip:AddLine("Zone: " .. (member.zone or "Unknown"), 1, 1, 1)
    GameTooltip:AddLine("Achievement points: " .. tostring(member.achievementPoints or "Unknown"), 1, 1, 1)
    GameTooltip:AddLine("Guild reputation (API value): " .. tostring(member.reputation or "Unknown"), 1, 1, 1)
    GameTooltip:AddLine("Mobile: " .. (member.isMobile and "Yes" or "No") .. " | " .. (member.status == 1 and "AFK" or member.status == 2 and "DND" or "Available"), 1, 1, 1)
    GameTooltip:AddLine("Days offline (approx.): " .. (member.offlineDays and string.format("%.1f", member.offlineDays) or "Unknown"), 1, 1, 1)
    GameTooltip:AddLine("Presence: " .. (member.online and "Online" or "Offline"),1,1,1)
    GameTooltip:AddLine("Public note: " .. (member.publicNote or ""),1,1,1,true)
    GameTooltip:AddLine("Officer note: " .. (member.officerNote or ""),1,1,1,true)
    GameTooltip:Show()
end

function T:StyleRow(row,hover)
    local colors=OldGodsTheme.Colors()
    local base=colors.card; local amount=hover and 0.10 or 0
    row:SetBackdropColor(base[1]+(colors.text[1]-base[1])*amount,base[2]+(colors.text[2]-base[2])*amount,base[3]+(colors.text[3]-base[3])*amount,1)
    row:SetBackdropBorderColor(unpack(colors.border))
    for _,line in ipairs(row.lines or {}) do line:SetTextColor(unpack(colors.text)) end
end
-- Stable sorting preserves selection identity and keeps unknown values last.
T.columns={{"level","Lvl",38},{"className","Class",70},{"name","Name",170},{"zone","Zone",106},{"rankName","Rank",82},{"publicNote","Note",170},{"achievementPoints","Achievement Points",112},{"faction","Faction",68}}
function T:Sort(members)
    local key=self.sortKey or "name"
    table.sort(members,function(a,b)
        local left,right=a[key],b[key]
        if left==nil or right==nil then if left~=right then return right==nil end
        else
            if type(left)=="boolean" then left=left and 1 or 0; right=right and 1 or 0 end
            if type(left)=="string" then left=left:lower(); right=tostring(right):lower() end
            if left~=right then if self.sortDescending then return left>right else return left<right end end
        end
        return (a.name or "")<(b.name or "")
    end)
end
function T:BuildTableHeader(page,button)
    local x=58
    for _,column in ipairs(self.columns) do
        local key=column[1]
        local header=button(page,column[2],function()
            if self.sortKey==key then self.sortDescending=not self.sortDescending else self.sortKey=key; self.sortDescending=false end
            self:Refresh()
        end,column[3]-2)
        header:SetPoint("TOPLEFT",x,-164); x=x+column[3]
        header:GetFontString():SetFontObject("GameFontHighlightSmall")
        OldGodsUI.Help(header,column[2],"Sort by "..column[2]..". Click again to reverse the order. Checked players remain selected.")
    end
    local days=CreateFrame("EditBox",nil,page,"InputBoxTemplate")
    local settings=OldGodsGuildAuditDB
    local savedDays=tonumber(settings.rosterInactiveDays) or 28
    if savedDays%1~=0 or savedDays<1 or savedDays>3650 then savedDays=28 end
    days:SetPoint("TOPLEFT",58,-108); days:SetSize(55,24); days:SetAutoFocus(false); days:SetMaxLetters(4); days:SetText(tostring(savedDays))
    OldGodsUI.Help(days,"Cleanup days","Enter a whole number of days offline. This changes only the roster search, never the audit.")
    local filter=CreateFrame("CheckButton",nil,page,"UICheckButtonTemplate")
    filter:SetSize(26,26); filter:SetPoint("TOPLEFT",24,-108)
    filter:SetChecked(settings.rosterInactiveEnabled == true)
    self.inactiveDays=filter:GetChecked() and savedDays or nil
    OldGodsUI.Help(filter,"Filter inactive")
    local function applyFilter()
        local n=tonumber(days:GetText())
        if filter:GetChecked() and (not n or n%1~=0 or n<1 or n>3650) then filter:SetChecked(false); settings.rosterInactiveEnabled=false; self.inactiveDays=nil; self.message="Enter 1–3650 whole days."; self:Refresh(); return end
        if n and n%1==0 and n>=1 and n<=3650 then settings.rosterInactiveDays=n end
        settings.rosterInactiveEnabled=filter:GetChecked() and true or false
        self.inactiveDays=filter:GetChecked() and n or nil; self:Refresh()
    end
    filter:SetScript("OnClick",applyFilter)
    days:SetScript("OnEnterPressed",function() days:ClearFocus(); applyFilter() end)
    days:SetScript("OnEditFocusLost",applyFilter)
end
