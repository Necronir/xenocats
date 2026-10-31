class_name CombatArena
extends Control

## CombatArena: Боевая сцена 4vX JRPG + QTE + Undertale Dodge Box + Пирамида Бремена (ADR-001 Section 2.4)

var _fsm: CombatFSM = null
var _qte: QTEController = null
var _dodge_arena: DodgeArena = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _party: Array[CatMechInstance] = []
var _enemies: Array[EnemyInstance] = []

# Очередь ходов: Array[Dictionary] -> {is_player: bool, index: int, score: int}
var _turn_queue: Array[Dictionary] = []
var _turn_cursor: int = 0
var _round_number: int = 1

# Выбранное действие игрока
var _active_cat_index: int = 0
var _selected_skill: SkillData = null
var _selected_enemy_index: int = 0
var _selected_part_slot: PartData.PartSlot = PartData.PartSlot.BODY
var _last_qte_mult: float = 1.0

# Выбранное действие врага
var _active_enemy_index: int = 0
var _enemy_skill: SkillData = null
var _defending_cat_index: int = 0

# Состояние режима «Пирамида Бремена»
var _pyramid_active: bool = false
var _pyramid_turns_left: int = 0

# Узлы сцены
var _bg_rect: TextureRect = null
var _cats_stage: Node2D = null
var _enemies_stage: Node2D = null
var _cat_rigs: Array[Dictionary] = []
var _pyramid_sprite: Sprite2D = null
var _enemy_rigs: Array[Dictionary] = []

# UI узлы
var _top_bar_label: Label = null
var _sync_bar: ProgressBar = null
var _log_label: Label = null
var _party_status_box: HBoxContainer = null
var _action_box: VBoxContainer = null
var _target_box: VBoxContainer = null
var _end_overlay: PanelContainer = null
var _end_title: Label = null
var _end_desc: Label = null
var _end_btn: Button = null

var _battle_payload: Dictionary = {}

func setup_battle(payload: Dictionary) -> void:
	_battle_payload = payload

func _ready() -> void:
	_rng.randomize()
	DataCatalog.ensure_loaded()

	_fsm = CombatFSM.new()
	add_child(_fsm)

	_build_visual_hierarchy()
	_init_combat_entities()
	_start_new_round()

func _build_visual_hierarchy() -> void:
	# 1. Фон сектора
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var sec: int = clampi(SaveManager.current_sector, 1, 3)
	var bg_path: String = "res://assets/sprites/backgrounds/bg_sector" + str(sec) + ".png"
	if ResourceLoader.exists(bg_path):
		_bg_rect.texture = load(bg_path) as Texture2D
	add_child(_bg_rect)

	# 2. 2D сцена для модульных спрайтов котов и врагов
	_cats_stage = Node2D.new()
	add_child(_cats_stage)

	_enemies_stage = Node2D.new()
	add_child(_enemies_stage)

	# 3. Верхняя информационная панель (Очередь ходов + Шкала Гармонии)
	var top_panel: PanelContainer = _make_styled_panel(Rect2(6, 4, 628, 28))
	add_child(top_panel)
	var top_hbox: HBoxContainer = HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	top_panel.add_child(top_hbox)

	_top_bar_label = Label.new()
	_top_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar_label.add_theme_font_size_override("font_size", 10)
	_top_bar_label.text = "РАУНД 1 | Инициализация боя..."
	top_hbox.add_child(_top_bar_label)

	var sync_lbl: Label = Label.new()
	sync_lbl.text = "ГАРМОНИЯ (ПИРАМИДА):"
	sync_lbl.add_theme_font_size_override("font_size", 9)
	sync_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	top_hbox.add_child(sync_lbl)

	_sync_bar = ProgressBar.new()
	_sync_bar.custom_minimum_size = Vector2(110, 16)
	_sync_bar.max_value = 100
	_sync_bar.value = SaveManager.sync_gauge
	_sync_bar.show_percentage = true
	top_hbox.add_child(_sync_bar)

	# 4. Лог боевых сообщений
	var log_panel: PanelContainer = _make_styled_panel(Rect2(6, 34, 628, 22))
	add_child(log_panel)
	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 10)
	_log_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.72))
	_log_label.text = "Боевая тревога! Отстреливайте детали элиток и боссов!"
	log_panel.add_child(_log_label)

	# 5. Нижняя панель HUD (Статус 4 котов слева + Меню действий и прицеливания справа)
	var bottom_panel: PanelContainer = _make_styled_panel(Rect2(6, 232, 628, 124))
	add_child(bottom_panel)
	var bottom_hbox: HBoxContainer = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 8)
	bottom_panel.add_child(bottom_hbox)

	_party_status_box = HBoxContainer.new()
	_party_status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_status_box.add_theme_constant_override("separation", 4)
	bottom_hbox.add_child(_party_status_box)

	var right_scroll: ScrollContainer = ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(265, 114)
	bottom_hbox.add_child(right_scroll)

	var menu_holder: VBoxContainer = VBoxContainer.new()
	menu_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(menu_holder)

	_action_box = VBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 2)
	menu_holder.add_child(_action_box)

	_target_box = VBoxContainer.new()
	_target_box.add_theme_constant_override("separation", 2)
	_target_box.visible = false
	menu_holder.add_child(_target_box)

	# 6. QTE контроллер (по центру арены)
	_qte = QTEController.new()
	_qte.position = Vector2(180, 110)
	_qte.qte_completed.connect(_on_qte_completed)
	add_child(_qte)

	# 7. Undertale Dodge Box (по центру арены)
	_dodge_arena = DodgeArena.new()
	_dodge_arena.position = Vector2(210, 66)
	_dodge_arena.part_hit.connect(_on_dodge_part_hit)
	_dodge_arena.dodge_finished.connect(_on_dodge_finished)
	add_child(_dodge_arena)

	# 8. Оверлей завершения боя (Победа / Поражение)
	_end_overlay = _make_styled_panel(Rect2(140, 76, 360, 170))
	_end_overlay.visible = false
	add_child(_end_overlay)
	var end_vbox: VBoxContainer = VBoxContainer.new()
	end_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	end_vbox.add_theme_constant_override("separation", 8)
	_end_overlay.add_child(end_vbox)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 14)
	end_vbox.add_child(_end_title)

	_end_desc = Label.new()
	_end_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_desc.add_theme_font_size_override("font_size", 10)
	end_vbox.add_child(_end_desc)

	_end_btn = Button.new()
	_end_btn.text = "ПРОДОЛЖИТЬ"
	_end_btn.add_theme_font_size_override("font_size", 11)
	end_vbox.add_child(_end_btn)

