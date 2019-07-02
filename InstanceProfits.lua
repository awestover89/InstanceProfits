-- TODO: Fix when logging in/out/reloading in an instance
-- TODO: Check for player repairing inside dungeon
-- TODO: Refactor and clean code into multiple LUA files
-- TODO: OPT: Add Auction Value option
-- TODO: OPT: Add option to enable/disable when in a group

---------
-- new --
---------
local strmatch, strgsub = string.match, string.gsub

local isInPvEInstance = false

local IGNORED_ZONES = { [1152]=true, [1330]=true, [1153]=true, [1154]=true, [1158]=true, [1331]=true, [1159]=true, [1160]=true };
local LOOT_ITEM_PATTERN = strgsub(LOOT_ITEM_SELF, "%%s", "(.+)")
local LOOT_ITEM_MULTIPLE_PATTERN = strgsub(strgsub(LOOT_ITEM_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)")
local LOOT_ITEM_PUSHED_PATTERN = strgsub(LOOT_ITEM_PUSHED_SELF, "%%s", "(.+)")
local LOOT_ITEM_PUSHED_MULTIPLE_PATTERN = strgsub(strgsub(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)")
local LOOT_ITEM_BONUS = strgsub(LOOT_ITEM_BONUS_ROLL_SELF, "%%s", "(.+)");
local LOOT_ITEM_MULTIPLE_BONUS = strgsub(strgsub(LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)")
local FILTER_BUTTONS = {}
local filteredDifficulties, tempFilters, globalSortedInstances, characterSortedInstances, textColors = {}, {}, {}, {}, {}
local sortDir, tempSortDir = "nameA", "nameA"
local minTime = 30
local minTimeUnit = "Seconds"
local scrollframe, scrollbar = {}, {}
local pageValues = {}

---------
-- old --
---------

local enteredAlive = true
instanceName, instanceDifficulty, instanceDifficultyName, startTime, startRepair, recentLimit = nil, nil, nil, 0, 0, 5;
characterHistory, globalHistory, contentButtons, detailButtons, recentHistory = {}, {}, {}, {}, {};
content, detailedContent = nil, nil;
contentButtonFrame, detailButtonFrame = nil, nil;
displayGlobal = false;
liveName = nil;
liveDifficulty = nil;
liveTime = nil;
liveLoot = nil;
liveVendor = nil;
detailedHeader, charDetails, acctDetails = nil, nil, nil;
prevPage, nextPage = nil, nil;
lastProfit, lastTime, shareType = nil, nil, nil;
local lootableItems = {};
local elapsedTime, lootedMoney, vendorMoney = 0, 0, 0;
local version = "0.7.1";
local repairTooltip = nil;

local frame = CreateFrame("FRAME", "InstanceProfitsFrame");
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
frame:RegisterEvent("PLAYER_ENTERING_WORLD");
frame:RegisterEvent("ADDON_LOADED");
frame:RegisterEvent("PLAYER_LOGOUT");
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED");

-- loot
frame:RegisterEvent("CHAT_MSG_LOOT");
frame:RegisterEvent("CHAT_MSG_MONEY");

function IP_PrintWelcomeMessage()
	print("|cFF00CCFF<IP>|r Instance Profit Tracker v. " .. version .. " loaded.");
	print("|cFF00CCFF<IP>|r Use \"/ip\" or \"/instanceprofit\" to display saved profit data.");
	print("|cFF00CCFF<IP>|r Use \"/ip live\" or \"/instanceprofit live\" to display the live tracker.");
end

function IP_CalculateRepairCost()
	repairTooltip = repairTooltip or CreateFrame("GameTooltip");
	local slots = {'HEADSLOT', 'NECKSLOT', 'SHOULDERSLOT',
	'BACKSLOT', 'CHESTSLOT', 'WRISTSLOT', 'HANDSSLOT',
	'WAISTSLOT', 'LEGSSLOT', 'FEETSLOT', 'FINGER0SLOT',
	'FINGER1SLOT', 'TRINKET0SLOT', 'TRINKET1SLOT',
	'MAINHANDSLOT', 'SECONDARYHANDSLOT'};
	local totalRepairCost = 0;
	for i, slot in ipairs(slots) do
		repairTooltip:ClearLines();
		local slotId, _ = GetInventorySlotInfo(slot);
		local hasItem, _, repairCost = repairTooltip:SetInventoryItem("player", slotId);
		if ((hasItem) and (repairCost) and (repairCost > 0)) then
			totalRepairCost = totalRepairCost + repairCost;
		end
	end
	return totalRepairCost;
end

function copperToString(copper)
	local gold = math.floor(copper/10000);
	local silver = math.floor((copper - gold*10000)/100);
	local remains = copper % 100;
	local lootedString = gold .. " gold, " .. silver .. " silver, and " .. remains .. " copper";
	return lootedString;
end

function timeToSmallString(seconds)
	local hours = math.floor(seconds/3600);
	seconds = seconds - (hours  * 3600);
	local minutes = math.floor(seconds/60);
	seconds = seconds - (minutes * 60);
	if hours < 10 then
		hours = "0" .. hours;
	end
	if minutes < 10 then
		minutes = "0" .. minutes;
	end
	if seconds < 10 then
		seconds = "0" .. seconds;
	end
	return hours .. ":" .. minutes .. ":" .. seconds;
end

function IsDungeonPartiallyCompleted()
	local _, _, numCriteria = C_Scenario.GetStepInfo()
	for i=1,numCriteria do
		if select(3,C_Scenario.GetCriteriaInfo(i)) then
			return true -- something completed
		end
	end
	return false;
end

function IP_ShowLiveTracker()
	InstanceProfits_LiveDisplay:Show();
	liveName = liveName or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveDifficulty = liveDifficulty or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveTime = liveTime or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveLoot = liveLoot or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveVendor = liveVendor or InstanceProfits_LiveDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Small");
	liveName:SetText(instanceName);
	liveDifficulty:SetText(instanceDifficultyName);
	liveTime:SetText(liveTime:GetText() or "Time: 00:00:00");
	liveLoot:SetText("Looted: " .. GetMoneyString(lootedMoney));
	liveVendor:SetText("Vendor: " .. GetMoneyString(vendorMoney));
	local ofsy = -5;
	liveName:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveName:GetStringHeight() - 5;
	liveDifficulty:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveDifficulty:GetStringHeight() - 5;
	liveTime:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveTime:GetStringHeight() - 5;
	liveLoot:SetPoint("TOPLEFT", 5, ofsy);
	ofsy = ofsy - liveLoot:GetStringHeight() - 5;
	liveVendor:SetPoint("TOPLEFT", 5, ofsy);
end

function triggerInstance(name, difficulty, difficultyName, incCount)
	if incCount then
		startTime = time();
		instanceName = name;
		instanceDifficulty = difficulty;
		instanceDifficultyName = difficultyName;
		startRepair = IP_CalculateRepairCost();
		lootedMoney, vendorMoney = 0, 0;
	end
	local n = GetNumSavedInstances();
	local saved = IsDungeonPartiallyCompleted();
	if not saved then
		for i=1, n do
			local savedName, saveId, resets, savedDifficulty, locked = GetSavedInstanceInfo(i);
			if (savedName == instanceName and locked and difficulty > 1) then
				saved = true;
			end
		end
	end
	if (not saved and incCount) then
		if (characterHistory[name] == nil) then
			characterHistory[name] = {
				[difficultyName] = {
					['count'] = 1,
					['totalTime'] = 0,
					['totalRepair'] = 0,
					['totalLoot'] = 0,
					['totalVendor'] = 0
				}
			};
		elseif (characterHistory[name][difficultyName] == nil) then
			characterHistory[name][difficultyName] = {
				['count'] = 1,
				['totalTime'] = 0,
				['totalRepair'] = 0,
				['totalLoot'] = 0,
				['totalVendor'] = 0
			};
		else
			characterHistory[name][difficultyName]['count'] = characterHistory[name][difficultyName]['count'] + 1;
		end
		if (globalHistory[name] == nil) then
			globalHistory[name] = {
				[difficultyName] = {
					['count'] = 1,
					['totalTime'] = 0,
					['totalRepair'] = 0,
					['totalLoot'] = 0,
					['totalVendor'] = 0
				}
			};
		elseif (globalHistory[name][difficultyName] == nil) then
			globalHistory[name][difficultyName] = {
				['count'] = 1,
				['totalTime'] = 0,
				['totalRepair'] = 0,
				['totalLoot'] = 0,
				['totalVendor'] = 0
			};
		else
			globalHistory[name][difficultyName]['count'] = globalHistory[name][difficultyName]['count'] + 1;
		end
	end
	IP_ShowLiveTracker();
	print("You have entered the " .. difficultyName .. " version of " .. name);
	print("You have recorded your profits for this instance " .. characterHistory[name][difficultyName]['count'] .. " times on this character.");
	print("You have recorded your profits for this instance " .. globalHistory[name][difficultyName]['count'] .. " times on this account.");
end

function IP_DeleteInstanceData(instance, difficulty)
	if not displayGlobal then
		for key, value in pairs(characterHistory[instance][difficulty]) do
			globalHistory[instance][difficulty][key] = globalHistory[instance][difficulty][key] - value;
		end
		if (globalHistory[instance][difficulty]["count"] == 0) then
			globalHistory[instance][difficulty] = nil;
		end
		characterHistory[instance][difficulty] = nil;
	end
end

function IP_DisplaySavedData(page)
	scrollbar[1]:SetValue(0)
	pageValues[page] = {}
	if page == 1 then
		pageValues[page]["r"] = 0
		pageValues[page]["p"] = 0
		pageValues[page]["t"] = 0
		pageValues[page]["index"] = 0
	else
		pageValues[page] = pageValues[page-1]
	end
	content = content or CreateFrame("Frame", nil, scrollframe[1]);
	contentButtonFrame = contentButtonFrame or CreateFrame("Frame", nil, content);
	contentButtonFrame:SetAllPoints(true);
	contentButtonFrame:SetWidth(20);
	detailButtonFrame = detailButtonFrame or CreateFrame("Frame", nil, content);
	detailButtonFrame:SetAllPoints(true);
	detailButtonFrame:SetWidth(20);
	content.text = content.text or content:CreateFontString(nil,"ARTWORK","SystemFont_Med1")
	content:SetHeight(10000);
	content:SetWidth(450);
	content.text:SetAllPoints(true)
	content.text:SetJustifyH("LEFT")
	content.text:SetJustifyV("TOP")
	content.text:SetTextColor(textColors['main']['r'], textColors['main']['g'], textColors['main']['b'], textColors['main']['a'])
	prevPage = prevPage or CreateFrame("Button", nil, InstanceProfits_TableDisplay, "UIPanelButtonTemplate");
	nextPage = nextPage or CreateFrame("Button", nil, InstanceProfits_TableDisplay, "UIPanelButtonTemplate");
	local dataString = "\n";
	local i, j = 0, 0;
	local showNext = false;
	local count = 0;
	if displayGlobal then
		local offy = 8
		for index, instance in pairs(globalSortedInstances) do
			if index >= pageValues[page]["index"] then
				if count > 25 then
					showNext = true
					pageValues[page]["index"] = index;
					break
				end
				data = globalHistory[instance]
				local firstPrint = true;
				for difficulty, values in pairs(data) do
					if filteredDifficulties[difficulty] == true then
						if firstPrint then	
							count = count + 1;
							dataString = dataString .. instance .. "\n";
							j = j + 1;
							detailButtons[j] = detailButtons[j] or CreateFrame("Button", nil, detailButtonFrame, "UIPanelButtonTemplate");
							------------------------
							-- ElvUI Skin Support --
							------------------------
							if (IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")) then
							  local c;
							  if ElvUI then
								local E, L, V, P, G, DF = unpack(ElvUI);
								c = E;
							  else
								local T, C, L, G = unpack(Tukui);
								c = T;
								c.TexCoords = {.08, .92, .08, .92};
							  end
							  local S = c:GetModule('Skins');
							  S:HandleButton(detailButtons[j]);
							end
							detailButtons[j]:SetPoint("TOPRIGHT", 0, offy * -1);
							detailButtons[j]:SetText("Details");
							detailButtons[j]:SetSize(60, 20);
							detailButtons[j]:SetNormalFontObject("GameFontNormal");
							detailButtons[j]:SetScript("OnClick", function(self, button, down)
								IP_ShowDetails(instance);
							end);
							detailButtons[j].tooltip_text = "View enhanced details of saved data for " .. instance;
							detailButtons[j]:SetScript("OnEnter", IP_TippedButtonOnEnter)
							detailButtons[j]:SetScript("OnLeave", IP_TippedButtonOnLeave)
							detailButtons[j]:Show();
							firstPrint = false;
						end
						dataString = dataString .. "    (" .. difficulty .. ") | " .. values['count'] .. " | " .. GetMoneyString(values['totalLoot'] + values['totalVendor'] - values['totalRepair']) .. " | " .. timeToSmallString(values['totalTime']) .. "\n";
						pageValues[page]["r"] = pageValues[page]["r"] + values['count']
						pageValues[page]["p"] = pageValues[page]["p"] + values['totalLoot'] + values['totalVendor'] - values['totalRepair']
						pageValues[page]["t"] = pageValues[page]["t"] + values['totalTime']
						content.text:SetText(dataString)
						offy = content.text:GetStringHeight() - 14;
					end			
				end
				if not firstPrint then
					dataString = dataString .. "\n";
					content.text:SetText(dataString)
					offy = content.text:GetStringHeight() - 14;
				end
			end
		end
		contentButtonFrame:Hide();
		detailButtonFrame:Show();
	else
		contentButtonFrame:Show();
		detailButtonFrame:Show();
		local offy = 8;
		for index, instance in pairs(characterSortedInstances) do
			if index >= pageValues[page]["index"] then
				if count > 25 then
					showNext = true
					pageValues[page]["index"] = index;
					break
				end
				data = characterHistory[instance]
				local firstPrint = true;
				for difficulty, values in pairs(data) do
					if filteredDifficulties[difficulty] == true then
						if firstPrint then
							count = count + 1;
							dataString = dataString .. "       " .. instance .. "\n";
							j = j + 1;
							detailButtons[j] = detailButtons[j] or CreateFrame("Button", nil, detailButtonFrame, "UIPanelButtonTemplate");
							------------------------
							-- ElvUI Skin Support --
							------------------------
							if (IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")) then
							  local c;
							  if ElvUI then
								local E, L, V, P, G, DF = unpack(ElvUI);
								c = E;
							  else
								local T, C, L, G = unpack(Tukui);
								c = T;
								c.TexCoords = {.08, .92, .08, .92};
							  end
							  local S = c:GetModule('Skins');
							  S:HandleButton(detailButtons[j]);
							end
							detailButtons[j]:SetPoint("TOPRIGHT", 0, offy * -1);
							detailButtons[j]:SetText("Details");
							detailButtons[j]:SetSize(60, 20);
							detailButtons[j]:SetNormalFontObject("GameFontNormal");
							detailButtons[j]:SetScript("OnClick", function(self, button, down)
								IP_ShowDetails(instance);
							end);
							detailButtons[j].tooltip_text = "View enhanced details of saved data for " .. instance;
							detailButtons[j]:SetScript("OnEnter", IP_TippedButtonOnEnter)
							detailButtons[j]:SetScript("OnLeave", IP_TippedButtonOnLeave)
							detailButtons[j]:Show();
							firstPrint = false;
						end
						i = i + 1;
						contentButtons[i] = contentButtons[i] or CreateFrame("Button", nil, contentButtonFrame, "UIPanelButtonTemplate");
						contentButtons[i]:SetPoint("TOPLEFT", 0, offy * -1);---28 * i + 16 + i * 4);
						contentButtons[i]:SetText("X");
						contentButtons[i]:SetSize(16, 16);
						contentButtons[i]:SetNormalFontObject("GameFontNormal");
						contentButtons[i]:SetScript("OnClick", function(self, button, down)
							StaticPopupDialogs["IP_Confirm_Delete"].OnAccept = function() 
								IP_DeleteInstanceData(instance, difficulty);
								IP_DisplaySavedData(1);
							end
							StaticPopup_Show("IP_Confirm_Delete", instance .. " (" .. difficulty .. ")");
						end);
						contentButtons[i].tooltip_text = "Delete saved data for " .. instance .. " (" .. difficulty .. ") for " .. GetUnitName("player");
						contentButtons[i]:SetScript("OnEnter", IP_TippedButtonOnEnter)
						contentButtons[i]:SetScript("OnLeave", IP_TippedButtonOnLeave)
						contentButtons[i]:Show();
						dataString = dataString .. "              (" .. difficulty .. ") " .. values['count'] .. " | " .. GetMoneyString(values['totalLoot'] + values['totalVendor'] - values['totalRepair']) .. " | " .. timeToSmallString(values['totalTime']) .. "\n";
						pageValues[page]["r"] = pageValues[page]["r"] + values['count']
						pageValues[page]["p"] = pageValues[page]["p"] + values['totalLoot'] + values['totalVendor'] - values['totalRepair']
						pageValues[page]["t"] = pageValues[page]["t"] + values['totalTime']
						content.text:SetText(dataString)
						offy = content.text:GetStringHeight() - 14;
					end
				end
				if not firstPrint then
					dataString = dataString .. "\n";
					content.text:SetText(dataString)
					offy = content.text:GetStringHeight() - 14;
				end
			end
		end
		for k=i+1, table.getn(contentButtons) do
			-- We deleted some instance data, so we have some extra buttons
			contentButtons[k]:Hide();
		end
	end
	for l=j+1, table.getn(detailButtons) do
		-- We deleted some instance data, so we have some extra buttons
		detailButtons[l]:Hide();
	end	
	scrollframe[1]:SetPoint("BOTTOMRIGHT", -10, 45)
	if showNext then
		scrollframe[1]:SetPoint("BOTTOMRIGHT", -10, 75)
		nextPage:SetText("Next Page");
		nextPage:SetPoint("BOTTOMRIGHT", -30, 40);
		nextPage:SetSize(100, 25)
		nextPage:SetScript("OnClick", function(self, button, down)
			IP_DisplaySavedData(page + 1)
		end);
		nextPage:Show()
	else
		dataString = dataString .. "Totals: \n           Runs: " .. pageValues[page]["r"] .. "\n           Profit: " .. GetMoneyString(pageValues[page]["p"]) .. "\n           Time: " .. timeToSmallString(pageValues[page]["t"]) .. "\n\n"
		nextPage:Hide()
	end
	if page > 1 then
		scrollframe[1]:SetPoint("BOTTOMRIGHT", -10, 75)
		prevPage:SetText("Previous Page");
		prevPage:SetPoint("BOTTOMLEFT", 30, 40);
		prevPage:SetSize(100, 25)
		prevPage:SetScript("OnClick", function(self, button, down)
			IP_DisplaySavedData(page - 1)
		end);
		prevPage:Show()
	else
		prevPage:Hide()
	end
	content.text:SetText(dataString)
	IP_MainScroll()
end

function IP_MainScroll()
	local scrollMax = content.text:GetStringHeight();
	local height = InstanceProfits_TableDisplay:GetHeight() - 140;
	if scrollMax > (height) then
		scrollbar[1]:Show();
		scrollMax = scrollMax - height;
	else
		scrollbar[1]:Hide();
		scrollMax = 1;
	end
	scrollbar[1]:SetMinMaxValues(1, scrollMax)
	scrollframe[1]:SetScrollChild(content)
end

function IP_TippedButtonOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(self.tooltip_text, nil, nil, nil, nil, true);
	GameTooltip:Show();
end

function IP_TippedButtonOnLeave()
	GameTooltip:Hide();
end

function IP_ToggleDisplayGlobal()
	displayGlobal = not displayGlobal;
	if (displayGlobal) then
		InstanceProfits_TableDisplay_ButtonToggleData:SetText("Show Character Data");
	else
		InstanceProfits_TableDisplay_ButtonToggleData:SetText("Show Account Data");
	end
	IP_DisplaySavedData(1);
end

function IP_UpdateTime(self, elapsed)
	elapsedTime = elapsedTime + elapsed;
	if (not isInPvEInstance) then
		if startTime > 0 and not enteredAlive then
			-- We were in an instance, but aren't anymore because we died. Don't count time spent dead as time in instance
			if elapsedTime >= 1 then
				elapsedTime = elapsedTime - 1
				startTime = startTime + 1
			end
		else
			elapsedTime = 0;
		end
	elseif (elapsedTime >= 1) then
		if instanceDifficultyName == nil or instanceDifficultyName == "" then
			name, typeOfInstance, instanceDifficulty, instanceDifficultyName, _, _, _, _, _ = GetInstanceInfo();
			liveDifficulty:SetText(instanceDifficultyName);
			triggerInstance(name, instanceDifficulty, instanceDifficultyName, enteredAlive);
		end
		elapsedTime = elapsedTime - 1;
		liveTime:SetText("Time: " .. timeToSmallString(difftime(time(), startTime)));
	end
end

function saveInstanceData()
	local totalTime = difftime(time(), startTime);
	local minTimeSeconds = 0
	if minTimeUnit == "Minutes" then
		minTimeSeconds = minTime*60
	else
		minTimeSeconds = minTime
	end
	if totalTime >= minTimeSeconds then
		local endRepair = IP_CalculateRepairCost();
		characterHistory[instanceName][instanceDifficultyName]['totalTime'] = characterHistory[instanceName][instanceDifficultyName]['totalTime'] + totalTime;
		characterHistory[instanceName][instanceDifficultyName]['totalRepair'] = characterHistory[instanceName][instanceDifficultyName]['totalRepair'] + (endRepair - startRepair);
		characterHistory[instanceName][instanceDifficultyName]['totalLoot'] = characterHistory[instanceName][instanceDifficultyName]['totalLoot'] + lootedMoney;
		characterHistory[instanceName][instanceDifficultyName]['totalVendor'] = characterHistory[instanceName][instanceDifficultyName]['totalVendor'] + vendorMoney;
		globalHistory[instanceName][instanceDifficultyName]['totalTime'] = globalHistory[instanceName][instanceDifficultyName]['totalTime'] + totalTime;
		globalHistory[instanceName][instanceDifficultyName]['totalRepair'] = globalHistory[instanceName][instanceDifficultyName]['totalRepair'] + (endRepair - startRepair);
		globalHistory[instanceName][instanceDifficultyName]['totalLoot'] = globalHistory[instanceName][instanceDifficultyName]['totalLoot'] + lootedMoney;
		globalHistory[instanceName][instanceDifficultyName]['totalVendor'] = globalHistory[instanceName][instanceDifficultyName]['totalVendor'] + vendorMoney;
		if (characterHistory[instanceName][instanceDifficultyName]['fastestRun'] == nil or characterHistory[instanceName][instanceDifficultyName]['fastestRun'] > totalTime) then
			characterHistory[instanceName][instanceDifficultyName]['fastestRun'] = totalTime
		end
		if (characterHistory[instanceName][instanceDifficultyName]['mostLoot'] == nil or characterHistory[instanceName][instanceDifficultyName]['mostLoot'] < lootedMoney) then
			characterHistory[instanceName][instanceDifficultyName]['mostLoot'] = lootedMoney
		end
		if (characterHistory[instanceName][instanceDifficultyName]['mostVendor'] == nil or characterHistory[instanceName][instanceDifficultyName]['mostVendor'] < vendorMoney) then
			characterHistory[instanceName][instanceDifficultyName]['mostVendor'] = vendorMoney
		end
		if (globalHistory[instanceName][instanceDifficultyName]['fastestRun'] == nil or globalHistory[instanceName][instanceDifficultyName]['fastestRun'] > totalTime) then
			globalHistory[instanceName][instanceDifficultyName]['fastestRun'] = totalTime
		end
		if (globalHistory[instanceName][instanceDifficultyName]['mostLoot'] == nil or globalHistory[instanceName][instanceDifficultyName]['mostLoot'] < lootedMoney) then
			globalHistory[instanceName][instanceDifficultyName]['mostLoot'] = lootedMoney
		end
		if (globalHistory[instanceName][instanceDifficultyName]['mostVendor'] == nil or globalHistory[instanceName][instanceDifficultyName]['mostVendor'] < vendorMoney) then
			globalHistory[instanceName][instanceDifficultyName]['mostVendor'] = vendorMoney
		end
		local timeString = math.floor(totalTime/60) .. " minutes and " .. (totalTime % 60) .. " seconds";
		local lootedString = copperToString(lootedMoney);
		local repairString = copperToString(endRepair - startRepair);
		local vendorString = copperToString(vendorMoney);
		local profitString = copperToString(lootedMoney + vendorMoney - (endRepair - startRepair));
		local recentString = "Date: " .. date("%m/%d/%y %H:%M:%S") .. " \nCharacter: " .. GetUnitName("player") .. "\nInstance: " .. instanceName .. " (" .. instanceDifficultyName .. ") \nTime: " .. timeString .. "\nLoot: " .. lootedString .. "\nVendor: " .. vendorString .. "\nRepair: " .. repairString .. "\nProfit: " .. profitString;
		table.insert(recentHistory, recentString);
		if (table.getn(recentHistory) > 10) then
			table.remove(recentHistory, 1);
		end
		print("You have exited your instance after spending " .. timeString .. " inside.");
		print("You earned " .. lootedString .. " from mobs");
		print("and " .. vendorString .. " from looted items that you can vendor.");
		print("Your gear will take " .. repairString .. " to be repaired. This makes your total profit " .. profitString);
		IP_SortData(sortDir);
		IP_DisplaySavedData(1);
	else
		print("This run was shorter than the minimum of " .. minTime .. " " .. minTimeUnit .. " and was not saved.")
	end
end

function IP_ClearCharacterData()
	StaticPopupDialogs["IP_Confirm_Delete_Character"].OnAccept = function() 
		for instance, data in pairs(characterHistory) do
			for difficulty, values in pairs(data) do
				globalHistory[instance][difficulty]['totalTime'] = globalHistory[instance][difficulty]['totalTime'] - values['totalTime'];
				globalHistory[instance][difficulty]['totalRepair'] = globalHistory[instance][difficulty]['totalRepair'] - values['totalRepair'];
				globalHistory[instance][difficulty]['totalLoot'] = globalHistory[instance][difficulty]['totalLoot'] - values['totalLoot'];
				globalHistory[instance][difficulty]['totalVendor'] = globalHistory[instance][difficulty]['totalVendor'] - values['totalVendor'];
				globalHistory[instance][difficulty]['count'] = globalHistory[instance][difficulty]['count'] - values['count'];
				if (globalHistory[instance][difficulty]["count"] == 0) then
					globalHistory[instance][difficulty] = nil;
				end
			end
		end
		characterHistory = {};
		IP_SortData(sortDir);
		IP_DisplaySavedData(1);
	end
	StaticPopup_Show("IP_Confirm_Delete_Character");
end

function IP_ClearRecentData()
	StaticPopupDialogs["IP_Confirm_Delete_Recent"].OnAccept = function() 
		recentHistory = {};
		IP_ShowRecent();
	end
	StaticPopup_Show("IP_Confirm_Delete_Recent");
end

function IP_ShowFilters()
	InstanceProfits_FilterOptions:Show();
	InstanceProfits_FilterOptions:SetFrameStrata("HIGH")
	InstanceProfits_FilterOptions:Raise()
	table.foreach(FILTER_BUTTONS, 
		function(k,v) 
			if filteredDifficulties[k] == true then
				_G[v]:SetChecked(true)
			else
				_G[v]:SetChecked(false)
			end
		end
	)
	if minTimeUnit == "Minutes" then
		_G["InstanceProfits_FilterOptionsMinTimeMinutes"]:SetChecked(true)
		_G["InstanceProfits_FilterOptionsMinTimeSeconds"]:SetChecked(false)
	else
		_G["InstanceProfits_FilterOptionsMinTimeMinutes"]:SetChecked(false)
		_G["InstanceProfits_FilterOptionsMinTimeSeconds"]:SetChecked(true)
	end
	_G["InstanceProfits_FilterOptions_MinTimeValue"]:SetNumber(minTime)
end

function IP_ShowShareDialog(share)
	InstanceProfits_ShareDialog:Show();
	InstanceProfits_ShareDialog:SetFrameStrata("HIGH");
	InstanceProfits_ShareDialog:Raise();
	shareType = share
end

function IP_ShowRecent()
	InstanceProfits_RecentHistory:Show();
	InstanceProfits_RecentHistory:SetFrameStrata("HIGH");
	InstanceProfits_RecentHistory:Raise();
	--UIDropDownMenu_SetSelectedID(InstanceProfits_RecentHistory_LimitDropDown, recentLimit);
	historyContent = historyContent or CreateFrame("Frame", nil, scrollframe[3]);
	historyContent:SetHeight(10000);
	historyContent:SetWidth(550);
	historyDetails = historyDetails or historyContent:CreateFontString(nil, "ARTWORK","NumberFontNormal");
	historyDetails:SetTextColor(textColors['recent']['r'], textColors['recent']['g'], textColors['recent']['b'], textColors['recent']['a'])
	local historyText = "";
	local count = 0;
	for i = table.getn(recentHistory), 1, -1 do
		if (count < recentLimit) then
			historyText = historyText .. "\n\n" .. recentHistory[i];
			count = count + 1;
		end
	end
	historyDetails:SetText(historyText);
	historyDetails:SetPoint("TOPLEFT", 15, 0);
	IP_RecentHistoryScroll();
end

function IP_RecentHistoryScroll()
	local scrollMax = historyDetails:GetStringHeight();
	local height = InstanceProfits_RecentHistory:GetHeight() - 110;
	if scrollMax > (height) then
		scrollbar[3]:Show();
		scrollMax = scrollMax - height;
	else
		scrollbar[3]:Hide();
		scrollMax = 1;
	end
	scrollbar[3]:SetMinMaxValues(1, scrollMax)
	scrollframe[3]:SetScrollChild(historyContent)
end

function IP_Checkbutton_OnLoad(checkbutton, difficultyNum)
	local name = GetDifficultyInfo(difficultyNum);
	FILTER_BUTTONS[name] = checkbutton:GetName();
	_G[checkbutton:GetName() .. "Text"]:SetText(name);
	filteredDifficulties[name] = true
	tempFilters[name] = true
end

function IP_Checkbutton_OnClick(checkbutton)
	local name = _G[checkbutton:GetName() .. "Text"]:GetText();
	if checkbutton:GetChecked() == true then
		tempFilters[name] = true
	else
		tempFilters[name] = false
	end
end

function IP_Radio_OnLoad(radiobutton, name)
	_G[radiobutton:GetName() .. "Text"]:SetText(name)
end

function IP_MinTimeRadio_OnClick(radiobutton)
	local name = _G[radiobutton:GetName() .. "Text"]:GetText();
	if radiobutton:GetChecked() == true then
		if name == "Seconds" then
			_G["InstanceProfits_FilterOptionsMinTimeMinutes"]:SetChecked(false)
		else
			_G["InstanceProfits_FilterOptionsMinTimeSeconds"]:SetChecked(false)
		end
	else
		radiobutton:SetChecked(true)
	end
end

function IP_ShareData()
	local msgtype, tgt = nil
	local msg1 = "Instance Profit Tracker - " .. instanceName .. " " .. instanceDifficultyName
	local msg2 = "Profit of " .. GetCoinText(vendorMoney + lootedMoney) .. " earned in " .. string.sub(liveTime:GetText(), 7)
	if _G["InstanceProfits_ShareDialogSay"]:GetChecked() == true then
		msgtype = "SAY"
	elseif _G["InstanceProfits_ShareDialogGuild"]:GetChecked() == true then
		msgtype = "GUILD"
	elseif _G["InstanceProfits_ShareDialogWhisper"]:GetChecked() == true then
		msgtype = "WHISPER"
		tgt = _G["InstanceProfits_ShareDialogWhisperName"]:GetText()
	elseif _G["InstanceProfits_ShareDialogGeneral"]:GetChecked() == true then
		msgtype = "CHANNEL"
		tgt = 1
	elseif _G["InstanceProfits_ShareDialogTrade"]:GetChecked() == true then
		msgtype = "CHANNEL"
		tgt = 2
	end
	
	if instanceName then
		SendChatMessage(msg1, msgtype, nil, tgt);
		SendChatMessage(msg2, msgtype, nil, tgt);
	end
end

function IP_FilterApply()
	table.foreach(tempFilters, 
		function(k,v) 
			filteredDifficulties[k] = v
		end
	)
	sortDir = tempSortDir;
	minTime = _G["InstanceProfits_FilterOptions_MinTimeValue"]:GetNumber()
	if _G["InstanceProfits_FilterOptionsMinTimeMinutes"]:GetChecked() == true then
		minTimeUnit = "Minutes"
	elseif _G["InstanceProfits_FilterOptionsMinTimeSeconds"]:GetChecked() == true then
		minTimeUnit = "Seconds"
	end
	InstanceProfits_FilterOptions:Hide();
	InstanceProfits_TableDisplay:Show();
	IP_SortData(sortDir)
	IP_DisplaySavedData(1);
end

function IP_FilterCancel()
	table.foreach(filteredDifficulties, 
		function(k,v) 
			tempFilters[k] = v
		end
	)
	if tempSortDir ~= sortDir then
		tempSortDir = sortDir;
		UIDropDownMenu_SetSelectedValue(InstanceProfits_FilterOptions_SortDropDown, sortDir);
	end
	InstanceProfits_FilterOptions:Hide();
end

function IP_SortData(field)
	characterSortedInstances = {}
	globalSortedInstances = {}
	for n in pairs(characterHistory) do table.insert(characterSortedInstances, n) end
	for n in pairs(globalHistory) do table.insert(globalSortedInstances, n) end
	if field == "nameA" then
		table.sort(characterSortedInstances)
		table.sort(globalSortedInstances)
	elseif field == "nameD" then
		table.sort(characterSortedInstances, function(a,b) return a > b end)
		table.sort(globalSortedInstances, function(a,b) return a > b end)
	elseif field == "timeA" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA < timeB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA < timeB;
			end
		)
		elseif field == "timeD" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA > timeB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local timeA = 0
				local timeB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					timeA = timeA + data["totalTime"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					timeB = timeB + data["totalTime"]
				end
				return timeA > timeB;
			end
		)
	elseif field == "profitA" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA < profitB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA < profitB;
			end
		)
	elseif field == "profitD" then 
		table.sort(globalSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(globalHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(globalHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA > profitB;
			end
		)
		table.sort(characterSortedInstances, 
			function(a,b)
				local profitA = 0
				local profitB = 0
				for difficulty, data in pairs(characterHistory[a]) do
					profitA = profitA + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				for difficulty, data in pairs(characterHistory[b]) do
					profitB = profitB + data["totalVendor"] + data["totalLoot"] - data["totalRepair"]
				end
				return profitA > profitB;
			end
		)
	end
end

function IP_BuildSortDropdown()
	local info = UIDropDownMenu_CreateInfo();
	info.text = "Name (Asc)";
	info.value = "nameA";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Name (Desc)";
	info.value = "nameD";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Profit (Asc)";
	info.value = "profitA";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Profit (Desc)";
	info.value = "profitD";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Time (Asc)";
	info.value = "timeA";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
	info = UIDropDownMenu_CreateInfo();
	info.text = "Time (Desc)";
	info.value = "timeD";
	info.func = IP_SortSelect;
	UIDropDownMenu_AddButton(info)
end

function IP_BuildLimitDropdown()
	local info = UIDropDownMenu_CreateInfo();
	info.text = "1";
	info.value = 1;
	info.func = IP_LimitSelect;
	UIDropDownMenu_AddButton(info);
	info = UIDropDownMenu_CreateInfo();
	info.text = "2";
	info.value = 2;
	info.func = IP_LimitSelect;
	UIDropDownMenu_AddButton(info);
	info = UIDropDownMenu_CreateInfo();
	info.text = "3";
	info.value = 3;
	info.func = IP_LimitSelect;
	UIDropDownMenu_AddButton(info);
	info = UIDropDownMenu_CreateInfo();
	info.text = "4";
	info.value = 4;
	info.func = IP_LimitSelect;
	UIDropDownMenu_AddButton(info);
	info = UIDropDownMenu_CreateInfo();
	info.text = "5";
	info.value = 5;
	info.func = IP_LimitSelect;
	UIDropDownMenu_AddButton(info);
	info = UIDropDownMenu_CreateInfo();
	info.text = "6";
	info.value = 6;
	info.func = IP_LimitSelect;
	UIDropDownMenu_AddButton(info);
	info = UIDropDownMenu_CreateInfo();
	info.text = "7";
	info.value = 7;
	info.func = IP_LimitSelect;
	UIDropDownMenu_AddButton(info);
end

function IP_SortSelect(self, arg1, arg2, checked)
	if not checked then
		UIDropDownMenu_SetSelectedValue(InstanceProfits_FilterOptions_SortDropDown, self.value);
		tempSortDir = self.value;
	end
end

function IP_LimitSelect(self, arg1, arg2, checked)
	if not checked then
		UIDropDownMenu_SetSelectedValue(InstanceProfits_RecentHistory_LimitDropDown, self.value);
		recentLimit = self.value;
		IP_ShowRecent();
	end
end

function copperToSmallString(copper) 
	local goldString = "";
	if copper < 0 then
		copper = math.abs(copper);
		goldString = "";
	end
	local gold = math.floor(copper/10000);
	copper = copper - gold * 10000;
	local silver = math.floor(copper/100);
	copper = copper - silver * 100;
	goldString = goldString .. gold .. "|TInterface\\MoneyFrame\\UI-GoldIcon:10:10:0:-7|t" .. silver .. "|TInterface\\MoneyFrame\\UI-SilverIcon:10:10:0:-7|t" .. copper .. "|TInterface\\MoneyFrame\\UI-CopperIcon:10:10:0:-7|t";
	return goldString;
end

function IP_ShowDetails(instanceName)
	detailedContent = detailedContent or CreateFrame("Frame", nil, scrollframe[2]);
	detailedContent:SetHeight(10000);
	detailedContent:SetWidth(550);
	InstanceProfits_DetailedDisplay:Show()
	InstanceProfits_DetailedDisplay:SetFrameStrata("HIGH")
	InstanceProfits_DetailedDisplay:Raise()
	detailedHeader = detailedHeader or InstanceProfits_DetailedDisplay:CreateFontString(nil, "ARTWORK","SystemFont_Huge2");
	charDetails = charDetails or detailedContent:CreateFontString(nil, "ARTWORK","NumberFontNormal");
	acctDetails = acctDetails or detailedContent:CreateFontString(nil, "ARTWORK","NumberFontNormal");
	detailedHeader:SetTextColor(textColors['details']['r'], textColors['details']['g'], textColors['details']['b'], textColors['details']['a'])
	charDetails:SetTextColor(textColors['details']['r'], textColors['details']['g'], textColors['details']['b'], textColors['details']['a'])
	acctDetails:SetTextColor(textColors['details']['r'], textColors['details']['g'], textColors['details']['b'], textColors['details']['a'])
	local charText = GetUnitName("player") .. "\n";
	local acctText = "Account\n";
	local runs, vendor, loot, repair, seconds, difficulties = 0, 0, 0, 0, 0, 0
	if characterHistory[instanceName] ~= nil then
		for difficulty, data in pairs(characterHistory[instanceName]) do
			if difficulty ~= "" then
				charText = charText .. "\n";
				difficulties = difficulties + 1
				runs = runs + data["count"]
				vendor = vendor + data["totalVendor"]
				loot = loot + data["totalLoot"]
				repair = repair + data["totalRepair"]
				seconds = seconds + data["totalTime"]
				charText = charText .. difficulty .. "\n" ..  data["count"] .. " runs in " .. math.floor(data["totalTime"]/60) .. " minutes and " .. (data["totalTime"] % 60) .. " seconds\n";
				charText = charText .. "Vendor Price of Items: " .. copperToSmallString(data["totalVendor"]) .. "\n";
				charText = charText .. "Gold Looted: " .. copperToSmallString(data["totalLoot"]) .. "\n";
				charText = charText .. "Cost to Repair: " .. copperToSmallString(data["totalRepair"]) .. "\n";
				charText = charText .. "Average Profit per Run: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/data["count"])) .. "\n";
				charText = charText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/(data["totalTime"]/3600))) .. "\n";
			end
		end
		if difficulties > 1 then
			charText = charText .. "\nGrand Total\n" ..  runs .. " runs in " .. math.floor(seconds/60) .. " minutes and " .. (seconds % 60) .. " seconds\n";
			charText = charText .. "Vendor Price of Items: " .. copperToSmallString(vendor) .. "\n";
			charText = charText .. "Gold Looted: " .. copperToSmallString(loot) .. "\n";
			charText = charText .. "Cost to Repair: " .. copperToSmallString(repair) .. "\n";
			charText = charText .. "Average Profit per Run: " .. copperToSmallString(math.floor((vendor + loot - repair)/runs)) .. "\n";
			charText = charText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((vendor + loot - repair)/(seconds/3600))) .. "\n";
		end
	end
	runs, vendor, loot, repair, seconds, difficulties = 0, 0, 0, 0, 0, 0
	if globalHistory[instanceName] ~= nil then
		for difficulty, data in pairs(globalHistory[instanceName]) do
			if difficulty ~= "" then
			acctText = acctText .. "\n";
			difficulties = difficulties + 1
			runs = runs + data["count"]
			vendor = vendor + data["totalVendor"]
			loot = loot + data["totalLoot"]
			repair = repair + data["totalRepair"]
			seconds = seconds + data["totalTime"]
			acctText = acctText .. difficulty .. "\n" ..  data["count"] .. " runs in " .. math.floor(data["totalTime"]/60) .. " minutes and " .. (data["totalTime"] % 60) .. " seconds\n";
			acctText = acctText .. "Vendor Price of Items: " .. copperToSmallString(data["totalVendor"]) .. "\n";
			acctText = acctText .. "Gold Looted: " .. copperToSmallString(data["totalLoot"]) .. "\n";
			acctText = acctText .. "Cost to Repair: " .. copperToSmallString(data["totalRepair"]) .. "\n";
			acctText = acctText .. "Average Profit per Run: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/data["count"])) .. "\n";
			acctText = acctText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((data["totalVendor"] + data["totalLoot"] - data["totalRepair"])/(data["totalTime"]/3600))) .. "\n";
			end
		end
		if difficulties > 1 then
			acctText = acctText .. "\nGrand Total\n" ..  runs .. " runs in " .. math.floor(seconds/60) .. " minutes and " .. (seconds % 60) .. " seconds\n";
			acctText = acctText .. "Vendor Price of Items: " .. copperToSmallString(vendor) .. "\n";
			acctText = acctText .. "Gold Looted: " .. copperToSmallString(loot) .. "\n";
			acctText = acctText .. "Cost to Repair: " .. copperToSmallString(repair) .. "\n";
			acctText = acctText .. "Average Profit per Run: " .. copperToSmallString(math.floor((vendor + loot - repair)/runs)) .. "\n";
			acctText = acctText .. "Average Profit per Hour: " .. copperToSmallString(math.floor((vendor + loot - repair)/(seconds/3600))) .. "\n";
		end
	end
	detailedHeader:SetText(instanceName);
	charDetails:SetText(charText);
	acctDetails:SetText(acctText);
	local ofsy = -30;
	detailedHeader:SetPoint("TOP", 0, ofsy);
	ofsy = ofsy - detailedHeader:GetStringHeight();
	charDetails:SetPoint("TOPLEFT", 15, 0);
	acctDetails:SetPoint("TOPRIGHT", -15, 0);
	IP_DetailsScroll()
