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

#include "interrupts.h"

#include "packets/s2c/0x028_battle2.h"
#include "petskill.h"
#include "utils/trustutils.h"

namespace ActionInterrupts
{
namespace
{
void LogInterruptPacket(CBattleEntity* PEntity, action_t& action, const CBattleEntity* PTarget, const char* source)
{
    trustutils::LogTrustActionPacket(PEntity, action, PTarget, source);
}
} // namespace

void AvatarOutOfRange(CBattleEntity* PAvatar, const CPetSkill* PSkill, const CBattleEntity* PTarget)
{
    // Avatars using BP against an enemy out of range use a specific set of BATTLE2 packets:
    // - 1. MAGIC_FINISH with Too Far Away message
    // - 2. SKILL_USE with SKILL_INTERRUPT animation and no message

    // 1. Build the MAGIC_FINISH packet
    auto magicFinishAction = action_t{
        .actorId    = PAvatar->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .param     = PSkill->getMobSkillID() > 0 ? PSkill->getMobSkillID() : PSkill->getID(),
                        .messageID = MsgBasic::TooFarAwayRed,
                    },
                },
            },
        },
    };

    // 2. Skill start packet with skill interrupt FourCC
    auto interruptAction = action_t{
        .actorId    = PAvatar->id,
        .actiontype = ActionCategory::SkillStart,
        .actionid   = static_cast<uint32_t>(FourCC::SkillInterrupt),
        .targets    = {
            {
                .actorId = PAvatar->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                    },
                },
            },
        }
    };

    LogInterruptPacket(PAvatar, magicFinishAction, PTarget, "interrupt_avatar_out_of_range");
    PAvatar->loc.zone->PushPacket(PAvatar, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
    LogInterruptPacket(PAvatar, interruptAction, PTarget, "interrupt_avatar_out_of_range");
    PAvatar->loc.zone->PushPacket(PAvatar, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(interruptAction));
}

void WyvernOutOfRange(CBattleEntity* PWyvern, const CPetSkill* PSkill, const CBattleEntity* PTarget)
{
    // Wyverns using breaths on an out-of-range entity:
    // - 1. MAGIC_FINISH
    // - 2. SKILL_USE with SKILL_INTERRUPT

    // 1. Build the MAGIC_FINISH packet
    auto magicFinishAction = action_t{
        .actorId    = PWyvern->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .resolution = ActionResolution::Miss,
                        .animation  = ActionAnimation::SkillInterrupt,
                        .param      = PSkill->getMobSkillID() > 0 ? PSkill->getMobSkillID() : PSkill->getID(),
                        .messageID  = MsgBasic::TooFarAwayRed,
                    },
                },
            },
        },
    };

    // 2. Build the final SKILL_USE
    auto interruptAction = action_t{
        .actorId    = PWyvern->id,
        .actiontype = ActionCategory::SkillStart,
        .actionid   = static_cast<uint32_t>(FourCC::SkillInterrupt),
        .targets    = {
            {
                .actorId = PWyvern->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PWyvern, magicFinishAction, PTarget, "interrupt_wyvern_out_of_range");
    PWyvern->loc.zone->PushPacket(PWyvern, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
    LogInterruptPacket(PWyvern, interruptAction, PTarget, "interrupt_wyvern_out_of_range");
    PWyvern->loc.zone->PushPacket(PWyvern, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(interruptAction));
}

void WyvernSkillReady(CBattleEntity* PWyvern)
{
    auto skillUseAction = action_t{
        .actorId    = PWyvern->id,
        .actiontype = ActionCategory::SkillStart,
        .actionid   = static_cast<uint32_t>(FourCC::SkillInterrupt),
        .targets    = {
            {
                .actorId = PWyvern->id,
                .results = {
                    {
                        // Empty result
                    },
                },
            },
        }
    };

    LogInterruptPacket(PWyvern, skillUseAction, PWyvern, "interrupt_wyvern_skill_ready");
    PWyvern->loc.zone->PushPacket(PWyvern, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(skillUseAction));
}

void AbilityInterrupt(CBattleEntity* PEntity)
{
    auto interruptAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::SkillStart,
        .actionid   = static_cast<uint32_t>(FourCC::SkillInterrupt),
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        // Empty result
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, interruptAction, PEntity, "interrupt_ability");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(interruptAction));
}

void RangedInterrupt(CBattleEntity* PEntity)
{
    auto interruptAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::RangedStart,
        .actionid   = static_cast<uint32_t>(FourCC::RangedInterrupt),
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, interruptAction, PEntity, "interrupt_ranged");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(interruptAction));
}

void MobSkillNoTargetInRange(CBattleEntity* PEntity)
{
    auto magicFinishAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::NoTargetInAreaOfEffect,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishAction, PEntity, "interrupt_mobskill_no_target");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
}

void MobSkillOutOfRange(CBattleEntity* PEntity, const CBattleEntity* PTarget)
{
    auto magicFinishAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::TooFarAway,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishAction, PTarget, "interrupt_mobskill_out_of_range");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
}

void WeaponSkillOutOfRange(CBattleEntity* PEntity, const CBattleEntity* PTarget)
{
    auto magicFinishAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::TooFarAway,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishAction, PTarget, "interrupt_weaponskill_out_of_range");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
}

