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

			# Verify Marker2D joints and CPUParticles2D hierarchy on cat rigs (Issue #11)
			assert(arena._cat_rigs.size() > 0, "Cat rigs must be spawned")
			for crig: Dictionary in arena._cat_rigs:
				var body_s: Sprite2D = crig["body_spr"] as Sprite2D
				assert(body_s != null and body_s.has_node("ArmsJoint") and body_s.has_node("LegsJoint"), "Body sprite must have ArmsJoint and LegsJoint Marker2D nodes")
				var arms_j: Marker2D = body_s.get_node("ArmsJoint") as Marker2D
				var legs_j: Marker2D = body_s.get_node("LegsJoint") as Marker2D
				assert(arms_j != null and legs_j != null, "Joints must be Marker2D")
				assert(crig["arms_spr"].get_parent() == arms_j, "ArmsSprite must be child of ArmsJoint")
				assert(crig["legs_spr"].get_parent() == legs_j, "LegsSprite must be child of LegsJoint")
				assert(crig["body_smoke"] is CPUParticles2D and crig["body_sparks"] is CPUParticles2D, "Body must have smoke/sparks CPUParticles2D")
				assert(crig["arms_smoke"] is CPUParticles2D and crig["arms_sparks"] is CPUParticles2D, "Arms must have smoke/sparks CPUParticles2D")
				assert(crig["legs_smoke"] is CPUParticles2D and crig["legs_sparks"] is CPUParticles2D, "Legs must have smoke/sparks CPUParticles2D")

			# Verify damage number floating label
			var dmg_lbl: Label = arena.spawn_damage_number(Vector2(200, 150), "-25", Color.RED)
			assert(dmg_lbl != null and dmg_lbl.is_inside_tree(), "Damage number label must be spawned in tree")

			# Verify screen shake and recoil triggers without exceptions
			arena._trigger_screenshake(4.0, 0.05)
			arena._play_cat_attack_recoil(0)
			arena._play_enemy_attack_recoil(0)
			arena._play_rig_hurt(arena._cat_rigs[0], 3.0)

			# Verify CPUParticles2D activation when part HP drops below 25% or breaks
			var test_cat: CatMechInstance = arena._party[0]
			test_cat.body_part.current_hp = int(float(test_cat.body_part.get_max_hp()) * 0.2)
			arena._refresh_hud()
			assert((arena._cat_rigs[0]["body_smoke"] as CPUParticles2D).emitting, "Smoke must emit when HP <= 25%")
			assert((arena._cat_rigs[0]["body_sparks"] as CPUParticles2D).emitting, "Sparks must emit when HP <= 25%")
			test_cat.body_part.repair_full()
			arena._refresh_hud()
			assert(not (arena._cat_rigs[0]["body_smoke"] as CPUParticles2D).emitting, "Smoke must stop when HP > 25%")

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
			# Verify Marker2D joints on garage preview (Issue #11)
			assert(garage._preview_body != null and garage._preview_body.has_node("ArmsJoint") and garage._preview_body.has_node("LegsJoint"), "Garage preview body must have ArmsJoint and LegsJoint Marker2D nodes")
			assert(garage._preview_arms.get_parent() == garage._preview_body.get_node("ArmsJoint"), "Preview arms must be child of ArmsJoint")
			assert(garage._preview_legs.get_parent() == garage._preview_body.get_node("LegsJoint"), "Preview legs must be child of LegsJoint")
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

	# Verify all 9 Brothers Grimm story cutscene illustrations
	var story_illustrations: Array[String] = [
		"res://assets/sprites/story/story_cat_exile.png",
		"res://assets/sprites/story/story_cat_alone_road.png",
		"res://assets/sprites/story/story_meet_hound.png",
		"res://assets/sprites/story/story_mill_mule_captive.png",
		"res://assets/sprites/story/story_mule_joins.png",
		"res://assets/sprites/story/story_tavern_cock_soup.png",
		"res://assets/sprites/story/story_cock_joins_quartet.png",
		"res://assets/sprites/story/story_bremen_window_pyramid.png",
		"res://assets/sprites/story/story_bremen_victory_concert.png"
	]
	for sil_path: String in story_illustrations:
		assert(ResourceLoader.exists(sil_path), "Story illustration missing: " + sil_path)

	# Verify progressive Bremen Musicians party recruitment (Sector 1: 2 -> Sector 2: 3 -> Sector 3: 4)
	SaveManager.start_new_run(777888)
	assert(SaveManager.party.size() == 2, "Sector 1 must start with FELIX + HOUND (2 musicians)")
	SaveManager.advance_to_next_sector()
	assert(SaveManager.party.size() == 3 and SaveManager.has_party_member("MULE"), "Sector 2 must recruit MULE (3 musicians)")
	SaveManager.advance_to_next_sector()
	assert(SaveManager.party.size() == 4 and SaveManager.has_party_member("COCK"), "Sector 3 must recruit COCK (4 musicians)")

	# Test EventScene with story cutscene payload and dynamic illustration switching
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
	assert(ev_node._illustration_rect.texture != null, "Story illustration must be loaded on first slide")
	# Advance through all lines of narrative cutscene
	while ev_node._line_cursor < ev_node._lines.size() - 1:
		ev_node._line_cursor += 1
		ev_node._render_dialogue_state()
	assert(ev_node._continue_btn.visible, "Continue button must be visible at end of narrative cutscene")
	assert(ev_node._continue_btn.text == "ВПЕРЁД ->", "Continue button text mismatch")
	ev_node.queue_free()
	await get_tree().process_frame
	print("[7] Bremen Musicians story cutscenes, 9 illustrations, party recruitment (2->3->4) verified OK")

	AudioManager.stop_music()
	await get_tree().process_frame
	SaveManager.delete_run_save()
	print("=== ALL SYSTEMS VERIFIED SUCCESSFULLY WITH 0 ERRORS ===")
	get_tree().quit(0)
