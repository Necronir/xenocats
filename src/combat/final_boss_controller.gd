class_name FinalBossController
extends RefCounted

## FinalBossController: Архитектура 4-фазного финального босса в Шпиле Бремен-4 (ADR-002, Issue #30)
## Управляет 4 цветовыми фазами (Blue -> Red -> Yellow -> Green),
## проверкой фазовых врат (Phase Gates) с требованием соответствующих тиров слияний,
## сюжетным катапультированием (Scripted Narrative Ejections) при неполном составе группы,
## и финальным 4-нотным QTE-добиванием (Ensemble Finisher: Felix -> Hound -> Mule -> Cock).

enum Phase {
	PHASE_1_BLUE = 1,
	PHASE_2_RED = 2,
	PHASE_3_YELLOW = 3,
	PHASE_4_GREEN = 4
}

var current_phase: Phase = Phase.PHASE_1_BLUE
var segments: Dictionary = {}
var boss_name: String = "Главный Ревизор эфира // Худсовет Бремен-4"
var is_finisher_ready: bool = false
var finisher_beat: int = 0
var finisher_succeeded: bool = false
var is_defeated: bool = false
var is_ejected: bool = false
var ejection_reason: String = ""
var target_story_phase: StoryProgressionData.StoryPhase = StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT

func _init() -> void:
	# Фаза 1: Синий сектор (Уязвим: FELIX / Тир 1+ Слияния)
	segments[1] = BossColoredSegment.new(
		&"segment_blue",
		"Синий резонатор эфира",
		BossColoredSegment.AffinityColor.BLUE,
		150, # HP
		0,   # Shield
		2,   # Armor
		1,   # Required breaking tier (Tier 1 ROBO_CATDOG)
		&"FELIX"
	)
	# Фаза 2: Красный сектор (Уязвим: HOUND / Тир 1+ Слияния)
	segments[2] = BossColoredSegment.new(
		&"segment_red",
		"Красный барабанный глушитель",
		BossColoredSegment.AffinityColor.RED,
		180, # HP
		30,  # Shield
		3,   # Armor
		2,   # Required breaking tier (Tier 2 ROBO_CATDOG_DONKEY)
		&"HOUND"
	)
	# Фаза 3: Жёлтый сектор (Уязвим: MULE / Тир 2+ Слияния)
	segments[3] = BossColoredSegment.new(
		&"segment_yellow",
		"Жёлтый басовый цензор",
		BossColoredSegment.AffinityColor.YELLOW,
		220, # HP
		40,  # Shield
		4,   # Armor
		3,   # Required breaking tier (Tier 3 ROBO_MEGA_PYRAMID)
		&"MULE"
	)
	# Фаза 4: Зелёный сектор (Уязвим: COCK / Тир 3 Слияние)
	segments[4] = BossColoredSegment.new(
		&"segment_green",
		"Зелёный синтезаторный фильтр",
		BossColoredSegment.AffinityColor.GREEN,
		260, # HP
		50,  # Shield
		5,   # Armor
		3,   # Required breaking tier (Tier 3 ROBO_MEGA_PYRAMID)
		&"COCK"
	)

func get_current_segment() -> BossColoredSegment:
	return segments.get(int(current_phase), segments[1]) as BossColoredSegment

func get_current_affinity_color() -> BossColoredSegment.AffinityColor:
	var seg: BossColoredSegment = get_current_segment()
	return seg.affinity_color if seg != null else BossColoredSegment.AffinityColor.BLUE

func get_current_hp() -> int:
	var seg: BossColoredSegment = get_current_segment()
	return seg.current_hp if seg != null else 0

func get_current_max_hp() -> int:
	var seg: BossColoredSegment = get_current_segment()
	return seg.max_hp if seg != null else 100

func get_total_current_hp() -> int:
	var total: int = 0
	for seg: BossColoredSegment in segments.values():
		if seg != null:
			total += seg.current_hp
	return total

func get_total_max_hp() -> int:
	var total: int = 0
	for seg: BossColoredSegment in segments.values():
		if seg != null:
			total += seg.max_hp
	return total