end

function IP_DetailsScroll()
	local scrollMax = acctDetails:GetStringHeight() + detailedHeader:GetStringHeight();
	local height = InstanceProfits_DetailedDisplay:GetHeight() - 110;
	if scrollMax > (height) then
		scrollbar[2]:Show();
		scrollMax = scrollMax - height;
	else
		scrollbar[2]:Hide();
		scrollMax = 1;
	end
	scrollbar[2]:SetMinMaxValues(1, scrollMax)
	scrollframe[2]:SetScrollChild(detailedContent)
end

function IP_InitScrollFrames()
	local scrollableFrames = {"InstanceProfits_TableDisplay", "InstanceProfits_DetailedDisplay", "InstanceProfits_RecentHistory"}
	for i, frameName in pairs(scrollableFrames) do
		--scrollframe
		scrollframe[i] = CreateFrame("ScrollFrame", nil, _G[frameName])
		scrollframe[i]:SetPoint("TOPLEFT", 10, -60)
		scrollframe[i]:SetPoint("BOTTOMRIGHT", -10, 45)
		scrollframe[i]:SetSize(500, 650)
		scrollframe[i]:EnableMouseWheel(true)

		--scrollbar
		scrollbar[i] = CreateFrame("Slider", nil, scrollframe[i], "UIPanelScrollBarTemplate")
		scrollbar[i]:SetPoint("TOPLEFT", _G[frameName], "TOPRIGHT", 4, -16)
		scrollbar[i]:SetPoint("BOTTOMLEFT", _G[frameName], "BOTTOMRIGHT", 4, 16)
		scrollbar[i]:SetMinMaxValues(1, 200)
		scrollbar[i]:SetValueStep(1)
		scrollbar[i].scrollStep = 1
		scrollbar[i]:SetValue(0)
		scrollbar[i]:SetWidth(16)
		scrollbar[i]:SetScript("OnValueChanged",
			function (self, value)
				self:GetParent():SetVerticalScroll(value)
			end
		)
		local scrollbg = scrollbar[i]:CreateTexture(nil, "BACKGROUND")
		scrollbg:SetAllPoints(scrollbar[i])
		scrollbg:SetTexture(0, 0, 0, 0.4)
		scrollframe[i]:SetScript("OnMouseWheel", function(self, delta)
			local current = scrollbar[i]:GetValue()

			if IsShiftKeyDown() and (delta > 0) then
			  scrollbar[i]:SetValue(0)
			elseif IsShiftKeyDown() and (delta < 0) then
			  scrollbar[i]:SetValue(200)
			elseif (delta < 0) then
			  scrollbar[i]:SetValue(current + 20)
			elseif (delta > 0) and (current > 1) then
			  scrollbar[i]:SetValue(current - 20)
			end
		end)
	end
