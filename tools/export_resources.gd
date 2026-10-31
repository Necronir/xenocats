extends SceneTree

func _init() -> void:
	DataCatalog.ensure_loaded()

	# Save all skills as .tres
	for sid: Variant in DataCatalog._skills.keys():
		var sk: SkillData = DataCatalog._skills[sid] as SkillData
		if sk != null:
			ResourceSaver.save(sk, "res://data/resources/skills/" + String(sid) + ".tres")

	# Save all parts as .tres
	for pid: Variant in DataCatalog._parts.keys():
		var pt: PartData = DataCatalog._parts[pid] as PartData
		if pt != null:
			ResourceSaver.save(pt, "res://data/resources/parts/" + String(pid) + ".tres")

	# Save all enemies as .tres
	for eid: Variant in DataCatalog._enemies.keys():
		var en: EnemyData = DataCatalog._enemies[eid] as EnemyData
		if en != null:
			ResourceSaver.save(en, "res://data/resources/enemies/" + String(eid) + ".tres")

	# Save all music tapes as .tres
	for tid: Variant in DataCatalog._tapes.keys():
		var tp: MusicTapeData = DataCatalog._tapes[tid] as MusicTapeData
		if tp != null:
			ResourceSaver.save(tp, "res://data/resources/music_tapes/" + String(tid) + ".tres")

	# Save all tutorials as .tres
	for tut_id: Variant in DataCatalog._tutorials.keys():
		var td: TutorialData = DataCatalog._tutorials[tut_id] as TutorialData
		if td != null:
			ResourceSaver.save(td, "res://data/resources/tutorials/" + String(tut_id) + ".tres")

	print("Successfully exported all .tres resources to res://data/resources/!")
	quit(0)

