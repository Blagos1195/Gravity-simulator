extends SceneTree

const Main = preload("res://scripts/main.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")

func _initialize() -> void:
	var main := Main.new()
	main.size = Vector2(1440.0, 900.0)
	root.add_child(main)
	await process_frame
	main.rocket_design = RocketAssembly.add_preset_hardware(RocketDesign.create_default())
	main._start_flight()
	await process_frame
	assert(main.mode == "flight")
	assert(is_instance_valid(main.flight_hud_top))
	assert(is_instance_valid(main.flight_hud_right_panel))
	assert(main.flight_hud_right_scroll.get_parent() == main.flight_hud_right_panel)
	assert(main.flight_hud_right_panel.size.x > 0.0 and main.flight_hud_right_panel.size.y > 0.0)
	assert(main.flight_hud_top.size.x > 0.0 and main.flight_hud_top.size.y > 0.0)
	main.size = Vector2(720.0, 540.0)
	main._layout_flight_hud()
	assert(not main.flight_hud_bottom.visible)
	assert(main.flight_hud_right_panel.anchor_top == 1.0)
	main.size = Vector2(1440.0, 900.0)
	main._layout_flight_hud()
	assert(main.flight_hud_bottom.visible)
	main.queue_free()
	await process_frame
	print("Flight HUD layout tests passed.")
	quit()
