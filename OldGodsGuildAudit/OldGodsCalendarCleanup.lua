-- Calendar deletion stays on a user click, with fresh indices for every event.
OldGodsCalendarCleanup = {}
local Cleanup = OldGodsCalendarCleanup
local waiting

local function dayNumber(value)
    if not value or not value.year or not value.month or not value.monthDay then return nil end
    return value.year * 10000 + value.month * 100 + value.monthDay
end

local function eligible(event, today)
    if not event or not event.eventID then return false end
    local ending = dayNumber(event.endTime or event.startTime)
    return ending and ending < today
        and (event.calendarType == "PLAYER" or event.calendarType == "GUILD_EVENT"
            or event.calendarType == "GUILD_ANNOUNCEMENT" or event.calendarType == "COMMUNITY_EVENT")
        and (event.modStatus == "CREATOR" or event.modStatus == "MODERATOR")
end

function Cleanup:Scan()
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local minimum = C_Calendar.GetMinDate()
    local base = C_Calendar.GetMonthInfo(0)
    local first = minimum.year * 12 + minimum.month
    local last = now.year * 12 + now.month
    local origin = base.year * 12 + base.month
    local found, seen = {}, {}
    for month = first, last do
        local offset = month - origin
        local info = C_Calendar.GetMonthInfo(offset)
        if info then
            for day = 1, info.numDays do
                for index = 1, C_Calendar.GetNumDayEvents(offset, day) do
                    local event = C_Calendar.GetDayEvent(offset, day, index)
                    if eligible(event, dayNumber(now)) and not seen[event.eventID]
                        and C_Calendar.ContextMenuEventCanRemove(offset, day, index) then
                        seen[event.eventID] = true
                        found[#found + 1] = { id = event.eventID, title = event.title,
                            ending = event.endTime or event.startTime, offset = offset, day = day, index = index }
                    end
                end
            end
        end
    end
    return found
end

function Cleanup:Status(text)
    if self.status then self.status:SetText(text) end
end

function Cleanup:Ready()
    if InCombatLockdown() then self:Status("Leave combat before cleaning up calendar events."); return false end
    if not C_Calendar or not C_Calendar.ContextMenuEventCanRemove
        or not C_Calendar.ContextMenuSelectEvent or not C_Calendar.ContextMenuEventRemove
        or not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then
        self:Status("Calendar cleanup is unavailable on this game client."); return false
    end
    if waiting or C_Calendar.IsActionPending() then
        self:Status("Waiting for WoW to finish the calendar request."); return false
    end
    return true
end

function Cleanup:Remove(id)
    if not self:Ready() then return end
    local ok, events = pcall(self.Scan, self)
    if not ok then self:Status("Calendar data is unavailable. Open WoW Calendar and try again."); return end
    for _, event in ipairs(events) do
        if event.id == id then
            -- Do not reuse the indices captured when the confirmation was opened.
            local selected = C_Calendar.GetDayEvent(event.offset, event.day, event.index)
            local now = C_DateAndTime.GetCurrentCalendarTime()
            if not selected or selected.eventID ~= id or not eligible(selected, dayNumber(now))
                or not C_Calendar.ContextMenuEventCanRemove(event.offset, event.day, event.index) then
                self:Status("Event changed. Click cleanup to scan again."); return
            end
            waiting = id
            local removed = pcall(function()
                C_Calendar.ContextMenuSelectEvent(event.offset, event.day, event.index)
                C_Calendar.ContextMenuEventRemove()
            end)
            if not removed then waiting = nil; self:Status("WoW refused the deletion. Open Calendar and try again."); return end
            self:Status("Deletion requested. Waiting for the calendar to update...")
            C_Timer.After(10, function()
                if waiting == id then
                    waiting = nil
                    Cleanup:Status("Deletion was not confirmed. Review WoW Calendar before trying again.")
                end
            end)
            return
        end
    end
    self:Status("That event is no longer eligible. Click cleanup to scan again.")
end

StaticPopupDialogs.OLD_GODS_CALENDAR_CLEANUP = {
    text = "Delete this past calendar event for all invitees?\n\n%s\n\nThis cannot be undone. Each event requires its own confirmation.",
    button1 = "Delete Event", button2 = "Cancel", timeout = 0,
    whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, id) Cleanup:Remove(id) end,
}

function Cleanup:Preview()
    if not self:Ready() then return end
    C_Calendar.OpenCalendar()
    local ok, events = pcall(self.Scan, self)
    if not ok then self:Status("Calendar data is unavailable. Open WoW Calendar and try again."); return end
    self:Status(string.format("%d removable past events found in WoW's available calendar history. Today and future dates are preserved.", #events))
    if #events == 0 then return end
    local event = events[1]
    local ending = event.ending
    local detail = string.format("%s\nEnded: %04d-%02d-%02d\nEligible events: %d",
        event.title or "Untitled event", ending.year, ending.month, ending.monthDay, #events)
    StaticPopup_Show("OLD_GODS_CALENDAR_CLEANUP", detail, nil, event.id)
end

function Cleanup:Build(page)
    local button = OldGodsUI.Button(page, "Clean Up Past Events", function() Cleanup:Preview() end, 180)
    button:SetPoint("RIGHT", page.newEventButton, "LEFT", -10, 0)
    self.status = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.status:SetPoint("TOPLEFT", 24, -530)
    self.status:SetWidth(800); self.status:SetJustifyH("LEFT")
    self:Status("Cleanup removes past events you can manage, one confirmation per event. Open WoW Calendar once before scanning.")
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
listener:RegisterEvent("CALENDAR_UPDATE_ERROR")
listener:SetScript("OnEvent", function(_, event)
    if not waiting then return end
    if event == "CALENDAR_UPDATE_ERROR" then
        waiting = nil; Cleanup:Status("WoW reported a calendar error. Review the event before trying again.")
    else
        local ok, events = pcall(Cleanup.Scan, Cleanup)
        if not ok then return end
        for _, item in ipairs(events) do if item.id == waiting then return end end
        waiting = nil
        Cleanup:Status("Event is no longer in the cleanup list. Click Clean Up Past Events for the next event.")
    end
end)
