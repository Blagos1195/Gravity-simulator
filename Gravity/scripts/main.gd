extends Control

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RoutePlanner = preload("res://scripts/route_planner.gd")
const SAVE_DIR := "user://saves"
const AUTOSAVE_INTERVAL := 60.0
const DOCKING_CAPTURE_DISTANCE := 100.0
const DOCKING_CAPTURE_SPEED := 2.5

var mode := "menu"
var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var infinite_weightless_fuel := false
var simulate_belt_collisions := false
var save_slot := 1
var sim
var fleet_sims: Array = []
var active_vehicle_index := 0
var fleet_time_backlog := 0.0
var vehicle_selector: OptionButton
var docking_links: Array[Dictionary] = []
var autosave_elapsed := 0.0
var autosave_enabled := true
var rebinding_action := ""
var rebinding_button: Button
const CONTROL_BINDINGS := {
	"engine_toggle": ["ENGINE TOGGLE", KEY_W],
	"throttle_cutoff": ["ENGINE CUTOFF", KEY_S],
	"rotate_left": ["ROTATE LEFT", KEY_A],
	"rotate_right": ["ROTATE RIGHT", KEY_D],
	"pause_game": ["PAUSE", KEY_SPACE],
	"stage_separation": ["STAGE SEPARATION", KEY_X],
	"guidance_toggle": ["GUIDANCE", KEY_H]
}
var status_label: Label
var menu_root: VBoxContainer
var settings_root: VBoxContainer
var hud_root: Control
var scale_factor := 1.0
var rocket_design: Dictionary = RocketDesign.create_default()
var design_stats_label: Label
var design_error_label: Label
var design_preview: Control

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	_configure_input_actions()
	_load_general_settings()
	_build_menu()

func _configure_input_actions() -> void:
	var config := ConfigFile.new()
	config.load("user://controls.cfg")
	for action in CONTROL_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var keycode := int(config.get_value("controls", action, CONTROL_BINDINGS[action][1]))
		var key_event := InputEventKey.new()
		key_event.keycode = keycode
		InputMap.action_add_event(action, key_event)

func _save_controls() -> void:
	var config := ConfigFile.new()
	for action in CONTROL_BINDINGS:
		var events := InputMap.action_get_events(action)
		if not events.is_empty() and events[0] is InputEventKey:
			config.set_value("controls", action, int(events[0].keycode))
	config.save("user://controls.cfg")

func _load_general_settings() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	autosave_enabled = bool(config.get_value("general", "autosave", true))
	simulate_belt_collisions = bool(config.get_value("general", "simulate_belt_collisions", false))
	var fullscreen := bool(config.get_value("general", "fullscreen", false))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _save_general_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("general", "autosave", autosave_enabled)
	config.set_value("general", "simulate_belt_collisions", simulate_belt_collisions)
	config.set_value("general", "fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	config.save("user://settings.cfg")

func _input(event: InputEvent) -> void:
	if rebinding_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		rebinding_action = ""
		if is_instance_valid(rebinding_button):
			rebinding_button.text = _binding_label(str(rebinding_button.get_meta("action")))
		rebinding_button = null
		return
	var candidate_key: int = int(event.keycode)
	for action in CONTROL_BINDINGS:
		if action == rebinding_action:
			continue
		for assigned_event in InputMap.action_get_events(action):
			if assigned_event is InputEventKey and assigned_event.keycode == candidate_key:
				if is_instance_valid(rebinding_button):
					rebinding_button.text = "KEY ALREADY ASSIGNED"
				return
	var key_event := InputEventKey.new()
	key_event.keycode = candidate_key
	InputMap.action_erase_events(rebinding_action)
	InputMap.action_add_event(rebinding_action, key_event)
	_save_controls()
	if is_instance_valid(rebinding_button):
		rebinding_button.text = _binding_label(rebinding_action)
	rebinding_action = ""
	rebinding_button = null

func _binding_label(action: String) -> String:
	var events := InputMap.action_get_events(action)
	var key_name := "UNBOUND"
	if not events.is_empty() and events[0] is InputEventKey:
		key_name = OS.get_keycode_string(events[0].keycode)
	return "%s  [%s]" % [str(CONTROL_BINDINGS[action][0]), key_name]

func _add_rebind_button(parent: Node, action: String) -> void:
	var button := Button.new()
	button.set_meta("action", action)
	button.text = _binding_label(action)
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(func():
		rebinding_action = action
		rebinding_button = button
		button.text = "PRESS A KEY  •  ESC TO CANCEL"
	)
	parent.add_child(button)

func _process(delta: float) -> void:
	if mode == "flight":
		_advance_fleet(delta)
		autosave_elapsed += delta
		if autosave_enabled and autosave_elapsed >= AUTOSAVE_INTERVAL:
			autosave_elapsed = 0.0
			_save_game(true)

func _advance_fleet(delta: float) -> void:
	if fleet_sims.is_empty() or not is_instance_valid(sim):
		return
	for vehicle in fleet_sims:
		vehicle.time_warp = sim.time_warp
		vehicle.paused = sim.paused
		vehicle.prediction_timer += delta
		if vehicle.show_predicted_trajectory and vehicle.prediction_timer >= 0.35:
			vehicle.prediction_timer = 0.0
			vehicle._calculate_predicted_trajectory()
		vehicle.trail_timer += delta
		if vehicle.trail_timer >= 0.12:
			vehicle.trail_timer = 0.0
			vehicle.trail.append(vehicle.rocket_position)
			if vehicle.trail.size() > 450:
				vehicle.trail.pop_front()
	if sim.paused:
		fleet_time_backlog = 0.0
	else:
		var effective_warp: float = sim.time_warp
		for vehicle in fleet_sims:
			var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position)
			var altitude: float = maxf(0.0, float(body.distance) - float(body.radius))
			var atmosphere_height: float = PlanetarySystem.planetary_atmosphere_height(str(body.get("name", "Earth")))
			if float(body.distance) < float(body.soi) and altitude < atmosphere_height:
				effective_warp = minf(effective_warp, 100.0)
		fleet_time_backlog += effective_warp * delta
		var iterations := 0
		var physics_budget_start_usec: int = Time.get_ticks_usec()
		_update_docked_masses()
		while fleet_time_backlog > 0.000001 and iterations < SimulationView.MAX_PHYSICS_STEPS_PER_FRAME and Time.get_ticks_usec() - physics_budget_start_usec < SimulationView.MAX_PHYSICS_BUDGET_USEC:
			var step_delta := fleet_time_backlog
			for vehicle in fleet_sims:
				if not _is_docked_child(vehicle.vehicle_name):
					step_delta = minf(step_delta, vehicle._adaptive_step_size())
			if step_delta <= 0.000001:
				break
			for vehicle in fleet_sims:
				if not _is_docked_child(vehicle.vehicle_name):
					vehicle._physics_step(step_delta)
			_sync_docked_vehicles()
			fleet_time_backlog = maxf(0.0, fleet_time_backlog - step_delta)
			iterations += 1
	for vehicle in fleet_sims:
		vehicle.simulation_time_backlog = fleet_time_backlog
	if is_instance_valid(sim):
		sim.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if mode != "flight" or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		_save_game(false)
	elif event.keycode == KEY_F9:
		_load_game()
	elif event.keycode == KEY_ESCAPE:
		_pause_simulation()

func _build_menu() -> void:
	mode = "menu"
	fleet_sims.clear()
	sim = null
	vehicle_selector = null
	fleet_time_backlog = 0.0
	docking_links.clear()
	rebinding_action = ""
	rebinding_button = null
	for child in get_children():
		child.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.018, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stars := Starfield.new()
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stars)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	menu_root = VBoxContainer.new()
	menu_root.custom_minimum_size = Vector2(480, 0)
	menu_root.add_theme_constant_override("separation", 18)
	center.add_child(menu_root)

	var title := Label.new()
	title.text = "G R A V I T Y"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	menu_root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "2D SPACEFLIGHT SIMULATOR"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.35, 0.66, 0.82))
	menu_root.add_child(subtitle)
	_add_spacer(menu_root, 18)

	if _latest_save_slot() > 0:
		_add_button(menu_root, "CONTINUE", _continue_game)
	_add_button(menu_root, "NEW GAME", _begin_new_game)
	_add_button(menu_root, "GAME LOAD", _show_game_load)
	_add_button(menu_root, "SETTINGS", _show_settings)
	_add_button(menu_root, "QUIT", _quit_game)

	var footer := Label.new()
	footer.text = "BUILD 0.1.0  •  PROCEDURAL SPACE SIMULATION"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(0.28, 0.38, 0.5))
	menu_root.add_child(footer)


