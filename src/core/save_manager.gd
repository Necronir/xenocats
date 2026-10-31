extends Node

## SaveManager: Управление user://meta_save.json и user://current_run.json (ADR-001 Section 2.8)

const META_SAVE_PATH: String = "user://meta_save.json"
const RUN_SAVE_PATH: String = "user://current_run.json"
const SETTINGS_PATH: String = "user://settings.cfg"
const VICTORY_BONUS_SCRAP: int = 250
const VICTORY_BONUS_CORES: int = 5

var settings: GameSettings = null

# --- Мета-состояние (Лагерь Бродяг / Hub) ---
var titanium_scrap: int = 80
var ai_cores: int = 3
var successful_evacuations: int = 0
var unlocked_perks: Array[String] = []
var shuttle_upgrades: Dictionary = {
	"hull_reinforce": 0,   # +10 к макс. HP всех корпусов за уровень
	"scrap_recycler": 0,   # +35 стартового лома в забеге за уровень
	"harmonic_battery": 0  # +20% стартового заряда шкалы Гармонии за уровень
}
var unlocked_tapes: Array[String] = ["tape_hardbass", "tape_blues", "tape_synth"]
var equipped_tape_id: StringName = &"tape_hardbass"

# --- Состояние активного забега (RunState) ---
var has_active_run: bool = false
var run_seed: int = 0
var current_sector: int = 1
var current_floor: int = 0
var current_node_id: int = -1
var completed_node_ids: Array[int] = []
var map_graph: Array[Dictionary] = []
var run_scrap: int = 50
var sync_gauge: int = 0
var party: Array[CatMechInstance] = []
var spare_parts_inventory: Array[String] = []
var pending_battle: Dictionary = {}

# --- Статистика забега (Issue #6) ---
var run_elapsed_sec: float = 0.0
var run_enemies_defeated: int = 0
var run_scrap_earned: int = 0
var run_cores_earned: int = 0

func _ready() -> void:
	DataCatalog.ensure_loaded()
	settings = GameSettings.new()
	if not settings.load_from_disk(SETTINGS_PATH):
		settings.save_to_disk(SETTINGS_PATH)
	settings.apply_all()
	load_meta()
	load_run()

func _process(delta: float) -> void:
	if has_active_run:
		run_elapsed_sec += delta

func _exit_tree() -> void:
	party.clear()
	CatMechInstance.clear_static_cache()
	DataCatalog.clear_cache()

# --- Перки и бонусы мета-прогрессии ---

func has_perk(perk_id: String) -> bool:
	return unlocked_perks.has(perk_id)

func unlock_perk(perk_id: String, cost_cores: int) -> bool:
	if unlocked_perks.has(perk_id) or ai_cores < cost_cores:
		return false
	ai_cores -= cost_cores
	unlocked_perks.append(perk_id)
	save_meta()
	EventBus.meta_resources_changed.emit(titanium_scrap, ai_cores)
	return true

func upgrade_shuttle_module(module_key: String, cost_scrap: int) -> bool:
	var current_lvl: int = int(shuttle_upgrades.get(module_key, 0))
	if current_lvl >= 3 or titanium_scrap < cost_scrap:
		return false
	titanium_scrap -= cost_scrap
	shuttle_upgrades[module_key] = current_lvl + 1
	save_meta()
	EventBus.meta_resources_changed.emit(titanium_scrap, ai_cores)
	return true

func get_active_tape() -> MusicTapeData:
	return DataCatalog.get_tape(String(equipped_tape_id))

# --- Управление забегом (Run Lifecycle) ---