func _make_styled_panel(rect: Rect2) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	st.border_color = Color(0.28, 0.55, 0.75, 0.95)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(4)
	p.add_theme_stylebox_override("panel", st)
	return p

func _init_combat_entities() -> void:
	_fsm.transition_to(CombatFSM.State.BATTLE_INIT)
	if SaveManager.party.is_empty():
		SaveManager.start_new_run()
	_party = SaveManager.party
	for cat: CatMechInstance in _party:
		cat.reset_combat_statuses()

	# Определяем состав врагов по типу ноды
	_enemies.clear()
	var node_type: String = String(_battle_payload.get("node_type", "COMBAT"))
	var sec: int = clampi(SaveManager.current_sector, 1, 3)

	if node_type == "BOSS":
		var bosses: Array[EnemyData] = DataCatalog.get_enemies_for_sector(sec, false, true)
		if not bosses.is_empty():
			_enemies.append(EnemyInstance.new(bosses[0]))
	elif node_type == "ELITE":
		var elites: Array[EnemyData] = DataCatalog.get_enemies_for_sector(sec, true, false)
		if not elites.is_empty():
			_enemies.append(EnemyInstance.new(elites[_rng.randi_range(0, elites.size() - 1)]))
		var regs: Array[EnemyData] = DataCatalog.get_enemies_for_sector(sec, false, false)
		if not regs.is_empty():
			_enemies.append(EnemyInstance.new(regs[_rng.randi_range(0, regs.size() - 1)]))
	else:
		var regular_pool: Array[EnemyData] = DataCatalog.get_enemies_for_sector(sec, false, false)
		var count: int = _rng.randi_range(2, 3)
		for i: int in range(count):
			if not regular_pool.is_empty():
				var ed: EnemyData = regular_pool[_rng.randi_range(0, regular_pool.size() - 1)]
				_enemies.append(EnemyInstance.new(ed))

	_spawn_cat_rigs()
	_spawn_enemy_rigs()
	_refresh_hud()

func _spawn_cat_rigs() -> void:
	for child: Node in _cats_stage.get_children():
		child.queue_free()
	_cat_rigs.clear()

	var positions: Array[Vector2] = [
		Vector2(62, 118),
		Vector2(138, 134),
		Vector2(74, 186),
		Vector2(152, 196)
	]

	for i: int in range(_party.size()):
		var cat: CatMechInstance = _party[i]
		var root: Node2D = Node2D.new()
		root.position = positions[i % positions.size()]
		_cats_stage.add_child(root)

		# Модульная сборка спрайтов через Marker2D (ADR-001 Section 4)
		var legs_mount: Marker2D = Marker2D.new()
		legs_mount.position = Vector2(0, 12)
		root.add_child(legs_mount)
		var legs_spr: Sprite2D = Sprite2D.new()
		if cat.legs_part != null and cat.legs_part.data != null and ResourceLoader.exists(cat.legs_part.data.texture_path):
			legs_spr.texture = load(cat.legs_part.data.texture_path) as Texture2D
		legs_mount.add_child(legs_spr)

		var body_mount: Marker2D = Marker2D.new()
		body_mount.position = Vector2(0, -4)
		root.add_child(body_mount)
		var body_spr: Sprite2D = Sprite2D.new()
		if cat.body_part != null and cat.body_part.data != null and ResourceLoader.exists(cat.body_part.data.texture_path):
			body_spr.texture = load(cat.body_part.data.texture_path) as Texture2D
		body_mount.add_child(body_spr)

		var arms_mount: Marker2D = Marker2D.new()
		arms_mount.position = Vector2(2, -2)
		root.add_child(arms_mount)
		var arms_spr: Sprite2D = Sprite2D.new()
		if cat.arms_part != null and cat.arms_part.data != null and ResourceLoader.exists(cat.arms_part.data.texture_path):
			arms_spr.texture = load(cat.arms_part.data.texture_path) as Texture2D
		arms_mount.add_child(arms_spr)

		var name_lbl: Label = Label.new()
		name_lbl.position = Vector2(-24, -32)
		name_lbl.text = cat.display_name
		name_lbl.add_theme_font_size_override("font_size", 8)
		root.add_child(name_lbl)

		_cat_rigs.append({
			"root": root,
			"body_spr": body_spr,
			"arms_spr": arms_spr,
			"legs_spr": legs_spr,
			"label": name_lbl
		})

	# Спрайт Пирамиды Бремена (скрыт по умолчанию)
	_pyramid_sprite = Sprite2D.new()
	_pyramid_sprite.position = Vector2(112, 148)
	_pyramid_sprite.texture = load("res://assets/sprites/cats/bremen_pyramid.png") as Texture2D
	_pyramid_sprite.visible = false
	_cats_stage.add_child(_pyramid_sprite)

