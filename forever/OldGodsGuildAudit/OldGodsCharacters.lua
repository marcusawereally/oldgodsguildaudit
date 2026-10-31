-- Player-owned main/alt choices. Guild notes and officer actions are never ownership evidence.
OldGodsCharacters = {}
local C = OldGodsCharacters
local appliedImports=setmetatable({},{__mode="k"})
local characterCache
local regions = {[1]="us",[2]="kr",[3]="eu",[4]="tw"}
local function trim(v) return tostring(v or ""):match("^%s*(.-)%s*$") end
local function copy(v)
    if type(v) ~= "table" then return v end
    local result={}; for k,x in pairs(v) do result[k]=copy(x) end; return result
end
-- Simple Unicode lowercase pairs keep accented character/realm keys aligned with the server.
local upperLetters="ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞĀĂĄĆĈĊČĎĐĒĔĖĘĚĜĞĠĢĤĦĨĪĬĮĲĴĶĹĻĽĿŁŃŅŇŊŌŎŐŒ" ..
    "ŔŖŘŚŜŞŠŢŤŦŨŪŬŮŰŲŴŶŸŹŻŽƁƂƄƆƇƉƊƋƎƏƐƑƓƔƖƗƘƜƝƟƠƢƤƦƧƩƬƮƯƱƲƳƵƷƸƼǄǅǇǈǊǋǍǏǑǓǕǗ" ..
    "ǙǛǞǠǢǤǦǨǪǬǮǱǲǴǶǷǸǺǼǾȀȂȄȆȈȊȌȎȐȒȔȖȘȚȜȞȠȢȤȦȨȪȬȮȰȲȺȻȽȾɁɃɄɅɆɈɊɌɎͰͲͶͿΆΈΉΊΌΎΏ" ..
    "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩΪΫϏϘϚϜϞϠϢϤϦϨϪϬϮϴϷϹϺϽϾϿЀЁЂЃЄЅІЇЈЉЊЋЌЍЎЏАБВГДЕЖЗ" ..
    "ИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯѠѢѤѦѨѪѬѮѰѲѴѶѸѺѼѾҀҊҌҎҐҒҔҖҘҚҜҞҠҢҤҦҨҪҬҮҰҲҴҶҸҺҼҾӀӁ" ..
    "ӃӅӇӉӋӍӐӒӔӖӘӚӜӞӠӢӤӦӨӪӬӮӰӲӴӶӸӺӼӾԀԂԄԆԈԊԌԎԐԒԔԖԘԚԜԞԠԢԤԦԨԪԬԮԱԲԳԴԵԶԷԸԹԺԻԼԽԾԿՀ" ..
    "ՁՂՃՄՅՆՇՈՉՊՋՌՍՎՏՐՑՒՓՔՕՖႠႡႢႣႤႥႦႧႨႩႪႫႬႭႮႯႰႱႲႳႴႵႶႷႸႹႺႻႼႽႾႿჀჁჂჃჄჅჇჍᎠᎡᎢᎣᎤᎥᎦᎧ" ..
    "ᎨᎩᎪᎫᎬᎭᎮᎯᎰᎱᎲᎳᎴᎵᎶᎷᎸᎹᎺᎻᎼᎽᎾᎿᏀᏁᏂᏃᏄᏅᏆᏇᏈᏉᏊᏋᏌᏍᏎᏏᏐᏑᏒᏓᏔᏕᏖᏗᏘᏙᏚᏛᏜᏝᏞᏟᏠᏡᏢᏣᏤᏥᏦᏧᏨᏩᏪᏫᏬᏭ" ..
    "ᏮᏯᏰᏱᏲᏳᏴᏵᲐᲑᲒᲓᲔᲕᲖᲗᲘᲙᲚᲛᲜᲝᲞᲟᲠᲡᲢᲣᲤᲥᲦᲧᲨᲩᲪᲫᲬᲭᲮᲯᲰᲱᲲᲳᲴᲵᲶᲷᲸᲹᲺᲽᲾᲿḀḂḄḆḈḊḌḎḐḒḔḖḘḚḜḞ" ..
    "ḠḢḤḦḨḪḬḮḰḲḴḶḸḺḼḾṀṂṄṆṈṊṌṎṐṒṔṖṘṚṜṞṠṢṤṦṨṪṬṮṰṲṴṶṸṺṼṾẀẂẄẆẈẊẌẎẐẒẔẞẠẢẤẦẨẪẬẮẰẲ" ..
    "ẴẶẸẺẼẾỀỂỄỆỈỊỌỎỐỒỔỖỘỚỜỞỠỢỤỦỨỪỬỮỰỲỴỶỸỺỼỾἈἉἊἋἌἍἎἏἘἙἚἛἜἝἨἩἪἫἬἭἮἯἸἹἺἻἼἽἾἿὈὉ" ..
    "ὊὋὌὍὙὛὝὟὨὩὪὫὬὭὮὯᾈᾉᾊᾋᾌᾍᾎᾏᾘᾙᾚᾛᾜᾝᾞᾟᾨᾩᾪᾫᾬᾭᾮᾯᾸᾹᾺΆᾼῈΈῊΉῌῘῙῚΊῨῩῪΎῬῸΌῺΏῼΩKÅℲⅠⅡ" ..
    "ⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫⅬⅭⅮⅯↃⒶⒷⒸⒹⒺⒻⒼⒽⒾⒿⓀⓁⓂⓃⓄⓅⓆⓇⓈⓉⓊⓋⓌⓍⓎⓏⰀⰁⰂⰃⰄⰅⰆⰇⰈⰉⰊⰋⰌⰍⰎⰏⰐⰑⰒⰓⰔⰕⰖⰗⰘⰙⰚⰛⰜ" ..
    "ⰝⰞⰟⰠⰡⰢⰣⰤⰥⰦⰧⰨⰩⰪⰫⰬⰭⰮⰯⱠⱢⱣⱤⱧⱩⱫⱭⱮⱯⱰⱲⱵⱾⱿⲀⲂⲄⲆⲈⲊⲌⲎⲐⲒⲔⲖⲘⲚⲜⲞⲠⲢⲤⲦⲨⲪⲬⲮⲰⲲⲴⲶⲸⲺⲼⲾⳀⳂⳄⳆ" ..
    "ⳈⳊⳌⳎⳐⳒⳔⳖⳘⳚⳜⳞⳠⳢⳫⳭⳲꙀꙂꙄꙆꙈꙊꙌꙎꙐꙒꙔꙖꙘꙚꙜꙞꙠꙢꙤꙦꙨꙪꙬꚀꚂꚄꚆꚈꚊꚌꚎꚐꚒꚔꚖꚘꚚꜢꜤꜦꜨꜪꜬꜮꜲꜴꜶꜸꜺꜼꜾꝀꝂ" ..
    "ꝄꝆꝈꝊꝌꝎꝐꝒꝔꝖꝘꝚꝜꝞꝠꝢꝤꝦꝨꝪꝬꝮꝹꝻꝽꝾꞀꞂꞄꞆꞋꞍꞐꞒꞖꞘꞚꞜꞞꞠꞢꞤꞦꞨꞪꞫꞬꞭꞮꞰꞱꞲꞳꞴꞶꞸꞺꞼꞾꟀꟂꟄꟅꟆꟇꟉꟐꟖꟘꟵ" ..
    "ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ"
