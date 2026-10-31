-- SVG remains the editable source; RGBA TGA gives consistent in-game scaling.
OldGodsAssets = {buttons=setmetatable({}, {__mode="k"})}
local A=OldGodsAssets
local root="Interface\\AddOns\\OldGodsGuildAudit\\Assets\\Icons\\"
A.names={"search","clear","promote","demote","kick","invite","ban","deselect","disarm","whisper","events","previous","next","refresh"}
function A.Attach(button,name)
    local icon=button:CreateTexture(nil,"ARTWORK")
    icon:SetTexture(root..name..".tga")
    icon:SetSize(32,32); icon:SetPoint("CENTER"); icon.oldGodsAsset=true
    button.oldGodsIcon=icon; button.oldGodsIconName=name
    button:SetSize(36,36); button:SetText("")
    function button:RefreshIcon(colors)
        self.oldGodsIconColors=colors or self.oldGodsIconColors
        local palette=self.oldGodsIconColors
        if not palette then return end
        local color=(self.oldGodsIconName=="ban" and palette.danger) or palette.text
        local enabled=self:IsEnabled()
        local alpha=enabled and 1 or 0.35
        self.oldGodsIcon:SetVertexColor(color[1],color[2],color[3],1)
        self.oldGodsIcon:SetAlpha(alpha)
        local base=palette.button
        local hover=enabled and self.oldGodsIconHover and 0.15 or 0
        self:SetBackdropColor(base[1]+(palette.text[1]-base[1])*hover,base[2]+(palette.text[2]-base[2])*hover,base[3]+(palette.text[3]-base[3])*hover,1)
        self:SetBackdropBorderColor(unpack(self.oldGodsIconHover and enabled and palette.text or palette.border))
    end
    button:HookScript("OnEnter",function(self) self.oldGodsIconHover=true; self:RefreshIcon() end)
    button:HookScript("OnLeave",function(self) self.oldGodsIconHover=false; self:RefreshIcon() end)
    button:HookScript("OnEnable",function(self) self:RefreshIcon() end)
    button:HookScript("OnDisable",function(self) self:RefreshIcon() end)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    A.buttons[button]=true
    if OldGodsTheme and OldGodsTheme.Colors then button:RefreshIcon(OldGodsTheme.Colors()) end
    return icon
end
function A.Button(parent,factory,label,name,callback)
    local button=factory(parent,label,callback,36)
    A.Attach(button,name); OldGodsUI.Help(button,label)
    return button
end