func _spawn_enemy_rigs() -> void:
	for child: Node in _enemies_stage.get_children():
		child.queue_free()
	_enemy_rigs.clear()

	var positions: Array[Vector2] = [
		Vector2(455, 132),
		Vector2(548, 152),
		Vector2(485, 198)
	]

	for i: int in range(_enemies.size()):
		var en: EnemyInstance = _enemies[i]
		var root: Node2D = Node2D.new()
		root.position = positions[i % positions.size()]
		_enemies_stage.add_child(root)

		var body_spr: Sprite2D = Sprite2D.new()
		var arms_spr: Sprite2D = null
		var legs_spr: Sprite2D = null

		if en.is_modular():
			arms_spr = Sprite2D.new()
			legs_spr = Sprite2D.new()
			var pfx: String = "res://assets/sprites/enemies/" + en.data.sprite_prefix
			if ResourceLoader.exists(pfx + "_legs.png"):
				legs_spr.texture = load(pfx + "_legs.png") as Texture2D
			if ResourceLoader.exists(pfx + "_body.png"):
				body_spr.texture = load(pfx + "_body.png") as Texture2D
			if ResourceLoader.exists(pfx + "_arms.png"):
				arms_spr.texture = load(pfx + "_arms.png") as Texture2D
			root.add_child(legs_spr)
			root.add_child(body_spr)
			root.add_child(arms_spr)
		else:
			var sp_path: String = "res://assets/sprites/enemies/" + en.data.sprite_prefix + ".png"
			if ResourceLoader.exists(sp_path):
				body_spr.texture = load(sp_path) as Texture2D
			root.add_child(body_spr)

		var info_lbl: Label = Label.new()
		info_lbl.position = Vector2(-52, -48)
		info_lbl.add_theme_font_size_override("font_size", 8)
		root.add_child(info_lbl)

		_enemy_rigs.append({
			"root": root,
			"body_spr": body_spr,
			"arms_spr": arms_spr,
			"legs_spr": legs_spr,
			"label": info_lbl
		})

func _refresh_hud() -> void:
	_sync_bar.value = SaveManager.sync_gauge

	# Обновляем визуальное состояние модульных спрайтов котов
	for i: int in range(_party.size()):
		var cat: CatMechInstance = _party[i]
		var rig: Dictionary = _cat_rigs[i]
		var root: Node2D = rig["root"] as Node2D
		root.visible = (not _pyramid_active) and cat.is_alive()

		var b_spr: Sprite2D = rig["body_spr"] as Sprite2D
		var a_spr: Sprite2D = rig["arms_spr"] as Sprite2D
		var l_spr: Sprite2D = rig["legs_spr"] as Sprite2D
		b_spr.modulate = Color(0.35, 0.35, 0.35) if cat.body_part.is_broken() else Color(1, 1, 1)
		a_spr.modulate = Color(0.4, 0.2, 0.2, 0.65) if cat.arms_part.is_broken() else Color(1, 1, 1)
		l_spr.modulate = Color(0.4, 0.2, 0.2, 0.65) if cat.legs_part.is_broken() else Color(1, 1, 1)

	_pyramid_sprite.visible = _pyramid_active

	# Обновляем спрайты и подписи врагов
	for j: int in range(_enemies.size()):
		var en: EnemyInstance = _enemies[j]
		var erig: Dictionary = _enemy_rigs[j]
		var eroot: Node2D = erig["root"] as Node2D
		eroot.visible = en.is_alive()
		if not en.is_alive():
			continue

		var status_tags: String = ""
		if en.marked:
			status_tags += " [МЕТКА]"
		if en.bleed_stacks > 0:
			status_tags += " [МАСЛО:" + str(en.bleed_stacks) + "]"
		if en.stunned:
			status_tags += " [ОГЛУШ]"

		var elbl: Label = erig["label"] as Label
		if en.is_modular():
			var eb: PartInstance = en.body_part
			var ea: PartInstance = en.arms_part
			var el: PartInstance = en.legs_part
			elbl.text = (
				en.data.enemy_name + status_tags + "\n"
				+ "Корп:" + str(eb.current_hp) + "/" + str(eb.get_max_hp())
				+ " Оруд:" + str(ea.current_hp)
				+ " Шасси:" + str(el.current_hp)
			)
			(erig["arms_spr"] as Sprite2D).modulate = Color(0.35, 0.2, 0.2, 0.5) if ea.is_broken() else Color(1, 1, 1)
			(erig["legs_spr"] as Sprite2D).modulate = Color(0.35, 0.2, 0.2, 0.5) if el.is_broken() else Color(1, 1, 1)
		else:
			elbl.text = en.data.enemy_name + status_tags + "\nHP: " + str(en.current_hp) + "/" + str(en.data.max_hp)

	# Перестраиваем карточки статуса 4 котов внизу
	for child: Node in _party_status_box.get_children():
		child.queue_free()

	for idx: int in range(_party.size()):
		var c: CatMechInstance = _party[idx]
		var card: PanelContainer = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cst: StyleBoxFlat = StyleBoxFlat.new()
		var is_active_turn: bool = (
			_fsm.current_state == CombatFSM.State.PLAYER_SELECT_ACTION
			or _fsm.current_state == CombatFSM.State.PLAYER_SELECT_TARGET
		) and (_active_cat_index == idx)
		cst.bg_color = Color(0.11, 0.16, 0.24, 0.95) if is_active_turn else Color(0.07, 0.09, 0.14, 0.9)
		cst.border_color = Color(0.95, 0.85, 0.3, 1.0) if is_active_turn else Color(0.25, 0.35, 0.45, 0.8)
		cst.set_border_width_all(1)
		cst.set_content_margin_all(3)
		card.add_theme_stylebox_override("panel", cst)
		_party_status_box.add_child(card)

		var cv: VBoxContainer = VBoxContainer.new()
		cv.add_theme_constant_override("separation", 1)
		card.add_child(cv)

		var title_l: Label = Label.new()
		var st_str: String = ""
		if c.shield > 0:
			st_str += " [Щ:" + str(c.shield) + "]"
		if c.taunt_turns > 0:
			st_str += " [ТАНК]"
		if c.bleed_stacks > 0:
			st_str += " [МАСЛО]"
		title_l.text = c.display_name + st_str
		title_l.add_theme_font_size_override("font_size", 9)
		title_l.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0) if c.is_alive() else Color(0.6, 0.3, 0.3))
		cv.add_child(title_l)

		cv.add_child(_make_part_hp_row("Корп:", c.body_part, Color(0.3, 0.85, 0.95)))
		cv.add_child(_make_part_hp_row("Руки:", c.arms_part, Color(0.95, 0.65, 0.25)))
		cv.add_child(_make_part_hp_row("Ноги:", c.legs_part, Color(0.45, 0.9, 0.45)))

		var spd_l: Label = Label.new()
		spd_l.text = "Иниц: " + str(c.get_initiative_score()) + (" (НОГИ СЛОМ!)" if c.legs_part.is_broken() else "")
		spd_l.add_theme_font_size_override("font_size", 8)
		cv.add_child(spd_l)