func check_phase_gate(
	from_phase: int,
	party_members: Array[StringName],
	fusion_tier: int = 0
) -> Dictionary:
	match from_phase:
		1:
			# Фаза 1 -> 2: Требует Тир 1 (ROBO_CATDOG) и наличие HOUND
			if not party_members.has(&"HOUND"):
				return {
					"allowed": false,
					"rejected": true,
					"reason": "Музыка слишком слабая. Прослушивание не пройдено! Вон из эфира!",
					"floating_text": "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!",
					"sfx": "dissonance",
					"target_story_phase": StoryProgressionData.StoryPhase.CYCLE_1_DUO
				}
			if fusion_tier < 1:
				return {
					"allowed": false,
					"rejected": false,
					"requires_tier": 1,
					"reason": "Для разрушения Синей части требуется слияние Робокотопёс (Тир 1)!",
					"floating_text": "ТРЕБУЕТСЯ СЛИЯНИЕ ТИР 1!",
					"sfx": "dissonance"
				}
			return {
				"allowed": true,
				"rejected": false,
				"next_phase": 2
			}
		2:
			# Фаза 2 -> 3: Требует Тир 2 (ROBO_CATDOG_DONKEY) и наличие MULE
			if not party_members.has(&"MULE"):
				return {
					"allowed": false,
					"rejected": true,
					"reason": "Одними гитарами и барабаном меня не удивить! Вон из эфира!",
					"floating_text": "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!",
					"sfx": "dissonance",
					"target_story_phase": StoryProgressionData.StoryPhase.CYCLE_2_TRIO
				}
			if fusion_tier < 2:
				return {
					"allowed": false,
					"rejected": false,
					"requires_tier": 2,
					"reason": "Для разрушения Красной части требуется слияние Робокотопсоосёл (Тир 2)!",
					"floating_text": "ТРЕБУЕТСЯ СЛИЯНИЕ ТИР 2!",
					"sfx": "dissonance"
				}
			return {
				"allowed": true,
				"rejected": false,
				"next_phase": 3
			}
		3:
			# Фаза 3 -> 4: Требует Тир 3 (ROBO_MEGA_PYRAMID) и наличие COCK
			if not party_members.has(&"COCK"):
				return {
					"allowed": false,
					"rejected": true,
					"reason": "Без синтезатора и электронных помех эфир не пробить! Вон из эфира!",
					"floating_text": "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!",
					"sfx": "dissonance",
					"target_story_phase": StoryProgressionData.StoryPhase.CYCLE_3_QUARTET
				}
			if fusion_tier < 3:
				return {
					"allowed": false,
					"rejected": false,
					"requires_tier": 3,
					"reason": "Для разрушения Жёлтой части требуется Мега-Пирамида (Тир 3)!",
					"floating_text": "ТРЕБУЕТСЯ МЕГА-ПИРАМИДА!",
					"sfx": "dissonance"
				}
			return {
				"allowed": true,
				"rejected": false,
				"next_phase": 4
			}
		_:
			return {
				"allowed": true,
				"rejected": false,
				"next_phase": from_phase
			}

func apply_attack(
	raw_damage: int,
	hero_id: StringName,
	fusion_tier: int = 0,
	ignore_armor: bool = false,
	party_members: Array[StringName] = []
) -> Dictionary:
	if is_defeated:
		return {
			"damage": 0,
			"immune": true,
			"floating_text": "РЕВИЗОР ПОВЕРЖЕН",
			"sfx": "hit",
			"is_broken": true
		}

	var seg: BossColoredSegment = get_current_segment()
	if seg == null:
		return {
			"damage": 0,
			"immune": true,
			"floating_text": "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!",
			"sfx": "dissonance"
		}

	# Если фаза 4 на пороге добивания (<= 1% HP), ждем QTE Finisher
	if is_finisher_ready:
		return {
			"damage": 0,
			"immune": true,
			"floating_text": "ГОТОВ К ФИНАЛЬНОМУ АККОРДУ!",
			"sfx": "dissonance",
			"finisher_ready": true
		}

	var res: Dictionary = seg.apply_damage(raw_damage, hero_id, fusion_tier, ignore_armor)

	# Если атака не совпала по цвету/слиянию
	if bool(res.get("immune", false)):
		return res

	# Если сегмент разрушен текущей атакой
	if bool(res.get("just_broken", false)) or seg.current_hp <= 0:
		if int(current_phase) < int(Phase.PHASE_4_GREEN):
			var gate_check: Dictionary = check_phase_gate(int(current_phase), party_members, fusion_tier)
			if bool(gate_check.get("rejected", false)):
				is_ejected = true
				ejection_reason = String(gate_check["reason"])
				target_story_phase = gate_check["target_story_phase"] as StoryProgressionData.StoryPhase
				res["ejected"] = true
				res["ejection_reason"] = ejection_reason
				res["target_story_phase"] = target_story_phase
				res["floating_text"] = String(gate_check["floating_text"])
				res["sfx"] = String(gate_check["sfx"])
				return res
			elif not bool(gate_check.get("allowed", false)):
				# Требуется слияние соответствующего тира для окончательного пробития
				seg.current_hp = 1
				seg.is_broken = false
				res["gate_blocked"] = true
				res["required_tier"] = gate_check.get("requires_tier", 1)
				res["floating_text"] = String(gate_check["floating_text"])
				res["sfx"] = "dissonance"
				return res
			else:
				# Переход на следующую фазу
				var next_p: int = int(gate_check["next_phase"])
				current_phase = next_p as Phase
				res["phase_transition"] = true
				res["new_phase"] = next_p
				res["new_segment"] = get_current_segment()
				res["floating_text"] = "ФАЗА " + str(next_p) + ": " + get_current_segment().segment_name + "!"
				return res
		else:
			# 4-я фаза сломана -> активируется QTE Finisher!
			is_finisher_ready = true
			seg.current_hp = 1
			seg.is_broken = false
			res["finisher_triggered"] = true
			res["floating_text"] = "ФИНАЛЬНЫЙ АККОРД: АНСАМБЛЬ!"
			return res

	# На 4-й фазе: если HP <= 1% от max_hp, также переключаем в Finisher
	if current_phase == Phase.PHASE_4_GREEN and seg.current_hp <= maxi(1, int(float(seg.max_hp) * 0.01)):
		is_finisher_ready = true
		seg.current_hp = 1
		res["finisher_triggered"] = true
		res["floating_text"] = "ФИНАЛЬНЫЙ АККОРД: АНСАМБЛЬ!"

	return res