end

function ShowColorPicker(r, g, b, a, changedCallback)
	ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = 
	changedCallback, changedCallback, changedCallback;
	ColorPickerFrame:SetColorRGB(r,g,b);
	ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = (a ~= nil), a;
	ColorPickerFrame.previousValues = {r,g,b,a};
	ColorPickerFrame:Hide(); -- Need to run the OnShow handler.
	ColorPickerFrame:Show();
end

local function mainColorCallback(restore)
 local newR, newG, newB, newA;
 if restore then
  -- The user bailed, we extract the old color from the table created by ShowColorPicker.
	newR, newG, newB, newA = unpack(restore);
 else
  -- Something changed
	newA, newR, newG, newB = OpacitySliderFrame:GetValue(), ColorPickerFrame:GetColorRGB();
 end
 
 -- Update our internal storage.
 textColors["main"]["r"] = newR;
 textColors["main"]["g"] = newG;
 textColors["main"]["b"] = newB;
 textColors["main"]["a"] = newA;
 
 content.text:SetTextColor(textColors['main']['r'], textColors['main']['g'], textColors['main']['b'], textColors['main']['a'])
end

local function detailsColorCallback(restore)
 local newR, newG, newB, newA;
 if restore then
  -- The user bailed, we extract the old color from the table created by ShowColorPicker.
	newR, newG, newB, newA = unpack(restore);
 else
  -- Something changed
	newA, newR, newG, newB = OpacitySliderFrame:GetValue(), ColorPickerFrame:GetColorRGB();
 end
 
 -- Update our internal storage.
 textColors["details"]["r"] = newR;
 textColors["details"]["g"] = newG;
 textColors["details"]["b"] = newB;
 textColors["details"]["a"] = newA;
 -- And update any UI elements that use this color...
	detailedHeader:SetTextColor(textColors['details']['r'], textColors['details']['g'], textColors['details']['b'], textColors['details']['a'])
	charDetails:SetTextColor(textColors['details']['r'], textColors['details']['g'], textColors['details']['b'], textColors['details']['a'])
	acctDetails:SetTextColor(textColors['details']['r'], textColors['details']['g'], textColors['details']['b'], textColors['details']['a'])