func _make_part_hp_row(prefix: String, part: PartInstance, col: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", 8)
	if part == null:
		l.text = prefix + " -"
		return l
	if part.is_broken():
		l.text = prefix + " 0/" + str(part.get_max_hp()) + " [СЛОМ]"
		l.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	else:
		l.text = prefix + " " + str(part.current_hp) + "/" + str(part.get_max_hp()) + " (Бр:" + str(part.get_armor()) + ")"
		l.add_theme_color_override("font_color", col)
	return l

# --- Логика раундов и очереди инициативы (по Ногам) ---

func _start_new_round() -> void:
	_fsm.transition_to(CombatFSM.State.TURN_ORDER_CALC)
	_turn_queue.clear()
	_turn_cursor = 0

	if _pyramid_active:
		_pyramid_turns_left -= 1
		if _pyramid_turns_left <= 0:
			_pyramid_active = false
			EventBus.pyramid_deactivated.emit()
			_log_label.text = "Режим «Пирамида Бремена» завершён — коты расстыковались!"

	for i: int in range(_party.size()):
		var cat: CatMechInstance = _party[i]
		if cat.is_alive():
			if cat.taunt_turns > 0:
				cat.taunt_turns -= 1
			if cat.speed_buff_turns > 0:
				cat.speed_buff_turns -= 1
			_turn_queue.append({
				"is_player": true,
				"index": i,
				"score": cat.get_initiative_score()
			})

	for j: int in range(_enemies.size()):
		var en: EnemyInstance = _enemies[j]
		if en.is_alive():
			_turn_queue.append({
				"is_player": false,
				"index": j,
				"score": en.get_initiative_score()
			})

	# Сортировка по убыванию инициативы
	_turn_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"])
	)

	_update_turn_order_header()
	_advance_turn()

func _update_turn_order_header() -> void:
	var names: PackedStringArray = PackedStringArray()
	for k: int in range(_turn_cursor, _turn_queue.size()):
		var item: Dictionary = _turn_queue[k]
		if bool(item["is_player"]):
			var c: CatMechInstance = _party[int(item["index"])]
			if c.is_alive():
				names.append(c.display_name + "(" + str(item["score"]) + ")")
		else:
			var e: EnemyInstance = _enemies[int(item["index"])]
			if e.is_alive():
				names.append(e.data.enemy_name + "(" + str(item["score"]) + ")")
	_top_bar_label.text = "РАУНД " + str(_round_number) + " | Очередь: " + " -> ".join(names)

