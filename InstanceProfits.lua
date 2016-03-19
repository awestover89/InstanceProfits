-- Fix bug with total calculation on global history page
-- Onyxia Lair not showing difficulty
-- TODO: Fix when logging in/out/reloading in an instance
-- TODO: Add a expanded detail pane
-- TODO: Check for player repairing inside dungeon
-- TODO: OPT: Allow sorting of displayed run data
-- TODO: OPT: Fix for only items actually looted to handle groups
-- TODO: OPT: Add Auction Value option

---------
-- new --
---------
local strmatch, strgsub = string.match, string.gsub

local isInPvEInstance = false
local currentCopperAmount

local IGNORED_ZONES = { [1152]=true, [1330]=true, [1153]=true, [1154]=true, [1158]=true, [1331]=true, [1159]=true, [1160]=true };
local LOOT_ITEM_PATTERN = strgsub(LOOT_ITEM_SELF, "%%s", "(.+)")
local LOOT_ITEM_MULTIPLE_PATTERN = strgsub(strgsub(LOOT_ITEM_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)")
local LOOT_ITEM_PUSHED_PATTERN = strgsub(LOOT_ITEM_PUSHED_SELF, "%%s", "(.+)")
local LOOT_ITEM_PUSHED_MULTIPLE_PATTERN = strgsub(strgsub(LOOT_ITEM_PUSHED_SELF_MULTIPLE, "%%s", "(.+)"), "%%d", "(%%d+)")

---------
-- old --
---------

local enteredAlive = true; -- need to change it, cuz it's always true, you can't enter whilst dead
instanceName, instanceDifficulty, instanceDifficultyName, startTime, startRepair = nil, nil, nil, 0, 0;
characterHistory, globalHistory, contentButtons = {}, {}, {};
content = nil;
contentButtonFrame = nil;
displayGlobal = false;
repairTooltip = nil;
liveName = nil;
liveDifficulty = nil;
liveTime = nil;
liveLoot = nil;
liveVendor = nil;
local lootableItems = {};
local elapsedTime, lootedMoney, vendorMoney = 0, 0, 0;
local version = "0.3.1";

local frame = CreateFrame("FRAME", "InstanceProfitsFrame");
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
frame:RegisterEvent("PLAYER_ENTERING_WORLD");
frame:RegisterEvent("ADDON_LOADED");
frame:RegisterEvent("PLAYER_LOGIN");
frame:RegisterEvent("PLAYER_LOGOUT");
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED");

-- loot
frame:RegisterEvent("PLAYER_MONEY");
frame:RegisterEvent("CHAT_MSG_LOOT");

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
	local saved = false;
	for i=1, n do
		local savedName, saveId, resets, difficulty, locked = GetSavedInstanceInfo(i);
		if (savedName == instanceName and locked) then
			saved = true;
		end
	end
	if (not saved and incCount) then
		if (characterHistory[name] == nil) then
			characterHistory[name] = {
				[instanceDifficultyName] = {
					['count'] = 1,
					['totalTime'] = 0,
					['totalRepair'] = 0,
					['totalLoot'] = 0,
					['totalVendor'] = 0
				}
			};
		elseif (characterHistory[name][instanceDifficultyName] == nil) then
			characterHistory[name][instanceDifficultyName] = {
				['count'] = 1,
				['totalTime'] = 0,
				['totalRepair'] = 0,
				['totalLoot'] = 0,
				['totalVendor'] = 0
			};
		else
			characterHistory[name][instanceDifficultyName]['count'] = characterHistory[name][instanceDifficultyName]['count'] + 1;
		end
		if (globalHistory[name] == nil) then
			globalHistory[name] = {
				[instanceDifficultyName] = {
					['count'] = 1,
					['totalTime'] = 0,
					['totalRepair'] = 0,
					['totalLoot'] = 0,
					['totalVendor'] = 0
				}
			};
		elseif (globalHistory[name][instanceDifficultyName] == nil) then
			globalHistory[name][instanceDifficultyName] = {
				['count'] = 1,
				['totalTime'] = 0,
				['totalRepair'] = 0,
				['totalLoot'] = 0,
				['totalVendor'] = 0
			};
		else
			globalHistory[name][instanceDifficultyName]['count'] = globalHistory[name][instanceDifficultyName]['count'] + 1;
		end
	end
	IP_ShowLiveTracker();
	print("You have entered the " .. difficultyName .. " version of " .. name);
	print("You have recorded your profits for this instance " .. characterHistory[name][instanceDifficultyName]['count'] .. " times on this character.");
	print("You have recorded your profits for this instance " .. globalHistory[name][instanceDifficultyName]['count'] .. " times on this account.");
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

function IP_DisplaySavedData()
	content = content or CreateFrame("Frame", nil, scrollframe);
	contentButtonFrame = contentButtonFrame or CreateFrame("Frame", nil, content);
	contentButtonFrame:SetAllPoints(true);
	contentButtonFrame:SetWidth(20);
	content.text = content.text or content:CreateFontString(nil,"ARTWORK","SystemFont_Med1")
	content:SetHeight(10000);
	content:SetWidth(450);
	content.text:SetAllPoints(true)
	content.text:SetJustifyH("LEFT")
	content.text:SetJustifyV("TOP")
	content.text:SetTextColor(0,.8,1,1)
	local dataString = "\n";
	local i = 0;
	local r, p, t = 0, 0, 0;
	if displayGlobal then
		for instance, data in pairs(globalHistory) do
			for difficulty, values in pairs(data) do
				dataString = dataString .. instance .. " (" .. difficulty .. ") | " .. values['count'] .. " | " .. GetMoneyString(values['totalLoot'] + values['totalVendor'] - values['totalRepair']) .. " | " .. timeToSmallString(values['totalTime']) .. "\n\n";
			end
		end
		contentButtonFrame:Hide();
	else
		contentButtonFrame:Show();
		local offy = 8;
		for instance, data in pairs(characterHistory) do
			for difficulty, values in pairs(data) do
				i = i + 1;
				contentButtons[i] = contentButtons[i] or CreateFrame("Button", nil, contentButtonFrame, "UIPanelButtonTemplate");
				contentButtons[i]:SetPoint("TOPRIGHT", 0, offy * -1);---28 * i + 16 + i * 4);
				contentButtons[i]:SetText("X");
				contentButtons[i]:SetSize(16, 16);
				contentButtons[i]:SetNormalFontObject("GameFontNormal");
				contentButtons[i]:SetScript("OnClick", function(self, button, down)
					IP_DeleteInstanceData(instance, difficulty);
					IP_DisplaySavedData();
				end);
				dataString = dataString .. instance .. " (" .. difficulty .. ") \n           " .. values['count'] .. " | " .. GetMoneyString(values['totalLoot'] + values['totalVendor'] - values['totalRepair']) .. " | " .. timeToSmallString(values['totalTime']) .. "\n\n";
				r = r + values['count']
				p = p + values['totalLoot'] + values['totalVendor'] - values['totalRepair']
				t = t + values['totalTime']
				content.text:SetText(dataString)
				offy = content.text:GetStringHeight() - 14;
			end
		end
		for j=i+1, table.getn(contentButtons) do
			-- We deleted some instance data, so we have some extra buttons
			contentButtons[j]:Hide();
		end
	end
	dataString = dataString .. "Totals: \n           Runs: " .. r .. "\n           Profit: " .. GetMoneyString(p) .. "\n           Time: " .. timeToSmallString(t) .. "\n\n"
	content.text:SetText(dataString)
	local scrollMax = content.text:GetStringHeight();
	if scrollMax > 613 then
		scrollbar:Show();
		scrollMax = scrollMax - 612;
	else
		scrollbar:Hide();
		scrollMax = 1;
	end
	scrollbar:SetMinMaxValues(1, scrollMax)
	scrollframe:SetScrollChild(content)
