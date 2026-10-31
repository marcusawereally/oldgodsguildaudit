-- Hardware-activated guild recruitment batches. Timers only prepare the next macro.
OldGodsRecruiting={buttons=setmetatable({},{__mode='k'}),approved={},generation=0}
local R=OldGodsRecruiting
local NAME='OGGA_Recruit'
local SUFFIX='\n/run OldGodsRecruitSent()'
local GUARD='/stopmacro [combat]'
local DORMANT='/stopmacro'..SUFFIX
local function macroBody(index)
    local body=GetMacroBody and GetMacroBody(index)
    return type(body)=='string' and body:gsub('\r\n','\n'):gsub('%s+$','') or body
end
local function locked() return InCombatLockdown and InCombatLockdown() end
local function permitted() return not locked() and CanGuildInvite and CanGuildInvite() end
function R:Owns(index)
    local body=macroBody(index)
    return type(body)=='string' and body:sub(-#SUFFIX)==SUFFIX
end
function R:FindMacro()
    local freeName
    for n=0,99 do
        local name=n==0 and NAME or NAME..'_'..n
        local index=GetMacroIndexByName(name)
        if index and index>0 then
            if self:Owns(index) then return index,name end
        elseif not freeName then freeName=name end
    end
    return 0,freeName
end
function R:Context()
    local guild=OldGodsFeedback.GuildKey()
    return guild and (guild..'|'..(UnitName('player') or '')..'|'..GetNormalizedRealmName())
end
function R:Bind(index)
    if locked() then return end
    for button in pairs(self.buttons) do
        button:SetAttribute('macro',index)
        button.oldGodsHelpKey=index and 'Invite' or 'Prepare Invite'
        button:SetText(button.oldGodsHelpKey)
    end
end
function R:Cancel(message)
    self.generation=self.generation+1
    self.batch,self.waiting,self.body=nil,nil,nil
    self.approved={}; self.message=message
    if locked() then self.clearPending=true; return end
    self.clearPending=nil; self:Bind(nil)
    local index=GetMacroIndexByName and GetMacroIndexByName(self.macroName or NAME)
    if index and index>0 and self:Owns(index) then EditMacro(index,self.macroName or NAME,'INV_MISC_QUESTIONMARK',DORMANT) end
end
function R:CommandName(candidate)
    local name=candidate.fullName
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name)~='string' or name=='' or name:find('[%s/|%c]') then return nil end
    local short,realm=name:match('^(.-)%-(.+)$')
    if short and (realm==GetNormalizedRealmName() or realm==(GetRealmName() or ''):gsub(' ','')) then return short end
    return name