func _advance_turn() -> void:
	if _check_battle_end():
		return

	while _turn_cursor < _turn_queue.size():
		var entry: Dictionary = _turn_queue[_turn_cursor]
		_turn_cursor += 1
		var is_plr: bool = bool(entry["is_player"])
		var idx: int = int(entry["index"])

		if is_plr:
			var cat: CatMechInstance = _party[idx]
			if not cat.is_alive():
				continue
			if cat.bleed_stacks > 0:
				cat.apply_part_damage(PartData.PartSlot.BODY, cat.bleed_stacks * 2, true)
				cat.bleed_stacks = maxi(0, cat.bleed_stacks - 1)
				if not cat.is_alive():
					_refresh_hud()
					if _check_battle_end():
						return
					continue
			if cat.stunned:
				cat.stunned = false
				_log_label.text = cat.display_name + " перегружен (Оглушение) и пропускает ход!"
				_refresh_hud()
				await get_tree().create_timer(0.6).timeout
				continue
			_begin_player_turn(idx)
			return
		else:
			var en: EnemyInstance = _enemies[idx]
			if not en.is_alive():
				continue
			if en.bleed_stacks > 0:
				en.take_damage(en.bleed_stacks * 4, PartData.PartSlot.BODY, true)
				en.bleed_stacks = maxi(0, en.bleed_stacks - 1)
				_refresh_hud()
				if not en.is_alive():
					if _check_battle_end():
						return
					continue
			if en.stunned:
				en.stunned = false
				_log_label.text = en.data.enemy_name + " оглушён звуковой волной и пропускает ход!"
				_refresh_hud()
				await get_tree().create_timer(0.6).timeout
				continue
			_begin_enemy_turn(idx)
			return

	_round_number += 1
	_start_new_round()

# --- Ход игрока ---

func _begin_player_turn(cat_index: int) -> void:
	_active_cat_index = cat_index
	_fsm.transition_to(CombatFSM.State.PLAYER_SELECT_ACTION)
	_update_turn_order_header()
	_refresh_hud()

	_action_box.visible = true
	_target_box.visible = false
	for child: Node in _action_box.get_children():
		child.queue_free()

	var cat: CatMechInstance = _party[_active_cat_index]
	var header: Label = Label.new()
	header.text = (
		"ХОД ТОТЕМА «ПИРАМИДА БРЕМЕНА»:"
		if _pyramid_active
		else ("ХОД: " + cat.display_name + " (" + cat.role_title + ")")
	)
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.95, 0.88, 0.35))
	_action_box.add_child(header)

	# Кнопка активации Пирамиды Бремена при 100% Синхронизации
	if SaveManager.sync_gauge >= 100 and not _pyramid_active:
		var pyr_btn: Button = Button.new()
		pyr_btn.text = "★ СТЫКОВКА: ПИРАМИДА БРЕМЕНА! ★"
		pyr_btn.add_theme_font_size_override("font_size", 10)
		pyr_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		pyr_btn.pressed.connect(_activate_bremen_pyramid)
		_action_box.add_child(pyr_btn)

	var skills: Array[SkillData] = []
	if _pyramid_active:
		var u1: SkillData = DataCatalog.get_skill("pyramid_acoustic_storm")
		var u2: SkillData = DataCatalog.get_skill("pyramid_cascade_overload")
		if u1 != null:
			skills.append(u1)
		if u2 != null:
			skills.append(u2)
	else:
		skills = cat.get_available_skills()

	for sk: SkillData in skills:
		var btn: Button = Button.new()
		btn.text = sk.skill_name + " (" + (
			"Урон:" + str(sk.base_damage) if sk.base_damage > 0 else "Саппорт"
		) + ")"
		btn.tooltip_text = sk.description
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_click")
			_on_skill_chosen(sk)
		)
		_action_box.add_child(btn)

func _activate_bremen_pyramid() -> void:
	SaveManager.sync_gauge = 0
	_pyramid_active = true
	_pyramid_turns_left = 1
	AudioManager.play_sfx("pyramid_siren")
	EventBus.pyramid_activated.emit()

	# Все 4 кота стыкуются: снимаются негативные статусы, выдается общий энергетический щит
	for cat: CatMechInstance in _party:
		if cat.is_alive():
			cat.clear_debuffs()
			cat.shield += 18

	_log_label.text = "СТЫКОВКА! Коты объединились в «Пирамиду Бремена»! Негативные статусы сняты!"
	_begin_player_turn(_active_cat_index)

