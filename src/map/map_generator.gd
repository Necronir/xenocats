class_name MapGenerator
extends RefCounted

## MapGenerator: Детерминированный генератор DAG с адаптацией этажей и тем секторов (ADR-002, Issue #28)

const TOTAL_FLOORS: int = 15
const SHORTENED_FLOORS: int = 7

enum BiomeTheme {
	GREEN = 1,
	YELLOW = 2,
	RED = 3,
	BLUE = 4
}

const SECTOR_THEMES: Dictionary = {
	1: "GREEN",
	2: "YELLOW",
	3: "RED",
	4: "BLUE"
}

static func get_sector_theme(sector: int, phase: int = -1) -> String:
	if phase == int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT):
		return "BLUE"
	elif phase == int(StoryProgressionData.StoryPhase.CYCLE_1_DUO):
		match sector:
			1: return "RED"
			2: return "BLUE"
			_: return "BLUE"
	elif phase == int(StoryProgressionData.StoryPhase.CYCLE_2_TRIO):
		match sector:
			1: return "YELLOW"
			2: return "RED"
			3: return "BLUE"
			_: return "BLUE"
	else:
		# Canonical sequence: Green (Sector 1) -> Yellow (Sector 2) -> Red (Sector 3) -> Blue (Sector 4)
		match sector:
			1: return "GREEN"
			2: return "YELLOW"
			3: return "RED"
			4: return "BLUE"
			_: return "BLUE"

static func get_sector_floor_count(sector: int, phase: int = -1) -> int:
	if phase == int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT) and sector == 1:
		return SHORTENED_FLOORS
	return TOTAL_FLOORS

static func get_sector_title(sector: int, phase: int = -1) -> String:
	var theme: String = get_sector_theme(sector, phase)
	if phase == int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT):
		return "ПРОЛОГ: Синий биом (Ретранслятор Бремен-4 // Прослушивание)"

	match theme:
		"GREEN":
			return "СЕКТОР %d: Зелёный биом (Высотные радиовышки // Эфирный сектор)" % sector
		"YELLOW":
			return "СЕКТОР %d: Жёлтый биом (Промзона // Гусеничные цеха)" % sector
		"RED":
			return "СЕКТОР %d: Красный биом (Сектор мародёров // Свалка)" % sector
		"BLUE":
			return "СЕКТОР %d: Синий биом (Ретранслятор Бремен-4 // Концертный зал)" % sector
		_:
			return "СЕКТОР %d" % sector

static func generate_sector_dag(
	seed_value: int,
	sector: int,
	custom_floors: int = -1,
	story_phase: int = -1
) -> Array[Dictionary]:
	var resolved_floors: int = TOTAL_FLOORS
	if custom_floors > 0:
		resolved_floors = custom_floors
	elif story_phase >= 0:
		resolved_floors = get_sector_floor_count(sector, story_phase)
	else:
		resolved_floors = TOTAL_FLOORS

	var sector_theme: String = get_sector_theme(sector, story_phase)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(seed_value) + sector * 7919

	var nodes: Array[Dictionary] = []
	var floor_node_ids: Array[Array] = []
	var next_id: int = 0

	for fl: int in range(1, resolved_floors + 1):
		var count: int = 3
		if fl == 1:
			count = 2
		elif fl == resolved_floors:
			count = 1
		else:
			count = rng.randi_range(2, 3)

		var ids_this_floor: Array[int] = []
		for lane: int in range(count):
			var ntype: String = _pick_node_type(fl, lane, rng, resolved_floors)
			var y_ratio: float = 0.5 if count == 1 else (float(lane) / float(count - 1))
			var node_dict: Dictionary = {
				"id": next_id,
				"floor": fl,
				"lane": lane,
				"y_ratio": y_ratio,
				"type": ntype,
				"next_ids": [],
				"theme": sector_theme,
				"sector": sector
			}
			nodes.append(node_dict)
			ids_this_floor.append(next_id)
			next_id += 1
		floor_node_ids.append(ids_this_floor)

	# Связываем этажи ориентированными рёбрами без висячих вершин (DAG)
	for f_idx: int in range(resolved_floors - 1):
		var curr_ids: Array = floor_node_ids[f_idx]
		var next_ids: Array = floor_node_ids[f_idx + 1]
		var incoming_count: Dictionary = {}
		for nid: Variant in next_ids:
			incoming_count[int(nid)] = 0

		for i: int in range(curr_ids.size()):
			var cid: int = int(curr_ids[i])
			var target_idx: int = clampi(i, 0, next_ids.size() - 1)
			var tid: int = int(next_ids[target_idx])
			_add_edge(nodes[cid], tid)
			incoming_count[tid] = int(incoming_count[tid]) + 1

			# Дополнительное ветвление
			if next_ids.size() > 1 and rng.randf() < 0.55:
				var alt_idx: int = clampi(target_idx + (1 if rng.randf() < 0.5 else -1), 0, next_ids.size() - 1)
				var alt_id: int = int(next_ids[alt_idx])
				_add_edge(nodes[cid], alt_id)
				incoming_count[alt_id] = int(incoming_count[alt_id]) + 1

		# Гарантируем, что в каждую ноду следующего этажа входит хотя бы 1 ребро
		for j: int in range(next_ids.size()):
			var check_id: int = int(next_ids[j])
			if int(incoming_count[check_id]) == 0:
				var src_idx: int = clampi(j, 0, curr_ids.size() - 1)
				var src_id: int = int(curr_ids[src_idx])
				_add_edge(nodes[src_id], check_id)

	return nodes

static func _add_edge(node_dict: Dictionary, target_id: int) -> void:
	var arr: Array = node_dict["next_ids"] as Array
	if not arr.has(target_id):
		arr.append(target_id)

static func _pick_node_type(floor_num: int, lane: int, rng: RandomNumberGenerator, total_floors: int = TOTAL_FLOORS) -> String:
	if floor_num == 1:
		return "COMBAT"
	if floor_num == total_floors:
		return "BOSS"

	if total_floors == 15:
		if floor_num == 8 or floor_num == 14:
			return "WORKSHOP"
		if floor_num in [5, 10, 12] and lane == 0:
			return "ELITE"
	else:
		if floor_num == total_floors - 1 or floor_num == maxi(2, int(total_floors / 2)):
			return "WORKSHOP"
		if floor_num in [maxi(2, int(total_floors * 0.4)), maxi(3, int(total_floors * 0.7))] and lane == 0:
			return "ELITE"

	var roll: float = rng.randf()
	if roll < 0.44:
		return "COMBAT"
	elif roll < 0.66:
		return "EVENT"
	elif roll < 0.84:
		return "WORKSHOP"
	return "ELITE"