end
function R:Build(includeReview)
    local choices,seen={},{}
    for _,candidate in ipairs(self.getCandidates and self.getCandidates() or {}) do
        local name=self:CommandName(candidate)
        local state=OldGodsFeedback.Eligibility(candidate)
        if name and not seen[candidate.fullName] and (state=='Eligible' or (state=='Review' and (includeReview or self.approved[candidate.fullName]))) then
            choices[#choices+1]={candidate=candidate,line='\n/ginvite '..name,review=state=='Review'}
            seen[candidate.fullName]=true
        end
    end
    -- Shortest complete lines first maximizes the number of names within 255 bytes.
    table.sort(choices,function(a,b) if #a.line==#b.line then return a.candidate.fullName<b.candidate.fullName end;return #a.line<#b.line end)
    local body,batch=GUARD,{}
    for _,choice in ipairs(choices) do
        if #body+#choice.line+#SUFFIX>255 then break end
        body=body..choice.line;batch[#batch+1]=choice.candidate
    end
    if #batch==0 then return nil end
    return body..SUFFIX,batch
end
function R:Refresh(prepare)
    self.error=nil
    if locked() then return end
    if self.clearPending then self:Cancel() end
    local context=self:Context()
    if context~=self.context then self:Cancel();self.context=context end
    if self.waiting then return end
    if not context or not permitted() then self:Cancel('Leave combat and check guild invite permission.'); return end
    if self.batch then
        if self:Valid() then self:Bind(self.index);return end
        self:Cancel('The prepared batch changed. Click Prepare Invite again.')
    end
    if not prepare then self:Bind(nil);self.message=self.message or 'Click Prepare Invite to build a macro batch.';return end
    local body,batch=self:Build(false)
    if not body then
        self:Bind(nil); self.batch,self.body=nil,nil
        local index=GetMacroIndexByName and GetMacroIndexByName(self.macroName or NAME)
        if index and index>0 and self:Owns(index) then EditMacro(index,self.macroName or NAME,'INV_MISC_QUESTIONMARK',DORMANT) end
        self.message=self:Build(true) and 'Some candidates need review. Click Prepare Invite to review the next batch.' or 'No candidates available for an invite batch.'
        return
    end
    if not GetMacroIndexByName or not CreateMacro or not EditMacro or not GetRunningMacro then self.error=true;self.message='Macro functions are unavailable in this client.';self:Bind(nil);return end
    local index,name=self:FindMacro()
    if not name then self.error=true;self.message='No free recruiting macro name. Rename an unused OGGA_Recruit macro.';self:Bind(nil);return end
    self.macroName=name
    local ok,result=pcall(function()
        if not index or index==0 then
            local count=GetNumMacros and GetNumMacros() or 0
            assert(not MAX_ACCOUNT_MACROS or count<MAX_ACCOUNT_MACROS,'Free one General Macro slot.')
            return CreateMacro(name,'INV_MISC_QUESTIONMARK',body)
        end
        if macroBody(index)~=body then EditMacro(index,name,'INV_MISC_QUESTIONMARK',body) end
        return index
    end)
    if not ok or not result or result==0 then self.error=true;self.message='Cannot prepare invite macro: '..tostring(result);self:Bind(nil);return end
    self.index,self.batch,self.body=result,batch,body
    self.message=string.format('Next macro: %d invitations (%d/255 bytes). Each click attempts one batch.',#batch,#body)
    self:Bind(result)
end
function R:Valid()
    if not permitted() or self:Context()~=self.context or not self.batch or self.waiting then return false end
    if not self:Owns(self.index) or macroBody(self.index)~=self.body then return false end
    local present={};for _,candidate in ipairs(self.getCandidates()) do present[candidate]=true end
    for _,candidate in ipairs(self.batch) do
        local state=OldGodsFeedback.Eligibility(candidate)
        if not present[candidate] or state=='Blocked' or (state=='Review' and not self.approved[candidate.fullName]) then return false end
    end
    return true
end
function R:Attach(button)
    self.buttons[button]=true
    button:RegisterForClicks('AnyUp')
    button:SetAttribute('type','macro');button:SetAttribute('useOnKeyDown',false);button:SetText('Prepare Invite')
    button:HookScript('PreClick',function()
        if not locked() and not R:Valid() then R:Cancel('The batch changed. Click Prepare Invite to build the current candidates.') end
    end)
end
function R:Clicked()
    if not permitted() or self.waiting then return end
    if self.batch then
        -- The footer must have run before PostClick. Do not silently repeat a
        -- partially executed macro when the client rejected its completion hook.
        self:Cancel('Macro completion was not observed. Review WoW errors before retrying.')
        print('Old Gods Audit: '..self.message);return
    end
    self:Refresh(true)
    if self.batch then return end
    if self.error then print('Old Gods Audit: '..self.message);return end
    local _,review=self:Build(true)
    if not review then print('Old Gods Audit: '..(self.message or 'No candidates available.'));return end
    local names={}
    for _,candidate in ipairs(review) do self.approved[candidate.fullName]=true;names[#names+1]=candidate.fullName end
    print('Old Gods Audit: Review these macro targets: '..table.concat(names,', ')..'. Click Invite again to attempt this batch. WoW checks faction and eligibility.')
    self:Refresh(true)
    if self.changed then self.changed() end
end
function R:Sent()
    if locked() or not self.batch or self.waiting or not GetRunningMacro or GetRunningMacro()~=self.index or self:Context()~=self.context then return end
    if not self:Owns(self.index) or macroBody(self.index)~=self.body then return end
    local batch=self.batch
    self.batch,self.body=nil,nil;self.waiting=true;self:Bind(nil)
    EditMacro(self.index,self.macroName or NAME,'INV_MISC_QUESTIONMARK',DORMANT)
    for _,candidate in ipairs(batch) do if self.onAttempt then self.onAttempt(candidate) end end
    print(string.format('Old Gods Audit: Macro attempted %d guild invitations; acceptance and server delivery are not confirmed.',#batch))
    local generation=self.generation
    C_Timer.After(0,function()
        if R.generation~=generation then return end
        R.waiting=nil;R:Refresh(true)
        if R.changed then R.changed() end
    end)
end
function OldGodsRecruitSent() R:Sent() end
