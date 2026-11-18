/*
===========================================================================

  Copyright (c) 2025 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#include "0x0b5_chat_std.h"

#include "ai/ai_container.h"
#include "aman.h"
#include "command_handler.h"
#include "common/ipc_structs.h"
#include "common/lua.h"
#include "common/settings.h"
#include "common/timer.h"
#include "entities/char_entity.h"
#include "entities/mob_entity.h"
#include "enums/msg_basic.h"
#include "ipc_client.h"
#include "linkshell.h"
#include "map_session.h"
#include "packets/c2s/validation.h"
#include "packets/s2c/0x009_message.h"
#include "packets/s2c/0x017_chat_std.h"
#include "packets/s2c/0x029_battle_message.h"
#include "roe.h"
#include "status_effect_container.h"
#include "unitychat.h"
#include "utils/jailutils.h"
#include "utils/trustutils.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <format>
#include <set>
#include <string_view>

namespace
{

constexpr auto   EnemyBarCommand           = std::string_view("mochienemybar");
constexpr uint32 EnemyBarRequestIntervalMs = 1000;
constexpr float  EnemyBarRange             = 24.0f;
constexpr size_t EnemyBarIconsPerPacket    = 8;
constexpr size_t EnemyBarMaxParts          = 17;

template <typename Number>
bool ParseEnemyBarNumber(std::string_view text, Number& value)
{
    if (text.empty() || text.front() < '1' || text.front() > '9')
    {
        return false;
    }

    const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value);
    return error == std::errc{} && end == text.data() + text.size();
}

void SendSelectedEnemyBar(CCharEntity* player, std::string_view request)
{
    if (!trustutils::CanUseTwillsTrustGameplay(player) || !player->isAlive() || player->inMogHouse() || player->pendingPositionUpdate)
    {
        return;
    }

    std::array<std::string_view, 4> fields;
    for (auto& field : fields)
    {
        if (!request.starts_with(' '))
        {
            return;
        }
        request.remove_prefix(1);
        field = request.substr(0, request.find(' '));
        request.remove_prefix(field.size());
    }
    const auto nonce = fields[0];
    uint16     zone  = 0;
    uint32     id    = 0;
    uint16     index = 0;
    if (!request.empty() || nonce.size() != 16 ||
        !std::ranges::all_of(nonce, [](char c)
                             {
                                 return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
                             }) ||
        !ParseEnemyBarNumber(fields[1], zone) || !ParseEnemyBarNumber(fields[2], id) || !ParseEnemyBarNumber(fields[3], index) || index > 4095)
    {
        return;
    }

    const auto now  = static_cast<uint32>(timer::count_milliseconds(timer::now().time_since_epoch()));
    const auto last = player->GetLocalVar("MochiriiEnemyBarLastRequest");
    if (last != 0 && now - last < EnemyBarRequestIntervalMs)
    {
        return;
    }
    player->SetLocalVar("MochiriiEnemyBarLastRequest", now);

    const auto header = std::format("MEB1 {} {} {} {}", nonce, zone, id, index);
    const auto send   = [&](const std::string& text)
    {
        player->pushPacket<GP_SERV_COMMAND_CHAT_STD>(player, MESSAGE_SYSTEM_1, text, "MochiEnemybar");
    };
    const auto  visible = player->SpawnMOBList.find(id);
    const auto* base    = visible == player->SpawnMOBList.end() ? nullptr : visible->second;
    auto*       mob     = base && base->objtype == TYPE_MOB ? static_cast<CMobEntity*>(visible->second) : nullptr;
    if (!mob || player->getZone() != static_cast<xi::ZoneId>(zone) || player->m_TargID != index || mob->targid != index ||
        player->loc.zone != mob->loc.zone || player->PInstance != mob->PInstance || player->PBattlefield != mob->PBattlefield ||
        player->getBattleID() != mob->getBattleID() || player->allegiance == mob->allegiance ||
        player->StatusEffectContainer->GetConfrontationEffect() != mob->StatusEffectContainer->GetConfrontationEffect() ||
        !mob->isAlive() || !mob->PAI->IsSpawned() || mob->PAI->IsUntargetable() || mob->IsNameHidden() || mob->GetUntargetable() ||
        mob->status == xi::Status::Invisible || distance(player->loc.p, mob->loc.p) > EnemyBarRange)
    {
        send(header + " unavailable");
        return;
    }

    std::set<uint16> icons;
    mob->StatusEffectContainer->ForEachEffect([&](const CStatusEffect& effect)
                                              {
                                                  if (const auto icon = effect.GetIcon(); icon != 0)
                                                  {
                                                      icons.insert(icon);
                                                  }
                                              });
    if (icons.size() > EnemyBarMaxParts * EnemyBarIconsPerPacket)
    {
        send(header + " unavailable");
        return;
    }

    const auto resources = std::format("{} {} {} {} {}", mob->health.hp, mob->GetMaxHP(), mob->health.mp, mob->GetMaxMP(), static_cast<uint16>(mob->health.tp));
    const auto parts     = std::max(size_t{ 1 }, (icons.size() + EnemyBarIconsPerPacket - 1) / EnemyBarIconsPerPacket);
    auto       icon      = icons.begin();
    for (size_t part = 1; part <= parts; ++part)
    {
        std::string effectList;
        for (size_t count = 0; icon != icons.end() && count < EnemyBarIconsPerPacket; ++icon, ++count)
        {
            if (!effectList.empty())
            {
                effectList += ',';
            }
            effectList += std::to_string(*icon);
        }
        send(std::format("{} {} {} {} {}", header, resources, part, parts, effectList.empty() ? "-" : effectList));
    }
}

const auto auditChat = [](Scheduler& scheduler, CCharEntity* PChar, const std::string& chatType, const std::string& rawMessage)
{
    const std::string auditConfigKey = std::format("map.AUDIT_{}", chatType);
    if (settings::get<bool>("map.AUDIT_CHAT") && settings::get<uint8>(auditConfigKey))
    {
        const auto& name   = PChar->getName();
        const auto  zoneId = PChar->getZone();

        scheduler.postToWorkerThread(
            [name, chatType, zoneId, rawMessage]()
            {
                const auto query = "INSERT INTO audit_chat (speaker, type, zoneid, message, datetime) VALUES(?, ?, ?, ?, current_timestamp())";
                if (!db::preparedStmt(query, name, chatType, zoneId, rawMessage))
                {
                    ShowErrorFmt("Failed to insert {} audit_chat record for player '{}'", chatType, name);
                }
            });
    }
};

const auto auditUnity = [](Scheduler& scheduler, CCharEntity* PChar, const std::string& rawMessage)
{
    if (settings::get<bool>("map.AUDIT_CHAT") && settings::get<uint8>("map.AUDIT_UNITY"))
    {
        const auto& name        = PChar->getName();
        const auto  zoneId      = PChar->getZone();
        const auto  unityLeader = PChar->PUnityChat->getLeader();

        scheduler.postToWorkerThread(
            [name, zoneId, unityLeader, rawMessage]()
            {
                const auto query = "INSERT INTO audit_chat (speaker, type, zoneid, unity, message, datetime) VALUES(?, 'UNITY', ?, ?, ?, current_timestamp())";
                if (!db::preparedStmt(query, name, zoneId, unityLeader, rawMessage))
                {
                    ShowError("Failed to insert UNITY audit_chat record for player '%s'", name.c_str());
                }
            });
    }
};

const auto auditLinkshell = [](Scheduler& scheduler, CCharEntity* PChar, CLinkshell* PLinkshell, const std::string& rawMessage)
{
    if (settings::get<bool>("map.AUDIT_CHAT") && settings::get<uint8>("map.AUDIT_LINKSHELL"))
    {
        const auto& name   = PChar->getName();
        const auto  zoneId = PChar->getZone();
        char        decodedLinkshellName[DecodeStringLength];
        DecodeStringLinkshell(PLinkshell->getName(), decodedLinkshellName);

        scheduler.postToWorkerThread(
            [name, zoneId, decodedLinkshellName, rawMessage]()
            {
                const auto query = "INSERT INTO audit_chat (speaker, type, lsName, zoneid, message, datetime) VALUES(?, 'LINKSHELL', ?, ?, ?, current_timestamp())";
                if (!db::preparedStmt(query, name, decodedLinkshellName, zoneId, rawMessage))
                {
                    ShowError("Failed to insert LINKSHELL audit_chat record for player '%s'", name);
                }
            });
    }
};

} // namespace

auto GP_CLI_COMMAND_CHAT_STD::validate(MapSession* PSession, const CCharEntity* PChar) const -> PacketValidationResult
{
    return PacketValidator(PChar)
        .oneOf<GP_CLI_COMMAND_CHAT_STD_KIND>(this->Kind);
}

void GP_CLI_COMMAND_CHAT_STD::process(MapSession* PSession, CCharEntity* PChar) const
{
    // Extremely important to figure out the message length here.
    // Depending on alignment, the message may not be NULL-terminated.
    // Start with reported size and skip the first 6 bytes (4x header + 1x kind + 1x unknown).
    const auto messageLength              = std::min<std::size_t>((header.size * 4) - 0x6, sizeof(this->Str));
    const auto rawMessage                 = asStringFromUntrustedSource(this->Str, messageLength);
    const auto firstChar                  = rawMessage[0];
    const auto rawMessageWithoutFirstChar = rawMessage.empty() ? std::string() : rawMessage.substr(1);

    // Handle possible !commands
    if (firstChar == '!' && !jailutils::InPrison(PChar))
    {
        const std::string_view command(rawMessageWithoutFirstChar);
        if (command == EnemyBarCommand || (command.starts_with(EnemyBarCommand) && command[EnemyBarCommand.size()] == ' '))
        {
            SendSelectedEnemyBar(PChar, command.substr(EnemyBarCommand.size()));
            return;
        }

        // TODO: Don't pass around Scheduler& through PSession
        auto& scheduler = *PSession->scheduler;
        if (CCommandHandler::call(scheduler, lua, PChar, rawMessageWithoutFirstChar) == CommandResult::Success ||
            PChar->m_GMlevel > 0)
        {
            // A command was handled OR a GM may have mistyped.
            return;
        }
    }

    // Handle possible GM message broadcast
    if (firstChar == '#' && PChar->m_GMlevel > 0)
    {
        message::send(ipc::ChatMessageServerMessage{
            .senderId   = PChar->id,
            .senderName = PChar->getName(),
            .message    = rawMessageWithoutFirstChar,
            .zoneId     = PChar->getZone(),
            .gmLevel    = PChar->m_GMlevel,
        });

        return;
    }

    // If you're jailed, you can only use /say
    if (jailutils::InPrison(PChar))
    {
        if (this->Kind == static_cast<uint8_t>(GP_CLI_COMMAND_CHAT_STD_KIND::Say))
        {
            // TODO: Don't pass around Scheduler& through PSession
            auditChat(*PSession->scheduler, PChar, "SAY", rawMessage);
            PChar->loc.zone->PushPacket(PChar, CHAR_INRANGE, std::make_unique<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SAY, rawMessage));
        }
        else
        {
            PChar->pushPacket<GP_SERV_COMMAND_BATTLE_MESSAGE>(PChar, PChar, 0, 0, MsgBasic::CannotInThisArea);
        }

        return;
    }

    // Now handle every other chat type
    switch (static_cast<GP_CLI_COMMAND_CHAT_STD_KIND>(this->Kind))
    {
        case GP_CLI_COMMAND_CHAT_STD_KIND::Say:
        {
            // TODO: Don't pass around Scheduler& through PSession
            auditChat(*PSession->scheduler, PChar, "SAY", rawMessage);
            PChar->loc.zone->PushPacket(PChar, CHAR_INRANGE, std::make_unique<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SAY, rawMessage));
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::Emote:
        {
            PChar->loc.zone->PushPacket(PChar, CHAR_INRANGE, std::make_unique<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_EMOTION, rawMessage));
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::Shout:
        {
            // TODO: Don't pass around Scheduler& through PSession
            auditChat(*PSession->scheduler, PChar, "SHOUT", rawMessage);
            PChar->loc.zone->PushPacket(PChar, CHAR_INSHOUT, std::make_unique<GP_SERV_COMMAND_CHAT_STD>(PChar, MESSAGE_SHOUT, rawMessage));
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::Linkshell1:
        {
            if (PChar->PLinkshell1 != nullptr)
            {
                message::send(ipc::ChatMessageLinkshell{
                    .linkshellId = PChar->PLinkshell1->getID(),
                    .senderId    = PChar->id,
                    .senderName  = PChar->getName(),
                    .message     = rawMessage,
                    .zoneId      = PChar->getZone(),
                    .gmLevel     = PChar->m_GMlevel,
                });

                // TODO: Don't pass around Scheduler& through PSession
                auditLinkshell(*PSession->scheduler, PChar, PChar->PLinkshell1, rawMessage);
            }
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::Linkshell2:
        {
            if (PChar->PLinkshell2 != nullptr)
            {
                message::send(ipc::ChatMessageLinkshell{
                    .linkshellId = PChar->PLinkshell2->getID(),
                    .senderId    = PChar->id,
                    .senderName  = PChar->getName(),
                    .message     = rawMessage,
                    .zoneId      = PChar->getZone(),
                    .gmLevel     = PChar->m_GMlevel,
                });

                // TODO: Don't pass around Scheduler& through PSession
                auditLinkshell(*PSession->scheduler, PChar, PChar->PLinkshell2, rawMessage);
            }
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::Party:
        {
            if (PChar->PParty != nullptr)
            {
                if (PChar->PParty->m_PAlliance)
                {
                    message::send(ipc::ChatMessageAlliance{
                        .allianceId = PChar->PParty->m_PAlliance->m_AllianceID,
                        .senderId   = PChar->id,
                        .senderName = PChar->getName(),
                        .message    = rawMessage,
                        .zoneId     = PChar->getZone(),
                        .gmLevel    = PChar->m_GMlevel,
                    });
                }
                else
                {
                    message::send(ipc::ChatMessageParty{
                        .partyId    = PChar->PParty->GetPartyID(),
                        .senderId   = PChar->id,
                        .senderName = PChar->getName(),
                        .message    = rawMessage,
                        .zoneId     = PChar->getZone(),
                        .gmLevel    = PChar->m_GMlevel,
                    });
                }

                // TODO: Don't pass around Scheduler& through PSession
                auditChat(*PSession->scheduler, PChar, "PARTY", rawMessage);
            }
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::Yell:
        {
            const auto yellCooldownTime = settings::get<uint16>("map.YELL_COOLDOWN");
            const auto isYellBanned     = PChar->getCharVar("[YELL]Banned") == 1;
            const auto isInYellCooldown = PChar->getCharVar("[YELL]Cooldown") == 1;

            if (PChar->loc.zone->CanUseMisc(xi::ZoneMisc::Yell))
            {
                if (isYellBanned)
                {
                    PChar->pushPacket<GP_SERV_COMMAND_BATTLE_MESSAGE>(PChar, PChar, 0, 0, MsgBasic::CannotUseInArea);
                }
                else if (!isInYellCooldown)
                {
                    // CharVar will self-expire and set to zero after the cooldown period
                    PChar->setCharVar("[YELL]Cooldown", 1, earth_time::timestamp() + yellCooldownTime);

                    message::send(ipc::ChatMessageYell{
                        .senderId   = PChar->id,
                        .senderName = PChar->getName(),
                        .message    = rawMessage,
                        .zoneId     = PChar->getZone(),
                        .gmLevel    = PChar->m_GMlevel,
                    });

                    // TODO: Don't pass around Scheduler& through PSession
                    auditChat(*PSession->scheduler, PChar, "YELL", rawMessage);
                }
                else
                {
                    PChar->pushPacket<GP_SERV_COMMAND_MESSAGE>(PChar, 0, MsgStd::WaitLonger);
                }
            }
            else
            {
                PChar->pushPacket<GP_SERV_COMMAND_MESSAGE>(PChar, 0, MsgStd::CannotHere);
            }
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::Unity:
        {
            if (!PChar->PUnityChat)
            {
                PChar->pushPacket<GP_SERV_COMMAND_MESSAGE>(MsgStd::UnityNotParticipating);
                return;
            }

            message::send(ipc::ChatMessageUnity{
                .unityLeaderId = PChar->PUnityChat->getLeader(),
                .senderId      = PChar->id,
                .senderName    = PChar->getName(),
                .message       = rawMessage,
                .zoneId        = PChar->getZone(),
                .gmLevel       = PChar->m_GMlevel,
            });

            roeutils::event(ROE_EVENT::ROE_UNITY_CHAT, PChar, RoeDatagram("unityMessage", rawMessage));

            // TODO: Don't pass around Scheduler& through PSession
            auditUnity(*PSession->scheduler, PChar, rawMessage);
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::LinkshellPvp:
        {
            // Not implemented
            // TODO: Don't pass around Scheduler& through PSession
            auditChat(*PSession->scheduler, PChar, "BALLISTA", rawMessage);
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::AssistJ:
        {
            if (!settings::get<bool>("main.ASSIST_CHANNEL_ENABLED") ||
                !PChar->loc.zone->CanUseMisc(xi::ZoneMisc::Assist) ||
                PChar->aman().isMuted() ||
                !PChar->aman().isAssistChannelEligible())
            {
                // Silently drop the message.
                return;
            }

            PChar->aman().recordLastMessage();
            message::send(ipc::ChatMessageAssist{
                .senderId    = PChar->id,
                .senderName  = PChar->getName(),
                .message     = rawMessage,
                .mentorRank  = PChar->aman().isMentor() ? PChar->aman().getMentorRank() : static_cast<uint8>(0),
                .masteryRank = PChar->aman().getMasteryRank(),
                .gmLevel     = PChar->m_GMlevel,
                .messageType = MESSAGE_JP_ASSIST,
            });

            // TODO: Don't pass around Scheduler& through PSession
            auditChat(*PSession->scheduler, PChar, "ASSISTJ", rawMessage);
        }
        break;
        case GP_CLI_COMMAND_CHAT_STD_KIND::AssistE:
        {
            if (!settings::get<bool>("main.ASSIST_CHANNEL_ENABLED") ||
                !PChar->loc.zone->CanUseMisc(xi::ZoneMisc::Assist) ||
                PChar->aman().isMuted() ||
                !PChar->aman().isAssistChannelEligible())
            {
                // Silently drop the message.
                return;
            }

            PChar->aman().recordLastMessage();
            message::send(ipc::ChatMessageAssist{
                .senderId    = PChar->id,
                .senderName  = PChar->getName(),
                .message     = rawMessage,
                .mentorRank  = PChar->aman().isMentor() ? PChar->aman().getMentorRank() : static_cast<uint8>(0),
                .masteryRank = PChar->aman().getMasteryRank(),
                .gmLevel     = PChar->m_GMlevel,
                .messageType = MESSAGE_NA_ASSIST,
            });

            // TODO: Don't pass around Scheduler& through PSession
            auditChat(*PSession->scheduler, PChar, "ASSISTE", rawMessage);
        }
        break;
    }

    PChar->m_charHistory.chatsSent++;
}
