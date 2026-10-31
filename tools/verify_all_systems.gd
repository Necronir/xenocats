extends Node

func _ready() -> void:
	print("=== XENOCATS: BREMEN-4 AUTOMATED VERIFICATION ===")
	DataCatalog.ensure_loaded()

	# 1. Verify .tres catalog counts
	var parts_count: int = DataCatalog.get_all_parts().size()
	var tapes_count: int = DataCatalog.get_all_tapes().size()
	print("[1] Loaded parts: ", parts_count, " | tapes: ", tapes_count)
	assert(parts_count >= 16, "Expected at least 16 parts in catalog")
	assert(tapes_count == 3, "Expected 3 music tapes")

	# 2. Verify Front Mission 3-part rules on CatMechInstance
	SaveManager.start_new_run(777888)
	var felix: CatMechInstance = SaveManager.party[0]
	var base_init: int = felix.get_initiative_score()
	var base_dodge_mult: float = felix.get_dodge_speed_multiplier()
	felix.legs_part.current_hp = 0
	var broken_init: int = felix.get_initiative_score()
	var broken_dodge_mult: float = felix.get_dodge_speed_multiplier()
	print("[2] FELIX initiative intact=", base_init, " broken_legs=", broken_init, " | dodge_mult=", broken_dodge_mult)
	assert(broken_init == int(float(base_init) * 0.3), "Broken legs must apply 70% speed penalty")
	assert(is_equal_approx(broken_dodge_mult, 0.6), "Broken legs must apply 40% dodge box speed penalty")

	felix.arms_part.current_hp = 0
	var broken_arms_skills: Array[SkillData] = felix.get_available_skills()
	assert(broken_arms_skills[0].skill_id == &"emergency_poke", "Broken arms must fallback to emergency_poke")
	felix.legs_part.repair_full()
	felix.arms_part.repair_full()

	# 3. Verify Hybrid Enemy Modularity (Regular vs Elite/Boss)
	var reg_data: EnemyData = DataCatalog.get_enemy("scrap_drone")
	var boss_data: EnemyData = DataCatalog.get_enemy("boss_press")
	assert(reg_data != null and not reg_data.is_modular, "Regular enemy must have unified HP")
	assert(boss_data != null and boss_data.is_modular, "Boss enemy must have 3 destructible parts")
	var boss_inst: EnemyInstance = EnemyInstance.new(boss_data)
	var hit_arms: Dictionary = boss_inst.take_damage(35, PartData.PartSlot.ARMS, false)
	print("[3] Boss arms targeted -> dealt=", hit_arms["damage"], " remaining arms HP=", boss_inst.arms_part.current_hp)

	# 4. Verify 15-floor deterministic StS DAG generator
	var dag1: Array[Dictionary] = MapGenerator.generate_sector_dag(777888, 1)
	var dag2: Array[Dictionary] = MapGenerator.generate_sector_dag(777888, 1)
	assert(dag1.size() == dag2.size(), "DAG generation must be deterministic for same seed")
	var max_floor: int = int(dag1[dag1.size() - 1]["floor"])
	var boss_type: String = String(dag1[dag1.size() - 1]["type"])
	print("[4] Generated DAG nodes: ", dag1.size(), " | Top floor: ", max_floor, " (", boss_type, ")")
	assert(max_floor == 15 and boss_type == "BOSS", "Floor 15 must be BOSS node")

	# 5. Verify SaveManager persistence (user://meta_save.json and user://current_run.json)
	SaveManager.save_meta()
	SaveManager.save_run()
	var loaded_ok: bool = SaveManager.load_run()
	print("[5] Persistence check: load_run()=", loaded_ok, " seed=", SaveManager.run_seed)
	assert(loaded_ok and SaveManager.run_seed == 777888, "Run save/load roundtrip failed")

	# 6. Instantiate and test all 6 scenes in SceneTree
	var scenes_to_test: Array[String] = [
		"res://src/core/game_root.tscn",
		"res://src/hub/hub_scene.tscn",
		"res://src/map/map_scene.tscn",
		"res://src/combat/combat_arena.tscn",
		"res://src/garage/garage_scene.tscn",
		"res://src/event/event_scene.tscn"
	]
	for spath: String in scenes_to_test:
		var packed: PackedScene = load(spath) as PackedScene
		assert(packed != null, "Failed to load scene: " + spath)
		var node: Node = packed.instantiate()
		add_child(node)
		await get_tree().process_frame
		if spath == "res://src/combat/combat_arena.tscn":
			var arena: CombatArena = node as CombatArena
			arena._begin_enemy_turn(0)
			await get_tree().create_timer(0.6).timeout
			# Test real bullet hit & freed Area2D inside _bullets array across frames
			arena._dodge_arena._spawn_pattern_wave()
			assert(arena._dodge_arena._bullets.size() > 0, "Bullet should be spawned")
			var b_node: Area2D = arena._dodge_arena._bullets[0]["node"] as Area2D
			arena._dodge_arena._on_segment_hit(PartData.PartSlot.BODY, b_node)
			await get_tree().process_frame
			await get_tree().process_frame
			# Step _process after bullet is freed to verify no freed-object cast error
			arena._dodge_arena._process(1.5)
			arena._dodge_arena._process(2.5)
			assert(not arena._dodge_arena._active, "DodgeArena must finish when timer expires")
			await get_tree().create_timer(0.5).timeout

			# Test immediate termination when defending cat's Body HP reaches 0
			arena._begin_enemy_turn(0)
			await get_tree().create_timer(0.6).timeout
			var def_cat: CatMechInstance = arena._party[arena._defending_cat_index]
			def_cat.body_part.current_hp = 1
			arena._on_dodge_part_hit(PartData.PartSlot.BODY, 50)
			await get_tree().process_frame
			assert(not arena._dodge_arena._active, "DodgeArena must stop immediately when cat Body HP reaches 0")
			await get_tree().create_timer(0.5).timeout
		elif spath == "res://src/garage/garage_scene.tscn":
			var garage: GarageScene = node as GarageScene
			assert(garage._exit_btn != null and garage._exit_btn.is_inside_tree(), "Garage must have active exit button in scene tree")
			assert(garage._repair_all_btn != null and garage._repair_all_btn.is_inside_tree(), "Garage must have repair_all button")
		node.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("[6] Scene verified OK: ", spath)

	# 7. Verify Story & Cutscene Timelines (.dtl) and Boss Portraits (Issue #7)
	var story_timelines: Array[String] = [
		"res://data/dialogues/story_intro_crash.dtl",
		"res://data/dialogues/boss_prelude_sector1.dtl",
		"res://data/dialogues/boss_prelude_sector2.dtl",
		"res://data/dialogues/boss_prelude_sector3.dtl",
		"res://data/dialogues/boss_postlude_sector1.dtl",
		"res://data/dialogues/boss_postlude_sector2.dtl",
		"res://data/dialogues/boss_postlude_sector3.dtl"
	]
	for tl_path: String in story_timelines:
		assert(FileAccess.file_exists(tl_path), "Timeline missing: " + tl_path)
		var f: FileAccess = FileAccess.open(tl_path, FileAccess.READ)
		var txt: String = f.get_as_text()
		f.close()
		assert(txt.length() > 50, "Timeline file too short: " + tl_path)

	# Verify portraits for 4 cats and 3 bosses across 4 mood states
	var required_portraits: Array[String] = [
		"felix", "mule", "hound", "cock", "atamansha", "press", "satellite"
	]
	var moods: Array[String] = ["normal", "battle", "damaged", "glitch"]
	for p_char: String in required_portraits:
		for mood: String in moods:
			var img_path: String = "res://assets/sprites/portraits/" + p_char + "_" + mood + ".png"
			assert(ResourceLoader.exists(img_path), "Portrait texture missing: " + img_path)

	# Test EventScene with story cutscene payload
	var ev_scene_packed: PackedScene = load("res://src/event/event_scene.tscn") as PackedScene
	var ev_node: EventScene = ev_scene_packed.instantiate() as EventScene
	ev_node.setup_event({
		"timeline": "res://data/dialogues/story_intro_crash.dtl",
		"next_scene": &"MAP",
		"title": "ТЕСТОВОЕ ИНТРО",
		"continue_text": "ВПЕРЁД ->",
		"action_on_complete": "save"
	})
	add_child(ev_node)
	await get_tree().process_frame
	# Advance through all lines of narrative cutscene
	while ev_node._line_cursor < ev_node._lines.size() - 1:
		ev_node._line_cursor += 1
		ev_node._render_dialogue_state()
	assert(ev_node._continue_btn.visible, "Continue button must be visible at end of narrative cutscene")
	assert(ev_node._continue_btn.text == "ВПЕРЁД ->", "Continue button text mismatch")
	ev_node.queue_free()
	await get_tree().process_frame
	print("[7] Story cutscenes, boss preludes/postludes and portraits verified OK")

	AudioManager.stop_music()
	await get_tree().process_frame
	SaveManager.delete_run_save()
	print("=== ALL SYSTEMS VERIFIED SUCCESSFULLY WITH 0 ERRORS ===")
	get_tree().quit(0)
