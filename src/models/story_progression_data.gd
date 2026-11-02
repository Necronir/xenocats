class_name StoryProgressionData
extends Resource

## StoryProgressionData: Управление мета-прогрессией 4 сюжетных циклов забегов (ADR-002 Section 3.1, Issue #28)

enum StoryPhase {
	CYCLE_0_SOLO_CAT = 0,    # Забег 0: Только Кот, укороченный Синий биом
	CYCLE_1_DUO = 1,         # Забег 1: Кот + Пёс, Красный -> Синий
	CYCLE_2_TRIO = 2,        # Забег 2: Кот + Пёс + Осёл, Жёлтый -> Красный -> Синий
	CYCLE_3_QUARTET = 3,     # Забег 3: Полный квартет, Зелёный -> Жёлтый -> Красный -> Синий
	COMPLETED = 4            # Финал пройден, доступен свободный выбор
}

@export var current_phase: StoryPhase = StoryPhase.CYCLE_0_SOLO_CAT
@export var unlocked_party_members: Array[StringName] = [&"FELIX"]
@export var unlocked_fusion_tiers: Array[int] = [0]
@export var seen_boomer_dialog: bool = false
@export var player_is_boomer: bool = false
@export var concert_hall_liberated: bool = false

static func get_default_party_for_phase(phase: StoryPhase) -> Array[StringName]:
	match phase:
		StoryPhase.CYCLE_0_SOLO_CAT:
			return [&"FELIX"]
		StoryPhase.CYCLE_1_DUO:
			return [&"FELIX", &"HOUND"]
		StoryPhase.CYCLE_2_TRIO:
			return [&"FELIX", &"HOUND", &"MULE"]
		StoryPhase.CYCLE_3_QUARTET, StoryPhase.COMPLETED:
			return [&"FELIX", &"HOUND", &"MULE", &"COCK"]
	return [&"FELIX"]

static func get_default_fusion_tiers_for_phase(phase: StoryPhase) -> Array[int]:
	match phase:
		StoryPhase.CYCLE_0_SOLO_CAT:
			return [0]
		StoryPhase.CYCLE_1_DUO:
			return [0, 1]
		StoryPhase.CYCLE_2_TRIO:
			return [0, 1, 2]
		StoryPhase.CYCLE_3_QUARTET, StoryPhase.COMPLETED:
			return [0, 1, 2, 3]
	return [0]

func set_phase(phase: StoryPhase, sync_defaults: bool = true) -> void:
	current_phase = phase
	if sync_defaults:
		unlocked_party_members = get_default_party_for_phase(phase).duplicate()
		unlocked_fusion_tiers = get_default_fusion_tiers_for_phase(phase).duplicate()
	else:
		var default_members: Array[StringName] = get_default_party_for_phase(phase)
		for m: StringName in default_members:
			if not unlocked_party_members.has(m):
				unlocked_party_members.append(m)
		var default_tiers: Array[int] = get_default_fusion_tiers_for_phase(phase)
		for t: int in default_tiers:
			if not unlocked_fusion_tiers.has(t):
				unlocked_fusion_tiers.append(t)

func advance_phase() -> bool:
	if int(current_phase) < int(StoryPhase.COMPLETED):
		set_phase((int(current_phase) + 1) as StoryPhase)
		return true
	return false

func unlock_party_member(member_id: StringName) -> bool:
	if unlocked_party_members.has(member_id):
		return false
	unlocked_party_members.append(member_id)
	_sync_fusion_tiers_from_members()
	return true

func _sync_fusion_tiers_from_members() -> void:
	if not unlocked_fusion_tiers.has(0):
		unlocked_fusion_tiers.append(0)
	if unlocked_party_members.has(&"FELIX") and unlocked_party_members.has(&"HOUND"):
		if not unlocked_fusion_tiers.has(1):
			unlocked_fusion_tiers.append(1)
	if unlocked_party_members.has(&"MULE"):
		if not unlocked_fusion_tiers.has(2):
			unlocked_fusion_tiers.append(2)
	if unlocked_party_members.has(&"COCK"):
		if not unlocked_fusion_tiers.has(3):
			unlocked_fusion_tiers.append(3)

func unlock_fusion_tier(tier: int) -> bool:
	if unlocked_fusion_tiers.has(tier):
		return false
	unlocked_fusion_tiers.append(tier)
	return true

func reset() -> void:
	current_phase = StoryPhase.CYCLE_0_SOLO_CAT
	unlocked_party_members = [&"FELIX"]
	unlocked_fusion_tiers = [0]
	seen_boomer_dialog = false
	player_is_boomer = false
	concert_hall_liberated = false

func to_dict() -> Dictionary:
	var members: Array[String] = []
	for m: StringName in unlocked_party_members:
		members.append(String(m))
	var tiers: Array[int] = []
	for t: int in unlocked_fusion_tiers:
		tiers.append(int(t))
	return {
		"current_phase": int(current_phase),
		"unlocked_party_members": members,
		"unlocked_fusion_tiers": tiers,
		"seen_boomer_dialog": seen_boomer_dialog,
		"player_is_boomer": player_is_boomer,
		"concert_hall_liberated": concert_hall_liberated
	}

func from_dict(d: Dictionary) -> void:
	current_phase = int(d.get("current_phase", StoryPhase.CYCLE_0_SOLO_CAT)) as StoryPhase
	unlocked_party_members.clear()
	if d.has("unlocked_party_members") and d["unlocked_party_members"] is Array:
		for m: Variant in d["unlocked_party_members"]:
			var sname: StringName = StringName(String(m))
			if not unlocked_party_members.has(sname):
				unlocked_party_members.append(sname)
	if unlocked_party_members.is_empty():
		unlocked_party_members.append(&"FELIX")

	unlocked_fusion_tiers.clear()
	if d.has("unlocked_fusion_tiers") and d["unlocked_fusion_tiers"] is Array:
		for t: Variant in d["unlocked_fusion_tiers"]:
			var ti: int = int(t)
			if not unlocked_fusion_tiers.has(ti):
				unlocked_fusion_tiers.append(ti)
	if unlocked_fusion_tiers.is_empty():
		unlocked_fusion_tiers.append(0)

	seen_boomer_dialog = bool(d.get("seen_boomer_dialog", false))
	player_is_boomer = bool(d.get("player_is_boomer", false))
	concert_hall_liberated = bool(d.get("concert_hall_liberated", false))
