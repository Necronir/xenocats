class_name PartData
extends Resource

enum PartSlot {
	BODY = 0,
	ARMS = 1,
	LEGS = 2
}

@export var part_id: StringName = &""
@export var part_name: String = ""
@export var description: String = ""
@export var slot: PartSlot = PartSlot.BODY
@export var max_hp: int = 60
@export var armor: int = 2
@export var weight: int = 10
@export var power_output: int = 0
@export var base_speed: int = 12
@export var skills: Array[SkillData] = []
@export var texture_path: String = ""
@export var arms_joint_offset: Vector2 = Vector2(2, 2)
@export var legs_joint_offset: Vector2 = Vector2(0, 16)

var max_weight_capacity: int:
	get:
		return power_output
	set(val):
		power_output = val

static func slot_to_russian(p_slot: PartSlot) -> String:
	match p_slot:
		PartSlot.BODY:
			return "Корпус"
		PartSlot.ARMS:
			return "Руки"
		PartSlot.LEGS:
			return "Ноги"
	return "Деталь"

