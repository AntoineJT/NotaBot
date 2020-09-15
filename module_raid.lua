-- Copyright (C) 2020 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "raid"

function Module:GetConfigTable()
	return {
		{
			Array = true,
			Name = "LockAuthorizedRoles",
			Description = "Roles allowed to lock and unlock server",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "AlertChannel",
			Description = "Channel where a message will be posted (if set) in case of raid",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
		{
			Name = "SendMessageThreshold",
			Description = "If a new member sends a message before this duration, they will be auto-banned (0 to disable)",
			Type = bot.ConfigType.Duration,
			Default = 5
		},
		{
			Name = "JoinDefaultLockDuration",
			Description = "For how many time should the server be locked in case of join spam",
			Type = bot.ConfigType.Duration,
			Default = 10 * 60
		},
		{
			Name = "JoinCountThreshold",
			Description = "How many members are allowed to join the server in the join window before triggering an automatic lock",
			Type = bot.ConfigType.Integer,
			Default = 10
		},
		{
			Name = "JoinTimeThreshold",
			Description = "For how many time should the join window be open",
			Type = bot.ConfigType.Integer,
			Default = 5
		},
		{
			Name = "SpamCountThreshold",
			Description = "How many messages is a member allowed to post in the spam window before being banned",
			Type = bot.ConfigType.Integer,
			Default = 5
		},
		{
			Name = "SpamTimeThreshold",
			Description = "For how many time should the spam window be open",
			Type = bot.ConfigType.Integer,
			Default = 2
		}
	}
end

function Module:CheckPermissions(member)
	local config = self:GetConfig(member.guild)
	if (util.MemberHasAnyRole(member, config.LockAuthorizedRoles)) then
		return true
	end

	if (member:hasPermission(enums.permission.administrator)) then
		return true
	end

	return false
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "lockserver",
		Args = {
			{Name = "duration", Type = Bot.ConfigType.Duration, Optional = true},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Locks the server, preventing people to join",
		Silent = true,
		Func = function (commandMessage, duration, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local lockedBy = commandMessage.member

			if (self:IsServerLocked(guild)) then
				commandMessage:reply("The server is already locked")
				return
			end

			-- Duration
			if (not duration) then
				duration = config.DefaultLockDuration
			end

			-- Reason
			local reasonStart = "locked by " .. lockedBy.mentionString
			if (reason) then
				reason = reasonStart .. ": " .. reason
			else
				reason = reasonStart
			end

			self:LockServer(guild, duration, reason)
		end
	})

	self:RegisterCommand({
		Name = "unlockserver",
		Args = {
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Unlocks the server",
		Silent = true,
		Func = function (commandMessage, targetUser, reason)
			local guild = commandMessage.guild
			local lockedBy = commandMessage.member

			if (not self:IsServerLocked(guild)) then
				commandMessage:reply("The server is not locked %s")
				return
			end

			-- Reason
			local reasonStart = "unlocked by " .. lockedBy.mentionString
			if (reason) then
				reason = reasonStart .. ": " .. reason
			else
				reason = reasonStart
			end

			self:UnlockServer(guild, reason)
		end
	})

	return true
end

function Module:OnEnable(guild)
	local data = self:GetData(guild)
	local persistentData = self:GetPersistentData(guild)
	persistentData.lockedUntil = persistentData.lockedUntil or 0

	local now = os.time()
	if (persistentData.lockedUntil > now) then
		self:StartLockTimer(persistentData.lockedUntil)
		data.locked = true
	else
		data.locked = false
	end

	data.joinChain = {}

	return true
end

function Module:OnDisable(guild)
	local data = self:GetData(guild)

	if (data.lockTimer) then
		data.lockTimer:Stop()
		data.lockTimer = nil
	end

	local data = self:GetData(guild)
	data.joinChain = {}

	return true
end

function Module:AutoLockServer(guild, reason)
	local config = self:GetConfig(guild)
	local duration = config.DefaultLockDuration

	self:LockServer(guild, duration, reason)
end

function Module:StartLockTimer(guild, unlockTimestamp)
	local data = self:GetData(guild)

	if (data.lockTimer) then
		data.lockTimer:Unlock()
	end

	if (unlockTimestamp >= math.huge) then
		local guildId = guild.id
		data.lockTimer = bot:ScheduleTimer(unlockTimestamp, function ()
			local guild = client:getGuild(guildId)
			if (guild) then
				self:UnlockServer(guild, "lock duration expired")
			end
		end)
	else
		data.lockTimer = nil
	end
end

function Module:LockServer(guild, duration, reason)
	local config = self:GetConfig(guild)
	local data = self:GetData(guild)
	local persistentData = self:GetPersistentData(guild)

	data.locked = true
	if (duration > 0) then
		persistentData.lockedUntil = os.time() + duration
	else
		persistentData.lockedUntil = math.huge
	end

	self:StartLockTimer(guild, persistentData.lockedUntil)

	if (config.AlertChannel) then
		local durationStr = duration > 0 and "for " .. util.FormatTime(duration, 3) or ""

		local alertChannel = guild:getChannel(config.AlertChannel)
		if (alertChannel) then
			local message = "🔒 The server has been locked " .. durationStr .. " because a raid has been detected (%s)"

			alertChannel:send({
				embed = {
					color = 16711680,
					description = string.format(message, util.FormatTime(duration, 3), reason),
					timestamp = discordia.Date():toISO('T', 'Z')
				}
			})
		end
	end
end

function Module:IsServerLocked(guild)
	local data = self:GetData(guild)
	return data.locked
end

function Module:UnlockServer(guild, reason)
	local config = self:GetConfig(guild)
	local data = self:GetData(guild)
	if (data.locked) then
		data.locked = false

		if (config.AlertChannel) then
			local alertChannel = guild:getChannel(config.AlertChannel)
			if (alertChannel) then
				local message = "🔓 The server has been unlocked (%s)"

				alertChannel:send({
					embed = {
						color = 65280,
						description = string.format(message, reason),
						timestamp = discordia.Date():toISO('T', 'Z')
					}
				})
			end
		end
	end
end

function Module:OnMemberJoin(member)
	local guild = member.guild
	local config = self:GetConfig(guild)
	local data = self:GetData(guild)

	if (data.locked) then
		member:kick("server is locked")
	else
		local now = os.time()

		local joinCountThreshold = config.JoinCountThreshold
		local timeThreshold = config.JoinTimeThreshold

		while (#data.joinChain > 0 and (now - data.joinChain[1].at > timeThreshold)) do
			table.remove(data.joinChain, 1)
		end

		table.insert(data.joinChain, {
			at = now,
			memberId = member.id
		})

		if (#data.joinChain > joinCountThreshold) then
			self:AutoLockServer(guild, "auto-lock for suspicious joining accounts")

			local membersToKick = {}
			for _, joinData in pairs(data.joinChain) do
				table.insert(membersToKick, joinData.memberId)
			end

			for _, memberId in pairs(membersToKick) do
				local member = guild:getMember(memberId)
				if (member) then
					member:kick("server is locked")
				end
			end
		end
	end
end

function Module:OnMessageCreate(message)
	if (not bot:IsPublicChannel(message.channel)) then
		return
	end

	if (message.author.bot) then
		return
	end

	local guild = message.guild
	local member = message.member
	local data = self:GetData(guild)

	local config = self:GetConfig(guild)

	local duration = discordia.Date() - discordia.Date.fromISO(member.joinedAt)
	if (duration:toSeconds() < config.SendMessageThreshold) then
		local success, err = member:ban("auto-ban for bot suspicion", 1)
		if (not success) then
			self:LogWarning(guild, "Failed to autoban potential bot %s (%s)", member.tag, err)
		end

		return
	end

	local spamChain = data.spamChain[member.id]
	if (not spamChain) then
		spamChain = {}
		data.spamChain[member.id] = spamChain
	end

	local now = os.time()
	local countThreshold = config.SpamCountThreshold
	local timeThreshold = config.SpamTimeThreshold

	while (#spamChain > 0 and (now - spamChain[1].at > timeThreshold)) do
		table.remove(spamChain, 1)
	end

	table.insert(spamChain, {
		at = now,
		messageId = message.id
	})

	if (#spamChain > countThreshold) then
		local success, err = member:ban("auto-ban for bot suspicion", 1)
		if (not success) then
			self:LogWarning(guild, "Failed to autoban potential bot %s (%s)", member.tag, err)
		end

		return
	end
end
