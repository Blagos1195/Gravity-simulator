extends Control

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const SAVE_DIR := "user://saves"
const AUTOSAVE_INTERVAL := 60.0

var mode := "menu"
var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var save_slot := 1
var sim
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
	var fullscreen := bool(config.get_value("general", "fullscreen", false))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _save_general_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("general", "autosave", autosave_enabled)
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
		autosave_elapsed += delta
		if autosave_enabled and autosave_elapsed >= AUTOSAVE_INTERVAL:
			autosave_elapsed = 0.0
			_save_game(true)

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
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 28
	root.offset_right = -28
	root.offset_top = 22
	root.offset_bottom = -22
	add_child(root)
	var heading := Label.new()
	heading.text = "VEHICLE ASSEMBLY"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	root.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "CONFIGURE A MULTI-STAGE LAUNCH VEHICLE  •  2–8 STAGES"
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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var columns := VBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)
	var stage_actions := HBoxContainer.new()
	stage_actions.add_theme_constant_override("separation", 10)
	columns.add_child(stage_actions)
	_add_button(stage_actions, "ADD STAGE", _add_rocket_stage)
	_add_button(stage_actions, "REMOVE LAST STAGE", _remove_rocket_stage)
	for stage_index in range(rocket_design["stages"].size()):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(panel)
		var fields := VBoxContainer.new()
		fields.add_theme_constant_override("separation", 8)
		panel.add_child(fields)
		var stage: Dictionary = rocket_design["stages"][stage_index]
		var stage_title := Label.new()
		stage_title.text = "STAGE %02d" % (stage_index + 1)
		stage_title.add_theme_font_size_override("font_size", 20)
		stage_title.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
		fields.add_child(stage_title)
		_add_design_field(fields, stage_index, "dry_mass", "Dry mass (kg)", 500.0, 200000.0, 100.0)
		_add_design_field(fields, stage_index, "fuel_capacity", "Propellant capacity (kg)", 500.0, 1000000.0, 1000.0)
		_add_design_field(fields, stage_index, "thrust", "Sea-level thrust (N)", 100000.0, 20000000.0, 100000.0)
		_add_design_field(fields, stage_index, "vacuum_thrust", "Vacuum thrust (N)", 100000.0, 22000000.0, 100000.0)
		_add_design_field(fields, stage_index, "flow", "Fuel flow per engine (kg/s)", 20.0, 8000.0, 10.0)
		_add_design_field(fields, stage_index, "engine_count", "Engine count", 1.0, 8.0, 1.0)
	var payload_panel := PanelContainer.new()
	payload_panel.custom_minimum_size.x = 230
	payload_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(payload_panel)
	var payload_fields := VBoxContainer.new()
	payload_panel.add_child(payload_fields)
	var payload_title := Label.new()
	payload_title.text = "PAYLOAD"
	payload_title.add_theme_font_size_override("font_size", 20)
	payload_title.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	payload_fields.add_child(payload_title)
	var payload_label := Label.new()
	payload_label.text = "Payload mass (kg)"
	payload_fields.add_child(payload_label)
	var payload := SpinBox.new()
	payload.min_value = 1.0
	payload.max_value = 100000.0
	payload.step = 10.0
	payload.value = float(rocket_design.get("payload_mass", 500.0))
	payload.value_changed.connect(func(value: float):
		rocket_design["payload_mass"] = value
		_update_design_stats()
	)
	payload_fields.add_child(payload)
	design_preview = RocketPreview.new()
	design_preview.design = rocket_design
	design_preview.custom_minimum_size = Vector2(210, 280)
	payload_fields.add_child(design_preview)
	design_stats_label = Label.new()
	design_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	payload_fields.add_child(design_stats_label)
	design_error_label = Label.new()
	design_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	design_error_label.add_theme_color_override("font_color", Color(1.0, 0.48, 0.35))
	payload_fields.add_child(design_error_label)
	_update_design_stats()
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)
	_add_button(actions, "RESET DESIGN", func():
		rocket_design = RocketDesign.create_default()
		_show_vehicle_editor()
	)
	_add_button(actions, "LOAD DESIGN", _load_rocket_design)
	_add_button(actions, "SAVE DESIGN", _save_rocket_design)
	_add_button(actions, "LAUNCH VEHICLE", _launch_designed_vehicle)
	_add_button(actions, "BACK", _show_new_game_setup)

