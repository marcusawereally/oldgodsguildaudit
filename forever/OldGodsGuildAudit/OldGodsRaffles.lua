OldGodsRaffles={}
local R=OldGodsRaffles
local empty="00000000-0000-0000-0000-000000000000"
local function copy(v) if type(v)~="table" then return v end local r={};for k,x in pairs(v) do r[k]=copy(x) end;return r end
local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") end
function R.Id() return ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]",function(c) return string.format("%x",c=="x" and math.random(0,15) or math.random(8,11)) end) end
function R.Money(c) c=tonumber(c) or 0;return string.format("%.0fg %.0fs %.0fc",math.floor(c/10000),math.floor(c%10000/100),c%100) end
function R.Date(t) return t and t>0 and date("!%Y-%m-%d %H:%M",t) or "Not set" end
function R.Time(text)
    local y,m,d,h,n=trim(text):match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
    if not y then return nil end
    y,m,d,h,n=tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(n)
    if m<1 or m>12 or d<1 or d>31 or h>23 or n>59 or y<1970 or y>9999 then return nil end
    local days={31,(y%4==0 and (y%100~=0 or y%400==0)) and 29 or 28,31,30,31,30,31,31,30,31,30,31}
    if d>days[m] then return nil end
    -- Civil UTC conversion is independent of the player's timezone and daylight saving.
    local year=y-(m<=2 and 1 or 0);local era=math.floor(year/400);local yo=year-era*400
    local shifted=m+(m>2 and -3 or 9)
    local day=math.floor((153*shifted+2)/5)+d-1
    return (era*146097+yo*365+math.floor(yo/4)-math.floor(yo/100)+day-719468)*86400+h*3600+n*60
end
function R:State()
    OldGodsGuildAuditDB=OldGodsGuildAuditDB or {};OldGodsGuildAuditDB.raffleSync=OldGodsGuildAuditDB.raffleSync or {operations={}}
    local state=OldGodsGuildAuditDB.raffleSync;state.operations=state.operations or {}
    if self.applied~=OldGodsRaffleImports then
        for id,result in pairs((OldGodsRaffleImports or {}).results or {}) do
            local op=state.operations[id]
            if op then if result.state=="accepted" then self.lastResult="Accepted: "..result.message;state.operations[id]=nil else op.result=copy(result) end end
        end
        self.applied=OldGodsRaffleImports
    end
    return state
end
function R:Snapshot()
    self:State();local data=OldGodsRaffleImports or {}
    if data.gameVersion~=(OldGodsGameProfile or "retail") then return {scopes={},records={},actorId="",syncedAt=0,entries={},draws={}} end
    return data
end
function R:Pending(id)
    for _,op in pairs(self:State().operations) do if op.mutation.raffleId==id then return op end end
