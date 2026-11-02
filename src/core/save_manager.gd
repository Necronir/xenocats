extends Node

## SaveManager: Управление user://meta_save.json и user://current_run.json (ADR-001 Section 2.8)

const META_SAVE_PATH: String = "user://meta_save.json"
const RUN_SAVE_PATH: String = "user://current_run.json"
const SETTINGS_PATH: String = "user://settings.cfg"
const VICTORY_BONUS_SCRAP: int = 250
const VICTORY_BONUS_CORES: int = 5

var settings: GameSettings = null
var story_progression: StoryProgressionData = null

# --- Мета-состояние (Лагерь Бродяг / Hub) ---
var titanium_scrap: int = 80
var ai_cores: int = 3
var successful_evacuations: int = 0
var highest_ng_cycle: int = 0
var unlocked_perks: Array[String] = []
var shuttle_upgrades: Dictionary = {
	"hull_reinforce": 0,   # +12 к макс. HP всех корпусов за уровень
	"scrap_recycler": 0,   # +35 стартового лома в забеге за уровень
	"harmonic_battery": 0  # +12% стартовой Гармонии за уровень
}
var unlocked_tapes: Array[String] = ["tape_hardbass", "tape_blues", "tape_synth"]
var equipped_tape_id: StringName = &"tape_hardbass"

# --- Состояние активного забега (RunState) ---
var has_active_run: bool = false
var ng_cycle: int = 0
var run_seed: int = 0
var current_sector: int = 1
var current_floor: int = 0
var current_node_id: int = -1
var completed_node_ids: Array[int] = []
var map_graph: Array[Dictionary] = []
var run_scrap: int = 50
var sync_gauge: int = 0
var party: Array[CatMechInstance] = []
var spare_parts_inventory: Array = []
var pending_battle: Dictionary = {}

# --- Статистика забега (Issue #6) ---
var run_elapsed_sec: float = 0.0
var run_enemies_defeated: int = 0
var run_scrap_earned: int = 0
var run_cores_earned: int = 0

func _ready() -> void:
	DataCatalog.ensure_loaded()
	story_progression = StoryProgressionData.new()
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

# --- Сюжетная мета-прогрессия (ADR-002, Issue #28) ---

func get_story_phase() -> StoryProgressionData.StoryPhase:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	return story_progression.current_phase

func set_story_phase(phase: StoryProgressionData.StoryPhase) -> void:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	story_progression.set_phase(phase)
	save_meta()

func advance_story_phase() -> bool:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	var advanced: bool = story_progression.advance_phase()
	if advanced:
		save_meta()
	return advanced

func unlock_party_member(cat_id: StringName) -> bool:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	var changed: bool = story_progression.unlock_party_member(cat_id)
	if changed:
		save_meta()
	return changed

func unlock_fusion_tier(tier: int) -> bool:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	var changed: bool = story_progression.unlock_fusion_tier(tier)
	if changed:
		save_meta()
	return changed

func is_fusion_tier_unlocked(tier: int) -> bool:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	return story_progression.unlocked_fusion_tiers.has(tier)

func get_unlocked_fusion_tiers() -> Array[int]:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	return story_progression.unlocked_fusion_tiers.duplicate()

func is_party_member_unlocked(cat_id: StringName) -> bool:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	return story_progression.unlocked_party_members.has(cat_id)

func get_unlocked_party_members() -> Array[StringName]:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	return story_progression.unlocked_party_members.duplicate()

func set_player_is_boomer(is_boomer: bool) -> void:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	story_progression.player_is_boomer = is_boomer
	story_progression.seen_boomer_dialog = true

func is_player_boomer() -> bool:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	return story_progression.player_is_boomer

# --- Перки и бонусы мета-прогрессии ---

func has_perk(perk_id: String) -> bool:
	return unlocked_perks.has(perk_id)