func start_new_run(custom_seed: int = -1) -> void:
	DataCatalog.ensure_loaded()
	if custom_seed > 0:
		run_seed = custom_seed
	else:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		run_seed = int(rng.randi() % 900000 + 100000)

	current_sector = 1
	current_floor = 0
	current_node_id = -1
	completed_node_ids.clear()
	map_graph.clear()
	pending_battle.clear()

	run_elapsed_sec = 0.0
	run_enemies_defeated = 0
	run_scrap_earned = 0
	run_cores_earned = 0

	var recycler_lvl: int = int(shuttle_upgrades.get("scrap_recycler", 0))
	var battery_lvl: int = int(shuttle_upgrades.get("harmonic_battery", 0))
	run_scrap = 50 + recycler_lvl * 35
	sync_gauge = clampi(battery_lvl * 25, 0, 100)

	party = DataCatalog.create_starting_party()
	spare_parts_inventory = ["scrap_arms", "titan_body"]
	_apply_meta_and_tape_bonuses_to_party()

	has_active_run = true
	save_run()

func has_party_member(cat_id: String) -> bool:
	for cat: CatMechInstance in party:
		if String(cat.cat_id) == cat_id:
			return true
	return false

func recruit_cat(cat_id: String) -> bool:
	if has_party_member(cat_id):
		return false
	var new_cat: CatMechInstance = DataCatalog.create_cat_instance(cat_id)
	if new_cat == null:
		return false
	party.append(new_cat)
	_apply_meta_and_tape_bonuses_to_cat(new_cat)
	return true

func advance_to_next_sector() -> void:
	current_sector += 1
	current_floor = 0
	current_node_id = -1
	completed_node_ids.clear()
	map_graph.clear()
	pending_battle.clear()
	# По канону «Бременских музыкантов»:
	# После победы над Хозяином-Мельником (Сектор 1 -> 2) к отряду присоединяется Осёл (M.U.L.E.)
	if current_sector >= 2:
		recruit_cat("MULE")
	# После победы над Хозяйкой-Атаманшей (Сектор 2 -> 3) к отряду присоединяется Петух (C.O.C.K.)
	if current_sector >= 3:
		recruit_cat("COCK")
	# Частичный авто-ремонт между секторами (30% HP всем деталям)
	for cat: CatMechInstance in party:
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null:
				part.repair(int(float(part.get_max_hp()) * 0.3))
	save_run()

func jump_to_boss_battle(target_sector: int = -1) -> Dictionary:
	DataCatalog.ensure_loaded()
	if not has_active_run or party.is_empty():
		start_new_run()

	var previous_sector: int = current_sector
	var sec: int = clampi(target_sector if target_sector > 0 else current_sector, 1, 3)
	current_sector = sec

	# Обеспечиваем канонический состав отряда для выбранного сектора (Сектор 1: 2, Сектор 2: 3, Сектор 3: 4)
	if target_sector == 1 and party.size() > 2:
		party = DataCatalog.create_starting_party()
		_apply_meta_and_tape_bonuses_to_party()
	elif target_sector == 2 and has_party_member("COCK"):
		var filtered: Array[CatMechInstance] = []
		for c: CatMechInstance in party:
			if String(c.cat_id) != "COCK":
				filtered.append(c)
		party = filtered

	if current_sector >= 2:
		recruit_cat("MULE")
	if current_sector >= 3:
		recruit_cat("COCK")

	# Полный ремонт деталей и сброс боевых статусов перед быстрым переходом к боссу
	for cat: CatMechInstance in party:
		cat.reset_combat_statuses()
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null:
				part.repair_full()

	if map_graph.is_empty() or previous_sector != current_sector or target_sector > 0:
		completed_node_ids.clear()
		map_graph = MapGenerator.generate_sector_dag(run_seed, current_sector)

	var boss_node_id: int = 0
	var boss_floor: int = MapGenerator.TOTAL_FLOORS
	for node_dict: Dictionary in map_graph:
		if String(node_dict.get("type", "")) == "BOSS":
			boss_node_id = int(node_dict["id"])
			boss_floor = int(node_dict.get("floor", MapGenerator.TOTAL_FLOORS))
			break

	current_floor = boss_floor
	current_node_id = boss_node_id
	if not completed_node_ids.has(boss_node_id):
		completed_node_ids.append(boss_node_id)

	has_active_run = true
	save_run()

	var prelude_path: String = "res://data/dialogues/boss_prelude_sector" + str(current_sector) + ".dtl"
	var boss_titles: Dictionary = {
		1: "МЕЛЬНИЦА СВАЛКИ // ХОЗЯИН ОСЛА (ТРЁХГОЛОВЫЙ ПРЕСС)",
		2: "ПРИТОН РАЗБОЙНИКОВ // ПЕТУХ И СУП АТАМАНШИ",
		3: "ИЗБА НА ВЕРШИНЕ // ПИРАМИДА БРЕМЕНА В ОКНЕ"
	}
	var boss_btns: Dictionary = {
		1: "В БОЙ ЗА СПАСЕНИЕ ОСЛА ->",
		2: "В БОЙ ЗА СПАСЕНИЕ ПЕТУХА ->",
		3: "ВЛОМИТЬСЯ В ОКНО (ФИНАЛЬНЫЙ БОЙ) ->"
	}
	var payload: Dictionary = {
		"timeline": prelude_path,
		"next_scene": &"BATTLE",
		"next_payload": {"node_id": boss_node_id, "node_type": "BOSS"},
		"title": String(boss_titles.get(current_sector, "БОЕВАЯ ТРЕВОГА")),
		"continue_text": String(boss_btns.get(current_sector, "В БОЙ ->"))
	}
	EventBus.node_selected.emit(boss_node_id, &"BOSS")
	EventBus.request_scene_change.emit(&"EVENT", payload)
	return payload