local lowerLetters="àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþāăąćĉċčďđēĕėęěĝğġģĥħĩīĭįĳĵķĺļľŀłńņňŋōŏőœ" ..
    "ŕŗřśŝşšţťŧũūŭůűųŵŷÿźżžɓƃƅɔƈɖɗƌǝəɛƒɠɣɩɨƙɯɲɵơƣƥʀƨʃƭʈưʊʋƴƶʒƹƽǆǆǉǉǌǌǎǐǒǔǖǘ" ..
    "ǚǜǟǡǣǥǧǩǫǭǯǳǳǵƕƿǹǻǽǿȁȃȅȇȉȋȍȏȑȓȕȗșțȝȟƞȣȥȧȩȫȭȯȱȳⱥȼƚⱦɂƀʉʌɇɉɋɍɏͱͳͷϳάέήίόύώ" ..
    "αβγδεζηθικλμνξοπρστυφχψωϊϋϗϙϛϝϟϡϣϥϧϩϫϭϯθϸϲϻͻͼͽѐёђѓєѕіїјљњћќѝўџабвгдежз" ..
    "ийклмнопрстуфхцчшщъыьэюяѡѣѥѧѩѫѭѯѱѳѵѷѹѻѽѿҁҋҍҏґғҕҗҙқҝҟҡңҥҧҩҫҭүұҳҵҷҹһҽҿӏӂ" ..
    "ӄӆӈӊӌӎӑӓӕӗәӛӝӟӡӣӥӧөӫӭӯӱӳӵӷӹӻӽӿԁԃԅԇԉԋԍԏԑԓԕԗԙԛԝԟԡԣԥԧԩԫԭԯաբգդեզէըթժիլխծկհ" ..
    "ձղճմյնշոչպջռսվտրցւփքօֆⴀⴁⴂⴃⴄⴅⴆⴇⴈⴉⴊⴋⴌⴍⴎⴏⴐⴑⴒⴓⴔⴕⴖⴗⴘⴙⴚⴛⴜⴝⴞⴟⴠⴡⴢⴣⴤⴥⴧⴭꭰꭱꭲꭳꭴꭵꭶꭷ" ..
    "ꭸꭹꭺꭻꭼꭽꭾꭿꮀꮁꮂꮃꮄꮅꮆꮇꮈꮉꮊꮋꮌꮍꮎꮏꮐꮑꮒꮓꮔꮕꮖꮗꮘꮙꮚꮛꮜꮝꮞꮟꮠꮡꮢꮣꮤꮥꮦꮧꮨꮩꮪꮫꮬꮭꮮꮯꮰꮱꮲꮳꮴꮵꮶꮷꮸꮹꮺꮻꮼꮽ" ..
    "ꮾꮿᏸᏹᏺᏻᏼᏽაბგდევზთიკლმნოპჟრსტუფქღყშჩცძწჭხჯჰჱჲჳჴჵჶჷჸჹჺჽჾჿḁḃḅḇḉḋḍḏḑḓḕḗḙḛḝḟ" ..
    "ḡḣḥḧḩḫḭḯḱḳḵḷḹḻḽḿṁṃṅṇṉṋṍṏṑṓṕṗṙṛṝṟṡṣṥṧṩṫṭṯṱṳṵṷṹṻṽṿẁẃẅẇẉẋẍẏẑẓẕßạảấầẩẫậắằẳ" ..
    "ẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹỻỽỿἀἁἂἃἄἅἆἇἐἑἒἓἔἕἠἡἢἣἤἥἦἧἰἱἲἳἴἵἶἷὀὁ" ..
    "ὂὃὄὅὑὓὕὗὠὡὢὣὤὥὦὧᾀᾁᾂᾃᾄᾅᾆᾇᾐᾑᾒᾓᾔᾕᾖᾗᾠᾡᾢᾣᾤᾥᾦᾧᾰᾱὰάᾳὲέὴήῃῐῑὶίῠῡὺύῥὸόὼώῳωkåⅎⅰⅱ" ..
    "ⅲⅳⅴⅵⅶⅷⅸⅹⅺⅻⅼⅽⅾⅿↄⓐⓑⓒⓓⓔⓕⓖⓗⓘⓙⓚⓛⓜⓝⓞⓟⓠⓡⓢⓣⓤⓥⓦⓧⓨⓩⰰⰱⰲⰳⰴⰵⰶⰷⰸⰹⰺⰻⰼⰽⰾⰿⱀⱁⱂⱃⱄⱅⱆⱇⱈⱉⱊⱋⱌ" ..
    "ⱍⱎⱏⱐⱑⱒⱓⱔⱕⱖⱗⱘⱙⱚⱛⱜⱝⱞⱟⱡɫᵽɽⱨⱪⱬɑɱɐɒⱳⱶȿɀⲁⲃⲅⲇⲉⲋⲍⲏⲑⲓⲕⲗⲙⲛⲝⲟⲡⲣⲥⲧⲩⲫⲭⲯⲱⲳⲵⲷⲹⲻⲽⲿⳁⳃⳅⳇ" ..
    "ⳉⳋⳍⳏⳑⳓⳕⳗⳙⳛⳝⳟⳡⳣⳬⳮⳳꙁꙃꙅꙇꙉꙋꙍꙏꙑꙓꙕꙗꙙꙛꙝꙟꙡꙣꙥꙧꙩꙫꙭꚁꚃꚅꚇꚉꚋꚍꚏꚑꚓꚕꚗꚙꚛꜣꜥꜧꜩꜫꜭꜯꜳꜵꜷꜹꜻꜽꜿꝁꝃ" ..
    "ꝅꝇꝉꝋꝍꝏꝑꝓꝕꝗꝙꝛꝝꝟꝡꝣꝥꝧꝩꝫꝭꝯꝺꝼᵹꝿꞁꞃꞅꞇꞌɥꞑꞓꞗꞙꞛꞝꞟꞡꞣꞥꞧꞩɦɜɡɬɪʞʇʝꭓꞵꞷꞹꞻꞽꞿꟁꟃꞔʂᶎꟈꟊꟑꟗꟙꟶ" ..
    "ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ"
