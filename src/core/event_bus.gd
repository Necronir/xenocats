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

# Сигналы мета-прогрессии и Dialogic 2
signal meta_resources_changed(titanium_scrap: int, ai_cores: int)
signal dialogic_event_triggered(event_code: String, amount: int)
signal music_tape_changed(tape_id: StringName)
signal character_theme_changed(theme_id: StringName, instruments: Array[String])

