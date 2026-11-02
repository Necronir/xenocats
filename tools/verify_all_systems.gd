extends Node

func _ready() -> void:
	print("=== XENOCATS: BREMEN-4 AUTOMATED VERIFICATION ===")
	DataCatalog.ensure_loaded()
	if SaveManager.settings != null:
		SaveManager.settings.tutorials_enabled = false

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
		"res://src/event/event_scene.tscn",
		"res://src/core/video_player_scene.tscn"
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
		"res://assets/photos/1-cat-start.jpg",
		"res://assets/photos/2-cat-and-hound-together.jpg",
		"res://assets/photos/3-press-boss-appirance.jpg",
		"res://assets/photos/4a-press-boss-win.jpg",
		"res://assets/photos/4b-press-boss-fail.jpg",
		"res://assets/photos/5-atamansha-boss-apperiance.jpg",
		"res://assets/photos/6a-atamansha-boss-win.jpg",
		"res://assets/photos/6b-atamansha-boss-fail.jpg",
		"res://assets/photos/7-sputnik-boss-apperiance.jpg",
		"res://assets/photos/8a-sputnik-boss-win.jpg",
		"res://assets/photos/8b-sputnik-boss-fail.jpg",
		"res://assets/photos/9-final.jpg"
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
	(active_modals2[0] as TutorialOverlay).disable_tutorials_and_close()
	await get_tree().process_frame
	assert(not SaveManager.settings.tutorials_enabled, "Skip/Disable button must set tutorials_enabled = false")

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

	AudioManager.stop_music()
	await get_tree().process_frame
	SaveManager.delete_run_save()
	print("=== ALL SYSTEMS VERIFIED SUCCESSFULLY WITH 0 ERRORS ===")
	get_tree().quit(0)