end

function IP_ToggleDisplayGlobal()
	displayGlobal = not displayGlobal;
	if (displayGlobal) then
		InstanceProfits_TableDisplay_ButtonToggleData:SetText("Show Character Data");
	else
		InstanceProfits_TableDisplay_ButtonToggleData:SetText("Show Account Data");
	end
	IP_DisplaySavedData();
end

function IP_UpdateTime(self, elapsed)
	elapsedTime = elapsedTime + elapsed;
	if (not isInPvEInstance) then
		elapsedTime = 0;
	elseif (elapsedTime >= 1) then
		if instanceDifficultyName == nil or instanceDifficultyName == "" then
			print("NIL DIFF");
			name, typeOfInstance, instanceDifficulty, instanceDifficultyName, _, _, _, _, _ = GetInstanceInfo();
			liveDifficulty:SetText(instanceDifficultyName);
			triggerInstance(name, instanceDifficulty, instanceDifficultyName, true);
		end
		elapsedTime = 0;
		if not enteredAlive then -- never happens
			startTime = startTime + 1
		end
		liveTime:SetText("Time: " .. timeToSmallString(difftime(time(), startTime)));
	end
end

function saveInstanceData()
	local totalTime = difftime(time(), startTime);
	local endRepair = IP_CalculateRepairCost();
	print(instanceName);
	print(instanceDifficultyName);
	print(characterHistory[instanceName][instanceDifficultyName])
	characterHistory[instanceName][instanceDifficultyName]['totalTime'] = characterHistory[instanceName][instanceDifficultyName]['totalTime'] + totalTime;
	characterHistory[instanceName][instanceDifficultyName]['totalRepair'] = characterHistory[instanceName][instanceDifficultyName]['totalRepair'] + (endRepair - startRepair);
	characterHistory[instanceName][instanceDifficultyName]['totalLoot'] = characterHistory[instanceName][instanceDifficultyName]['totalLoot'] + lootedMoney;
	characterHistory[instanceName][instanceDifficultyName]['totalVendor'] = characterHistory[instanceName][instanceDifficultyName]['totalVendor'] + vendorMoney;
	globalHistory[instanceName][instanceDifficultyName]['totalTime'] = globalHistory[instanceName][instanceDifficultyName]['totalTime'] + totalTime;
	globalHistory[instanceName][instanceDifficultyName]['totalRepair'] = globalHistory[instanceName][instanceDifficultyName]['totalRepair'] + (endRepair - startRepair);
	globalHistory[instanceName][instanceDifficultyName]['totalLoot'] = globalHistory[instanceName][instanceDifficultyName]['totalLoot'] + lootedMoney;
	globalHistory[instanceName][instanceDifficultyName]['totalVendor'] = globalHistory[instanceName][instanceDifficultyName]['totalVendor'] + vendorMoney;
	local timeString = math.floor(totalTime/60) .. " minutes and " .. (totalTime % 60) .. " seconds";
	local lootedString = copperToString(lootedMoney);
	print("You have exited your instance after spending " .. timeString .. " inside.");
	print("You earned " .. lootedString .. " from mobs");
	print("and " .. copperToString(vendorMoney) .. " from looted items that you can vendor.");
	print("Your gear will take " .. copperToString(endRepair - startRepair) .. " to be repaired. This makes your total profit " .. copperToString(lootedMoney + vendorMoney - (endRepair - startRepair)));
	IP_DisplaySavedData();
