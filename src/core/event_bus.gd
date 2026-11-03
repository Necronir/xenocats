extends Node

## EventBus: Глобальная шина слабосвязанных сигналов (ADR-001 Section 2.3)

# Боевые сигналы
signal cat_part_damaged(cat_id: StringName, part_slot: int, damage: int, current_hp: int)
signal cat_part_destroyed(cat_id: StringName, part_slot: int)
signal enemy_part_destroyed(enemy_index: int, part_slot: int)
signal sync_gauge_changed(current_value: int, max_value: int)
signal sync_gauge_filled()
signal pyramid_activated()
signal pyramid_damaged(damage: int, current_hp: int, max_hp: int)
signal pyramid_deactivated()
signal battle_finished(victory: bool, scrap_earned: int, cores_earned: int, dropped_part_id: String)

# Сигналы карты и навигации
signal request_scene_change(scene_name: StringName, payload: Dictionary)
signal node_selected(node_id: int, node_type: StringName)
signal node_completed(node_id: int)
signal run_resources_changed(scrap: int, sync_gauge: int)

# Сигналы паузы и меню
signal pause_requested()

# Сигналы мета-прогрессии и Dialogic 2
signal meta_resources_changed(titanium_scrap: int, ai_cores: int)
signal dialogic_event_triggered(event_code: String, amount: int)
signal music_tape_changed(tape_id: StringName)
signal character_theme_changed(theme_id: StringName, instruments: Array[String])

func _ready() -> void:
	_ensure_input_mappings()

func _ensure_input_mappings() -> void:
	# 1. dodge_* actions for Undertale-style Dodge Box
	_ensure_action(&"dodge_left", [
		_key_event(KEY_LEFT), _key_event(KEY_A),
		_joy_button_event(JOY_BUTTON_DPAD_LEFT),
		_joy_axis_event(JOY_AXIS_LEFT_X, -1.0)
	])
	_ensure_action(&"dodge_right", [
		_key_event(KEY_RIGHT), _key_event(KEY_D),
		_joy_button_event(JOY_BUTTON_DPAD_RIGHT),
		_joy_axis_event(JOY_AXIS_LEFT_X, 1.0)
	])
	_ensure_action(&"dodge_up", [
		_key_event(KEY_UP), _key_event(KEY_W),
		_joy_button_event(JOY_BUTTON_DPAD_UP),
		_joy_axis_event(JOY_AXIS_LEFT_Y, -1.0)
	])
	_ensure_action(&"dodge_down", [
		_key_event(KEY_DOWN), _key_event(KEY_S),
		_joy_button_event(JOY_BUTTON_DPAD_DOWN),
		_joy_axis_event(JOY_AXIS_LEFT_Y, 1.0)
	])

	# 2. qte_strike action
	_ensure_action(&"qte_strike", [
		_key_event(KEY_SPACE), _key_event(KEY_ENTER), _key_event(KEY_KP_ENTER), _key_event(KEY_Z),
		_joy_button_event(JOY_BUTTON_A),
		_joy_button_event(JOY_BUTTON_B),
		_joy_button_event(JOY_BUTTON_X),
		_joy_button_event(JOY_BUTTON_Y),
		_joy_button_event(JOY_BUTTON_RIGHT_SHOULDER)
	])

	# 3. pause action
	_ensure_action(&"pause", [
		_key_event(KEY_ESCAPE),
		_joy_button_event(JOY_BUTTON_START),
		_joy_button_event(JOY_BUTTON_BACK)
	])

	# 4. Enhance standard ui_* actions for gamepad & WASD navigation
	_add_events_to_action(&"ui_left", [
		_key_event(KEY_A),
		_joy_button_event(JOY_BUTTON_DPAD_LEFT),
		_joy_axis_event(JOY_AXIS_LEFT_X, -1.0)
	])
	_add_events_to_action(&"ui_right", [
		_key_event(KEY_D),
		_joy_button_event(JOY_BUTTON_DPAD_RIGHT),
		_joy_axis_event(JOY_AXIS_LEFT_X, 1.0)
	])
	_add_events_to_action(&"ui_up", [
		_key_event(KEY_W),
		_joy_button_event(JOY_BUTTON_DPAD_UP),
		_joy_axis_event(JOY_AXIS_LEFT_Y, -1.0)
	])
	_add_events_to_action(&"ui_down", [
		_key_event(KEY_S),
		_joy_button_event(JOY_BUTTON_DPAD_DOWN),
		_joy_axis_event(JOY_AXIS_LEFT_Y, 1.0)
	])
	_add_events_to_action(&"ui_accept", [
		_key_event(KEY_SPACE), _key_event(KEY_ENTER), _key_event(KEY_KP_ENTER), _key_event(KEY_Z),
		_joy_button_event(JOY_BUTTON_A),
		_joy_button_event(JOY_BUTTON_X)
	])
	_add_events_to_action(&"ui_cancel", [
		_key_event(KEY_ESCAPE), _key_event(KEY_BACKSPACE),
		_joy_button_event(JOY_BUTTON_B)
	])

func _key_event(code: Key) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	return ev

func _joy_button_event(btn: JoyButton) -> InputEventJoypadButton:
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = btn
	return ev

func _joy_axis_event(axis: JoyAxis, val: float) -> InputEventJoypadMotion:
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = val
	return ev

func _ensure_action(action_name: StringName, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	_add_events_to_action(action_name, events)

func _add_events_to_action(action_name: StringName, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, 0.2)
	var existing: Array[InputEvent] = InputMap.action_get_events(action_name)
	for ev: InputEvent in events:
		var already_has: bool = false
		for ex: InputEvent in existing:
			if ex is InputEventKey and ev is InputEventKey:
				if (ex as InputEventKey).keycode == (ev as InputEventKey).keycode:
					already_has = true
					break
			elif ex is InputEventJoypadButton and ev is InputEventJoypadButton:
				if (ex as InputEventJoypadButton).button_index == (ev as InputEventJoypadButton).button_index:
					already_has = true
					break
			elif ex is InputEventJoypadMotion and ev is InputEventJoypadMotion:
				var m_ex: InputEventJoypadMotion = ex as InputEventJoypadMotion
				var m_ev: InputEventJoypadMotion = ev as InputEventJoypadMotion
				if m_ex.axis == m_ev.axis and signf(m_ex.axis_value) == signf(m_ev.axis_value):
					already_has = true
					break
		if not already_has:
			InputMap.action_add_event(action_name, ev)


