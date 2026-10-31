class_name SceneManager
extends Control

## SceneManager / GameRoot: Корневой менеджер топологии сцен (ADR-001 Section 2.3)

var _screen_container: Control = null
var _current_scene: Node = null
var _pause_menu: PauseMenu = null
var current_scene_key: StringName = &""
var current_payload: Dictionary = {}

const PAUSABLE_SCENES: Array[StringName] = [&"BATTLE", &"MAP"]

const SCENE_PATHS: Dictionary = {
	"HUB": "res://src/hub/hub_scene.tscn",
	"MAP": "res://src/map/map_scene.tscn",
	"BATTLE": "res://src/combat/combat_arena.tscn",
	"GARAGE": "res://src/garage/garage_scene.tscn",
	"EVENT": "res://src/event/event_scene.tscn"
}

func _ready() -> void:
	_screen_container = Control.new()
	_screen_container.name = "ScreenContainer"
	_screen_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_container)

	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)

	EventBus.request_scene_change.connect(_on_request_scene_change)
	change_scene(&"HUB", {})

func _exit_tree() -> void:
	if _pause_menu != null:
		_pause_menu.close()
	if is_inside_tree():
		get_tree().paused = false

func _on_request_scene_change(scene_name: StringName, payload: Dictionary) -> void:
	change_scene(scene_name, payload)

func change_scene(scene_name: StringName, payload: Dictionary = {}) -> void:
	var key: String = String(scene_name)
	if not SCENE_PATHS.has(key):
		push_error("Unknown scene requested: " + key)
		return

	if _pause_menu != null:
		_pause_menu.close()
	if is_inside_tree():
		get_tree().paused = false

	if _current_scene != null and is_instance_valid(_current_scene):
		_current_scene.queue_free()
		_current_scene = null

	var packed: PackedScene = load(String(SCENE_PATHS[key])) as PackedScene
	if packed == null:
		return

	current_scene_key = StringName(key)
	current_payload = payload.duplicate(true)

	var inst: Node = packed.instantiate()
	if inst.has_method("setup_battle") and key == "BATTLE":
		inst.call("setup_battle", payload)
	elif inst.has_method("setup_garage") and key == "GARAGE":
		inst.call("setup_garage", payload)
	elif inst.has_method("setup_event") and key == "EVENT":
		inst.call("setup_event", payload)

	_screen_container.add_child(inst)
	_current_scene = inst

	if _pause_menu != null:
		_pause_menu.mode = current_scene_key
		_pause_menu.allowed = PAUSABLE_SCENES.has(current_scene_key)
		_pause_menu.current_scene_ref = _current_scene