end
function R:Records()
    local result,seen={},{}
    for _,d in ipairs(self:Snapshot().records or {}) do if d.status~="deleted" then result[#result+1]=d;seen[d.id]=true end end
    for _,op in pairs(self:State().operations) do local m=op.mutation;if not seen[m.raffleId] then local d=copy(m.data or self:Server(m.raffleId) or {id=m.raffleId,title="Pending "..m.action.." ("..m.raffleId:sub(1,8)..")",kind="raffle",scope="unavailable",guildId=empty,chapterId=empty,status="unavailable",prizes={},version=0});d.canManage=self:CanManage(d);d.localOnly=true;result[#result+1]=d;seen[d.id]=true end end
    table.sort(result,function(a,b) return (a.title or "")<(b.title or "") end);return result
end
function R:Server(id) for _,r in ipairs(self:Snapshot().records or {}) do if r.id==id then return r end end end
function R:CanManage(d)
    for _,s in ipairs(self:Snapshot().scopes or {}) do if s.canManage and s.guildId==d.guildId and s.scope==d.scope and s.chapterId==d.chapterId then return true end end
    return false
end
function R:Queue(action,data,entry)
    local snap=self:Snapshot();local d=data or self.draft
    if not d or snap.actorId=="" or snap.actorId==nil then return false,"Sync raffles in Companion while signed in first." end
    if action~="reserve" and action~="release" and not self:CanManage(d) then return false,"Your synced account cannot manage this scope/chapter." end
    if self:Pending(d.id) then return false,"This event already has a pending operation. Sync it or review the failure before changing it again." end
    local id=self.Id();self.lastResult=nil
    self:State().operations[id]={actorId=snap.actorId,gameVersion=OldGodsGameProfile or "retail",mutation={mutationId=id,raffleId=d.id,action=action,expectedVersion=d.version or 0,data=(action=="create" or action=="update") and copy(d) or nil,entry=copy(entry)}}
    self.message="Saved locally, pending server acceptance. /reload, Sync raffles in Companion, then /reload again."
    if self.window then self:RenderList();self.window.status:SetText(self.message) end
    return true
end
function R:New()
    local scope;for _,s in ipairs(self:Snapshot().scopes or {}) do if s.canManage and s.scope=="chapter" then scope=s;break end end
    if not scope then for _,s in ipairs(self:Snapshot().scopes or {}) do if s.canManage then scope=s;break end end end
    if not scope then self.message="No management assignment in the synced account. Members can browse published events.";return false end
    self:Edit({id=self.Id(),guildId=scope.guildId,chapterId=scope.chapterId,scope=scope.scope,kind="raffle",title="",description="",prizes={{name="",quantity=1,order=1,kind="custom",copper=0}},ticketPriceCopper=0,opensAt=GetServerTime(),closesAt=GetServerTime()+7*86400,status="draft",version=0,canManage=true})
    return true
end
function R:Edit(d)
    self.draft=copy(d);self.selected=d.id
    if self.window then self:RenderEditor();self:RenderList() end
end
function R:ReviewLocal()
    if not self.draft then return end
    local op=self:Pending(self.draft.id)
    if not op or not op.result or (op.result.state~="failed" and op.result.state~="conflict") then return end
    local d=op.mutation.data and copy(op.mutation.data) or copy(self:Server(self.draft.id))
    if not d then self.message="Refresh the server snapshot before retrying this operation.";return end
    local server=self:Server(d.id)
    if server and server.status=="deleted" then self.message="This event was deleted. Discard the local change; a deleted ID cannot be restored.";if self.window then self.window.status:SetText(self.message)end;return end
    d.version=server and server.version or 0;d.canManage=self:CanManage(d)
    if server and server.protected then
        d.protected=true
        for _,key in ipairs({"scope","guildId","chapterId","kind","description","prizes","ticketPriceCopper","opensAt","giveawayEveryTickets"})do d[key]=copy(server[key])end
        d.closesAt=math.max(d.closesAt or 0,server.closesAt or 0)
    end
    self:State().operations[op.mutation.mutationId]=nil
    self.message="Review retained changes against server v"..d.version..". Locked rules are restored from the server when entries exist. Saving sends a NEW operation."
    self:Edit(d);if self.window then self.window.status:SetText(self.message) end
end
function R:UseServer()
    if not self.draft then return end
    local id=self.draft.id;for key,op in pairs(self:State().operations) do if op.mutation.raffleId==id then self:State().operations[key]=nil end end
    local server=self:Server(id);if server and server.status~="deleted" then self:Edit(server) else self:New() end
    self.message="Local change discarded. Server records are unchanged.";if self.window then self:RenderList();self.window.status:SetText(self.message) end
end
local function integer(text,minimum,maximum,optional)
    text=trim(text);if text=="" and optional then return nil end
    if not text:match("^%d+$") then return nil,"Use whole numbers." end
    local n=tonumber(text);if not n or n<minimum or n>maximum then return nil,"Number is outside the supported range." end
    return n
end
function R:ReadForm()
    local d=copy(self.draft);local f=self.window.fields
    d.title=trim(f.title:GetText());d.description=f.description:GetText()
    local _,titleLength=d.title:gsub("[^\128-\191]","")
    if d.title=="" or titleLength>120 then return nil,"Enter a title." end
    local gold,e=integer(f.gold:GetText(),0,100000000);if e then return nil,"Gold: "..e end
    local silver,es=integer(f.silver:GetText(),0,99);local copper,ec=integer(f.copper:GetText(),0,99);if es or ec then return nil,"Silver/copper must be 0–99 whole numbers." end
    d.ticketPriceCopper=gold*10000+silver*100+copper
    local total,et=integer(f.totalLimit:GetText(),1,2147483647,true);local member,em=integer(f.memberLimit:GetText(),1,2147483647,true);if et or em then return nil,"Ticket limits must be positive whole numbers or blank for unlimited." end
    d.totalLimit=total;d.memberLimit=member;if total and member and member>total then return nil,"Member limit cannot exceed total limit." end
    d.opensAt=self.Time(f.opensAt:GetText());d.closesAt=self.Time(f.closesAt:GetText());if not d.opensAt or not d.closesAt or d.closesAt<=d.opensAt then return nil,"Enter valid UTC dates; closing must follow opening." end
    local interval,ei=integer(f.giveaway:GetText(),0,2147483647);if ei then return nil,ei end;d.giveawayEveryTickets=interval
    d.prizes={};local seen={}
    for i,p in ipairs(self.draft.prizes or {}) do
        local w=self.window.prizeRows[i];local q,eq=integer(w.quantity:GetText(),1,1000000);local order,eo=integer(w.order:GetText(),1,2147483647)
        local amount,ea=integer(w.copper:GetText(),0,1000000000000);local item,ei=integer(w.itemId:GetText(),1,2147483647,true)
        if eq or eo or ea or ei or trim(w.name:GetText())=="" or seen[order] then return nil,"Every prize needs a name, positive quantity and unique draw order, with valid whole-number details." end
        seen[order]=true
        d.prizes[#d.prizes+1]={name=trim(w.name:GetText()),description=w.description:GetText(),quantity=q,order=order,kind=p.kind or "custom",copper=amount,itemId=item,itemLink=w.itemLink:GetText()}
    end
    if #d.prizes==0 and (d.version or 0)==0 then return nil,"Add at least one prize." end
    return d
end
function R:Save()
    if not self.draft then return end
    local d,message=self:ReadForm();if d then local ok;ok,message=self:Queue(d.version==0 and "create" or "update",d);if ok then self.draft=d end end
    if message then self.message=message;self.window.status:SetText(message) end
end
function R:Confirm(message,fn)
    local w=self.confirm
    if not w then
        w=CreateFrame("Frame","OldGodsRaffleConfirmation",UIParent,"BasicFrameTemplateWithInset");self.confirm=w;w:SetSize(530,180);w:SetPoint("CENTER");w:SetFrameStrata("FULLSCREEN_DIALOG")
        if w.TitleText then w.TitleText:SetText("Confirm raffle action") end
        w.text=w:CreateFontString(nil,"OVERLAY","GameFontHighlight");w.text:SetPoint("TOPLEFT",18,-40);w.text:SetWidth(490);w.text:SetJustifyH("LEFT")
        local yes=OldGodsUI.Button(w,"Confirm",function() local callback=w.callback;w:Hide();if callback then callback() end end,110);yes:SetPoint("BOTTOMLEFT",20,20)
        local no=OldGodsUI.Button(w,"Cancel",function()w:Hide()end,110);no:SetPoint("LEFT",yes,"RIGHT",8,0)
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="OldGodsRaffleConfirmation" end
        if OldGodsTheme then OldGodsTheme.RegisterWindow(w) end
    end
    w.callback=fn;w.text:SetText(message);w:Show()
end
function R:Action(action,entry)
    local d=self.draft;if not d then return end
    local function send() local ok,msg=R:Queue(action,d,entry);if not ok then R.window.status:SetText(msg) end end
    if action=="delete" or action=="cancel" or action=="refund" or action=="deliver" or action=="draw" then self:Confirm("Queue "..action.."? History is preserved. Refund/delivery means gold or prizes have actually been returned/delivered. The server must accept this action.",send) else send() end
end
function R:RenderList()
    local w=self.window;for _,row in ipairs(w.listRows) do row:Hide() end
    local list=self:Records()
    for i,d in ipairs(list) do
        local row=w.listRows[i] or OldGodsUI.Button(w.listContent,"",function()end,255);w.listRows[i]=row
        row:SetSize(255,88);row:GetFontString():SetWidth(245);row:GetFontString():SetWordWrap(true);row:GetFontString():SetMaxLines(4);row:SetPoint("TOPLEFT",0,-(i-1)*92);row:Show()
        row:SetText((d.title~="" and d.title or "Untitled draft").."\n"..d.kind.." · "..d.scope.." · "..d.status.."\n"..self.Money(d.ticketPriceCopper).." · "..tostring(d.allocated or 0).." tickets"..(self:Pending(d.id) and "\nLOCAL CHANGE PENDING" or ""))
        row:SetScript("OnClick",function()R:Edit(d)end)
    end
    w.listContent:SetHeight(math.max(1,#list*92))
    local n=0;for _ in pairs(self:State().operations)do n=n+1 end
    local snap=self:Snapshot();w.connection:SetText(((snap.syncedAt and GetServerTime()-snap.syncedAt>3600) and "STALE cached snapshot: " or "Cached snapshot: ")..self.Date(snap.syncedAt).." UTC | "..n.." pending. /reload → Companion Sync raffles → /reload.")
end
function R:RenderEditor()
    local w=self.window;local d=self.draft;if not d then
        for _,key in ipairs({"scope","kind","lifecycle","addPrize","save","delete","cancel","archive","review"})do w[key]:SetEnabled(false)end
        for _,field in pairs(w.fields)do field:EnableMouse(false)end
        for _,row in ipairs(w.prizeRows)do row:Hide()end
        return
    end
    local f=w.fields;local editable=self:CanManage(d);local material=editable and not d.protected;local pending=self:Pending(d.id)
    local values={title=d.title,description=d.description,gold=math.floor((d.ticketPriceCopper or 0)/10000),silver=math.floor((d.ticketPriceCopper or 0)%10000/100),copper=(d.ticketPriceCopper or 0)%100,totalLimit=d.totalLimit or "",memberLimit=d.memberLimit or "",opensAt=self.Date(d.opensAt),closesAt=self.Date(d.closesAt),giveaway=d.giveawayEveryTickets or 0}
    for key,value in pairs(values)do f[key]:SetText(tostring(value));f[key]:EnableMouse(editable and (material or key=="title" or key=="totalLimit" or key=="memberLimit" or key=="closesAt")) end
    w.scope:SetText(d.scope..": "..(d.chapterName or (d.scope=="guild" and "All Retail and Forever chapters" or "Selected chapter")))
    if w.scope.RefreshLabel then w.scope:RefreshLabel() end;if w.kind.RefreshLabel then w.kind:RefreshLabel() end;if w.lifecycle.RefreshLabel then w.lifecycle:RefreshLabel() end
    w.scope:SetEnabled(material);w.kind:SetEnabled(material);w.lifecycle:SetEnabled(editable)
    for _,row in ipairs(w.prizeRows)do row:Hide() end
    for i,p in ipairs(d.prizes or {})do
        local row=w.prizeRows[i]
        if not row then
            row=CreateFrame("Frame",nil,w.editorContent);row:SetSize(600,232);w.prizeRows[i]=row
            local function field(key,label,x,y,width)
                local title=row:CreateFontString(nil,"OVERLAY","GameFontNormal");title:SetPoint("TOPLEFT",x,y);title:SetText(label)
                local box=CreateFrame("EditBox",nil,row,"InputBoxTemplate");box:SetPoint("TOPLEFT",x,y-20);box:SetSize(width,25);box:SetAutoFocus(false);box:SetMaxLetters(key=="description" and 2000 or 1000);row[key]=box
            end
            field("name","Prize name",0,0,355);field("quantity","Quantity",370,0,90);field("order","Draw order",475,0,90)
            field("description","Prize description",0,-52,565);field("copper","Currency copper",0,-104,180);field("itemId","Item ID",200,-104,120)
            field("itemLink","Item link",0,-156,565)
        end
        local index=i
        row.kind=row.kind or OldGodsUI.Dropdown(row,"Prize kind",{{"custom","Custom"},{"item","Item"},{"currency","Currency"}},function()return R.draft.prizes[index].kind or "custom"end,function(v)R.draft.prizes[index].kind=v end,150);row.kind:SetPoint("TOPLEFT",350,-124);row.kind:SetEnabled(material)
        if row.kind.RefreshLabel then row.kind:RefreshLabel()end
        for _,key in ipairs({"name","description","quantity","order","copper","itemId","itemLink"})do row[key]:SetText(tostring(p[key] or (key=="copper" and 0 or "")));row[key]:EnableMouse(material)end
        row.remove=row.remove or OldGodsUI.Button(row,"Remove prize",function()R:RemovePrize(index)end,130);row.remove:SetPoint("TOPLEFT",0,-202);row.remove:SetEnabled(material)
        row:SetPoint("TOPLEFT",10,-640-(i-1)*240);row:Show()
    end
    local y=-650-#(d.prizes or {})*240
    w.addPrize:ClearAllPoints();w.addPrize:SetPoint("TOPLEFT",w.editorContent,"TOPLEFT",10,y);w.addPrize:SetEnabled(material)
    w.history:ClearAllPoints();w.history:SetPoint("TOPLEFT",w.editorContent,"TOPLEFT",10,y-40)
    local history={"Record "..d.id.." | version "..tostring(d.version or 0),"Created "..self.Date(d.createdAt).." UTC | "..(d.createdBy or "Pending acceptance"),"Updated "..self.Date(d.updatedAt).." UTC | "..(d.updatedBy or "Pending acceptance"),"Entries/payments (your entries unless managing):"}
    for _,e in ipairs((self:Snapshot().entries or {})[d.id] or {})do history[#history+1]=e.id..": "..e.player.." #"..e.firstTicket.."-"..(e.firstTicket+e.ticketCount-1).." | "..e.state.." | "..self.Money(e.amountCopper).." | refund "..e.refundState end
    for _,draw in ipairs((self:Snapshot().draws or {})[d.id] or {})do history[#history+1]="Prize "..draw.prizeOrder..": #"..draw.ticket.." "..draw.player.." | "..draw.delivery end
    w.history:SetText(table.concat(history,"\n"));w.editorContent:SetHeight(-y+math.max(160,(w.history.GetStringHeight and w.history:GetStringHeight() or #history*18)+60))
    w.save:SetEnabled(editable and not pending);w.delete:SetEnabled(editable and d.status=="draft" and not d.protected and not pending)
    w.cancel:SetEnabled(editable and not pending and d.status~="drawn" and d.status~="completed" and d.status~="archived");w.archive:SetEnabled(editable and not pending and (d.status=="drawn" or d.status=="completed" or d.status=="cancelled"))
    w.review:SetEnabled(pending and pending.result and (pending.result.state=="failed" or pending.result.state=="conflict") or false)
    w.status:SetText(pending and (pending.result and (pending.result.state..": "..pending.result.message) or "Local operation pending server acceptance. Sync through Companion.") or self.lastResult or (d.protected and "Entries/payments exist: material rules/prizes are locked. Limits cannot go below allocations. Cancel/archive preserves history." or not editable and "Read only: published event. Management requires an authorized chapter/guild assignment." or "Edit this draft or event, then Save to queue the operation."))
    w.entryTitle:SetText("Entry controls | "..tostring(d.allocated or 0).." allocated | "..tostring(d.confirmed or 0).." confirmed")
end
function R:KeepForm()
    local d,message=self:ReadForm();if not d then self.window.status:SetText(message);return false end;self.draft=d;return true
end
function R:AddPrize()
    -- Capture unfinished text without requiring other blank prize rows to be valid.
    self:CapturePrizeFields();local prizes=self.draft.prizes;if #prizes>=25 then return end
    prizes[#prizes+1]={name="",description="",quantity=1,order=#prizes+1,kind="custom",copper=0};self:RenderPrizesOnly()
end
function R:CapturePrizeFields()
    local d=self.draft;for key in pairs({title=1,description=1})do d[key]=self.window.fields[key]:GetText()end
    for i,p in ipairs(d.prizes)do local row=self.window.prizeRows[i];if row then for _,key in ipairs({"name","description","itemLink"})do p[key]=row[key]:GetText()end;for _,key in ipairs({"quantity","order","copper","itemId"})do p[key]=tonumber(row[key]:GetText())end end end
end
function R:RenderPrizesOnly()
    local f=self.window.fields;local kept={};for key,box in pairs(f)do kept[key]=box:GetText()end
    self:RenderEditor();for key,text in pairs(kept)do f[key]:SetText(text)end
end
function R:RemovePrize(index)self:CapturePrizeFields();table.remove(self.draft.prizes,index);self:RenderPrizesOnly()end
function R:Open()
    if not self.window then
        local w=CreateFrame("Frame","OldGodsRafflesWindow",UIParent,"BasicFrameTemplateWithInset");self.window=w;w.fields={};w.listRows={};w.prizeRows={}
        w:SetSize(980,760);w:SetPoint("CENTER");w:SetFrameStrata("DIALOG");w:SetClampedToScreen(true);w:SetMovable(true);w:EnableMouse(true);w:RegisterForDrag("LeftButton");w:SetScript("OnDragStart",w.StartMoving);w:SetScript("OnDragStop",w.StopMovingOrSizing)
        if w.TitleText then w.TitleText:SetText("Raffles and Lotteries")end;if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="OldGodsRafflesWindow"end
        w.connection=w:CreateFontString(nil,"OVERLAY","GameFontHighlight");w.connection:SetPoint("TOPLEFT",20,-36);w.connection:SetWidth(930);w.connection:SetJustifyH("LEFT")
        local list=CreateFrame("ScrollFrame",nil,w,"UIPanelScrollFrameTemplate");list:SetPoint("TOPLEFT",18,-80);list:SetPoint("BOTTOMRIGHT",w,"BOTTOMLEFT",292,170);w.listContent=CreateFrame("Frame",nil,list);w.listContent:SetSize(255,1);list:SetScrollChild(w.listContent)
        local scroll=CreateFrame("ScrollFrame",nil,w,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",325,-80);scroll:SetPoint("BOTTOMRIGHT",-34,170);w.editorContent=CreateFrame("Frame",nil,scroll);w.editorContent:SetSize(610,1);scroll:SetScrollChild(w.editorContent)
        local function field(key,label,x,y,width,multiline)
            local title=w.editorContent:CreateFontString(nil,"OVERLAY","GameFontNormal");title:SetPoint("TOPLEFT",x,y);title:SetText(label)
            local box=CreateFrame("EditBox",nil,w.editorContent,"InputBoxTemplate");box:SetSize(width,multiline and 70 or 25);box:SetPoint("TOPLEFT",x,y-22);box:SetAutoFocus(false);box:SetMaxLetters(multiline and 8000 or 240)
            if multiline then box:SetMultiLine(true);box:SetFontObject("GameFontHighlight")end;w.fields[key]=box
        end
        field("title","Title",10,0,580);field("description","Rules / description",10,-130,580,true)
        field("gold","Gold (0 = free)",10,-240,180);field("silver","Silver 0–99",210,-240,180);field("copper","Copper 0–99",410,-240,180)
        field("totalLimit","Total limit (blank = unlimited)",10,-300,280);field("memberLimit","Per player incl. alts (blank = unlimited)",310,-300,280)
        field("opensAt","Opens UTC: YYYY-MM-DD HH:MM",10,-360,280);field("closesAt","Closes UTC: YYYY-MM-DD HH:MM",310,-360,280)
        field("giveaway","Lottery giveaway interval (0 disabled)",10,-420,280)
        local function scopeChoices()local choices={};for _,s in ipairs(R:Snapshot().scopes or {})do if s.canManage then choices[#choices+1]={s.scope..":"..(s.scope=="guild" and s.guildId or s.chapterId),s.scope..": "..s.name}end end;return choices end
        w.scope=OldGodsUI.Button(w.editorContent,"Scope / chapter",function()OldGodsUI.Choose(w.scope,scopeChoices(),function(key)if not R.draft or not R:CanManage(R.draft) or R.draft.protected then return end;for _,s in ipairs(R:Snapshot().scopes or {})do if key==s.scope..":"..(s.scope=="guild" and s.guildId or s.chapterId) then R.draft.guildId=s.guildId;R.draft.chapterId=s.chapterId;R.draft.scope=s.scope;w.scope:SetText(s.scope..": "..s.name)end end end)end,580);w.scope:SetPoint("TOPLEFT",10,-62)
        w.kind=OldGodsUI.Dropdown(w.editorContent,"Type",{{"raffle","Raffle"},{"lottery","Lottery"}},function()return R.draft and R.draft.kind or "raffle"end,function(v)if R.draft and R:CanManage(R.draft) and not R.draft.protected then R.draft.kind=v end end,200);w.kind:SetPoint("TOPLEFT",10,-100)
        w.lifecycle=OldGodsUI.Dropdown(w.editorContent,"Status",{{"draft","Draft"},{"active","Active"},{"closed","Closed"},{"drawn","Drawn"},{"completed","Completed"},{"cancelled","Cancelled"},{"archived","Archived"}},function()return R.draft and R.draft.status or "draft"end,function(v)if R.draft and R:CanManage(R.draft) then R.draft.status=v end end,240);w.lifecycle:SetPoint("TOPLEFT",320,-442)
        w.addPrize=OldGodsUI.Button(w.editorContent,"Add prize",function()R:AddPrize()end,150)
        w.history=w.editorContent:CreateFontString(nil,"OVERLAY","GameFontHighlight");w.history:SetWidth(580);w.history:SetJustifyH("LEFT")
        local new=OldGodsUI.Button(w,"New raffle / lottery",function()if not R:New()then w.status:SetText(R.message)end end,180);new:SetPoint("BOTTOMLEFT",20,130)
        w.save=OldGodsUI.Button(w,"Save / queue",function()R:Save()end,130);w.save:SetPoint("LEFT",new,"RIGHT",8,0)
        w.delete=OldGodsUI.Button(w,"Delete draft",function()R:Action("delete")end,130);w.delete:SetPoint("LEFT",w.save,"RIGHT",8,0)
        w.cancel=OldGodsUI.Button(w,"Cancel event",function()R:Action("cancel")end,130);w.cancel:SetPoint("LEFT",w.delete,"RIGHT",8,0)
        w.archive=OldGodsUI.Button(w,"Archive",function()R:Action("archive")end,100);w.archive:SetPoint("LEFT",w.cancel,"RIGHT",8,0)
        w.review=OldGodsUI.Button(w,"Review failed change",function()R:ReviewLocal()end,180);w.review:SetPoint("BOTTOMLEFT",20,92)
        local server=OldGodsUI.Button(w,"Discard local / use server",function()R:Confirm("Discard your unsynced change and use the downloaded server version?",function()R:UseServer()end)end,230);server:SetPoint("LEFT",w.review,"RIGHT",8,0)
        w.entryTitle=w.editorContent:CreateFontString(nil,"OVERLAY","GameFontNormal");w.entryTitle:SetPoint("TOPLEFT",w.editorContent,"TOPLEFT",10,-510)
        local function small(key,x,width,label)
            local box=CreateFrame("EditBox",nil,w.editorContent,"InputBoxTemplate");box:SetSize(width,25);box:SetPoint("TOPLEFT",x,-540);box:SetAutoFocus(false);box:SetMaxLetters(100);OldGodsUI.Help(box,label);w[key]=box;return box
        end
        local n,realm=UnitFullName("player");small("player",10,225,"Character-Realm"):SetText((n or "").."-"..(realm or GetRealmName()))
        small("tickets",250,60,"Tickets"):SetText("1");small("amount",325,120,"Actual copper payment"):SetText("0");small("entryId",460,120,"Entry ID or prize order"):SetText("0")
        w.entryScope=OldGodsUI.Button(w.editorContent,"Entry chapter",function()local choices={};for _,s in ipairs(R:Snapshot().scopes or {})do if s.scope=="chapter" then choices[#choices+1]={s.chapterId,s.name}end end;OldGodsUI.Choose(w.entryScope,choices,function(id)w.entryChapter=id;for _,s in ipairs(R:Snapshot().scopes)do if s.chapterId==id then w.entryScope:SetText(s.name)end end end)end,220);w.entryScope:SetPoint("TOPLEFT",10,-580)
        local actions;actions=OldGodsUI.Button(w.editorContent,"Entry / draw actions",function()
            local d=R.draft;if not d then return end;local choices={{"reserve","Reserve my tickets"},{"release","Release my reservation"}};if R:CanManage(d)then for _,a in ipairs({{"allocate","Record confirmed tickets"},{"confirm","Confirm actual payment"},{"refund","Mark actual refund"},{"draw","Draw prize order"},{"deliver","Mark prize delivered"}})do choices[#choices+1]=a end end
            OldGodsUI.Choose(actions,choices,function(action)
                local chapter=w.entryChapter;if not chapter then local key=OldGodsChapterSettings and OldGodsChapterSettings.Key();for _,s in ipairs(R:Snapshot().scopes or {})do if s.scope=="chapter" and (s.guildClubKey==key or d.chapterId==s.chapterId)then chapter=s.chapterId;break end end end
                local tickets=tonumber(w.tickets:GetText());local amount=tonumber(w.amount:GetText());local id=tonumber(w.entryId:GetText());if not tickets or tickets%1~=0 or not amount or amount%1~=0 or not id or id%1~=0 then w.status:SetText("Tickets, copper, and entry/prize IDs must be whole numbers.");return end
                R:Action(action,{chapterId=chapter or empty,player=w.player:GetText(),tickets=tickets,amountCopper=amount,purchaseId=id,prizeOrder=id})
            end)
        end,310);actions:SetPoint("TOPLEFT",250,-580)
        w.status=w:CreateFontString(nil,"OVERLAY","GameFontHighlight");w.status:SetPoint("BOTTOMLEFT",20,18);w.status:SetWidth(930);w.status:SetJustifyH("LEFT")
        if OldGodsTheme then OldGodsTheme.RegisterWindow(w)end
    end
    self:RenderList();local list=self:Records();if self.draft then self:RenderEditor()elseif list[1]then self:Edit(list[1])else self:New()end
    if not self.draft then self:RenderEditor();for _,key in ipairs({"save","delete","cancel","archive","review"})do self.window[key]:SetEnabled(false)end;self.window.status:SetText("No published raffles in this snapshot. Sign in and Sync raffles in Companion. Management choices require chapter assignments.")end
    self.window:Show();if OldGodsTheme then OldGodsTheme.ApplyWindow(self.window)end
end
SLASH_OLDGODSRAFFLES1="/ograffle"
SlashCmdList.OLDGODSRAFFLES=function()R:Open()end
