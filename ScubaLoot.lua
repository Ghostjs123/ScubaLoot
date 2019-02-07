--==========================================================================================================

-- Init functions and globals

officerRank1 = "Rear Admiral"
officerRank2 = "Salty Dog"
officerRank3 = "ExtraRank"

ScubaLootTitle = "CLC"
ScubaLootVersion = "1.0"

ScubaLoot_SessionOpen = true
ScubaLoot_QueuedItems = {} -- if multiple items are raid warning'd then they will go here

ScubaLoot_GUIMaximized = true

ScubaLoot_OfficerList = {}
ScubaLoot_FinishedVotingCount = 0

ScubaLoot_Sort = {
    Names = {}, -- names of the people linking
    Links = {} -- items that they linked
}

SlashCmdList["SLASH_SCUBALOOT"] = function() end

SLASH_SCUBALOOT1 = "/sl"
function SlashCmdList.SCUBALOOT(args)
    if(string.find(args, " ")) then
        args = split(args, " ")
    end

    if(type(args) == "string") then
        args = {args} -- need it to be a table, even if just one value
    end

    if(ScubaLoot_HasValue(args, "test")) then
        ScubaLoot_Test()
    else
        ScubaLoot_ToggleGUI()
    end
end

function ScubaLoot_Test()
    ScubaLoot_tprint(ScubaLoot_OfficerList)
end

function ScubaLoot_OnLoad()
    this:RegisterEvent("VARIABLES_LOADED")
    this:RegisterEvent("CHAT_MSG_RAID")
    this:RegisterEvent("CHAT_MSG_RAID_LEADER")
    this:RegisterEvent("CHAT_MSG_RAID_WARNING")
    this:RegisterEvent("CHAT_MSG_OFFICER")
end

function ScubaLoot_Init()
    -- reinitialize globals
    ScubaLoot_Sort.Names = {}
    ScubaLoot_Sort.Links = {}

    --ScubaLoot_SessionOpen = false
    ScubaLoot_ItemBeingDecided = ""
    ScubaLoot_QueuedItems = {}

    ScubaLoot_GUIMaximized = true

    ScubaLoot_FinishedVotingCount = 0

    -- call some functions
    ScubaLoot_FillOfficerList()
end

--==========================================================================================================

-- Main addon functions