func _apply_meta_and_tape_bonuses_to_party() -> void:
	for cat: CatMechInstance in party:
		_apply_meta_and_tape_bonuses_to_cat(cat)

func _apply_meta_and_tape_bonuses_to_cat(cat: CatMechInstance) -> void:
	var hull_lvl: int = int(shuttle_upgrades.get("hull_reinforce", 0))
	var tape: MusicTapeData = get_active_tape()
	var armor_aura: int = 0
	var speed_aura: int = 0
	if tape != null:
		if tape.passive_aura_type == &"ARMOR_AURA":
			armor_aura = tape.passive_aura_value
		elif tape.passive_aura_type == &"SPEED_AURA":
			speed_aura = tape.passive_aura_value

	var cid: String = String(cat.cat_id)
	var perk_hp: int = 15 if has_perk(cid + "_CORE_HP") else 0
	var perk_arm: int = 1 if has_perk(cid + "_ARMOR") else 0
	var perk_spd: int = 3 if has_perk(cid + "_SPEED") else 0

	if cat.body_part != null:
		cat.body_part.max_hp_bonus = hull_lvl * 12 + perk_hp
		cat.body_part.armor_bonus = armor_aura + perk_arm
		cat.body_part.repair_full()
	if cat.arms_part != null:
		cat.arms_part.max_hp_bonus = perk_hp / 2
		cat.arms_part.armor_bonus = armor_aura + perk_arm
		cat.arms_part.repair_full()
	if cat.legs_part != null:
		cat.legs_part.max_hp_bonus = perk_hp / 2
		cat.legs_part.armor_bonus = armor_aura + perk_arm
		cat.legs_part.speed_bonus = speed_aura + perk_spd
		cat.legs_part.repair_full()

func add_sync(amount: int) -> void:
	var tape: MusicTapeData = get_active_tape()
	var final_add: int = amount
	if tape != null and tape.passive_aura_type == &"SYNC_BOOST" and amount > 0:
		final_add = int(round(float(amount) * (1.0 + float(tape.passive_aura_value) / 100.0)))
	var was_full: bool = sync_gauge >= 100
	sync_gauge = clampi(sync_gauge + final_add, 0, 100)
	EventBus.sync_gauge_changed.emit(sync_gauge, 100)
	if not was_full and sync_gauge >= 100:
		EventBus.sync_gauge_filled.emit()