func _show_vehicle_editor() -> void:
	for child in get_children():
		child.queue_free()
	mode = "editor"
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.018, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 26
	root.offset_right = -26
	root.offset_top = 18
	root.offset_bottom = -18
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var heading := Label.new()
	heading.text = "VEHICLE WORKSHOP"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	root.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "ASSEMBLE STAGES AND PAYLOADS  •  PERFORMANCE IS CALCULATED AUTOMATICALLY"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.35, 0.66, 0.82))
	root.add_child(subtitle)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 10)
	root.add_child(preset_row)
	var preset_selector := OptionButton.new()
	preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in RocketDesign.preset_options():
		preset_selector.add_item(str(preset.label))
		preset_selector.set_item_metadata(preset_selector.item_count - 1, str(preset.id))
	preset_selector.select(1)
	preset_row.add_child(preset_selector)
	var preset_description := Label.new()
	preset_description.text = RocketDesign.preset_description("LEO_CARGO")
	preset_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_description.add_theme_color_override("font_color", Color(0.58, 0.68, 0.8))
	root.add_child(preset_description)
	preset_selector.item_selected.connect(func(index: int):
		var selected_preset_id := str(preset_selector.get_item_metadata(index))
		preset_description.text = RocketDesign.preset_description(selected_preset_id)
	)
	_add_button(preset_row, "LOAD PRESET", func():
		var selected_preset_id := str(preset_selector.get_item_metadata(preset_selector.selected))
		rocket_design = RocketDesign.create_preset(selected_preset_id)
		_show_vehicle_editor()
	)
	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 18)
	root.add_child(workspace)
	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size.x = 390
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(preview_panel)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 10)
	preview_panel.add_child(preview_column)
	var preview_title := Label.new()
	preview_title.text = "VEHICLE PREVIEW"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_title.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	preview_column.add_child(preview_title)
	design_preview = RocketPreview.new()
	design_preview.design = rocket_design
	design_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	design_preview.custom_minimum_size = Vector2(330, 390)
	preview_column.add_child(design_preview)
	design_stats_label = Label.new()
	design_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	design_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_column.add_child(design_stats_label)
	design_error_label = Label.new()
	design_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	design_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	design_error_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.35))
	preview_column.add_child(design_error_label)
	var assembly_panel := PanelContainer.new()
	assembly_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assembly_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(assembly_panel)
	var assembly := VBoxContainer.new()
	assembly.add_theme_constant_override("separation", 10)
	assembly_panel.add_child(assembly)
	var vehicle_name_label := Label.new()
	vehicle_name_label.text = "VEHICLE NAME"
	vehicle_name_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	assembly.add_child(vehicle_name_label)
	var vehicle_name := LineEdit.new()
	vehicle_name.text = str(rocket_design.get("name", "Custom Vehicle"))
	vehicle_name.placeholder_text = "Vehicle name"
	vehicle_name.text_changed.connect(func(value: String):
		rocket_design["name"] = value
		design_preview.queue_redraw()
	)
	assembly.add_child(vehicle_name)
	var payload_label := Label.new()
	payload_label.text = "PAYLOAD"
	payload_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	assembly.add_child(payload_label)
	var payload_selector := OptionButton.new()
	payload_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var payload_options := [
		{"id": "custom", "label": "Custom payload · %.1f t" % (float(rocket_design.get("payload_mass", 500.0)) / 1000.0), "mass": float(rocket_design.get("payload_mass", 500.0))},
		{"id": "satellite", "label": "Small satellite · 150 kg", "mass": 150.0},
		{"id": "probe", "label": "Science probe · 1.8 t", "mass": 1800.0},
		{"id": "crew", "label": "Crew capsule · 6.5 t", "mass": 6500.0},
		{"id": "cargo", "label": "Cargo module · 8 t", "mass": 8000.0},
		{"id": "heavy_cargo", "label": "Heavy cargo · 12 t", "mass": 12000.0}
	]
	var selected_payload := 0
	for payload_index in range(payload_options.size()):
		var payload_option: Dictionary = payload_options[payload_index]
		payload_selector.add_item(str(payload_option.label))
		payload_selector.set_item_metadata(payload_index, payload_option)
		if is_equal_approx(float(payload_option.mass), float(rocket_design.get("payload_mass", 500.0))):
			selected_payload = payload_index
	payload_selector.select(selected_payload)
	rocket_design["payload_type"] = str(payload_options[selected_payload].id)
	payload_selector.item_selected.connect(func(index: int):
		var selected_payload_option: Dictionary = payload_selector.get_item_metadata(index)
		rocket_design["payload_mass"] = float(selected_payload_option.mass)
		rocket_design["payload_type"] = str(selected_payload_option.id)
		_update_design_stats()
	)
	assembly.add_child(payload_selector)
	var stages_heading := Label.new()
	stages_heading.text = "STAGE STACK  •  FIRST STAGE AT THE BOTTOM"
	stages_heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	assembly.add_child(stages_heading)
	var stage_scroll := ScrollContainer.new()
	stage_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	assembly.add_child(stage_scroll)
	var stage_list := VBoxContainer.new()
	stage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_list.add_theme_constant_override("separation", 8)
	stage_scroll.add_child(stage_list)
	var stage_part_options := RocketDesign.stage_part_options()
	for stage_index in range(rocket_design["stages"].size()):
		var stage: Dictionary = rocket_design["stages"][stage_index]
		var stage_panel := PanelContainer.new()
		stage_list.add_child(stage_panel)
		var stage_row := HBoxContainer.new()
		stage_row.add_theme_constant_override("separation", 8)
		stage_panel.add_child(stage_row)
		var stage_number := Label.new()
		stage_number.text = "STAGE %02d" % (stage_index + 1)
		stage_number.custom_minimum_size.x = 90
		stage_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stage_row.add_child(stage_number)
		var part_selector := OptionButton.new()
		part_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected_part_index := 0
		for part_index in range(stage_part_options.size()):
			var part_option: Dictionary = stage_part_options[part_index]
			part_selector.add_item(str(part_option.label))
			part_selector.set_item_metadata(part_index, str(part_option.id))
			if str(stage.get("part_id", "")) == str(part_option.id):
				selected_part_index = part_index
		if not stage_part_options.is_empty():
			part_selector.select(selected_part_index)
		part_selector.item_selected.connect(func(part_index: int):
			var selected_part_id := str(part_selector.get_item_metadata(part_index))
			rocket_design["stages"][stage_index] = RocketDesign.configure_stage(selected_part_id, 1, 1.0)
			_show_vehicle_editor()
		)
		stage_row.add_child(part_selector)
		var engine_selector := OptionButton.new()
		engine_selector.tooltip_text = "Splits the stage's total thrust and fuel flow across this many smaller engines."
		for engine_count in [1, 2, 3, 4, 6, 8]:
			engine_selector.add_item("%d engine%s" % [engine_count, "" if engine_count == 1 else "s"])
			engine_selector.set_item_metadata(engine_selector.item_count - 1, engine_count)
		var current_engine_count := int(stage.get("engine_count", 1))
		var engine_options := [1, 2, 3, 4, 6, 8]
		engine_selector.select(engine_options.find(current_engine_count) if current_engine_count in engine_options else 0)
		engine_selector.item_selected.connect(func(option_index: int):
			var current_stage: Dictionary = rocket_design["stages"][stage_index]
			var configured := RocketDesign.configure_stage(str(current_stage.get("part_id", "")), int(engine_selector.get_item_metadata(option_index)), float(current_stage.get("tank_scale", 1.0)))
			if not configured.is_empty():
				rocket_design["stages"][stage_index] = configured
				_update_design_stats()
		)
		stage_row.add_child(engine_selector)
		var tank_selector := OptionButton.new()
		var tank_options := [
			{"label": "Compact tank", "scale": 0.75},
			{"label": "Standard tank", "scale": 1.0},
			{"label": "Extended tank", "scale": 1.25}
		]
		var selected_tank_index := 1
		for tank_index in range(tank_options.size()):
			tank_selector.add_item(str(tank_options[tank_index].label))
			tank_selector.set_item_metadata(tank_index, float(tank_options[tank_index].scale))
			if is_equal_approx(float(stage.get("tank_scale", 1.0)), float(tank_options[tank_index].scale)):
				selected_tank_index = tank_index
		tank_selector.select(selected_tank_index)
		tank_selector.item_selected.connect(func(option_index: int):
			var current_stage: Dictionary = rocket_design["stages"][stage_index]
			var configured := RocketDesign.configure_stage(str(current_stage.get("part_id", "")), int(current_stage.get("engine_count", 1)), float(tank_selector.get_item_metadata(option_index)))
			if not configured.is_empty():
				rocket_design["stages"][stage_index] = configured
				_update_design_stats()
		)
		stage_row.add_child(tank_selector)
		var move_up_button := Button.new()
		move_up_button.text = "↑"
		move_up_button.tooltip_text = "Move this stage closer to the payload"
		move_up_button.disabled = stage_index == rocket_design["stages"].size() - 1
		move_up_button.pressed.connect(func():
			var stages: Array = rocket_design["stages"]
			var moved_stage: Dictionary = stages[stage_index]
			stages.remove_at(stage_index)
			stages.insert(stage_index + 1, moved_stage)
			_show_vehicle_editor()
		)
		stage_row.add_child(move_up_button)
		var move_down_button := Button.new()
		move_down_button.text = "↓"
		move_down_button.tooltip_text = "Move this stage closer to the launch pad"
		move_down_button.disabled = stage_index == 0
		move_down_button.pressed.connect(func():
			var stages: Array = rocket_design["stages"]
			var moved_stage: Dictionary = stages[stage_index]
			stages.remove_at(stage_index)
			stages.insert(stage_index - 1, moved_stage)
			_show_vehicle_editor()
		)
		stage_row.add_child(move_down_button)
		var remove_button := Button.new()
		remove_button.text = "REMOVE"
		remove_button.disabled = rocket_design["stages"].size() <= RocketDesign.MIN_STAGES
		remove_button.pressed.connect(func():
			rocket_design["stages"].remove_at(stage_index)
			_show_vehicle_editor()
		)
		stage_row.add_child(remove_button)
	var component_row := HBoxContainer.new()
	component_row.add_theme_constant_override("separation", 8)
	assembly.add_child(component_row)
	var new_stage_selector := OptionButton.new()
	new_stage_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for part_option in stage_part_options:
		new_stage_selector.add_item(str(part_option.label))
		new_stage_selector.set_item_metadata(new_stage_selector.item_count - 1, str(part_option.id))
	_add_button(component_row, "ADD STAGE", func():
		if rocket_design["stages"].size() >= RocketDesign.MAX_STAGES:
			return
		var new_stage := RocketDesign.configure_stage(str(new_stage_selector.get_item_metadata(new_stage_selector.selected)), 1, 1.0)
		if not new_stage.is_empty():
			rocket_design["stages"].append(new_stage)
			_show_vehicle_editor()
	)
	component_row.add_child(new_stage_selector)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	root.add_child(actions)
	_add_button(actions, "RESET", func():
		rocket_design = RocketDesign.create_default()
		_show_vehicle_editor()
	)
	_add_button(actions, "LOAD DESIGN", _load_rocket_design)
	_add_button(actions, "SAVE DESIGN", _save_rocket_design)
	_add_button(actions, "LAUNCH VEHICLE", _launch_designed_vehicle)
	_add_button(actions, "BACK", _show_new_game_setup)
	_update_design_stats()

func _update_design_stats() -> void:
	if not is_instance_valid(design_stats_label) or not is_instance_valid(design_error_label):
		return
	var errors := RocketDesign.validation_errors(rocket_design)
	var total_mass := RocketDesign.total_initial_mass(rocket_design)
	var delta_v := RocketDesign.total_delta_v(rocket_design)
	var stages: Array = rocket_design["stages"]
	var first: Dictionary = stages[0]
	var initial_twr := float(first["thrust"]) * float(first.get("engine_count", 1)) / maxf(1.0, total_mass * 9.80665)
	var engine_report := PackedStringArray()
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var sea_isp := RocketDesign.stage_specific_impulse(stage, false)
		var vacuum_isp := RocketDesign.stage_specific_impulse(stage, true)
		var ignition_mass := RocketDesign.stage_ignition_mass(rocket_design, i)
		var stage_thrust := float(stage["thrust"] if i == 0 else stage["vacuum_thrust"]) * float(stage.get("engine_count", 1))
		var stage_twr := stage_thrust / maxf(1.0, ignition_mass * 9.80665)
		engine_report.append("STAGE %d  •  Isp %.0f / %.0f s  •  TWR %.2f" % [i + 1, sea_isp, vacuum_isp, stage_twr])
	design_stats_label.text = "INITIAL MASS\n%.1f tonnes\n\nIDEAL ΔV\n%.2f km/s\n\nPAD TWR\n%.2f\n\n%s" % [total_mass / 1000.0, delta_v / 1000.0, initial_twr, "\n".join(engine_report)]
	design_error_label.text = "\n".join(errors) if not errors.is_empty() else "DESIGN VALID"
	if is_instance_valid(design_preview):
		design_preview.design = rocket_design
		design_preview.queue_redraw()