func _add_rocket_stage() -> void:
	var stages: Array = rocket_design["stages"]
	if stages.size() >= 8:
		return
	stages.append({
		"name": "STAGE %02d" % (stages.size() + 1),
		"dry_mass": 4000.0,
		"fuel_capacity": 30000.0,
		"thrust": 200000.0,
		"vacuum_thrust": 250000.0,
		"flow": 63.3,
		"engine_count": 1
	})
	_show_vehicle_editor()

func _remove_rocket_stage() -> void:
	var stages: Array = rocket_design["stages"]
	if stages.size() <= 2:
		return
	stages.pop_back()
	_show_vehicle_editor()

func _add_design_field(parent: VBoxContainer, stage_index: int, key: String, label_text: String, minimum: float, maximum: float, step: float) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value = float(rocket_design["stages"][stage_index].get(key, minimum))
	spin.value_changed.connect(func(value: float):
		rocket_design["stages"][stage_index][key] = value
		_update_design_stats()
	)
	parent.add_child(spin)

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


func _load_rocket_design() -> void:
	var path := "user://rocket_design.json"
	if not FileAccess.file_exists(path):
		if is_instance_valid(design_error_label):
			design_error_label.text = "NO SAVED DESIGN FOUND"
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
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
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(500, 0)
	root.add_theme_constant_override("separation", 12)
	center.add_child(root)
	var heading := Label.new()
	heading.text = "LOAD GAME"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	root.add_child(heading)
	for slot in range(1, 9):
		var path := "%s/slot_%02d.json" % [SAVE_DIR, slot]
		var label := "SLOT %02d  •  EMPTY" % slot
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			var parsed: Variant = null
			if file:
				parsed = JSON.parse_string(file.get_as_text())
				file.close()
			if parsed is Dictionary:
				label = "SLOT %02d  •  %s  •  %s" % [slot, str(parsed.get("realism", "Unknown")), str(parsed.get("world_scale", "Unknown"))]
				_add_button(root, label, _load_menu_slot.bind(slot))
			else:
				var corrupt_label := Label.new()
				corrupt_label.text = "SLOT %02d  •  INVALID SAVE" % slot
				root.add_child(corrupt_label)
		else:
			var empty_label := Label.new()
			empty_label.text = label
			root.add_child(empty_label)
	_add_button(root, "BACK", _build_menu)

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
	_add_setting_label(settings_root, "KEYBOARD CONTROLS")
	for action in CONTROL_BINDINGS:
		_add_rebind_button(settings_root, action)
	var controls_note := Label.new()
	controls_note.text = "Physics, universe scale and career are selected when creating a new game. Key bindings are saved globally."
	controls_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_note.add_theme_color_override("font_color", Color(0.58, 0.68, 0.8))
	settings_root.add_child(controls_note)
	_add_button(settings_root, "BACK", _build_menu)