func unlock_perk(perk_id: String, cost_cores: int) -> bool:
	if unlocked_perks.has(perk_id) or ai_cores < cost_cores:
		return false
	ai_cores -= cost_cores
	unlocked_perks.append(perk_id)
	save_meta()
	reapply_party_bonuses()
	EventBus.meta_resources_changed.emit(titanium_scrap, ai_cores)
	return true

func get_shuttle_upgrade_cost(module_key: String) -> int:
	var current_lvl: int = int(shuttle_upgrades.get(module_key, 0))
	match current_lvl:
		0:
			return 40
		1:
			return 80
		2:
			return 140
		_:
			return 999999

func upgrade_shuttle_module(module_key: String, cost_scrap: int = -1) -> bool:
	var current_lvl: int = int(shuttle_upgrades.get(module_key, 0))
	var required_cost: int = cost_scrap if cost_scrap > 0 else get_shuttle_upgrade_cost(module_key)
	if current_lvl >= 3 or titanium_scrap < required_cost:
		return false
	titanium_scrap -= required_cost
	shuttle_upgrades[module_key] = current_lvl + 1
	save_meta()
	reapply_party_bonuses()
	EventBus.meta_resources_changed.emit(titanium_scrap, ai_cores)
	return true

func get_active_tape() -> MusicTapeData:
	return DataCatalog.get_tape(String(equipped_tape_id))

func equip_tape(tape_id: StringName) -> void:
	equipped_tape_id = tape_id
	save_meta()
	reapply_party_bonuses()

func unlock_tape(tape_id: String) -> bool:
	if not unlocked_tapes.has(tape_id):
		unlocked_tapes.append(tape_id)
		save_meta()
		return true
	return false

func complete_epilogue_triumph() -> Dictionary:
	var newly_unlocked: bool = false
	if not unlocked_tapes.has("tape_bremen_triumph"):
		unlocked_tapes.append("tape_bremen_triumph")
		newly_unlocked = true
	highest_ng_cycle += 1
	if story_progression != null:
		story_progression.concert_hall_liberated = true
		story_progression.set_phase(StoryProgressionData.StoryPhase.COMPLETED)
	save_meta()
	return {
		"tape_unlocked": "tape_bremen_triumph",
		"highest_ng_cycle": highest_ng_cycle,
		"concert_hall_liberated": true,
		"newly_unlocked": newly_unlocked
	}

# --- NG+ Масштабирование сложности ---

func get_enemy_hp_mult() -> float:
	return 1.0 + float(ng_cycle) * 0.25

func get_enemy_damage_mult() -> float:
	return 1.0 + float(ng_cycle) * 0.15

func get_enemy_speed_mult() -> float:
	return 1.0 + float(ng_cycle) * 0.05

func get_meta_reward_mult() -> float:
	return 1.0 + float(ng_cycle) * 0.30

func advance_to_ng_plus_cycle() -> void:
	ng_cycle += 1
	highest_ng_cycle = maxi(highest_ng_cycle, ng_cycle)
	current_sector = 1
	current_floor = 0
	current_node_id = -1
	completed_node_ids.clear()
	map_graph.clear()
	pending_battle.clear()
	for cat: CatMechInstance in party:
		cat.reset_combat_statuses()
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null:
				part.repair_full()
	save_meta()
	save_run()

# --- Управление забегом (Run Lifecycle) ---