local utf8Letter="[\194-\244][\128-\191]*"
local unicodeLower={}
local nextLower=lowerLetters:gmatch(utf8Letter)
for letter in upperLetters:gmatch(utf8Letter) do unicodeLower[letter]=nextLower() end
local function lower(v) return v:lower():gsub(utf8Letter,unicodeLower) end
function C.Key(name,realm)
    return lower(trim(name)) .. "-" .. lower(trim(realm)):gsub("[%s'%-]",""):gsub("’","")
end
function C.Scope()
    return (OldGodsGameProfile or "retail") .. ":" .. (regions[GetCurrentRegion()] or "us")
end
function C:Imported()
    local p=OldGodsCharacterImports and OldGodsCharacterImports.profiles and OldGodsCharacterImports.profiles[self.Scope()]
    if p and p.gameVersion == (OldGodsGameProfile or "retail") and p.region == regions[GetCurrentRegion()] then return p end
end
function C:State()
    OldGodsGuildAuditDB=OldGodsGuildAuditDB or {}
    OldGodsGuildAuditDB.playerCharacters=OldGodsGuildAuditDB.playerCharacters or {}
    local scope=self.Scope()
    local row=OldGodsGuildAuditDB.playerCharacters[scope]
    if not row then
        row={profileId="",gameVersion=OldGodsGameProfile or "retail",region=regions[GetCurrentRegion()] or "us",baseRevision=0,mainKey="",manualCharacters={},characters={},mutationId=""}
        OldGodsGuildAuditDB.playerCharacters[scope]=row
    end
    local imported=self:Imported()
    if imported and ((not row.pending and appliedImports[row]~=imported) or (row.pending and row.mutationId==imported.mutationId and (row.profileId=="" or row.profileId==imported.profileId))) then
        row.profileId=imported.profileId; row.baseRevision=imported.revision; row.mainKey=imported.mainKey
        row.characters=copy(imported.characters or {}); row.manualCharacters={}
        for _,character in ipairs(row.characters) do if character.source=="manual" then row.manualCharacters[#row.manualCharacters+1]=copy(character) end end
        row.pending=false; row.mutationId=imported.mutationId or ""
        appliedImports[row]=imported; characterCache=nil
    end
    return row
end
function C:Characters()
    local row=self:State(); local result,seen={},{}
    if characterCache and characterCache.row==row and characterCache.mutationId==row.mutationId then return characterCache.list,characterCache.lookup end
    local lookup={}
    -- Import only Blizzard-owned entries here; manual removals must not reappear from the old import.
    for _,list in ipairs({row.characters or {},row.manualCharacters or {}}) do
        for _,character in ipairs(list) do
            local key=self.Key(character.name,character.realm)
            if not seen[key] and (list==row.manualCharacters or character.source=="blizzard") then
                local c=copy(character); c.key=key; result[#result+1]=c; seen[key]=true; lookup[key]=c
            end
        end
    end
    table.sort(result,function(a,b) return a.key<b.key end)
    characterCache={row=row,mutationId=row.mutationId,list=result,lookup=lookup}
    return result,lookup
end
function C:Changed(row)
    row.serial=(row.serial or 0)+1
    row.mutationId=(UnitGUID and UnitGUID("player") or "player") .. ":" .. tostring(GetServerTime()) .. ":" .. row.serial
    row.pending=true
    if self.window then self:Render() end
end
function C:Add(name,realm)
    name,realm=trim(name),trim(realm)
    if name=="" or #name>96 or name:find("[%s%d%p%c]") or realm=="" or #realm>160 or realm:find("[|%c]") then return false,"Enter a character name and realm in separate fields." end
    local row=self:State()
    if #row.manualCharacters>=100 then return false,"Up to 100 manual characters are supported." end
    local key=self.Key(name,realm)
    for _,c in ipairs(self:Characters()) do if c.key==key then return false,"That character is already linked." end end
    -- Mark pending before mutation so State() cannot reapply a previous download.
    row.pending=true; row.manualCharacters[#row.manualCharacters+1]={name=name,realm=realm,source="manual"}
    self:Changed(row); return true
end
function C:SetMain(key)
    if key~="" then
        local found=false; for _,c in ipairs(self:Characters()) do if c.key==key then found=true end end
        if not found then return false end
    end
    local row=self:State(); row.pending=true; row.mainKey=key; self:Changed(row); return true
end
function C:Remove(key)
    local row=self:State(); row.pending=true
    for i=#row.manualCharacters,1,-1 do if self.Key(row.manualCharacters[i].name,row.manualCharacters[i].realm)==key then table.remove(row.manualCharacters,i) end end
    if row.mainKey==key then row.mainKey="" end
    self:Changed(row)
end
function C:UseSynced()
    if not self:Imported() then return end
    local row=self:State(); row.pending=false; appliedImports[row]=nil; self:State(); self.message="Synced choices restored; local edits discarded."
    if self.window then self:Render() end
end
function C:Link(name)
    local character,realm=trim(name):match("^([^%-]+)%-(.+)$")
    if not character then character=trim(name); realm=GetNormalizedRealmName() or GetRealmName() end
    local key=self.Key(character,realm)
    local row=self:State(); local _,lookup=self:Characters(); local main=lookup[row.mainKey]; local own=lookup[key]
    if own then
        if main then return {main=main.name.."-"..main.realm,source=own.source,alts={},role=key==row.mainKey and "Main" or "Alt"} end
        return nil
    end
    local imported=self:Imported()
    if row.pending and imported then
        for _,c in ipairs(imported.characters or {}) do if self.Key(c.name,c.realm)==key then return nil end end
    end
    local guildKey=OldGodsChapterSettings and OldGodsChapterSettings.Key()
    local link=guildKey and OldGodsCharacterImports and OldGodsCharacterImports.guilds and OldGodsCharacterImports.guilds[guildKey] and OldGodsCharacterImports.guilds[guildKey][key]
    if link then
        link=copy(link); local n,r=link.main:match("^([^%-]+)%-(.+)$")
        link.role=n and self.Key(n,r)==key and "Main" or "Alt"
        return link
    end
end
function C:Render()
    local w=self.window; local row=self:State()
    for _,item in ipairs(w.rows) do item:Hide() end
    local list=self:Characters()
    for i,c in ipairs(list) do
        local item=w.rows[i]
        if not item then
            item=CreateFrame("Frame",nil,w.content); item:SetSize(680,34)
            item.text=item:CreateFontString(nil,"OVERLAY","GameFontHighlight"); item.text:SetPoint("LEFT",0,0); item.text:SetWidth(450); item.text:SetJustifyH("LEFT")
            item.main=OldGodsUI.Button(item,"Set main",function() end,94); item.main:SetPoint("LEFT",450,0)
            item.remove=OldGodsUI.Button(item,"Remove",function() end,94); item.remove:SetPoint("LEFT",550,0)
            w.rows[i]=item
        end
        local key=c.key
        item:SetPoint("TOPLEFT",0,-(i-1)*36); item:Show()
        item.text:SetText((key==row.mainKey and "Main: " or row.mainKey~="" and "Alt: " or "")..c.name.."-"..c.realm.." ("..(c.source=="blizzard" and "Blizzard" or "Manual")..")")
        item.main:SetEnabled(key~=row.mainKey); item.main:SetScript("OnClick",function() C:SetMain(key) end)
        item.remove:SetShown(c.source~="blizzard"); item.remove:SetScript("OnClick",function() C:Remove(key) end)
    end
    w.content:SetHeight(math.max(1,#list*36))
    local imported=self:Imported()
    local conflict=row.pending and imported and ((row.profileId~="" and row.profileId~=imported.profileId) or (row.baseRevision~=imported.revision and row.mutationId~=imported.mutationId))
    w.status:SetText(self.message or (conflict and "Sync conflict: your edits are kept. Use synced choices to discard them, or review My characters on the website." or row.pending and "Saved locally. /reload, click Sync my characters in Companion, then /reload again." or "Synced choices. Choose your main or add a manual character below."))
    w.restore:SetEnabled(imported~=nil)
end
function C:Open()
    if not self.window then
        local w=CreateFrame("Frame","OldGodsCharactersWindow",UIParent,"BasicFrameTemplateWithInset"); self.window=w; w.rows={}
        w:SetSize(740,570); w:SetPoint("CENTER"); w:SetFrameStrata("DIALOG"); w:SetClampedToScreen(true)
        w:SetMovable(true); w:EnableMouse(true); w:RegisterForDrag("LeftButton"); w:SetScript("OnDragStart",w.StartMoving); w:SetScript("OnDragStop",w.StopMovingOrSizing)
        if w.TitleText then w.TitleText:SetText("My Characters - Main / Alts") end
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="OldGodsCharactersWindow" end
        local help=w:CreateFontString(nil,"OVERLAY","GameFontHighlight"); help:SetPoint("TOPLEFT",18,-38); help:SetWidth(700); help:SetJustifyH("LEFT")
        help:SetText("You choose your main. Blizzard supplies owned characters after Companion sync.\nManual links are player-entered. Your selected main and matching guild alts are shared.\nRetail and Forever stay separate; guild notes and permissions are unchanged.")
        w.scroll=CreateFrame("ScrollFrame",nil,w,"UIPanelScrollFrameTemplate"); w.scroll:SetPoint("TOPLEFT",20,-100); w.scroll:SetPoint("BOTTOMRIGHT",-36,170)
        w.content=CreateFrame("Frame",nil,w.scroll); w.content:SetSize(680,1); w.scroll:SetScrollChild(w.content)
        local function input(label,x,width)
            local title=w:CreateFontString(nil,"OVERLAY","GameFontNormal"); title:SetPoint("BOTTOMLEFT",x,145); title:SetText(label)
            local box=CreateFrame("EditBox",nil,w,"InputBoxTemplate"); box:SetSize(width,26); box:SetPoint("BOTTOMLEFT",x,112); box:SetAutoFocus(false); box:SetMaxLetters(80); return box
        end
        w.name=input("Character name",24,190); w.realm=input("Realm",232,220); w.realm:SetText(GetRealmName() or "")
        local add=OldGodsUI.Button(w,"Add character",function() local ok,message=C:Add(w.name:GetText(),w.realm:GetText()); C.message=ok and "Character linked locally. Choose a main, then sync in Companion." or message; if ok then w.name:SetText("") end; C:Render() end,132); add:SetPoint("BOTTOMLEFT",470,112)
        local current=OldGodsUI.Button(w,"Add this character",function() local n,r=UnitFullName("player"); local ok,message=C:Add(n,r or GetRealmName()); C.message=ok and "Current character linked locally." or message; C:Render() end,160); current:SetPoint("BOTTOMLEFT",24,74)
        local clear=OldGodsUI.Button(w,"Stop sharing",function() C.message=nil; C:SetMain("") end,125); clear:SetPoint("LEFT",current,"RIGHT",8,0)
        w.restore=OldGodsUI.Button(w,"Use synced choices",function() C:UseSynced() end,165); w.restore:SetPoint("LEFT",clear,"RIGHT",8,0)
        OldGodsUI.Help(w.restore,"Use synced choices","Discard unsynced edits and restore the latest choices downloaded by Companion.")
        w.status=w:CreateFontString(nil,"OVERLAY","GameFontHighlight"); w.status:SetPoint("BOTTOMLEFT",20,14); w.status:SetWidth(700); w.status:SetJustifyH("LEFT")
        if OldGodsTheme and OldGodsTheme.RegisterWindow then OldGodsTheme.RegisterWindow(w) end
    end
    self.message=nil; self:Render(); self.window:Show()
    if OldGodsTheme and OldGodsTheme.ApplyWindow then OldGodsTheme.ApplyWindow(self.window) end
end
SLASH_OLDGODSCHARACTERS1="/ogchars"
SlashCmdList.OLDGODSCHARACTERS=function() C:Open() end
