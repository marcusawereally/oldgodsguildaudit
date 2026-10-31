-- Plain-English help lives here. Edit these strings without changing feature code.
OldGodsUI = { help = {
    ["π"] = "Ctrl+Shift+click to show or hide debug options.",
    ["Scan Current Zone"] = "Find unguilded players in your current zone using this character's /who results. Quiet zones, bans and the seven-day invitation history still apply.",
    ["Scan All Zones"] = "Start a series of /who searches. Continue Search becomes available after each countdown; click it to send the next search.",
    ["Continue Search"] = "Send the next /who search after the countdown. Each search needs a click.",
    ["Invite Next"] = "Invite one eligible player. One click sends one invitation. Banned players, quiet zones and players invited within the last seven days are excluded.",
    ["Invite"] = "Run the prepared guild-invite macro batch with this click. The next batch is built afterwards. Server delivery and acceptance are not confirmed; check WoW's errors. Bans, quiet zones, history and review checks still apply.",
    ["Prepare Invite"] = "Build a macro with as many complete guild-invite commands as fit within 255 bytes. This click does not invite anyone. The button changes to Invite for the next click.",
    ["Recruiting search"] = "Search all zones. While searches remain, click Continue Search after each cooldown. Hover the green or red circle for live progress and next-invite details.",
    ["Clear List"] = "Clear the candidates currently displayed. Your invitation history and ban list are kept.",
    ["Reset Saved Realms"] = "Developer tool: forget cached realm information so it can be read again from WoW. This does not change your guild or character's realm.",
    ["Copy Last Scan Log"] = "Developer tool: copy the latest recruiting search details for troubleshooting.",
    ["Copy Calendar JSON"] = "Developer tool: copy calendar data as structured text for troubleshooting.",
    ["Faction"] = "Choose which known factions to display. Unknown means WoW did not provide enough information to identify the faction.",
    ["Show candidates"] = "All candidates includes players who cannot currently be invited and their reason. Eligible only shows players who pass all invitation checks.",
    ["Applicant alerts"] = "Sound plays a notification, Popup shows an invitation window, and Both does both. Alerts wait until you leave quiet content such as a dungeon or raid. Manage quiet zones in Chapter > Quiet Zones.",
    ["Queue Inactive Kicks"] = "Prepare the guild-wide 28-day inactive list for review and removal. This does not remove anyone until you use the configured cleanup key. Ranks 0 and 1 are exempt.",
    ["Arm Announcement"] = "Preview the chapter announcement by hovering. Click to prepare it, then press Ctrl+Shift+A to send it to guild chat.",
    ["Cleanup key"] = "Choose the temporary key used while a removal queue is armed. It is released when you disarm or finish. Existing bindings work again afterwards.",
    ["Filter inactive"] = "Enable or disable the saved days-offline filter. Its value and enabled state survive /reload. Ranks 0 and 1 are exempt. Review and select players before arming removal. This filter does not affect the 28-day audit.",
    ["Clear search"] = "Clear the roster search and request a fresh roster. Checked players remain selected.",
    ["Whisper selected"] = "Check exactly one player to open a whisper. Banned players cannot be contacted through this action.",
    ["Player tools"] = "Click a roster row, then copy its public or officer note or inspect its ban history. Open Roster opens Blizzard's guild window.",
    ["View Events"] = "Open the event log for the player whose row you last clicked, or the full event log if no player is focused.",
    ["Previous page"] = "Show the previous 50 matching members. Checked players stay selected across pages.",
    ["Next page"] = "Show the next 50 matching members. Checked players stay selected across pages.",
    ["Copy Main"] = "Copy the Main note in your chapter's chosen format. Paste it into the player's public note yourself.",
    ["Copy Alt"] = "Copy the Alt note in your chapter's chosen format. Paste it into the player's public note yourself.",
    ["Main note format"] = "Choose Playername: Main, Main: Playername, or Playername-Main. The preview shows exactly what Copy Main will copy.",
    ["Alt note format"] = "Choose Playername: Alt, Alt: Playername, or Playername-Alt. The preview shows exactly what Copy Alt will copy.",
    ["Open realms"] = "Comma-separated realm names approved for recruiting from any chapter. These realms do not show a realm warning. Other invitation safeguards still apply.",
    ["Report Zone"] = "Suggest a quiet zone to chapter leadership. It does not become an approved rule until a rank 0–4 officer approves it.",
    ["Approve Zone"] = "Approve this reported quiet zone for the chapter and share the updated rules. Only guild ranks 0–4 may approve or remove quiet zones.",
    ["Save chapter rules"] = "Save all chapter sections and share the policy with online guild members. Log out or /reload to let Companion upload it.",
    ["Selected only"] = "Review every checked player, including selections hidden by the current search. Filtering and sorting keep your selections.",
    ["Clear selection"] = "Uncheck every selected player and disarm the current action queue.",
    ["Disarm"] = "Stop the queued action and release its temporary key binding. No additional players are changed.",
    ["Arm Kick (K)"] = "Prepare removal of the selected players. Review Selected only first, then use your configured cleanup key. WoW permissions are checked again before each batch.",
    ["Arm Promote (P)"] = "Prepare promotions for selected players. Ctrl+Shift+P performs one promotion; wait for the roster update before the next.",
    ["Arm Demote (D)"] = "Prepare demotions for selected players. Ctrl+Shift+D performs one demotion; wait for the roster update before the next.",
    ["Arm Group Invite (G)"] = "Prepare group invitations for selected players. Ctrl+Shift+G sends one invitation at a time.",
    ["Search fields"] = "Choose which fields your roster search checks. Commas mean OR, spaces mean AND, and quotation marks keep a phrase together.",
    ["Theme"] = "Choose the appearance of all Old Gods windows and controls.",
    ["Feedback type"] = "Choose Bug for a broken feature, Feedback for a suggestion, or Feature request for new functionality.",
    ["Queue feedback"] = "Save this report locally. /reload or log out, then let the signed-in Companion upload it.",
    ["Event type"] = "Choose the kind of calendar event you are creating.",
    ["Missing In Game Promotions"] = "Review the linked Discord requests and confirm that the requested in-game rank changes have been handled. This check is confirmed manually.",
    ["View"] = "Choose bank transaction history or the latest captured inventory. Open the guild bank and refresh to collect current information.",
    ["Kind"] = "Filter bank records to gold or items, or display both.",
    ["Type"] = "Choose which kinds of records to display. This changes the view; it does not delete records.",
    ["Add Ban"] = "Block outreach to this Character-Realm. Enter a reason. Adding a ban does not remove a guild member.",
    ["Reason"] = "Explain why this character is banned. Tab or Shift+Tab moves between Character-Realm and Reason.",
    ["Chapter"] = "Review chapter rules and their author/version. Leadership can edit rules; members receive shared settings.",
    ["Bank"] = "Review captured guild bank inventory and transactions. These records depend on information WoW has supplied.",
    ["Event Log"] = "Review recorded roster changes and recruitment activity. Filters only change which records are shown.",
} }
OldGodsUI.help["Add Event"] = "Submit this calendar event to WoW. For a repeating series, each occurrence requires its own click after the countdown."
OldGodsUI.help["Add Invitee"] = "Add the entered character to this event draft. The invitation is sent when the event is submitted."
OldGodsUI.help["Clear Invitees"] = "Remove all invitees from the current draft. Existing calendar events are unchanged."
OldGodsUI.help["New Event"] = "Start a new calendar draft. This clears the current form."
OldGodsUI.help["Clean Up Past Events"] = "Find past calendar events you can delete. Review the event name and date before confirming each deletion. Today, future events, holidays, and raid lockouts are preserved. Deleting an event removes it for all invitees."
OldGodsUI.help["Open WoW Calendar"] = "Open Blizzard’s calendar to review events and invitations."
OldGodsUI.help["Capture Now"] = "Request current guild bank inventory and transaction logs. Open the guild bank first so WoW can supply them."
OldGodsUI.help["Copy Bank JSON"] = "Developer tool: copy captured bank data for troubleshooting."
OldGodsUI.help["Copy Snapshot"] = "Developer tool: copy the most recent audit diagnostics. Restricted values are not exposed."
OldGodsUI.help["Copy Name"] = "Copy the selected character’s name and realm."
OldGodsUI.help["Copy Officer Note"] = "Copy the selected character’s Officer Note when WoW makes it available to you."
OldGodsUI.help["Copy Public Note"] = "Copy the selected character’s public note."
OldGodsUI.help["Ban List"] = "Review local outreach bans or add a character with a reason. Bans do not remove guild members."
OldGodsUI.help["Ban..."] = "Open the Ban List with this character filled in. Add a reason before saving."
OldGodsUI.help["Bind F12"] = "Temporarily assign F12 to the next Spazzy pickup action. One keypress performs the next permitted action."
OldGodsUI.help["Release F12"] = "Release Spazzy’s temporary F12 binding and restore the normal binding."
OldGodsUI.help["Spazzy"] = "Review prize-tab Pet Cage counts and prepare supported pickup actions. Open the guild bank first."
OldGodsUI.help["Clear x"] = "Clear the roster search and request a fresh roster. Checked players remain selected."
OldGodsUI.help["Compact Recruiter"] = "Open the smaller recruiting window. It shares the main candidate list. Ctrl+Shift+S searches and Ctrl+Shift+I invites one player."
OldGodsUI.help["Open Full Recruiter"] = "Open the full Recruiting tab with the same candidates and invitation history."
OldGodsUI.help["Complete"] = "Mark this event-log item as reviewed. This records your review; it does not change the player’s guild status."
OldGodsUI.help["Ignore Warning for This Character"] = "Acknowledge this character/guild realm mismatch. Other recruiting safeguards remain active. Leadership can approve Open Realms in Chapter settings."
OldGodsUI.help["Open Roster"] = "Open Blizzard’s guild roster to inspect or edit guild information using your existing permissions."
OldGodsUI.help["Prepare Demote"] = "Prepare a demotion for the selected member. The next step still requires your action and WoW permission."
OldGodsUI.help["Prepare Promote"] = "Prepare a promotion for the selected member. The next step still requires your action and WoW permission."
OldGodsUI.help["Prepare Kick"] = "Prepare removal of this member using your configured cleanup key. Preparing does not remove the member."
OldGodsUI.help["Prepare Remove"] = "Arm the removal confirmation for this member. Review the name before confirming."
OldGodsUI.help["Previous"] = "Show the previous page of records."
OldGodsUI.help["Next"] = "Show the next page of records."
OldGodsUI.help["Refresh"] = "Request fresh guild information and update the audit. Some data requires opening the relevant Blizzard window."
OldGodsUI.help["Refresh Audit"] = "Run the guild audit again using currently available data."
OldGodsUI.help["Refresh Events"] = "Request guild events and refresh the displayed event history."
OldGodsUI.help["Refresh Roster"] = "Request a fresh guild roster. Existing checked selections remain selected."
OldGodsUI.help["Quiet Zones"] = "Review protected zones and pending reports. Zone changes require approval by ranks 0–4."
OldGodsUI.help["Report Current Zone"] = "Report the zone you are standing in, using its exact name. Leadership must approve it before it becomes a chapter rule."
OldGodsUI.help["Remove Zone"] = "Remove this chapter quiet-zone rule. Only ranks 0–4 can do this; built-in protections remain active."
OldGodsUI.help["Search"] = "Apply the text entered in this page’s search box. Searching does not change saved records."
OldGodsUI.help["View Events"] = "Show the event history for the selected character."
OldGodsUI.help["Whisper"] = "Open a whisper to the selected character. You review and send the message yourself. Bans block outreach."
OldGodsUI.help["Category"] = "Choose membership, recruiting, notes or administration records, or view all categories."
OldGodsUI.help["Priority"] = "Choose which review status to display. Completed means someone marked the record reviewed."
OldGodsUI.help["Time"] = "Choose AM or PM for the event’s time."
OldGodsUI.help["Preview GRM Import"] = "Preview the bans that can be copied from GRM. Nothing is imported until you confirm."
OldGodsUI.help["Confirm Import"] = "Copy the previewed new bans. Existing bans are kept and GRM is unchanged."
OldGodsUI.help["Show Ban List"] = "Return from the import preview to the saved local bans."
OldGodsUI.help["Remove Ban"] = "Click once to arm removal, then confirm. This allows future outreach to the character."
OldGodsUI.help["Add selected bans"] = "Review each checked character and confirm a ban reason individually. The previous reason is available for reuse. Existing bans are preserved; this does not kick anyone."
OldGodsUI.help["Request latest rules"] = "Ask online chapter leadership to send the newest saved chapter policy."
OldGodsUI.help["Member target (980–1000)"] = "Set the chapter membership target used by recruiting and the audit. Enter a whole number from 980 to 1000."
OldGodsUI.help["Chapter cleanup announcement"] = "Enter the message officers should announce before cleanup. Preview it here; Save does not send it."
OldGodsUI.help["Donations tab number (1–8)"] = "Choose the numbered bank tab used by the audit and Spazzy. Its name and spelling do not affect selection."
OldGodsUI.help["Audit"] = "Review guild-wide standards and the actions needed to address each finding. Inactivity uses 28 days; leadership exemptions remain."
OldGodsUI.help["Recruiting"] = "Search for candidates, send one invitation at a time, and review quiet-zone reports."
OldGodsUI.help["Calendar"] = "Prepare guild event drafts and open the WoW calendar. Each event submission needs a click."
OldGodsUI.help["Roster"] = "Search, sort and review guild members. Check players to retain a selection across filters."
OldGodsUI.help["Feedback"] = "Queue a bug report or suggestion for upload by the desktop Companion."
OldGodsUI.help["Special"] = "Open Spazzy’s prize-tab helper and its guided pickup controls."
OldGodsUI.help["Debug"] = "Developer diagnostics for troubleshooting. These are not required for normal officer work."
OldGodsUI.help["Event name"] = "Enter the title members will see in the WoW calendar."
OldGodsUI.help["Hour"] = "Enter an hour from 1 to 12, then choose AM or PM."
OldGodsUI.help["Minute"] = "Enter minutes from 00 to 59."
OldGodsUI.help["Description"] = "Describe the event for members. WoW limits this field to 255 characters."
OldGodsUI.help["Repeat interval"] = "Enter the number of days between repeated events."
OldGodsUI.help["Occurrences"] = "Enter how many events to prepare in the series. Each occurrence still requires a click."
OldGodsUI.help["Invitee"] = "Enter the character to add to the draft invitee list."
OldGodsUI.help["Lock Event"] = "Lock the calendar event using WoW’s event setting."
OldGodsUI.help["Repeat"] = "Prepare a series of events using the interval and occurrence count below."
OldGodsUI.help["Feedback title"] = "Summarize the problem or suggestion in one sentence."
OldGodsUI.help["Feedback description"] = "Explain what happened or the improvement you want. Do not include passwords or other secrets."
OldGodsUI.help["Reproduction steps"] = "Optional: describe the steps that make the problem happen."
OldGodsUI.help["Roster search"] = "Search all visible player fields. Commas mean OR; spaces mean AND; quoted phrases stay together. Example: inactive:>=14 rankindex:>=2."
OldGodsUI.help["Bank search"] = "Filter captured bank transactions or inventory by the entered text."
OldGodsUI.help["Event search"] = "Find recorded events by character or event text."
OldGodsUI.help["Ban search"] = "Filter the local ban list by character, realm or reason."
OldGodsUI.help["Select player"] = "Keep this player selected across searches and sorting. Review Selected only before arming any action."
OldGodsUI.help["Reopen"] = "Mark this event-log item as needing review again. The original event record is kept."
local U = OldGodsUI
function U.Help(widget, key, detail)
    if not widget or not widget.HookScript then return end
    widget.oldGodsHelpKey = key
    if widget.oldGodsHelpHooked then return end
    widget.oldGodsHelpHooked = true
    widget:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        local label = self.oldGodsHelpKey or (self.GetText and self:GetText()) or "Option"
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label)
        GameTooltip:AddLine(detail or U.help[label] or ("Use " .. label .. ". Changes are shown on this page; queued actions still require confirmation or their action key."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end
-- An addon-owned menu: no Blizzard dropdown textures or global skin changes.
function U.Choose(button, choices, selectValue)
    if U.menu then U.menu:Hide() end
    local menu=U.menu or CreateFrame("Frame","OldGodsOptionsMenu",UIParent,"BackdropTemplate")
    if not U.menu and UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]="OldGodsOptionsMenu" end
    U.menu=menu
    menu:SetParent(button); menu:ClearAllPoints(); menu:SetFrameStrata("TOOLTIP"); menu:SetClampedToScreen(true)
    menu:SetPoint("TOPLEFT",button,"BOTTOMLEFT",0,-3)
    menu:SetSize(math.max(button:GetWidth(),210),math.min(#choices,8)*28+8)
    if not menu.scroll then
        menu.scroll=CreateFrame("ScrollFrame",nil,menu,"UIPanelScrollFrameTemplate")
        menu.scroll:SetPoint("TOPLEFT",4,-4); menu.scroll:SetPoint("BOTTOMRIGHT",-22,4)
        menu.content=CreateFrame("Frame",nil,menu.scroll); menu.scroll:SetScrollChild(menu.content); menu.options={}
    end
    menu.content:SetSize(menu:GetWidth()-26,#choices*28); menu.scroll:SetVerticalScroll(0)
    for _,option in ipairs(menu.options) do option:Hide() end
    for i,item in ipairs(choices) do
        local value,label=item[1],item[2]
        local option=menu.options[i] or U.Button(menu.content,label,function() end,menu:GetWidth()-28)
        menu.options[i]=option; option.oldGodsHelpKey=label; option:SetText(label); option:SetWidth(menu:GetWidth()-28); option:ClearAllPoints()
        option:SetPoint("TOPLEFT",0,-(i-1)*28)
        option:SetScript("OnClick",function() menu:Hide(); selectValue(value) end); option:Show()
    end
    if not button.oldGodsMenuHide then
        button.oldGodsMenuHide=true; button:HookScript("OnHide",function(self) if U.menu and U.menu:GetParent()==self then U.menu:Hide() end end)
    end
    if OldGodsTheme then OldGodsTheme.RegisterWindow(menu) end
    menu:Show()
end

function U.Dropdown(parent, label, choices, getter, setter, width)
    local button
    button = U.Button(parent, label, function()
        U.Choose(button, choices, function(value) setter(value); button:RefreshLabel() end)
    end, width)
    function button:RefreshLabel()
        for _, choice in ipairs(choices) do if choice[1] == getter() then self:SetText(label .. ": " .. choice[2] .. "  v"); return end end
        self:SetText(label .. "  v")
    end
    U.Help(button, label); button:RefreshLabel()
    return button
end
