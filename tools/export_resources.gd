extends SceneTree

func _init() -> void:
	DataCatalog.ensure_loaded()

	# Save all skills as .tres and bind canonical resource_path for ExtResource linking
	var skill_keys: Array = DataCatalog._skills.keys()
	for i: int in range(skill_keys.size()):
		var sid: String = String(skill_keys[i])
		var sk: SkillData = DataCatalog._skills[skill_keys[i]] as SkillData
		if sk != null:
			var sk_path: String = "res://data/resources/skills/" + sid + ".tres"
			sk.take_over_path(sk_path)
			ResourceSaver.save(sk, sk_path)

	# Save all parts as .tres and bind canonical resource_path for ExtResource linking
	var part_keys: Array = DataCatalog._parts.keys()
	for i: int in range(part_keys.size()):
		var pid: String = String(part_keys[i])
		var pt: PartData = DataCatalog._parts[part_keys[i]] as PartData
		if pt != null:
			var pt_path: String = "res://data/resources/parts/" + pid + ".tres"
			pt.take_over_path(pt_path)
			ResourceSaver.save(pt, pt_path)

	# Save all enemies as .tres
	var enemy_keys: Array = DataCatalog._enemies.keys()
	for i: int in range(enemy_keys.size()):
		var eid: String = String(enemy_keys[i])
		var en: EnemyData = DataCatalog._enemies[enemy_keys[i]] as EnemyData
		if en != null:
			var en_path: String = "res://data/resources/enemies/" + eid + ".tres"
			en.take_over_path(en_path)
			ResourceSaver.save(en, en_path)

	# Save all music tapes as .tres
	var tape_keys: Array = DataCatalog._tapes.keys()
	for i: int in range(tape_keys.size()):
		var tid: String = String(tape_keys[i])
		var tp: MusicTapeData = DataCatalog._tapes[tape_keys[i]] as MusicTapeData
		if tp != null:
			var tp_path: String = "res://data/resources/music_tapes/" + tid + ".tres"
			tp.take_over_path(tp_path)
			ResourceSaver.save(tp, tp_path)

	# Save all tutorials as .tres
	var tut_keys: Array = DataCatalog._tutorials.keys()
	for i: int in range(tut_keys.size()):
		var tut_id: String = String(tut_keys[i])
		var td: TutorialData = DataCatalog._tutorials[tut_keys[i]] as TutorialData
		if td != null:
			var td_path: String = "res://data/resources/tutorials/" + tut_id + ".tres"
			td.take_over_path(td_path)
			ResourceSaver.save(td, td_path)

	print("Successfully exported all .tres resources to res://data/resources/!")
	quit(0)