func _on_skill_chosen(sk: SkillData) -> void:
	_selected_skill = sk
	if (
		sk.target_type == SkillData.TargetType.ALL_ENEMIES
		or sk.target_type == SkillData.TargetType.ALL_ALLIES
		or sk.target_type == SkillData.TargetType.SELF
	):
		_start_player_qte()
		return

	# Иначе выбираем цель и деталь (для модульных боссов/элиток)
	_fsm.transition_to(CombatFSM.State.PLAYER_SELECT_TARGET)
	_action_box.visible = false
	_target_box.visible = true
	for child: Node in _target_box.get_children():
		child.queue_free()

	var t_lbl: Label = Label.new()
	t_lbl.text = "ВЫБЕРИТЕ ЦЕЛЬ / ДЕТАЛЬ (" + sk.skill_name + "):"
	t_lbl.add_theme_font_size_override("font_size", 9)
	t_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
	_target_box.add_child(t_lbl)

	for e_idx: int in range(_enemies.size()):
		var en: EnemyInstance = _enemies[e_idx]
		if not en.is_alive():
			continue
		if en.is_modular():
			# 3 кнопки выбора конкретной детали у Элитки или Босса!
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 3)
			_target_box.add_child(row)

			for slot: PartData.PartSlot in [PartData.PartSlot.BODY, PartData.PartSlot.ARMS, PartData.PartSlot.LEGS]:
				var p: PartInstance = en.get_part(slot)
				var p_btn: Button = Button.new()
				p_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				p_btn.add_theme_font_size_override("font_size", 8)
				var s_name: String = PartData.slot_to_russian(slot)
				if p.is_broken() and slot != PartData.PartSlot.BODY:
					p_btn.text = s_name + " [ОТСТРЕЛЕНО]"
					p_btn.disabled = true
				else:
					p_btn.text = s_name + " (" + str(p.current_hp) + " HP)"
				p_btn.pressed.connect(func() -> void:
					AudioManager.play_sfx("ui_click")
					_selected_enemy_index = e_idx
					_selected_part_slot = slot
					_start_player_qte()
				)
				row.add_child(p_btn)
		else:
			var e_btn: Button = Button.new()
			e_btn.text = en.data.enemy_name + " (HP: " + str(en.current_hp) + "/" + str(en.data.max_hp) + ")"
			e_btn.add_theme_font_size_override("font_size", 9)
			e_btn.pressed.connect(func() -> void:
				AudioManager.play_sfx("ui_click")
				_selected_enemy_index = e_idx
				_selected_part_slot = PartData.PartSlot.BODY
				_start_player_qte()
			)
			_target_box.add_child(e_btn)

	var back_btn: Button = Button.new()
	back_btn.text = "<- Назад к навыкам"
	back_btn.add_theme_font_size_override("font_size", 9)
	back_btn.pressed.connect(func() -> void:
		_begin_player_turn(_active_cat_index)
	)
	_target_box.add_child(back_btn)

func _start_player_qte() -> void:
	_action_box.visible = false
	_target_box.visible = false
	if _selected_skill.qte_profile == SkillData.QTEProfile.NONE:
		_on_qte_completed(1.0, "АВТО", 5)
		return
	_fsm.transition_to(CombatFSM.State.QTE_ATTACK_PHASE)
	_qte.start_qte(_selected_skill.skill_name)

func _on_qte_completed(multiplier: float, rating_label: String, bonus_sync: int) -> void:
	_last_qte_mult = multiplier
	_fsm.transition_to(CombatFSM.State.RESOLVE_PLAYER_DAMAGE)

	var cat: CatMechInstance = _party[_active_cat_index]
	var sk: SkillData = _selected_skill
	SaveManager.add_sync(sk.sync_gain + bonus_sync)

	var scaled_dmg: int = int(round(float(sk.base_damage) * multiplier))
	var log_parts: PackedStringArray = PackedStringArray()
	log_parts.append(cat.display_name + " -> " + sk.skill_name + " [" + rating_label + "]")

	if sk.target_type == SkillData.TargetType.ALL_ALLIES or sk.target_type == SkillData.TargetType.SELF:
		AudioManager.play_sfx("heal")
		for ally: CatMechInstance in _party:
			if not ally.is_alive():
				continue
			if sk.shield_amount > 0:
				ally.shield += int(round(float(sk.shield_amount) * multiplier))
			if sk.heal_amount > 0:
				ally.body_part.repair(int(round(float(sk.heal_amount) * multiplier)))
			if sk.status_effect == SkillData.StatusEffect.CLEANSE:
				ally.clear_debuffs()
			elif sk.status_effect == SkillData.StatusEffect.SPEED_UP:
				ally.speed_buff_turns = maxi(ally.speed_buff_turns, sk.status_stacks)
		log_parts.append("Поддержка отряда выполнена!")
	elif sk.target_type == SkillData.TargetType.ALL_ENEMIES:
		AudioManager.play_sfx("laser")
		for e_idx: int in range(_enemies.size()):
			var en: EnemyInstance = _enemies[e_idx]
			if not en.is_alive():
				continue
			var res: Dictionary = en.take_damage(scaled_dmg, PartData.PartSlot.BODY, sk.ignore_armor)
			_apply_skill_status_to_enemy(en, sk, multiplier)
			log_parts.append(en.data.enemy_name + ": -" + str(res["damage"]) + " HP")
	else:
		AudioManager.play_sfx("laser")
		if sk.shield_amount > 0:
			cat.shield += sk.shield_amount
		if sk.status_effect == SkillData.StatusEffect.TAUNT:
			cat.taunt_turns = sk.status_stacks

		var target_en: EnemyInstance = _enemies[_selected_enemy_index]
		if not target_en.is_alive():
			for fallback_en: EnemyInstance in _enemies:
				if fallback_en.is_alive():
					target_en = fallback_en
					break
		if target_en != null and target_en.is_alive():
			var hit_res: Dictionary = target_en.take_damage(scaled_dmg, _selected_part_slot, sk.ignore_armor)
			_apply_skill_status_to_enemy(target_en, sk, multiplier)
			var slot_str: String = PartData.slot_to_russian(hit_res["slot"] as PartData.PartSlot)
			log_parts.append(target_en.data.enemy_name + " (" + slot_str + "): -" + str(hit_res["damage"]) + " HP")
			if bool(hit_res["triggered_mark"]):
				SaveManager.add_sync(15)
				log_parts.append("КОМБО ПО МЕТКЕ!")
			if bool(hit_res["just_broken"]) and target_en.is_modular():
				AudioManager.play_sfx("part_break")
				EventBus.enemy_part_destroyed.emit(_selected_enemy_index, int(hit_res["slot"]))
				log_parts.append("ДЕТАЛЬ [" + slot_str + "] ОТСТРЕЛЕНА!")

	_log_label.text = " | ".join(log_parts)
	_refresh_hud()
	await get_tree().create_timer(0.65).timeout
	_advance_turn()

