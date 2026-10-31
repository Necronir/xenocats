class_name EnemyInstance
extends RefCounted

var data: EnemyData = null
var current_hp: int = 60

# Модульные детали (только для Элиток и Боссов: data.is_modular == true)
var body_part: PartInstance = null
var arms_part: PartInstance = null
var legs_part: PartInstance = null

# Боевые статусы
var marked: bool = false
var bleed_stacks: int = 0
var stunned: bool = false
var shield: int = 0

func _init(p_data: EnemyData = null) -> void:
	data = p_data
	if data != null:
		if data.is_modular:
			if data.body_part != null:
				body_part = PartInstance.new(data.body_part)
			if data.arms_part != null:
				arms_part = PartInstance.new(data.arms_part)
			if data.legs_part != null:
				legs_part = PartInstance.new(data.legs_part)
			current_hp = body_part.current_hp if body_part != null else data.max_hp
		else:
			current_hp = data.max_hp

func is_modular() -> bool:
	return data != null and data.is_modular

func is_alive() -> bool:
	if is_modular():
		return body_part != null and body_part.current_hp > 0
	return current_hp > 0

func get_initiative_score() -> int:
	if data == null:
		return 5
	if is_modular() and legs_part != null:
		if legs_part.is_broken():
			return maxi(1, int(float(legs_part.get_base_speed()) * 0.3))
		return legs_part.get_base_speed()
	return data.speed

func get_part(slot: PartData.PartSlot) -> PartInstance:
	match slot:
		PartData.PartSlot.BODY:
			return body_part
		PartData.PartSlot.ARMS:
			return arms_part
		PartData.PartSlot.LEGS:
			return legs_part
	return body_part

func take_damage(raw_damage: int, target_slot: PartData.PartSlot = PartData.PartSlot.BODY, ignore_armor: bool = false) -> Dictionary:
	var bonus_from_mark: int = 0
	var triggered_mark: bool = false
	if marked:
		bonus_from_mark = maxi(4, int(float(raw_damage) * 0.35))
		marked = false
		triggered_mark = true

	var total_raw: int = raw_damage + bonus_from_mark
	if shield > 0 and not ignore_armor:
		var absorbed: int = mini(shield, total_raw)
		shield -= absorbed
		total_raw -= absorbed

	if not is_modular():
		var reduction: int = 0 if ignore_armor else (data.armor if data != null else 0)
		var dealt: int = maxi(1, total_raw - reduction) if total_raw > 0 else 0
		current_hp = maxi(0, current_hp - dealt)
		return {
			"slot": PartData.PartSlot.BODY,
			"damage": dealt,
			"just_broken": current_hp <= 0,
			"triggered_mark": triggered_mark,
			"killed": not is_alive()
		}

	var part: PartInstance = get_part(target_slot)
	var actual_slot: PartData.PartSlot = target_slot
	if part == null or (part.is_broken() and target_slot != PartData.PartSlot.BODY):
		part = body_part
		actual_slot = PartData.PartSlot.BODY

	var was_broken: bool = part.is_broken()
	var mod_dealt: int = part.take_damage(total_raw, ignore_armor) if total_raw > 0 else 0
	current_hp = body_part.current_hp if body_part != null else 0
	var just_broken: bool = (not was_broken) and part.is_broken()
	return {
		"slot": actual_slot,
		"damage": mod_dealt,
		"just_broken": just_broken,
		"triggered_mark": triggered_mark,
		"killed": not is_alive()
	}

func choose_next_skill(rng: RandomNumberGenerator) -> SkillData:
	if data == null:
		return null
	var pool: Array[SkillData] = []
	if is_modular():
		if arms_part != null and not arms_part.is_broken() and arms_part.data != null:
			for s: SkillData in arms_part.data.skills:
				if s != null:
					pool.append(s)
		if body_part != null and not body_part.is_broken() and body_part.data != null:
			for s: SkillData in body_part.data.skills:
				if s != null:
					pool.append(s)
		if legs_part != null and not legs_part.is_broken() and legs_part.data != null:
			for s: SkillData in legs_part.data.skills:
				if s != null:
					pool.append(s)
	for s: SkillData in data.skills:
		if s != null:
			pool.append(s)
	if pool.is_empty():
		var fallback: SkillData = SkillData.new()
		fallback.skill_id = &"enemy_ram"
		fallback.skill_name = "Аварийный таран"
		fallback.base_damage = 8
		return fallback
	return pool[rng.randi_range(0, pool.size() - 1)]

