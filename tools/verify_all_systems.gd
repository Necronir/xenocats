extends Node

func _ready() -> void:
	print("=== XENOCATS: BREMEN-4 AUTOMATED VERIFICATION ===")
	DataCatalog.ensure_loaded()
	SaveManager.hard_reset_all_progress()
	if SaveManager.settings != null:
		SaveManager.settings.tutorials_enabled = false

	# 1. Verify .tres catalog counts
	var parts_count: int = DataCatalog.get_all_parts().size()
	var tapes_count: int = DataCatalog.get_all_tapes().size()
	print("[1] Loaded parts: ", parts_count, " | tapes: ", tapes_count)
	assert(parts_count >= 16, "Expected at least 16 parts in catalog")
	assert(tapes_count >= 4, "Expected at least 4 music tapes in catalog")
	assert(DataCatalog.get_tape("tape_bremen_triumph") != null, "tape_bremen_triumph must be registered in catalog")

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
		"res://src/event/event_scene.tscn",
		"res://src/core/video_player_scene.tscn",
		"res://src/epilogue/epilogue_scene.tscn"
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
			# Verify Weight indicator and Progress bar (Issue #8)
			assert(garage.find_child("WeightIndicatorBox", true, false) != null, "Garage must display WeightIndicatorBox")
			assert(garage.find_child("WeightSummaryLabel", true, false) != null, "Garage must display WeightSummaryLabel")
			assert(garage.find_child("WeightProgressBar", true, false) != null, "Garage must display WeightProgressBar")
		node.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("[6] Scene verified OK: ", spath)

	# 7. Verify Story & Cutscene Timelines (.dtl) and Boss Portraits (Issue #7)
	var story_timelines: Array[String] = [
		"res://data/dialogues/story_intro_crash.dtl",
		"res://data/dialogues/story_intro_cat.dtl",
		"res://data/dialogues/story_intro_hound.dtl",
		"res://data/dialogues/boss_prelude_sector1.dtl",
		"res://data/dialogues/boss_prelude_sector2.dtl",
		"res://data/dialogues/boss_prelude_sector3.dtl",
		"res://data/dialogues/boss_postlude_sector1.dtl",
		"res://data/dialogues/boss_postlude_sector2.dtl",
		"res://data/dialogues/boss_postlude_sector3.dtl",
		"res://data/dialogues/boss_prelude_sputnik_solo.dtl",
		"res://data/dialogues/boss_postlude_sputnik_solo.dtl"
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
	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_1_DUO)
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

	# 7.1 Verify Issue #24 Plot Photos, Video assets and VideoPlayerScene
	var plot_photos: Array[String] = [
		"res://assets/photos/0-battle-fail.jpg",
		"res://assets/photos/1-1-cat-start.jpg",
		"res://assets/photos/1-2-sputnik-apperiance.jpg",
		"res://assets/photos/1-3-cat-and-sputnik.jpg",
		"res://assets/photos/1-4a-cat-and-sputnik-fail.jpg",
		"res://assets/photos/1-4b-trubadur-apperiance.jpg",
		"res://assets/photos/1-5a-trubadur-fail.jpg",
		"res://assets/photos/1-5b-trubadur-win.jpg",
		"res://assets/photos/2-1-cat-and-hound-together.jpg",
		"res://assets/photos/2-2-press-boss-appirance.jpg",
		"res://assets/photos/2-3a-press-boss-win.jpg",
		"res://assets/photos/2-3b-press-boss-fail.jpg",
		"res://assets/photos/3-1-atamansha-boss-apperiance.jpg",
		"res://assets/photos/3-2a-atamansha-boss-win.jpg",
		"res://assets/photos/3-2b-atamansha-boss-fail.jpg",
		"res://assets/photos/4-1-sputnik-boss-apperiance.jpg",
		"res://assets/photos/4-2a-sputnik-boss-win.jpg",
		"res://assets/photos/4-2b-sputnik-boss-fail.jpg",
		"res://assets/photos/5-1-trubadur-full.jpg",
		"res://assets/photos/5-2-trubadur-blue.jpg",
		"res://assets/photos/5-3-trubadur-red.jpg",
		"res://assets/photos/5-3-trubadur-yellow.jpg",
		"res://assets/photos/5-4-trubadur-win.jpg",
		"res://assets/photos/5-4a-trubadur-fail.jpg",
		"res://assets/photos/6-1-fake-boss-apperiance.jpg",
		"res://assets/photos/6-2-fake-boss-monster.jpg",
		"res://assets/photos/6-3-fake-boss-piramide.jpg",
		"res://assets/photos/6-4-fake-boss-win.jpg",
		"res://assets/photos/7-final.jpg"
	]
	for ppath: String in plot_photos:
		assert(ResourceLoader.exists(ppath), "Plot photo missing: " + ppath)
		var p_tex: Texture2D = ResourceLoader.load(ppath) as Texture2D
		assert(p_tex != null, "Failed to load plot photo texture: " + ppath)

	var vid_packed: PackedScene = load("res://src/core/video_player_scene.tscn") as PackedScene
	assert(vid_packed != null, "video_player_scene.tscn must be loadable")

	# Test VideoPlayerScene with Photo Slide
	var photo_scene: VideoPlayerScene = vid_packed.instantiate() as VideoPlayerScene
	photo_scene.setup_video({
		"image_path": "res://assets/photos/1-cat-start.jpg",
		"title": "ТЕСТОВОЕ ФОТО",
		"next_scene": &"HUB",
		"next_payload": {}
	})
	add_child(photo_scene)
	await get_tree().process_frame
	assert(photo_scene._photo_rect != null, "Photo rect must exist")
	assert(photo_scene._skip_btn != null, "Skip/Continue button must exist")
	photo_scene._on_skip_pressed()
	assert(photo_scene._is_finishing, "Skip button must trigger finish")
	photo_scene.queue_free()
	await get_tree().process_frame

	# Test VideoPlayerScene with Video Stream
	var vid_scene: VideoPlayerScene = vid_packed.instantiate() as VideoPlayerScene
	vid_scene.setup_video({
		"video_path": "res://assets/videos/1-cat.ogv",
		"title": "ТЕСТОВОЕ ВИДЕО",
		"next_scene": &"HUB",
		"next_payload": {}
	})
	add_child(vid_scene)
	await get_tree().process_frame
	assert(vid_scene._video_player != null, "Video player node must exist")
	vid_scene._on_skip_pressed()
	assert(vid_scene._is_finishing, "Skip button must trigger finish")
	vid_scene.queue_free()
	await get_tree().process_frame
	print("[7.1] All 13 Plot photos, video assets, and cutscene player modes verified OK")

	# 8. Verify Sector 3 Boss Victory Screen, Run Statistics, Meta-Rewards & Save Lifecycle (Issue #6)
	SaveManager.start_new_run(888999)
	SaveManager.advance_to_next_sector() # Sector 2
	SaveManager.advance_to_next_sector() # Sector 3 (4 cats)
	SaveManager.run_elapsed_sec = 425.0  # 07:05
	SaveManager.record_enemies_defeated(12)
	var pre_scrap: int = SaveManager.titanium_scrap
	var pre_cores: int = SaveManager.ai_cores
	var pre_evacs: int = SaveManager.successful_evacuations

	var boss_arena_packed: PackedScene = load("res://src/combat/combat_arena.tscn") as PackedScene
	var boss_arena: CombatArena = boss_arena_packed.instantiate() as CombatArena
	boss_arena.setup_battle({"node_id": 99, "node_type": "BOSS"})
	add_child(boss_arena)
	await get_tree().process_frame
	assert(boss_arena._enemies.size() == 1 and boss_arena._enemies[0].data.is_boss, "Sector 3 boss must be spawned")
	boss_arena._enemies[0].body_part.current_hp = 0
	boss_arena._handle_victory()

	assert(boss_arena._end_overlay.visible, "Victory overlay must be visible on Sector 3 boss defeat")
	assert(
		boss_arena._end_title.text == "СИГНАЛ SOS БРЕМЕН-4 ПЕРЕДАН В ОТКРЫТЫЙ КОСМОС!",
		"Victory title must match Bremen-4 SOS broadcast message"
	)
	assert(boss_arena._end_desc.text.contains("07:05"), "Victory screen must display formatted run time")
	assert(boss_arena._end_desc.text.contains("Побеждено врагов: 13"), "Victory screen must display total defeated enemies")
	assert(boss_arena._end_desc.text.contains("Спасенные детали:"), "Victory screen must display salvaged parts count")
	assert(boss_arena._end_desc.text.contains("Заработанные ресурсы:"), "Victory screen must display earned resources")
	assert(boss_arena._end_btn.text == "В ЛАГЕРЬ БРОДЯГ (ХАБ)", "Victory screen must have Hub return button")
	assert(not SaveManager.has_active_run and not FileAccess.file_exists(SaveManager.RUN_SAVE_PATH), "Current run save must be deleted on victory")
	assert(SaveManager.titanium_scrap >= pre_scrap + SaveManager.VICTORY_BONUS_SCRAP, "Meta titanium scrap bonus must be awarded")
	assert(SaveManager.ai_cores >= pre_cores + SaveManager.VICTORY_BONUS_CORES, "Meta AI cores bonus must be awarded")
	SaveManager.load_meta()
	assert(SaveManager.successful_evacuations == pre_evacs + 1, "Successful evacuations counter must be persisted in meta_save.json")

	boss_arena.queue_free()
	await get_tree().process_frame
	print("[8] Sector 3 Boss Victory screen, SOS Bremen-4 broadcast, run stats & meta-save verified OK")

	# 9. Verify Developer Fast-Track Menu (DevMenuBar & jump_to_boss_battle) (Issue #16)
	SaveManager.start_new_run(999111)
	var map_packed: PackedScene = load("res://src/map/map_scene.tscn") as PackedScene
	var map_inst: MapScene = map_packed.instantiate() as MapScene
	add_child(map_inst)
	await get_tree().process_frame
	assert(map_inst._dev_menu_bar != null and map_inst._dev_menu_bar.is_inside_tree(), "MapScene must have DevMenuBar at the top")
	assert(map_inst._fast_boss_btn != null and map_inst._fast_boss_btn.is_inside_tree(), "MapScene top bar must have fast boss button")
	assert(map_inst._dev_menu_bar._current_boss_btn != null, "DevMenuBar must have current level boss button")
	assert(map_inst._dev_menu_bar._boss1_btn != null and map_inst._dev_menu_bar._boss2_btn != null and map_inst._dev_menu_bar._boss3_btn != null, "DevMenuBar must have Boss 1/2/3 buttons")
	map_inst.queue_free()
	await get_tree().process_frame

	var captured_scene: Array[String] = [""]
	var captured_payload: Array[Dictionary] = [{}]
	var scene_cb: Callable = func(sc_name: StringName, pl: Dictionary) -> void:
		captured_scene[0] = String(sc_name)
		captured_payload[0] = pl
	EventBus.request_scene_change.connect(scene_cb)

	# Jump to current sector (Sector 1) boss prelude dialogue
	var p1: Dictionary = SaveManager.jump_to_boss_battle(-1)
	assert(captured_scene[0] == "EVENT" and String(p1.get("timeline", "")) == "res://data/dialogues/boss_prelude_sector1.dtl", "jump_to_boss_battle(-1) must request EVENT with boss_prelude_sector1.dtl")
	assert(String(p1.get("next_scene", "")) == "BATTLE" and String((p1.get("next_payload", {}) as Dictionary).get("node_type", "")) == "BOSS", "Prelude event must lead to BOSS BATTLE")
	assert(SaveManager.current_sector == 1 and SaveManager.current_floor == 15, "Sector 1 boss jump must set floor to 15")
	assert(SaveManager.party.size() == 2, "Sector 1 boss jump must have 2 cats")

	# Jump directly to Sector 2 boss prelude dialogue
	var p2: Dictionary = SaveManager.jump_to_boss_battle(2)
	assert(captured_scene[0] == "EVENT" and String(p2.get("timeline", "")) == "res://data/dialogues/boss_prelude_sector2.dtl", "jump_to_boss_battle(2) must request EVENT with boss_prelude_sector2.dtl")
	assert(SaveManager.current_sector == 2 and SaveManager.current_floor == 15, "Sector 2 boss jump must set sector=2, floor=15")
	assert(SaveManager.party.size() == 3 and SaveManager.has_party_member("MULE"), "Sector 2 boss jump must include MULE")

	# Jump directly to Sector 3 boss prelude dialogue
	var p3: Dictionary = SaveManager.jump_to_boss_battle(3)
	assert(captured_scene[0] == "EVENT" and String(p3.get("timeline", "")) == "res://data/dialogues/boss_prelude_sector3.dtl", "jump_to_boss_battle(3) must request EVENT with boss_prelude_sector3.dtl")
	assert(SaveManager.current_sector == 3 and SaveManager.current_floor == 15, "Sector 3 boss jump must set sector=3, floor=15")
	assert(SaveManager.party.size() == 4 and SaveManager.has_party_member("COCK"), "Sector 3 boss jump must include full quartet")

	EventBus.request_scene_change.disconnect(scene_cb)
	print("[9] Developer Fast-Track Menu (DevMenuBar & jump_to_boss_battle) verified OK")

	# 10. Verify Bremen Pyramid Unified HP Pool, Proportional Damage Routing, Undock VFX/SFX & Progressive Story Melodies (Issue #9)
	var required_themes: Dictionary = {
		"FELIX": ["res://assets/audio/themes/theme_felix_guitar.wav", "Гитара"],
		"MULE": ["res://assets/audio/themes/theme_mule_bass.wav", "Бас"],
		"HOUND": ["res://assets/audio/themes/theme_hound_drums.wav", "Барабан"],
		"COCK": ["res://assets/audio/themes/theme_cock_synth.wav", "Синтезатор"]
	}
	for c_key: String in required_themes.keys():
		var t_info: Array = required_themes[c_key] as Array
		var t_path: String = String(t_info[0])
		assert(ResourceLoader.exists(t_path), "Character theme WAV missing: " + t_path)

	assert(ResourceLoader.exists("res://assets/audio/themes/theme_duo_cat_hound.wav"), "Duo theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_trio_cat_hound_mule.wav"), "Trio theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_bremen_ensemble.wav"), "Ensemble theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_pyramid_2.wav"), "Pyramid 2 theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_pyramid_3.wav"), "Pyramid 3 theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_pyramid_4.wav"), "Pyramid 4 theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_boss_sector1.wav"), "Boss 1 theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_boss_sector2.wav"), "Boss 2 theme WAV missing")
	assert(ResourceLoader.exists("res://assets/audio/themes/theme_boss_sector3.wav"), "Boss 3 theme WAV missing")
	assert(ResourceLoader.exists("res://assets/sprites/cats/bremen_pyramid_2.png"), "2-tier tower sprite missing")
	assert(ResourceLoader.exists("res://assets/sprites/cats/bremen_pyramid_3.png"), "3-tier tower sprite missing")
	assert(ResourceLoader.exists("res://assets/sprites/cats/bremen_pyramid.png"), "4-tier tower sprite missing")
	assert(ResourceLoader.exists("res://assets/audio/sfx/pyramid_undock.wav"), "Pyramid undock SFX WAV missing")

	# Verify Boss themes use only the party's current instruments for that sector (no foreign instruments)
	AudioManager.play_boss_theme(1)
	assert(AudioManager.current_theme_id == &"BOSS_1" and AudioManager.active_instruments == ["Гитара", "Барабан"], "Boss 1 theme must use Sector 1 instruments (Guitar + Drums)")
	AudioManager.play_boss_theme(2)
	assert(AudioManager.current_theme_id == &"BOSS_2" and AudioManager.active_instruments == ["Гитара", "Барабан", "Бас"], "Boss 2 theme must use Sector 2 instruments (Guitar + Drums + Bass)")
	AudioManager.play_boss_theme(3)
	assert(AudioManager.current_theme_id == &"BOSS_3" and AudioManager.active_instruments == ["Гитара", "Барабан", "Бас", "Синтезатор"], "Boss 3 theme must use Sector 3 instruments (all 4)")

	# Verify progressive story music stages: 1 (Cat) -> 2 (Cat+Dog) -> 3 (Cat+Dog+Donkey) -> 4 (Full Quartet)
	AudioManager.play_story_stage(1)
	assert(AudioManager.current_story_stage == 1 and AudioManager.active_instruments == ["Гитара"], "Stage 1 must play only Cat's Guitar")

	# Verify Prologue cutscene progression: starts with Stage 1 (Cat alone), switches to Stage 2 when meeting Hound
	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_1_DUO)
	SaveManager.start_new_run(444555)
	var intro_ev: EventScene = ev_scene_packed.instantiate() as EventScene
	intro_ev.setup_event({"timeline": "res://data/dialogues/story_intro_crash.dtl"})
	add_child(intro_ev)
	await get_tree().process_frame
	assert(AudioManager.current_story_stage == 1 and AudioManager.active_instruments.size() == 1, "Prologue slide 1 (story_cat_exile.png) must play Stage 1 (only Cat)")
	intro_ev._line_cursor = 5
	intro_ev._render_dialogue_state()
	assert(AudioManager.current_story_stage == 2 and AudioManager.active_instruments == ["Гитара", "Барабан"], "Prologue slide 3 (story_meet_hound.png) must play Stage 2 (Cat + Dog)")
	intro_ev.queue_free()
	await get_tree().process_frame

	# Sector 1 (2 cats) -> Stage 2; Sector 2 (3 cats) -> Stage 3; Sector 3 (4 cats) -> Stage 4
	var pyr_arena_packed: PackedScene = load("res://src/combat/combat_arena.tscn") as PackedScene
	AudioManager.sync_music_to_party(SaveManager.party)
	assert(AudioManager.current_story_stage == 2 and AudioManager.active_instruments.size() == 2, "2-cat party must play Stage 2 (Guitar + Drums)")

	# Verify Tier 2 Small Tower ("Дуэт") in Sector 1 (2 cats)
	var pyr_arena_t2: CombatArena = pyr_arena_packed.instantiate() as CombatArena
	pyr_arena_t2.setup_battle({"node_id": 10, "node_type": "COMBAT"})
	add_child(pyr_arena_t2)
	await get_tree().process_frame
	SaveManager.sync_gauge = 100
	pyr_arena_t2._activate_bremen_pyramid()
	assert(pyr_arena_t2._pyramid_tier == 2, "2-cat party must build 2-tier Small Tower")
	assert(AudioManager.current_theme_id == &"PYRAMID_2" and AudioManager.active_instruments.has("Резонатор «Бремен»"), "Tier 2 Tower must play PYRAMID_2 with Resonator")
	assert(DataCatalog.get_skill("pyramid_2_acoustic_storm").base_damage == 26 and DataCatalog.get_skill("pyramid_2_cascade_overload").base_damage == 46, "Tier 2 Tower skills must be ~55% power")
	pyr_arena_t2.queue_free()
	await get_tree().process_frame

	SaveManager.advance_to_next_sector()
	AudioManager.sync_music_to_party(SaveManager.party)
	assert(AudioManager.current_story_stage == 3 and AudioManager.active_instruments == ["Гитара", "Барабан", "Бас"], "3-cat party must play Stage 3 (Guitar + Drums + Bass)")

	# Verify Tier 3 Medium Tower ("Трио") in Sector 2 (3 cats)
	var pyr_arena_t3: CombatArena = pyr_arena_packed.instantiate() as CombatArena
	pyr_arena_t3.setup_battle({"node_id": 25, "node_type": "COMBAT"})
	add_child(pyr_arena_t3)
	await get_tree().process_frame
	SaveManager.sync_gauge = 100
	pyr_arena_t3._activate_bremen_pyramid()
	assert(pyr_arena_t3._pyramid_tier == 3, "3-cat party must build 3-tier Medium Tower")
	assert(AudioManager.current_theme_id == &"PYRAMID_3" and AudioManager.active_instruments.has("Резонатор «Бремен»"), "Tier 3 Tower must play PYRAMID_3 with Resonator")
	assert(DataCatalog.get_skill("pyramid_3_acoustic_storm").base_damage == 36 and DataCatalog.get_skill("pyramid_3_cascade_overload").base_damage == 64, "Tier 3 Tower skills must be ~75% power")
	pyr_arena_t3.queue_free()
	await get_tree().process_frame

	SaveManager.advance_to_next_sector()
	AudioManager.sync_music_to_party(SaveManager.party)
	assert(AudioManager.current_story_stage == 4 and AudioManager.active_instruments == ["Гитара", "Барабан", "Бас", "Синтезатор"], "4-cat party must play Stage 4 (Full Quartet)")

	# Prepare full quartet (4 cats) and damage one part slightly to verify exact total_current_hp / total_max_hp
	assert(SaveManager.party.size() == 4, "Quartet must have 4 cats")
	SaveManager.party[0].arms_part.current_hp -= 10

	var expected_curr_hp: int = 0
	var expected_max_hp: int = 0
	for c_inst: CatMechInstance in SaveManager.party:
		expected_curr_hp += c_inst.get_total_current_hp()
		expected_max_hp += c_inst.get_total_max_hp()

	var pyr_arena: CombatArena = pyr_arena_packed.instantiate() as CombatArena
	pyr_arena.setup_battle({"node_id": 50, "node_type": "ELITE"})
	add_child(pyr_arena)
	await get_tree().process_frame

	SaveManager.sync_gauge = 100
	pyr_arena._activate_bremen_pyramid()
	assert(pyr_arena._pyramid_active and pyr_arena._pyramid_tier == 4, "Bremen Pyramid Tier 4 must be active")
	assert(pyr_arena._pyramid_current_hp == expected_curr_hp, "Pyramid current HP must equal sum of all alive cats' current HP")
	assert(pyr_arena._pyramid_max_hp == expected_max_hp, "Pyramid max HP must equal sum of all alive cats' max HP")
	assert(pyr_arena._pyramid_hp_bar != null and pyr_arena._pyramid_hp_bar.is_inside_tree(), "HUD must display unified Pyramid HP ProgressBar")
	assert(int(pyr_arena._pyramid_hp_bar.value) == expected_curr_hp and int(pyr_arena._pyramid_hp_bar.max_value) == expected_max_hp, "Unified HP bar values must match total_current_hp / total_max_hp")
	assert(pyr_arena._pyramid_hp_label != null and pyr_arena._pyramid_hp_label.text.contains(str(expected_curr_hp) + "/" + str(expected_max_hp)), "Unified HP label must show total_current_hp/total_max_hp")
	assert(AudioManager.current_theme_id == &"PYRAMID_4" and AudioManager.active_instruments.size() == 5 and AudioManager.active_instruments.has("Резонатор «Бремен»"), "Full Pyramid mode must play 4 instruments + Bremen Resonator")

	# Route damage to Pyramid totem during docking round
	pyr_arena._on_dodge_part_hit(PartData.PartSlot.BODY, 60)
	pyr_arena._on_dodge_part_hit(PartData.PartSlot.ARMS, 40)
	assert(pyr_arena._pyramid_current_hp == expected_curr_hp - 100, "Pyramid HP pool must deduct 100 routed damage")
	assert(pyr_arena._pyramid_damage_taken == 100, "Pyramid must track 100 total damage taken")
	assert(int(pyr_arena._pyramid_hp_bar.value) == expected_curr_hp - 100, "Unified HP bar must update after totem takes damage")

	# Undock at end of Pyramid round and verify proportional damage distribution + undock audio/visual accent
	var undock_emitted: Array[bool] = [false]
	var undock_cb: Callable = func() -> void:
		undock_emitted[0] = true
	EventBus.pyramid_deactivated.connect(undock_cb)

	var dist_info: Dictionary = pyr_arena._deactivate_bremen_pyramid()
	EventBus.pyramid_deactivated.disconnect(undock_cb)

	assert(not pyr_arena._pyramid_active, "Pyramid must be inactive after undock")
	assert(undock_emitted[0], "pyramid_deactivated signal must be emitted on undock")
	assert(AudioManager.last_sfx_played == "pyramid_undock", "pyramid_undock SFX must play on undock")
	assert(int(dist_info.get("total_distributed", 0)) == 100, "All 100 damage from Pyramid pool must be distributed to cat parts")

	var post_undock_hp: int = 0
	for c_after: CatMechInstance in SaveManager.party:
		post_undock_hp += c_after.get_total_current_hp()
		assert(c_after.get_total_current_hp() < c_after.get_total_max_hp(), "Each alive cat must receive proportional share of totem damage")
	assert(post_undock_hp == expected_curr_hp - 100, "Sum of party parts HP after undock must equal Pyramid remaining HP pool")

	pyr_arena.queue_free()
	await get_tree().process_frame
	print("[10] Bremen Pyramid Unified HP Pool, proportional damage routing, undock VFX/SFX & 4 instrument themes verified OK")

	# 11. Verify Settings, Audio Buses, Pause Menu, Battle Retry Checkpoint & Tutorial System (Issue #12)
	var music_bus_idx: int = AudioServer.get_bus_index(AudioManager.BUS_MUSIC)
	var sfx_bus_idx: int = AudioServer.get_bus_index(AudioManager.BUS_SFX)
	assert(music_bus_idx >= 0 and sfx_bus_idx >= 0, "Music and SFX audio buses must exist")
	assert(AudioManager._music_player.bus == AudioManager.BUS_MUSIC, "Music player must be routed to Music bus")
	assert(AudioManager._sfx_players[0].bus == AudioManager.BUS_SFX, "SFX players must be routed to SFX bus")

	SaveManager.settings.set_bus_linear(AudioManager.BUS_MUSIC, 0.5)
	assert(is_equal_approx(AudioServer.get_bus_volume_db(music_bus_idx), linear_to_db(0.5)), "Music bus dB must match linear_to_db(0.5)")
	assert(not AudioServer.is_bus_mute(music_bus_idx), "Music bus must not be muted at 0.5")
	SaveManager.settings.set_bus_linear(AudioManager.BUS_MUSIC, 0.0)
	assert(AudioServer.is_bus_mute(music_bus_idx), "Music bus must be muted at 0.0")
	SaveManager.settings.set_bus_linear(AudioManager.BUS_MUSIC, 0.85)

	AudioManager.set_pause_duck(true)
	assert(AudioManager.is_pause_ducked, "AudioManager must report pause ducking active")
	assert(AudioServer.is_bus_effect_enabled(music_bus_idx, 0) and AudioServer.is_bus_effect_enabled(music_bus_idx, 1), "Music bus ducking effects (LPF + Amplify) must be enabled on pause")
	AudioManager.set_pause_duck(false)
	assert(not AudioServer.is_bus_effect_enabled(music_bus_idx, 0) and not AudioServer.is_bus_effect_enabled(music_bus_idx, 1), "Music bus ducking effects must be disabled when unpaused")

	# Settings persistence round-trip
	var temp_settings_path: String = "user://verify_test_settings.cfg"
	var gs_out: GameSettings = GameSettings.new()
	gs_out.master_volume = 0.75
	gs_out.music_volume = 0.40
	gs_out.sfx_volume = 0.65
	gs_out.fullscreen = true
	gs_out.tutorials_enabled = false
	gs_out.seen_tutorials = ["elite_targeting", "qte_timing"]
	assert(gs_out.save_to_disk(temp_settings_path), "GameSettings save_to_disk must succeed")

	var gs_in: GameSettings = GameSettings.new()
	assert(gs_in.load_from_disk(temp_settings_path), "GameSettings load_from_disk must succeed")
	assert(is_equal_approx(gs_in.master_volume, 0.75) and is_equal_approx(gs_in.music_volume, 0.40) and is_equal_approx(gs_in.sfx_volume, 0.65), "Loaded volumes must match")
	assert(gs_in.fullscreen == true and gs_in.tutorials_enabled == false, "Loaded display and tutorial flags must match")
	assert(gs_in.seen_tutorials.size() == 2 and gs_in.seen_tutorials.has("elite_targeting"), "Loaded seen_tutorials must match")
	gs_in.apply_display()
	if FileAccess.file_exists(temp_settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_settings_path))

	# PauseMenu in GameRoot: allowed only in MAP and BATTLE, blocked in HUB and after VICTORY
	var root_packed: PackedScene = load("res://src/core/game_root.tscn") as PackedScene
	var root_inst: SceneManager = root_packed.instantiate() as SceneManager
	add_child(root_inst)
	await get_tree().process_frame
	assert(root_inst._pause_menu != null, "GameRoot must own a PauseMenu instance")
	assert(not root_inst._pause_menu.allowed and not root_inst._pause_menu.open(), "PauseMenu must be disallowed in HUB")

	root_inst.change_scene(&"MAP", {})
	await get_tree().process_frame
	assert(root_inst._pause_menu.allowed and root_inst._pause_menu.open(), "PauseMenu must open in MAP")
	assert(get_tree().paused and AudioManager.is_pause_ducked, "Opening PauseMenu must pause SceneTree and duck music")
	assert(not root_inst._pause_menu._retry_battle_btn.visible, "Retry Battle button must be hidden on MAP")
	root_inst._pause_menu.close()
	assert(not get_tree().paused and not AudioManager.is_pause_ducked, "Closing PauseMenu must unpause SceneTree and unduck music")

	root_inst.change_scene(&"BATTLE", {"node_id": 3, "node_type": "COMBAT"})
	await get_tree().process_frame
	assert(root_inst._pause_menu.allowed and root_inst._pause_menu.open(), "PauseMenu must open in BATTLE")
	assert(root_inst._pause_menu._retry_battle_btn.visible, "Retry Battle button must be visible in BATTLE")
	root_inst._pause_menu.close()
	var battle_node: CombatArena = root_inst._current_scene as CombatArena
	battle_node._handle_victory()
	assert(not battle_node.can_pause() and not root_inst._pause_menu.open(), "PauseMenu must be blocked on VICTORY screen")
	root_inst.queue_free()
	await get_tree().process_frame

	# Battle Retry Checkpoint verification
	SaveManager.start_new_run(314159)
	var pre_battle_hp: int = SaveManager.party[0].body_part.current_hp
	var pre_battle_scrap: int = SaveManager.run_scrap
	var retry_arena: CombatArena = pyr_arena_packed.instantiate() as CombatArena
	retry_arena.setup_battle({"node_id": 7, "node_type": "ELITE"})
	add_child(retry_arena)
	await get_tree().process_frame
	assert(int(SaveManager.pending_battle.get("node_id", -1)) == 7 and String(SaveManager.pending_battle.get("node_type", "")) == "ELITE", "CombatArena must record pending_battle checkpoint on entry")
	SaveManager.party[0].body_part.current_hp = 5
	SaveManager.run_scrap = 999
	var restored_payload: Dictionary = SaveManager.restore_battle_checkpoint()
	assert(int(restored_payload.get("node_id", -1)) == 7, "restore_battle_checkpoint must return battle payload")
	assert(SaveManager.party[0].body_part.current_hp == pre_battle_hp and SaveManager.run_scrap == pre_battle_scrap, "restore_battle_checkpoint must restore party HP and scrap to battle entry state")
	SaveManager.clear_battle_checkpoint()
	SaveManager.save_run()
	SaveManager.load_run()
	assert(SaveManager.pending_battle.is_empty(), "clear_battle_checkpoint + save_run must clear pending_battle on disk")
	retry_arena.queue_free()
	await get_tree().process_frame

	# Tutorial Catalog, Modal TutorialOverlay & Non-blocking TutorialToast verification
	var all_tuts: Array[TutorialData] = DataCatalog.get_all_tutorials()
	assert(all_tuts.size() == 4, "DataCatalog must load all 4 TutorialData resources")
	assert(DataCatalog.get_tutorial("pyramid_ready").presentation == TutorialData.Presentation.TOAST, "pyramid_ready tutorial must have TOAST presentation")

	SaveManager.settings.reset_tutorials()
	assert(SaveManager.settings.is_tutorial_needed(&"elite_targeting"), "elite_targeting must be needed after reset")
	TutorialOverlay.show_if_needed(self, &"elite_targeting")
	await get_tree().process_frame
	var active_modals: Array[Node] = get_tree().get_nodes_in_group(&"modal_overlay")
	assert(active_modals.size() == 1 and get_tree().paused, "TutorialOverlay must join modal_overlay group and pause SceneTree")
	var modal_inst: TutorialOverlay = active_modals[0] as TutorialOverlay
	modal_inst.confirm_and_close()
	await get_tree().process_frame
	assert(not get_tree().paused, "Closing TutorialOverlay must restore unpaused state")
	assert(SaveManager.settings.seen_tutorials.has("elite_targeting") and not SaveManager.settings.is_tutorial_needed(&"elite_targeting"), "Confirmed tutorial must be marked seen")

	TutorialOverlay.show_if_needed(self, &"qte_timing")
	await get_tree().process_frame
	var active_modals2: Array[Node] = get_tree().get_nodes_in_group(&"modal_overlay")
	assert(active_modals2.size() == 1, "qte_timing TutorialOverlay must open")
	var modal_inst2: TutorialOverlay = active_modals2[0] as TutorialOverlay
	assert(modal_inst2._ok_btn != null and modal_inst2._ok_btn.has_theme_stylebox_override("focus"), "Tutorial _ok_btn must have high-contrast focus stylebox")
	assert(modal_inst2._disable_btn != null and modal_inst2._disable_btn.has_theme_stylebox_override("focus"), "Tutorial _disable_btn must have high-contrast focus stylebox")

	# Test joypad [X] button skips and disables tutorials
	var joy_x: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_x.button_index = JOY_BUTTON_X
	joy_x.pressed = true
	modal_inst2._input(joy_x)
	await get_tree().process_frame
	assert(not SaveManager.settings.tutorials_enabled, "Joypad [X] must skip and disable tutorials")
	assert(not get_tree().paused, "Joypad [X] must unpause game after skipping tutorial")

	# Test joypad [B] button closes tutorial
	SaveManager.settings.tutorials_enabled = true
	TutorialOverlay.show_if_needed(self, &"dodge_segments")
	await get_tree().process_frame
	var active_modals3: Array[Node] = get_tree().get_nodes_in_group(&"modal_overlay")
	assert(active_modals3.size() == 1, "dodge_segments TutorialOverlay must open")
	var modal_inst3: TutorialOverlay = active_modals3[0] as TutorialOverlay
	var joy_b: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_b.button_index = JOY_BUTTON_B
	joy_b.pressed = true
	modal_inst3._input(joy_b)
	await get_tree().process_frame
	assert(not get_tree().paused, "Joypad [B] must confirm/close tutorial overlay")

	# Test joypad [A] button confirms tutorial
	SaveManager.settings.reset_tutorials()
	TutorialOverlay.show_if_needed(self, &"dodge_segments")
	await get_tree().process_frame
	var active_modals4: Array[Node] = get_tree().get_nodes_in_group(&"modal_overlay")
	assert(active_modals4.size() == 1, "dodge_segments TutorialOverlay re-open must succeed")
	var modal_inst4: TutorialOverlay = active_modals4[0] as TutorialOverlay
	var joy_a: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_a.button_index = JOY_BUTTON_A
	joy_a.pressed = true
	modal_inst4._input(joy_a)
	await get_tree().process_frame
	assert(not get_tree().paused, "Joypad [A] must confirm and close tutorial overlay")

	SaveManager.settings.reset_tutorials()
	var toast_inst: TutorialToast = TutorialToast.show_if_needed(self, &"pyramid_ready")
	assert(toast_inst != null and toast_inst.is_inside_tree(), "TutorialToast must be spawned for pyramid_ready")
	assert(not get_tree().paused, "TutorialToast must NOT pause SceneTree")
	assert(SaveManager.settings.seen_tutorials.has("pyramid_ready"), "TutorialToast must immediately mark pyramid_ready seen")
	toast_inst.dismiss()
	await get_tree().process_frame

	SaveManager.settings.reset_tutorials()
	SaveManager.settings.master_volume = 1.0
	SaveManager.settings.music_volume = 0.85
	SaveManager.settings.sfx_volume = 0.90
	SaveManager.settings.fullscreen = false
	SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
	print("[11] Settings, Audio Buses, Pause Menu, Battle Retry & Tutorial System verified OK")

	# 12. Verify Unique Boss Patterns, Telegraph Markers & Multi-Wave Sequences (Issue #10)
	var b_press: EnemyData = DataCatalog.get_enemy("boss_press")
	var b_ata: EnemyData = DataCatalog.get_enemy("boss_atamansha")
	var b_sat: EnemyData = DataCatalog.get_enemy("boss_satellite")
	assert(b_press != null and b_press.dodge_pattern_id == &"boss_press_hammers", "boss_press must have boss_press_hammers pattern")
	assert(b_press.dodge_patterns.has(&"boss_press_hammers") and b_press.dodge_patterns.has(&"press_crush"), "boss_press must have multi-wave dodge_patterns")
	assert(b_ata != null and b_ata.dodge_pattern_id == &"boss_atamansha_crane", "boss_atamansha must have boss_atamansha_crane pattern")
	assert(b_ata.dodge_patterns.has(&"boss_atamansha_crane") and b_ata.dodge_patterns.has(&"boss_atamansha_rotating"), "boss_atamansha must have rotating laser multi-wave")
	assert(b_sat != null and b_sat.dodge_pattern_id == &"boss_satellite_orbital", "boss_satellite must have boss_satellite_orbital pattern")
	assert(b_sat.dodge_patterns.size() == 3, "boss_satellite must have 3-wave sequence: orbital, homing, and interference")

	var sk_press: SkillData = DataCatalog.get_skill("enemy_heavy_press")
	var sk_laser: SkillData = DataCatalog.get_skill("enemy_laser_barrage")
	var sk_sat: SkillData = DataCatalog.get_skill("enemy_satellite_strike")
	assert(sk_press != null and sk_press.dodge_pattern_id == &"boss_press_hammers", "enemy_heavy_press skill must have boss_press_hammers")
	assert(sk_laser != null and sk_laser.dodge_pattern_id == &"boss_atamansha_crane", "enemy_laser_barrage skill must have boss_atamansha_crane")
	assert(sk_sat != null and sk_sat.dodge_pattern_id == &"boss_satellite_orbital", "enemy_satellite_strike skill must exist")

	# Test Telegraphing primitives & callbacks
	var test_dodge: DodgeArena = DodgeArena.new()
	add_child(test_dodge)
	await get_tree().process_frame
	test_dodge.start_dodge("TEST", &"saw_sweep", 10, 1.0, 10.0)

	var trig: Dictionary = {"rect": false, "line": false, "circle": false}
	test_dodge.add_telegraph_rect(Rect2(20, 20, 30, 80), 0.2, func() -> void:
		trig["rect"] = true
	)
	test_dodge.add_telegraph_line(Vector2(10, 10), Vector2(100, 100), 0.2, func() -> void:
		trig["line"] = true
	)
	test_dodge.add_telegraph_circle(Vector2(50, 50), 15.0, 0.2, func() -> void:
		trig["circle"] = true
	)
	assert(test_dodge._telegraphs.size() == 3, "3 telegraph markers must be registered")
	test_dodge._process(0.25)
	assert(trig["rect"] and trig["line"] and trig["circle"], "All telegraph callbacks must trigger upon timer completion")
	assert(test_dodge._telegraphs.is_empty(), "Telegraphs must be cleared after triggering")

	# Test unique Boss 1: Трёхголовый пресс (vertical hammers + floor shards)
	test_dodge.start_dodge("FELIX", &"boss_press_hammers", 18, 1.0, 3.0)
	test_dodge._spawn_pattern_wave()
	assert(test_dodge._bullets.size() > 0, "Hammer bullet must be spawned")
	assert(test_dodge._telegraphs.size() > 0, "Vertical column telegraph must be created for hammer")
	var hammer_entry: Dictionary = test_dodge._bullets[0]
	assert(hammer_entry["type"] == &"hammer" and bool(hammer_entry.get("primed", false)), "Hammer must start in primed state")
	test_dodge._process(0.45)
	assert(not bool(hammer_entry.get("primed", true)), "Hammer must unprime and fall after telegraph finishes")
	var h_node: Area2D = hammer_entry["node"] as Area2D
	if is_instance_valid(h_node):
		h_node.position.y = test_dodge._box_origin.y + test_dodge.BOX_H - 7.0
	test_dodge._process(0.05)
	var found_shard: bool = false
	for b_e: Dictionary in test_dodge._bullets:
		if b_e.get("type") == &"shard":
			found_shard = true
			break
	assert(found_shard, "Hammer ground impact must spawn shards in floor zone")

	# Test unique Boss 2: Атаманша (Crane scanning laser & rotating beams)
	test_dodge.start_dodge("FELIX", &"boss_atamansha_crane", 20, 1.0, 3.0)
	test_dodge._spawn_pattern_wave()
	assert(test_dodge._bullets.size() > 0, "Lead laser bullet must be spawned")
	assert(test_dodge._telegraphs.size() > 0, "Crane laser sight line telegraph must be created")
	var bullets_before_burst: int = test_dodge._bullets.size()
	test_dodge._process(0.45)
	assert(test_dodge._bullets.size() > bullets_before_burst, "Laser salvo must fire along telegraphed trajectory")

	test_dodge.start_dodge("FELIX", &"boss_atamansha_rotating", 16, 1.0, 3.0)
	test_dodge._spawn_pattern_wave()
	var orbit_count: int = 0
	for b_e: Dictionary in test_dodge._bullets:
		if b_e.get("type") == &"orbit":
			orbit_count += 1
	assert(orbit_count >= 3, "Atamansha rotating beams must spawn at least 3 orbiting bullets")
	var prev_angle: float = float(test_dodge._bullets[0].get("angle", 0.0))
	test_dodge._process(0.1)
	assert(float(test_dodge._bullets[0].get("angle", 0.0)) > prev_angle, "Orbiting bullets must rotate over time")

	# Test unique Boss 3: Спящий спутник (Orbital bombardment, homing radio-spheres, phase interference)
	test_dodge.start_dodge("FELIX", &"boss_satellite_orbital", 22, 1.0, 3.0)
	test_dodge._spawn_pattern_wave()
	assert(test_dodge._bullets.size() > 0 and test_dodge._telegraphs.size() > 0, "Orbital bomb and circular reticle must be created")

	test_dodge.start_dodge("FELIX", &"boss_satellite_homing", 14, 1.0, 3.0)
	test_dodge._spawn_pattern_wave()
	var found_homing: bool = false
	for b_e: Dictionary in test_dodge._bullets:
		if b_e.get("type") == &"homing":
			found_homing = true
			break
	assert(found_homing, "Satellite homing radio-sphere must be spawned")

	test_dodge.start_dodge("FELIX", &"boss_satellite_interference", 12, 1.0, 3.0)
	test_dodge._spawn_pattern_wave()
	var found_wave: bool = false
	for b_e: Dictionary in test_dodge._bullets:
		if b_e.get("type") == &"wave":
			found_wave = true
			break
	assert(found_wave, "Satellite phase interference pulse wave must be spawned")

	# Test Multi-Wave Sequencer (Array of waves + Comma separated + Simultaneous '+')
	var wave_res: Dictionary = {"switched": false}
	test_dodge.wave_started.connect(func(idx: int, count: int, pat: StringName) -> void:
		wave_res["switched"] = true
	)
	test_dodge.start_dodge("FELIX", [&"boss_press_hammers", &"acid_rain"], 15, 1.0, 2.0)
	assert(test_dodge._pattern_sequence.size() == 2 and test_dodge._current_wave_index == 0, "Multi-wave must initialize with 2 waves at index 0")
	test_dodge._process(1.1)
	assert(wave_res["switched"] and test_dodge._current_wave_index == 1 and test_dodge._pattern_id == &"acid_rain", "Sequencer must advance to wave 2 at midpoint")

	test_dodge.start_dodge("MULE", "boss_press_hammers,press_crush", 15, 1.0, 2.0)
	assert(test_dodge._pattern_sequence.size() == 2, "Comma-separated string must parse into 2 waves")

	test_dodge.start_dodge("HOUND", &"boss_press_hammers+acid_rain", 15, 1.0, 2.0)
	test_dodge._spawn_pattern_wave()
	var has_hammer: bool = false
	var has_acid: bool = false
	for b_e: Dictionary in test_dodge._bullets:
		if b_e.get("type") == &"hammer":
			has_hammer = true
		if (b_e.get("node") as Area2D).position.y < test_dodge._box_origin.y:
			has_acid = true
	assert(has_hammer and has_acid, "Simultaneous '+' combo must spawn bullets from both patterns")

	test_dodge.force_finish()
	assert(not test_dodge._active and test_dodge._bullets.is_empty(), "force_finish must clear active state and bullets")
	test_dodge.queue_free()
	await get_tree().process_frame
	print("[12] Unique Boss Bullet Patterns, Telegraph Markers & Multi-Wave Sequences (Issue #10) verified OK")

	# 13. Front Mission Weight & Power Output System (Issue #8)
	var felix_test: CatMechInstance = SaveManager.party[0]
	assert(felix_test.body_part.data.power_output == 35, "Felix Body power_output must be 35")
	assert(felix_test.body_part.data.max_weight_capacity == 35, "max_weight_capacity alias must match power_output")
	var f_tot_w: int = felix_test.get_total_weight()
	assert(f_tot_w == 10 + 12 + 11, "Felix total weight must be 33 tons (10 body + 12 arms + 11 legs)")
	assert(felix_test.get_power_capacity() == 35, "Felix power capacity must be 35 tons")
	assert(not felix_test.is_overweight(), "Default Felix assembly must not be overweight")
	assert(felix_test.get_overweight() == 0, "Default overweight must be 0")
	assert(is_equal_approx(felix_test.get_overweight_penalty_multiplier(), 1.0), "No overweight penalty multiplier for normal weight")

	# Overweight simulation: equip heavy Titan Arms (22 tons) and Titan Legs (20 tons) on Felix Body (capacity 35)
	var titan_arms_data: PartData = DataCatalog.get_part("titan_arms")
	var titan_legs_data: PartData = DataCatalog.get_part("titan_legs")
	assert(titan_arms_data != null and titan_legs_data != null, "Titan parts must be loaded in catalog")

	var old_arms: PartInstance = felix_test.set_part(PartData.PartSlot.ARMS, PartInstance.new(titan_arms_data))
	# Weight is now 10 (body) + 22 (arms) + 11 (legs) = 43 tons. Overweight by 8 tons.
	assert(felix_test.get_total_weight() == 43, "Projected weight with Titan arms must be 43 tons")
	assert(felix_test.is_overweight(), "Felix must be overweight with Titan arms")
	assert(felix_test.get_overweight() == 8, "Overweight must be 8 tons")
	# 8 * 0.3 = 2.4 penalty -> clamped to 0.15 floor
	assert(is_equal_approx(felix_test.get_overweight_penalty_multiplier(), 0.15), "Heavy overweight must clamp to 0.15 floor")
	assert(is_equal_approx(felix_test.get_dodge_speed_multiplier(), 0.15), "Dodge speed multiplier must clamp to 0.15")

	# Single unit overweight test: custom part with 1 ton overweight
	var p_1ton_over: PartData = PartData.new()
	p_1ton_over.slot = PartData.PartSlot.ARMS
	p_1ton_over.weight = 15 # 10 (body) + 15 (arms) + 11 (legs) = 36 vs 35 capacity -> 1 ton overweight!
	p_1ton_over.base_speed = 16
	felix_test.set_part(PartData.PartSlot.ARMS, PartInstance.new(p_1ton_over))
	assert(felix_test.get_total_weight() == 36, "Total weight must be 36 tons")
	assert(felix_test.get_overweight() == 1, "Overweight must be exactly 1 ton")
	assert(is_equal_approx(felix_test.get_overweight_penalty_multiplier(), 0.7), "1 ton overweight must apply 30% penalty (0.7x mult)")
	assert(is_equal_approx(felix_test.get_dodge_speed_multiplier(), 0.7), "Dodge speed multiplier must be 0.7")
	var normal_init: int = felix_test.legs_part.get_base_speed()
	assert(felix_test.get_initiative_score() == int(float(normal_init) * 0.7), "Initiative must be reduced by 30% when 1 ton overweight")

	# Both broken legs AND overweight
	felix_test.legs_part.current_hp = 0
	var broken_and_over_init: int = felix_test.get_initiative_score()
	var broken_and_over_dodge: float = felix_test.get_dodge_speed_multiplier()
	assert(broken_and_over_init == int(float(int(float(normal_init) * 0.3)) * 0.7), "Both broken legs and overweight penalties must stack")
	assert(is_equal_approx(broken_and_over_dodge, 0.6 * 0.7), "Both dodge penalties must stack multiplicatively")

	# Restore Felix
	felix_test.legs_part.repair_full()
	felix_test.set_part(PartData.PartSlot.ARMS, old_arms)
	assert(not felix_test.is_overweight(), "Felix must be normal after restoring arms")

	# Test strict_weight_limit setting
	SaveManager.settings.strict_weight_limit = true
	assert(SaveManager.settings.strict_weight_limit, "Strict weight limit setting must be enabled")
	SaveManager.settings.strict_weight_limit = false

	# Persist/export all .tres parts with power_output and weight
	for pid: Variant in DataCatalog._parts.keys():
		var pt: PartData = DataCatalog._parts[pid] as PartData
		if pt != null:
			ResourceSaver.save(pt, "res://data/resources/parts/" + String(pid) + ".tres")

	print("[13] Front Mission Weight & Power Output System (Issue #8) verified OK")

	# 14. Verify Issue #26: Game Balance, Trump Card Pyramid, Partial Carryover, Inventory HP & NG+
	SaveManager.start_new_run(123999)
	# 14.1 Start without free titan body
	assert(SaveManager.spare_parts_inventory.size() == 1, "Starter inventory must only have scrap_arms")
	var starter_part: Dictionary = SaveManager.spare_parts_inventory[0] as Dictionary
	assert(starter_part["part_id"] == "scrap_arms", "Starter part must be scrap_arms")

	# 14.2 Partial sync carryover
	SaveManager.sync_gauge = 100
	SaveManager.prepare_battle_sync()
	assert(SaveManager.sync_gauge <= 25 + int(SaveManager.shuttle_upgrades.get("harmonic_battery", 0)) * 12, "Battle sync carryover must be capped at 25% + battery bonus")

	# 14.3 Overheat & Pyramid Trump Card
	var pyr_check_arena: CombatArena = pyr_arena_packed.instantiate() as CombatArena
	pyr_check_arena.setup_battle({"node_id": 1, "node_type": "COMBAT"})
	add_child(pyr_check_arena)
	await get_tree().process_frame
	SaveManager.sync_gauge = 100
	pyr_check_arena._activate_bremen_pyramid()
	assert(pyr_check_arena._pyramid_active, "Pyramid must be active after activation")
	pyr_check_arena._selected_skill = DataCatalog.get_skill("pyramid_2_acoustic_storm")
	pyr_check_arena._on_qte_completed(1.5, "КРИТ-СИНХРО", 12)
	assert(SaveManager.sync_gauge == 0, "No sync must be gained during active Pyramid or overheat")
	assert(not pyr_check_arena._pyramid_active, "Pyramid must undock after 1 ultimate action")
	assert(pyr_check_arena._pyramid_overheat_rounds == 1, "Pyramid must trigger 1 round of overheat")
	pyr_check_arena.queue_free()
	await get_tree().process_frame

	# 14.4 Inventory HP preservation & Modifiers application
	var test_cat: CatMechInstance = SaveManager.party[0]
	test_cat.arms_part.current_hp = 15
	var damaged_hp: int = test_cat.arms_part.current_hp
	var garage_inst: GarageScene = load("res://src/garage/garage_scene.tscn").instantiate() as GarageScene
	add_child(garage_inst)
	await get_tree().process_frame
	var scrap_pdata: PartData = DataCatalog.get_part("scrap_arms")
	garage_inst._selected_cat_idx = 0
	garage_inst._equip_inventory_part(0, scrap_pdata, 40)
	var stored_entry: Dictionary = SaveManager.spare_parts_inventory[0] as Dictionary
	assert(stored_entry["current_hp"] == damaged_hp, "Unequipped part must retain its damaged HP in inventory")
	assert(test_cat.arms_part.data.part_id == &"scrap_arms", "Scrap arms must be equipped")
	garage_inst.queue_free()
	await get_tree().process_frame

	# 14.5 NG+ Cycle Scaling
	assert(SaveManager.ng_cycle == 0, "Default ng_cycle must be 0")
	SaveManager.advance_to_ng_plus_cycle()
	assert(SaveManager.ng_cycle == 1, "ng_cycle must be 1 after advancing")
	assert(SaveManager.highest_ng_cycle == 1, "highest_ng_cycle must track 1")
	assert(SaveManager.get_enemy_hp_mult() > 1.0, "Enemy HP mult must scale above 1.0 in NG+")
	assert(SaveManager.get_enemy_damage_mult() > 1.0, "Enemy damage mult must scale above 1.0 in NG+")

	# 14.6 Progressive Shuttle Upgrade Costs
	SaveManager.shuttle_upgrades["hull_reinforce"] = 0
	assert(SaveManager.get_shuttle_upgrade_cost("hull_reinforce") == 40, "Level 0 hull upgrade must cost 40")
	SaveManager.shuttle_upgrades["hull_reinforce"] = 1
	assert(SaveManager.get_shuttle_upgrade_cost("hull_reinforce") == 80, "Level 1 hull upgrade must cost 80")
	SaveManager.shuttle_upgrades["hull_reinforce"] = 2
	assert(SaveManager.get_shuttle_upgrade_cost("hull_reinforce") == 140, "Level 2 hull upgrade must cost 140")

	# 14.7 Hard Reset / Reset Progress
	SaveManager.titanium_scrap = 500
	SaveManager.ai_cores = 10
	SaveManager.hard_reset_all_progress()
	assert(SaveManager.titanium_scrap == 0 and SaveManager.ai_cores == 0, "Hard reset must clear scrap and cores")
	assert(SaveManager.ng_cycle == 0 and SaveManager.highest_ng_cycle == 0, "Hard reset must clear NG+ cycles")
	assert(SaveManager.unlocked_perks.is_empty(), "Hard reset must clear unlocked perks")
	assert(not SaveManager.has_active_run, "Hard reset must delete active run")
	print("[14] Issue #26: Game Balance, Trump Card Pyramid, Partial Carryover, Inventory HP Preservation, Hard Reset & NG+ Cycle verified OK")

	# 15. Verify Issue #28: Dynamic 4-Run Story Loop & Sequential Biome Unlock Topology
	# 15.1 Verify StoryProgressionData enum and defaults
	var sp_fresh: StoryProgressionData = StoryProgressionData.new()
	assert(int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT) == 0, "CYCLE_0_SOLO_CAT must be 0")
	assert(int(StoryProgressionData.StoryPhase.CYCLE_1_DUO) == 1, "CYCLE_1_DUO must be 1")
	assert(int(StoryProgressionData.StoryPhase.CYCLE_2_TRIO) == 2, "CYCLE_2_TRIO must be 2")
	assert(int(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET) == 3, "CYCLE_3_QUARTET must be 3")
	assert(int(StoryProgressionData.StoryPhase.COMPLETED) == 4, "COMPLETED must be 4")
	assert(sp_fresh.current_phase == StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT, "Default phase must be CYCLE_0_SOLO_CAT")
	assert(sp_fresh.unlocked_party_members == [&"FELIX"], "Default unlocked party members must be FELIX only")
	assert(sp_fresh.unlocked_fusion_tiers == [0], "Default unlocked fusion tiers must be [0]")

	# 15.2 Verify phase advancement and companion defaults
	assert(sp_fresh.advance_phase(), "Advancing from CYCLE_0 must succeed")
	assert(sp_fresh.current_phase == StoryProgressionData.StoryPhase.CYCLE_1_DUO, "Advanced phase must be CYCLE_1_DUO")
	assert(sp_fresh.unlocked_party_members.has(&"FELIX") and sp_fresh.unlocked_party_members.has(&"HOUND"), "CYCLE_1_DUO must unlock FELIX and HOUND")
	assert(sp_fresh.unlocked_fusion_tiers.has(1), "CYCLE_1_DUO must unlock Tier 1 fusion")

	assert(sp_fresh.advance_phase(), "Advancing from CYCLE_1 must succeed")
	assert(sp_fresh.current_phase == StoryProgressionData.StoryPhase.CYCLE_2_TRIO, "Advanced phase must be CYCLE_2_TRIO")
	assert(sp_fresh.unlocked_party_members.has(&"MULE"), "CYCLE_2_TRIO must unlock MULE")
	assert(sp_fresh.unlocked_fusion_tiers.has(2), "CYCLE_2_TRIO must unlock Tier 2 fusion")

	assert(sp_fresh.advance_phase(), "Advancing from CYCLE_2 must succeed")
	assert(sp_fresh.current_phase == StoryProgressionData.StoryPhase.CYCLE_3_QUARTET, "Advanced phase must be CYCLE_3_QUARTET")
	assert(sp_fresh.unlocked_party_members.has(&"COCK"), "CYCLE_3_QUARTET must unlock COCK")
	assert(sp_fresh.unlocked_fusion_tiers.has(3), "CYCLE_3_QUARTET must unlock Tier 3 fusion")

	assert(sp_fresh.advance_phase(), "Advancing from CYCLE_3 to COMPLETED must succeed")
	assert(sp_fresh.current_phase == StoryProgressionData.StoryPhase.COMPLETED, "Advanced phase must be COMPLETED")
	assert(not sp_fresh.advance_phase(), "Advancing beyond COMPLETED must return false")

	# 15.3 Verify Unit Test save/load roundtrip of StoryProgressionData
	var sp_custom: StoryProgressionData = StoryProgressionData.new()
	sp_custom.set_phase(StoryProgressionData.StoryPhase.CYCLE_2_TRIO)
	sp_custom.seen_boomer_dialog = true
	sp_custom.player_is_boomer = true
	sp_custom.concert_hall_liberated = true
	var sp_dict: Dictionary = sp_custom.to_dict()
	var sp_loaded: StoryProgressionData = StoryProgressionData.new()
	sp_loaded.from_dict(sp_dict)
	assert(sp_loaded.current_phase == StoryProgressionData.StoryPhase.CYCLE_2_TRIO, "Roundtrip phase mismatch")
	assert(sp_loaded.unlocked_party_members == [&"FELIX", &"HOUND", &"MULE"], "Roundtrip party members mismatch")
	assert(sp_loaded.unlocked_fusion_tiers == [0, 1, 2], "Roundtrip fusion tiers mismatch")
	assert(sp_loaded.seen_boomer_dialog and sp_loaded.player_is_boomer and sp_loaded.concert_hall_liberated, "Roundtrip flags mismatch")

	var test_res_path: String = "user://test_story_progression.tres"
	var res_save_err: Error = ResourceSaver.save(sp_custom, test_res_path)
	assert(res_save_err == OK, "ResourceSaver failed to save StoryProgressionData")
	var sp_disk_res: StoryProgressionData = ResourceLoader.load(test_res_path) as StoryProgressionData
	assert(sp_disk_res != null and sp_disk_res.current_phase == StoryProgressionData.StoryPhase.CYCLE_2_TRIO, "ResourceLoader failed to load StoryProgressionData")
	if FileAccess.file_exists(test_res_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_res_path))

	# 15.4 Verify SaveManager.meta_save.json stores current_phase, unlocked_party_members, unlocked_fusion_tiers
	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_2_TRIO)
	SaveManager.save_meta()
	assert(FileAccess.file_exists(SaveManager.META_SAVE_PATH), "meta_save.json must exist")
	var mfile: FileAccess = FileAccess.open(SaveManager.META_SAVE_PATH, FileAccess.READ)
	assert(mfile != null, "Failed to read meta_save.json")
	var meta_raw: Variant = JSON.parse_string(mfile.get_as_text())
	mfile.close()
	assert(meta_raw is Dictionary, "meta_save.json must be valid JSON dictionary")
	var mdict: Dictionary = meta_raw as Dictionary
	assert(mdict.has("current_phase") and int(mdict["current_phase"]) == 2, "meta_save.json must store current_phase at top-level")
	assert(mdict.has("unlocked_party_members") and (mdict["unlocked_party_members"] as Array).has("MULE"), "meta_save.json must store unlocked_party_members at top-level")
	assert(mdict.has("unlocked_fusion_tiers") and (mdict["unlocked_fusion_tiers"] as Array).map(func(v: Variant) -> int: return int(v)).has(2), "meta_save.json must store unlocked_fusion_tiers at top-level")

	SaveManager.story_progression = null
	SaveManager.load_meta()
	assert(SaveManager.story_progression != null, "load_meta() must recreate story_progression")
	assert(SaveManager.get_story_phase() == StoryProgressionData.StoryPhase.CYCLE_2_TRIO, "Loaded phase mismatch")
	assert(SaveManager.story_progression.unlocked_party_members.has(&"MULE"), "Loaded unlocked members mismatch")

	# 15.5 Verify SaveManager.start_new_run() initializes party matching current story phase
	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT)
	SaveManager.start_new_run(888111)
	assert(SaveManager.party.size() == 1 and SaveManager.party[0].cat_id == &"FELIX", "CYCLE_0 must start with Solo Felix")

	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_1_DUO)
	SaveManager.start_new_run(888222)
	assert(SaveManager.party.size() == 2 and SaveManager.has_party_member("FELIX") and SaveManager.has_party_member("HOUND"), "CYCLE_1 must start with Felix and Hound")

	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_2_TRIO)
	SaveManager.start_new_run(888333)
	assert(SaveManager.party.size() == 3 and SaveManager.has_party_member("MULE"), "CYCLE_2 must start with Trio (including MULE)")

	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET)
	SaveManager.start_new_run(888444)
	assert(SaveManager.party.size() == 4 and SaveManager.has_party_member("COCK"), "CYCLE_3 must start with full Quartet (including COCK)")

	# 15.6 Verify on party wipe, unlocked characters are not lost; subsequent runs start with all unlocked companions
	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_1_DUO)
	SaveManager.start_new_run(777111)
	assert(SaveManager.party.size() == 2, "Starting run in CYCLE_1 must have 2 cats")
	SaveManager.recruit_cat("MULE")
	assert(SaveManager.party.size() == 3, "After recruiting MULE party size must be 3")
	assert(SaveManager.story_progression.unlocked_party_members.has(&"MULE"), "MULE must be permanently unlocked")

	# Simulate party wipe
	SaveManager.delete_run_save()
	assert(not SaveManager.has_active_run, "Run save must be deleted after party wipe")
	SaveManager.load_meta()
	assert(SaveManager.story_progression.unlocked_party_members.has(&"MULE"), "MULE must persist in meta-save across wipe")

	SaveManager.start_new_run(777222)
	assert(SaveManager.party.size() == 3 and SaveManager.has_party_member("MULE"), "Subsequent run after wipe must start with unlocked companions")

	# 15.7 Verify MapGenerator.generate_sector_dag() floor count and sector theme adaptation
	# Prologue (Run 0): shortened Blue Biome (7 floors)
	var dag_c0: Array[Dictionary] = MapGenerator.generate_sector_dag(555, 1, -1, int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT))
	assert(dag_c0[dag_c0.size() - 1]["floor"] == 7, "Prologue must adapt floor count to 7")
	assert(dag_c0[dag_c0.size() - 1]["type"] == "BOSS", "Floor 7 must be BOSS node in Prologue")
	assert(dag_c0[0]["theme"] == "BLUE", "Prologue sector theme must be BLUE")
	assert(MapGenerator.get_sector_theme(1, int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT)) == "BLUE", "Sector theme for CYCLE_0 must be BLUE")
	assert(MapGenerator.get_sector_floor_count(1, int(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT)) == 7, "Sector floor count for CYCLE_0 must be 7")

	# Canonical sequence: Green (Sector 1) -> Yellow (Sector 2) -> Red (Sector 3) -> Blue (Sector 4)
	var dag_s1: Array[Dictionary] = MapGenerator.generate_sector_dag(555, 1, -1, int(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET))
	assert(dag_s1[dag_s1.size() - 1]["floor"] == 15 and dag_s1[0]["theme"] == "GREEN", "Sector 1 must be 15 floors and GREEN theme")
	assert(MapGenerator.get_sector_theme(1) == "GREEN", "Sector 1 default theme must be GREEN")

	var dag_s2: Array[Dictionary] = MapGenerator.generate_sector_dag(555, 2, -1, int(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET))
	assert(dag_s2[dag_s2.size() - 1]["floor"] == 15 and dag_s2[0]["theme"] == "YELLOW", "Sector 2 must be 15 floors and YELLOW theme")
	assert(MapGenerator.get_sector_theme(2) == "YELLOW", "Sector 2 default theme must be YELLOW")

	var dag_s3: Array[Dictionary] = MapGenerator.generate_sector_dag(555, 3, -1, int(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET))
	assert(dag_s3[dag_s3.size() - 1]["floor"] == 15 and dag_s3[0]["theme"] == "RED", "Sector 3 must be 15 floors and RED theme")
	assert(MapGenerator.get_sector_theme(3) == "RED", "Sector 3 default theme must be RED")

	var dag_s4: Array[Dictionary] = MapGenerator.generate_sector_dag(555, 4, -1, int(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET))
	assert(dag_s4[dag_s4.size() - 1]["floor"] == 15 and dag_s4[0]["theme"] == "BLUE", "Sector 4 must be 15 floors and BLUE theme")
	assert(MapGenerator.get_sector_theme(4) == "BLUE", "Sector 4 default theme must be BLUE")

	print("[15] Issue #28: Dynamic 4-Run Story Loop, Biome Themes, Save/Load Roundtrip & Wipe Persistence verified OK")

	# =========================================================================
	# [16] Issue #30: 4-Phase Final Boss with Color Vulnerability Matrix & Ensemble Finisher
	# =========================================================================
	print("\n--- [16] VERIFYING ISSUE #30: 4-PHASE FINAL BOSS & ENSEMBLE FINISHER ---")

	# 16.1 BossColoredSegment data class manages affinity color, shielding, and damage filters
	var seg_blue: BossColoredSegment = BossColoredSegment.new(
		&"segment_blue",
		"Синий резонатор",
		BossColoredSegment.AffinityColor.BLUE,
		100, # HP
		20,  # Shield
		2,   # Armor
		1,   # Required tier
		&"FELIX"
	)
	assert(seg_blue.affinity_color == BossColoredSegment.AffinityColor.BLUE, "Affinity color must be BLUE")
	assert(seg_blue.current_hp == 100 and seg_blue.shield == 20, "HP and Shield must match initial values")
	assert(seg_blue.is_vulnerable_to(&"FELIX"), "Blue segment must be vulnerable to FELIX")
	assert(not seg_blue.is_vulnerable_to(&"HOUND"), "Blue segment must not be vulnerable to HOUND solo")
	assert(not seg_blue.is_vulnerable_to(&"MULE"), "Blue segment must not be vulnerable to MULE solo")
	assert(not seg_blue.is_vulnerable_to(&"COCK"), "Blue segment must not be vulnerable to COCK solo")

	# 16.2 Attacking a segment with a non-matching hero deals 0 damage, plays dissonant clipping SFX, and displays floating notification \"0! МУЗЫКА СЛИШКОМ СЛАБАЯ!\"
	var immune_res: Dictionary = seg_blue.apply_damage(50, &"HOUND", 0)
	assert(immune_res["damage"] == 0, "Non-matching hero attack must deal strictly 0 damage")
	assert(immune_res["immune"] == true, "Non-matching attack must flag immune=true")
	assert(immune_res["floating_text"] == "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!", "Non-matching attack must display '0! МУЗЫКА СЛИШКОМ СЛАБАЯ!'")
	assert(immune_res["sfx"] == "dissonance", "Non-matching attack must trigger dissonant SFX")
	assert(seg_blue.current_hp == 100 and seg_blue.shield == 20, "Target HP and shield must be untouched on non-matching attack")

	AudioManager.play_sfx("dissonance")
	assert(AudioManager.last_sfx_played == "dissonance", "AudioManager must support dissonance SFX")
	AudioManager.play_sfx("clipping")
	assert(AudioManager.last_sfx_played == "clipping", "AudioManager must support clipping SFX")

	# Matching attack: absorbs shield, reduces armor, damages HP
	var hit_res_felix: Dictionary = seg_blue.apply_damage(30, &"FELIX", 0)
	assert(not hit_res_felix["immune"], "Matching hero attack must not be immune")
	assert(seg_blue.shield == 0, "20 shield absorbed from 30 raw damage")
	assert(hit_res_felix["absorbed_by_shield"] == 20, "Shield absorption mismatch")
	assert(hit_res_felix["damage"] == 8, "Damage after shield and armor must be 8")
	assert(seg_blue.current_hp == 92, "HP must be 92")

	# 16.3 Fusion attacks correctly deal multi-color damage corresponding to their constituent members
	var seg_red: BossColoredSegment = BossColoredSegment.new(&"segment_red", "Красный глушитель", BossColoredSegment.AffinityColor.RED, 100, 0, 0, 2, &"HOUND")
	var seg_yellow: BossColoredSegment = BossColoredSegment.new(&"segment_yellow", "Жёлтый цензор", BossColoredSegment.AffinityColor.YELLOW, 100, 0, 0, 3, &"MULE")
	var seg_green: BossColoredSegment = BossColoredSegment.new(&"segment_green", "Зелёный фильтр", BossColoredSegment.AffinityColor.GREEN, 100, 0, 0, 3, &"COCK")

	# Tier 1 (ROBO_CATDOG): Blue + Red
	assert(seg_blue.is_vulnerable_to(&"FELIX", 1) and seg_blue.is_vulnerable_to(&"HOUND", 1), "Tier 1 must damage Blue")
	assert(seg_red.is_vulnerable_to(&"FELIX", 1) and seg_red.is_vulnerable_to(&"HOUND", 1), "Tier 1 must damage Red")
	assert(not seg_yellow.is_vulnerable_to(&"FELIX", 1), "Tier 1 must NOT damage Yellow")
	assert(not seg_green.is_vulnerable_to(&"FELIX", 1), "Tier 1 must NOT damage Green")

	var t1_yellow_hit: Dictionary = seg_yellow.apply_damage(60, &"FELIX", 1)
	assert(t1_yellow_hit["damage"] == 0 and t1_yellow_hit["immune"] and t1_yellow_hit["floating_text"] == "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!", "Tier 1 on Yellow must deal 0 damage with weak music alert")

	# Tier 2 (ROBO_CATDOG_DONKEY): Blue + Red + Yellow
	assert(seg_blue.is_vulnerable_to(&"FELIX", 2), "Tier 2 must damage Blue")
	assert(seg_red.is_vulnerable_to(&"FELIX", 2), "Tier 2 must damage Red")
	assert(seg_yellow.is_vulnerable_to(&"FELIX", 2), "Tier 2 must damage Yellow")
	assert(not seg_green.is_vulnerable_to(&"FELIX", 2), "Tier 2 must NOT damage Green")

	var t2_green_hit: Dictionary = seg_green.apply_damage(60, &"FELIX", 2)
	assert(t2_green_hit["damage"] == 0 and t2_green_hit["immune"] and t2_green_hit["floating_text"] == "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!", "Tier 2 on Green must deal 0 damage with weak music alert")

	# Tier 3 (ROBO_MEGA_PYRAMID): Blue + Red + Yellow + Green (Universal spectral damage)
	assert(seg_blue.is_vulnerable_to(&"FELIX", 3), "Tier 3 must damage Blue")
	assert(seg_red.is_vulnerable_to(&"FELIX", 3), "Tier 3 must damage Red")
	assert(seg_yellow.is_vulnerable_to(&"FELIX", 3), "Tier 3 must damage Yellow")
	assert(seg_green.is_vulnerable_to(&"FELIX", 3), "Tier 3 must damage Green")

	var t3_green_hit: Dictionary = seg_green.apply_damage(45, &"FELIX", 3)
	assert(t3_green_hit["damage"] == 45 and not t3_green_hit["immune"], "Tier 3 Mega-Pyramid must successfully damage Green")

	# 16.4 Phase gates enforce fusion requirements:
	# - Phase 1 -> 2 requires Tier 1 (ROBO_CATDOG)
	# - Phase 2 -> 3 requires Tier 2 (ROBO_CATDOG_DONKEY)
	# - Phase 3 -> 4 requires Tier 3 (ROBO_MEGA_PYRAMID)
	var boss_ctrl: FinalBossController = FinalBossController.new()
	assert(boss_ctrl.current_phase == FinalBossController.Phase.PHASE_1_BLUE, "Boss must start in Phase 1 (Blue)")

	# Phase 1 -> 2 gate checks
	var p1_gate_notier: Dictionary = boss_ctrl.check_phase_gate(1, [&"FELIX", &"HOUND"], 0)
	assert(not p1_gate_notier["allowed"] and not p1_gate_notier["rejected"] and p1_gate_notier["requires_tier"] == 1, "Phase 1 -> 2 must require Tier 1 fusion")
	var p1_gate_pass: Dictionary = boss_ctrl.check_phase_gate(1, [&"FELIX", &"HOUND"], 1)
	assert(p1_gate_pass["allowed"] and p1_gate_pass["next_phase"] == 2, "Phase 1 -> 2 must pass with Tier 1")

	# Phase 2 -> 3 gate checks
	var p2_gate_notier: Dictionary = boss_ctrl.check_phase_gate(2, [&"FELIX", &"HOUND", &"MULE"], 1)
	assert(not p2_gate_notier["allowed"] and not p2_gate_notier["rejected"] and p2_gate_notier["requires_tier"] == 2, "Phase 2 -> 3 must require Tier 2 fusion")
	var p2_gate_pass: Dictionary = boss_ctrl.check_phase_gate(2, [&"FELIX", &"HOUND", &"MULE"], 2)
	assert(p2_gate_pass["allowed"] and p2_gate_pass["next_phase"] == 3, "Phase 2 -> 3 must pass with Tier 2")

	# Phase 3 -> 4 gate checks
	var p3_gate_notier: Dictionary = boss_ctrl.check_phase_gate(3, [&"FELIX", &"HOUND", &"MULE", &"COCK"], 2)
	assert(not p3_gate_notier["allowed"] and not p3_gate_notier["rejected"] and p3_gate_notier["requires_tier"] == 3, "Phase 3 -> 4 must require Tier 3 fusion")
	var p3_gate_pass: Dictionary = boss_ctrl.check_phase_gate(3, [&"FELIX", &"HOUND", &"MULE", &"COCK"], 3)
	assert(p3_gate_pass["allowed"] and p3_gate_pass["next_phase"] == 4, "Phase 3 -> 4 must pass with Tier 3")

	# 16.5 Scripted narrative rejection kicks player back to Hub if required party members are missing
	# Run 0 (Solo Cat): missing Hound on Phase 1 defeat
	var run0_boss: FinalBossController = FinalBossController.new()
	var run0_eject: Dictionary = run0_boss.check_phase_gate(1, [&"FELIX"], 0)
	assert(run0_eject["rejected"] == true, "Run 0 missing Hound must trigger scripted rejection")
	assert(run0_eject["target_story_phase"] == StoryProgressionData.StoryPhase.CYCLE_1_DUO, "Run 0 rejection must target CYCLE_1_DUO")
	assert(run0_eject["floating_text"] == "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!", "Run 0 rejection must display '0! МУЗЫКА СЛИШКОМ СЛАБАЯ!'")
	assert(run0_eject["sfx"] == "dissonance", "Run 0 rejection must trigger dissonant SFX")

	# Run 1 (Duo): missing Mule on Phase 2 defeat
	var run1_boss: FinalBossController = FinalBossController.new()
	var run1_eject: Dictionary = run1_boss.check_phase_gate(2, [&"FELIX", &"HOUND"], 1)
	assert(run1_eject["rejected"] == true, "Run 1 missing Mule must trigger scripted rejection")
	assert(run1_eject["target_story_phase"] == StoryProgressionData.StoryPhase.CYCLE_2_TRIO, "Run 1 rejection must target CYCLE_2_TRIO")

	# Run 2 (Trio): missing Cock on Phase 3 defeat
	var run2_boss: FinalBossController = FinalBossController.new()
	var run2_eject: Dictionary = run2_boss.check_phase_gate(3, [&"FELIX", &"HOUND", &"MULE"], 2)
	assert(run2_eject["rejected"] == true, "Run 2 missing Cock must trigger scripted rejection")
	assert(run2_eject["target_story_phase"] == StoryProgressionData.StoryPhase.CYCLE_3_QUARTET, "Run 2 rejection must target CYCLE_3_QUARTET")

	# 16.6 Phase 4 Finisher: Synchronized 4-note rhythmic QTE executing the full band chord to destroy the boss
	var run3_boss: FinalBossController = FinalBossController.new()
	run3_boss.current_phase = FinalBossController.Phase.PHASE_4_GREEN
	var green_seg: BossColoredSegment = run3_boss.get_current_segment()
	green_seg.shield = 0
	green_seg.armor = 0
	var pre_finisher_hit: Dictionary = run3_boss.apply_attack(258, &"FELIX", 3, true, [&"FELIX", &"HOUND", &"MULE", &"COCK"])
	assert(run3_boss.is_finisher_ready, "Boss in Phase 4 at <= 1% HP must transition to is_finisher_ready=true")
	assert(pre_finisher_hit["finisher_triggered"] == true, "Finisher trigger flag must be set")

	# 4-beat sequence: Felix -> Hound -> Mule -> Cock
	var b1: Dictionary = run3_boss.execute_finisher_beat(1, true)
	assert(b1["success"] and b1["hero"] == &"FELIX" and not b1["all_completed"], "Beat 1 must be Felix (Guitar)")

	var b2: Dictionary = run3_boss.execute_finisher_beat(2, true)
	assert(b2["success"] and b2["hero"] == &"HOUND" and not b2["all_completed"], "Beat 2 must be Hound (Drums)")

	var b3: Dictionary = run3_boss.execute_finisher_beat(3, true)
	assert(b3["success"] and b3["hero"] == &"MULE" and not b3["all_completed"], "Beat 3 must be Mule (Bass)")

	var b4: Dictionary = run3_boss.execute_finisher_beat(4, true)
	assert(b4["success"] and b4["hero"] == &"COCK" and b4["all_completed"], "Beat 4 must be Cock (Synth) and complete finisher")
	assert(run3_boss.finisher_succeeded and run3_boss.is_defeated, "Full 4-note finisher must defeat the final boss")

	var vfx_info: Dictionary = run3_boss.trigger_destruction_vfx()
	assert(vfx_info.has("screenshake_amplitude") and float(vfx_info["screenshake_amplitude"]) >= 15.0, "Finisher must trigger screenshake")
	assert(vfx_info.has("spark_colors") and (vfx_info["spark_colors"] as Array).size() == 4, "Finisher VFX must produce 4 spectral colors")
	assert(vfx_info["sfx_main"] == "part_break" and vfx_info["sfx_secondary"] == "pyramid_undock", "Finisher must trigger destruction SFX")

	# 16.7 Integration in EnemyInstance with boss_censor resource
	var censor_data: EnemyData = DataCatalog.get_enemy("boss_censor")
	assert(censor_data != null, "boss_censor resource must be registered in DataCatalog")
	assert(censor_data.is_boss and censor_data.sector_level == 4, "boss_censor must be sector 4 boss")

	var censor_enemy: EnemyInstance = EnemyInstance.new(censor_data)
	assert(censor_enemy.is_final_boss(), "EnemyInstance must identify boss_censor as final boss")
	assert(censor_enemy.final_boss_controller != null, "boss_censor must automatically initialize FinalBossController")

	# Non-matching attack on censor enemy deals 0 damage with floating text
	var en_immune_hit: Dictionary = censor_enemy.take_damage(70, PartData.PartSlot.BODY, false, &"HOUND", 0, [&"FELIX", &"HOUND"])
	assert(en_immune_hit["damage"] == 0 and en_immune_hit["immune"], "Non-matching attack on censor enemy must deal 0 damage")
	assert(en_immune_hit["floating_text"] == "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!", "Must display '0! МУЗЫКА СЛИШКОМ СЛАБАЯ!'")
	assert(en_immune_hit["sfx"] == "dissonance", "Must trigger dissonance sfx")

	# Matching attack on censor enemy deals damage
	var en_hit_felix: Dictionary = censor_enemy.take_damage(40, PartData.PartSlot.BODY, false, &"FELIX", 0, [&"FELIX", &"HOUND"])
	assert(en_hit_felix["damage"] > 0 and not en_hit_felix["immune"], "Matching attack on censor enemy must deal damage")

	print("[16] Issue #30: 4-Phase Final Boss with Color Vulnerability Matrix & Ensemble Finisher verified OK")

	print("\n--- [17] VERIFYING ISSUE #31: BIOME BOSS DEFEAT & COMPANION RESCUE PIPELINE (MULE & COCK) ---")

	# 17.1 Verify Dialogic timeline files exist on disk
	var mule_tl_path: String = "res://data/dialogues/dialogic_rescue_mule.dtl"
	var cock_tl_path: String = "res://data/dialogues/dialogic_rescue_cock.dtl"
	assert(FileAccess.file_exists(mule_tl_path), "dialogic_rescue_mule.dtl must exist")
	assert(FileAccess.file_exists(cock_tl_path), "dialogic_rescue_cock.dtl must exist")

	# Verify EventScene parses dialogic_rescue_mule and dialogic_rescue_cock
	var ev_scene_res: PackedScene = load("res://src/event/event_scene.tscn") as PackedScene
	var ev_mule: EventScene = ev_scene_res.instantiate() as EventScene
	add_child(ev_mule)
	ev_mule.setup_event({"timeline": "dialogic_rescue_mule"})
	await get_tree().process_frame
	assert(ev_mule._lines.size() >= 3, "dialogic_rescue_mule must parse dialogue lines")
	ev_mule.queue_free()
	await get_tree().process_frame

	var ev_cock: EventScene = ev_scene_res.instantiate() as EventScene
	add_child(ev_cock)
	ev_cock.setup_event({"timeline": "dialogic_rescue_cock"})
	await get_tree().process_frame
	assert(ev_cock._lines.size() >= 3, "dialogic_rescue_cock must parse dialogue lines")
	ev_cock.queue_free()
	await get_tree().process_frame

	# 17.2 Initialize party with 2 members (Felix & Hound)
	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_1_DUO)
	SaveManager.start_new_run(999111)
	assert(SaveManager.party.size() == 2, "Starting party must have size 2 before Yellow boss")
	assert(SaveManager.has_party_member("FELIX") and SaveManager.has_party_member("HOUND"), "Party must have Felix and Hound")
	assert(not SaveManager.has_party_member("MULE"), "MULE must not be in party before Yellow boss rescue")
	assert(not SaveManager.has_party_member("COCK"), "COCK must not be in party before Green boss rescue")

	# Damage a part to test 30% squad repair
	var felix_inst: CatMechInstance = SaveManager.party[0]
	var initial_body_hp: int = felix_inst.body_part.current_hp
	felix_inst.body_part.current_hp = 20
	var felix_damaged_body_hp: int = felix_inst.body_part.current_hp

	# 17.3 Yellow Biome Boss Defeat -> Rescues M.U.L.E.
	var yellow_res: Dictionary = SaveManager.handle_biome_boss_defeat("YELLOW", "boss_press")
	assert(yellow_res["rescued"] == true, "Yellow boss defeat must rescue companion")
	assert(yellow_res["companion_id"] == "MULE", "Yellow boss defeat must rescue MULE")
	assert(yellow_res["timeline_id"] == "dialogic_rescue_mule", "Timeline must be dialogic_rescue_mule")
	assert(yellow_res["timeline"] == mule_tl_path, "Timeline path mismatch")

	# Acceptance criteria check:
	# - Unlocks MULE in SaveManager
	assert(SaveManager.is_party_member_unlocked(&"MULE"), "MULE must be unlocked in SaveManager")
	# - Rescued character is immediately instantiated via DataCatalog.create_cat_instance() and appended to active party
	assert(SaveManager.has_party_member("MULE"), "MULE must be in active party")
	# - Unit test verifies party size increments to 3 after Yellow boss
	assert(SaveManager.party.size() == 3, "Party size must increment to 3 after Yellow boss defeat")
	# - Repair 30% HP across the squad
	var expected_heal: int = int(float(felix_inst.body_part.get_max_hp()) * 0.3)
	assert(felix_inst.body_part.current_hp >= felix_damaged_body_hp + expected_heal - 1, "Squad must receive 30% HP repair upon Yellow boss defeat")
	# - Story phase advanced in SaveManager
	assert(int(SaveManager.get_story_phase()) >= int(StoryProgressionData.StoryPhase.CYCLE_2_TRIO), "Story phase must advance in SaveManager")
	# - Fusion tier ROBO_CATDOG_DONKEY unlocked
	assert(SaveManager.is_fusion_tier_unlocked(2), "ROBO_CATDOG_DONKEY (Tier 2) must be unlocked")

	# 17.4 Next run retains MULE and ROBO_CATDOG_DONKEY
	SaveManager.start_new_run(999222)
	assert(SaveManager.party.size() >= 3 and SaveManager.has_party_member("MULE"), "Next run must retain rescued MULE")
	assert(SaveManager.is_fusion_tier_unlocked(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY), "Next run must retain ROBO_CATDOG_DONKEY unlock")

	# Prepare for Green Biome Boss defeat: party has 3 members (Felix, Hound, Mule)
	if SaveManager.has_party_member("COCK"):
		var filtered_cats: Array[CatMechInstance] = []
		for c: CatMechInstance in SaveManager.party:
			if String(c.cat_id) != "COCK":
				filtered_cats.append(c)
		SaveManager.party = filtered_cats
	assert(SaveManager.party.size() == 3, "Party size must be 3 before Green boss")
	assert(not SaveManager.has_party_member("COCK"), "COCK must not be in party before Green boss rescue")

	# Damage party to test squad repair on Green boss defeat
	SaveManager.party[1].arms_part.current_hp = 15
	var hound_arms_damaged: int = SaveManager.party[1].arms_part.current_hp
	var hound_arms_heal: int = int(float(SaveManager.party[1].arms_part.get_max_hp()) * 0.3)

	# 17.5 Green Biome Boss Defeat -> Rescues C.O.C.K.
	var green_res: Dictionary = SaveManager.handle_biome_boss_defeat("GREEN", "boss_atamansha")
	assert(green_res["rescued"] == true, "Green boss defeat must rescue companion")
	assert(green_res["companion_id"] == "COCK", "Green boss defeat must rescue COCK")
	assert(green_res["timeline_id"] == "dialogic_rescue_cock", "Timeline must be dialogic_rescue_cock")
	assert(green_res["timeline"] == cock_tl_path, "Timeline path mismatch")

	# Acceptance criteria check:
	# - Unlocks COCK in SaveManager
	assert(SaveManager.is_party_member_unlocked(&"COCK"), "COCK must be unlocked in SaveManager")
	# - Rescued character is immediately instantiated via DataCatalog.create_cat_instance() and appended to active party
	assert(SaveManager.has_party_member("COCK"), "COCK must be in active party")
	# - Unit test verifies party size increments to 4 after Green boss
	assert(SaveManager.party.size() == 4, "Party size must increment to 4 after Green boss defeat")
	# - Repair 30% HP across the squad
	assert(SaveManager.party[1].arms_part.current_hp >= hound_arms_damaged + hound_arms_heal - 1, "Squad must receive 30% HP repair upon Green boss defeat")
	# - Advance story phase in SaveManager
	assert(int(SaveManager.get_story_phase()) >= int(StoryProgressionData.StoryPhase.CYCLE_3_QUARTET), "Story phase must advance in SaveManager")
	# - Fusion tier ROBO_MEGA_PYRAMID unlocked
	assert(SaveManager.is_fusion_tier_unlocked(3), "ROBO_MEGA_PYRAMID (Tier 3) must be unlocked")

	# 17.6 Next run retains COCK and ROBO_MEGA_PYRAMID
	SaveManager.start_new_run(999333)
	assert(SaveManager.party.size() == 4 and SaveManager.has_party_member("COCK"), "Next run must retain full quartet including COCK")
	assert(SaveManager.is_fusion_tier_unlocked(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID), "Next run must retain ROBO_MEGA_PYRAMID unlock")

	# 17.7 Verify CombatArena UI integration upon boss victory
	var arena_packed: PackedScene = load("res://src/combat/combat_arena.tscn") as PackedScene
	var arena_inst: CombatArena = arena_packed.instantiate() as CombatArena
	arena_inst.setup_battle({"node_type": "BOSS", "biome_theme": "YELLOW", "boss_id": "boss_press"})
	add_child(arena_inst)
	await get_tree().process_frame
	arena_inst._handle_victory()
	assert(arena_inst._end_title.text.find("M.U.L.E.") != -1, "Victory title must mention M.U.L.E. rescue")
	assert(arena_inst._end_btn.text.find("M.U.L.E.") != -1, "Victory button text must mention M.U.L.E. rescue")
	arena_inst.queue_free()
	await get_tree().process_frame

	print("[17] Issue #31: Biome boss defeat triggers and companion rescue pipeline (MULE & COCK) verified OK")

	# -----------------------------------------------------------------------------------------------------------------
	# [18] VERIFY ISSUE #29: TIERED ROBO-FUSIONS WITH SELECTABLE COST TIERS IN ALL ENCOUNTERS (ADR-002)
	# -----------------------------------------------------------------------------------------------------------------
	print("\n--- [18] VERIFYING ISSUE #29: TIERED ROBO-FUSIONS WITH SELECTABLE COST TIERS IN ALL ENCOUNTERS ---")

	# 18.1 CombatFusionController structure and FusionTier enum
	var fusion_ctrl: CombatFusionController = CombatFusionController.new()
	assert(CombatFusionController.FusionTier.NONE == 0, "FusionTier.NONE must be 0")
	assert(CombatFusionController.FusionTier.ROBO_CATDOG == 1, "FusionTier.ROBO_CATDOG must be 1")
	assert(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY == 2, "FusionTier.ROBO_CATDOG_DONKEY must be 2")
	assert(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID == 3, "FusionTier.ROBO_MEGA_PYRAMID must be 3")

	# Sync costs: 50% / 75% / 100%
	assert(fusion_ctrl.get_tier_sync_cost(CombatFusionController.FusionTier.ROBO_CATDOG) == 50, "Tier 1 cost must be 50% Sync")
	assert(fusion_ctrl.get_tier_sync_cost(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY) == 75, "Tier 2 cost must be 75% Sync")
	assert(fusion_ctrl.get_tier_sync_cost(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID) == 100, "Tier 3 cost must be 100% Sync")

	# Durations: 2 turns for T1/T2, 3 turns for T3
	assert(fusion_ctrl.get_tier_duration(CombatFusionController.FusionTier.ROBO_CATDOG) == 2, "Tier 1 must last 2 turns")
	assert(fusion_ctrl.get_tier_duration(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY) == 2, "Tier 2 must last 2 turns")
	assert(fusion_ctrl.get_tier_duration(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID) == 3, "Tier 3 must last 3 turns")

	# Constituent members
	var t1_members: Array[StringName] = CombatFusionController.get_constituent_members(CombatFusionController.FusionTier.ROBO_CATDOG)
	var t2_members: Array[StringName] = CombatFusionController.get_constituent_members(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY)
	var t3_members: Array[StringName] = CombatFusionController.get_constituent_members(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID)
	assert(t1_members == [&"FELIX", &"HOUND"], "Tier 1 must consist of Felix + Hound")
	assert(t2_members == [&"FELIX", &"HOUND", &"MULE"], "Tier 2 must consist of Felix + Hound + Mule")
	assert(t3_members == [&"FELIX", &"HOUND", &"MULE", &"COCK"], "Tier 3 must consist of Full Quartet")

	# 18.2 Available tiers are filtered by currently alive and unlocked party members
	SaveManager.start_new_run(777111)
	SaveManager.story_progression.unlocked_fusion_tiers = [0, 1, 2, 3]

	# All 4 alive -> all 3 tiers available
	var all_4_alive: Array[StringName] = [&"FELIX", &"HOUND", &"MULE", &"COCK"]
	var avail_all: Array[CombatFusionController.FusionTier] = fusion_ctrl.get_available_tiers(all_4_alive)
	assert(avail_all.size() == 3, "All 3 tiers must be available when all 4 cats are alive")
	assert(avail_all.has(CombatFusionController.FusionTier.ROBO_CATDOG), "T1 must be available")
	assert(avail_all.has(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY), "T2 must be available")
	assert(avail_all.has(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID), "T3 must be available")

	# Mule dead -> only T1 available (T2 and T3 require Mule)
	var mule_dead: Array[StringName] = [&"FELIX", &"HOUND", &"COCK"]
	var avail_no_mule: Array[CombatFusionController.FusionTier] = fusion_ctrl.get_available_tiers(mule_dead)
	assert(avail_no_mule.size() == 1 and avail_no_mule[0] == CombatFusionController.FusionTier.ROBO_CATDOG, "Only T1 must be available if Mule is dead")

	# Hound dead -> no tiers available (all fusions require Hound)
	var hound_dead: Array[StringName] = [&"FELIX", &"MULE", &"COCK"]
	assert(fusion_ctrl.get_available_tiers(hound_dead).is_empty(), "No tiers must be available if Hound is dead")

	# Lock T2 and T3 in progression -> only T1 available even if all 4 are alive
	SaveManager.story_progression.unlocked_fusion_tiers = [0, 1]
	var avail_prog_t1: Array[CombatFusionController.FusionTier] = fusion_ctrl.get_available_tiers(all_4_alive)
	assert(avail_prog_t1.size() == 1 and avail_prog_t1[0] == CombatFusionController.FusionTier.ROBO_CATDOG, "Only unlocked tiers in progression must be available")
	SaveManager.story_progression.unlocked_fusion_tiers = [0, 1, 2, 3]

	# 18.3 Dynamic combat UI buttons with tooltips and activation thresholds (50% / 75% / 100%)
	var ui_arena: CombatArena = arena_packed.instantiate() as CombatArena
	ui_arena.setup_battle({"node_type": "COMBAT"})
	add_child(ui_arena)
	await get_tree().process_frame

	# At 40% Sync: all buttons exist but disabled (locked)
	SaveManager.sync_gauge = 40
	ui_arena._begin_player_turn(0)
	var btn_t1: Button = ui_arena._action_box.get_node_or_null("FusionButton_Tier1") as Button
	var btn_t2: Button = ui_arena._action_box.get_node_or_null("FusionButton_Tier2") as Button
	var btn_t3: Button = ui_arena._action_box.get_node_or_null("FusionButton_Tier3") as Button
	assert(btn_t1 != null and btn_t2 != null and btn_t3 != null, "All 3 fusion buttons must exist in action box")
	assert(btn_t1.disabled and btn_t2.disabled and btn_t3.disabled, "All fusion buttons must be disabled below 50% Sync")
	assert(btn_t1.tooltip_text.contains("50%"), "T1 button tooltip must specify 50% threshold")
	assert(btn_t2.tooltip_text.contains("75%"), "T2 button tooltip must specify 75% threshold")
	assert(btn_t3.tooltip_text.contains("100%"), "T3 button tooltip must specify 100% threshold")

	# At 50% Sync: T1 enabled, T2 and T3 disabled
	SaveManager.sync_gauge = 50
	ui_arena._begin_player_turn(0)
	await get_tree().process_frame
	btn_t1 = ui_arena._action_box.get_node_or_null("FusionButton_Tier1") as Button
	btn_t2 = ui_arena._action_box.get_node_or_null("FusionButton_Tier2") as Button
	btn_t3 = ui_arena._action_box.get_node_or_null("FusionButton_Tier3") as Button
	assert(not btn_t1.disabled, "T1 button must be enabled at 50% Sync")
	assert(btn_t2.disabled and btn_t3.disabled, "T2 and T3 buttons must remain disabled at 50% Sync")

	# At 75% Sync: T1 and T2 enabled, T3 disabled
	SaveManager.sync_gauge = 75
	ui_arena._begin_player_turn(0)
	await get_tree().process_frame
	btn_t1 = ui_arena._action_box.get_node_or_null("FusionButton_Tier1") as Button
	btn_t2 = ui_arena._action_box.get_node_or_null("FusionButton_Tier2") as Button
	btn_t3 = ui_arena._action_box.get_node_or_null("FusionButton_Tier3") as Button
	assert(not btn_t1.disabled and not btn_t2.disabled, "T1 and T2 buttons must be enabled at 75% Sync")
	assert(btn_t3.disabled, "T3 button must remain disabled at 75% Sync")

	# At 100% Sync: all 3 buttons enabled
	SaveManager.sync_gauge = 100
	ui_arena._begin_player_turn(0)
	await get_tree().process_frame
	btn_t1 = ui_arena._action_box.get_node_or_null("FusionButton_Tier1") as Button
	btn_t2 = ui_arena._action_box.get_node_or_null("FusionButton_Tier2") as Button
	btn_t3 = ui_arena._action_box.get_node_or_null("FusionButton_Tier3") as Button
	assert(not btn_t1.disabled and not btn_t2.disabled and not btn_t3.disabled, "All 3 fusion buttons must be enabled at 100% Sync")
	ui_arena.queue_free()
	await get_tree().process_frame

	# 18.4 Fusions can be activated in regular, elite, and boss combats
	for node_t: String in ["COMBAT", "ELITE", "BOSS"]:
		var test_arena: CombatArena = arena_packed.instantiate() as CombatArena
		test_arena.setup_battle({"node_type": node_t})
		add_child(test_arena)
		await get_tree().process_frame
		SaveManager.sync_gauge = 50
		test_arena._begin_player_turn(0)
		var fbtn: Button = test_arena._action_box.get_node_or_null("FusionButton_Tier1") as Button
		assert(fbtn != null and not fbtn.disabled, "Fusion must be activatable in " + node_t + " encounters")
		test_arena.queue_free()
		await get_tree().process_frame

	# 18.5 Stats and HP pool correctly computed as the sum of participating mechs; debuffs cleansed on merge
	var merge_arena: CombatArena = arena_packed.instantiate() as CombatArena
	merge_arena.setup_battle({"node_type": "COMBAT"})
	add_child(merge_arena)
	await get_tree().process_frame

	# Set debuffs on party
	SaveManager.party[0].bleed_stacks = 2 # Felix
	SaveManager.party[1].stunned = true   # Hound
	SaveManager.party[2].bleed_stacks = 3 # Mule (non-participant in T1)
	SaveManager.party[3].stunned = true   # Cock (non-participant in T1)

	var felix_hp: int = SaveManager.party[0].get_total_current_hp()
	var hound_hp: int = SaveManager.party[1].get_total_current_hp()
	var mule_hp: int = SaveManager.party[2].get_total_current_hp()
	var cock_hp: int = SaveManager.party[3].get_total_current_hp()
	var expected_t1_hp: int = felix_hp + hound_hp

	SaveManager.sync_gauge = 100
	merge_arena._activate_fusion_tier(CombatFusionController.FusionTier.ROBO_CATDOG)

	# Verify Sync deducted by exactly 50 (leaves 50)
	assert(SaveManager.sync_gauge == 50, "Activating Tier 1 (50% Sync) from 100% must leave 50% Sync")
	assert(merge_arena._pyramid_active, "Fusion must be active")
	assert(merge_arena._fusion_controller.current_tier == CombatFusionController.FusionTier.ROBO_CATDOG, "Active tier must be ROBO_CATDOG")
	assert(merge_arena._pyramid_turns_left == 2, "T1 duration must be 2 turns")
	assert(merge_arena._pyramid_current_hp == expected_t1_hp, "T1 HP pool must strictly equal sum of Felix + Hound HP")

	# Verify debuffs cleansed on participating mechs, preserved on non-participating
	assert(SaveManager.party[0].bleed_stacks == 0, "Felix bleed debuff must be cleansed on merge")
	assert(not SaveManager.party[1].stunned, "Hound stun debuff must be cleansed on merge")
	assert(SaveManager.party[2].bleed_stacks == 3, "Non-participating Mule debuff must NOT be cleansed")
	assert(SaveManager.party[3].stunned == true, "Non-participating Cock debuff must NOT be cleansed")

	# 18.6 Upon fusion expiration (2 turns for T1/T2, 3 turns for T3), total damage received is distributed proportionally across participating body parts
	merge_arena.apply_pyramid_damage(30, true)
	assert(merge_arena._pyramid_damage_taken == 30, "Fusion must track 30 damage taken")
	assert(merge_arena._pyramid_current_hp == expected_t1_hp - 30, "Fusion HP must deduct 30 damage")

	# Advance round 1 -> 1 turn left
	merge_arena._start_new_round()
	assert(merge_arena._pyramid_active and merge_arena._pyramid_turns_left == 1, "Fusion must remain active after 1 round with 1 turn left")

	# Advance round 2 -> expiration
	merge_arena._start_new_round()
	assert(not merge_arena._pyramid_active, "Fusion must expire after 2 turns")
	assert(not merge_arena._fusion_controller.is_active(), "Fusion controller must be inactive after expiration")

	# Damage distributed only across Felix and Hound; Mule and Cock took 0 damage
	assert(SaveManager.party[2].get_total_current_hp() == mule_hp, "Non-participating Mule must take 0 damage from fusion")
	assert(SaveManager.party[3].get_total_current_hp() == cock_hp, "Non-participating Cock must take 0 damage from fusion")
	var t1_participants_hp: int = SaveManager.party[0].get_total_current_hp() + SaveManager.party[1].get_total_current_hp()
	assert(t1_participants_hp == expected_t1_hp - 30, "Participating mechs (Felix + Hound) must absorb exactly 30 total distributed damage")
	merge_arena.queue_free()
	await get_tree().process_frame

	# 18.7 Tier 2 (ROBO_CATDOG_DONKEY): Heavy armor (+60%), 2 turns duration, 3 mechs damage distribution
	var t2_arena: CombatArena = arena_packed.instantiate() as CombatArena
	t2_arena.setup_battle({"node_type": "COMBAT"})
	add_child(t2_arena)
	await get_tree().process_frame
	SaveManager.sync_gauge = 100
	t2_arena._activate_fusion_tier(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY)
	assert(SaveManager.sync_gauge == 25, "Activating Tier 2 (75% Sync) from 100% must leave 25% Sync")
	assert(t2_arena._pyramid_turns_left == 2, "Tier 2 duration must be 2 turns")

	# Test heavy armor (+60% damage reduction = takes 40% damage)
	var t2_hit_res: Dictionary = t2_arena.apply_pyramid_damage(50, false)
	assert(int(t2_hit_res["damage"]) == 20, "Tier 2 heavy armor (+60%) must reduce 50 raw damage to 20")

	# Expire after 2 turns
	t2_arena._start_new_round()
	t2_arena._start_new_round()
	assert(not t2_arena._pyramid_active, "Tier 2 must expire after 2 turns")
	t2_arena.queue_free()
	await get_tree().process_frame

	# 18.8 Tier 3 (ROBO_MEGA_PYRAMID): 3 turns duration, status immunity, full quartet
	var t3_arena: CombatArena = arena_packed.instantiate() as CombatArena
	t3_arena.setup_battle({"node_type": "BOSS"})
	add_child(t3_arena)
	await get_tree().process_frame
	SaveManager.sync_gauge = 100
	t3_arena._activate_fusion_tier(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID)
	assert(SaveManager.sync_gauge == 0, "Activating Tier 3 (100% Sync) must leave 0% Sync")
	assert(t3_arena._pyramid_turns_left == 3, "Tier 3 duration must be 3 turns")

	# Advance 2 rounds -> still active (3 turns duration)
	t3_arena._start_new_round()
	assert(t3_arena._pyramid_active and t3_arena._pyramid_turns_left == 2, "Tier 3 must have 2 turns remaining after round 1")
	t3_arena._start_new_round()
	assert(t3_arena._pyramid_active and t3_arena._pyramid_turns_left == 1, "Tier 3 must have 1 turn remaining after round 2")
	t3_arena._start_new_round()
	assert(not t3_arena._pyramid_active, "Tier 3 must expire after 3 turns")
	t3_arena.queue_free()
	await get_tree().process_frame

	# 18.9 Audio theme switches dynamically via AudioManager.play_pyramid_theme(tier)
	AudioManager.play_pyramid_theme(CombatFusionController.FusionTier.ROBO_CATDOG)
	assert(AudioManager.current_theme_id == &"PYRAMID_2" and AudioManager.active_instruments.size() == 3, "Tier 1 theme must be PYRAMID_2 with 3 instruments")

	AudioManager.play_pyramid_theme(CombatFusionController.FusionTier.ROBO_CATDOG_DONKEY)
	assert(AudioManager.current_theme_id == &"PYRAMID_3" and AudioManager.active_instruments.size() == 4, "Tier 2 theme must be PYRAMID_3 with 4 instruments")

	AudioManager.play_pyramid_theme(CombatFusionController.FusionTier.ROBO_MEGA_PYRAMID)
	assert(AudioManager.current_theme_id == &"PYRAMID_4" and AudioManager.active_instruments.size() == 5, "Tier 3 theme must be PYRAMID_4 with 5 instruments")

	print("[18] Issue #29: Tiered robo-fusions with selectable cost tiers in all encounters verified OK")
	# --- [19] VERIFYING ISSUE #32: DIALOGIC 2 TIMELINES WITH 4TH-WALL BREAK CHOICE, PISIKOT GAG & MID-BATTLE COMBAT PAUSE ---
	print("\n--- [19] VERIFYING ISSUE #32: DIALOGIC 2 TIMELINES WITH 4TH-WALL BREAK CHOICE, PISIKOT GAG & MID-BATTLE COMBAT PAUSE ---")

	# 19.1 Verify timeline files exist on disk
	var first_fusion_tl_path: String = "res://data/dialogues/timeline_first_fusion.dtl"
	var rescue_mule_tl_path: String = "res://data/dialogues/timeline_rescue_mule.dtl"
	var rescue_cock_tl_path: String = "res://data/dialogues/timeline_rescue_cock.dtl"
	assert(FileAccess.file_exists(first_fusion_tl_path), "timeline_first_fusion.dtl must exist")
	assert(FileAccess.file_exists(rescue_mule_tl_path), "timeline_rescue_mule.dtl must exist")
	assert(FileAccess.file_exists(rescue_cock_tl_path), "timeline_rescue_cock.dtl must exist")

	# Verify contents of timeline_first_fusion.dtl
	var f_fusion_file: FileAccess = FileAccess.open(first_fusion_tl_path, FileAccess.READ)
	var f_fusion_txt: String = f_fusion_file.get_as_text()
	f_fusion_file.close()
	assert(f_fusion_txt.find("Robo-CatDog") != -1 or f_fusion_txt.find("Робокотопёс") != -1, "Must mention Robo-CatDog")
	assert(f_fusion_txt.find("писикот") != -1, "Must contain pisikot gag")
	assert(f_fusion_txt.find("Уральских пельменей") != -1, "Must reference Ural Pelmeni KVN sketch")
	assert(f_fusion_txt.find("эщкере") != -1 or f_fusion_txt.find("eshkere") != -1, "Must reference eshkere")
	assert(f_fusion_txt.find("40-") != -1 or f_fusion_txt.find("40-летние") != -1 or f_fusion_txt.find("boomers") != -1, "Must contain 4th wall break about 40yo boomers")
	assert(f_fusion_txt.find("player") != -1 or f_fusion_txt.find("игрок") != -1, "Hound must address player")
	assert(f_fusion_txt.find("Yes, that's true") != -1 or f_fusion_txt.find("Да, это правда") != -1, "Must have Yes choice")
	assert(f_fusion_txt.find("No, I'm younger") != -1 or f_fusion_txt.find("Нет, я моложе") != -1, "Must have No choice")
	assert(f_fusion_txt.find("пали контору") != -1 or f_fusion_txt.find("blow their cover") != -1, "Felix must tell Hound not to blow cover")
	assert(f_fusion_txt.find("замоггаю") != -1 or f_fusion_txt.find("mog") != -1, "Felix must threaten to mog Hound")

	# Verify contents of timeline_rescue_mule.dtl
	var f_mule_file: FileAccess = FileAccess.open(rescue_mule_tl_path, FileAccess.READ)
	var f_mule_txt: String = f_mule_file.get_as_text()
	f_mule_file.close()
	assert(f_mule_txt.find("писикотоосла") != -1 or f_mule_txt.find("pisikotodonkey") != -1, "Must mention pisikotodonkey")
	assert(f_mule_txt.find("закатывает глаза") != -1 or f_mule_txt.find("rolls eyes") != -1, "Felix must roll eyes")
	assert(f_mule_txt.find("part_break") != -1, "Must have part_break audio SFX")
	assert(f_mule_txt.find("heal") != -1, "Must have heal audio SFX")
	assert(f_mule_txt.find("(normal)") != -1 and f_mule_txt.find("(battle)") != -1, "Must have portrait expressions")

	# Verify contents of timeline_rescue_cock.dtl
	var f_cock_file: FileAccess = FileAccess.open(rescue_cock_tl_path, FileAccess.READ)
	var f_cock_txt: String = f_cock_file.get_as_text()
	f_cock_file.close()
	assert(f_cock_txt.find("писикота") != -1, "Must mention pisikot")
	assert(f_cock_txt.find("C.O.C.K.") != -1, "Must mention C.O.C.K. callsign")
	assert(f_cock_txt.find("part_break") != -1, "Must have part_break audio SFX")
	assert(f_cock_txt.find("qte_perfect") != -1, "Must have qte_perfect audio SFX")

	# 19.2 Verify EventScene parsing and choice branching for timeline_first_fusion
	var ev_fusion: EventScene = ev_scene_res.instantiate() as EventScene
	ev_fusion.setup_event({"timeline": first_fusion_tl_path})
	add_child(ev_fusion)
	await get_tree().process_frame
	assert(ev_fusion._lines.size() >= 3, "timeline_first_fusion must parse introductory lines")
	assert(ev_fusion._choices.size() == 2, "timeline_first_fusion must parse 2 branching choice nodes")

	# Test choice 0 in EventScene: Yes -> player_is_boomer = true
	SaveManager.story_progression.player_is_boomer = false
	SaveManager.story_progression.seen_boomer_dialog = false
	ev_fusion._on_choice_selected(ev_fusion._choices[0])
	assert(SaveManager.story_progression.player_is_boomer == true, "Selecting Yes must set player_is_boomer to true")
	assert(SaveManager.story_progression.seen_boomer_dialog == true, "Selecting choice must set seen_boomer_dialog to true")
	assert(ev_fusion._lines.size() >= 1, "Branch lines must be loaded into _lines")
	assert(ev_fusion._lines[0]["text"].find("пали контору") != -1, "Felix blow cover response must be displayed")
	ev_fusion.queue_free()
	await get_tree().process_frame

	# Test choice 1 in EventScene: No -> player_is_boomer = false
	var ev_fusion2: EventScene = ev_scene_res.instantiate() as EventScene
	ev_fusion2.setup_event({"timeline": first_fusion_tl_path})
	add_child(ev_fusion2)
	await get_tree().process_frame
	ev_fusion2._on_choice_selected(ev_fusion2._choices[1])
	assert(SaveManager.story_progression.player_is_boomer == false, "Selecting No must set player_is_boomer to false")
	assert(ev_fusion2._lines[0]["text"].find("замоггаю") != -1, "Felix mogging response must be displayed")
	ev_fusion2.queue_free()
	await get_tree().process_frame

	# 19.3 Verify SaveManager persistence round-trip for player_is_boomer
	SaveManager.set_player_is_boomer(true)
	assert(SaveManager.is_player_boomer() == true, "SaveManager.is_player_boomer() helper must return true")
	SaveManager.save_meta()
	SaveManager.set_player_is_boomer(false)
	assert(SaveManager.is_player_boomer() == false, "Must be false after set")
	SaveManager.load_meta()
	assert(SaveManager.is_player_boomer() == true, "load_meta() must restore player_is_boomer")

	# 19.4 Verify Mid-Battle Dialogue Trigger, Seamless Combat Pause and Resume
	var combat_arena_packed: PackedScene = load("res://src/combat/combat_arena.tscn") as PackedScene
	var combat_arena: CombatArena = combat_arena_packed.instantiate() as CombatArena
	combat_arena.setup_battle({"node_type": "COMBAT"})
	add_child(combat_arena)
	await get_tree().process_frame

	# Ensure combat starts unpaused
	assert(get_tree().paused == false, "Combat tree must be unpaused initially")
	assert(not combat_arena.is_mid_battle_dialogue_active(), "Mid-battle dialogue must be inactive initially")

	# Trigger mid-battle dialogue
	var dlg_overlay: MidBattleDialogueOverlay = combat_arena.trigger_mid_battle_dialogue("res://data/dialogues/timeline_first_fusion.dtl")
	assert(dlg_overlay != null, "Dialogue overlay must be created")
	assert(combat_arena.is_mid_battle_dialogue_active() == true, "is_mid_battle_dialogue_active must be true")

	# Acceptance Criteria: Combat seamlessly pauses during mid-battle dialogue trigger
	assert(get_tree().paused == true, "Combat must seamlessly pause when mid-battle dialogue is triggered")

	# Verify overlay parsed timeline and SFX
	assert(dlg_overlay._lines.size() >= 4, "Overlay must parse dialogue lines")
	assert(dlg_overlay._choices.size() == 2, "Overlay must parse 2 choices")
	assert(AudioManager.last_sfx_played == "pyramid_siren", "First fusion timeline must play pyramid_siren SFX")

	# Advance lines to reach choices
	while not dlg_overlay.is_showing_choices() and dlg_overlay._line_cursor < dlg_overlay._lines.size() - 1:
		dlg_overlay._line_cursor += 1
		dlg_overlay._render_dialogue_state()

	assert(dlg_overlay.is_showing_choices(), "Overlay must present player choices")
	var choices: Array[Dictionary] = dlg_overlay.get_choices()
	assert(choices.size() == 2, "Must have exactly 2 choices")

	# Select choice 0: Yes -> sets player_is_boomer = true
	dlg_overlay.select_choice(0)
	assert(SaveManager.story_progression.player_is_boomer == true, "Overlay select_choice(0) must set player_is_boomer = true")
	assert(dlg_overlay.get_current_line()["text"].find("пали контору") != -1, "Felix response displayed in overlay")

	# Advance past Felix response to close dialogue
	dlg_overlay.close_dialogue()
	await get_tree().process_frame

	# Acceptance Criteria: Combat seamlessly resumes upon dialogue completion
	assert(not combat_arena.is_mid_battle_dialogue_active(), "Dialogue overlay must be cleared")
	assert(get_tree().paused == false, "Combat must seamlessly resume (unpause) upon dialogue completion")

	# 19.5 Verify automatic trigger on first fusion in CombatArena
	SaveManager.story_progression.seen_boomer_dialog = false
	SaveManager.sync_gauge = 100
	combat_arena._force_headless_mid_battle_dialogue = true
	combat_arena._activate_fusion_tier(CombatFusionController.FusionTier.ROBO_CATDOG)

	assert(combat_arena.is_mid_battle_dialogue_active() == true, "First fusion must automatically trigger mid-battle dialogue")
	assert(get_tree().paused == true, "Combat must pause on first fusion dialogue trigger")

	# Select choice 1: No -> sets player_is_boomer = false
	var auto_dlg: MidBattleDialogueOverlay = combat_arena.get_mid_battle_dialogue()
	assert(auto_dlg != null, "Overlay ref must be valid")
	auto_dlg.select_choice(1)
	assert(SaveManager.story_progression.player_is_boomer == false, "Selecting choice 1 must set player_is_boomer = false")
	assert(auto_dlg.get_current_line()["text"].find("замоггаю") != -1, "Felix mogging response displayed in auto overlay")

	auto_dlg.close_dialogue()
	await get_tree().process_frame
	assert(get_tree().paused == false, "Combat must resume after auto-dialogue completion")
	assert(SaveManager.story_progression.seen_boomer_dialog == true, "seen_boomer_dialog must be set to true")

	# Subsequent fusion must NOT re-trigger dialogue
	SaveManager.sync_gauge = 100
	combat_arena._activate_fusion_tier(CombatFusionController.FusionTier.ROBO_CATDOG)
	assert(not combat_arena.is_mid_battle_dialogue_active(), "Subsequent fusion must NOT trigger dialogue after already seen")

	combat_arena.queue_free()
	await get_tree().process_frame

	# 19.6 Verify EventScene parses timeline_rescue_mule.dtl and timeline_rescue_cock.dtl with audio SFX
	var ev_mule_32: EventScene = ev_scene_res.instantiate() as EventScene
	ev_mule_32.setup_event({"timeline": rescue_mule_tl_path})
	add_child(ev_mule_32)
	await get_tree().process_frame
	assert(ev_mule_32._lines.size() >= 4, "timeline_rescue_mule must parse at least 4 dialogue lines")
	assert(AudioManager.last_sfx_played == "heal" or AudioManager.last_sfx_played == "part_break", "timeline_rescue_mule must trigger audio SFX")
	ev_mule_32.queue_free()
	await get_tree().process_frame

	var ev_cock_32: EventScene = ev_scene_res.instantiate() as EventScene
	ev_cock_32.setup_event({"timeline": rescue_cock_tl_path})
	add_child(ev_cock_32)
	await get_tree().process_frame
	assert(ev_cock_32._lines.size() >= 4, "timeline_rescue_cock must parse at least 4 dialogue lines")
	assert(AudioManager.last_sfx_played == "qte_perfect" or AudioManager.last_sfx_played == "part_break", "timeline_rescue_cock must trigger audio SFX")
	ev_cock_32.queue_free()
	await get_tree().process_frame

	print("[19] Issue #32: Dialogic 2 timelines, 4th-wall break choice, pisikot gag & mid-battle pause verified OK")
	# =========================================================================
	# [20] Issue #34: Epilogue: Robbers' Cabin Fairy-Tale Cutscene & Grand Victory Rock Concert
	# =========================================================================
	print("\n--- [20] VERIFYING ISSUE #34: EPILOGUE: ROBBERS' CABIN CUTSCENE & GRAND VICTORY ROCK CONCERT ---")

	# 20.1 Verify SceneManager routing and registration for EPILOGUE scene
	assert(SceneManager.SCENE_PATHS.has("EPILOGUE"), "SceneManager must register EPILOGUE scene")
	var epilogue_packed: PackedScene = load("res://src/epilogue/epilogue_scene.tscn") as PackedScene
	assert(epilogue_packed != null, "Epilogue scene must be loadable")
	var epilogue: EpilogueScene = epilogue_packed.instantiate() as EpilogueScene
	assert(epilogue != null, "Epilogue scene must instantiate as EpilogueScene")
	add_child(epilogue)
	await get_tree().process_frame

	# 20.2 Verify Act 1: Initial state starts at Cabin, showing Robo-Mega-Pyramid sprite
	assert(epilogue.get_current_act() == EpilogueScene.Act.CABIN, "Epilogue must start at Act 1: CABIN")
	assert(epilogue.get_cabin_sprite_path().ends_with("story_cabin_mega_pyramid.png") or epilogue.get_cabin_sprite_path().ends_with("bremen_pyramid.png") or epilogue.get_cabin_sprite_path().ends_with("6-2-fake-boss-monster.jpg") or epilogue.get_cabin_sprite_path().ends_with("6-1-fake-boss-apperiance.jpg"), "Initial Act 1 sprite must be Mega-Pyramid")
	assert(not epilogue.is_animal_pyramid_active(), "Classic animal pyramid must not be active initially")

	# 20.3 Verify Cabin cutscene sequence switches sprites from Mega-Pyramid to stacked animal pyramid with comic SFX
	# Step through dialogue to the disassembly line
	var reached_switch: bool = false
	for line_i: int in range(12):
		var cur_line: Dictionary = epilogue.get_dialogue_line(epilogue._line_cursor)
		if bool(cur_line.get("switch_pyramid", false)):
			reached_switch = true
			break
		epilogue.advance_cabin_dialogue()
		await get_tree().process_frame

	assert(reached_switch, "Must reach classic pyramid disassembly line in dialogue")
	assert(epilogue.is_animal_pyramid_active() == true, "Must switch to classic animal pyramid")
	assert(epilogue.get_cabin_sprite_path().ends_with("story_bremen_window_pyramid.png") or epilogue.get_cabin_sprite_path().ends_with("bremen_animal_pyramid.png") or epilogue.get_cabin_sprite_path().ends_with("6-3-fake-boss-piramide.jpg"), "Sprite must switch to classic animal pyramid")
	assert(epilogue.has_comic_sfx_played() == true, "Comic SFX must play on pyramid disassembly switch")

	# 20.4 Verify Outlaw dialogue displays authentic Brothers Grimm panic quotes and Felix punchline
	var found_outlaw_panic: bool = false
	var found_felix_punchline: bool = false
	for ch_line: Dictionary in epilogue._lines:
		var txt: String = String(ch_line.get("text", ""))
		var spk: String = String(ch_line.get("speaker", ""))
		if spk == "outlaw" and (txt.find("ведьма") != -1 or txt.find("witch") != -1) and (txt.find("когтями") != -1 or txt.find("claws") != -1) and (txt.find("ножом") != -1 or txt.find("knife") != -1 or txt.find("devil") != -1):
			found_outlaw_panic = true
		if spk == "felix" and (txt.find("робопетухокотопсоосла") != -1 or txt.find("Robo-RoosterCatDogDonkey") != -1):
			found_felix_punchline = true

	assert(found_outlaw_panic, "Outlaw dialogue must contain authentic Brothers Grimm panic quotes")
	assert(found_felix_punchline, "Felix dialogue must contain punchline: Robo-RoosterCatDogDonkey")

	# 20.5 Verify Act 2: Grand Victory Rock Concert
	var prev_highest_ng: int = SaveManager.highest_ng_cycle
	epilogue.start_act_2_concert()
	await get_tree().process_frame

	assert(epilogue.get_current_act() == EpilogueScene.Act.CONCERT, "Must transition to Act 2: CONCERT")

	# 20.6 Final Concert plays full polyphonic track (Guitar + Drums + Bass + Synth)
	assert(epilogue.is_polyphonic_track_playing() == true, "Final Concert must play full polyphonic track")
	assert(AudioManager.active_instruments.has("Гитара"), "Active instruments must include Guitar")
	assert(AudioManager.active_instruments.has("Барабан"), "Active instruments must include Drums")
	assert(AudioManager.active_instruments.has("Бас"), "Active instruments must include Bass")
	assert(AudioManager.active_instruments.has("Синтезатор"), "Active instruments must include Synth")

	# 20.7 Animated character rigs for all 4 musicians
	var rigs: Array[Dictionary] = epilogue.get_character_rigs()
	assert(rigs.size() == 4, "Concert stage must have exactly 4 character rigs (Mule, Felix, Hound, Cock)")
	var rig_ids: Array[String] = []
	for r: Dictionary in rigs:
		rig_ids.append(String(r["id"]))
	assert(rig_ids.has("FELIX") and rig_ids.has("HOUND") and rig_ids.has("MULE") and rig_ids.has("COCK"), "All 4 heroes must have animated character rigs on stage")

	# Simulate several process frames to verify animations, lighting & pyro
	epilogue._process(0.16)
	epilogue._process(0.16)
	await get_tree().process_frame
	assert(epilogue.are_lights_and_pyro_active() == true, "Stage spotlights and pyrotechnic cannons must be active")

	# 20.8 Credits roll over concert performance and player input allows skipping to Hub
	var initial_scroll_y: float = epilogue.get_credits_scroll_position()
	epilogue._process(0.5)
	assert(epilogue.get_credits_scroll_position() < initial_scroll_y, "Credits must roll upward over concert performance")

	var hub_requested: Array[bool] = [false]
	var scene_handler: Callable = func(s_name: StringName, _pl: Dictionary) -> void:
		if s_name == &"HUB":
			hub_requested[0] = true
	EventBus.request_scene_change.connect(scene_handler)
	epilogue.skip_to_hub()
	await get_tree().process_frame
	EventBus.request_scene_change.disconnect(scene_handler)
	assert(hub_requested[0] == true, "Player input skipping concert must navigate to Hub")

	# 20.9 Unlocks tape_bremen_triumph and sets highest_ng_cycle += 1 in SaveManager
	assert(SaveManager.unlocked_tapes.has("tape_bremen_triumph"), "Must unlock tape_bremen_triumph in SaveManager")
	assert(SaveManager.highest_ng_cycle == prev_highest_ng + 1, "Must set highest_ng_cycle += 1 in SaveManager")
	assert(SaveManager.story_progression.concert_hall_liberated == true, "Must set concert_hall_liberated = true")
	assert(SaveManager.story_progression.current_phase == StoryProgressionData.StoryPhase.COMPLETED, "Story phase must be COMPLETED")

	# Verify persistence of unlocked tape and NG+ cycle in meta_save.json
	SaveManager.save_meta()
	SaveManager.load_meta()
	assert(SaveManager.unlocked_tapes.has("tape_bremen_triumph"), "tape_bremen_triumph must persist across save_meta/load_meta roundtrip")
	assert(SaveManager.highest_ng_cycle == prev_highest_ng + 1, "highest_ng_cycle must persist across save_meta/load_meta roundtrip")

	# 20.10 Verify Dialogic 2 timeline files for Epilogue
	assert(FileAccess.file_exists("res://data/dialogues/epilogue_cabin_scene.dtl"), "epilogue_cabin_scene.dtl must exist")
	assert(FileAccess.file_exists("res://data/dialogues/boss_postlude_sector3.dtl"), "boss_postlude_sector3.dtl must exist")

	var ev_scene_epilogue: EventScene = ev_scene_res.instantiate() as EventScene
	ev_scene_epilogue.setup_event({"timeline": "res://data/dialogues/epilogue_cabin_scene.dtl"})
	add_child(ev_scene_epilogue)
	await get_tree().process_frame
	assert(ev_scene_epilogue._lines.size() >= 8, "epilogue_cabin_scene.dtl must parse into at least 8 lines in EventScene")
	ev_scene_epilogue.queue_free()
	await get_tree().process_frame

	epilogue.queue_free()
	await get_tree().process_frame

	print("[20] Issue #34: Robbers' cabin fairy-tale cutscene, sprite switch, Grimm quotes & victory rock concert verified OK")

	# =========================================================================
	# 21. Verify Issue #41: Dynamic Loop Prologue, Sputnik Boss Duel, Trubadur Entrance and Deferred Hound Join
	# =========================================================================
	print("[21] Verifying Issue #41: Dynamic Loop Prologue, Sputnik Boss Duel, Trubadur Entrance and Deferred Hound Join...")

	# 21.1 In CYCLE_0_SOLO_CAT, Cat enters Sector 1 alone (Hound does NOT join immediately)
	SaveManager.set_story_phase(StoryProgressionData.StoryPhase.CYCLE_0_SOLO_CAT)
	SaveManager.start_new_run(12345)
	assert(SaveManager.party.size() == 1, "CYCLE_0_SOLO_CAT must start with solo Felix")
	assert(SaveManager.party[0].cat_id == &"FELIX", "Party must contain only Felix")
	assert(not SaveManager.has_party_member("HOUND"), "Hound must NOT be in party at start of prologue")
	assert(SaveManager.current_sector == 1, "Prologue must start in Sector 1")

	# 21.2 Sector 1 Boss in CYCLE_0_SOLO_CAT is Sputnik (Blue biome)
	var p0_val: int = int(SaveManager.story_progression.current_phase)
	var p0_theme: String = MapGenerator.get_sector_theme(1, p0_val)
	assert(p0_theme == "BLUE", "CYCLE_0_SOLO_CAT Sector 1 theme must be BLUE")

	# 21.3 Defeating Sputnik in Cycle 0 yields Hound rescue data, postlude_sputnik_solo, and triggers Trubadur entrance
	var sputnik_defeat_res: Dictionary = SaveManager.handle_biome_boss_defeat("BLUE", "boss_satellite")
	assert(sputnik_defeat_res["companion_id"] == "HOUND", "Cycle 0 Sputnik defeat must yield companion HOUND")
	assert(sputnik_defeat_res["timeline_id"] == "boss_postlude_sputnik_solo", "Must route to boss_postlude_sputnik_solo timeline")
	assert(sputnik_defeat_res["photo_path"] == "res://assets/photos/1-4b-trubadur-apperiance.jpg", "Photo must be 1-4b-trubadur-apperiance.jpg")
	assert(int(SaveManager.story_progression.current_phase) == int(StoryProgressionData.StoryPhase.CYCLE_1_DUO), "Must advance to CYCLE_1_DUO")
	assert(SaveManager.story_progression.unlocked_party_members.has(&"HOUND"), "HOUND must be unlocked")
	assert(SaveManager.is_fusion_tier_unlocked(1), "Fusion Tier 1 (ROBO_CATDOG) must be unlocked")

	# 21.4 Advancing to next sector after Cycle 0 transition sets up Cycle 1 Duo at Sector 1
	SaveManager.advance_to_next_sector()
	assert(SaveManager.current_sector == 1, "Cycle 1 Duo must start at Sector 1 (Red Biome)")
	assert(SaveManager.has_party_member("FELIX") and SaveManager.has_party_member("HOUND"), "Party must now have Felix and Hound")
	assert(SaveManager.party.size() == 2, "Party must be exactly 2 members (MULE must not be recruited yet)")
	assert(not SaveManager.has_party_member("MULE"), "MULE must not be recruited in Cycle 1 Sector 1")

	# 21.5 Verify EventScene parses boss_prelude_sputnik_solo.dtl and boss_postlude_sputnik_solo.dtl
	var ev_p0_prelude: EventScene = ev_scene_res.instantiate() as EventScene
	ev_p0_prelude.setup_event({"timeline": "res://data/dialogues/boss_prelude_sputnik_solo.dtl"})
	add_child(ev_p0_prelude)
	await get_tree().process_frame
	assert(ev_p0_prelude._lines.size() >= 3, "boss_prelude_sputnik_solo.dtl must parse into at least 3 lines")
	ev_p0_prelude.queue_free()
	await get_tree().process_frame

	var ev_p0_postlude: EventScene = ev_scene_res.instantiate() as EventScene
	ev_p0_postlude.setup_event({"timeline": "res://data/dialogues/boss_postlude_sputnik_solo.dtl"})
	add_child(ev_p0_postlude)
	await get_tree().process_frame
	assert(ev_p0_postlude._lines.size() >= 7, "boss_postlude_sputnik_solo.dtl must parse into at least 7 lines")
	ev_p0_postlude.queue_free()
	await get_tree().process_frame

	# 21.6 In Cycle 1 Sector 1, Boss is Press (2-2-press-boss-appirance.jpg, boss_prelude_sector1.dtl)
	var p1_val: int = int(SaveManager.story_progression.current_phase)
	assert(p1_val == int(StoryProgressionData.StoryPhase.CYCLE_1_DUO), "Must be in CYCLE_1_DUO")
	var press_defeat_res: Dictionary = SaveManager.handle_biome_boss_defeat("YELLOW", "boss_press")
	assert(press_defeat_res["companion_id"] == "MULE", "Press defeat must rescue MULE")
	assert(press_defeat_res["photo_path"] == "res://assets/photos/2-3a-press-boss-win.jpg", "Press defeat must show 2-3a-press-boss-win.jpg")
	assert(press_defeat_res["timeline_id"] == "dialogic_rescue_mule", "Must route to dialogic_rescue_mule")
	assert(SaveManager.party.size() == 3, "Party must now have Felix, Hound, Mule")

	# 21.7 Subsequent Sputnik defeat in Cycle 1 routes to Trubadur Trio postlude & photo (breaking 3 stations)
	var sputnik_c1_res: Dictionary = SaveManager.handle_biome_boss_defeat("BLUE", "boss_satellite")
	assert(sputnik_c1_res["timeline_id"] == "boss_postlude_trubadur_trio", "Cycle 1 Sputnik defeat must route to boss_postlude_trubadur_trio")
	assert(sputnik_c1_res["photo_path"] == "res://assets/photos/5-1-trubadur-full.jpg", "Cycle 1 Sputnik defeat must show 5-1-trubadur-full.jpg")
	assert(SaveManager.current_sector == 1, "Sputnik defeat in Cycle 1 sets current_sector to 1 so advance enters Sector 2")

	# 21.8 In Cycle 2 Sector 2, Boss is Atamansha (3-1-atamansha-boss-apperiance.jpg, boss_prelude_sector2.dtl)
	SaveManager.advance_to_next_sector()
	assert(SaveManager.current_sector == 2, "Must advance to Sector 2 (Bandit Den) for Cycle 2")
	var atamansha_defeat_res: Dictionary = SaveManager.handle_biome_boss_defeat("GREEN", "boss_atamansha")
	assert(atamansha_defeat_res["companion_id"] == "COCK", "Atamansha defeat must rescue COCK")
	assert(atamansha_defeat_res["photo_path"] == "res://assets/photos/3-2a-atamansha-boss-win.jpg", "Atamansha defeat must show 3-2a-atamansha-boss-win.jpg")
	assert(atamansha_defeat_res["timeline_id"] == "dialogic_rescue_cock", "Must route to dialogic_rescue_cock")
	assert(SaveManager.party.size() == 4, "Party must now have all 4 members")

	# 21.9 Subsequent Sputnik defeat in Cycle 2 routes to Trubadur Quartet postlude (breaking all 4 stations)
	var sputnik_c2_res: Dictionary = SaveManager.handle_biome_boss_defeat("BLUE", "boss_satellite")
	assert(sputnik_c2_res["timeline_id"] == "boss_postlude_trubadur_quartet", "Cycle 2 Sputnik defeat must route to boss_postlude_trubadur_quartet")
	assert(sputnik_c2_res["photo_path"] == "res://assets/photos/5-1-trubadur-full.jpg", "Cycle 2 Sputnik defeat must show 5-1-trubadur-full.jpg")

	# 21.10 Verify EventScene parses boss_postlude_trubadur_trio.dtl, story_intro_trio.dtl and boss_postlude_trubadur_quartet.dtl
	var ev_trio: EventScene = ev_scene_res.instantiate() as EventScene
	ev_trio.setup_event({"timeline": "res://data/dialogues/boss_postlude_trubadur_trio.dtl"})
	add_child(ev_trio)
	await get_tree().process_frame
	assert(ev_trio._lines.size() >= 8, "boss_postlude_trubadur_trio.dtl must parse into at least 8 lines")
	ev_trio.queue_free()
	await get_tree().process_frame

	var ev_trio_intro: EventScene = ev_scene_res.instantiate() as EventScene
	ev_trio_intro.setup_event({"timeline": "res://data/dialogues/story_intro_trio.dtl"})
	add_child(ev_trio_intro)
	await get_tree().process_frame
	assert(ev_trio_intro._lines.size() >= 6, "story_intro_trio.dtl must parse into at least 6 lines")
	ev_trio_intro.queue_free()
	await get_tree().process_frame

	var ev_quartet: EventScene = ev_scene_res.instantiate() as EventScene
	ev_quartet.setup_event({"timeline": "res://data/dialogues/boss_postlude_trubadur_quartet.dtl"})
	add_child(ev_quartet)
	await get_tree().process_frame
	assert(ev_quartet._lines.size() >= 10, "boss_postlude_trubadur_quartet.dtl must parse into at least 10 lines")
	ev_quartet.queue_free()
	await get_tree().process_frame

	print("[21] Issue #41: Dynamic Loop Prologue, Sputnik Boss Duel, Trubadur Entrance and Deferred Hound Join verified OK")

	# 22. Issue #43: Arts Compression & Preview Aspect Ratio in Dialogues
	print("--- [22] VERIFYING ISSUE #43: ARTS COMPRESSION & PREVIEW IN DIALOGUES ---")
	var ev_test_43: EventScene = ev_scene_res.instantiate() as EventScene
	ev_test_43.setup_event({"timeline": "res://data/dialogues/story_intro_cat.dtl"})
	add_child(ev_test_43)
	await get_tree().process_frame
	assert(ev_test_43._illustration_rect.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "Illustration rect must use TEXTURE_FILTER_LINEAR_WITH_MIPMAPS")
	assert(ev_test_43._illustration_rect.custom_minimum_size.x == 256 and ev_test_43._illustration_rect.custom_minimum_size.y == 144, "16:9 illustration must be 256x144, not cramped 280x100")
	var ev_aspect: float = ev_test_43._illustration_rect.custom_minimum_size.x / ev_test_43._illustration_rect.custom_minimum_size.y
	assert(abs(ev_aspect - (16.0 / 9.0)) < 0.05, "Illustration aspect ratio must be 16:9")

	# Verify dynamic adaptation for wide sprite
	if ResourceLoader.exists("res://assets/sprites/story/story_cat_exile.png"):
		ev_test_43._update_illustration(load("res://assets/sprites/story/story_cat_exile.png") as Texture2D)
		assert(ev_test_43._illustration_rect.custom_minimum_size.x == 280 and ev_test_43._illustration_rect.custom_minimum_size.y == 99, "Wide sprite must scale to 280x99 preserving aspect")
	ev_test_43.queue_free()
	await get_tree().process_frame

	# Verify EpilogueScene cabin illustration
	var ep_test_43_packed: PackedScene = load("res://src/epilogue/epilogue_scene.tscn") as PackedScene
	var ep_test_43: EpilogueScene = ep_test_43_packed.instantiate() as EpilogueScene
	ep_test_43.setup_epilogue({"act": 1})
	add_child(ep_test_43)
	await get_tree().process_frame
	assert(ep_test_43._cabin_illustration_rect.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "Cabin illustration rect must use TEXTURE_FILTER_LINEAR_WITH_MIPMAPS")
	assert(ep_test_43._cabin_illustration_rect.custom_minimum_size.x == 256 and ep_test_43._cabin_illustration_rect.custom_minimum_size.y == 144, "Cabin 16:9 photo must be 256x144")
	ep_test_43.queue_free()
	await get_tree().process_frame

	# Verify VideoPlayerScene photo filter
	var vid_test_43_packed: PackedScene = load("res://src/core/video_player_scene.tscn") as PackedScene
	var vid_test_43: VideoPlayerScene = vid_test_43_packed.instantiate() as VideoPlayerScene
	add_child(vid_test_43)
	await get_tree().process_frame
	assert(vid_test_43._photo_rect.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "Video player photo rect must use TEXTURE_FILTER_LINEAR_WITH_MIPMAPS")
	vid_test_43.queue_free()
	await get_tree().process_frame

	print("[22] Issue #43: Arts compression & dialogue preview aspect ratio verified OK")

	# 23. Elimination of Duplicate Robbers' Cabin Scene & Routing to Epilogue Rock Concert
	print("\n--- [23] VERIFYING ELIMINATION OF DUPLICATE CABIN SCENE & ROCK CONCERT ROUTING ---")
	SaveManager.start_new_run()
	SaveManager.current_sector = 2
	SaveManager.recruit_cat("HOUND")
	SaveManager.recruit_cat("MULE")
	SaveManager.recruit_cat("COCK")
	assert(SaveManager.party.size() == 4, "Party must have all 4 members for quartet finale test")

	# 23.1 Test Quartet defeat of Sputnik transition chain in CombatArena
	var arena_23_packed: PackedScene = load("res://src/combat/combat_arena.tscn") as PackedScene
	var test_arena: CombatArena = arena_23_packed.instantiate() as CombatArena
	test_arena.setup_battle({"node_id": 88, "node_type": "BOSS", "boss_id": "boss_satellite", "biome_theme": "BLUE"})
	add_child(test_arena)
	await get_tree().process_frame

	var captured_scene_23: Array[StringName] = [&""]
	var captured_payload_23: Array[Dictionary] = [{}]
	var on_scene_change: Callable = func(sn: StringName, sp: Dictionary) -> void:
		captured_scene_23[0] = sn
		captured_payload_23[0] = sp

	EventBus.request_scene_change.connect(on_scene_change)
	test_arena._enemies[0].body_part.current_hp = 0
	test_arena._handle_victory()
	test_arena._end_btn.pressed.emit()
	await get_tree().process_frame

	assert(captured_scene_23[0] == &"VIDEO", "Must transition to VIDEO player for 5-1-trubadur-full.jpg")
	assert(captured_payload_23[0]["image_path"] == "res://assets/photos/5-1-trubadur-full.jpg", "Must show 5-1-trubadur-full.jpg")

	# Step 1: Trubadur postlude payload
	var p1_trubadur: Dictionary = captured_payload_23[0]["next_payload"] as Dictionary
	assert(p1_trubadur["timeline_name"] == "boss_postlude_trubadur_quartet", "Must route to boss_postlude_trubadur_quartet")
	assert(captured_payload_23[0]["next_scene"] == &"EVENT", "Next scene after video must be EVENT")

	# Step 2: Cabin exterior cutscene payload
	var p2_cabin_cutscene: Dictionary = p1_trubadur["next_payload"] as Dictionary
	assert(p1_trubadur["next_scene"] == &"VIDEO", "Next scene after quartet postlude must be VIDEO")
	assert(p2_cabin_cutscene["image_path"] == "res://assets/photos/6-1-fake-boss-apperiance.jpg", "Must show 6-1-fake-boss-apperiance.jpg")

	# Step 3: Cabin dialogue payload (played ONCE as boss_postlude_sector3)
	var p3_cabin_dialogue: Dictionary = p2_cabin_cutscene["next_payload"] as Dictionary
	assert(p2_cabin_cutscene["next_scene"] == &"EVENT", "Next scene after cabin photo must be EVENT")
	assert(p3_cabin_dialogue["timeline_name"] == "boss_postlude_sector3", "Cabin dialogue must run boss_postlude_sector3")

	# Step 4: Epilogue concert cutscene payload
	var p4_concert_cutscene: Dictionary = p3_cabin_dialogue["next_payload"] as Dictionary
	assert(p3_cabin_dialogue["next_scene"] == &"VIDEO", "Next scene after cabin dialogue must be VIDEO")
	assert(p4_concert_cutscene["image_path"] == "res://assets/photos/7-final.jpg", "Must show 7-final.jpg for grand rock concert")

	# Step 5: Epilogue rock concert scene (NOT a duplicate cabin scene, and NOT directly HUB!)
	assert(p4_concert_cutscene["next_scene"] == &"EPILOGUE", "7-final.jpg must route directly to EPILOGUE scene")
	var p5_concert: Dictionary = p4_concert_cutscene["next_payload"] as Dictionary
	assert(int(p5_concert.get("act", 0)) == 2, "EPILOGUE payload must launch Act 2 (Rock Concert)")
	assert(p4_concert_cutscene.get("action_on_complete", "") == "finish_run", "Must mark action_on_complete as finish_run")

	# Verify that duplicate epilogue_cabin_scene.dtl is completely absent from the entire payload tree
	var serialized_payload: String = str(captured_payload_23[0])
	assert(not serialized_payload.contains("epilogue_cabin_scene"), "Duplicate epilogue_cabin_scene must NOT be present in transition chain")

	EventBus.request_scene_change.disconnect(on_scene_change)
	test_arena.queue_free()
	await get_tree().process_frame

	# 23.2 Test boss_censor transition chain in CombatArena
	var censor_arena: CombatArena = arena_23_packed.instantiate() as CombatArena
	censor_arena.setup_battle({"node_id": 89, "node_type": "BOSS", "boss_id": "boss_censor", "biome_theme": "BLUE"})
	add_child(censor_arena)
	await get_tree().process_frame

	EventBus.request_scene_change.connect(on_scene_change)
	censor_arena._enemies[0].body_part.current_hp = 0
	censor_arena._handle_victory()
	censor_arena._end_btn.pressed.emit()
	await get_tree().process_frame

	assert(captured_scene_23[0] == &"VIDEO", "Censor defeat must transition to VIDEO")
	assert(captured_payload_23[0]["image_path"] == "res://assets/photos/6-4-fake-boss-win.jpg", "Must show 6-4-fake-boss-win.jpg")
	var censor_post: Dictionary = captured_payload_23[0]["next_payload"] as Dictionary
	assert(censor_post["timeline_name"] == "boss_postlude_sector3", "Must route to boss_postlude_sector3")
	var censor_concert_cut: Dictionary = censor_post["next_payload"] as Dictionary
	assert(censor_concert_cut["image_path"] == "res://assets/photos/7-final.jpg", "Must show 7-final.jpg")
	assert(censor_concert_cut["next_scene"] == &"EPILOGUE", "Censor 7-final.jpg must route directly to EPILOGUE scene")
	var censor_concert_payload: Dictionary = censor_concert_cut["next_payload"] as Dictionary
	assert(int(censor_concert_payload.get("act", 0)) == 2, "Must launch Act 2 (Rock Concert)")
	assert(not str(captured_payload_23[0]).contains("epilogue_cabin_scene"), "Duplicate epilogue_cabin_scene must not be present for Censor")

	EventBus.request_scene_change.disconnect(on_scene_change)
	censor_arena.queue_free()
	await get_tree().process_frame

	# 23.3 Verify EpilogueScene starting directly in Act 2 (Rock Concert)
	var ep_direct_packed: PackedScene = load("res://src/epilogue/epilogue_scene.tscn") as PackedScene
	var ep_direct: EpilogueScene = ep_direct_packed.instantiate() as EpilogueScene
	ep_direct.setup_epilogue({"act": 2, "source": "final_boss_victory"})
	add_child(ep_direct)
	await get_tree().process_frame

	assert(ep_direct.get_current_act() == EpilogueScene.Act.CONCERT, "Must start directly at Act 2: CONCERT")
	assert(ep_direct._act1_root.visible == false, "Cabin Act 1 must be invisible")
	assert(ep_direct._act2_root.visible == true, "Concert Act 2 must be visible")
	assert(ep_direct.is_polyphonic_track_playing() == true, "4-instrument polyphonic concert music must play")
	assert(ep_direct.are_lights_and_pyro_active() == true, "Stage lights and pyrotechnics must be active")
	assert(SaveManager.story_progression.concert_hall_liberated == true, "Concert hall must be marked liberated")
	assert(SaveManager.unlocked_tapes.has("tape_bremen_triumph"), "tape_bremen_triumph must be unlocked")

	# Verify return to hub from concert deletes active run save
	SaveManager.has_active_run = true
	ep_direct.skip_to_hub()
	await get_tree().process_frame
	assert(not SaveManager.has_active_run, "Returning to HUB from epilogue concert must delete active run save")
	ep_direct.queue_free()
	await get_tree().process_frame

	print("[23] Elimination of duplicate robbers' cabin scene & routing to epilogue rock concert verified OK")

	print("\n--- [24] VERIFYING ISSUE #45: GAMEPAD & MOBILE TOUCH SUPPORT ---")

	# 24.1 Input Actions Registration
	assert(InputMap.has_action(&"dodge_left"), "dodge_left action must be registered")
	assert(InputMap.has_action(&"dodge_right"), "dodge_right action must be registered")
	assert(InputMap.has_action(&"dodge_up"), "dodge_up action must be registered")
	assert(InputMap.has_action(&"dodge_down"), "dodge_down action must be registered")
	assert(InputMap.has_action(&"qte_strike"), "qte_strike action must be registered")
	assert(InputMap.has_action(&"pause"), "pause action must be registered")

	var dodge_l_events: Array[InputEvent] = InputMap.action_get_events(&"dodge_left")
	var has_joy_dodge: bool = false
	for ev: InputEvent in dodge_l_events:
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			has_joy_dodge = true
			break
	assert(has_joy_dodge, "dodge_left must have gamepad joypad event mapped")

	var qte_events: Array[InputEvent] = InputMap.action_get_events(&"qte_strike")
	var has_joy_qte: bool = false
	for ev: InputEvent in qte_events:
		if ev is InputEventJoypadButton:
			has_joy_qte = true
			break
	assert(has_joy_qte, "qte_strike must have gamepad joypad button event mapped")

	# 24.2 DodgeArena Mobile Touch D-Pad & Boundaries
	var da: DodgeArena = DodgeArena.new()
	add_child(da)
	await get_tree().process_frame
	da.start_dodge("TEST_MOBILE", &"saw_sweep", 10, 1.0, 5.0)

	var start_pos: Vector2 = da._avatar_root.position
	# Simulate left button press
	da._touch_btn_left.emit_signal("button_down")
	assert(da._dpad_dir.x < -0.9, "Left D-pad button down must set negative X direction")
	da._process(0.2)
	assert(da._avatar_root.position.x < start_pos.x, "Avatar must move left when left touch D-pad is held")
	da._touch_btn_left.emit_signal("button_up")
	assert(da._dpad_dir == Vector2.ZERO, "Releasing touch D-pad button must reset direction")

	# Simulate up button press
	var pos_before_up: Vector2 = da._avatar_root.position
	da._touch_btn_up.emit_signal("button_down")
	da._process(0.2)
	assert(da._avatar_root.position.y < pos_before_up.y, "Avatar must move up when up touch D-pad is held")
	da._touch_btn_up.emit_signal("button_up")

	# 24.3 DodgeArena Floating Virtual Joystick (Touch)
	var touch_down: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_down.index = 1
	touch_down.pressed = true
	touch_down.position = da.global_position + Vector2(-50.0, 50.0)
	da._unhandled_input(touch_down)
	assert(da._virtual_stick_active, "Touch outside arena box must activate floating virtual joystick")

	var touch_drag: InputEventScreenDrag = InputEventScreenDrag.new()
	touch_drag.index = 1
	touch_drag.position = touch_down.position + Vector2(25.0, 0.0)
	da._unhandled_input(touch_drag)
	assert(da._virtual_dir.x > 0.5, "Dragging right on virtual joystick must steer avatar right")

	var pos_before_joy: Vector2 = da._avatar_root.position
	da._process(0.2)
	assert(da._avatar_root.position.x > pos_before_joy.x, "Avatar must move right from floating virtual stick")

	var touch_up: InputEventScreenTouch = InputEventScreenTouch.new()
	touch_up.index = 1
	touch_up.pressed = false
	touch_up.position = touch_drag.position
	da._unhandled_input(touch_up)
	assert(not da._virtual_stick_active, "Releasing touch must deactivate floating virtual stick")
	assert(da._virtual_dir == Vector2.ZERO, "Releasing touch must reset virtual direction to ZERO")

	# 24.4 DodgeArena Direct/Relative Touch Drag Inside Box
	var drag_touch_down: InputEventScreenTouch = InputEventScreenTouch.new()
	drag_touch_down.index = 2
	drag_touch_down.pressed = true
	drag_touch_down.position = da.global_position + da._box_origin + Vector2(20.0, 20.0)
	da._unhandled_input(drag_touch_down)
	assert(da._touch_drag_active, "Touching inside arena box must activate touch drag mode")

	var drag_touch_move: InputEventScreenDrag = InputEventScreenDrag.new()
	drag_touch_move.index = 2
	drag_touch_move.position = drag_touch_down.position + Vector2(15.0, 15.0)
	da._unhandled_input(drag_touch_move)
	assert(da._pending_drag_delta.x > 10.0, "Dragging inside box must record drag delta")

	var pos_before_drag: Vector2 = da._avatar_root.position
	da._process(0.016)
	assert(da._avatar_root.position.x > pos_before_drag.x, "Avatar must move from direct touch drag")

	# Test box boundaries clamping
	da._avatar_root.position = Vector2(9999.0, 9999.0)
	da._clamp_avatar_position()
	assert(da._avatar_root.position.x <= da._box_origin.x + da.BOX_W - 11.0, "Clamping must prevent avatar exceeding right boundary")
	assert(da._avatar_root.position.y <= da._box_origin.y + da.BOX_H - 12.0, "Clamping must prevent avatar exceeding bottom boundary")

	da.queue_free()
	await get_tree().process_frame

	# 24.5 QTE Controller Gamepad and Touch Strike
	var qte: QTEController = QTEController.new()
	add_child(qte)
	await get_tree().process_frame

	# Test Joypad Button strike
	qte.start_qte("TEST_SKILL", 1.0)
	assert(qte._active and not qte._resolved, "QTE must start active")
	var joy_btn_ev: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_btn_ev.button_index = JOY_BUTTON_A
	joy_btn_ev.pressed = true
	qte._input(joy_btn_ev)
	assert(qte._resolved, "Gamepad JOY_BUTTON_A must trigger QTE strike")

	# Test Touch Screen tap strike
	qte.start_qte("TEST_SKILL_TOUCH", 1.0)
	assert(qte._active and not qte._resolved, "QTE must start active")
	var screen_touch_ev: InputEventScreenTouch = InputEventScreenTouch.new()
	screen_touch_ev.pressed = true
	qte._input(screen_touch_ev)
	assert(qte._resolved, "Screen touch tap must trigger QTE strike")

	qte.queue_free()
	await get_tree().process_frame

	# 24.6 UI Focus Navigation for Gamepad in Combat Arena
	var combat_test: CombatArena = load("res://src/combat/combat_arena.tscn").instantiate() as CombatArena
	add_child(combat_test)
	await get_tree().process_frame
	combat_test._begin_player_turn(0)
	await get_tree().process_frame
	var focused_action: Control = combat_test.get_viewport().gui_get_focus_owner()
	assert(focused_action != null and focused_action is Button, "First action button must automatically grab focus on player turn for gamepad")
	assert((focused_action as Button).has_theme_stylebox_override("focus"), "Combat action button must have high-contrast focus stylebox")

	# Test focus reclaim when focus is lost in action menu
	combat_test.get_viewport().gui_release_focus()
	assert(combat_test.get_viewport().gui_get_focus_owner() == null, "Focus should be cleared")
	var stick_nav: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_nav.axis = JOY_AXIS_LEFT_Y
	stick_nav.axis_value = 0.8
	combat_test._unhandled_input(stick_nav)
	await get_tree().process_frame
	var reclaimed_action: Control = combat_test.get_viewport().gui_get_focus_owner()
	assert(reclaimed_action != null and reclaimed_action is Button, "Stick movement must reclaim focus in action menu when lost")

	# Test Modular Enemy Target Box with Vertical Part Buttons and Circular Navigation
	var modular_ed: EnemyData = DataCatalog.get_enemy("elite_crusher")
	assert(modular_ed != null, "elite_crusher must exist")
	var modular_en: EnemyInstance = EnemyInstance.new(modular_ed)
	assert(modular_en.is_modular(), "elite_crusher must be modular")
	combat_test._enemies = [modular_en]
	combat_test._turn_queue = [
		{"is_player": true, "index": 0, "score": 20},
		{"is_player": false, "index": 0, "score": 15}
	]
	combat_test._turn_cursor = 0

	var test_sk: SkillData = DataCatalog.get_skill("felix_laser_claws")
	combat_test._on_skill_chosen(test_sk)
	await get_tree().process_frame

	var focused_target: Control = combat_test.get_viewport().gui_get_focus_owner()
	assert(focused_target != null and focused_target is Button, "First target button must automatically grab focus on targeting for gamepad")
	assert((focused_target as Button).has_theme_stylebox_override("focus"), "Target button must have high-contrast focus stylebox")

	# Find Body, Arms, Legs, and Back buttons in _target_box
	var body_btn: Button = null
	var arms_btn: Button = null
	var legs_btn: Button = null
	var back_btn: Button = null

	for child: Node in combat_test._target_box.get_children():
		if child is Button:
			var btn: Button = child as Button
			var txt: String = btn.text.to_upper()
			if "КОРПУС" in txt:
				body_btn = btn
			elif "ОРУЖИЕ" in txt:
				arms_btn = btn
			elif "ШАССИ" in txt:
				legs_btn = btn
			elif "НАЗАД" in txt:
				back_btn = btn

	assert(body_btn != null, "Target box must have full-width Body button")
	assert(arms_btn != null, "Target box must have full-width Arms button")
	assert(legs_btn != null, "Target box must have full-width Legs button")
	assert(back_btn != null, "Target box must have Back button")

	# Verify circular focus neighbor chain (Body <-> Arms <-> Legs <-> Back <-> Body)
	assert(body_btn.get_node(body_btn.focus_neighbor_bottom) == arms_btn, "Body down must lead to Arms")
	assert(arms_btn.get_node(arms_btn.focus_neighbor_bottom) == legs_btn, "Arms down must lead to Legs")
	assert(legs_btn.get_node(legs_btn.focus_neighbor_bottom) == back_btn, "Legs down must lead to Back")
	assert(back_btn.get_node(back_btn.focus_neighbor_bottom) == body_btn, "Back down must wrap to Body")

	assert(body_btn.get_node(body_btn.focus_neighbor_top) == back_btn, "Body up must wrap to Back")
	assert(back_btn.get_node(back_btn.focus_neighbor_top) == legs_btn, "Back up must lead to Legs")
	assert(legs_btn.get_node(legs_btn.focus_neighbor_top) == arms_btn, "Legs up must lead to Arms")
	assert(arms_btn.get_node(arms_btn.focus_neighbor_top) == body_btn, "Arms up must lead to Body")

	# Verify broken part is disabled and skipped by circular chain
	modular_en.get_part(PartData.PartSlot.ARMS).current_hp = 0
	assert(modular_en.get_part(PartData.PartSlot.ARMS).is_broken())
	combat_test._on_skill_chosen(test_sk)
	await get_tree().process_frame

	var body_btn2: Button = null
	var arms_btn2: Button = null
	var legs_btn2: Button = null
	for child2: Node in combat_test._target_box.get_children():
		if child2 is Button:
			var btn2: Button = child2 as Button
			if "КОРПУС" in btn2.text.to_upper():
				body_btn2 = btn2
			elif "ОРУЖИЕ" in btn2.text.to_upper():
				arms_btn2 = btn2
			elif "ШАССИ" in btn2.text.to_upper():
				legs_btn2 = btn2

	assert(arms_btn2 != null and arms_btn2.disabled, "Broken arms part button must be disabled")
	assert(body_btn2 != null and legs_btn2 != null)
	assert(body_btn2.get_node(body_btn2.focus_neighbor_bottom) == legs_btn2, "Body down must skip broken Arms and lead directly to Legs")

	# Test Joypad B button cancel returning to action box
	var b_ev: InputEventJoypadButton = InputEventJoypadButton.new()
	b_ev.button_index = JOY_BUTTON_B
	b_ev.pressed = true
	combat_test._unhandled_input(b_ev)
	await get_tree().process_frame
	assert(combat_test._action_box.visible and not combat_test._target_box.visible, "Joypad B must return to action menu")

	# Test Elite + Regular Mob targeting (No black menu, both targets selectable)
	var reg_ed: EnemyData = DataCatalog.get_enemy("drone_scout")
	if reg_ed == null:
		var sec1_regs: Array[EnemyData] = DataCatalog.get_enemies_for_sector(1, false, false)
		assert(not sec1_regs.is_empty())
		reg_ed = sec1_regs[0]
	var reg_en: EnemyInstance = EnemyInstance.new(reg_ed)
	var modular_en3: EnemyInstance = EnemyInstance.new(modular_ed)
	combat_test._enemies = [modular_en3, reg_en]
	combat_test._turn_queue = [
		{"is_player": true, "index": 0, "score": 20},
		{"is_player": false, "index": 0, "score": 15},
		{"is_player": false, "index": 1, "score": 10}
	]
	combat_test._turn_cursor = 0
	combat_test._on_skill_chosen(test_sk)
	await get_tree().process_frame

	assert(combat_test._target_box.visible, "Target box must be visible")
	var elite_part_count: int = 0
	var mob_btn_found: bool = false
	for ch_e: Node in combat_test._target_box.get_children():
		if ch_e is Button:
			var bt: Button = ch_e as Button
			var btxt: String = bt.text.to_upper()
			if "КОРПУС" in btxt or "ОРУЖИЕ" in btxt or "ШАССИ" in btxt:
				elite_part_count += 1
			elif reg_ed.enemy_name.to_upper() in btxt:
				mob_btn_found = true

	assert(elite_part_count >= 3, "Elite parts must all be present when targeting elite + mob")
	assert(mob_btn_found, "Regular mob button must be present alongside elite parts")

	combat_test.queue_free()
	await get_tree().process_frame

	# 24.7 Mid-Battle Dialogue & Hound Question Gamepad Navigation
	var mid_dlg: MidBattleDialogueOverlay = MidBattleDialogueOverlay.new()
	add_child(mid_dlg)
	mid_dlg.setup_timeline("res://data/dialogues/timeline_first_fusion.dtl")
	await get_tree().process_frame

	mid_dlg._line_cursor = mid_dlg._lines.size() - 1
	mid_dlg._render_dialogue_state()
	await get_tree().process_frame

	var choice_btns: Array[Button] = []
	for ch_d: Node in mid_dlg._choices_box.get_children():
		if ch_d is Button:
			choice_btns.append(ch_d as Button)

	assert(choice_btns.size() >= 2, "Hound question must have at least 2 choice buttons")
	assert(choice_btns[0].has_theme_stylebox_override("focus"), "Choice button must have high-contrast focus stylebox")
	assert(choice_btns[0].get_node(choice_btns[0].focus_neighbor_bottom) == choice_btns[1], "Down on choice 0 must lead to choice 1")
	assert(choice_btns[1].get_node(choice_btns[1].focus_neighbor_top) == choice_btns[0], "Up on choice 1 must lead to choice 0")

	mid_dlg.get_viewport().gui_release_focus()
	assert(mid_dlg.get_viewport().gui_get_focus_owner() == null)
	var dlg_nav: InputEventJoypadMotion = InputEventJoypadMotion.new()
	dlg_nav.axis = JOY_AXIS_LEFT_Y
	dlg_nav.axis_value = 0.7
	mid_dlg._unhandled_input(dlg_nav)
	await get_tree().process_frame
	assert(mid_dlg.get_viewport().gui_get_focus_owner() != null, "Joypad navigation must reclaim focus on dialogue choices")

	choice_btns[0].grab_focus()
	var choice_advanced: bool = mid_dlg.advance()
	assert(choice_advanced, "Advance on focused choice button must select that choice")

	mid_dlg.close_dialogue()
	await get_tree().process_frame

	# 24.8 Event Scene Gamepad Choice Navigation
	var ev_scene: EventScene = load("res://src/event/event_scene.tscn").instantiate() as EventScene
	add_child(ev_scene)
	ev_scene.setup_event({"timeline": "res://data/dialogues/event_overloaded_core.dtl"})
	await get_tree().process_frame

	ev_scene._line_cursor = ev_scene._lines.size() - 1
	ev_scene._render_dialogue_state()
	await get_tree().process_frame

	var ev_choice_btns: Array[Button] = []
	for ch_ev: Node in ev_scene._choices_box.get_children():
		if ch_ev is Button:
			ev_choice_btns.append(ch_ev as Button)

	assert(ev_choice_btns.size() >= 2, "Event must display choice buttons")
	assert(ev_choice_btns[0].has_theme_stylebox_override("focus"), "Event choice button must have high-contrast focus stylebox")
	assert(ev_choice_btns[0].get_node(ev_choice_btns[0].focus_neighbor_bottom) == ev_choice_btns[1], "Down on event choice 0 must lead to choice 1")

	ev_choice_btns[1].grab_focus()
	var ev_advanced: bool = ev_scene._advance_dialogue_or_continue()
	assert(ev_advanced, "Advance on focused event choice button must activate that choice")

	ev_scene.queue_free()
	await get_tree().process_frame

	# 24.9 Garage Parts List Gamepad Navigation & Scrolling
	var garage_test: GarageScene = load("res://src/garage/garage_scene.tscn").instantiate() as GarageScene
	SaveManager.spare_parts_inventory = [
		{"part_id": "titan_body", "current_hp": 80},
		{"part_id": "titan_arms", "current_hp": 60},
		{"part_id": "titan_legs", "current_hp": 50},
		{"part_id": "titan_body", "current_hp": 80},
		{"part_id": "titan_arms", "current_hp": 60},
		{"part_id": "titan_legs", "current_hp": 50},
		{"part_id": "titan_body", "current_hp": 80},
		{"part_id": "titan_arms", "current_hp": 60},
		{"part_id": "titan_legs", "current_hp": 50}
	]
	add_child(garage_test)
	await get_tree().process_frame

	assert(garage_test._right_scroll != null, "Garage must have ScrollContainer for spare parts")
	var garage_eq_btns: Array[Button] = []
	for inv_c: Node in garage_test._inventory_box.get_children():
		if inv_c is VBoxContainer:
			for sub_b: Node in inv_c.get_children():
				if sub_b is Button:
					garage_eq_btns.append(sub_b as Button)

	assert(garage_eq_btns.size() >= 3, "Garage must have equip buttons for all inventory items")
	assert(garage_eq_btns[0].has_theme_stylebox_override("focus"), "Equip button must have high-contrast focus stylebox")
	assert(garage_eq_btns[0].get_node(garage_eq_btns[0].focus_neighbor_bottom) == garage_eq_btns[1], "Down on part 0 must lead to part 1")
	assert(garage_eq_btns[1].get_node(garage_eq_btns[1].focus_neighbor_bottom) == garage_eq_btns[2], "Down on part 1 must lead to part 2")

	var r_stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	r_stick.axis = JOY_AXIS_RIGHT_Y
	r_stick.axis_value = 1.0
	garage_test._unhandled_input(r_stick)
	assert(garage_test.get_viewport().is_input_handled(), "Right analog stick motion must be handled by garage scroll")

	var initial_cat_idx: int = garage_test._selected_cat_idx
	var rb_ev: InputEventJoypadButton = InputEventJoypadButton.new()
	rb_ev.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb_ev.pressed = true
	garage_test._unhandled_input(rb_ev)
	assert(garage_test._selected_cat_idx != initial_cat_idx or SaveManager.party.size() <= 1, "RB must cycle selected cat in garage")

	garage_test.queue_free()
	await get_tree().process_frame

	# 24.10 GameSettings Touch Controls Persistence
	SaveManager.settings.touch_controls_enabled = false
	SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)
	SaveManager.settings.load_from_disk(SaveManager.SETTINGS_PATH)
	assert(not SaveManager.settings.touch_controls_enabled, "touch_controls_enabled false must persist to settings.cfg")
	SaveManager.settings.touch_controls_enabled = true
	SaveManager.settings.save_to_disk(SaveManager.SETTINGS_PATH)

	# 24.11 MapScene Centering on Selectable Path & Gamepad Scrolling
	SaveManager.start_new_run(555666)
	var map_test: MapScene = map_packed.instantiate() as MapScene
	add_child(map_test)
	await get_tree().process_frame

	assert(map_test._scroll != null, "MapScene must have a ScrollContainer")
	assert(map_test._selectable_buttons.size() >= 1, "MapScene must have at least 1 selectable button at start")
	assert(map_test._selectable_buttons[0].has_theme_stylebox_override("focus"), "Selectable map node button must have high-contrast focus stylebox")
	assert(map_test._selectable_buttons[0].has_focus(), "First selectable map node must automatically receive focus on map open")

	# Test right analog stick horizontal scroll
	var map_initial_scroll: int = map_test._scroll.scroll_horizontal
	var r_stick_map: InputEventJoypadMotion = InputEventJoypadMotion.new()
	r_stick_map.axis = JOY_AXIS_RIGHT_X
	r_stick_map.axis_value = 1.0
	map_test._unhandled_input(r_stick_map)
	assert(map_test._scroll.scroll_horizontal > map_initial_scroll, "Right analog stick right must scroll map to the right")

	# Test RB bumper page scroll
	var before_rb: int = map_test._scroll.scroll_horizontal
	var rb_map: InputEventJoypadButton = InputEventJoypadButton.new()
	rb_map.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb_map.pressed = true
	map_test._unhandled_input(rb_map)
	assert(map_test._scroll.scroll_horizontal > before_rb, "RB button must scroll map to the right")

	# Test [Y] button re-center on selectable path
	var y_map: InputEventJoypadButton = InputEventJoypadButton.new()
	y_map.button_index = JOY_BUTTON_Y
	y_map.pressed = true
	map_test._unhandled_input(y_map)
	assert(map_test._scroll.scroll_horizontal == map_initial_scroll or map_test._scroll_tween != null, "Y button must re-center on selectable path")

	# Test centering on a middle floor
	for n_map: Dictionary in SaveManager.map_graph:
		if int(n_map.get("floor", 0)) == 5:
			SaveManager.current_node_id = int(n_map.get("id", -1))
			SaveManager.current_floor = 5
			if not SaveManager.completed_node_ids.has(SaveManager.current_node_id):
				SaveManager.completed_node_ids.append(SaveManager.current_node_id)
			break
	map_test._populate_map_nodes()
	assert(map_test._scroll.scroll_horizontal > 0, "MapScene on floor 5/6 must be centered with scroll_horizontal > 0")

	map_test.queue_free()
	await get_tree().process_frame

	print("[24] Issue #45: Gamepad & Mobile Touch support in Dodge Box, Combat & Map verified OK")

	AudioManager.stop_music()
	await get_tree().process_frame
	SaveManager.delete_run_save()
	print("=== ALL SYSTEMS VERIFIED SUCCESSFULLY WITH 0 ERRORS ===")
	get_tree().quit(0)