func _apply_skill_status_to_enemy(en: EnemyInstance, sk: SkillData, mult: float) -> void:
	if not en.is_alive():
		return
	match sk.status_effect:
		SkillData.StatusEffect.MARK:
			en.marked = true
		SkillData.StatusEffect.BLEED:
			en.bleed_stacks += sk.status_stacks
		SkillData.StatusEffect.STUN:
			if mult >= 1.1 or _rng.randf() < 0.65:
				en.stunned = true

# --- Ход врага и мини-игра уворота DodgeArena ---

func _begin_enemy_turn(enemy_index: int) -> void:
	_active_enemy_index = enemy_index
	_fsm.transition_to(CombatFSM.State.ENEMY_AI_SELECT)
	_action_box.visible = false
	_target_box.visible = false
	_update_turn_order_header()

	var en: EnemyInstance = _enemies[enemy_index]
	_enemy_skill = en.choose_next_skill(_rng)
	_defending_cat_index = _pick_target_cat_index()
	var defender: CatMechInstance = _party[_defending_cat_index]

	_log_label.text = (
		en.data.enemy_name + " применяет «" + _enemy_skill.skill_name
		+ "» по " + defender.display_name + "! Уклоняйтесь в боксе!"
	)
	_refresh_hud()

	await get_tree().create_timer(0.55).timeout
	_fsm.transition_to(CombatFSM.State.SPAWN_DODGE_BOX)
	_fsm.transition_to(CombatFSM.State.DODGE_REALTIME_MINIGAME)

	_dodge_arena.start_dodge(
		defender.display_name,
		en.data.dodge_pattern_id,
		_enemy_skill.base_damage,
		defender.get_dodge_speed_multiplier(),
		3.5
	)

func _pick_target_cat_index() -> int:
	# Сначала проверяем котов с активной провокацией (Taunt)
	var taunt_indices: Array[int] = []
	var alive_indices: Array[int] = []
	for i: int in range(_party.size()):
		if _party[i].is_alive():
			alive_indices.append(i)
			if _party[i].taunt_turns > 0:
				taunt_indices.append(i)
	if not taunt_indices.is_empty():
		return taunt_indices[_rng.randi_range(0, taunt_indices.size() - 1)]
	if not alive_indices.is_empty():
		return alive_indices[_rng.randi_range(0, alive_indices.size() - 1)]
	return 0

func _on_dodge_part_hit(slot: PartData.PartSlot, raw_damage: int) -> void:
	var defender: CatMechInstance = _party[_defending_cat_index]
	if not defender.is_alive():
		_dodge_arena.call_deferred("force_finish")
		return
	var res: Dictionary = defender.apply_part_damage(slot, raw_damage, false)
	var actual_slot: PartData.PartSlot = int(res["slot"]) as PartData.PartSlot
	var dealt: int = int(res["damage"])
	var part_obj: PartInstance = defender.get_part(actual_slot)

	EventBus.cat_part_damaged.emit(defender.cat_id, int(actual_slot), dealt, part_obj.current_hp)
	var s_name: String = PartData.slot_to_russian(actual_slot)
	_log_label.text = "ПОПАДАНИЕ в [" + s_name + "] (" + defender.display_name + "): -" + str(dealt) + " HP!"

	if bool(res["just_broken"]):
		AudioManager.play_sfx("part_break")
		EventBus.cat_part_destroyed.emit(defender.cat_id, int(actual_slot))
		_log_label.text += " ДЕТАЛЬ [" + s_name + "] РАЗРУШЕНА!"

	_refresh_hud()

	# Если Корпус защищающегося кота выбит до 0 HP — немедленно завершаем обстрел!
	if not defender.is_alive():
		_log_label.text += " КОРПУС ВЫБИТ!"
		_dodge_arena.call_deferred("force_finish")

func _on_dodge_finished(total_hits: int) -> void:
	_fsm.transition_to(CombatFSM.State.RESOLVE_PART_DAMAGE)
	if total_hits == 0:
		SaveManager.add_sync(10)
		_log_label.text = "ИДЕАЛЬНОЕ УКЛОНЕНИЕ! Ни один снаряд не задел кота (+10 Гармонии)!"
	_refresh_hud()
	await get_tree().create_timer(0.45).timeout
	_advance_turn()

# --- Проверка окончания боя ---

func _check_battle_end() -> bool:
	_fsm.transition_to(CombatFSM.State.CHECK_BATTLE_END)

	var any_enemy_alive: bool = false
	for en: EnemyInstance in _enemies:
		if en.is_alive():
			any_enemy_alive = true
			break

	var any_cat_alive: bool = false
	for cat: CatMechInstance in _party:
		if cat.is_alive():
			any_cat_alive = true
			break

	if not any_enemy_alive:
		_handle_victory()
		return true

	if not any_cat_alive:
		_handle_defeat()
		return true

	return false

