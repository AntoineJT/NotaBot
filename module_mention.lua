-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "mention"

function Module:GetConfigTable()
	return {
		{
			Name = "Emoji",
			Description = "Emoji to add as a reaction",
			Type = bot.ConfigType.Emoji,
			Default = "mention"
		}
	}
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)
	local mentionEmoji = bot:GetEmojiData(guild, config.Emoji)
	if (not mentionEmoji) then
		return false, "Emoji \"" .. config.Emoji .. "\" not found (check your configuration)"
	end

	return true
end

function Module:OnMessageCreate(message)
	if (message.channel.type ~= enums.channelType.text) then
		return
	end

	local mention = false

	if (message.mentionsEveryone) then
		mention = true
	else
		for _, user in pairs(message.mentionedUsers) do
			if (user.id == client.user.id) then
				mention = true
				break
			end
		end
	end

	if (mention) then
		local config = self:GetConfig(message.guild)
		local mentionEmoji = bot:GetEmojiData(message.guild, config.Emoji)
		if (not mentionEmoji) then
			return
		end

		message:addReaction(mentionEmoji.Emoji or mentionEmoji.Id)
	end
end