void RangedParalyzed(CBattleEntity* PEntity)
{
    auto paralyzeAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsParalyzed2,
                    },
                },
            },
        },
    };

    RangedInterrupt(PEntity);
    LogInterruptPacket(PEntity, paralyzeAction, PEntity, "interrupt_ranged_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(paralyzeAction));
}

void MagicInterrupt(CBattleEntity* PEntity, CSpell* PSpell)
{
    auto interruptAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicStart,
        .actionid   = static_cast<uint32_t>(PSpell->getFourCC(true)),
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .param = static_cast<int32_t>(PSpell->getID()),
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, interruptAction, PEntity, "interrupt_magic");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(interruptAction));
}

void MagicParalyzed(CBattleEntity* PEntity, CSpell* PSpell, const CBattleEntity* PTarget)
{
    auto interruptedAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .actionid   = static_cast<uint16>(PSpell->getID()),
        .recast     = 2s,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsParalyzed2,
                    },
                },
            },
        }
    };

    auto stopCastAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicStart,
        .actionid   = static_cast<uint32_t>(PSpell->getFourCC(true)),
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .param     = static_cast<int32_t>(PSpell->getID()),
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, interruptedAction, PTarget, "interrupt_magic_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(interruptedAction));
    LogInterruptPacket(PEntity, stopCastAction, PTarget, "interrupt_magic_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(stopCastAction));
}

void MagicIntimidated(CBattleEntity* PEntity, CSpell* PSpell, const CBattleEntity* PTarget)
{
    auto magicFinishAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .actionid   = static_cast<uint32_t>(PSpell->getID()),
        .recast     = 2s,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsIntimidated,
                    },
                },
            },
        },
    };

    auto magicInterrupt = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicStart,
        .actionid   = static_cast<uint32_t>(PSpell->getFourCC(true)),
        .recast     = 2s,
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .param     = static_cast<int32_t>(PSpell->getID()),
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishAction, PTarget, "interrupt_magic_intimidated");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
    LogInterruptPacket(PEntity, magicInterrupt, PTarget, "interrupt_magic_intimidated");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicInterrupt));
}

void AttackParalyzed(CBattleEntity* PEntity, const CBattleEntity* PTarget)
{
    auto magicFinishSelfAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsParalyzed2,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishSelfAction, PTarget, "interrupt_attack_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishSelfAction));
}

void AttackIntimidated(CBattleEntity* PEntity, const CBattleEntity* PTarget)
{
    auto magicFinishAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsIntimidated,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishAction, PTarget, "interrupt_attack_intimidated");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
}

void AbilityParalyzed(CBattleEntity* PEntity, const CBattleEntity* PTarget)
{
    // 1. Generic MagicFinish with Paralyzed message
    auto magicFinishSelfAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsParalyzed2,
                    },
                },
            },
        },
    };

    // 2. Generic MagicFinish with Paralyzed message
    auto magicFinishTargetAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsParalyzed2,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishSelfAction, PTarget, "interrupt_ability_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishSelfAction));
    LogInterruptPacket(PEntity, magicFinishTargetAction, PTarget, "interrupt_ability_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishTargetAction));
}

void ItemInterrupt(CBattleEntity* PEntity)
{
    auto itemStartAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::ItemStart,
        .actionid   = static_cast<uint32_t>(FourCC::ItemInterrupt),
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        // Empty result
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, itemStartAction, PEntity, "interrupt_item");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(itemStartAction));
}

void ItemParalyzed(CBattleEntity* PEntity, const CBattleEntity* PTarget)
{
    // 1. Generic MagicFinish with Paralyzed message
    auto magicFinishAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsParalyzed2,
                    },
                },
            },
        },
    };

    // 2. ItemStart with cancel animation
    auto itemStartAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::ItemStart,
        .actionid   = static_cast<uint32_t>(FourCC::ItemInterrupt),
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishAction, PTarget, "interrupt_item_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
    LogInterruptPacket(PEntity, itemStartAction, PTarget, "interrupt_item_paralyzed");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(itemStartAction));
}

void ItemIntimidated(CBattleEntity* PEntity, const CBattleEntity* PTarget)
{
    // 1. Generic MagicFinish with Paralyzed message
    auto magicFinishAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::MagicFinish,
        .targets    = {
            {
                .actorId = PTarget->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                        .messageID = MsgBasic::IsIntimidated,
                    },
                },
            },
        },
    };

    // 2. ItemStart with cancel animation
    auto itemStartAction = action_t{
        .actorId    = PEntity->id,
        .actiontype = ActionCategory::ItemStart,
        .actionid   = static_cast<uint32_t>(FourCC::ItemInterrupt),
        .targets    = {
            {
                .actorId = PEntity->id,
                .results = {
                    {
                        .animation = ActionAnimation::SkillInterrupt,
                    },
                },
            },
        },
    };

    LogInterruptPacket(PEntity, magicFinishAction, PTarget, "interrupt_item_intimidated");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(magicFinishAction));
    LogInterruptPacket(PEntity, itemStartAction, PTarget, "interrupt_item_intimidated");
    PEntity->loc.zone->PushPacket(PEntity, CHAR_INRANGE_SELF, std::make_unique<GP_SERV_COMMAND_BATTLE2>(itemStartAction));
}

}; // namespace ActionInterrupts