func _save_rocket_design() -> void:
	var errors := RocketDesign.validation_errors(rocket_design)
	if not errors.is_empty():
		_update_design_stats()
		return
	var file := FileAccess.open("user://rocket_design.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(rocket_design, "\t"))
		file.close()
		if is_instance_valid(design_error_label):
			design_error_label.text = "DESIGN SAVED"
	else:
		if is_instance_valid(design_error_label):
			design_error_label.text = "DESIGN FILE COULD NOT BE OPENED"


func _load_rocket_design() -> void:
	var path := "user://rocket_design.json"
	if not FileAccess.file_exists(path):
		if is_instance_valid(design_error_label):
			design_error_label.text = "NO SAVED DESIGN FOUND"
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if is_instance_valid(design_error_label):
			design_error_label.text = "SAVED DESIGN COULD NOT BE OPENED"
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and RocketDesign.validation_errors(parsed).is_empty():
		rocket_design = parsed
		_show_vehicle_editor()
	else:
		if is_instance_valid(design_error_label):
			design_error_label.text = "SAVED DESIGN IS INVALID"

func _launch_designed_vehicle() -> void:
	var errors := RocketDesign.validation_errors(rocket_design)
	if not errors.is_empty():
		_update_design_stats()
		return
	_start_flight()

func _begin_new_game() -> void:
	rocket_design = RocketDesign.create_default()
	infinite_weightless_fuel = false
	_show_new_game_setup()

func _show_new_game_setup() -> void:
	for child in get_children():
		child.queue_free()
	mode = "new_game_setup"
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.018, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(560, 0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)
	var heading := Label.new()
	heading.text = "NEW GAME SETUP"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	root.add_child(heading)
	_add_setting_label(root, "PHYSICS PRESET")
	var physics := OptionButton.new()
	for option in ["Arcade", "Standard", "Realistic", "Hardcore"]:
		physics.add_item(option)
	physics.select(["Arcade", "Standard", "Realistic", "Hardcore"].find(realism))
	physics.item_selected.connect(func(index: int): realism = physics.get_item_text(index))
	root.add_child(physics)
	_add_setting_label(root, "SOLAR SYSTEM SCALE")
	var scale := OptionButton.new()
	for option in ["Compressed", "Balanced", "Realistic distances"]:
		scale.add_item(option)
	scale.select(["Compressed", "Balanced", "Realistic distances"].find(world_scale))
	scale.item_selected.connect(func(index: int): world_scale = scale.get_item_text(index))
	root.add_child(scale)
	_add_setting_label(root, "GAME MODE")
	var career := CheckButton.new()
	career.text = "Enable career progression"
	career.button_pressed = career_enabled
	career.toggled.connect(func(value: bool): career_enabled = value)
	root.add_child(career)
	var infinite_fuel := CheckButton.new()
	infinite_fuel.text = "Infinite propellant (fuel mass retained)"
	infinite_fuel.button_pressed = infinite_weightless_fuel
	infinite_fuel.toggled.connect(func(value: bool): infinite_weightless_fuel = value)
	root.add_child(infinite_fuel)
	var note := Label.new()
	note.text = "These choices are stored with this new save and remain separate from global game settings."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.58, 0.68, 0.8))
	root.add_child(note)
	_add_button(root, "CONTINUE TO ROCKET BUILDER", _show_vehicle_editor)
	_add_button(root, "BACK", _build_menu)

func _save_exists(slot: int) -> bool:
	return FileAccess.file_exists("%s/slot_%02d.json" % [SAVE_DIR, slot])

func _latest_save_slot() -> int:
	var latest_slot := 0
	var latest_time := -1
	for slot in range(1, 9):
		var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not (parsed is Dictionary):
			continue
		var modified := FileAccess.get_modified_time(path)
		if modified > latest_time:
			latest_time = modified
			latest_slot = slot
	return latest_slot

func _continue_game() -> void:
	save_slot = _latest_save_slot()
	if save_slot <= 0:
		_build_menu()
		return
	_start_flight()
	_load_game()

func _load_menu_slot(slot: int) -> void:
	save_slot = slot
	_start_flight()
	_load_game()

func _show_game_load() -> void:
	for child in get_children():
		child.queue_free()
	mode = "load_menu"
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.018, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(620, 0)
	layout.add_theme_constant_override("separation", 12)
	center.add_child(layout)
	var heading := Label.new()
	heading.text = "LOAD GAME"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	layout.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 560)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 7)
	scroll.add_child(root)
	for slot in range(1, 9):
		var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			var parsed: Variant = null
			if file:
				parsed = JSON.parse_string(file.get_as_text())
				file.close()
			if parsed is Dictionary:
				var label := "SLOT %02d  •  %s  •  %s" % [slot, str(parsed.get("realism", "Unknown")), str(parsed.get("world_scale", "Unknown"))]
				_add_button(root, label, _load_menu_slot.bind(slot))
			else:
				var corrupt_label := Label.new()
				corrupt_label.text = "SLOT %02d  •  INVALID SAVE" % slot
				root.add_child(corrupt_label)
		else:
			var empty_label := Label.new()
			empty_label.text = "SLOT %02d  •  EMPTY" % slot
			root.add_child(empty_label)
		var history_paths: Array[String] = _autosave_history_paths(slot)
		for history_path in history_paths:
			var history_time: int = FileAccess.get_modified_time(history_path)
			var history_label := "     ↳ AUTOSAVE  •  %s" % Time.get_datetime_string_from_unix_time(history_time, true)
			_add_button(root, history_label, _load_menu_path.bind(slot, history_path))
	_add_button(layout, "BACK", _build_menu)

func _show_settings() -> void:
	for child in get_children():
		child.queue_free()
	mode = "settings"
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.018, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	settings_root = VBoxContainer.new()
	settings_root.custom_minimum_size = Vector2(520, 0)
	settings_root.add_theme_constant_override("separation", 14)
	center.add_child(settings_root)
	var heading := Label.new()
	heading.text = "GAME SETTINGS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	settings_root.add_child(heading)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(func(enabled: bool):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
		_save_general_settings()
	)
	settings_root.add_child(fullscreen)
	var autosave := CheckButton.new()
	autosave.text = "Automatic saving every 60 seconds"
	autosave.button_pressed = autosave_enabled
	autosave.toggled.connect(func(enabled: bool):
		autosave_enabled = enabled
		_save_general_settings()
	)
	settings_root.add_child(autosave)
	var belt_collisions := CheckButton.new()
	belt_collisions.text = "Enable small-body collision simulation"
	belt_collisions.button_pressed = simulate_belt_collisions
	belt_collisions.toggled.connect(func(enabled: bool):
		simulate_belt_collisions = enabled
		_save_general_settings()
	)
	settings_root.add_child(belt_collisions)
	var belt_collisions_note := Label.new()
	belt_collisions_note.text = "Belt objects follow independent, massless Sun-orbit paths and can impact the spacecraft. Mutual asteroid gravity is not modeled."
	belt_collisions_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	belt_collisions_note.add_theme_color_override("font_color", Color(0.58, 0.68, 0.8))
	settings_root.add_child(belt_collisions_note)
	_add_setting_label(settings_root, "KEYBOARD CONTROLS")
	for action in CONTROL_BINDINGS:
		_add_rebind_button(settings_root, action)
	var controls_note := Label.new()
	controls_note.text = "Physics, universe scale and career are selected when creating a new game. Key bindings are saved globally."
	controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_note.add_theme_color_override("font_color", Color(0.58, 0.68, 0.8))
	settings_root.add_child(controls_note)
	_add_button(settings_root, "BACK", _build_menu)

func _create_vehicle(design: Dictionary, name: String, saved_state: Dictionary = {}) -> SimulationView:
	var vehicle := SimulationView.new()
	vehicle.vehicle_name = name
	vehicle.realism = realism
	vehicle.world_scale = world_scale
	vehicle.career_enabled = career_enabled
	vehicle.infinite_weightless_fuel = infinite_weightless_fuel
	vehicle.simulate_belt_collisions = simulate_belt_collisions
	vehicle.input_enabled = false
	vehicle.visible = false
	vehicle.z_index = -1
	vehicle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vehicle.set_rocket_design(design)
	add_child(vehicle)
	vehicle.set_process(false)
	if not saved_state.is_empty() and not vehicle.load_save_data(saved_state):
		vehicle.queue_free()
		return null
	vehicle.input_enabled = false
	vehicle.visible = false
	vehicle.set_process(false)
	return vehicle

func _start_flight() -> void:
	for child in get_children():
		child.queue_free()
	fleet_sims.clear()
	active_vehicle_index = 0
	fleet_time_backlog = 0.0
	docking_links.clear()
	vehicle_selector = null
	mode = "flight"
	autosave_elapsed = 0.0
	var first_vehicle := _create_vehicle(rocket_design, "Vehicle 1")
	fleet_sims.append(first_vehicle)
	_build_flight_hud()
	_switch_vehicle(0)

func _add_new_vehicle() -> void:
	if not is_instance_valid(sim):
		return
	var design := {
		"name": sim.vehicle_name,
		"payload_mass": sim.payload_mass,
		"stages": sim.rocket_stages.duplicate(true)
	}
	_launch_vehicle_design(design)

func _launch_vehicle_design(design: Dictionary) -> void:
	if fleet_sims.is_empty():
		if status_label:
			status_label.text = "LAUNCH A FIRST VEHICLE BEFORE ADDING ANOTHER"
		return
	var errors := RocketDesign.validation_errors(design)
	if not errors.is_empty():
		if status_label:
			status_label.text = "VEHICLE DESIGN IS INVALID"
		return
	var new_name := "Vehicle %d" % (fleet_sims.size() + 1)
	var vehicle := _create_vehicle(design, new_name)
	vehicle.sim_time = sim.sim_time
	vehicle.time_warp = sim.time_warp
	fleet_sims.append(vehicle)
	_refresh_vehicle_selector()
	_switch_vehicle(fleet_sims.size() - 1)

func _show_new_vehicle_dialog() -> void:
	if not is_instance_valid(sim):
		return
	var options: Array[Dictionary] = []
	var current_design := {
		"name": sim.vehicle_name,
		"payload_mass": sim.payload_mass,
		"stages": sim.rocket_stages.duplicate(true)
	}
	options.append({
		"id": "current",
		"label": "Current vehicle design",
		"description": "Launch another copy of the currently selected spacecraft.",
		"design": current_design
	})
	for preset in RocketDesign.preset_options():
		var preset_id := str(preset.get("id", ""))
		var preset_design := RocketDesign.create_preset(preset_id)
		if RocketDesign.validation_errors(preset_design).is_empty():
			options.append({
				"id": preset_id,
				"label": str(preset.get("label", preset_id)),
				"description": RocketDesign.preset_description(preset_id),
				"design": preset_design
			})
	var saved_design_path := "user://rocket_design.json"
	if FileAccess.file_exists(saved_design_path):
		var saved_file := FileAccess.open(saved_design_path, FileAccess.READ)
		if saved_file != null:
			var saved_design: Variant = JSON.parse_string(saved_file.get_as_text())
			saved_file.close()
			if saved_design is Dictionary and RocketDesign.validation_errors(saved_design).is_empty():
				options.append({
					"id": "saved",
					"label": "Saved custom design",
					"description": "Launch the custom vehicle saved in the workshop.",
					"design": saved_design
				})
	var window := Window.new()
	window.title = "BUILD OR SELECT A VEHICLE"
	window.size = Vector2i(500, 360)
	window.min_size = Vector2i(420, 300)
	window.transient = true
	window.exclusive = true
	add_child(window)
	window.close_requested.connect(window.queue_free)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 12)
	window.add_child(layout)
	var heading := Label.new()
	heading.text = "SELECT A VEHICLE DESIGN"
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1))
	layout.add_child(heading)
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in options:
		selector.add_item(str(option.label))
		selector.set_item_metadata(selector.item_count - 1, option)
	layout.add_child(selector)
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(description)
	var launch_button := Button.new()
	launch_button.text = "LAUNCH SELECTED VEHICLE"
	launch_button.custom_minimum_size.y = 44
	layout.add_child(launch_button)
	selector.item_selected.connect(func(index: int):
		var selected: Dictionary = selector.get_item_metadata(index)
		description.text = str(selected.get("description", ""))
	)
	launch_button.pressed.connect(func():
		if selector.item_count == 0:
			return
		var selected: Dictionary = selector.get_item_metadata(selector.selected)
		var selected_design: Dictionary = selected.get("design", {}).duplicate(true)
		_launch_vehicle_design(selected_design)
		window.queue_free()
	)
	if not options.is_empty():
		selector.select(0)
		description.text = str(options[0].get("description", ""))
	else:
		launch_button.disabled = true
	window.popup_centered()