func add_run_scrap(amount: int) -> void:
	if amount > 0:
		run_scrap_earned += amount
	run_scrap = maxi(0, run_scrap + amount)
	EventBus.run_resources_changed.emit(run_scrap, sync_gauge)

func add_meta_rewards(scrap_delta: int, cores_delta: int) -> void:
	if has_active_run and cores_delta > 0:
		run_cores_earned += cores_delta
	titanium_scrap = maxi(0, titanium_scrap + scrap_delta)
	ai_cores = maxi(0, ai_cores + cores_delta)
	save_meta()
	EventBus.meta_resources_changed.emit(titanium_scrap, ai_cores)

func record_enemies_defeated(count: int) -> void:
	run_enemies_defeated += maxi(0, count)

func get_intact_party_parts_count() -> int:
	var intact: int = 0
	for cat: CatMechInstance in party:
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null and not part.is_broken():
				intact += 1
	return intact

func get_salvaged_parts_count() -> int:
	return get_intact_party_parts_count() + spare_parts_inventory.size()

func get_formatted_run_time() -> String:
	var total_sec: int = maxi(1, int(round(run_elapsed_sec)))
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]

func complete_run_victory() -> Dictionary:
	var intact_parts: int = get_intact_party_parts_count()
	var spare_parts: int = spare_parts_inventory.size()
	var total_parts: int = intact_parts + spare_parts
	var formatted_time: String = get_formatted_run_time()

	successful_evacuations += 1
	add_meta_rewards(VICTORY_BONUS_SCRAP, VICTORY_BONUS_CORES)
	delete_run_save()

	return {
		"elapsed_sec": maxi(1, int(round(run_elapsed_sec))),
		"formatted_time": formatted_time,
		"enemies_defeated": run_enemies_defeated,
		"intact_party_parts": intact_parts,
		"spare_parts_count": spare_parts,
		"total_salvaged_parts": total_parts,
		"run_scrap_earned": run_scrap_earned,
		"run_cores_earned": run_cores_earned,
		"bonus_titanium_scrap": VICTORY_BONUS_SCRAP,
		"bonus_ai_cores": VICTORY_BONUS_CORES,
		"successful_evacuations": successful_evacuations
	}

# --- Сериализация MetaState (user://meta_save.json) ---

