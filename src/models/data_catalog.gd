class_name DataCatalog
extends RefCounted

static var _skills: Dictionary = {}
static var _parts: Dictionary = {}
static var _enemies: Dictionary = {}
static var _cats: Dictionary = {}
static var _tapes: Dictionary = {}
static var _initialized: bool = false

static func ensure_loaded() -> void:
	if _initialized:
		return
	_initialized = true
	_load_dir_resources("res://data/resources/skills", _skills, "skill_id")
	_load_dir_resources("res://data/resources/parts", _parts, "part_id")
	_load_dir_resources("res://data/resources/enemies", _enemies, "enemy_id")
	_load_dir_resources("res://data/resources/music_tapes", _tapes, "tape_id")
	_build_default_catalog_if_needed()

static func _load_dir_resources(dir_path: String, target_dict: Dictionary, id_prop: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var clean_name: String = file_name.trim_suffix(".remap")
			if clean_name.ends_with(".tres"):
				var res: Resource = ResourceLoader.load(dir_path + "/" + clean_name)
				if res != null:
					var id_val: Variant = res.get(id_prop)
					if id_val != null and String(id_val) != "":
						target_dict[String(id_val)] = res
		file_name = dir.get_next()
	dir.list_dir_end()

static func get_skill(skill_id: String) -> SkillData:
	ensure_loaded()
	return _skills.get(skill_id, null) as SkillData

static func get_part(part_id: String) -> PartData:
	ensure_loaded()
	return _parts.get(part_id, null) as PartData

static func get_all_parts() -> Dictionary:
	ensure_loaded()
	return _parts

static func get_loot_parts() -> Array[PartData]:
	ensure_loaded()
	var arr: Array[PartData] = []
	for key: Variant in _parts.keys():
		var p: PartData = _parts[key] as PartData
		if p != null:
			arr.append(p)
	return arr

static func get_enemy(enemy_id: String) -> EnemyData:
	ensure_loaded()
	return _enemies.get(enemy_id, null) as EnemyData

static func get_enemies_for_sector(sector: int, is_elite: bool, is_boss: bool) -> Array[EnemyData]:
	ensure_loaded()
	var list: Array[EnemyData] = []
	for key: Variant in _enemies.keys():
		var e: EnemyData = _enemies[key] as EnemyData
		if e == null:
			continue
		if e.sector_level == sector and e.is_elite == is_elite and e.is_boss == is_boss:
			list.append(e)
	if list.is_empty():
		for key2: Variant in _enemies.keys():
			var e2: EnemyData = _enemies[key2] as EnemyData
			if e2 != null and e2.is_boss == is_boss and e2.is_elite == is_elite:
				list.append(e2)
	return list

static func get_tape(tape_id: String) -> MusicTapeData:
	ensure_loaded()
	return _tapes.get(tape_id, null) as MusicTapeData

static func get_all_tapes() -> Array[MusicTapeData]:
	ensure_loaded()
	var res: Array[MusicTapeData] = []
	for k: Variant in _tapes.keys():
		var t: MusicTapeData = _tapes[k] as MusicTapeData
		if t != null:
			res.append(t)
	return res

static func clear_cache() -> void:
	_skills.clear()
	_parts.clear()
	_enemies.clear()
	_cats.clear()
	_tapes.clear()
	_initialized = false

static func create_default_party() -> Array[CatMechInstance]:
	ensure_loaded()
	var party: Array[CatMechInstance] = []
	for cid: String in ["FELIX", "MULE", "HOUND", "COCK"]:
		var cdata: CatMechData = _cats.get(cid, null) as CatMechData
		if cdata != null:
			party.append(CatMechInstance.new(cdata))
	return party

static func _make_skill(
	p_id: String,
	p_name: String,
	p_desc: String,
	p_target: SkillData.TargetType,
	p_dmg: int,
	p_qte: SkillData.QTEProfile,
	p_status: SkillData.StatusEffect = SkillData.StatusEffect.NONE,
	p_stacks: int = 0,
	p_shield: int = 0,
	p_heal: int = 0,
	p_sync: int = 15,
	p_ignore_armor: bool = false
) -> SkillData:
	if _skills.has(p_id):
		return _skills[p_id] as SkillData
	var s: SkillData = SkillData.new()
	s.skill_id = StringName(p_id)
	s.skill_name = p_name
	s.description = p_desc
	s.target_type = p_target
	s.base_damage = p_dmg
	s.qte_profile = p_qte
	s.status_effect = p_status
	s.status_stacks = p_stacks
	s.shield_amount = p_shield
	s.heal_amount = p_heal
	s.sync_gain = p_sync
	s.ignore_armor = p_ignore_armor
	_skills[p_id] = s
	return s

static func _make_part(
	p_id: String,
	p_name: String,
	p_desc: String,
	p_slot: PartData.PartSlot,
	p_hp: int,
	p_armor: int,
	p_speed: int,
	p_tex: String,
	p_skills: Array[SkillData]
) -> PartData:
	if _parts.has(p_id):
		return _parts[p_id] as PartData
	var p: PartData = PartData.new()
	p.part_id = StringName(p_id)
	p.part_name = p_name
	p.description = p_desc
	p.slot = p_slot
	p.max_hp = p_hp
	p.armor = p_armor
	p.base_speed = p_speed
	p.texture_path = p_tex
	p.skills = p_skills
	_parts[p_id] = p
	return p

static func _build_default_catalog_if_needed() -> void:
	# Навыки котов
	var sk_laser_claws: SkillData = _make_skill(
		"felix_laser_claws", "Лазерные когти", "Быстрый порез по детали врага. Вешает Метку (Mark) для комбо.",
		SkillData.TargetType.SINGLE_PART, 18, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.MARK, 1, 0, 0, 20
	)
	var sk_battery_grenade: SkillData = _make_skill(
		"felix_battery_grenade", "Граната из батареек", "Взрыв по всем врагам в секторе.",
		SkillData.TargetType.ALL_ENEMIES, 13, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.NONE, 0, 0, 0, 20
	)
	var sk_overdrive_step: SkillData = _make_skill(
		"felix_overdrive", "Форсаж сервоприводов", "Ускоряет всю партию (+Скорость на 2 хода).",
		SkillData.TargetType.ALL_ALLIES, 0, SkillData.QTEProfile.NONE, SkillData.StatusEffect.SPEED_UP, 2, 0, 0, 15
	)

	var sk_bucket_bash: SkillData = _make_skill(
		"mule_bucket_bash", "Удар ковшом", "Тяжелый удар щитом-отвалом и Провокация (Taunt) на 2 хода.",
		SkillData.TargetType.SINGLE_PART, 15, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.TAUNT, 2, 10, 0, 20
	)
	var sk_heat_shield: SkillData = _make_skill(
		"mule_heat_shield", "Экран перегрева", "Раздаёт всей группе силовые щиты (+14 Щит).",
		SkillData.TargetType.ALL_ALLIES, 0, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.SHIELD, 1, 14, 0, 20
	)

	var sk_saw_bite: SkillData = _make_skill(
		"hound_saw_bite", "Пилообразный укус", "Разрывает обшивку детали, вызывая Утечку масла (Bleed).",
		SkillData.TargetType.SINGLE_PART, 22, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.BLEED, 3, 0, 0, 20
	)
	var sk_pack_vengeance: SkillData = _make_skill(
		"hound_vengeance", "Ярость стаи", "Сокрушительный удар, пробивающий броню цели.",
		SkillData.TargetType.SINGLE_PART, 26, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.NONE, 0, 0, 0, 25, true
	)

	var sk_sonic_wave: SkillData = _make_skill(
		"cock_sonic_wave", "Акустический залп", "Удар звуковой волной, шанс оглушить врага (Stun).",
		SkillData.TargetType.SINGLE_PART, 16, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.STUN, 1, 0, 0, 22
	)
	var sk_dawn_howl: SkillData = _make_skill(
		"cock_dawn_howl", "Рассветный вой", "Снимает все дебаффы с отряда и чинит корпуса (+12 HP).",
		SkillData.TargetType.ALL_ALLIES, 0, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.CLEANSE, 1, 0, 12, 20
	)

	# Лут-навыки
	var sk_rail_shot: SkillData = _make_skill(
		"titan_rail_shot", "Рельсотронный прострел", "Сверхмощный выстрел сквозь броню.",
		SkillData.TargetType.SINGLE_PART, 30, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.NONE, 0, 0, 0, 25, true
	)
	var sk_scrap_flamer: SkillData = _make_skill(
		"scrap_flamer", "Шлаковый огнемёт", "Обжигает всех врагов раскалённым шлаком и вызывает утечку.",
		SkillData.TargetType.ALL_ENEMIES, 16, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.BLEED, 2, 0, 0, 20
	)

	# Ультимейты Пирамиды Бремена
	_make_skill(
		"pyramid_acoustic_storm", "УЛЬТА: Акустический шторм",
		"AoE-контузия всех врагов сигналом тревоги максимальной громкости + Оглушение!",
		SkillData.TargetType.ALL_ENEMIES, 48, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.STUN, 1, 0, 0, 0, true
	)
	_make_skill(
		"pyramid_cascade_overload", "УЛЬТА: Каскадный перегруз",
		"Точечный сокрушительный залп всеми орудиями 4 котов в цель, игнорирующий броню и щиты!",
		SkillData.TargetType.SINGLE_PART, 85, SkillData.QTEProfile.TIMING_BAR, SkillData.StatusEffect.MARK, 2, 0, 0, 0, true
	)

	# Детали 4 котов
	var felix_body: PartData = _make_part(
		"felix_body", "Сервисное ядро FELIX", "Лёгкий корпус сервисного кота-лидера.",
		PartData.PartSlot.BODY, 65, 2, 16, "res://assets/sprites/cats/felix_body.png", [sk_battery_grenade]
	)
	var felix_arms: PartData = _make_part(
		"felix_arms", "Лазерные когти Мк-1", "Высокочастотные резаки с целеуказателем.",
		PartData.PartSlot.ARMS, 50, 1, 16, "res://assets/sprites/cats/felix_arms.png", [sk_laser_claws]
	)
	var felix_legs: PartData = _make_part(
		"felix_legs", "Пружинные лапы Рысь", "Максимальная инициатива и скорость в боксе уворота.",
		PartData.PartSlot.LEGS, 50, 1, 18, "res://assets/sprites/cats/felix_legs.png", [sk_overdrive_step]
	)

	var mule_body: PartData = _make_part(
		"mule_body", "Каркас Погрузчика M.U.L.E.", "Тяжёлый бронированный корпус с генератором щитов.",
		PartData.PartSlot.BODY, 95, 4, 9, "res://assets/sprites/cats/mule_body.png", [sk_heat_shield]
	)
	var mule_arms: PartData = _make_part(
		"mule_arms", "Ковш-отвал Титан", "Привлекает огонь врагов на себя и даёт персональный щит.",
		PartData.PartSlot.ARMS, 75, 4, 9, "res://assets/sprites/cats/mule_arms.png", [sk_bucket_bash]
	)
	var mule_legs: PartData = _make_part(
		"mule_legs", "Гусеничное шасси", "Медленные, но почти неуязвимые гусеницы.",
		PartData.PartSlot.LEGS, 80, 4, 9, "res://assets/sprites/cats/mule_legs.png", []
	)

	var hound_body: PartData = _make_part(
		"hound_body", "Патрульный блок H.O.U.N.D.", "Охранный корпус с форсированным гидравлическим приводом.",
		PartData.PartSlot.BODY, 80, 3, 13, "res://assets/sprites/cats/hound_body.png", [sk_pack_vengeance]
	)
	var hound_arms: PartData = _make_part(
		"hound_arms", "Пилообразные челюсти", "Цепные пилы, оставляющие глубокие пробоины.",
		PartData.PartSlot.ARMS, 65, 2, 13, "res://assets/sprites/cats/hound_arms.png", [sk_saw_bite]
	)
	var hound_legs: PartData = _make_part(
		"hound_legs", "Лапы Перехватчика", "Сбалансированное шасси патрульного дроида.",
		PartData.PartSlot.LEGS, 60, 2, 13, "res://assets/sprites/cats/hound_legs.png", []
	)

	var cock_body: PartData = _make_part(
		"cock_body", "РЭБ-ядро C.O.C.K.", "Модуль радиоэлектронной борьбы и регенерации.",
		PartData.PartSlot.BODY, 60, 2, 15, "res://assets/sprites/cats/cock_body.png", [sk_dawn_howl]
	)
	var cock_arms: PartData = _make_part(
		"cock_arms", "Акустический мегафон", "Генератор направленных звуковых ударных волн.",
		PartData.PartSlot.ARMS, 50, 1, 15, "res://assets/sprites/cats/cock_arms.png", [sk_sonic_wave]
	)
	var cock_legs: PartData = _make_part(
		"cock_legs", "Магнитные катушки", "Левитирующее шасси высокой манёвренности.",
		PartData.PartSlot.LEGS, 50, 2, 15, "res://assets/sprites/cats/cock_legs.png", []
	)

	# Редкие лут-детали для дропа и мастерской
	_make_part(
		"titan_body", "Корпус «Эгида-Прайм»", "Военный корпус с повышенным запасом прочности.",
		PartData.PartSlot.BODY, 110, 5, 12, "res://assets/sprites/cats/titan_body.png", [sk_heat_shield]
	)
	_make_part(
		"titan_arms", "Рельсотрон «Авангард»", "Экспериментальное орудие дальней пробивной стрельбы.",
		PartData.PartSlot.ARMS, 70, 3, 12, "res://assets/sprites/cats/titan_arms.png", [sk_rail_shot]
	)
	_make_part(
		"titan_legs", "Турбо-траки «Бастион»", "Укреплённые гусеницы с реактивным ускорителем.",
		PartData.PartSlot.LEGS, 85, 4, 15, "res://assets/sprites/cats/titan_legs.png", [sk_overdrive_step]
	)
	_make_part(
		"scrap_arms", "Шлаковый Огнемёт", "Кустарный распылитель перегретого металла.",
		PartData.PartSlot.ARMS, 65, 2, 12, "res://assets/sprites/cats/scrap_arms.png", [sk_scrap_flamer]
	)

	# Профили 4 котов
	var c_felix: CatMechData = CatMechData.new()
	c_felix.cat_id = &"FELIX"
	c_felix.display_name = "FELIX"
	c_felix.role_title = "Ловкач / Комбо-лидер"
	c_felix.portrait_prefix = "felix"
	c_felix.default_body = felix_body
	c_felix.default_arms = felix_arms
	c_felix.default_legs = felix_legs
	_cats["FELIX"] = c_felix

	var c_mule: CatMechData = CatMechData.new()
	c_mule.cat_id = &"MULE"
	c_mule.display_name = "M.U.L.E."
	c_mule.role_title = "Тяжёлый танк / Щиты"
	c_mule.portrait_prefix = "mule"
	c_mule.default_body = mule_body
	c_mule.default_arms = mule_arms
	c_mule.default_legs = mule_legs
	_cats["MULE"] = c_mule

	var c_hound: CatMechData = CatMechData.new()
	c_hound.cat_id = &"HOUND"
	c_hound.display_name = "H.O.U.N.D."
	c_hound.role_title = "Брузер / Утечка масла"
	c_hound.portrait_prefix = "hound"
	c_hound.default_body = hound_body
	c_hound.default_arms = hound_arms
	c_hound.default_legs = hound_legs
	_cats["HOUND"] = c_hound

	var c_cock: CatMechData = CatMechData.new()
	c_cock.cat_id = &"COCK"
	c_cock.display_name = "C.O.C.K."
	c_cock.role_title = "РЭБ-маг / Саппорт"
	c_cock.portrait_prefix = "cock"
	c_cock.default_body = cock_body
	c_cock.default_arms = cock_arms
	c_cock.default_legs = cock_legs
	_cats["COCK"] = c_cock

	# Вражеские навыки
	var esk_saw: SkillData = _make_skill(
		"enemy_saw_slash", "Циркулярный рез", "Враг запускает дисковые пилы по арене.",
		SkillData.TargetType.SINGLE_ENEMY, 14, SkillData.QTEProfile.NONE
	)
	var esk_acid: SkillData = _make_skill(
		"enemy_acid_spray", "Кислотный душ", "Дождь едких капель сверху по манипуляторам.",
		SkillData.TargetType.SINGLE_ENEMY, 15, SkillData.QTEProfile.NONE, SkillData.StatusEffect.BLEED, 2
	)
	var esk_press: SkillData = _make_skill(
		"enemy_heavy_press", "Гидравлический пресс", "Огромные прессы обрушиваются сверху и сбоку!",
		SkillData.TargetType.ALL_ENEMIES, 18, SkillData.QTEProfile.NONE
	)
	var esk_laser: SkillData = _make_skill(
		"enemy_laser_barrage", "Лазерная засечка", "Прицельный обстрел высокоточными лучами.",
		SkillData.TargetType.SINGLE_ENEMY, 20, SkillData.QTEProfile.NONE
	)

	# Обычные мобы (единая шкала HP: is_modular = false)
	_register_regular_enemy("scrap_drone", "Дрон-уборщик", 1, 52, 1, 11, "scrap_drone", "saw_sweep", [esk_saw], 22)
	_register_regular_enemy("acid_cleaner", "Кислотный чистильщик", 1, 58, 1, 10, "acid_cleaner", "acid_rain", [esk_acid], 25)
	_register_regular_enemy("welder_raider", "Сварщик-мародёр", 2, 72, 2, 13, "welder_raider", "laser_grid", [esk_laser], 32)
	_register_regular_enemy("security_hound", "Охранная гончая", 2, 78, 2, 15, "security_hound", "saw_sweep", [esk_saw], 35)
	_register_regular_enemy("spectre_drone", "Спектр-перехватчик", 3, 90, 3, 16, "spectre_drone", "laser_grid", [esk_laser], 45)
	_register_regular_enemy("core_sentinel", "Часовой ядра", 3, 105, 4, 12, "core_sentinel", "press_crush", [esk_press], 50)

	# Элитки и Боссы (Модульные: is_modular = true, 3 разрушаемые детали!)
	_register_modular_enemy(
		"elite_crusher", "ЭЛИТА: Погрузчик-Крушитель", 1, true, false, "elite_crusher", "press_crush",
		110, 75, 70, 3, 11, [esk_press], [esk_saw], 55, 1
	)
	_register_modular_enemy(
		"elite_driller", "ЭЛИТА: Штурмовой Бурильщик", 2, true, false, "elite_driller", "saw_sweep",
		135, 85, 80, 4, 13, [esk_saw], [esk_laser], 70, 1
	)
	_register_modular_enemy(
		"elite_aegis", "ЭЛИТА: Эгида-Дроид", 3, true, false, "elite_aegis", "laser_grid",
		160, 95, 90, 5, 14, [esk_laser], [esk_press], 90, 2
	)

	# 3 Босса секторов
	_register_modular_enemy(
		"boss_press", "БОСС: Трёхголовый Пресс", 1, false, true, "boss_press", "press_crush",
		180, 110, 95, 3, 12, [esk_press], [esk_saw, esk_acid], 100, 2
	)
	_register_modular_enemy(
		"boss_atamansha", "БОСС: Атаманша (Кран-Шагатель)", 2, false, true, "boss_atamansha", "laser_grid",
		230, 130, 115, 4, 14, [esk_laser, esk_press], [esk_saw], 140, 3
	)
	_register_modular_enemy(
		"boss_satellite", "ФИНАЛ: Спящий Спутник Бремен-4", 3, false, true, "boss_satellite", "laser_grid",
		290, 160, 140, 5, 16, [esk_laser, esk_press], [esk_acid, esk_laser], 220, 5
	)

	# Музыкальные кассеты
	_register_tape(
		"tape_hardbass", "Кассета: Bremen Hardbass FM",
		"Боевой ритм свалки: +20% к скорости набора шкалы Гармонии (Пирамиды).",
		"res://assets/audio/tapes/tape_hardbass.wav", &"SYNC_BOOST", 20
	)
	_register_tape(
		"tape_blues", "Кассета: Rust & Hydraulic Blues",
		"Тяжёлый блюз механиков: +2 к броне всех деталей отряда.",
		"res://assets/audio/tapes/tape_blues.wav", &"ARMOR_AURA", 2
	)
	_register_tape(
		"tape_synth", "Кассета: Overclock Synth 2084",
		"Синтвейв перегрузки: +4 к базовой скорости ног и инициативе.",
		"res://assets/audio/tapes/tape_synth.wav", &"SPEED_AURA", 4
	)

static func _register_regular_enemy(
	p_id: String, p_name: String, p_sec: int, p_hp: int, p_armor: int, p_spd: int,
	p_sprite: String, p_dodge: String, p_skills: Array[SkillData], p_scrap: int
) -> void:
	if _enemies.has(p_id):
		return
	var e: EnemyData = EnemyData.new()
	e.enemy_id = StringName(p_id)
	e.enemy_name = p_name
	e.is_modular = false
	e.is_elite = false
	e.is_boss = false
	e.sector_level = p_sec
	e.max_hp = p_hp
	e.armor = p_armor
	e.speed = p_spd
	e.sprite_prefix = p_sprite
	e.dodge_pattern_id = StringName(p_dodge)
	e.skills = p_skills
	e.scrap_reward = p_scrap
	e.core_reward = 0
	_enemies[p_id] = e

static func _register_modular_enemy(
	p_id: String, p_name: String, p_sec: int, p_elite: bool, p_boss: bool,
	p_sprite: String, p_dodge: String, p_bhp: int, p_ahp: int, p_lhp: int,
	p_armor: int, p_spd: int, p_arm_skills: Array[SkillData], p_body_skills: Array[SkillData],
	p_scrap: int, p_cores: int
) -> void:
	if _enemies.has(p_id):
		return
	var bp: PartData = _make_part(
		p_id + "_body", "Ядро (" + p_name + ")", "Центральный процессор и реактор.",
		PartData.PartSlot.BODY, p_bhp, p_armor, p_spd,
		"res://assets/sprites/enemies/" + p_sprite + "_body.png", p_body_skills
	)
	var ap: PartData = _make_part(
		p_id + "_arms", "Орудия (" + p_name + ")", "Боевой блок вооружения (отстрелите, чтобы ослабить атаки!).",
		PartData.PartSlot.ARMS, p_ahp, maxi(1, p_armor - 1), p_spd,
		"res://assets/sprites/enemies/" + p_sprite + "_arms.png", p_arm_skills
	)
	var lp: PartData = _make_part(
		p_id + "_legs", "Шасси (" + p_name + ")", "Ходовая часть (отстрелите, чтобы обрушить инициативу врага!).",
		PartData.PartSlot.LEGS, p_lhp, maxi(1, p_armor - 1), p_spd,
		"res://assets/sprites/enemies/" + p_sprite + "_legs.png", []
	)
	var e: EnemyData = EnemyData.new()
	e.enemy_id = StringName(p_id)
	e.enemy_name = p_name
	e.is_modular = true
	e.is_elite = p_elite
	e.is_boss = p_boss
	e.sector_level = p_sec
	e.max_hp = p_bhp
	e.armor = p_armor
	e.speed = p_spd
	e.body_part = bp
	e.arms_part = ap
	e.legs_part = lp
	e.sprite_prefix = p_sprite
	e.dodge_pattern_id = StringName(p_dodge)
	e.skills = p_body_skills
	e.scrap_reward = p_scrap
	e.core_reward = p_cores
	_enemies[p_id] = e

static func _register_tape(
	p_id: String, p_name: String, p_desc: String, p_path: String, p_aura: StringName, p_val: int
) -> void:
	if _tapes.has(p_id):
		return
	var t: MusicTapeData = MusicTapeData.new()
	t.tape_id = StringName(p_id)
	t.tape_name = p_name
	t.description = p_desc
	t.track_path = p_path
	t.passive_aura_type = p_aura
	t.passive_aura_value = p_val
	_tapes[p_id] = t
