--[[
Display an icon recommending a mana pot to use from your inventory.

If sound is on (/cmm cry) play it every 30s while a pot is available.
If all pots are on cooldown, display the shortest one (no sound).
If no pots available or major mana regen (Tide/trinket), display nothing.

/cmm help
]]
local L = "CareMyMana"
local UIParent = UIParent
local GetItemInfo = GetItemInfo
local GetItemCooldown = GetItemCooldown
local GetContainerItemLink = GetContainerItemLink
local GetContainerNumSlots = GetContainerNumSlots
local GetTime = GetTime
local UnitGUID = UnitGUID
local UnitAura = UnitAura
local GetNumPartyMembers = GetNumPartyMembers

--TODO: don't start this addon if UnitPowerType ~= 0 (or extend it with health/haste/destru pots)
local classUser = select(2, UnitClass("player"))
local manaUser = (classUser == "DRUID" or UnitPowerType("player") == 0)

local waitBigRegen --GetTime for expiration of last major mana regen
local soundPlayedTime = 0 --last GetTime we cry for mana
local consumeList = {} --pots in bags [itemId]=1

local function log(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end -- alias for convenience

-- local reference to the addon settings. this gets initialized when the ADDON_LOADED event fires
local CareMyManaDB

DBdefaults = {
  version = 1.00,
  enable = true, --show/hide frame + (un)register events
  cry = false, --no sound "/cmm cry/stfu"
  --TODO: add sound selection
  --TODO: add icon size option
  relativePoint = "CENTER", -- default frame position
  xOfs = 0,
  yOfs = 0,
}

-----------------------------------------------------------------------------
local Potions = {}
-- [cnt]={[1]=itemID,[2]=missingManaTrigger,[3]=requiredHealth,[4]=zoneRestriction,[5]=cooldown}
-- [5] is cooldown -1 no such item in bag, 0 usable, >0 time cooldown ends
-- available ones will be displayed first so insert in the prefered order
table.insert(Potions, { "12662", 1500, 1000, "ALL", -1 } ) --Demonic Rune
table.insert(Potions, { "20520", 1500, 1000, "ALL", -1 } ) --Dark Rune
table.insert(Potions, { "31677", 3200, 0,    "ALL", -1 } ) --Fel Mana
table.insert(Potions, { "32902", 3000, 0,    "TK",  -1 } ) --Bottled Nethergon Energy
table.insert(Potions, { "32903", 3000, 0,    "SSC", -1 } ) --Cenarion Mana
table.insert(Potions, { "33935", 3000, 0,    "ALL", -1 } ) --Crystal Mana
table.insert(Potions, { "32948", 3000, 0,    "ALL", -1 } ) --Auchenai Mana
table.insert(Potions, { "33093", 3000, 0,    "ALL", -1 } ) --Mana Potion Injector
table.insert(Potions, { "23823", 3000, 0,    "ALL", -1 } ) --Mana Potion Injector
table.insert(Potions, { "22832", 3000, 0,    "ALL", -1 } ) --Super Mana
table.insert(Potions, { "28101", 2250, 0,    "ALL", -1 } ) --Unstable Mana
table.insert(Potions, { "13444", 2250, 0,    "ALL", -1 } ) --Major Mana

local potionsInfo = {} -- localized names are saved here
for k, v in pairs(Potions) do
  local name = GetItemInfo(v[1])
  if name then
    potionsInfo[v[1]] = name
  else -- Report pots IDs not seen so far on the server
    log(L .. " unknown itemId: " .. v[1])
  end
end


-----------------------------------------------------------------------------
-- Create the main frame
local CareMyMana = CreateFrame("Button", nil, UIParent)
CareMyMana:SetSize(24, 24)
CareMyMana.cdText = CareMyMana:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
CareMyMana.cdText:SetPoint("CENTER")
CareMyMana.nameText = CareMyMana:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
--name text stands below
CareMyMana.nameText:SetPoint("TOP", CareMyMana, "BOTTOM")

function CareMyMana:OnEvent(event, ...)
	self[event](self, ...) -- route event parameters to CareMyMana:EVENT methods
end
CareMyMana:SetScript("OnEvent", CareMyMana.OnEvent)


local function displayPotion(idx)
  local questionTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
  --don't display if a major mana regen buff is running (unless unlocked)
  if not CareMyMana.unlock and waitBigRegen and waitBigRegen > GetTime() then
    CareMyMana:Hide()
    return
  end
  --change icon
  if idx == nil then --no potion, display unlocked
    CareMyMana:SetNormalTexture(questionTexture)
    CareMyMana.nameText:SetText("Place Me!")
  elseif CareMyMana.idx ~= idx then
    CareMyMana.idx = idx
    local id = Potions[idx][1]
    local itemTexture = select(10, GetItemInfo(id)) or questionTexture
    CareMyMana:SetNormalTexture(itemTexture)
    local name = potionsInfo[id]
    CareMyMana.nameText:SetText(name or "")
  end

  --update cooldown text
  if idx then
    local timeLeft = Potions[idx][5] - GetTime()
    if timeLeft < 0 then timeLeft = 0 end
    if timeLeft > 0 then
      local minutes = floor(timeLeft / 60)
      local seconds = timeLeft % 60
      if minutes > 0 then
	CareMyMana.cdText:SetText(string.format("%d:%02d", minutes, seconds))
      else
	CareMyMana.cdText:SetText(floor(seconds))
      end
    else
      CareMyMana.cdText:SetText("")
    end
  end

  CareMyMana:Show()
end


-- Handle mouse dragging
function CareMyMana:StopMoving()
  self:StopMovingOrSizing()
  point, relativeTo, CareMyManaDB.relativePoint, CareMyManaDB.xOfs, CareMyManaDB.yOfs = CareMyMana:GetPoint()
end
CareMyMana:SetScript("OnDragStart", CareMyMana.StartMoving)
CareMyMana:SetScript("OnDragStop", CareMyMana.StopMoving)
CareMyMana:RegisterForDrag("LeftButton")

local function unlockFrame(b)
  CareMyMana.unlock = b --always display an icon in unlock mode
  --display last potion or quesionMark
  displayPotion(CareMyMana.idx or nil)
  CareMyMana:SetMovable(b)
  CareMyMana:EnableMouse(b)
end

-----------------------------------------------------------------------------

local lastBagUpdate = 0

function CareMyMana:BAG_UPDATE(arg1)
  --arg1 = bag number triggering event
  --scan all bags to detect gone consumes

  --prevent lag on event spam
  local timeNow = GetTime()
  if math.abs(timeNow - lastBagUpdate) < 0.1 then return end
  lastBagUpdate = timeNow

  consumeList = {}
  local now = GetTime()
  for k, v in pairs(Potions) do
    for bag = 0, 4 do
      for slot = 1, GetContainerNumSlots(bag) do
	--id=GetContainerItemId(bag,slot)
	_, _, id = string.find(GetContainerItemLink(bag, slot) or "", "item:(%d+)")
	if id and id == v[1] then
	  consumeList[id] = 1 --TODO: get the real item count to display it
	  break
	end
      end
      if consumeList[v[1]] then break end
    end
  end
  updateCooldowns() --update CD when adding/drinking consume
  --log(L.." available consumes updated")
end
CareMyMana:RegisterEvent("BAG_UPDATE")

-- return zoneType: TK,SSC,BG,ALL (all other places)
local function getZoneType()
  local zoneName = GetRealZoneText()
  local zoneType = "ALL"
  if (zoneName == "The Botanica" or zoneName == "Tempest Keep" or zoneName == "The Mechanar" or zoneName == "The Arcatraz") then
    zoneType = "TK"
  elseif (zoneName == "Serpentshrine Cavern" or zoneName == "The Slave Pens" or zoneName == "The Underbog" or zoneName == "The Steamvault") then
    zoneType = "SSC"
  elseif (zoneName == "Warsong Gulch" or zoneName == "Alterac Valley" or zoneName == "Arathi Basin" or zoneName == "Eye of the Storm") then
    zoneType = "BG"
  end

  return zoneType
end

--handling of zone-restricted consumable
local zoneType = getZoneType()

function CareMyMana:ZONE_CHANGED_NEW_AREA()
  zoneType = getZoneType()
end
CareMyMana:RegisterEvent("ZONE_CHANGED_NEW_AREA") --change zone
--CareMyMana:RegisterEvent("ZONE_CHANGED") --change subzone (district in city for instance)

--no event when item cooldown ends (called from BAG_UPDATE and UNIT_MANA)
function updateCooldowns()
  local now = GetTime()
  for k, v in pairs(Potions) do
    local id = v[1]
    if consumeList[id] then
      startTime, duration, enable = GetItemCooldown(id)
      Potions[k][5] = startTime + duration
    else
      Potions[k][5] = -1 --no such pot in bags
    end
  end
end


function CareMyMana:UNIT_MANA(unitId)
  if unitId ~= "player" or not manaUser then return end
  local antiSpam = 30 --wait 30s between crying about mana (TODO: make this an option)
  local sound = "Sound\\Character\\BloodElf\\BloodElfFemale_Err_NoMana02.wav"
  local cry = false  --don't spam, wait to cry more
  local now = GetTime()
  if ((now - soundPlayedTime) > antiSpam) then cry = CareMyManaDB.cry end
  -- check missing mana(, 0)
  local missingMana = UnitPowerMax("player", 0) - UnitPower("player", 0)

  updateCooldowns()
  -- check potions in priority order
  local idxCooldown = nil --shortest cooldown pot index in Potions
  for cnt = 1, #Potions do
    -- potion is usable from bag, match the mana trigger and won't kill us
    local id = consumeList[Potions[cnt][1]]
    if id and missingMana >= Potions[cnt][2] and Potions[cnt][3] < UnitHealth("player") then
      local potCooldown = Potions[cnt][5]
      if potCooldown == 0 then
	displayPotion(cnt) --pot available, no CD
	if cry then
	  soundPlayedTime = now
	  PlaySoundFile(sound)
	end
	return
      elseif potCooldown > 0 then --remember pot with lowest cooldown
	if not idxCooldown or (idxCooldown and Potions[idxCooldown][5] > potCooldown) then
	  idxCooldown = cnt --new best cooldown
	end
      end
    end
  end
  --no pots found, display best one on cooldown (if it exist)
  if idxCooldown then
    displayPotion(idxCooldown)
  elseif CareMyMana.unlock then
    displayPotion(nil)
  else
    CareMyMana:Hide() --nothing to show
  end
end
CareMyMana:RegisterEvent("UNIT_MANA")


-- Handle default settings
function CareMyMana:ADDON_LOADED(arg1)
  if arg1 == L then
    if _G.CareMyManaDB and _G.CareMyManaDB.version then
      if _G.CareMyManaDB.version < DBdefaults.version then
	if _G.CareMyManaDB.version >= 1.00 then --1.00 is previous released version
	  --minor update
	  _G.CareMyManaDB.version = DBdefaults.version
	else -- major changes, must reset settings
	  _G.CareMyManaDB = CopyTable(DBdefaults)
	end
      end
    else -- never installed before
      _G.CareMyManaDB = CopyTable(DBdefaults)
    end
    CareMyManaDB = _G.CareMyManaDB
  end
  self.BAG_UPDATE() --scan consumes
  if CareMyManaDB.relativePoint and CareMyManaDB.xOfs and CareMyManaDB.yOfs then
    CareMyMana:SetPoint(CareMyManaDB.relativePoint, CareMyManaDB.xOfs, CareMyManaDB.yOfs)
  else
    CareMyMana:SetPoint("CENTER")
  end
end
CareMyMana:RegisterEvent("ADDON_LOADED")


--Buff/Debuff scanning
--add big mp5 aura detection as we may not want to quaff
--Wisdom 37656 from Memento of Tyrande
--Enlightenment 29601 from Pendant of the Violet Eye
--Aura of the Blue Dragon 23684 from Darkmoon Card: Blue Dragon
--innervate 29166
--symbol of hope 32548
function CareMyMana:UNIT_AURA(unitId) -- fired when a (de)buff is gained/lost
  if unitId ~= "player" then return end
  
  for i = 1, 40 do
    name, rank, icon, count, debuffType, duration, expirationTime,
      unitCaster, isStealable, shouldConsolidate,
      spellId = UnitAura("player", i, "HELPFUL")
    if not name then break end -- no more debuffs, terminate the loop
    if spellId == 37656 or spellId == 29601 or spellId == 23684 or spellId == 29166 or spellId == 32548 then
      if expirationTime > (waitBigRegen or 0) then
	waitBigRegen = expirationTime
	log(L.." hides for "..floor(waitBigRegen - GetTime()).. "s")
	if CareMyMana.unlock then
	  displayPotion(nil)
	else
	  CareMyMana:Hide()
	end
      end
    end
  end
end
CareMyMana:RegisterEvent("UNIT_AURA")

function CareMyMana:COMBAT_LOG_EVENT_UNFILTERED(...)
  local timestamp,event,sourceGUID,sourceName,sourceFlags,destGUID,destName,
    destFlags,spellId,spellName,spellSchool = select(1,...)
  --16190=Mana Tide Totem
  if spellId == 16190 then --in my group?
    for i = 0, GetNumPartyMembers() do
      local unitId
      if i == 0 then unitId = "player" else unitId = "party"..i end
      if UnitGUID(unitId) == sourceGUID then
	log(L.." Mana Tide in my group")
	local expirationTime = 12 + GetTime()
	if expirationTime > (waitBigRegen or 0) then
	  waitBigRegen = expirationTime
	  log(L.." hides for "..floor(waitBigRegen - GetTime()).. "s")
	  if CareMyMana.unlock then
	    displayPotion(nil)
	  else
	    CareMyMana:Hide()
	  end
	  return
	end
      end
    end
  end
end
CareMyMana:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

local function registerEvents(enable)
  if enable then
    CareMyMana:RegisterEvent("BAG_UPDATE")
    CareMyMana:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    CareMyMana:RegisterEvent("UNIT_MANA")
    CareMyMana:RegisterEvent("UNIT_AURA")
    CareMyMana:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  else
    CareMyMana:UnregisterEvent("BAG_UPDATE")
    CareMyMana:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    CareMyMana:UnregisterEvent("UNIT_MANA")
    CareMyMana:UnregisterEvent("UNIT_AURA")
    CareMyMana:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    CareMyMana:Hide()
  end
end

-----------------------------------------------------------------------------
SLASH_CareMyMana1 = "/cmm"
SLASH_CareMyMana2 = "/caremymana"
SlashCmdList[L] = function(cmd)
	cmd = cmd:lower()
	if cmd == "reset" then
	elseif cmd == "lock" then
	  unlockFrame(false)
	  log(L .. " locked.")
	elseif cmd == "unlock" then
	  unlockFrame(true)
	  log(L .. " unlocked.")
	elseif cmd == "enable" then
	  CareMyManaDB.enable = true
	  registerEvents(CareMyManaDB.enable)
	  CareMyMana:Show()
	  log(L .. ": enabled.")
	elseif cmd == "disable" then
	  CareMyManaDB.enable = false
	  registerEvents(CareMyManaDB.enable)
	  CareMyMana:Hide()
	  log(L .. ": disabled.")
	elseif cmd == "cry" then
	  CareMyManaDB.cry = true
	elseif cmd == "stfu" then
	  CareMyManaDB.cry = false
	elseif cmd:sub(1, 4) == "help" then
	  log(L .. " slash commands:")
	  log("    reset")
	  log("    lock")
	  log("    unlock")
	  log("    enable")
	  log("    disable")
	  log("    cry")
	  log("    stfu")
	else
	  log(L .. ": Type \"/cmm help\" for more options.")
	end
end