func save_meta() -> void:
	var data: Dictionary = {
		"titanium_scrap": titanium_scrap,
		"ai_cores": ai_cores,
		"successful_evacuations": successful_evacuations,
		"unlocked_perks": unlocked_perks,
		"shuttle_upgrades": shuttle_upgrades,
		"unlocked_tapes": unlocked_tapes,
		"equipped_tape_id": String(equipped_tape_id)
	}
	var file: FileAccess = FileAccess.open(META_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func load_meta() -> void:
	if not FileAccess.file_exists(META_SAVE_PATH):
		save_meta()
		return
	var file: FileAccess = FileAccess.open(META_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		var d: Dictionary = parsed as Dictionary
		titanium_scrap = int(d.get("titanium_scrap", 80))
		ai_cores = int(d.get("ai_cores", 3))
		successful_evacuations = int(d.get("successful_evacuations", 0))
		unlocked_perks.clear()
		if d.has("unlocked_perks") and d["unlocked_perks"] is Array:
			for p: Variant in d["unlocked_perks"]:
				unlocked_perks.append(String(p))
		if d.has("shuttle_upgrades") and d["shuttle_upgrades"] is Dictionary:
			var upg: Dictionary = d["shuttle_upgrades"] as Dictionary
			for k: Variant in upg.keys():
				shuttle_upgrades[String(k)] = int(upg[k])
		equipped_tape_id = StringName(String(d.get("equipped_tape_id", "tape_hardbass")))

# --- Чекпоинт боя для переигровки и выхода в Лагерь через паузу (Issue #12) ---

func begin_battle_checkpoint(battle_payload: Dictionary) -> void:
	pending_battle = battle_payload.duplicate(true)
	save_run()

func restore_battle_checkpoint() -> Dictionary:
	var saved_elapsed: float = run_elapsed_sec
	load_run()
	run_elapsed_sec = maxf(run_elapsed_sec, saved_elapsed)
	return pending_battle.duplicate(true)

func clear_battle_checkpoint() -> void:
	pending_battle.clear()

# --- Сериализация RunState (user://current_run.json) ---
# Вызывается между нодами карты и на входе в бой (ADR-001 Section 2.8)

func save_run() -> void:
	var party_arr: Array[Dictionary] = []
	for cat: CatMechInstance in party:
		party_arr.append(cat.to_dict())

	var data: Dictionary = {
		"run_seed": run_seed,
		"current_sector": current_sector,
		"current_floor": current_floor,
		"current_node_id": current_node_id,
		"completed_node_ids": completed_node_ids,
		"map_graph": map_graph,
		"run_scrap": run_scrap,
		"sync_gauge": sync_gauge,
		"party": party_arr,
		"spare_parts_inventory": spare_parts_inventory,
		"pending_battle": pending_battle,
		"run_elapsed_sec": run_elapsed_sec,
		"run_enemies_defeated": run_enemies_defeated,
		"run_scrap_earned": run_scrap_earned,
		"run_cores_earned": run_cores_earned
	}
	var file: FileAccess = FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	has_active_run = true

func load_run() -> bool:
	if not FileAccess.file_exists(RUN_SAVE_PATH):
		has_active_run = false
		return false
	var file: FileAccess = FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
	if file == null:
		has_active_run = false
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		has_active_run = false
		return false

	var d: Dictionary = parsed as Dictionary
	run_seed = int(d.get("run_seed", 123456))
	current_sector = int(d.get("current_sector", 1))
	current_floor = int(d.get("current_floor", 0))
	current_node_id = int(d.get("current_node_id", -1))

	completed_node_ids.clear()
	if d.has("completed_node_ids") and d["completed_node_ids"] is Array:
		for nid: Variant in d["completed_node_ids"]:
			completed_node_ids.append(int(nid))

	map_graph.clear()
	if d.has("map_graph") and d["map_graph"] is Array:
		for n_item: Variant in d["map_graph"]:
			if n_item is Dictionary:
				map_graph.append(n_item as Dictionary)

	run_scrap = int(d.get("run_scrap", 50))
	sync_gauge = int(d.get("sync_gauge", 0))
	run_elapsed_sec = float(d.get("run_elapsed_sec", 0.0))
	run_enemies_defeated = int(d.get("run_enemies_defeated", 0))
	run_scrap_earned = int(d.get("run_scrap_earned", 0))
	run_cores_earned = int(d.get("run_cores_earned", 0))

	party.clear()
	var part_catalog: Dictionary = DataCatalog.get_all_parts()
	if d.has("party") and d["party"] is Array:
		for c_item: Variant in d["party"]:
			if c_item is Dictionary:
				party.append(CatMechInstance.from_dict(c_item as Dictionary, part_catalog))
	if party.is_empty():
		party = DataCatalog.create_default_party()

	spare_parts_inventory.clear()
	if d.has("spare_parts_inventory") and d["spare_parts_inventory"] is Array:
		for pid: Variant in d["spare_parts_inventory"]:
			spare_parts_inventory.append(String(pid))

	pending_battle.clear()
	if d.has("pending_battle") and d["pending_battle"] is Dictionary:
		pending_battle = (d["pending_battle"] as Dictionary).duplicate(true)

	has_active_run = true
	return true

func delete_run_save() -> void:
	pending_battle.clear()
	if FileAccess.file_exists(RUN_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_SAVE_PATH))
	has_active_run = false
