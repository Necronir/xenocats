class_name CombatFusionController
extends RefCounted

## CombatFusionController: Управление тирами слияний (ADR-002 Section 3.2, Issue #29 & #30)
## Предоставляет выбор тира слияния:
## - Тир 1 (50% шкалы): Робокотопёс (ROBO_CATDOG) -> Синий + Красный урон
## - Тир 2 (75% шкалы): Робокотопсоосёл (ROBO_CATDOG_DONKEY) -> Синий + Красный + Жёлтый урон
## - Тир 3 (100% шкалы): Мега-Пирамида (ROBO_MEGA_PYRAMID) -> Спектральный урон по всем 4 цветам

enum FusionTier {
	NONE = 0,
	ROBO_CATDOG = 1,          # 50% шкалы
	ROBO_CATDOG_DONKEY = 2,   # 75% шкалы
	ROBO_MEGA_PYRAMID = 3     # 100% шкалы
}

var current_tier: FusionTier = FusionTier.NONE
var turns_remaining: int = 0

func get_tier_sync_cost(tier: FusionTier) -> int:
	match tier:
		FusionTier.ROBO_CATDOG:
			return 50
		FusionTier.ROBO_CATDOG_DONKEY:
			return 75
		FusionTier.ROBO_MEGA_PYRAMID:
			return 100
	return 0

func can_activate_tier(tier: FusionTier, sync_gauge: int, party_ids: Array[StringName]) -> bool:
	if tier == FusionTier.NONE:
		return false
	if sync_gauge < get_tier_sync_cost(tier):
		return false
	match tier:
		FusionTier.ROBO_CATDOG:
			return party_ids.has(&"FELIX") and party_ids.has(&"HOUND")
		FusionTier.ROBO_CATDOG_DONKEY:
			return party_ids.has(&"FELIX") and party_ids.has(&"HOUND") and party_ids.has(&"MULE")
		FusionTier.ROBO_MEGA_PYRAMID:
			return party_ids.has(&"FELIX") and party_ids.has(&"HOUND") and party_ids.has(&"MULE") and party_ids.has(&"COCK")
	return false

func activate_tier(tier: FusionTier, sync_gauge: int, party_ids: Array[StringName]) -> bool:
	if not can_activate_tier(tier, sync_gauge, party_ids):
		return false
	current_tier = tier
	turns_remaining = 3 if tier == FusionTier.ROBO_MEGA_PYRAMID else 2
	return true

func deactivate() -> void:
	current_tier = FusionTier.NONE
	turns_remaining = 0

func is_active() -> bool:
	return current_tier != FusionTier.NONE

static func get_tier_name(tier: FusionTier) -> String:
	match tier:
		FusionTier.ROBO_CATDOG:
			return "Слияние: Робокотопёс (Тир 1)"
		FusionTier.ROBO_CATDOG_DONKEY:
			return "Слияние: Робокотопсоосёл (Тир 2)"
		FusionTier.ROBO_MEGA_PYRAMID:
			return "Слияние: Мега-Пирамида (Тир 3)"
		_:
			return "Одиночные атаки"

static func get_constituent_members(tier: FusionTier) -> Array[StringName]:
	return BossColoredSegment.get_fusion_members(int(tier))

static func get_constituent_colors(tier: FusionTier) -> Array[BossColoredSegment.AffinityColor]:
	return BossColoredSegment.get_fusion_colors(int(tier))
