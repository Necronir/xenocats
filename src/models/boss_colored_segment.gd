class_name BossColoredSegment
extends Resource

## BossColoredSegment: Управление цветными сегментами уязвимости финального босса (ADR-002, Issue #30)
## 4 цветовых сегмента: Blue (Felix / Тир 1+), Red (Hound / Тир 1+), Yellow (Mule / Тир 2+), Green (Cock / Тир 3).
## Несовпадающие атаки наносят строго 0 урона с баннером "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!" и диссонирующим SFX.

enum AffinityColor {
	BLUE = 1,
	RED = 2,
	YELLOW = 3,
	GREEN = 4
}

@export var segment_id: StringName = &"segment_blue"
@export var segment_name: String = "Синий резонатор"
@export var affinity_color: AffinityColor = AffinityColor.BLUE
@export var max_hp: int = 150
@export var current_hp: int = 150
@export var shield: int = 0
@export var max_shield: int = 0
@export var armor: int = 0
@export var is_broken: bool = false
@export var phase_index: int = 1
@export var required_breaking_tier: int = 1
@export var constituent_hero: StringName = &"FELIX"

func _init(
	p_id: StringName = &"segment_blue",
	p_name: String = "Синий резонатор",
	p_color: AffinityColor = AffinityColor.BLUE,
	p_hp: int = 150,
	p_shield: int = 0,
	p_armor: int = 0,
	p_tier: int = 1,
	p_hero: StringName = &"FELIX"
) -> void:
	segment_id = p_id
	segment_name = p_name
	affinity_color = p_color
	max_hp = p_hp
	current_hp = p_hp
	shield = p_shield
	max_shield = p_shield
	armor = p_armor
	required_breaking_tier = p_tier
	constituent_hero = p_hero
	is_broken = false

static func color_to_string(color: AffinityColor) -> String:
	match color:
		AffinityColor.BLUE: return "BLUE"
		AffinityColor.RED: return "RED"
		AffinityColor.YELLOW: return "YELLOW"
		AffinityColor.GREEN: return "GREEN"
	return "BLUE"

static func string_to_color(str_val: String) -> AffinityColor:
	match str_val.to_upper():
		"BLUE": return AffinityColor.BLUE
		"RED": return AffinityColor.RED
		"YELLOW": return AffinityColor.YELLOW
		"GREEN": return AffinityColor.GREEN
	return AffinityColor.BLUE

static func color_to_russian(color: AffinityColor) -> String:
	match color:
		AffinityColor.BLUE: return "Синий (Гитара / FELIX)"
		AffinityColor.RED: return "Красный (Ударные / HOUND)"
		AffinityColor.YELLOW: return "Жёлтый (Бас / MULE)"
		AffinityColor.GREEN: return "Зелёный (Синтезатор / COCK)"
	return "Синий"

static func color_to_godot_color(color: AffinityColor) -> Color:
	match color:
		AffinityColor.BLUE: return Color(0.2, 0.7, 1.0)
		AffinityColor.RED: return Color(1.0, 0.3, 0.3)
		AffinityColor.YELLOW: return Color(1.0, 0.85, 0.2)
		AffinityColor.GREEN: return Color(0.3, 0.95, 0.4)
	return Color.WHITE

static func get_hero_affinity_color(hero_id: StringName) -> AffinityColor:
	match String(hero_id).to_upper():
		"FELIX": return AffinityColor.BLUE
		"HOUND": return AffinityColor.RED
		"MULE": return AffinityColor.YELLOW
		"COCK": return AffinityColor.GREEN
	return AffinityColor.BLUE

static func get_color_hero(color: AffinityColor) -> StringName:
	match color:
		AffinityColor.BLUE: return &"FELIX"
		AffinityColor.RED: return &"HOUND"
		AffinityColor.YELLOW: return &"MULE"
		AffinityColor.GREEN: return &"COCK"
	return &"FELIX"

static func get_fusion_colors(tier: int) -> Array[AffinityColor]:
	match tier:
		1: # ROBO_CATDOG (Felix + Hound)
			return [AffinityColor.BLUE, AffinityColor.RED]
		2: # ROBO_CATDOG_DONKEY (Felix + Hound + Mule)
			return [AffinityColor.BLUE, AffinityColor.RED, AffinityColor.YELLOW]
		3: # ROBO_MEGA_PYRAMID (Felix + Hound + Mule + Cock)
			return [AffinityColor.BLUE, AffinityColor.RED, AffinityColor.YELLOW, AffinityColor.GREEN]
	return []

