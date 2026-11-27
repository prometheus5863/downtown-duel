extends RefCounted
## Actions added at runtime (project.godot keeps the original hand-edited ones). One table, so the HUD hint,
## the touch buttons and the key bindings stay in step. Called once from player.gd before anything polls input.

const ACTIONS := {
	"cmd_attack": [KEY_1],
	"cmd_follow": [KEY_2],
	"cmd_hold": [KEY_3],
	"cmd_return": [KEY_4],
	"cmd_work": [KEY_5],
	"use_tool": [KEY_R],
	"place_block": [KEY_T],
	"character_menu": [KEY_C],
}


static func ensure() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