end

function IP_ClearCharacterData()
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
	IP_DisplaySavedData();
end

--function IP_ClearAllData()
	--globalHistory = {};
	--characterHistory = {};
	--IP_DisplaySavedData();
--end

function eventHandler(self, event, ...)
	local arg1, arg2 = ...
	if event == "ADDON_LOADED" and arg1 == "InstanceProfits" then
		instanceName = "|cFFFF0000Not in instance|r";
		instanceDifficultyName = instanceName;
		InstanceProfits_TableDisplay:Hide();
		InstanceProfits_LiveDisplay:Hide();

		characterHistory = _G["IP_InstanceRunsCharacterHistory"] or {};
		globalHistory = _G["IP_InstanceRunsGlobalHistory"] or {};

		IP_PrintWelcomeMessage();
		--scrollframe
		scrollframe = CreateFrame("ScrollFrame", nil, InstanceProfits_TableDisplay)
		scrollframe:SetPoint("TOPLEFT", 10, -60)
		scrollframe:SetPoint("BOTTOMRIGHT", -10, 45)
		scrollframe:SetSize(500, 550)
		InstanceProfits_TableDisplay.scrollframe = scrollframe

		--scrollbar
		scrollbar = CreateFrame("Slider", nil, scrollframe, "UIPanelScrollBarTemplate")
		scrollbar:SetPoint("TOPLEFT", InstanceProfits_TableDisplay, "TOPRIGHT", 4, -16)
		scrollbar:SetPoint("BOTTOMLEFT", InstanceProfits_TableDisplay, "BOTTOMRIGHT", 4, 16)
		scrollbar:SetMinMaxValues(1, 200)
		scrollbar:SetValueStep(1)
		scrollbar.scrollStep = 1
		scrollbar:SetValue(0)
		scrollbar:SetWidth(16)
		scrollbar:SetScript("OnValueChanged",
		function (self, value)
		self:GetParent():SetVerticalScroll(value)
		end)
		local scrollbg = scrollbar:CreateTexture(nil, "BACKGROUND")
		scrollbg:SetAllPoints(scrollbar)
		scrollbg:SetTexture(0, 0, 0, 0.4)
		InstanceProfits_TableDisplay.scrollbar = scrollbar

		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		currentCopperAmount = GetMoney()
	elseif event == "PLAYER_ENTERING_WORLD" then
		local inInstance, instanceType = IsInInstance()
		local wasInPvEInstance = isInPvEInstance
		isInPvEInstance = inInstance and (instanceType == "party" or instanceType == "raid")

		if isInPvEInstance then -- entered instance
			local name, typeOfInstance, difficulty, difficultyName, _, _, _, instanceMapId = GetInstanceInfo()

			if not IGNORED_ZONES[instanceMapId] then
				triggerInstance(name, difficulty, difficultyName, true);
			end
		else -- entered something else
			if wasInPvEInstance ~= isInPvEInstance then -- we actually left instance
				saveInstanceData();
			end
		end
	elseif event == "PLAYER_MONEY" and isInPvEInstance then
		local previousCopperAmount = currentCopperAmount
		currentCopperAmount = GetMoney()

		local difference = currentCopperAmount - previousCopperAmount
		if difference > 0 then
			lootedMoney = lootedMoney + difference
		end

		liveLoot:SetText("Looted: " .. GetMoneyString(lootedMoney));
	elseif event == "CHAT_MSG_LOOT" and isInPvEInstance then
		local itemLink, quantity = strmatch(arg1, LOOT_ITEM_MULTIPLE_PATTERN)
		if not itemLink then
			itemLink, quantity = strmatch(arg1, LOOT_ITEM_PUSHED_MULTIPLE_PATTERN)
			if not itemLink then
				quantity, itemLink = 1, strmatch(arg1, LOOT_ITEM_PATTERN)
				if not itemLink then
					quantity, itemLink = 1, strmatch(arg1, LOOT_ITEM_PUSHED_PATTERN)
					if not itemLink then
						return
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
	elseif event == "GET_ITEM_INFO_RECEIVED" and isInPvEInstance then
		local name, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(arg1);
		vendorMoney = vendorMoney + (vendorPrice * (lootableItems[name] or 0));
		lootableItems[name] = 0;

		liveVendor:SetText("Vendor: " .. GetMoneyString(vendorMoney))
	elseif event == "PLAYER_LOGOUT" then
		if isInPvEInstance then
			saveInstanceData();
		end
		_G["IP_InstanceRunsCharacterHistory"] = characterHistory;
		_G["IP_InstanceRunsGlobalHistory"] = globalHistory;
	end
end
frame:SetScript("OnEvent", eventHandler);

SLASH_INSTANCEPROFITS1, SLASH_INSTANCEPROFITS2, SLASH_INSTANCEPROFITS3 = '/ip', '/instanceprofit', '/instanceprofits';
function SlashCmdList.INSTANCEPROFITS(msg, editbox)
	if msg == 'live' then
		IP_ShowLiveTracker();
	else
		InstanceProfits_TableDisplay:Show();
		IP_DisplaySavedData();
	end
end