func _start_flight() -> void:
	for child in get_children():
		child.queue_free()
	mode = "flight"
	autosave_elapsed = 0.0
	sim = SimulationView.new()
	sim.realism = realism
	sim.world_scale = world_scale
	sim.career_enabled = career_enabled
	sim.set_rocket_design(rocket_design)
	sim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sim)
	_build_flight_hud()

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

	_add_button(right, "SOLAR SYSTEM VIEW  [M]", func(): sim.show_solar_system = not sim.show_solar_system)
	_add_button(right, "FLIGHT COMPUTER", _show_flight_computer)
	_add_button(right, "PREDICTED PATH  [P]", func():
		sim.show_predicted_trajectory = not sim.show_predicted_trajectory
		if sim.show_predicted_trajectory:
			sim._calculate_predicted_trajectory()
	)
	_add_button(right, "SAVE  [F5]", func(): _save_game(false))
	_add_button(right, "LOAD  [F9]", _load_game)
	_add_button(right, "PAUSE  [ESC]", _pause_simulation)
	_add_button(right, "RETURN TO MENU", _confirm_menu)

	var bottom := Label.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 350
	bottom.offset_right = -20
	bottom.offset_top = -58
	bottom.offset_bottom = -8
	bottom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.text = "W ENGINE ON/OFF     S CUTOFF     X STAGE     Q / E GIMBAL     A / D ROTATE\nH GUIDANCE     M SOLAR SYSTEM     P PREDICTED PATH     SPACE PAUSE     +/- WARP     F5 SAVE     F9 LOAD  •  REMAP IN SETTINGS"
	bottom.add_theme_font_size_override("font_size", 12)
	bottom.add_theme_color_override("font_color", Color(0.65, 0.77, 0.9))
	hud_root.add_child(bottom)