func start_new_run(custom_seed: int = -1) -> void:
	DataCatalog.ensure_loaded()
	if custom_seed > 0:
		run_seed = custom_seed
	else:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		run_seed = int(rng.randi() % 900000 + 100000)

	ng_cycle = 0
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
	sync_gauge = clampi(battery_lvl * 12, 0, 100)

	party.clear()
	if story_progression == null:
		story_progression = StoryProgressionData.new()

	var members_to_spawn: Array[StringName] = []
	for member_id: StringName in story_progression.unlocked_party_members:
		members_to_spawn.append(member_id)

	if members_to_spawn.is_empty():
		members_to_spawn = StoryProgressionData.get_default_party_for_phase(story_progression.current_phase)

	for mid: StringName in members_to_spawn:
		var cat_inst: CatMechInstance = DataCatalog.create_cat_instance(String(mid))
		if cat_inst != null:
			party.append(cat_inst)

	if party.is_empty():
		var felix: CatMechInstance = DataCatalog.create_cat_instance("FELIX")
		if felix != null:
			party.append(felix)

	# Базовый склад деталей (без имбового titan_body)
	spare_parts_inventory = [
		{"part_id": "scrap_arms", "current_hp": 65}
	]
	_apply_meta_and_tape_bonuses_to_party()

	has_active_run = true
	save_run()

func has_party_member(cat_id: String) -> bool:
	for cat: CatMechInstance in party:
		if String(cat.cat_id) == cat_id:
			return true
	return false

func recruit_cat(cat_id: String) -> bool:
	unlock_party_member(StringName(cat_id))
	if has_party_member(cat_id):
		return false
	var new_cat: CatMechInstance = DataCatalog.create_cat_instance(cat_id)
	if new_cat == null:
		return false
	party.append(new_cat)
	_apply_meta_and_tape_bonuses_to_cat(new_cat)
	return true

func repair_squad_percentage(ratio: float = 0.3) -> void:
	for cat: CatMechInstance in party:
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null:
				part.repair(int(float(part.get_max_hp()) * ratio))

func rescue_companion(cat_id: String) -> Dictionary:
	var cid_upper: String = cat_id.to_upper().strip_edges()
	var theme: String = "YELLOW" if cid_upper == "MULE" else ("GREEN" if cid_upper == "COCK" else ("BLUE" if cid_upper == "HOUND" else ""))
	var b_id: String = "boss_press" if cid_upper == "MULE" else ("boss_atamansha" if cid_upper == "COCK" else ("boss_satellite" if cid_upper == "HOUND" else ""))
	return handle_biome_boss_defeat(theme, b_id)

