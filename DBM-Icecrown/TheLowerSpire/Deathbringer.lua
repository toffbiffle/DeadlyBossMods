local mod	= DBM:NewMod("Deathbringer", "DBM-Icecrown", 1)
local L		= mod:GetLocalizedStrings()

mod:SetRevision(("$Revision$"):sub(12, -3))
mod:SetCreatureID(37813)
mod:RegisterCombat("combat")
mod:SetUsedIcons(5, 6, 7, 8)

mod:RegisterEvents(
	"SPELL_CAST_START",
	"SPELL_CAST_SUCCESS",
	"SPELL_AURA_APPLIED",
	"SPELL_AURA_REMOVED",
	"UNIT_HEALTH",
	"CHAT_MSG_MONSTER_YELL"
)

local isRanged = select(2, UnitClass("player")) == "MAGE"
              or select(2, UnitClass("player")) == "HUNTER"
              or select(2, UnitClass("player")) == "WARLOCK"

local warnFrenzySoon		= mod:NewAnnounce("warnFrenzySoon", 2, 72737)
local warnAddsSoon			= mod:NewSoonAnnounce(72173, 3)
local warnFrenzy			= mod:NewSpellAnnounce(72737)
local warnBloodNova			= mod:NewSpellAnnounce(73058)
local warnMark				= mod:NewTargetAnnounce(72444)
local warnBoilingBlood		= mod:NewTargetAnnounce(72441)
local warnRuneofBlood		= mod:NewTargetAnnounce(72410)

local specWarnMarkCast		= mod:NewSpecialWarningYou(72444, false)--Experimental
local specwarnMark			= mod:NewSpecialWarningTarget(72444, false)
local specwarnRuneofBlood	= mod:NewSpecialWarningTarget(72410, false)

local timerCombatStart		= mod:NewTimer(48, "TimerCombatStart", 2457)
local timerRuneofBlood		= mod:NewTargetTimer(20, 72410)
local timerBoilingBlood		= mod:NewBuffActiveTimer(15, 72441)
local timerBloodNova		= mod:NewCDTimer(20, 73058)--20-25sec cooldown?
local timerCallBloodBeast	= mod:NewNextTimer(40, 72173)
local timerNextRuneofBlood	= mod:NewCDTimer(25, 72410)

local enrageTimer			= mod:NewBerserkTimer(480)

mod:AddBoolOption("RangeFrame", isRanged)
mod:AddBoolOption("RunePowerFrame", true, "misc")
mod:AddBoolOption("SetIconOnBoilingBlood", true)
mod:AddBoolOption("SetIconOnMarkCast", true)
mod:RemoveOption("HealthFrame")

local warned_preFrenzy = false
local boilingBloodTargets = {}
local boilingBloodIcon 	= 7
local spamBloodBeast = 0

local function warnBoilingBloodTargets()
	warnBoilingBlood:Show(table.concat(boilingBloodTargets, "<, >"))
	table.wipe(boilingBloodTargets)
	timerBoilingBlood:Start()
	boilingBloodIcon = 7
end

function mod:OnCombatStart(delay)
	if self.Options.RunePowerFrame then
		DBM.BossHealth:Show(L.name)
		DBM.BossHealth:AddBoss(37813, L.name)
		self:ScheduleMethod(0.5, "CreateBossRPFrame")
	end
	timerCallBloodBeast:Start(-delay)
	warnAddsSoon:Schedule(35-delay)
	timerBloodNova:Start(-delay)
	if mod:IsDifficulty("normal10") or mod:IsDifficulty("normal25") then
		enrageTimer:Start(-delay)
	else
		enrageTimer:Start(360-delay)
	end
	table.wipe(boilingBloodTargets)
	warned_preFrenzy = false
	boilingBloodIcon = 7
	if self.Options.RangeFrame then
		DBM.RangeCheck:Show(12)
	end
end

function mod:OnCombatEnd()
	if self.Options.RangeFrame then
		DBM.RangeCheck:Hide()
	end
	DBM.BossHealth:Clear()
end