static func get_finisher_beat_hero(beat: int) -> StringName:
	match beat:
		1: return &"FELIX"
		2: return &"HOUND"
		3: return &"MULE"
		4: return &"COCK"
	return &"FELIX"

static func get_finisher_beat_instrument(beat: int) -> String:
	match beat:
		1: return "Соло-гитара"
		2: return "Ударные"
		3: return "Бас-партия"
		4: return "Синтезатор"
	return "Гитара"

static func get_finisher_beat_color(beat: int) -> Color:
	match beat:
		1: return Color(0.2, 0.7, 1.0)
		2: return Color(1.0, 0.3, 0.3)
		3: return Color(1.0, 0.85, 0.2)
		4: return Color(0.3, 0.95, 0.4)
	return Color.WHITE

func start_finisher() -> void:
	is_finisher_ready = true
	finisher_beat = 0
	finisher_succeeded = false

func execute_finisher_beat(beat: int, timing_success: bool = true) -> Dictionary:
	if not is_finisher_ready:
		return {"success": false, "error": "Finisher not ready"}

	var expected_beat: int = finisher_beat + 1
	if beat != expected_beat:
		return {"success": false, "error": "Incorrect beat sequence order", "expected": expected_beat}

	var hero: StringName = get_finisher_beat_hero(beat)
	var inst: String = get_finisher_beat_instrument(beat)
	var col: Color = get_finisher_beat_color(beat)

	if not timing_success:
		return {
			"success": false,
			"beat": beat,
			"hero": hero,
			"instrument": inst,
			"floating_text": "СБОЙ РИТМА! ПОВТОРИТЕ НОТУ!",
			"color": Color(1.0, 0.4, 0.4)
		}

	finisher_beat = beat
	if beat >= 4:
		finisher_succeeded = true
		is_defeated = true
		var cur_seg: BossColoredSegment = get_current_segment()
		if cur_seg != null:
			cur_seg.current_hp = 0
			cur_seg.is_broken = true
		return {
			"success": true,
			"beat": beat,
			"hero": hero,
			"instrument": inst,
			"color": col,
			"all_completed": true,
			"vfx_triggered": true,
			"floating_text": "ФИНАЛЬНЫЙ АККОРД: РЕВИЗОР ЭФИРА УНИЧТОЖЕН!"
		}

	return {
		"success": true,
		"beat": beat,
		"hero": hero,
		"instrument": inst,
		"color": col,
		"all_completed": false,
		"floating_text": "НОТА " + str(beat) + "/4: " + inst.to_upper() + " В РИТМЕ!"
	}

func trigger_destruction_vfx() -> Dictionary:
	return {
		"screenshake_amplitude": 16.0,
		"screenshake_duration": 1.5,
		"spark_colors": [
			Color(0.2, 0.7, 1.0),
			Color(1.0, 0.3, 0.3),
			Color(1.0, 0.85, 0.2),
			Color(0.3, 0.95, 0.4)
		],
		"sfx_main": "part_break",
		"sfx_secondary": "pyramid_undock",
		"theme": "ENSEMBLE"
	}