func handle_biome_boss_defeat(biome_theme: String = "", boss_id: String = "") -> Dictionary:
	var clean_theme: String = biome_theme.to_upper().strip_edges()
	var companion_id: StringName = &""
	var timeline: String = ""
	var timeline_id: String = ""
	var photo_path: String = ""
	var post_title: String = ""
	var fusion_tier: int = 0

	# Map theme or boss_id to companion rescue per ADR-002:
	# Yellow Biome Boss -> M.U.L.E. (Donkey / Bassist)
	# Green Biome Boss -> C.O.C.K. (Rooster / Synth & Electronic Warfare)
	var p_val: int = int(story_progression.current_phase) if story_progression != null else -1
	if p_val == int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT) or (boss_id == "boss_satellite" and p_val == 0):
		companion_id = &"HOUND"
		timeline = "res://data/dialogues/boss_postlude_sputnik_solo.dtl"
		timeline_id = "boss_postlude_sputnik_solo"
		photo_path = "res://assets/photos/1-4b-trubadur-apperiance.jpg"
		post_title = "ПРОЛОГ: СПУТНИК ПОВЕРЖЕН // ПОЯВЛЕНИЕ КИБЕР-ТРУБАДУРА"
		fusion_tier = 1
		clean_theme = "BLUE"
	elif clean_theme == "YELLOW" or boss_id == "boss_press":
		companion_id = &"MULE"
		timeline = "res://data/dialogues/dialogic_rescue_mule.dtl"
		timeline_id = "dialogic_rescue_mule"
		photo_path = "res://assets/photos/2-3a-press-boss-win.jpg"
		post_title = "СЕКТОР: ПОБЕДА НАД ПРЕССОМ // СПАСЕНИЕ ОСЛА M.U.L.E."
		fusion_tier = 2 # ROBO_CATDOG_DONKEY
		clean_theme = "YELLOW"
	elif clean_theme == "GREEN" or boss_id == "boss_atamansha":
		companion_id = &"COCK"
		timeline = "res://data/dialogues/dialogic_rescue_cock.dtl"
		timeline_id = "dialogic_rescue_cock"
		photo_path = "res://assets/photos/3-2a-atamansha-boss-win.jpg"
		post_title = "СЕКТОР: ПОБЕДА НАД АТАМАНШЕЙ // СПАСЕНИЕ ПЕТУХА C.O.C.K."
		fusion_tier = 3 # ROBO_MEGA_PYRAMID
		clean_theme = "GREEN"
	else:
		var inferred: String = MapGenerator.get_sector_theme(current_sector, p_val)
		if inferred == "YELLOW":
			companion_id = &"MULE"
			timeline = "res://data/dialogues/dialogic_rescue_mule.dtl"
			timeline_id = "dialogic_rescue_mule"
			photo_path = "res://assets/photos/2-3a-press-boss-win.jpg"
			post_title = "СЕКТОР: ПОБЕДА НАД ПРЕССОМ // СПАСЕНИЕ ОСЛА M.U.L.E."
			fusion_tier = 2
			clean_theme = "YELLOW"
		elif inferred == "GREEN":
			companion_id = &"COCK"
			timeline = "res://data/dialogues/dialogic_rescue_cock.dtl"
			timeline_id = "dialogic_rescue_cock"
			photo_path = "res://assets/photos/3-2a-atamansha-boss-win.jpg"
			post_title = "СЕКТОР: ПОБЕДА НАД АТАМАНШЕЙ // СПАСЕНИЕ ПЕТУХА C.O.C.K."
			fusion_tier = 3
			clean_theme = "GREEN"

	# 1. Unlock companion in SaveManager (which also unlocks the fusion tier in StoryProgressionData)
	if companion_id != &"":
		unlock_party_member(companion_id)
		if fusion_tier > 0:
			unlock_fusion_tier(fusion_tier)

	# 2. Rescued character is immediately instantiated via DataCatalog.create_cat_instance() and appended to active party
	var instantiated: bool = false
	if companion_id != &"" and not has_party_member(String(companion_id)):
		var new_cat: CatMechInstance = DataCatalog.create_cat_instance(String(companion_id))
		if new_cat != null:
			party.append(new_cat)
			_apply_meta_and_tape_bonuses_to_cat(new_cat)
			instantiated = true

	# 3. Repair 30% HP across the squad
	repair_squad_percentage(0.3)

	# 4. Advance story phase in SaveManager
	if companion_id == &"HOUND" and p_val == int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT):
		# Ejected from Spire to scrap heap: next sector advance will enter Sector 1 of Cycle 1
		current_sector = 0
	advance_story_phase()

	save_meta()
	save_run()

	return {
		"rescued": (companion_id != &""),
		"companion_id": String(companion_id),
		"biome_theme": clean_theme,
		"timeline": timeline,
		"timeline_id": timeline_id,
		"post_title": post_title,
		"photo_path": photo_path,
		"fusion_tier": fusion_tier,
		"party_size": party.size(),
		"repaired_percentage": 0.3,
		"newly_instantiated": instantiated
	}

