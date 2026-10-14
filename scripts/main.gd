extends Node
## Root node. Swaps between the three top-level screens: menu, workshop, fly.

var _current: Node = null


func _ready() -> void:
	Game.screen_requested.connect(_on_screen)
	_on_screen("menu", {})


func _on_screen(screen: String, args: Dictionary) -> void:
	if _current != null:
		_current.queue_free()
		_current = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().process_frame
	match screen:
		"menu":
			_current = MainMenu.new()
		"workshop":
			_current = Workshop.new()
			_current.start_stage = args.get("stage", Game.workshop_stage)
			_current.message = args.get("message", "")
		"fly":
			_current = FlyStage.new()
		_:
			push_error("Unknown screen %s" % screen)
			return
	add_child(_current)
	Audio.set_music(screen != "fly")
	Audio.motor_level = 0.0
