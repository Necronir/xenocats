class_name CombatFSM
extends Node

## CombatFSM: Конечный автомат боевой сцены (ADR-001 Section 2.4)

enum State {
	BATTLE_INIT,
	TURN_ORDER_CALC,
	PLAYER_SELECT_ACTION,
	PLAYER_SELECT_TARGET,
	QTE_ATTACK_PHASE,
	RESOLVE_PLAYER_DAMAGE,
	ENEMY_AI_SELECT,
	SPAWN_DODGE_BOX,
	DODGE_REALTIME_MINIGAME,
	RESOLVE_PART_DAMAGE,
	CHECK_BATTLE_END,
	VICTORY,
	DEFEAT
}

signal state_changed(new_state: State)

var current_state: State = State.BATTLE_INIT

func transition_to(next_state: State) -> void:
	current_state = next_state
	state_changed.emit(current_state)

static func state_to_string(s: State) -> String:
	match s:
		State.BATTLE_INIT:
			return "BATTLE_INIT"
		State.TURN_ORDER_CALC:
			return "TURN_ORDER_CALC"
		State.PLAYER_SELECT_ACTION:
			return "PLAYER_SELECT_ACTION"
		State.PLAYER_SELECT_TARGET:
			return "PLAYER_SELECT_TARGET"
		State.QTE_ATTACK_PHASE:
			return "QTE_ATTACK_PHASE"
		State.RESOLVE_PLAYER_DAMAGE:
			return "RESOLVE_PLAYER_DAMAGE"
		State.ENEMY_AI_SELECT:
			return "ENEMY_AI_SELECT"
		State.SPAWN_DODGE_BOX:
			return "SPAWN_DODGE_BOX"
		State.DODGE_REALTIME_MINIGAME:
			return "DODGE_REALTIME_MINIGAME"
		State.RESOLVE_PART_DAMAGE:
			return "RESOLVE_PART_DAMAGE"
		State.CHECK_BATTLE_END:
			return "CHECK_BATTLE_END"
		State.VICTORY:
			return "VICTORY"
		State.DEFEAT:
			return "DEFEAT"
	return "UNKNOWN"