func advance_to_next_sector() -> void:
	current_sector += 1
	var phase_val: int = int(story_progression.current_phase) if story_progression != null else -1

	current_floor = 0
	current_node_id = -1
	completed_node_ids.clear()
	map_graph.clear()
	pending_battle.clear()
	map_graph = MapGenerator.generate_sector_dag(run_seed, current_sector, -1, phase_val)
	if current_sector >= 2:
		recruit_cat("MULE")
	if current_sector >= 3:
		recruit_cat("COCK")
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
	var sec: int = clampi(target_sector if target_sector > 0 else current_sector, 1, 4)
	current_sector = sec

	if (target_sector == 1 or sec == 1) and party.size() > 2:
		party = DataCatalog.create_starting_party()
		_apply_meta_and_tape_bonuses_to_party()
	elif (target_sector == 2 or sec == 2) and has_party_member("COCK"):
		var filtered: Array[CatMechInstance] = []
		for c: CatMechInstance in party:
			if String(c.cat_id) != "COCK":
				filtered.append(c)
		party = filtered

	if current_sector >= 2:
		recruit_cat("MULE")
	if current_sector >= 3:
		recruit_cat("COCK")

	for cat: CatMechInstance in party:
		cat.reset_combat_statuses()
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null:
				part.repair_full()

	if map_graph.is_empty() or previous_sector != current_sector or target_sector > 0:
		completed_node_ids.clear()
		var phase_val: int = int(story_progression.current_phase) if story_progression != null else -1
		map_graph = MapGenerator.generate_sector_dag(run_seed, current_sector, -1, phase_val)

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

	var dtl_sec: int = clampi(current_sector, 1, 3)
	var prelude_path: String = "res://data/dialogues/boss_prelude_sector" + str(dtl_sec) + ".dtl"
	var boss_titles: Dictionary = {
		1: "МЕЛЬНИЦА СВАЛКИ // ХОЗЯИН ОСЛА (ТРЁХГОЛОВЫЙ ПРЕСС)",
		2: "ПРИТОН РАЗБОЙНИКОВ // ПЕТУХ И СУП АТАМАНШИ",
		3: "ВЕРШИНА БРЕМЕН-4 // СПУТНИК В ЭФИРЕ",
		4: "ВЕРШИНА БРЕМЕН-4 // ИСТИННЫЙ РЕВИЗОР ЭФИРА"
	}
	var boss_btns: Dictionary = {
		1: "В БОЙ ЗА СПАСЕНИЕ ОСЛА ->",
		2: "В БОЙ ЗА СПАСЕНИЕ ПЕТУХА ->",
		3: "В БОЙ ЗА РЕТРАНСЛЯТОР ->",
		4: "ВЛОМИТЬСЯ В ОКНО (ФИНАЛЬНЫЙ БОЙ) ->"
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

# --- Модульная система бонусов к деталям ---

func apply_meta_and_tape_bonuses_to_part(part: PartInstance, cat_id: StringName) -> void:
	if part == null or part.data == null:
		return
	var hull_lvl: int = int(shuttle_upgrades.get("hull_reinforce", 0))
	var tape: MusicTapeData = get_active_tape()
	var armor_aura: int = 0
	var speed_aura: int = 0
	if tape != null:
		if tape.passive_aura_type == &"ARMOR_AURA":
			armor_aura = tape.passive_aura_value
		elif tape.passive_aura_type == &"SPEED_AURA":
			speed_aura = tape.passive_aura_value
		elif tape.passive_aura_type == &"TRIUMPH_AURA":
			armor_aura = 2
			speed_aura = 3

	var cid: String = String(cat_id)
	var perk_hp: int = 15 if has_perk(cid + "_CORE_HP") else 0
	var perk_arm: int = 1 if has_perk(cid + "_ARMOR") else 0
	var perk_spd: int = 3 if has_perk(cid + "_SPEED") else 0

	match part.data.slot:
		PartData.PartSlot.BODY:
			part.max_hp_bonus = hull_lvl * 12 + perk_hp
			part.armor_bonus = armor_aura + perk_arm
		PartData.PartSlot.ARMS:
			part.max_hp_bonus = perk_hp / 2
			part.armor_bonus = armor_aura + perk_arm
		PartData.PartSlot.LEGS:
			part.max_hp_bonus = perk_hp / 2
			part.armor_bonus = armor_aura + perk_arm
			part.speed_bonus = speed_aura + perk_spd
	part.current_hp = clampi(part.current_hp, 0, part.get_max_hp())

func reapply_party_bonuses() -> void:
	for cat: CatMechInstance in party:
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null:
				apply_meta_and_tape_bonuses_to_part(part, cat.cat_id)

func _apply_meta_and_tape_bonuses_to_party() -> void:
	reapply_party_bonuses()
	for cat: CatMechInstance in party:
		for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
			var part: PartInstance = cat.get_part(slot)
			if part != null:
				part.repair_full()

func _apply_meta_and_tape_bonuses_to_cat(cat: CatMechInstance) -> void:
	if cat == null:
		return
	for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
		var part: PartInstance = cat.get_part(slot)
		if part != null:
			apply_meta_and_tape_bonuses_to_part(part, cat.cat_id)
			part.repair_full()

# --- Управление Гармонией (Синхрой) и Ресурсами ---

func prepare_battle_sync() -> void:
	var carry: int = mini(25, int(float(sync_gauge) * 0.25))
	var battery_lvl: int = int(shuttle_upgrades.get("harmonic_battery", 0))
	var battery_bonus: int = battery_lvl * 12
	sync_gauge = clampi(carry + battery_bonus, 0, 100)
	EventBus.sync_gauge_changed.emit(sync_gauge, 100)

func add_sync(amount: int) -> void:
	var tape: MusicTapeData = get_active_tape()
	var final_add: int = amount
	if tape != null and (tape.passive_aura_type == &"SYNC_BOOST" or tape.passive_aura_type == &"TRIUMPH_AURA") and amount > 0:
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
	var r_mult: float = get_meta_reward_mult()
	var scaled_scrap: int = int(round(float(scrap_delta) * r_mult)) if scrap_delta > 0 else scrap_delta
	var scaled_cores: int = cores_delta
	if has_active_run and scaled_cores > 0:
		run_cores_earned += scaled_cores
	titanium_scrap = maxi(0, titanium_scrap + scaled_scrap)
	ai_cores = maxi(0, ai_cores + scaled_cores)
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
		"successful_evacuations": successful_evacuations,
		"ng_cycle": ng_cycle
	}

