class_name EnemyData
extends Resource

@export var enemy_id: StringName = &""
@export var enemy_name: String = ""
@export var description: String = ""
@export var is_modular: bool = false # false = обычный моб (единый HP), true = Элитка / Босс (3 детали)
@export var is_boss: bool = false
@export var is_elite: bool = false
@export var sector_level: int = 1

# Для обычных мобов (is_modular == false)
@export var max_hp: int = 60
@export var armor: int = 1
@export var speed: int = 10

# Для Элиток и Боссов (is_modular == true)
@export var body_part: PartData = null
@export var arms_part: PartData = null
@export var legs_part: PartData = null

@export var skills: Array[SkillData] = []
@export var dodge_pattern_id: StringName = &"saw_sweep"
@export var sprite_prefix: String = "scrap_drone"
@export var scrap_reward: int = 25
@export var core_reward: int = 0

