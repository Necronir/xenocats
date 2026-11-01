class_name CatMechInstance
extends RefCounted

var cat_id: StringName = &""
var display_name: String = ""
var role_title: String = ""
var instrument_name: String = "Гитара"
var theme_path: String = "res://assets/audio/themes/theme_felix_guitar.wav"
var portrait_prefix: String = "felix"

var body_part: PartInstance = null # Корпус (Core / Body)
var arms_part: PartInstance = null # Руки / Орудия (Arms)
var legs_part: PartInstance = null # Ноги / Шасси (Legs)

# Временные боевые статусы
var shield: int = 0
var taunt_turns: int = 0
var bleed_stacks: int = 0
var stunned: bool = false
var speed_buff_turns: int = 0

static var _emergency_poke_skill: SkillData = null

func _init(p_data: CatMechData = null) -> void:
	if p_data != null:
		cat_id = p_data.cat_id
		display_name = p_data.display_name
		role_title = p_data.role_title
		instrument_name = p_data.instrument_name
		theme_path = p_data.theme_path
		portrait_prefix = p_data.portrait_prefix
		if p_data.default_body != null:
			body_part = PartInstance.new(p_data.default_body)
		if p_data.default_arms != null:
			arms_part = PartInstance.new(p_data.default_arms)
		if p_data.default_legs != null:
			legs_part = PartInstance.new(p_data.default_legs)

func is_alive() -> bool:
	return body_part != null and body_part.current_hp > 0

func get_total_weight() -> int:
	var total: int = 0
	if body_part != null:
		total += body_part.get_weight()
	if arms_part != null:
		total += arms_part.get_weight()
	if legs_part != null:
		total += legs_part.get_weight()
	return total

func get_power_capacity() -> int:
	if body_part != null:
		return body_part.get_power_output()
	return 0

func get_overweight() -> int:
	var cap: int = get_power_capacity()
	if cap <= 0:
		return 0
	return maxi(0, get_total_weight() - cap)

func is_overweight() -> bool:
	return get_overweight() > 0

func get_overweight_penalty_multiplier() -> float:
	var ow: int = get_overweight()
	if ow <= 0:
		return 1.0
	# -30% к скорости за каждую единицу перегруза (ADR-001 / Issue #8, Вариант Б)
	return clampf(1.0 - (float(ow) * 0.3), 0.15, 1.0)

func get_initiative_score() -> int:
	if legs_part == null:
		return 1
	var spd: int = legs_part.get_base_speed()
	if speed_buff_turns > 0:
		spd += 4
	if legs_part.is_broken():
		spd = maxi(1, int(float(spd) * 0.3)) # Штраф 70% скорости при сломанных ногах (ADR-001)
	if is_overweight():
		spd = maxi(1, int(float(spd) * get_overweight_penalty_multiplier()))
	return spd

func get_dodge_speed_multiplier() -> float:
	var mult: float = 1.0
	if legs_part != null and legs_part.is_broken():
		mult = 0.6 # Скорость движения аватара в Dodge Box падает на 40% (ADR-001)
	if is_overweight():
		mult *= get_overweight_penalty_multiplier()
	return maxf(0.15, mult)

func get_part(slot: PartData.PartSlot) -> PartInstance:
	match slot:
		PartData.PartSlot.BODY:
			return body_part
		PartData.PartSlot.ARMS:
			return arms_part
		PartData.PartSlot.LEGS:
			return legs_part
	return body_part

func set_part(slot: PartData.PartSlot, new_part: PartInstance) -> PartInstance:
	var old: PartInstance = get_part(slot)
	match slot:
		PartData.PartSlot.BODY:
			body_part = new_part
		PartData.PartSlot.ARMS:
			arms_part = new_part
		PartData.PartSlot.LEGS:
			legs_part = new_part
	return old

func get_total_current_hp() -> int:
	var total: int = 0
	if body_part != null:
		total += body_part.current_hp
	if arms_part != null:
		total += arms_part.current_hp
	if legs_part != null:
		total += legs_part.current_hp
	return total

func get_total_max_hp() -> int:
	var total: int = 0
	if body_part != null:
		total += body_part.get_max_hp()
	if arms_part != null:
		total += arms_part.get_max_hp()
	if legs_part != null:
		total += legs_part.get_max_hp()
	return total