# --- Сериализация MetaState (user://meta_save.json) ---

func save_meta() -> void:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
	var sp_dict: Dictionary = story_progression.to_dict()
	var data: Dictionary = {
		"titanium_scrap": titanium_scrap,
		"ai_cores": ai_cores,
		"successful_evacuations": successful_evacuations,
		"highest_ng_cycle": highest_ng_cycle,
		"unlocked_perks": unlocked_perks,
		"shuttle_upgrades": shuttle_upgrades,
		"unlocked_tapes": unlocked_tapes,
		"equipped_tape_id": String(equipped_tape_id),
		"current_phase": int(story_progression.current_phase),
		"unlocked_party_members": sp_dict["unlocked_party_members"],
		"unlocked_fusion_tiers": sp_dict["unlocked_fusion_tiers"],
		"story_progression": sp_dict
	}
	var file: FileAccess = FileAccess.open(META_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "	"))
		file.close()

func load_meta() -> void:
	if story_progression == null:
		story_progression = StoryProgressionData.new()
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
		highest_ng_cycle = int(d.get("highest_ng_cycle", 0))
		unlocked_perks.clear()
		if d.has("unlocked_perks") and d["unlocked_perks"] is Array:
			for p: Variant in d["unlocked_perks"]:
				unlocked_perks.append(String(p))
		if d.has("shuttle_upgrades") and d["shuttle_upgrades"] is Dictionary:
			var upg: Dictionary = d["shuttle_upgrades"] as Dictionary
			for k: Variant in upg.keys():
				shuttle_upgrades[String(k)] = int(upg[k])
		if d.has("unlocked_tapes") and d["unlocked_tapes"] is Array:
			unlocked_tapes.clear()
			for t: Variant in d["unlocked_tapes"]:
				unlocked_tapes.append(String(t))
		equipped_tape_id = StringName(String(d.get("equipped_tape_id", "tape_hardbass")))

		if d.has("story_progression") and d["story_progression"] is Dictionary:
			story_progression.from_dict(d["story_progression"] as Dictionary)
		else:
			var sp_dict: Dictionary = {}
			if d.has("current_phase"):
				sp_dict["current_phase"] = d["current_phase"]
			if d.has("unlocked_party_members"):
				sp_dict["unlocked_party_members"] = d["unlocked_party_members"]
			if d.has("unlocked_fusion_tiers"):
				sp_dict["unlocked_fusion_tiers"] = d["unlocked_fusion_tiers"]
			if not sp_dict.is_empty():
				story_progression.from_dict(sp_dict)