func _switch_vehicle(index: int) -> void:
	if index < 0 or index >= fleet_sims.size():
		return
	var requested_name: String = str(fleet_sims[index].vehicle_name)
	for link in docking_links:
		if str(link.get("child_name", "")) == requested_name:
			for parent_index in range(fleet_sims.size()):
				if fleet_sims[parent_index].vehicle_name == str(link.get("parent_name", "")):
					index = parent_index
					break
			break
	if is_instance_valid(sim):
		if not sim.autopilot_enabled:
			sim.thrust_key_down = false
		sim.input_enabled = false
		sim.visible = false
	active_vehicle_index = index
	sim = fleet_sims[index]
	sim.input_enabled = not _is_docked_child(sim.vehicle_name)
	sim.visible = true
	sim.time_warp = fleet_sims[0].time_warp
	rocket_design = {
		"name": sim.vehicle_name,
		"payload_mass": sim.payload_mass,
		"stages": sim.rocket_stages.duplicate(true)
	}
	_refresh_vehicle_selector()
	if status_label:
		if _is_docked_child(sim.vehicle_name):
			for link in docking_links:
				if str(link.get("child_name", "")) == sim.vehicle_name:
					status_label.text = "%s  •  DOCKED TO %s" % [sim.vehicle_name.to_upper(), str(link.get("parent_name", "")).to_upper()]
					return
		status_label.text = "%s  •  %s" % [sim.vehicle_name.to_upper(), sim.status_message]

func _refresh_vehicle_selector() -> void:
	if not is_instance_valid(vehicle_selector):
		return
	vehicle_selector.clear()
	for index in range(fleet_sims.size()):
		var vehicle: SimulationView = fleet_sims[index]
		vehicle_selector.add_item("%02d  •  %s" % [index + 1, vehicle.vehicle_name])
	vehicle_selector.select(active_vehicle_index)

func _find_vehicle_by_name(vehicle_name: String) -> SimulationView:
	for vehicle in fleet_sims:
		if vehicle.vehicle_name == vehicle_name:
			return vehicle
	return null

func _rename_vehicle(vehicle_name: String, requested_name: String) -> bool:
	var vehicle := _find_vehicle_by_name(vehicle_name)
	var clean_name := requested_name.strip_edges()
	if vehicle == null or clean_name.is_empty() or clean_name.length() > 32:
		return false
	for other in fleet_sims:
		if other != vehicle and other.vehicle_name.to_lower() == clean_name.to_lower():
			return false
	var previous_name := vehicle.vehicle_name
	vehicle.vehicle_name = clean_name
	for link in docking_links:
		if str(link.get("parent_name", "")) == previous_name:
			link["parent_name"] = clean_name
		if str(link.get("child_name", "")) == previous_name:
			link["child_name"] = clean_name
	_refresh_vehicle_selector()
	_sync_docked_vehicles()
	if vehicle == sim and is_instance_valid(status_label):
		status_label.text = "%s  •  %s" % [vehicle.vehicle_name.to_upper(), vehicle.status_message]
	return true

func _show_rename_vehicle_dialog(vehicle: SimulationView) -> void:
	var window := Window.new()
	window.title = "RENAME SPACECRAFT"
	window.size = Vector2i(380, 150)
	window.min_size = Vector2i(320, 130)
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	window.add_child(layout)
	var name_input := LineEdit.new()
	name_input.text = vehicle.vehicle_name
	name_input.max_length = 32
	name_input.placeholder_text = "Spacecraft name"
	layout.add_child(name_input)
	var save_button := Button.new()
	save_button.text = "SAVE NAME"
	layout.add_child(save_button)
	var message := Label.new()
	message.text = "Names must be unique and contain 1–32 characters."
	layout.add_child(message)
	save_button.pressed.connect(func():
		if _rename_vehicle(vehicle.vehicle_name, name_input.text):
			window.queue_free()
		else:
			message.text = "That name is invalid or already in use."
	)
	name_input.text_submitted.connect(func(_value: String):
		if _rename_vehicle(vehicle.vehicle_name, name_input.text):
			window.queue_free()
	)
	window.popup_centered()

func _show_fleet_management_panel() -> void:
	var window := Window.new()
	window.title = "SPACECRAFT FLEET"
	window.size = Vector2i(650, 520)
	window.min_size = Vector2i(480, 360)
	window.transient = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	window.add_child(layout)
	var heading := Label.new()
	heading.text = "FLEET OVERVIEW  •  %d SPACECRAFT" % fleet_sims.size()
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	layout.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 6)
	scroll.add_child(entries)
	for index in range(fleet_sims.size()):
		var vehicle: SimulationView = fleet_sims[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		entries.add_child(row)
		var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position)
		var altitude := maxf(0.0, float(body.get("distance", 0.0)) - float(body.get("radius", 0.0)))
		var fuel_capacity := vehicle.total_propellant_capacity()
		var fuel_percent := 100.0 * vehicle.total_propellant_remaining() / maxf(1.0, fuel_capacity)
		var state := "DOCKED" if _is_vehicle_docked(vehicle.vehicle_name) else ("LANDED" if vehicle.landed else ("CRASHED" if vehicle.crashed else ("AUTOPILOT" if vehicle.autopilot_enabled else "MANUAL")))
		var details := Label.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.text = "%s\n%s  •  %s  •  %.0f km altitude  •  %.0f%% fuel" % [vehicle.vehicle_name, state, str(body.get("name", "Deep space")), altitude / 1000.0, fuel_percent]
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(details)
		var select_button := Button.new()
		select_button.text = "SELECT"
		select_button.pressed.connect(func():
			_switch_vehicle(index)
			window.queue_free()
		)
		row.add_child(select_button)
		var rename_button := Button.new()
		rename_button.text = "RENAME"
		rename_button.pressed.connect(_show_rename_vehicle_dialog.bind(vehicle))
		row.add_child(rename_button)
	_add_button(layout, "CLOSE", func(): window.queue_free())
	window.popup_centered()


func _is_docked_child(vehicle_name: String) -> bool:
	for link in docking_links:
		if str(link.get("child_name", "")) == vehicle_name:
			return true
	return false

func _is_vehicle_docked(vehicle_name: String) -> bool:
	for link in docking_links:
		if str(link.get("parent_name", "")) == vehicle_name or str(link.get("child_name", "")) == vehicle_name:
			return true
	return false

func _are_docked(first_name: String, second_name: String) -> bool:
	for link in docking_links:
		var parent_name := str(link.get("parent_name", ""))
		var child_name := str(link.get("child_name", ""))
		if (parent_name == first_name and child_name == second_name) or (parent_name == second_name and child_name == first_name):
			return true
	return false

func _update_docked_masses() -> void:
	for vehicle in fleet_sims:
		vehicle.docked_mass = 0.0
	for link in docking_links:
		var parent := _find_vehicle_by_name(str(link.get("parent_name", "")))
		var child := _find_vehicle_by_name(str(link.get("child_name", "")))
		if parent != null and child != null:
			parent.docked_mass += child._current_vehicle_mass()

func _sync_docked_vehicles() -> void:
	for vehicle in fleet_sims:
		vehicle.docked_visuals.clear()
	for link in docking_links:
		var parent := _find_vehicle_by_name(str(link.get("parent_name", "")))
		var child := _find_vehicle_by_name(str(link.get("child_name", "")))
		if parent == null or child == null:
			continue
		var local_offset := Vector2(float(link.get("offset_x", 0.0)), float(link.get("offset_y", 0.0)))
		var world_offset := local_offset.rotated(parent.rotation_angle)
		parent.docked_visuals.append({
			"name": child.vehicle_name,
			"direction": world_offset.normalized(),
			"rotation": parent.rotation_angle
		})
		child.rocket_position = parent.rocket_position + world_offset
		child.velocity = parent.velocity
		child.rotation_angle = parent.rotation_angle
		child.sim_time = parent.sim_time
		child.landed = parent.landed
		child.crashed = parent.crashed
		child.landed_body_name = parent.landed_body_name
		child.landed_surface_normal = parent.landed_surface_normal
		child.autopilot_enabled = false
		child.guidance_enabled = false
		child.thrust_key_down = false
		child.docked_mass = 0.0

func _dock_vehicle(target_name: String) -> bool:
	var target := _find_vehicle_by_name(target_name)
	if target == null or sim == null or target == sim:
		return false
	if sim.landed or sim.crashed or target.landed or target.crashed:
		return false
	if _is_vehicle_docked(sim.vehicle_name) or _is_vehicle_docked(target.vehicle_name):
		return false
	var separation: float = target.rocket_position.distance_to(sim.rocket_position)
	var relative_speed: float = (target.velocity - sim.velocity).length()
	if separation > DOCKING_CAPTURE_DISTANCE or relative_speed > DOCKING_CAPTURE_SPEED:
		return false
	var local_offset: Vector2 = (target.rocket_position - sim.rocket_position).rotated(-sim.rotation_angle)
	docking_links.append({
		"parent_name": sim.vehicle_name,
		"child_name": target.vehicle_name,
		"offset_x": local_offset.x,
		"offset_y": local_offset.y
	})
	target.autopilot_enabled = false
	target.guidance_enabled = false
	target.thrust_key_down = false
	target.input_enabled = false
	_update_docked_masses()
	_sync_docked_vehicles()
	return true

func _undock_vehicle(target_name: String) -> bool:
	for index in range(docking_links.size()):
		var link: Dictionary = docking_links[index]
		if not ((str(link.parent_name) == sim.vehicle_name and str(link.child_name) == target_name) or (str(link.parent_name) == target_name and str(link.child_name) == sim.vehicle_name)):
			continue
		var child := _find_vehicle_by_name(str(link.get("child_name", "")))
		docking_links.remove_at(index)
		if child != null:
			child.input_enabled = child == sim
			child.docked_mass = 0.0
		_update_docked_masses()
		_sync_docked_vehicles()
		return true
	return false

func _transfer_fuel(from_name: String, to_name: String) -> float:
	if not _are_docked(from_name, to_name):
		return 0.0
	var donor := _find_vehicle_by_name(from_name)
	var recipient := _find_vehicle_by_name(to_name)
	if donor == null or recipient == null or donor.infinite_weightless_fuel or recipient.infinite_weightless_fuel:
		return 0.0
	var available_space := maxf(0.0, recipient.total_propellant_capacity() - recipient.total_propellant_remaining())
	var amount := minf(donor.total_propellant_remaining(), available_space)
	if amount <= 0.0:
		return 0.0
	var removed := donor.remove_propellant(amount)
	var added := recipient.add_propellant(removed)
	if added < removed:
		donor.add_propellant(removed - added)
	amount = added
	_update_docked_masses()
	_sync_docked_vehicles()
	return amount