end

local function recentColorCallback(restore)
 local newR, newG, newB, newA;
 if restore then
  -- The user bailed, we extract the old color from the table created by ShowColorPicker.
	newR, newG, newB, newA = unpack(restore);
 else
  -- Something changed
	newA, newR, newG, newB = OpacitySliderFrame:GetValue(), ColorPickerFrame:GetColorRGB();
 end
 
 -- Update our internal storage.
 textColors["recent"]["r"] = newR;
 textColors["recent"]["g"] = newG;
 textColors["recent"]["b"] = newB;
 textColors["recent"]["a"] = newA;
 -- And update any UI elements that use this color...
historyDetails:SetTextColor(textColors['recent']['r'], textColors['recent']['g'], textColors['recent']['b'], textColors['recent']['a'])
end

function IP_MainTextColor()
	ShowColorPicker(textColors['main']['r'], textColors['main']['g'], textColors['main']['b'], textColors['main']['a'], mainColorCallback);
end

function IP_DetailsTextColor()
	ShowColorPicker(textColors['details']['r'], textColors['details']['g'], textColors['details']['b'], textColors['details']['a'], detailsColorCallback);
end

function IP_RecentTextColor()
	ShowColorPicker(textColors['recent']['r'], textColors['recent']['g'], textColors['recent']['b'], textColors['recent']['a'], recentColorCallback);