func get_available_skills() -> Array[SkillData]:
	var result: Array[SkillData] = []
	if arms_part != null and not arms_part.is_broken() and arms_part.data != null:
		for s: SkillData in arms_part.data.skills:
			if s != null:
				result.append(s)
	else:
		# При сломанных руках блокируются орудийные скиллы, остаётся только аварийный тычок (ADR-001)
		result.append(_get_emergency_poke())

	if body_part != null and not body_part.is_broken() and body_part.data != null:
		for s: SkillData in body_part.data.skills:
			if s != null:
				result.append(s)

	if legs_part != null and not legs_part.is_broken() and legs_part.data != null:
		for s: SkillData in legs_part.data.skills:
			if s != null:
				result.append(s)
	return result

static func _get_emergency_poke() -> SkillData:
	if _emergency_poke_skill == null:
		var poke: SkillData = SkillData.new()
		poke.skill_id = &"emergency_poke"
		poke.skill_name = "Аварийный тычок"
		poke.description = "Руки сломаны! Слабый удар искрящим манипулятором."
		poke.target_type = SkillData.TargetType.SINGLE_PART
		poke.base_damage = 5
		poke.qte_profile = SkillData.QTEProfile.TIMING_BAR
		poke.sync_gain = 8
		_emergency_poke_skill = poke
	return _emergency_poke_skill

static func clear_static_cache() -> void:
	_emergency_poke_skill = null

func apply_part_damage(slot: PartData.PartSlot, raw_damage: int, ignore_armor: bool = false) -> Dictionary:
	var target_part: PartInstance = get_part(slot)
	if target_part == null:
		target_part = body_part
	# Если выбранная деталь (Руки или Ноги) уже разрушена, избыточный урон переходит в Корпус
	var actual_slot: PartData.PartSlot = slot
	if target_part.is_broken() and slot != PartData.PartSlot.BODY:
		target_part = body_part
		actual_slot = PartData.PartSlot.BODY

	var remaining: int = raw_damage
	if shield > 0 and not ignore_armor:
		var absorbed: int = mini(shield, remaining)
		shield -= absorbed
		remaining -= absorbed

	var was_broken: bool = target_part.is_broken()
	var dealt: int = 0
	if remaining > 0:
		dealt = target_part.take_damage(remaining, ignore_armor)
	var just_broken: bool = (not was_broken) and target_part.is_broken()
	return {
		"slot": actual_slot,
		"damage": dealt,
		"just_broken": just_broken,
		"unit_ko": not is_alive()
	}

func reset_combat_statuses() -> void:
	shield = 0
	taunt_turns = 0
	bleed_stacks = 0
	stunned = false
	speed_buff_turns = 0

func clear_debuffs() -> void:
	bleed_stacks = 0
	stunned = false

func to_dict() -> Dictionary:
	return {
		"cat_id": String(cat_id),
		"display_name": display_name,
		"role_title": role_title,
		"instrument_name": instrument_name,
		"theme_path": theme_path,
		"portrait_prefix": portrait_prefix,
		"body": body_part.to_dict() if body_part != null else {},
		"arms": arms_part.to_dict() if arms_part != null else {},
		"legs": legs_part.to_dict() if legs_part != null else {}
	}

static func from_dict(d: Dictionary, part_catalog: Dictionary) -> CatMechInstance:
	var inst: CatMechInstance = CatMechInstance.new()
	inst.cat_id = StringName(String(d.get("cat_id", "FELIX")))
	inst.display_name = String(d.get("display_name", "FELIX"))
	inst.role_title = String(d.get("role_title", ""))
	inst.instrument_name = String(d.get("instrument_name", AudioManager.get_character_instrument(inst.cat_id)))
	inst.theme_path = String(d.get("theme_path", AudioManager.get_character_theme_path(inst.cat_id)))
	inst.portrait_prefix = String(d.get("portrait_prefix", "felix"))
	if d.has("body") and d["body"] is Dictionary:
		inst.body_part = PartInstance.from_dict(d["body"] as Dictionary, part_catalog)
	if d.has("arms") and d["arms"] is Dictionary:
		inst.arms_part = PartInstance.from_dict(d["arms"] as Dictionary, part_catalog)
	if d.has("legs") and d["legs"] is Dictionary:
		inst.legs_part = PartInstance.from_dict(d["legs"] as Dictionary, part_catalog)
	return inst
