class_name PartInstance
extends RefCounted

var data: PartData = null
var current_hp: int = 1
var max_hp_bonus: int = 0
var armor_bonus: int = 0
var speed_bonus: int = 0

func _init(p_data: PartData = null, p_hp: int = -1) -> void:
	data = p_data
	if data != null:
		if p_hp >= 0:
			current_hp = clampi(p_hp, 0, get_max_hp())
		else:
			current_hp = get_max_hp()

func get_max_hp() -> int:
	if data == null:
		return 1
	return maxi(1, data.max_hp + max_hp_bonus)

func get_armor() -> int:
	if data == null:
		return 0
	return maxi(0, data.armor + armor_bonus)

func get_base_speed() -> int:
	if data == null:
		return 1
	return maxi(1, data.base_speed + speed_bonus)

func is_broken() -> bool:
	return current_hp <= 0

func take_damage(raw_damage: int, ignore_armor: bool = false) -> int:
	if is_broken():
		return 0
	var reduction: int = 0 if ignore_armor else get_armor()
	var final_damage: int = maxi(1, raw_damage - reduction)
	current_hp = maxi(0, current_hp - final_damage)
	return final_damage

func repair(amount: int) -> int:
	var before: int = current_hp
	current_hp = mini(get_max_hp(), current_hp + maxi(0, amount))
	return current_hp - before

func repair_full() -> void:
	current_hp = get_max_hp()

func to_dict() -> Dictionary:
	return {
		"part_id": String(data.part_id) if data != null else "",
		"current_hp": current_hp,
		"max_hp_bonus": max_hp_bonus,
		"armor_bonus": armor_bonus,
		"speed_bonus": speed_bonus
	}

static func from_dict(d: Dictionary, part_catalog: Dictionary) -> PartInstance:
	var pid: String = String(d.get("part_id", ""))
	var p_data: PartData = part_catalog.get(pid, null) as PartData
	var inst: PartInstance = PartInstance.new(p_data)
	inst.max_hp_bonus = int(d.get("max_hp_bonus", 0))
	inst.armor_bonus = int(d.get("armor_bonus", 0))
	inst.speed_bonus = int(d.get("speed_bonus", 0))
	inst.current_hp = clampi(int(d.get("current_hp", inst.get_max_hp())), 0, inst.get_max_hp())
	return inst