static func get_fusion_members(tier: int) -> Array[StringName]:
	match tier:
		1:
			return [&"FELIX", &"HOUND"]
		2:
			return [&"FELIX", &"HOUND", &"MULE"]
		3:
			return [&"FELIX", &"HOUND", &"MULE", &"COCK"]
	return []

func is_vulnerable_to(hero_id: StringName, fusion_tier: int = 0) -> bool:
	if fusion_tier > 0:
		var colors: Array[AffinityColor] = get_fusion_colors(fusion_tier)
		return colors.has(affinity_color)
	var hero_color: AffinityColor = get_hero_affinity_color(hero_id)
	return hero_color == affinity_color

func can_damage(hero_id: StringName, fusion_tier: int = 0) -> bool:
	return is_vulnerable_to(hero_id, fusion_tier)

func apply_damage(raw_damage: int, hero_id: StringName, fusion_tier: int = 0, ignore_armor: bool = false) -> Dictionary:
	if is_broken:
		return {
			"damage": 0,
			"immune": true,
			"floating_text": "0! УЖЕ СЛОМАН",
			"sfx": "hit",
			"just_broken": false,
			"is_broken": true,
			"absorbed_by_shield": 0,
			"current_hp": 0,
			"current_shield": shield
		}

	# Проверка уязвимости по цветовой матрице
	if not is_vulnerable_to(hero_id, fusion_tier):
		return {
			"damage": 0,
			"immune": true,
			"floating_text": "0! МУЗЫКА СЛИШКОМ СЛАБАЯ!",
			"sfx": "dissonance",
			"just_broken": false,
			"is_broken": false,
			"absorbed_by_shield": 0,
			"current_hp": current_hp,
			"current_shield": shield
		}

	# Атака подходящего цвета/слияния
	var remaining: int = raw_damage
	var absorbed: int = 0
	if shield > 0 and not ignore_armor:
		absorbed = mini(shield, remaining)
		shield -= absorbed
		remaining -= absorbed

	var reduction: int = 0 if ignore_armor else armor
	var dealt: int = maxi(1, remaining - reduction) if remaining > 0 else 0
	dealt = mini(dealt, current_hp)
	current_hp = maxi(0, current_hp - dealt)

	var just_broken: bool = (current_hp <= 0) and (not is_broken)
	if current_hp <= 0:
		is_broken = true

	return {
		"damage": dealt,
		"immune": false,
		"floating_text": "-" + str(dealt) + " HP",
		"sfx": "part_break" if just_broken else "hit",
		"just_broken": just_broken,
		"is_broken": is_broken,
		"absorbed_by_shield": absorbed,
		"current_hp": current_hp,
		"current_shield": shield
	}

func add_shield(amount: int) -> void:
	shield += amount
	max_shield = maxi(max_shield, shield)

func repair(amount: int) -> void:
	current_hp = mini(max_hp, current_hp + amount)
	if current_hp > 0:
		is_broken = false

func reset(p_hp: int = -1, p_shield: int = -1) -> void:
	if p_hp > 0:
		max_hp = p_hp
	current_hp = max_hp
	if p_shield >= 0:
		max_shield = p_shield
	shield = max_shield
	is_broken = false

func to_dict() -> Dictionary:
	return {
		"segment_id": String(segment_id),
		"segment_name": segment_name,
		"affinity_color": int(affinity_color),
		"max_hp": max_hp,
		"current_hp": current_hp,
		"shield": shield,
		"max_shield": max_shield,
		"armor": armor,
		"is_broken": is_broken,
		"phase_index": phase_index,
		"required_breaking_tier": required_breaking_tier,
		"constituent_hero": String(constituent_hero)
	}

func from_dict(d: Dictionary) -> void:
	segment_id = StringName(d.get("segment_id", "segment_blue"))
	segment_name = String(d.get("segment_name", "Синий резонатор"))
	affinity_color = int(d.get("affinity_color", AffinityColor.BLUE)) as AffinityColor
	max_hp = int(d.get("max_hp", 150))
	current_hp = int(d.get("current_hp", max_hp))
	shield = int(d.get("shield", 0))
	max_shield = int(d.get("max_shield", shield))
	armor = int(d.get("armor", 0))
	is_broken = bool(d.get("is_broken", false))
	phase_index = int(d.get("phase_index", 1))
	required_breaking_tier = int(d.get("required_breaking_tier", 1))
	constituent_hero = StringName(d.get("constituent_hero", "FELIX"))