# --- Сброс всего прогресса (Hard Reset / New Game) ---

func hard_reset_all_progress() -> void:
	delete_run_save()
	if FileAccess.file_exists(META_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(META_SAVE_PATH))

	titanium_scrap = 0
	ai_cores = 0
	successful_evacuations = 0
	highest_ng_cycle = 0
	ng_cycle = 0
	unlocked_perks.clear()
	shuttle_upgrades = {
		"hull_reinforce": 0,
		"scrap_recycler": 0,
		"harmonic_battery": 0
	}
	unlocked_tapes = ["tape_hardbass", "tape_blues", "tape_synth"]
	equipped_tape_id = &"tape_hardbass"

	if story_progression == null:
		story_progression = StoryProgressionData.new()
	story_progression.reset()
	successful_evacuations = 0
	highest_ng_cycle = 0
	ng_cycle = 0
	unlocked_perks.clear()
	shuttle_upgrades = {
		"hull_reinforce": 0,
		"scrap_recycler": 0,
		"harmonic_battery": 0
	}
	unlocked_tapes = ["tape_hardbass", "tape_blues", "tape_synth"]
	equipped_tape_id = &"tape_hardbass"

	has_active_run = false
	party.clear()
	spare_parts_inventory.clear()
	sync_gauge = 0
	run_elapsed_sec = 0.0
	run_enemies_defeated = 0
	run_scrap_earned = 0
	run_cores_earned = 0
	pending_battle.clear()

	save_meta()
	EventBus.meta_resources_changed.emit(titanium_scrap, ai_cores)
	EventBus.run_resources_changed.emit(run_scrap, sync_gauge)

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

func save_run() -> void:
	var party_arr: Array[Dictionary] = []
	for cat: CatMechInstance in party:
		party_arr.append(cat.to_dict())

	var serialized_parts: Array = []
	for p_item: Variant in spare_parts_inventory:
		if p_item is Dictionary:
			serialized_parts.append((p_item as Dictionary).duplicate())
		elif p_item is String:
			serialized_parts.append({"part_id": String(p_item), "current_hp": -1})

	var data: Dictionary = {
		"run_seed": run_seed,
		"ng_cycle": ng_cycle,
		"current_sector": current_sector,
		"current_floor": current_floor,
		"current_node_id": current_node_id,
		"completed_node_ids": completed_node_ids,
		"map_graph": map_graph,
		"run_scrap": run_scrap,
		"sync_gauge": sync_gauge,
		"party": party_arr,
		"spare_parts_inventory": serialized_parts,
		"pending_battle": pending_battle,
		"run_elapsed_sec": run_elapsed_sec,
		"run_enemies_defeated": run_enemies_defeated,
		"run_scrap_earned": run_scrap_earned,
		"run_cores_earned": run_cores_earned
	}
	var file: FileAccess = FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "	"))
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
	ng_cycle = int(d.get("ng_cycle", 0))
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
		for item: Variant in d["spare_parts_inventory"]:
			if item is Dictionary:
				spare_parts_inventory.append((item as Dictionary).duplicate())
			elif item is String:
				spare_parts_inventory.append({"part_id": String(item), "current_hp": -1})

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
