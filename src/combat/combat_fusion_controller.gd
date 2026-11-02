class_name CombatFusionController
extends RefCounted

## CombatFusionController: Управление тирами слияний (ADR-002 Section 3.2, Issue #29 & #30)
## Предоставляет гибкий выбор тира слияния:
## - Тир 1 (50% шкалы): Робокотопёс (ROBO_CATDOG) -> Кот + Пёс (Быстрый комбо-мех, кровотечение, Синий + Красный урон)
## - Тир 2 (75% шкалы): Робокотопсоосёл (ROBO_CATDOG_DONKEY) -> + Осёл (Тяжёлая броня +60%, провокация, сейсмический Синий/Красный/Жёлтый урон)
## - Тир 3 (100% шкалы): Мега-Пирамида (ROBO_MEGA_PYRAMID) -> Полный квартет (Статус-иммунитет, универсальный спектральный урон по всем 4 цветам, добивание)

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

func get_tier_duration(tier: FusionTier) -> int:
	match tier:
		FusionTier.ROBO_MEGA_PYRAMID:
			return 3
		FusionTier.ROBO_CATDOG, FusionTier.ROBO_CATDOG_DONKEY:
			return 2
	return 0

func is_tier_unlocked(tier: FusionTier) -> bool:
	if tier == FusionTier.NONE:
		return false
	if Engine.has_singleton("SaveManager"):
		var sm: Object = Engine.get_singleton("SaveManager")
		if sm != null and sm.has_method("is_fusion_tier_unlocked"):
			return bool(sm.call("is_fusion_tier_unlocked", int(tier)))
	# Fallback directly to global SaveManager if available
	if is_instance_valid(SaveManager) and SaveManager.story_progression != null:
		return SaveManager.is_fusion_tier_unlocked(int(tier))
	return true

func are_members_alive(tier: FusionTier, alive_party_ids: Array[StringName]) -> bool:
	match tier:
		FusionTier.ROBO_CATDOG:
			return alive_party_ids.has(&"FELIX") and alive_party_ids.has(&"HOUND")
		FusionTier.ROBO_CATDOG_DONKEY:
			return alive_party_ids.has(&"FELIX") and alive_party_ids.has(&"HOUND") and alive_party_ids.has(&"MULE")
		FusionTier.ROBO_MEGA_PYRAMID:
			return alive_party_ids.has(&"FELIX") and alive_party_ids.has(&"HOUND") and alive_party_ids.has(&"MULE") and alive_party_ids.has(&"COCK")
	return false

func is_tier_available(tier: FusionTier, alive_party_ids: Array[StringName]) -> bool:
	return is_tier_unlocked(tier) and are_members_alive(tier, alive_party_ids)

func get_available_tiers(alive_party_ids: Array[StringName]) -> Array[FusionTier]:
	var result: Array[FusionTier] = []
	for t: FusionTier in [FusionTier.ROBO_CATDOG, FusionTier.ROBO_CATDOG_DONKEY, FusionTier.ROBO_MEGA_PYRAMID]:
		if is_tier_available(t, alive_party_ids):
			result.append(t)
	return result

func can_activate_tier(tier: FusionTier, sync_gauge: int, party_ids: Array[StringName]) -> bool:
	if tier == FusionTier.NONE:
		return false
	if sync_gauge < get_tier_sync_cost(tier):
		return false
	if not are_members_alive(tier, party_ids):
		return false
	if not is_tier_unlocked(tier):
		return false
	return true

func activate_tier(tier: FusionTier, sync_gauge: int, party_ids: Array[StringName]) -> bool:
	if not can_activate_tier(tier, sync_gauge, party_ids):
		return false
	current_tier = tier
	turns_remaining = get_tier_duration(tier)
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

static func get_tier_title(tier: FusionTier) -> String:
	match tier:
		FusionTier.ROBO_CATDOG:
			return "РОБОКОТОПЁС (ТИР 1)"
		FusionTier.ROBO_CATDOG_DONKEY:
			return "РОБОКОТОПСООСЁЛ (ТИР 2)"
		FusionTier.ROBO_MEGA_PYRAMID:
			return "МЕГА-ПИРАМИДА (ТИР 3)"
		_:
			return "ТОТЕМ «ПИРАМИДА БРЕМЕНА»"

static func get_tier_tooltip(tier: FusionTier) -> String:
	match tier:
		FusionTier.ROBO_CATDOG:
			return "Робокотопёс [Кот + Пёс]: Быстрый комбо-мех, кровотечение, двойной Синий/Красный урон. Длительность: 2 хода."
		FusionTier.ROBO_CATDOG_DONKEY:
			return "Робокотопсоосёл [+ Осёл]: Тяжёлая броня (+60%), провокация, сейсмический Синий/Красный/Жёлтый урон. Длительность: 2 хода."
		FusionTier.ROBO_MEGA_PYRAMID:
			return "Робопетухокотопсоосёл [Полный квартет]: Абсолютный статус-иммунитет, универсальный спектральный урон (все 4 цвета), командное добивание! Длительность: 3 хода."
		_:
			return ""

static func get_constituent_members(tier: FusionTier) -> Array[StringName]:
	return BossColoredSegment.get_fusion_members(int(tier))

static func get_constituent_colors(tier: FusionTier) -> Array[BossColoredSegment.AffinityColor]:
	return BossColoredSegment.get_fusion_colors(int(tier))

static func get_music_tier(tier: FusionTier) -> int:
	match tier:
		FusionTier.ROBO_CATDOG:
			return 2
		FusionTier.ROBO_CATDOG_DONKEY:
			return 3
		FusionTier.ROBO_MEGA_PYRAMID:
			return 4
	return 4