func _build_flight_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(hud_root)

	var top := PanelContainer.new()
	top.position = Vector2(18, 18)
	top.custom_minimum_size = Vector2(330, 0)
	hud_root.add_child(top)
	var info := VBoxContainer.new()
	top.add_child(info)
	var heading := Label.new()
	heading.text = "GRAVITY  /  FLIGHT SYSTEMS"
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1))
	info.add_child(heading)
	status_label = Label.new()
	status_label.text = "READY  •  EARTH SYSTEM"
	info.add_child(status_label)

	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-245, 18)
	right.custom_minimum_size = Vector2(225, 0)
	hud_root.add_child(right)

	var slot_label := Label.new()
	slot_label.text = "SAVE SLOT"
	slot_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1))
	right.add_child(slot_label)
	var slot_picker := OptionButton.new()
	for slot in range(1, 9):
		slot_picker.add_item("SLOT %02d" % slot)
	slot_picker.select(save_slot - 1)
	slot_picker.item_selected.connect(func(index: int): save_slot = index + 1)
	right.add_child(slot_picker)

	var vehicle_label := Label.new()
	vehicle_label.text = "ACTIVE SPACECRAFT"
	vehicle_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1))
	right.add_child(vehicle_label)
	vehicle_selector = OptionButton.new()
	vehicle_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_selector.item_selected.connect(_switch_vehicle)
	right.add_child(vehicle_selector)
	_refresh_vehicle_selector()
	_add_button(right, "BUILD / LAUNCH VEHICLE", _show_new_vehicle_dialog)
	_add_button(right, "FLEET MANAGER", _show_fleet_management_panel)
	_add_button(right, "DOCKING & FUEL", _show_docking_panel)

	_add_button(right, "SOLAR SYSTEM VIEW  [M]", func(): sim.show_solar_system = not sim.show_solar_system)
	_add_button(right, "VELOCITY VECTOR  [V]", func(): sim.show_vectors = not sim.show_vectors)
	_add_button(right, "AUTOPILOT", _show_autopilot_panel)
	_add_button(right, "FLIGHT COMPUTER", _show_flight_computer)
	_add_button(right, "PREDICTED PATH  [P]", func():
		sim.show_predicted_trajectory = not sim.show_predicted_trajectory
		if sim.show_predicted_trajectory:
			sim._calculate_predicted_trajectory()
	)
	_add_button(right, "SAVE  [F5]", func(): _save_game(false))
	_add_button(right, "LOAD  [F9]", _load_game)
	_add_button(right, "AUTOSAVE HISTORY", _show_autosave_history)
	_add_button(right, "PAUSE  [ESC]", _pause_simulation)
	_add_button(right, "RETURN TO MENU", _confirm_menu)

	var bottom := Label.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 350
	bottom.offset_right = -20
	bottom.offset_top = -58
	bottom.offset_bottom = -8
	bottom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.text = "W ENGINE ON/OFF     S CUTOFF     X STAGE     Q / E GIMBAL     A / D ROTATE\nH GUIDANCE     V VELOCITY VECTOR     M SOLAR SYSTEM     P PREDICTED PATH     SPACE PAUSE     +/- WARP     F5 SAVE     F9 LOAD  •  REMAP IN SETTINGS"
	bottom.add_theme_font_size_override("font_size", 12)
	bottom.add_theme_color_override("font_color", Color(0.65, 0.77, 0.9))
	hud_root.add_child(bottom)

func _load_history_in_flight(path: String, window: Window) -> void:
	_load_game_from_path(path)
	window.queue_free()

func _show_autosave_history() -> void:
	var history_paths: Array[String] = _autosave_history_paths(save_slot)
	var window := Window.new()
	window.title = "AUTOSAVE HISTORY  •  SLOT %02d" % save_slot
	window.size = Vector2i(520, 520)
	window.min_size = Vector2i(420, 320)
	window.transient = true
	window.exclusive = true
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	window.add_child(layout)
	var heading := Label.new()
	heading.text = "RESTORE A PREVIOUS AUTOSAVE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(entries)
	if history_paths.is_empty():
		var empty := Label.new()
		empty.text = "No autosave history is available for this slot yet."
		entries.add_child(empty)
	for history_path in history_paths:
		var history_time: int = FileAccess.get_modified_time(history_path)
		var history_label := "LOAD  •  %s" % Time.get_datetime_string_from_unix_time(history_time, true)
		_add_button(entries, history_label, _load_history_in_flight.bind(history_path, window))
	_add_button(layout, "CLOSE", func(): window.queue_free())
	window.popup_centered()