-- arg1
--    chat message
-- arg2
--    author
-- arg3
--    lineID
function ScubaLoot_OnEvent(event, arg1, arg2, arg3, arg4, arg5)
    if(event == "VARIABLES_LOADED") then
        this:UnregisterEvent("VARIABLES_LOADED")
        ScubaLoot_Init()
    elseif(event == "CHAT_MSG_RAID_WARNING") then
        ScubaLoot_OpenLootSession(arg1)
    elseif(event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER") then
        if(ScubaLoot_SessionOpen) then
            ScubaLoot_AddToSort(arg1, arg2)
            ScubaLoot_HandleOfficerMessage(arg1, arg2) -- todo remove this later
        end
    elseif(event == "CHAT_MSG_OFFICER") then
        ScubaLoot_HandleOfficerMessage(arg1, arg2)
    end
end

-- arg1
--    chat message
-- arg2
--    author
function ScubaLoot_AddToSort(arg1, arg2)
    local itemLinks = ScubaLoot_GetItemLinks(arg1)
    if(itemLinks) then
        if(ScubaLoot_HasValue(ScubaLoot_Sort.Names, arg2) == false) then
            table.insert(ScubaLoot_Sort.Names, arg2) -- add name
            table.insert(ScubaLoot_Sort.Links, itemLinks) -- add items
        else
            for k, v in pairs(ScubaLoot_Sort.Names) do
                if(v == arg2) then
                    ScubaLoot_Sort.Links[k] = itemLinks
                end
            end
        end
        ScubaLoot_UpdateRows()
    end
end

-- arg1
--    chat message
function ScubaLoot_GetItemLinks(arg1)
    local items = {}
    local added = false
    -- matches one or more items similar to |Hitem:6948:0:0:0:0:0:0:0|h[Hearthstone]|h
    for item in string.gmatch(arg1, "|.-]|h") do
        table.insert(items, item)
        added = true
    end
    if(added) then
        -- also need any additional text
        arg1 = string.gsub(arg1, "|.-]|h", "") -- removes the links from the msg
        items[3] = arg1 -- index 3 could possibly be another item link so index it directly
        return items
    else
        return nil
    end
end

-- arg1
--    chat message
function ScubaLoot_OpenLootSession(arg1)
    -- if item is linked in rw then start a loot session
    -- do not start if arg1 contains "roll"
    local itemLinks = ScubaLoot_GetItemLinks(arg1)
    if(itemLinks[1] and string.find(strlower(arg1), "roll") == nil) then
        ScubaLoot_UpdateMainItem(itemLinks)
    end
end

-- itemLinks
--    one or more linked items in a table
function ScubaLoot_UpdateMainItem(itemLinks)
    for _, link in itemLinks do
        if(link ~= nil) then
            -- make sure the link is a link bc itemLinks also contains the note text in index 3
            if(string.find(link, "|.-]|h") ~= nil) then
                table.insert(ScubaLoot_QueuedItems, link)
            end
        end
    end
    if(ScubaLoot_QueuedItems[1]) then
        local nextItem = table.remove(ScubaLoot_QueuedItems, 1)
        ScubaLoot_AddMainItemToGUI(nextItem)
        ScubaLoot_ItemBeingDecided = nextItem
        SendChatMessage("Link for " .. ScubaLoot_LinkToName(nextItem), "RAID")
    end
end

-- arg1
--    chat message
-- arg2
--    author
function ScubaLoot_HandleOfficerMessage(arg1, arg2)
    if(ScubaLoot_OfficerList[arg2]) then
        if(string.find(arg1, "I voted for") ~= nil) then
            arg1 = string.gsub(arg1, "I voted for ", "")
            ScubaLoot_OfficerList[arg2] = arg1
            ScubaLoot_UpdateVoteCounts()
        elseif(string.find(arg1, "I unvoted for") ~= nil) then
            arg1 = string.gsub(arg1, "I unvoted for ", "")
            ScubaLoot_OfficerList[arg2] = ""
            ScubaLoot_UpdateVoteCounts()
        elseif(string.find(arg1, "has finished voting")) then
            ScubaLoot_FinishedVotingCount = ScubaLoot_FinishedVotingCount + 1
        elseif(string.find(arg1, "has not finished voting")) then
            ScubaLoot_FinishedVotingCount = ScubaLoot_FinishedVotingCount - 1
        end
    end
end

function ScubaLoot_UpdateVoteCounts()
    DEFAULT_CHAT_FRAME:AddMessage("ScubaLoot_UpdateVoteCounts")
    local tempVoteTable = {}
    for officerName, linkerName in ScubaLoot_OfficerList do
        local playerIndex
        for i = 1, table.getn(ScubaLoot_Sort.Names) do
            if(ScubaLoot_Sort.Names[i] == linkerName) then
                playerIndex = i
                break
            end
        end
        if(playerIndex) then
            if(tempVoteTable[playerIndex]) then
                tempVoteTable[playerIndex] = tempVoteTable[playerIndex] + 1
            else
                tempVoteTable[playerIndex] = 1
            end
        end
    end
    for index, count in tempVoteTable do
        local voteText = getglobal("ScubaLootVoteCount"..index.."Text")
        voteText:SetText(count)
    end
    -- set all others to 0 if not in tempVoteTable
    for i = 1, table.getn(ScubaLoot_Sort.Names) do
        if(tempVoteTable[i] == nil) then
            local voteText = getglobal("ScubaLootVoteCount"..i.."Text")
            voteText:SetText("0")
        end
    end
end

function ScubaLoot_GetNameByID(itemLink)
    local name, _, quality, _, _, _, _, _, texture = GetItemInfo(ScubaLoot_LinkToID(itemLink))
    return name, texture, quality
end

function ScubaLoot_LinkToID(itemLink)
    -- item link format ex: |Hitem:6948:0:0:0:0:0:0:0|h[Hearthstone]|h
    -- matches anything inside the first 2 :'s ex: |Hitem:6948:0:0:0:0: -> 6948
    return string.match(itemLink, ":(%d+)")
end

function ScubaLoot_LinkToName(itemLink)
    -- item link format ex: |Hitem:6948:0:0:0:0:0:0:0|h[Hearthstone]|h
    -- matches anything inside square brackets ex: asdasd[abc]asdasd -> abc
    return string.match(itemLink, "%[(.+)%]")
end

function ScubaLoot_GetPlayerRGB(playerName)
    -- couldn't think of a quick way to do this w/o looping through the raid
    -- can't use UnitClass("UnitID") bc a players name is not a UnitID
    for i = 1, 40 do
        local name, _, _, _, class, _, _, _, _, _, _ = GetRaidRosterInfo(i)
        if(name == playerName) then
            -- colors from : https://wow.gamepedia.com/Class_colors
            if(class == "Warrior") then
                return 0.78, 0.61, 0.43
            elseif(class == "Rogue") then
                return 1.00, 0.96, 0.41
            elseif(class == "Mage") then
                return 0.25, 0.78, 0.92
            elseif(class == "Warlock") then
                return 0.53, 0.53, 0.93
            elseif(class == "Hunter") then
                return 0.67, 0.83, 0.45
            elseif(class == "Paladin") then
                return 0.96, 0.55, 0.73
            elseif(class == "Druid") then
                return 1.00, 0.49, 0.04
            elseif(class == "Priest") then
                return 1.00, 1.00, 1.00
            elseif(class == "Shaman") then
                return 0.00, 0.44, 0.87
            else
                DEFAULT_CHAT_FRAME:AddMessage("ScubaLoot_GetPlayerRGB - Error could not find " .. playerName .. "'s class")
            end
        end
    end
end

function ScubaLoot_FillOfficerList()
    -- loop through the entire guild roster
    -- numTotalMembers, numOnlineMembers
    local numTotalMembers, _ = GetNumGuildMembers()
    for i = 1, numTotalMembers do
        local name, rank, _, _, _, zone, _, _, online, _, _, _, _, _ = GetGuildRosterInfo(i)
        if(online ~= nil) then
            if(rank == officerRank1 or rank == officerRank2 or rank == officerRank3) then
                ScubaLoot_OfficerList[name] = "" -- empty string signifies has not voted
            end
        end
    end

    -- add ppl testing the addon, non officers of course
    -- todo remove later
    ScubaLoot_OfficerList["Kaymon"] = ""
    ScubaLoot_OfficerList["Kaymage"] = ""
    ScubaLoot_OfficerList["Forest"] = ""
    ScubaLoot_OfficerList["Forestbank"] = ""
    ScubaLoot_OfficerList["Zela"] = ""
    ScubaLoot_OfficerList["Ztaps"] = ""
end

function ScubaLoot_GetItemWinner()
    local voteText
    local highest = 0
    local highestIndex = 0
    for i= 1, 40 do
        voteText = getglobal("ScubaLootVoteCount"..i.."Text")
        if(tonumber(voteText:GetText()) > highest) then
            highest = tonumber(voteText:GetText())
            highestIndex = i
        end
    end
    return ScubaLoot_Sort.Names[highestIndex]
end

function ScubaLoot_AnnounceWinner()
    SendChatMessage(GetItemWinner() .. " wins: " .. ScubaLoot_OfficerList, "RAID_WARNING")
end

function ScubaLoot_tprint(tbl, indent)
    if not indent then indent = 0 end
    for k, v in pairs(tbl) do
        local formatting = string.rep("  ", indent) .. k .. ": "
        if type(v) == "table" then
            DEFAULT_CHAT_FRAME:AddMessage(formatting)
            tprint(v, indent+1)
        elseif type(v) == 'boolean' then
            DEFAULT_CHAT_FRAME:AddMessage(formatting .. tostring(v))
        else
            DEFAULT_CHAT_FRAME:AddMessage(formatting .. v)
        end
    end
end

--==========================================================================================================

-- GUI specific code

-- itemLink
--    itemLink as a string
function ScubaLoot_AddMainItemToGUI(itemLink)
    local item = getglobal("ScubaLootMainItem")
    local itemText = getglobal("ScubaLootMainItemText")
    local itemName = getglobal("ScubaLootMainItemName")
    local itemIcon = getglobal("ScubaLootMainItemIcon")
    local name, texture, quality = ScubaLoot_GetNameByID(itemLink)
    itemIcon:SetTexture(texture)
    itemName:SetText(name)
    local r,g,b = GetItemQualityColor(quality)
    itemName:SetTextColor(r,g,b)
    itemIcon:SetVertexColor(1,1,1)
    itemText:SetText("Linking for: ")
    item:Show()
end

function ScubaLoot_UpdateRows()
    local list = ScubaLoot_Sort.Links

    if list then
        local r, g, b, found
        local texture, name, quality
        local itemCheckBox, itemPlayer
        local item1, itemName1, itemIcon1
        local item2, itemName2, itemIcon2
        local note, noteText, vote
        for i = 1, 40 do
            item1 = getglobal("ScubaLootRow"..i)
            itemPlayer = getglobal("ScubaLootRow"..i.."Player")
            itemName1 = getglobal("ScubaLootRow"..i.."Name")
            itemIcon1 = getglobal("ScubaLootRow"..i.."Icon")
            item2 = getglobal("ScubaLootAdditionalItem"..i)
            itemName2 = getglobal("ScubaLootAdditionalItem"..i.."Name")
            itemIcon2 = getglobal("ScubaLootAdditionalItem"..i.."Icon")
            itemCheckBox = getglobal("ScubaLootRowCheckBox"..i)
            note = getglobal("ScubaLootLinkNote"..i)
            noteText = getglobal("ScubaLootLinkNote"..i.."Text")
            vote = getglobal("ScubaLootVoteCount"..i)
            if i <= table.getn(list) then
                name, texture, quality = ScubaLoot_GetNameByID(list[i][1])
                itemIcon1:SetTexture(texture)
                itemName1:SetText(name)
                r,g,b = GetItemQualityColor(quality)
                itemName1:SetTextColor(r,g,b)
                itemIcon1:SetVertexColor(1,1,1)
                if(table.getn(list[i]) >= 2) then -- multiple links
                    name, texture, quality = ScubaLoot_GetNameByID(list[i][2])
                    itemIcon2:SetTexture(texture)
                    itemName2:SetText(name)
                    r,g,b = GetItemQualityColor(quality)
                    itemName2:SetTextColor(r,g,b)
                    itemIcon2:SetVertexColor(1,1,1)

                    if(ScubaLoot_GUIMaximized) then
                        item2:Show()
                    end
                    noteText:ClearAllPoints()
                    noteText:SetPoint("LEFT", item2, "RIGHT", 2, 0)
                else
                    noteText:ClearAllPoints()
                    noteText:SetPoint("LEFT", item1, "RIGHT", 2, -1)
                end
                itemPlayer:SetText(ScubaLoot_Sort.Names[i] .. ":")
                r,g,b = ScubaLoot_GetPlayerRGB(ScubaLoot_Sort.Names[i])
                itemPlayer:SetTextColor(r,g,b)
                noteText:SetText(list[i][3])

                if(ScubaLoot_GUIMaximized) then
                    item1:Show()
                    itemCheckBox:Show()
                    note:Show()
                    vote:Show()
                end
            else
                item1:Hide()
                item2:Hide()
                itemCheckBox:Hide()
                note:Hide()
                vote:Hide()
            end
        end
        if(ScubaLoot_GUIMaximized) then -- update height and width
            ScubaLootFrame:SetHeight(80 + ScubaLoot_GetTableLength(list) * 26)
            local newWidth = 330
            for _, tab in ScubaLoot_Sort.Links do
                if table.getn(tab) >= 2 then
                    newWidth = 452
                    break
                end
            end
            ScubaLootFrame:SetWidth(newWidth)
        end
    end
end

-- shows tooltip for items in the sort list
function ScubaLoot_ShowTooltip(id)
    local list = ScubaLoot_Sort.Links[id]

    if list then
        local _, link = GetItemInfo(ScubaLoot_LinkToID(list[1]))
        GameTooltip:SetOwner(ScubaLootFrame, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

function ScubaLoot_ShowAlternateTooltip(id)
    local list = ScubaLoot_Sort.Links[id]

    if list then
        local _, link = GetItemInfo(ScubaLoot_LinkToID(list[2]))
        GameTooltip:SetOwner(ScubaLootFrame, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

function ScubaLoot_ShowMainItemToolTip()
    if ScubaLoot_ItemBeingDecided then
        local _, link = GetItemInfo(ScubaLoot_LinkToID(ScubaLoot_ItemBeingDecided))
        GameTooltip:SetOwner(ScubaLootFrame, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

function ScubaLootFrameTitleText_OnShow()
    ScubaLootFrameTitleText:SetText(ScubaLootTitle .. " v" .. ScubaLootVersion)
end

function ScubaLoot_ToggleGUI()
    if ScubaLootFrame:IsShown() then
        ScubaLootFrame:Hide()
    else
        ScubaLootFrame:Show()
    end
end

function ScubaLoot_RegisterVote(itemID)
    local list = ScubaLoot_Sort.Names

    local item = getglobal("ScubaLootRowCheckBox"..itemID)
    if(item:GetChecked()) then
        SendChatMessage("I voted for " .. list[itemID], "RAID")
        -- uncheck all other checkboxs
        for i = 1,40 do
            item = getglobal("ScubaLootRowCheckBox"..i)
            if(itemID ~= i and item:GetChecked()) then
                item:SetChecked(false)
            end
        end
    else
        SendChatMessage("I unvoted for " .. list[itemID], "RAID")
    end
end

function ScubaLoot_FinishedVoting()
    local playerName = UnitName("player")
    if(FinishedVotingCheckbox:GetChecked()) then
        SendChatMessage(playerName .. " has finished voting", "RAID")
    else
        SendChatMessage(playerName .. " has not finished voting", "RAID")
    end
end

function ScubaLoot_GetTableLength(tab)
    local count = 0
    for _, _ in tab do
        count = count + 1
    end
    return count
end

function ScubaLoot_ToggleGUISize()

    local item1, item2, itemCheckBox, note, vote

    -- initial frame height is 80
    -- shouldn't hardcode 81 but w/e
    if(ScubaLootFrame:GetHeight() > 81) then -- minimize
        ScubaLoot_GUIMaximized = false
        -- hide all of the checkboxes and rows etc
        for i = 1, 40 do
            item1 = getglobal("ScubaLootRow"..i)
            item2 = getglobal("ScubaLootAdditionalItem"..i)
            itemCheckBox = getglobal("ScubaLootRowCheckBox"..i)
            note = getglobal("ScubaLootLinkNote"..i)
            vote = getglobal("ScubaLootVoteCount"..i)
            item1:Hide()
            item2:Hide()
            itemCheckBox:Hide()
            note:Hide()
            vote:Hide()
        end
        -- update the height
        ScubaLootFrame:SetHeight(80)
    else -- maximize
        ScubaLoot_GUIMaximized = true
        -- show all of the checkboxes and rows etc
        local list = ScubaLoot_Sort.Links
        for i = 1, 40 do
            item1 = getglobal("ScubaLootRow"..i)
            item2 = getglobal("ScubaLootAdditionalItem"..i)
            itemCheckBox = getglobal("ScubaLootRowCheckBox"..i)
            note = getglobal("ScubaLootLinkNote"..i)
            vote = getglobal("ScubaLootVoteCount"..i)
            if i <= table.getn(list) then
                item1:Show()
                itemCheckBox:Show()
                note:Show()
                vote:Show()
                if table.getn(list[i]) >= 2 then
                    item2:Show()
                end
            end
        end
        -- update the height
        ScubaLootFrame:SetHeight(80 + ScubaLoot_GetTableLength(list) * 26)
    end
end

--==========================================================================================================

-- Aditional functions

-- credit Sol
string.match = string.match or function(str, pattern)
    local tbl_res = { string.find(str, pattern) }

    if tbl_res[3] then
        return select(3, unpack(tbl_res))
    else
        return tbl_res[1], tbl_res[2]
    end
end

-- credit Sol
select = select or function(idx, ...)
    local len = table.getn(arg)

    if type(idx) == 'string' and idx == '#' then
        return len
    else
        local tbl = {}

        for i = idx, len do
            table.insert(tbl, arg[i])
        end

        return unpack(tbl)
    end
end

-- credit Sol
string.split = string.split or function(delim, s, limit)
    local split_string = {}
    local rest = {}

    local i = 1
    for str in string.gfind(s, '([^' .. delim .. ']+)' .. delim .. '?') do
        if limit and i >= limit then
            table.insert(rest, str)
        else
            table.insert(split_string, str)
        end

        i = i + 1
    end

    if limit then
        table.insert(split_string, string.join(delim, unpack(rest)))
    end

    return unpack(split_string)
end

-- credit Sol
string.gmatch = string.gmatch or function(str, pattern)
    local init = 0

    return function()
        local tbl = { string.find(str, pattern, init) }

        local start_pos = tbl[1]
        local end_pos = tbl[2]

        if start_pos then
            init = end_pos + 1

            if tbl[3] then
                return unpack({select(3, unpack(tbl))})
            else
                return string.sub(str, start_pos, end_pos)
            end
        end
    end
end

-- credit Sol
string.trim = string.trim or function(str)
    return string.gsub(str, '^%s*(.-)%s*$', '%1')
end

function ScubaLoot_HasValue(tab, val)
    for _, value in tab do
        if value == val then
            return true
        end
    end
    return false
end