end

function eventHandler(self, event, ...)
	local arg1, arg2 = ...
	if event == "ADDON_LOADED" and arg1 == "InstanceProfits" then
		------------------------
		-- ElvUI Skin Support --
		------------------------
		if (IsAddOnLoaded("ElvUI") or IsAddOnLoaded("Tukui")) then
		  local c;
		  if ElvUI then
			local E, L, V, P, G, DF = unpack(ElvUI);
			c = E;
		  else
			local T, C, L, G = unpack(Tukui);
			c = T;
			c.TexCoords = {.08, .92, .08, .92};
		  end
		  local S = c:GetModule('Skins');
		  
		  -- Skin the InstanceProfits_LiveDisplay Frame and all Buttons
		  InstanceProfits_LiveDisplay:SetHeight(90);
		  InstanceProfits_LiveDisplay_ButtonClose:ClearAllPoints();
		  InstanceProfits_LiveDisplay_ButtonClose:SetPoint("TOPRIGHT", InstanceProfits_LiveDisplay, "TOPRIGHT", -5, -5);
		  InstanceProfits_LiveDisplay_ButtonDetails:ClearAllPoints();
		  InstanceProfits_LiveDisplay_ButtonDetails:SetPoint("TOPRIGHT", InstanceProfits_LiveDisplay, "TOPRIGHT", -5, -25);
		  InstanceProfits_LiveDisplay_ButtonDetails:SetWidth(16)
		  InstanceProfits_LiveDisplay_ButtonDetails:SetHeight(16)
		  InstanceProfits_LiveDisplay_ButtonDetails.Text:SetText("H")
		  InstanceProfits_LiveDisplay_ButtonRecent:ClearAllPoints();
		  InstanceProfits_LiveDisplay_ButtonRecent:SetPoint("TOPRIGHT", InstanceProfits_LiveDisplay, "TOPRIGHT", -5, -45);
		  InstanceProfits_LiveDisplay_ButtonRecent:SetWidth(16)
		  InstanceProfits_LiveDisplay_ButtonRecent:SetHeight(16)
		  InstanceProfits_LiveDisplay_ButtonRecent.Text:SetText("R")
		  InstanceProfits_LiveDisplay:StripTextures(true);
		  InstanceProfits_LiveDisplay:CreateBackdrop("Transparent");
		  S:HandleButton(InstanceProfits_LiveDisplay_ButtonClose);
		  S:HandleButton(InstanceProfits_LiveDisplay_ButtonDetails);
		  S:HandleButton(InstanceProfits_LiveDisplay_ButtonRecent);
		  
		  -- Skin the InstanceProfits_TableDisplay Frame, all Buttons and the Scroll Bar
		  InstanceProfits_TableDisplay:StripTextures(true);
		  InstanceProfits_TableDisplay:CreateBackdrop("Transparent");
		  S:HandleButton(InstanceProfits_TableDisplay_TitleBar_ButtonClose);
		  InstanceProfits_TableDisplay_TitleBar:SetBackdropColor(128/255, 128/255, 128/255, 0.75);
		  InstanceProfits_TableDisplay_TitleBar_TitleString:SetTextColor(1, 1, 1);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonToggleData);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonRecent);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonClose);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonFilter);
		  S:HandleButton(InstanceProfits_TableDisplay_ButtonResetChar);
		  
		  -- Skin the InstanceProfits_FilterOptions Frame and all Buttons
		  InstanceProfits_FilterOptions:StripTextures(true);
		  InstanceProfits_FilterOptions:CreateBackdrop("Transparent");
		  InstanceProfits_FilterOptions_TitleBar:SetBackdropColor(128/255, 128/255, 128/255, 0.75);
		  InstanceProfits_FilterOptions_TitleBar_TitleString:SetTextColor(1, 1, 1);
		  S:HandleButton(InstanceProfits_FilterOptions_TitleBar_ButtonClose);
		  S:HandleButton(InstanceProfits_FilterOptions_ButtonSave);
		  S:HandleDropDownBox(InstanceProfits_FilterOptions_SortDropDown);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsNormalFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsHeroicFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTenManFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTwentyFiveFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTenHeroicFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsTwentyFiveHeroicFilter);
		  S:HandleCheckBox(InstanceProfits_FilterOptionsLFRFilter);
		  
		  -- Skin the InstanceProfits_DetailedDisplay Frame and all Buttons
		  InstanceProfits_DetailedDisplay:StripTextures(true);
		  InstanceProfits_DetailedDisplay:CreateBackdrop("Transparent");
		  S:HandleButton(InstanceProfits_DetailedDisplay_ButtonClose);
		  
		  -- Skin the InstanceProfits_RecentHistory Frame and all Buttons
		  InstanceProfits_RecentHistory:StripTextures(true);
		  InstanceProfits_RecentHistory:CreateBackdrop("Transparent");
		  InstanceProfits_RecentHistory_TitleBar:SetBackdropColor(128/255, 128/255, 128/255, 0.75);
		  InstanceProfits_RecentHistory_TitleBar_TitleString:SetTextColor(1, 1, 1);
		  S:HandleButton(InstanceProfits_RecentHistory_TitleBar_ButtonClose);
		  S:HandleDropDownBox(InstanceProfits_RecentHistory_LimitDropDown);
		  
		end
		instanceName = "|cFFFF0000Not in instance|r";
		instanceDifficultyName = instanceName;
		InstanceProfits_TableDisplay:Hide();
		InstanceProfits_LiveDisplay:Hide();
		InstanceProfits_FilterOptions:Hide();
		InstanceProfits_DetailedDisplay:Hide();
		InstanceProfits_RecentHistory:Hide();
		InstanceProfits_ShareDialog:Hide();

		characterHistory = _G["IP_InstanceRunsCharacterHistory"] or {};
		globalHistory = _G["IP_InstanceRunsGlobalHistory"] or {};
		recentHistory = _G["IP_RecentHistory"] or {};
		recentLimit = _G["IP_RecentLimit"] or 5;
		filteredDifficulties = _G["IP_DifficultyFilters"] or filteredDifficulties;
		textColors = _G["IP_TextColors"] or {};
		minTime = _G["IP_MinTime"] or 30;
		minTimeUnit = _G["IP_MinTimeUnit"] or "Seconds";
		if textColors['main'] == nil then
			textColors['main'] = {};
			textColors["main"]["r"] = 0;
			textColors["main"]["g"] = .8;
			textColors["main"]["b"] = 1;
			textColors["main"]["a"] = 1;
		end
		if textColors['details'] == nil then
			textColors["details"] = {};
			textColors["details"]["r"] = 1;
			textColors["details"]["g"] = 1;
			textColors["details"]["b"] = 1;
			textColors["details"]["a"] = 1;
		end
		if textColors['recent'] == nil then
			textColors['recent'] = {};
			textColors["recent"]["r"] = 1;
			textColors["recent"]["g"] = 1;
			textColors["recent"]["b"] = 1;
			textColors["recent"]["a"] = 1;
		end

		IP_PrintWelcomeMessage();
		IP_InitScrollFrames();
		
		IP_SortData("nameA")
		StaticPopupDialogs["IP_Confirm_Delete"] = {
			text = "Are you sure you want to delete all data for %s? This action cannot be undone.",
			button1 = "Yes",
			button2 = "No",
			OnAccept = function() end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3
		}
		
		StaticPopupDialogs["IP_Confirm_Delete_Recent"] = {
			text = "Are you sure you want to delete all recent runs? This will NOT delete any of the aggregate data for this character, it will only reset the list of recent instances. This action cannot be undone.",
			button1 = "Yes",
			button2 = "No",
			OnAccept = function() end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3
		}
		
		StaticPopupDialogs["IP_Confirm_Delete_Character"] = {
			text = "Are you sure you want to delete all data for this character? This action cannot be undone.",
			button1 = "Yes",
			button2 = "No",
			OnAccept = function() end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3
		}

		InstanceProfits_RecentHistory_LimitDropDown.selectedName = recentLimit;
		InstanceProfits_RecentHistory_LimitDropDown.selectedValue = recentLimit;
		UIDropDownMenu_SetSelectedID(InstanceProfits_RecentHistory_LimitDropDown, recentLimit);		
		UIDropDownMenu_SetWidth(InstanceProfits_RecentHistory_LimitDropDown, 60);	

		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		local inInstance, instanceType = IsInInstance()
		local wasInPvEInstance = isInPvEInstance
		isInPvEInstance = inInstance and (instanceType == "party" or instanceType == "raid")

		if isInPvEInstance then -- entered instance
			local name, typeOfInstance, difficulty, difficultyName, _, _, _, instanceMapId = GetInstanceInfo()

			if not IGNORED_ZONES[instanceMapId] then
				triggerInstance(name, difficulty, difficultyName, enteredAlive);
			end
			enteredAlive = true
		else -- entered something else
			if wasInPvEInstance ~= isInPvEInstance then -- we actually left instance
				enteredAlive = not UnitIsDeadOrGhost("player"); -- Check if we were a ghost when exiting
				if enteredAlive then
					saveInstanceData();
				end
			end
		end
	elseif event == "CHAT_MSG_LOOT" and isInPvEInstance then
		local itemLink, quantity = strmatch(arg1, LOOT_ITEM_MULTIPLE_PATTERN)
		if not itemLink then
			itemLink, quantity = strmatch(arg1, LOOT_ITEM_PUSHED_MULTIPLE_PATTERN)
			if not itemLink then
				quantity, itemLink = 1, strmatch(arg1, LOOT_ITEM_PATTERN)
				if not itemLink then
					quantity, itemLink = 1, strmatch(arg1, LOOT_ITEM_PUSHED_PATTERN)
					if not itemLink then
						quantity, itemLink = 1, strmatch(arg1, LOOT_ITEM_BONUS)
						if not itemLink then
							itemLink, quantity = strmatch(arg1, LOOT_ITEM_MULTIPLE_BONUS)
							if not itemLink then
								return
							end
						end	
					end
				end
			end
		end

		quantity = tonumber(quantity or 1)
		local name, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemLink)

		if name then
			vendorMoney = vendorMoney + (vendorPrice * quantity)
		else
			lootableItems[name] = (lootableItems[name] or 0) + quantity;
		end

		liveVendor:SetText("Vendor: " .. GetMoneyString(vendorMoney))
	elseif event == "GET_ITEM_INFO_RECEIVED" and isInPvEInstance and arg1 > 0 then
		local name, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(arg1);
		if name and vendorPrice then
			vendorMoney = vendorMoney + (vendorPrice * (lootableItems[name] or 0));
			lootableItems[name] = 0;
		else
			print("Error loading item ID " .. arg1);
		end
		liveVendor:SetText("Vendor: " .. GetMoneyString(vendorMoney))
	elseif event == "CHAT_MSG_MONEY" and isInPvEInstance then
		local goldPattern = GOLD_AMOUNT:gsub('%%d', '(%%d*)')
		local silverPattern = SILVER_AMOUNT:gsub('%%d', '(%%d*)')
		local copperPattern = COPPER_AMOUNT:gsub('%%d', '(%%d*)')
		local gold = tonumber(string.match(arg1, goldPattern) or 0)
		local silver = tonumber(string.match(arg1, silverPattern) or 0)
		local copper = tonumber(string.match(arg1, copperPattern) or 0)
		lootedMoney = lootedMoney + (gold * 100 * 100) + (silver * 100) + copper
		liveLoot:SetText("Looted: " .. GetMoneyString(lootedMoney));
	elseif event == "PLAYER_LOGOUT" then
		if isInPvEInstance or not enteredAlive then
			saveInstanceData();
		end
		_G["IP_InstanceRunsCharacterHistory"] = characterHistory;
		_G["IP_InstanceRunsGlobalHistory"] = globalHistory;
		_G["IP_DifficultyFilters"] = filteredDifficulties;
		_G["IP_RecentHistory"] = recentHistory;
		_G["IP_RecentLimit"] = recentLimit;
		_G["IP_TextColors"] = textColors;
		_G["IP_MinTime"] = minTime;
		_G["IP_MinTimeUnit"] = minTimeUnit;
	end
end
frame:SetScript("OnEvent", eventHandler);

SLASH_INSTANCEPROFITS1, SLASH_INSTANCEPROFITS2, SLASH_INSTANCEPROFITS3 = '/ip', '/instanceprofit', '/instanceprofits';
function SlashCmdList.INSTANCEPROFITS(msg, editbox)
	if msg == 'live' then
		IP_ShowLiveTracker();
	else
		InstanceProfits_TableDisplay:Show();
		IP_DisplaySavedData(1);
	end
end