func _show_autopilot_panel() -> void:
	var window := Window.new()
	window.title = "AUTOPILOT CONTROL"
	window.size = Vector2i(520, 720)
	window.min_size = Vector2i(460, 600)
	window.unresizable = false
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 18
	root.offset_right = -18
	root.offset_top = 18
	root.offset_bottom = -18
	window.add_child(root)
	var heading := Label.new()
	heading.text = "AUTOPILOT CONTROL"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(heading)
	var description := Label.new()
	description.text = "Choose a destination, configure automatic guidance and monitor fuel margins. Manual route design is available in the Flight Computer."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(description)
	var calculate_simulated_transfer := false
	var priority_label := Label.new()
	var initial_priority_percent := roundi(sim.autopilot_speed_priority * 100.0)
	priority_label.text = "TRAJECTORY PRIORITY  •  " + ("FUEL" if initial_priority_percent < 35 else "SPEED" if initial_priority_percent > 65 else "BALANCED") + "  (%d%% SPEED)" % initial_priority_percent
	root.add_child(priority_label)
	var priority_slider := HSlider.new()
	priority_slider.min_value = 0.0
	priority_slider.max_value = 100.0
	priority_slider.step = 5.0
	priority_slider.value = sim.autopilot_speed_priority * 100.0
	priority_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	priority_slider.value_changed.connect(func(value: float):
		sim.autopilot_speed_priority = value / 100.0
		priority_label.text = "TRAJECTORY PRIORITY  •  " + ("FUEL" if value < 35.0 else "SPEED" if value > 65.0 else "BALANCED") + "  (%d%% SPEED)" % roundi(value)
		calculate_simulated_transfer = false
	)
	root.add_child(priority_slider)
	var safety_label := Label.new()
	safety_label.text = "FUEL RESERVE"
	root.add_child(safety_label)
	var safety := OptionButton.new()
	safety.add_item("Conservative · 20% reserve", 20)
	safety.add_item("Normal · 10% reserve", 10)
	safety.add_item("Aggressive · 3% reserve", 3)
	var safety_index := 1
	for option_index in range(safety.item_count):
		if safety.get_item_id(option_index) == roundi(sim.autopilot_safety_margin * 100.0):
			safety_index = option_index
	safety.select(safety_index)
	safety.item_selected.connect(func(index: int):
		sim.autopilot_safety_margin = float(safety.get_item_id(index)) / 100.0
		calculate_simulated_transfer = false
	)
	root.add_child(safety)
	var planet_label := Label.new()
	planet_label.text = "DESTINATION PLANET"
	root.add_child(planet_label)
	var planet_dropdown := OptionButton.new()
	planet_dropdown.add_item("Earth", -2)
	for planet_index in range(FlightComputer.PLANET_TARGETS.size()):
		var planet: Dictionary = FlightComputer.PLANET_TARGETS[planet_index]
		planet_dropdown.add_item(str(planet.get("name", "Unknown")), planet_index)
	root.add_child(planet_dropdown)
	var moon_label := Label.new()
	moon_label.text = "MOON (OPTIONAL)"
	root.add_child(moon_label)
	var moon_dropdown := OptionButton.new()
	root.add_child(moon_dropdown)
	var rebuild_moon_options := func(parent_target_index: int) -> void:
		moon_dropdown.clear()
		moon_dropdown.add_item("Planet only", parent_target_index)
		if parent_target_index == -2:
			moon_dropdown.add_item("Moon")
			moon_dropdown.set_item_id(moon_dropdown.item_count - 1, -1)
		else:
			var parent_name := FlightComputer.target_body_name(parent_target_index)
			for satellite in FlightComputer.satellite_targets_for_host(parent_name):
				moon_dropdown.add_item(str(satellite.get("display_name", satellite.get("name", "Unknown"))), int(satellite.get("id", -1)))
		moon_dropdown.select(0)
		moon_dropdown.disabled = moon_dropdown.item_count <= 1
	var selected_target_index := func() -> int:
		return moon_dropdown.get_selected_id()
	planet_dropdown.select(0)
	rebuild_moon_options.call(planet_dropdown.get_selected_id())
	var orbit_altitude_label := Label.new()
	orbit_altitude_label.text = "TARGET ORBIT ALTITUDE"
	root.add_child(orbit_altitude_label)
	var orbit_altitude := SpinBox.new()
	orbit_altitude.min_value = 1.0
	orbit_altitude.max_value = 1000000000.0
	orbit_altitude.step = 1.0
	orbit_altitude.value = 200.0
	orbit_altitude.suffix = " km"
	root.add_child(orbit_altitude)
	var selected_orbit_feasible := true
	var selected_minimum_altitude_km := 1.0
	var update_orbit_altitude_limits := func():
		var body_name := FlightComputer.target_body_name(selected_target_index.call())
		var target_body: Dictionary = sim._surface_body_state(body_name)
		if target_body.is_empty():
			selected_orbit_feasible = false
			return
		var body_radius := float(target_body.get("radius", 0.0))
		var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(body_name, body_radius)
		var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(target_body.get("soi", 0.0)))
		selected_minimum_altitude_km = minimum_altitude / 1000.0
		selected_orbit_feasible = maximum_altitude >= minimum_altitude
		orbit_altitude.min_value = selected_minimum_altitude_km
		orbit_altitude.max_value = maxf(selected_minimum_altitude_km, maximum_altitude / 1000.0)
		orbit_altitude.editable = selected_orbit_feasible
		orbit_altitude.value = clampf(orbit_altitude.value, orbit_altitude.min_value, orbit_altitude.max_value)
	update_orbit_altitude_limits.call()
	var report_scroll := ScrollContainer.new()
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(report_scroll)
	var report := RichTextLabel.new()
	report.bbcode_enabled = false
	report.fit_content = true
	report.scroll_active = false
	report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.add_child(report)
	var calculate := Button.new()
	calculate.text = "CALCULATE FLIGHT PLAN"
	root.add_child(calculate)
	var launch_windows_button := Button.new()
	launch_windows_button.text = "SCAN NEXT 18 MONTHS FOR LAUNCH WINDOWS"
	root.add_child(launch_windows_button)
	var autopilot := Button.new()
	autopilot.text = "ENGAGE AUTOPILOT FOR SELECTED TARGET"
	root.add_child(autopilot)
	var landing := Button.new()
	landing.text = "ENGAGE POWERED LANDING"
	landing.pressed.connect(func():
		var selected_id: int = selected_target_index.call()
		var planet_index := selected_id
		var body_name := FlightComputer.target_body_name(planet_index)
		var current_body: Dictionary = sim._nearest_body_state(sim.rocket_position)
		if str(current_body.get("name", "")) != body_name:
			report.text += "\n\nLanding guidance requires you to be inside the selected body's sphere of influence."
			return
		if not bool(current_body.get("solid", false)):
			report.text += "\n\nGas giants have no solid landing surface in this simulation."
			return
		var relative_position: Vector2 = sim.rocket_position - current_body.position
		var relative_velocity: Vector2 = sim.velocity - current_body.velocity
		var local_orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(current_body.mass))
		if not bool(local_orbit.get("bound", false)):
			report.text += "\n\nFirst establish a stable orbit around %s." % body_name
			return
		sim.autopilot_enabled = true
		sim.autopilot_complete = false
		sim.autopilot_target_mode = "LAND"
		sim.autopilot_planet_index = planet_index
		sim.autopilot_phase = "LANDING_DESCENT"
		sim.autopilot_burn_remaining = 0.0
		sim.autopilot_burn_direction = Vector2.ZERO
		sim.autopilot_throttle = 0.0
		sim.guidance_enabled = true
		sim.thrust_key_down = false
		report.text += "\n\nPowered landing guidance engaged for %s. It will manage braking and descent; touchdown still depends on available thrust and fuel." % body_name
	)
	root.add_child(landing)
	var cancel := Button.new()
	cancel.text = "CLOSE"
	cancel.pressed.connect(window.queue_free)
	root.add_child(cancel)
	var update_report := func() -> void:
		var selected_id: int = selected_target_index.call()
		var current_body: Dictionary = sim._nearest_body_state(sim.rocket_position)
		landing.disabled = sim.crashed
		autopilot.disabled = sim.crashed or not selected_orbit_feasible
		var current_position: Vector2 = sim.rocket_position - current_body.position
		var current_velocity: Vector2 = sim.velocity - current_body.velocity
		var state := FlightComputer.orbital_state(current_position, current_velocity, FlightComputer.G * float(current_body.mass))
		var current_altitude: float = float(current_body.distance) - float(current_body.radius)
		var text_lines := PackedStringArray()
		var remaining_delta_v := FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if sim.infinite_weightless_fuel else FlightComputer.available_delta_v(rocket_design, sim.stage_index, sim.fuel)
		var required_delta_v := 0.0
		var mission_valid := true
		var has_estimated_plan := false
		var within_current_sphere := float(current_body.get("distance", INF)) <= float(current_body.get("soi", 0.0))
		var current_minimum_safe_altitude := FlightComputer.minimum_safe_orbit_altitude(str(current_body.get("name", "")), float(current_body.get("radius", 0.0)))
		var stable_departure_state := not within_current_sphere or (bool(state.get("bound", false)) and float(state.get("periapsis", 0.0)) > float(current_body.radius) + current_minimum_safe_altitude)
		var destination_name := FlightComputer.target_body_name(selected_id)
		var destination_is_local := within_current_sphere and str(current_body.get("name", "")) == destination_name
		var target_altitude_m := orbit_altitude.value * 1000.0
		text_lines.append("CURRENT FLIGHT STATE")
		text_lines.append("Current body: %s" % str(current_body.name))
		text_lines.append("Altitude: %.1f km" % (current_altitude / 1000.0))
		text_lines.append("Speed: %.0f m/s" % current_velocity.length())
		text_lines.append("Apoapsis: %s" % ("UNBOUND" if not bool(state.get("bound", false)) else "%.1f km" % ((float(state.get("apoapsis", 0.0)) - float(current_body.radius)) / 1000.0)))
		text_lines.append("Periapsis: %.1f km" % ((float(state.get("periapsis", 0.0)) - float(current_body.radius)) / 1000.0))
		text_lines.append("")
		text_lines.append("TARGET ORBIT")
		text_lines.append("Body: %s" % destination_name)
		text_lines.append("Altitude: %.0f km" % (target_altitude_m / 1000.0))
		var target_body: Dictionary = sim._surface_body_state(destination_name)
		var target_radius := float(target_body.get("radius", 0.0)) + target_altitude_m
		text_lines.append("Circular speed: %.0f m/s" % FlightComputer.circular_orbit_speed(target_radius, FlightComputer.G * float(target_body.get("mass", 0.0))))
		if not selected_orbit_feasible:
			mission_valid = false
			text_lines.append("NO STABLE ORBIT FITS INSIDE THIS BODY'S SPHERE OF INFLUENCE.")
		if destination_is_local:
			if stable_departure_state:
				var local_orbit_plan := FlightComputer.target_radius_burn(current_position, current_velocity, target_radius, FlightComputer.G * float(current_body.mass))
				text_lines.append("Target-orbit transfer: %.0f m/s Δv" % float(local_orbit_plan.get("delta_v", 0.0)))
				required_delta_v = float(local_orbit_plan.get("delta_v", 0.0))
				has_estimated_plan = bool(local_orbit_plan.get("valid", false))
			else:
				text_lines.append("Autopilot will launch and insert into the selected orbit around the current body.")
		elif not stable_departure_state:
			var current_maximum_stable_altitude := FlightComputer.maximum_stable_orbit_altitude(float(current_body.get("radius", 0.0)), float(current_body.get("soi", 0.0)))
			if current_maximum_stable_altitude < current_minimum_safe_altitude:
				text_lines.append("This body has no stable parking orbit inside its sphere of influence; autopilot will use direct escape.")
			else:
				var parking_altitude := clampf(200000.0, current_minimum_safe_altitude, current_maximum_stable_altitude)
				text_lines.append("Autopilot will first establish a %.0f km parking orbit around %s." % [parking_altitude / 1000.0, str(current_body.get("name", "the current body"))])
				text_lines.append("Calculate a transfer after reaching that parking orbit for a trajectory estimate.")
		elif not calculate_simulated_transfer:
			text_lines.append("Press CALCULATE FLIGHT PLAN to simulate trajectories from the current orbit.")
		else:
			var available_for_transfer: float = remaining_delta_v * (1.0 - sim.autopilot_safety_margin)
			var simulated_plan := FlightComputer.simulated_transfer_search_precise(sim.rocket_position_precise, sim.velocity, sim.sim_time, selected_id, available_for_transfer, sim.autopilot_speed_priority, false, target_altitude_m)
			if bool(simulated_plan.get("valid", false)):
				text_lines.append("Departure manoeuvre: %.0f m/s Δv" % float(simulated_plan.get("departure_delta_v", 0.0)))
				text_lines.append("Arrival capture + circularisation: %.0f m/s Δv" % float(simulated_plan.get("capture_delta_v", 0.0)))
				text_lines.append("Total simulated Δv: %.0f m/s" % float(simulated_plan.get("total_delta_v", 0.0)))
				text_lines.append("Predicted flight time: %.1f days" % (float(simulated_plan.get("transfer_time", 0.0)) / 86400.0))
				text_lines.append("Closest approach: %.0f km" % (float(simulated_plan.get("closest_approach", 0.0)) / 1000.0))
				text_lines.append("Candidate trajectories simulated: %d" % int(simulated_plan.get("search_candidates", 0)))
				required_delta_v = float(simulated_plan.get("total_delta_v", 0.0))
				has_estimated_plan = true
			else:
				mission_valid = false
				text_lines.append("NO FEASIBLE TRAJECTORY FOUND")
				text_lines.append(str(simulated_plan.get("reason", "No candidate passed the trajectory and capture checks.")))
			text_lines.append("Search estimates use impulsive burns; finite engine-burn and atmospheric losses are not included.")
		text_lines.append("")
		text_lines.append("VEHICLE FUEL FEASIBILITY")
		text_lines.append("Remaining ideal vehicle Δv: %s" % ("UNLIMITED • MASSLESS FUEL" if sim.infinite_weightless_fuel else "%.2f km/s" % (remaining_delta_v / 1000.0)))
		var available_delta_v: float = remaining_delta_v * (1.0 - sim.autopilot_safety_margin)
		var margin: float = available_delta_v - required_delta_v
		if has_estimated_plan:
			text_lines.append("Estimated mission budget: %.2f km/s" % (required_delta_v / 1000.0))
			if not sim.infinite_weightless_fuel:
				text_lines.append("Selected fuel reserve: %.0f%%" % (sim.autopilot_safety_margin * 100.0))
				text_lines.append("Available Δv after reserve: %.2f km/s" % (available_delta_v / 1000.0))
				text_lines.append("Margin after reserve: %+.2f km/s" % (margin / 1000.0))
		if not mission_valid:
			text_lines.append("STATUS: NO VALID FLIGHT PLAN")
		elif sim.infinite_weightless_fuel:
			text_lines.append("STATUS: INFINITE MASSLESS PROPELLANT ENABLED")
		elif remaining_delta_v <= 0.0:
			text_lines.append("STATUS: NO USABLE PROPELLANT")
		elif not has_estimated_plan:
			text_lines.append("STATUS: AWAITING DEPARTURE ORBIT OR FLIGHT PLAN")
		elif margin >= 0.0:
			text_lines.append("STATUS: DELTA-V BUDGET PASSES")
		elif remaining_delta_v >= required_delta_v:
			text_lines.append("STATUS: MARGINAL - SELECTED RESERVE NOT MET")
		else:
			text_lines.append("STATUS: INSUFFICIENT DELTA-V")
		text_lines.append("Ideal rocket-equation estimate only. Real ascent, steering and correction losses can make a nominal pass fail.")
		report.text = "\n".join(text_lines)
	priority_slider.value_changed.connect(func(_value: float):
		calculate_simulated_transfer = false
		update_report.call()
	)
	safety.item_selected.connect(func(_index: int):
		calculate_simulated_transfer = false
		update_report.call()
	)
	calculate.pressed.connect(func():
		calculate_simulated_transfer = true
		update_report.call()
	)
	launch_windows_button.pressed.connect(func():
		var destination_index: int = selected_target_index.call()
		var body: Dictionary = sim._nearest_body_state(sim.rocket_position)
		var relative_position: Vector2 = sim.rocket_position - body.position
		var relative_velocity: Vector2 = sim.velocity - body.velocity
		var orbit_state := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(body.mass))
		var inside_body_soi := float(body.get("distance", INF)) <= float(body.get("soi", 0.0))
		var minimum_safe_altitude := FlightComputer.minimum_safe_orbit_altitude(str(body.get("name", "")), float(body.get("radius", 0.0)))
		var maximum_stable_altitude := FlightComputer.maximum_stable_orbit_altitude(float(body.get("radius", 0.0)), float(body.get("soi", 0.0)))
		var stable_parking_orbit := bool(orbit_state.get("bound", false)) and float(orbit_state.get("periapsis", 0.0)) > float(body.get("radius", 0.0)) + minimum_safe_altitude and float(orbit_state.get("apoapsis", INF)) < float(body.get("radius", 0.0)) + maximum_stable_altitude
		if sim.landed or (inside_body_soi and not stable_parking_orbit):
			report.text += "\n\nLaunch-window scanning requires a safe, stable parking orbit around the current body, or a spacecraft already in deep space."
			return
		launch_windows_button.disabled = true
		report.text = "SCANNING FUTURE DEPARTURE DATES...\nThis simulates coarse candidate transfers and may take a little while."
		await get_tree().process_frame
		var available: float = FlightComputer.INFINITE_FUEL_PLANNING_DELTA_V if sim.infinite_weightless_fuel else FlightComputer.available_delta_v(rocket_design, sim.stage_index, sim.fuel) * (1.0 - sim.autopilot_safety_margin)
		var windows := FlightComputer.scan_launch_windows(sim.rocket_position, sim.velocity, sim.sim_time, destination_index, available, sim.autopilot_speed_priority, 540, 30, orbit_altitude.value * 1000.0, sim.rocket_position_precise)
		launch_windows_button.disabled = false
		if not bool(windows.get("valid", false)):
			report.text = "NO FEASIBLE WINDOWS FOUND\n" + str(windows.get("reason", "No valid transfer was found."))
		else:
			var best: Dictionary = windows.best
			var destination := FlightComputer.target_body_name(destination_index)
			report.text = "LAUNCH WINDOW SEARCH: %s\nDates sampled: %d\nBest refined departure: in %.1f days\nDeparture Δv: %.0f m/s\nCapture Δv: %.0f m/s\nTotal Δv: %.0f m/s\nTransfer time: %.1f days\n\nThis is the best of the sampled dates and burn candidates, not a guaranteed global optimum. Use CALCULATE FLIGHT PLAN at the selected date for a higher-resolution search." % [destination, int(windows.dates_checked), float(best.departure_wait_days), float(best.departure_delta_v), float(best.capture_delta_v), float(best.total_delta_v), float(best.transfer_time) / 86400.0]
	)
	planet_dropdown.item_selected.connect(func(_index: int):
		rebuild_moon_options.call(planet_dropdown.get_selected_id())
		update_orbit_altitude_limits.call()
		calculate_simulated_transfer = false
		update_report.call()
	)
	moon_dropdown.item_selected.connect(func(_index: int):
		update_orbit_altitude_limits.call()
		calculate_simulated_transfer = false
		update_report.call()
	)
	orbit_altitude.value_changed.connect(func(_value: float):
		calculate_simulated_transfer = false
		update_report.call()
	)
	autopilot.pressed.connect(func():
		var selected_id: int = selected_target_index.call()
		sim.autopilot_enabled = true
		sim.autopilot_complete = false
		sim.autopilot_target_altitude = orbit_altitude.value * 1000.0
		sim.autopilot_target_mode = "ORBIT"
		sim.autopilot_planet_index = selected_id
		sim.autopilot_burn_remaining = 0.0
		sim.autopilot_apsis_correction_armed = true
		sim.autopilot_apsis_correction_angle = 0.0
		sim.autopilot_burn_direction = Vector2.ZERO
		sim.autopilot_transfer_corrections = 0
		var current_body: Dictionary = sim._nearest_body_state(sim.rocket_position)
		var relative_position: Vector2 = sim.rocket_position - current_body.position
		sim.autopilot_apsis_correction_angle = relative_position.angle()
		var relative_velocity: Vector2 = sim.velocity - current_body.velocity
		var current_orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(current_body.mass))
		var target_state: Dictionary = sim._autopilot_target_state()
		var target_distance: float = sim._relative_position_to_body(target_state).length() if not target_state.is_empty() else INF
		var within_current_sphere := float(current_body.get("distance", INF)) <= float(current_body.get("soi", 0.0))
		var destination_is_local := within_current_sphere and str(current_body.get("name", "")) == FlightComputer.target_body_name(selected_id)
		var target_is_near: bool = not target_state.is_empty() and target_distance <= float(target_state.get("soi", 0.0)) and str(sim._nearest_body_state(sim.rocket_position).get("name", "")) == FlightComputer.target_body_name(selected_id)
		var current_altitude := float(current_body.distance) - float(current_body.radius)
		var current_minimum_safe_altitude := FlightComputer.minimum_safe_orbit_altitude(str(current_body.get("name", "")), float(current_body.get("radius", 0.0)))
		var stable_current_orbit := not within_current_sphere or (bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current_body.radius) + current_minimum_safe_altitude)
		if target_is_near and not sim.landed and not stable_current_orbit:
			sim.autopilot_phase = "ARRIVAL_APPROACH"
		elif sim.landed or (current_altitude < current_minimum_safe_altitude and not stable_current_orbit):
			sim.autopilot_phase = "ASCENT"
		elif destination_is_local:
			sim.autopilot_phase = "CIRCULARISE"
		else:
			sim.autopilot_phase = "PLAN_TRANSFER"
		sim.guidance_enabled = true
		sim.thrust_key_down = sim.landed or sim.autopilot_phase == "ASCENT"
		report.text += "\n\nAUTOPILOT ENGAGED. Target: %s orbit at %.0f km altitude. Departure and transfer phases will be selected from your current body and orbit." % [FlightComputer.target_body_name(selected_id), sim.autopilot_target_altitude / 1000.0]
	)
	update_report.call()
	window.popup_centered()