func _show_flight_computer() -> void:
	var window := Window.new()
	window.title = "FLIGHT COMPUTER"
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
	heading.text = "ORBITAL FLIGHT COMPUTER"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	root.add_child(heading)
	var description := Label.new()
	description.text = "Choose a destination and tune the trajectory search between fuel use and travel time. The reserve setting controls how much vehicle delta-v the planner is allowed to spend."
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
	var target_label := Label.new()
	target_label.text = "PLANNED DESTINATION / ORBIT"
	root.add_child(target_label)
	var target := OptionButton.new()
	target.add_item("Low Earth orbit · 200 km", 200000)
	target.add_item("Medium Earth orbit · 2,000 km", 2000000)
	target.add_item("Geostationary orbit · 35,786 km", 35786000)
	target.add_separator()
	target.add_item("Moon", -1)
	target.add_item("Mercury", -2)
	target.add_item("Venus", -3)
	target.add_item("Mars", -4)
	target.add_item("Jupiter", -5)
	target.add_item("Saturn", -6)
	target.add_item("Uranus", -7)
	target.add_item("Neptune", -8)
	root.add_child(target)
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
	var autopilot := Button.new()
	autopilot.text = "ENGAGE AUTOPILOT FOR SELECTED TARGET"
	root.add_child(autopilot)
	var landing := Button.new()
	landing.text = "ENGAGE POWERED LANDING"
	landing.pressed.connect(func():
		var selected_id: int = target.get_selected_id()
		if selected_id > 0:
			report.text += "\n\nSelect a planetary body or the Moon for landing guidance."
			return
		var planet_index := -1 if selected_id == -1 else -selected_id - 2
		var body_name := "Moon" if planet_index == -1 else str(FlightComputer.PLANET_TARGETS[planet_index].get("name", ""))
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
		var selected_id: int = target.get_selected_id()
		var current_body: Dictionary = sim._nearest_body_state(sim.rocket_position)
		landing.disabled = selected_id > 0 or sim.crashed
		autopilot.disabled = sim.crashed
		var current_position: Vector2 = sim.rocket_position - current_body.position
		var current_velocity: Vector2 = sim.velocity - current_body.velocity
		var state := FlightComputer.orbital_state(current_position, current_velocity, FlightComputer.G * float(current_body.mass))
		var current_altitude: float = float(current_body.distance) - float(current_body.radius)
		var text_lines := PackedStringArray()
		var remaining_delta_v := FlightComputer.available_delta_v(rocket_design, sim.stage_index, sim.fuel)
		var required_delta_v := 0.0
		var mission_valid := true
		var in_orbit := str(current_body.name) == "Earth" and current_altitude > 70000.0 and bool(state.get("bound", false))
		text_lines.append("CURRENT FLIGHT STATE")
		text_lines.append("Current body: %s" % str(current_body.name))
		text_lines.append("Altitude: %.1f km" % (current_altitude / 1000.0))
		text_lines.append("Speed: %.0f m/s" % current_velocity.length())
		text_lines.append("Apoapsis: %s" % ("UNBOUND" if not bool(state.get("bound", false)) else "%.1f km" % ((float(state.get("apoapsis", 0.0)) - float(current_body.radius)) / 1000.0)))
		text_lines.append("Periapsis: %.1f km" % ((float(state.get("periapsis", 0.0)) - float(current_body.radius)) / 1000.0))
		text_lines.append("")
		if selected_id > 0 and str(current_body.name) == "Earth":
			var target_radius := FlightComputer.EARTH_RADIUS + float(selected_id)
			var circular := FlightComputer.circularisation_burn(current_position, current_velocity, true, FlightComputer.G * float(current_body.mass))
			var orbit_origin_radius := maxf(float(current_body.radius) + 100000.0, current_position.length())
			var orbit_transfer := FlightComputer.hohmann_transfer(orbit_origin_radius, target_radius)
			var orbit_departure_direction := "PROGRADE" if target_radius > orbit_origin_radius else "RETROGRADE"
			text_lines.append("TARGET EARTH ORBIT")
			text_lines.append("Altitude: %.0f km" % (float(selected_id) / 1000.0))
			text_lines.append("Circular speed: %.0f m/s" % FlightComputer.circular_orbit_speed(target_radius))
			text_lines.append("Circularise at current position: %.0f m/s Δv" % float(circular.get("delta_v", 0.0)))
			text_lines.append("Hohmann orbit-change estimate: %.0f m/s Δv" % float(orbit_transfer.get("total_delta_v", 0.0)))
			text_lines.append("Transfer time: %.1f minutes" % (float(orbit_transfer.get("transfer_time", 0.0)) / 60.0))
			required_delta_v = float(orbit_transfer.get("total_delta_v", 0.0)) if in_orbit else 9400.0 + float(orbit_transfer.get("total_delta_v", 0.0))
		else:
			var destination_index := -2 if selected_id > 0 else (-1 if selected_id == -1 else -selected_id - 2)
			var destination_name := "Earth" if destination_index == -2 else "Moon" if destination_index == -1 else str(FlightComputer.PLANET_TARGETS[destination_index].get("name", "Unknown"))
			var stable_departure_state := bool(state.get("bound", false)) and float(state.get("periapsis", 0.0)) > float(current_body.radius) + 70000.0
			text_lines.append("SIMULATED TRANSFER")
			text_lines.append("Destination: %s" % destination_name)
			if sim.landed or (current_altitude < 120000.0 and not stable_departure_state):
				mission_valid = false
				text_lines.append("A stable departure orbit is required before the transfer search can run.")
				text_lines.append("Autopilot will establish the departure orbit, then simulate candidate trajectories.")
			elif not calculate_simulated_transfer:
				text_lines.append("Press CALCULATE FLIGHT PLAN to simulate candidate trajectories from the current state.")
			else:
				var available_for_transfer: float = remaining_delta_v * (1.0 - sim.autopilot_safety_margin)
				var simulated_plan := FlightComputer.simulated_transfer_search(sim.rocket_position, sim.velocity, sim.sim_time, destination_index, available_for_transfer, sim.autopilot_speed_priority)
				if bool(simulated_plan.get("valid", false)):
					text_lines.append("Departure manoeuvre: %.0f m/s Δv" % float(simulated_plan.get("departure_delta_v", 0.0)))
					text_lines.append("Arrival capture: %.0f m/s Δv" % float(simulated_plan.get("capture_delta_v", 0.0)))
					text_lines.append("Total simulated Δv: %.0f m/s" % float(simulated_plan.get("total_delta_v", 0.0)))
					text_lines.append("Predicted flight time: %.1f days" % (float(simulated_plan.get("transfer_time", 0.0)) / 86400.0))
					text_lines.append("Closest approach: %.0f km" % (float(simulated_plan.get("closest_approach", 0.0)) / 1000.0))
					text_lines.append("Candidate trajectories simulated: %d" % int(simulated_plan.get("search_candidates", 0)))
					required_delta_v = float(simulated_plan.get("total_delta_v", 0.0))
				else:
					mission_valid = false
					text_lines.append("NO FEASIBLE TRAJECTORY FOUND")
					text_lines.append(str(simulated_plan.get("reason", "No candidate passed the trajectory and capture checks.")))
			text_lines.append("The search propagates candidate burns through the current multi-body gravity model. Finite engine-burn and atmospheric losses are not included in the search estimate.")
		text_lines.append("")
		text_lines.append("VEHICLE FUEL FEASIBILITY")
		text_lines.append("Remaining ideal vehicle Δv: %.2f km/s" % (remaining_delta_v / 1000.0))
		text_lines.append("Estimated mission budget: %.2f km/s" % (required_delta_v / 1000.0))
		text_lines.append("Selected fuel reserve: %.0f%%" % (sim.autopilot_safety_margin * 100.0))
		text_lines.append("Available Δv after reserve: %.2f km/s" % (remaining_delta_v * (1.0 - sim.autopilot_safety_margin) / 1000.0))
		var margin: float = remaining_delta_v * (1.0 - sim.autopilot_safety_margin) - required_delta_v
		text_lines.append("Margin after reserve: %+.2f km/s" % (margin / 1000.0))
		if not mission_valid:
			text_lines.append("STATUS: NO VALID FLIGHT PLAN")
		elif remaining_delta_v <= 0.0:
			text_lines.append("STATUS: NO USABLE PROPELLANT")
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
	target.item_selected.connect(func(_index: int):
		calculate_simulated_transfer = false
		update_report.call()
	)
	autopilot.pressed.connect(func():
		var selected_id: int = target.get_selected_id()
		sim.autopilot_enabled = true
		sim.autopilot_complete = false
		sim.autopilot_target_altitude = float(selected_id) if selected_id > 0 else 200000.0
		sim.autopilot_target_mode = "ORBIT" if selected_id > 0 else "PLANET"
		sim.autopilot_planet_index = -2 if selected_id > 0 else -1 if selected_id == -1 else -selected_id - 2
		sim.autopilot_burn_remaining = 0.0
		sim.autopilot_burn_direction = Vector2.ZERO
		sim.autopilot_transfer_corrections = 0
		var current_body: Dictionary = sim._nearest_body_state(sim.rocket_position)
		var relative_position: Vector2 = sim.rocket_position - current_body.position
		var relative_velocity: Vector2 = sim.velocity - current_body.velocity
		var current_orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(current_body.mass))
		var target_state: Dictionary = sim._autopilot_target_state()
		var target_distance: float = sim.rocket_position.distance_to(Vector2(target_state.get("position", Vector2.ZERO)))
		var target_is_near: bool = not target_state.is_empty() and target_distance <= float(target_state.get("soi", 0.0)) and (sim.autopilot_planet_index != -2 or str(current_body.name) == "Earth")
		var current_altitude := float(current_body.distance) - float(current_body.radius)
		var stable_current_orbit := bool(current_orbit.get("bound", false)) and float(current_orbit.get("periapsis", 0.0)) > float(current_body.radius) + 70000.0
		var selected_earth_orbit := selected_id > 0
		var source_is_earth := str(current_body.name) == "Earth"
		var already_at_destination_surface: bool = not selected_earth_orbit and sim.landed and sim.landed_body_name == sim._autopilot_target_body_name()
		if already_at_destination_surface:
			sim.autopilot_phase = "COMPLETE"
			sim.autopilot_complete = true
		elif target_is_near and not (selected_earth_orbit and source_is_earth):
			sim.autopilot_phase = "ARRIVAL_APPROACH"
		elif selected_earth_orbit and source_is_earth:
			if sim.landed or (current_altitude < 120000.0 and not stable_current_orbit):
				sim.autopilot_phase = "ASCENT"
			else:
				sim.autopilot_phase = "CIRCULARISE"
		elif sim.landed or (current_altitude < 120000.0 and not stable_current_orbit):
			sim.autopilot_phase = "ASCENT"
		else:
			sim.autopilot_phase = "PLAN_TRANSFER"
		sim.guidance_enabled = true
		sim.thrust_key_down = sim.landed or sim.autopilot_phase == "ASCENT"
		report.text += "\n\nAUTOPILOT ENGAGED. " + ("Target orbit: %.0f km." % (sim.autopilot_target_altitude / 1000.0) if selected_id > 0 else "Target: " + str(target.get_item_text(target.selected)) + ". A trajectory search will use your current position and velocity.")
	)
	update_report.call()
	window.popup_centered()