function mod:MarkTarget()
	local targetname = self:GetBossTarget(37813)
	if not targetname then return end
	if self.Options.SetIconOnMarkCast then
		self:SetIcon(targetname, 8, 1.2)
	end
	if targetname == UnitName("player") then
		specWarnMarkCast:Show(targetname)
	end
end

do	-- add the additional Rune Power Bar
	local last = 0
	local function getRunePowerPercent()
		local guid = UnitGUID("focus")
		if guid and tonumber(guid:sub(9, 12), 16) == 37813 then 
			last = math.floor(UnitPower("focus")/UnitPowerMax("focus") * 100)
			return last
		end
		for i = 0, GetNumRaidMembers(), 1 do
			local unitId = ((i == 0) and "target") or "raid"..i.."target"
			local guid = UnitGUID(unitId)
			if guid and tonumber(guid:sub(9, 12), 16) == 37813 then
				last = math.floor(UnitPower(unitId)/UnitPowerMax(unitId) * 100)
				return last
			end
		end
		return last
	end
	function mod:CreateBossRPFrame()
		DBM.BossHealth:AddBoss(getRunePowerPercent, L.RunePower)
	end
end

function mod:SPELL_CAST_START(args)
	if args:IsSpellID(73058, 72378) then	-- Blood Nova (only 2 cast IDs, 4 spell damage IDs, and one dummy)
		warnBloodNova:Show()
		timerBloodNova:Start()
	elseif args:IsSpellID(72293) then		-- Mark of the Fallen Champion
		self:ScheduleMethod(0.3, "MarkTarget")
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args:IsSpellID(72173, 72356, 72357, 72358) then
		timerCallBloodBeast:Start()
		if GetTime() - spamBloodBeast > 5 then
			warnAddsSoon:Schedule(35)
			spamBloodBeast = GetTime()
		end
	elseif args:IsSpellID(72410) then
		timerNextRuneofBlood:Start()
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args:IsSpellID(72293) then		-- Mark of the Fallen Champion
		warnMark:Show(args.destName)
		specwarnMark:Show(args.destName)
	elseif args:IsSpellID(72385, 72441, 72442, 72443) then	-- Boiling Blood
		boilingBloodTargets[#boilingBloodTargets + 1] = args.destName
		if self.Options.SetIconOnBoilingBlood then
			self:SetIcon(args.destName, boilingBloodIcon, 15)
			boilingBloodIcon = boilingBloodIcon - 1
		end
		self:Unschedule(warnBoilingBloodTargets)
		if mod:IsDifficulty("normal10") or (mod:IsDifficulty("normal25") and #boilingBloodTargets >= 3) then	-- Boiling Blood
			warnBoilingBloodTargets()
		else
			self:Schedule(0.3, warnBoilingBloodTargets)
		end
	elseif args:IsSpellID(72410) then						-- Rune of Blood
		warnRuneofBlood:Show(args.destName)
		timerRuneofBlood:Start(args.destName)
		specwarnRuneofBlood:Show(args.destName)
	elseif args:IsSpellID(72737) then						-- Frenzy
		warnFrenzy:Show()
	end
end

function mod:SPELL_AURA_REMOVED(args)
	if args:IsSpellID(72385, 72441, 72442, 72443) then
		self:SetIcon(args.destName, 0)
	end
end

function mod:UNIT_HEALTH(uId)
	if not warned_preFrenzy and self:GetUnitCreatureId(uId) == 37813 and UnitHealth(uId) / UnitHealthMax(uId) <= 0.33 then
		warned_preFrenzy = true
		warnFrenzySoon:Show()	
	end
end

function mod:CHAT_MSG_MONSTER_YELL(msg)
	if msg == L.PullAlliance or msg:find(L.PullAlliance, 1, true) then
		self:SendSync("PullAlliance")
	elseif msg == L.PullHorde or msg:find(L.PullHorde, 1, true) then
		self:SendSync("PullHorde")
	end
end

function mod:OnSync(msg, arg)
	if msg == "PullAlliance" then
		timerCombatStart:Start()
	elseif msg == "PullHorde" then
		timerCombatStart:Start(99)
	end
end