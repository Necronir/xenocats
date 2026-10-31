class_name SkillData
extends Resource

enum TargetType {
	SINGLE_ENEMY,
	SINGLE_PART,
	ALL_ENEMIES,
	SELF,
	ALLY,
	ALL_ALLIES
}

enum QTEProfile {
	TIMING_BAR,
	MULTI_HIT,
	POWER_CHARGE,
	NONE
}

enum StatusEffect {
	NONE,
	MARK,
	BLEED,
	TAUNT,
	SHIELD,
	STUN,
	CLEANSE,
	SPEED_UP
}

@export var skill_id: StringName = &""
@export var skill_name: String = ""
@export var description: String = ""
@export var target_type: TargetType = TargetType.SINGLE_PART
@export var base_damage: int = 12
@export var shield_amount: int = 0
@export var heal_amount: int = 0
@export var status_effect: StatusEffect = StatusEffect.NONE
@export var status_stacks: int = 0
@export var qte_profile: QTEProfile = QTEProfile.TIMING_BAR
@export var sync_gain: int = 15
@export var ignore_armor: bool = false
@export var triggers_mark_combo: bool = false
@export var preferred_part_slot: int = 0 # 0=BODY, 1=ARMS, 2=LEGS (for enemy AI targeting hint)
@export var dodge_pattern_id: StringName = &""
@export var dodge_patterns: Array[StringName] = []