func _pause_simulation() -> void:
	if sim:
		sim.paused = not sim.paused
		if status_label:
			status_label.text = "PAUSED" if sim.paused else "FLIGHT ACTIVE"

func _confirm_menu() -> void:
	_save_game(true)
	_build_menu()

func _save_game(automatic: bool) -> void:
	if not sim:
		return

	var data: Dictionary = sim.get_save_data()
	data["realism"] = realism
	data["world_scale"] = world_scale
	data["career_enabled"] = career_enabled
	data["slot"] = save_slot

	var path := "%s/slot_%02d.json" % [SAVE_DIR, save_slot]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		if status_label:
			status_label.text = ("AUTOSAVED" if automatic else "SAVED") + "  •  SLOT %02d" % save_slot

func _load_game() -> void:
	var path := "%s/slot_%02d.json" % [SAVE_DIR, save_slot]
	if not FileAccess.file_exists(path):
		if status_label:
			status_label.text = "NO SAVE FOUND IN SLOT %02d" % save_slot
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if status_label:
			status_label.text = "SAVE COULD NOT BE OPENED"
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and sim:
		realism = str(parsed.get("realism", realism))
		world_scale = str(parsed.get("world_scale", world_scale))
		career_enabled = bool(parsed.get("career_enabled", career_enabled))
		sim.load_save_data(parsed)
		var saved_design: Variant = parsed.get("rocket_design", null)
		if saved_design is Dictionary:
			rocket_design = saved_design
		if status_label:
			status_label.text = "LOADED  •  SLOT %02d" % save_slot
	elif status_label:
		status_label.text = "SAVE DATA IS INVALID  •  SLOT %02d" % save_slot

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
		var top := 14.0
		var width := minf(48.0, size.x * 0.24)
		var stage_height := minf(48.0, (size.y - 65.0) / float(maxi(1, stages.size())))
		var payload_height := 25.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(center_x, top),
			Vector2(center_x - width * 0.5, top + payload_height),
			Vector2(center_x + width * 0.5, top + payload_height)
		]), Color(0.75, 0.84, 0.94))
		var y := top + payload_height
		for i in range(stages.size() - 1, -1, -1):
			var stage_width := width * (1.0 + float(i) * 0.08)
			draw_rect(Rect2(center_x - stage_width * 0.5, y, stage_width, stage_height), Color(0.36 + float(i) * 0.025, 0.62, 0.78))
			draw_rect(Rect2(center_x - stage_width * 0.5, y + stage_height * 0.68, stage_width, stage_height * 0.2), Color(0.92, 0.65, 0.22))
			y += stage_height

		draw_string(ThemeDB.fallback_font, Vector2(12, size.y - 8), str(design.get("name", "CUSTOM VEHICLE")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.8, 0.92))

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