func _show_flight_computer() -> void:
	var planner = RoutePlanner.new()
	add_child(planner)
	planner.configure(sim, rocket_design)
	var screen_size := DisplayServer.screen_get_size()
	planner.size = Vector2i(mini(980, screen_size.x - 40), mini(820, screen_size.y - 80))
	planner.position = Vector2i(maxi(20, screen_size.x - planner.size.x - 24), 40)
	planner.popup()

func _show_docking_panel() -> void:
	var window := Window.new()
	window.title = "DOCKING AND FUEL TRANSFER"
	window.size = Vector2i(500, 520)
	window.min_size = Vector2i(420, 420)
	window.transient = true
	window.exclusive = true
	add_child(window)
	window.close_requested.connect(window.queue_free)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 12)
	window.add_child(layout)
	var intro := Label.new()
	intro.text = "Rendezvous with another spacecraft, match its velocity and dock within the capture limits."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(intro)
	var parent_name: String = str(sim.vehicle_name)
	var target_label := Label.new()
	target_label.text = "OTHER SPACECRAFT"
	target_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1))
	layout.add_child(target_label)
	var target_selector := OptionButton.new()
	target_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for vehicle in fleet_sims:
		if vehicle.vehicle_name != parent_name:
			target_selector.add_item(vehicle.vehicle_name)
			target_selector.set_item_metadata(target_selector.item_count - 1, vehicle.vehicle_name)
	layout.add_child(target_selector)
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 72
	layout.add_child(status)
	var dock_button := Button.new()
	dock_button.text = "DOCK"
	dock_button.custom_minimum_size.y = 44
	layout.add_child(dock_button)
	var undock_button := Button.new()
	undock_button.text = "UNDOCK"
	undock_button.custom_minimum_size.y = 44
	layout.add_child(undock_button)
	var fuel_heading := Label.new()
	fuel_heading.text = "FUEL TRANSFER"
	fuel_heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1))
	layout.add_child(fuel_heading)
	var fuel_direction := OptionButton.new()
	fuel_direction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(fuel_direction)
	var transfer_button := Button.new()
	transfer_button.text = "TRANSFER AVAILABLE FUEL"
	transfer_button.custom_minimum_size.y = 44
	layout.add_child(transfer_button)
	var fuel_status := Label.new()
	fuel_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(fuel_status)
	var refresh_fuel_direction := func(target_name: String) -> void:
		fuel_direction.clear()
		fuel_direction.add_item("%s  →  %s" % [parent_name, target_name])
		fuel_direction.set_item_metadata(0, {"from": parent_name, "to": target_name})
		fuel_direction.add_item("%s  →  %s" % [target_name, parent_name])
		fuel_direction.set_item_metadata(1, {"from": target_name, "to": parent_name})
		fuel_direction.select(0)
	var refresh_panel := func() -> void:
		if sim.vehicle_name != parent_name:
			status.text = "The selected spacecraft changed. Close this panel and reopen it for the new vehicle."
			dock_button.disabled = true
			undock_button.disabled = true
			transfer_button.disabled = true
			fuel_direction.disabled = true
			return
		if target_selector.item_count == 0:
			status.text = "Launch another vehicle before attempting to dock."
			dock_button.disabled = true
			undock_button.disabled = true
			transfer_button.disabled = true
			fuel_direction.disabled = true
			return
		var target_name := str(target_selector.get_item_metadata(target_selector.selected))
		var target := _find_vehicle_by_name(target_name)
		if target == null:
			status.text = "The selected spacecraft is no longer available."
			dock_button.disabled = true
			undock_button.disabled = true
			transfer_button.disabled = true
			return
		var separation: float = sim.rocket_position.distance_to(target.rocket_position)
		var relative_speed: float = (sim.velocity - target.velocity).length()
		var docked := _are_docked(parent_name, target_name)
		var available_to_dock: bool = not docked and not _is_vehicle_docked(parent_name) and not _is_vehicle_docked(target_name) and not sim.landed and not sim.crashed and not target.landed and not target.crashed and separation <= DOCKING_CAPTURE_DISTANCE and relative_speed <= DOCKING_CAPTURE_SPEED
		if docked:
			status.text = "DOCKED  •  %s\nCombined mass is included in the parent spacecraft's flight dynamics." % target_name
		elif available_to_dock:
			status.text = "DOCKING CONDITIONS MET\nRange: %.1f m  •  Relative speed: %.2f m/s" % [separation, relative_speed]
		else:
			status.text = "Range: %.1f m / %.0f m\nRelative speed: %.2f / %.2f m/s\nBoth spacecraft must be free-flying and undocked." % [separation, DOCKING_CAPTURE_DISTANCE, relative_speed, DOCKING_CAPTURE_SPEED]
		dock_button.disabled = not available_to_dock
		undock_button.disabled = not docked
		fuel_direction.disabled = not docked
		transfer_button.disabled = not docked
		if docked and fuel_direction.item_count > 0:
			var direction: Dictionary = fuel_direction.get_item_metadata(fuel_direction.selected)
			var donor := _find_vehicle_by_name(str(direction.get("from", "")))
			var recipient := _find_vehicle_by_name(str(direction.get("to", "")))
			if donor == null or recipient == null:
				transfer_button.disabled = true
				fuel_status.text = "Fuel transfer unavailable."
			else:
				var available := donor.total_propellant_remaining()
				var room := maxf(0.0, recipient.total_propellant_capacity() - recipient.total_propellant_remaining())
				var amount := minf(available, room)
				transfer_button.disabled = amount <= 0.0 or donor.infinite_weightless_fuel or recipient.infinite_weightless_fuel
				fuel_status.text = "Available: %.0f kg  •  Receiver space: %.0f kg across remaining stages" % [available, room]
		else:
			fuel_status.text = "Dock spacecraft to enable transfer. Transfers fill the receiver's active tank first, then its later stages."
	var target_changed := func(_index: int) -> void:
		var target_name := str(target_selector.get_item_metadata(target_selector.selected))
		refresh_fuel_direction.call(target_name)
		refresh_panel.call()
	target_selector.item_selected.connect(target_changed)
	fuel_direction.item_selected.connect(func(_index: int): refresh_panel.call())
	dock_button.pressed.connect(func():
		if sim.vehicle_name != parent_name:
			refresh_panel.call()
			return
		var target_name := str(target_selector.get_item_metadata(target_selector.selected))
		if _dock_vehicle(target_name):
			fuel_status.text = "Docking complete."
		refresh_panel.call()
	)
	undock_button.pressed.connect(func():
		if sim.vehicle_name != parent_name:
			refresh_panel.call()
			return
		var target_name := str(target_selector.get_item_metadata(target_selector.selected))
		if _undock_vehicle(target_name):
			fuel_status.text = "Spacecraft undocked."
		refresh_panel.call()
	)
	transfer_button.pressed.connect(func():
		if sim.vehicle_name != parent_name:
			refresh_panel.call()
			return
		var direction: Dictionary = fuel_direction.get_item_metadata(fuel_direction.selected)
		var amount := _transfer_fuel(str(direction.get("from", "")), str(direction.get("to", "")))
		fuel_status.text = "Transferred %.0f kg of propellant." % amount if amount > 0.0 else "No fuel could be transferred."
		refresh_panel.call()
	)
	if target_selector.item_count > 0:
		target_selector.select(0)
		refresh_fuel_direction.call(str(target_selector.get_item_metadata(0)))
	else:
		fuel_direction.disabled = true
	refresh_panel.call()
	var refresh_timer := Timer.new()
	refresh_timer.wait_time = 0.25
	refresh_timer.timeout.connect(refresh_panel)
	window.add_child(refresh_timer)
	refresh_timer.start()
	window.popup_centered()

func _pause_simulation() -> void:
	if sim:
		var pause_state: bool = not bool(sim.paused)
		for vehicle in fleet_sims:
			vehicle.paused = pause_state
		if status_label:
			status_label.text = "PAUSED" if pause_state else "FLIGHT ACTIVE"

func _confirm_menu() -> void:
	_save_game(true)
	_build_menu()

func _autosave_history_paths(slot: int) -> Array[String]:
	var directory := "%s/history/slot_%02d" % [SAVE_DIR, slot]
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		return paths
	for filename in DirAccess.get_files_at(directory):
		if filename.begins_with("auto_") and filename.ends_with(".json"):
			paths.append(directory.path_join(filename))
	paths.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b)
	)
	return paths

func _prune_autosave_history(slot: int, keep_count: int = 10) -> void:
	var paths: Array[String] = _autosave_history_paths(slot)
	for i in range(keep_count, paths.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(paths[i]))