func _handle_victory() -> void:
	_fsm.transition_to(CombatFSM.State.VICTORY)
	_action_box.visible = false
	_target_box.visible = false

	var total_scrap: int = 0
	var total_cores: int = 0
	var was_boss: bool = false
	var was_elite: bool = false

	for en: EnemyInstance in _enemies:
		if en.data != null:
			total_scrap += en.data.scrap_reward
			total_cores += en.data.core_reward
			if en.data.is_boss:
				was_boss = true
			if en.data.is_elite:
				was_elite = true

	SaveManager.add_run_scrap(total_scrap)
	SaveManager.add_meta_rewards(total_scrap / 2, total_cores)

	var dropped_part_name: String = ""
	if was_elite or was_boss or _rng.randf() < 0.45:
		var loot_pool: Array[PartData] = [
			DataCatalog.get_part("titan_body"),
			DataCatalog.get_part("titan_arms"),
			DataCatalog.get_part("titan_legs"),
			DataCatalog.get_part("scrap_arms")
		]
		var picked: PartData = loot_pool[_rng.randi_range(0, loot_pool.size() - 1)]
		if picked != null:
			SaveManager.spare_parts_inventory.append(String(picked.part_id))
			dropped_part_name = picked.part_name

	EventBus.battle_finished.emit(true, total_scrap, total_cores, dropped_part_name)

	_end_overlay.visible = true
	if was_boss:
		var current_sec: int = clampi(SaveManager.current_sector, 1, 3)
		var postlude_path: String = "res://data/dialogues/boss_postlude_sector" + str(current_sec) + ".dtl"
		if current_sec >= 3:
			_end_title.text = "ПОБЕДА! СИГНАЛ БРЕМЕН-4 ОТПРАВЛЕН!"
			_end_title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.55))
			_end_desc.text = (
				"Спящий Спутник повержен! FELIX и банда котов готовы передать аварийный сигнал SOS на частоте Бремен-4!\n"
				+ "Получено: +" + str(total_scrap) + " Титанового лома, +" + str(total_cores) + " Ядер ИИ."
			)
			_end_btn.text = "СЮЖЕТ: ФИНАЛЬНАЯ ТРАНСЛЯЦИЯ ->"
			_end_btn.pressed.connect(func() -> void:
				EventBus.request_scene_change.emit(&"EVENT", {
					"timeline": postlude_path,
					"next_scene": &"HUB",
					"next_payload": {},
					"title": "ФИНАЛ: ТРАНСЛЯЦИЯ СИГНАЛА SOS // БРЕМЕН-4",
					"continue_text": "В ЛАГЕРЬ БРОДЯГ (ХАБ) ->",
					"action_on_complete": "finish_run"
				})
			)
		else:
			_end_title.text = "ПОБЕДА НАД БОССОМ СЕКТОРА " + str(current_sec) + "!"
			_end_title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
			var drop_txt: String = ("\nНайден модуль: [" + dropped_part_name + "]!") if dropped_part_name != "" else ""
			_end_desc.text = (
				"Собрано лома: +" + str(total_scrap)
				+ ((" | Ядра ИИ: +" + str(total_cores)) if total_cores > 0 else "")
				+ drop_txt
			)
			_end_btn.text = "СЮЖЕТ: ИТОГ БОЯ ->"
			_end_btn.pressed.connect(func() -> void:
				EventBus.request_scene_change.emit(&"EVENT", {
					"timeline": postlude_path,
					"next_scene": &"MAP",
					"next_payload": {},
					"title": "СЕКТОР " + str(current_sec) + " ЗАЧИЩЕН // ПЕРЕХОД",
					"continue_text": "ПЕРЕЙТИ В СЕКТОР " + str(current_sec + 1) + " ->",
					"action_on_complete": "advance_sector"
				})
			)
	else:
		_end_title.text = "ПОБЕДА В БОЮ!"
		_end_title.add_theme_color_override("font_color", Color(0.35, 0.95, 1.0))
		var drop_txt: String = ("\nНайден модуль: [" + dropped_part_name + "]!") if dropped_part_name != "" else ""
		_end_desc.text = (
			"Собрано лома: +" + str(total_scrap)
			+ ((" | Ядра ИИ: +" + str(total_cores)) if total_cores > 0 else "")
			+ drop_txt
		)
		_end_btn.text = "ВЕРНУТЬСЯ НА КАРТУ"
		_end_btn.pressed.connect(func() -> void:
			SaveManager.save_run()
			EventBus.request_scene_change.emit(&"MAP", {})
		)

func _handle_defeat() -> void:
	_fsm.transition_to(CombatFSM.State.DEFEAT)
	_action_box.visible = false
	_target_box.visible = false

	# При гибели партии текущий сейв забега стирается, а ядра эвакуируются в Хаб (ADR-001 Section 2.8)
	SaveManager.add_meta_rewards(25, 1)
	SaveManager.delete_run_save()
	EventBus.battle_finished.emit(false, 25, 1, "")

	_end_overlay.visible = true
	_end_title.text = "КОРПУСА ВЫБИТЫ — ЭВАКУАЦИЯ ЯДЕР!"
	_end_title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_end_desc.text = (
		"Все 4 корпуса котов выведены из строя.\n"
		+ "Аварийный маяк вернул AI-ядра в «Лагерь Бродяг» (+25 Титанового лома, +1 Ядро ИИ)."
	)
	_end_btn.text = "В ЛАГЕРЬ БРОДЯГ (ХАБ)"
	_end_btn.pressed.connect(func() -> void:
		EventBus.request_scene_change.emit(&"HUB", {})
	)