func _save_game(automatic: bool) -> void:
	if not sim:
		return

	var data: Dictionary = sim.get_save_data()
	var saved_vehicles: Array[Dictionary] = []
	for vehicle in fleet_sims:
		saved_vehicles.append({
			"name": vehicle.vehicle_name,
			"state": vehicle.get_save_data()
		})
	data["vehicles"] = saved_vehicles
	data["active_vehicle_index"] = active_vehicle_index
	data["docking_links"] = docking_links.duplicate(true)
	data["realism"] = realism
	data["world_scale"] = world_scale
	data["career_enabled"] = career_enabled
	data["slot"] = save_slot

	if automatic:
		var history_directory := "%s/history/slot_%02d" % [SAVE_DIR, save_slot]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(history_directory))
		var history_name := "auto_%d_%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		var history_path := history_directory.path_join(history_name)
		var history_file := FileAccess.open(history_path, FileAccess.WRITE)
		if history_file:
			history_file.store_string(JSON.stringify(data, "\t"))
			history_file.close()
			_prune_autosave_history(save_slot)
		else:
			if status_label:
				status_label.text = "AUTOSAVE HISTORY COULD NOT BE WRITTEN"

	var path := "%s/slot_%02d.json" % [SAVE_DIR, save_slot]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		if status_label:
			status_label.text = ("AUTOSAVED" if automatic else "SAVED") + "  •  SLOT %02d" % save_slot
	else:
		if status_label:
			status_label.text = "SAVE COULD NOT BE WRITTEN"

func _load_menu_path(slot: int, path: String) -> void:
	save_slot = slot
	_start_flight()
	_load_game_from_path(path)

func _load_game() -> void:
	var path := "%s/slot_%02d.json" % [SAVE_DIR, save_slot]
	_load_game_from_path(path)

func _load_game_from_path(path: String) -> void:
	if not FileAccess.file_exists(path):
		if status_label:
			status_label.text = "SAVE NOT FOUND"
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if status_label:
			status_label.text = "SAVE COULD NOT BE OPENED"
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not sim:
		if status_label:
			status_label.text = "SAVE DATA IS INVALID  •  SLOT %02d" % save_slot
		return
	var loaded_realism := str(parsed.get("realism", realism))
	var loaded_world_scale := str(parsed.get("world_scale", world_scale))
	var loaded_career := bool(parsed.get("career_enabled", career_enabled))
	var saved_vehicles: Variant = parsed.get("vehicles", null)
	if saved_vehicles is Array and not saved_vehicles.is_empty():
		var loaded_fleet: Array = []
		for entry in saved_vehicles:
			if not entry is Dictionary or not entry.get("state", {}) is Dictionary:
				for vehicle in loaded_fleet:
					vehicle.queue_free()
				if status_label:
					status_label.text = "SAVE CONTAINS INVALID VEHICLE DATA"
				return
			var state: Dictionary = entry.state
			var saved_design: Variant = state.get("rocket_design", null)
			if not saved_design is Dictionary or not RocketDesign.validation_errors(saved_design).is_empty():
				for vehicle in loaded_fleet:
					vehicle.queue_free()
				if status_label:
					status_label.text = "SAVE CONTAINS AN INVALID VEHICLE DESIGN"
				return
			realism = loaded_realism
			world_scale = loaded_world_scale
			career_enabled = loaded_career
			var vehicle := _create_vehicle(saved_design, str(entry.get("name", "Vehicle %d" % (loaded_fleet.size() + 1))), state)
			if vehicle == null:
				for loaded_vehicle in loaded_fleet:
					loaded_vehicle.queue_free()
				realism = str(parsed.get("realism", realism))
				world_scale = str(parsed.get("world_scale", world_scale))
				career_enabled = bool(parsed.get("career_enabled", career_enabled))
				if status_label:
					status_label.text = "SAVE CONTAINS INVALID VEHICLE STATE"
				return
			loaded_fleet.append(vehicle)
		for vehicle in fleet_sims:
			vehicle.queue_free()
		fleet_sims = loaded_fleet
		active_vehicle_index = clampi(int(parsed.get("active_vehicle_index", 0)), 0, fleet_sims.size() - 1)
		realism = loaded_realism
		world_scale = loaded_world_scale
		career_enabled = loaded_career
		fleet_time_backlog = 0.0
		_switch_vehicle(active_vehicle_index)
	else:
		var saved_design: Variant = parsed.get("rocket_design", null)
		if not saved_design is Dictionary or not RocketDesign.validation_errors(saved_design).is_empty():
			if status_label:
				status_label.text = "SAVE DATA IS INVALID  •  SLOT %02d" % save_slot
			return
		if not sim.load_save_data(parsed):
			if status_label:
				status_label.text = "SAVE DATA IS INVALID  •  SLOT %02d" % save_slot
			return
		realism = loaded_realism
		world_scale = loaded_world_scale
		career_enabled = loaded_career
		rocket_design = saved_design
		sim.vehicle_name = str(parsed.get("vehicle_name", "Vehicle 1"))
		fleet_sims = [sim]
		active_vehicle_index = 0
		_switch_vehicle(0)
	docking_links.clear()
	var saved_docking_links: Variant = parsed.get("docking_links", [])
	if saved_docking_links is Array:
		var linked_names: Dictionary = {}
		for saved_link in saved_docking_links:
			if not saved_link is Dictionary:
				continue
			var parent_name := str(saved_link.get("parent_name", ""))
			var child_name := str(saved_link.get("child_name", ""))
			var offset_x: Variant = saved_link.get("offset_x", null)
			var offset_y: Variant = saved_link.get("offset_y", null)
			if parent_name.is_empty() or child_name.is_empty() or parent_name == child_name:
				continue
			if _find_vehicle_by_name(parent_name) == null or _find_vehicle_by_name(child_name) == null:
				continue
			if linked_names.has(parent_name) or linked_names.has(child_name):
				continue
			if not (offset_x is float or offset_x is int) or not (offset_y is float or offset_y is int):
				continue
			if not is_finite(float(offset_x)) or not is_finite(float(offset_y)):
				continue
			docking_links.append({
				"parent_name": parent_name,
				"child_name": child_name,
				"offset_x": float(offset_x),
				"offset_y": float(offset_y)
			})
			linked_names[parent_name] = true
			linked_names[child_name] = true
	_update_docked_masses()
	_sync_docked_vehicles()
	_switch_vehicle(active_vehicle_index)
	infinite_weightless_fuel = sim.infinite_weightless_fuel
	for vehicle in fleet_sims:
		vehicle.realism = realism
		vehicle.world_scale = world_scale
		vehicle.career_enabled = career_enabled
		vehicle.time_warp = sim.time_warp
	if status_label:
		status_label.text = "LOADED  •  SLOT %02d  •  %d VEHICLES" % [save_slot, fleet_sims.size()]

func _add_button(parent: Node, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 15)
	button.pressed.connect(callback)
	parent.add_child(button)

func _add_setting_label(parent: Node, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", Color(0.4, 0.72, 0.94))
	parent.add_child(label)

func _add_spacer(parent: Node, amount: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = amount
	parent.add_child(spacer)

func _quit_game() -> void:
	get_tree().quit()

class RocketPreview:
	extends Control
	var design: Dictionary = {}

	func _draw() -> void:
		var stages: Array = design.get("stages", [])
		if stages.is_empty():
			return
		var center_x := size.x * 0.5
		var top := 18.0
		var available_height := maxf(100.0, size.y - 70.0)
		var payload_height := clampf(available_height * 0.13, 32.0, 52.0)
		var total_stage_mass := 0.0
		for stage in stages:
			total_stage_mass += float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
		var stage_heights: Array[float] = []
		for stage in stages:
			var stage_mass := float(stage.get("dry_mass", 0.0)) + float(stage.get("fuel_capacity", 0.0))
			stage_heights.append(clampf((available_height - payload_height) * stage_mass / maxf(1.0, total_stage_mass), 34.0, 86.0))
		var total_height := payload_height
		for stage_height in stage_heights:
			total_height += stage_height
		var scale_height := minf(1.0, available_height / maxf(1.0, total_height))
		payload_height *= scale_height
		for index in range(stage_heights.size()):
			stage_heights[index] *= scale_height
		var rocket_width := minf(92.0, size.x * 0.34)
		var payload_type := str(design.get("payload_type", "probe"))
		var payload_rect := Rect2(center_x - rocket_width * 0.32, top + 16.0, rocket_width * 0.64, payload_height - 16.0)
		if payload_type == "satellite":
			draw_rect(Rect2(center_x - rocket_width * 0.72, top + 22.0, rocket_width * 0.4, 12.0), Color(0.16, 0.42, 0.72))
			draw_rect(Rect2(center_x + rocket_width * 0.32, top + 22.0, rocket_width * 0.4, 12.0), Color(0.16, 0.42, 0.72))
			draw_rect(payload_rect, Color(0.78, 0.7, 0.42))
		elif payload_type == "crew":
			draw_colored_polygon(PackedVector2Array([Vector2(center_x, top), Vector2(center_x - rocket_width * 0.32, top + payload_height), Vector2(center_x + rocket_width * 0.32, top + payload_height)]), Color(0.82, 0.86, 0.92))
			draw_circle(Vector2(center_x, top + payload_height * 0.62), 7.0, Color(0.2, 0.52, 0.72))
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(center_x, top), Vector2(center_x - rocket_width * 0.32, top + payload_height), Vector2(center_x + rocket_width * 0.32, top + payload_height)]), Color(0.78, 0.84, 0.9))
			draw_rect(Rect2(center_x - 8.0, top + payload_height * 0.62, 16.0, 10.0), Color(0.22, 0.52, 0.72))
		var y := top + payload_height
		for i in range(stages.size() - 1, -1, -1):
			var stage: Dictionary = stages[i]
			var stage_height: float = stage_heights[i]
			var stage_width := rocket_width * (0.9 - 0.18 * float(i) / float(maxi(1, stages.size() - 1)))
			var stage_rect := Rect2(center_x - stage_width * 0.5, y, stage_width, stage_height)
			draw_rect(stage_rect, Color(0.34, 0.57, 0.72))
			draw_rect(Rect2(stage_rect.position + Vector2(5.0, 5.0), Vector2(stage_width - 10.0, stage_height * 0.58)), Color(0.48, 0.68, 0.78))
			draw_rect(Rect2(center_x - stage_width * 0.5, y + stage_height * 0.76, stage_width, stage_height * 0.12), Color(0.88, 0.65, 0.28))
			draw_string(ThemeDB.fallback_font, Vector2(center_x + stage_width * 0.5 + 8.0, y + stage_height * 0.58), "S%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.8, 0.92))
			var engine_count := int(stage.get("engine_count", 1))
			var nozzle_width := minf(9.0, stage_width * 0.12)
			var engine_spacing := minf(20.0, stage_width * 0.68 / float(maxi(1, engine_count - 1)))
			for engine_index in range(engine_count):
				var engine_x := center_x + (float(engine_index) - float(engine_count - 1) * 0.5) * engine_spacing
				draw_colored_polygon(PackedVector2Array([Vector2(engine_x - nozzle_width, y + stage_height), Vector2(engine_x + nozzle_width, y + stage_height), Vector2(engine_x + nozzle_width * 0.65, y + stage_height + 12.0), Vector2(engine_x - nozzle_width * 0.65, y + stage_height + 12.0)]), Color(0.58, 0.62, 0.7))
			y += stage_height
		draw_string(ThemeDB.fallback_font, Vector2(12.0, size.y - 12.0), str(design.get("name", "CUSTOM VEHICLE")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.8, 0.92))

class Starfield:
	extends Control
	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 918273
		for i in range(260):
			var p := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
			var radius := rng.randf_range(0.5, 1.7)
			draw_circle(p, radius, Color(0.55, 0.72, 0.9, rng.randf_range(0.15, 0.7)))
	func _ready() -> void:
		queue_redraw()
