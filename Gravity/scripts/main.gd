extends Control

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const SAVE_DIR := "user://saves"
const AUTOSAVE_INTERVAL := 60.0

var mode := "menu"
var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var save_slot := 1
var sim
var autosave_elapsed := 0.0
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
	_build_menu()

func _process(delta: float) -> void:
	if mode == "flight":
		autosave_elapsed += delta
		if autosave_elapsed >= AUTOSAVE_INTERVAL:
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

	_add_button(menu_root, "START FLIGHT", _start_flight)
	_add_button(menu_root, "VEHICLE ASSEMBLY", _show_vehicle_editor)
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
		_add_design_field(fields, stage_index, "dry_mass", "Dry mass (kg)", 100.0, 100000.0, 100.0)
		_add_design_field(fields, stage_index, "fuel_capacity", "Propellant capacity (kg)", 100.0, 1000000.0, 1000.0)
		_add_design_field(fields, stage_index, "thrust", "Sea-level thrust (N)", 10000.0, 50000000.0, 100000.0)
		_add_design_field(fields, stage_index, "vacuum_thrust", "Vacuum thrust (N)", 10000.0, 60000000.0, 100000.0)
		_add_design_field(fields, stage_index, "flow", "Fuel flow per engine (kg/s)", 1.0, 20000.0, 10.0)
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
	_add_button(actions, "BACK", _build_menu)

func _add_rocket_stage() -> void:
	var stages: Array = rocket_design["stages"]
	if stages.size() >= 8:
		return
	stages.append({
		"name": "STAGE %02d" % (stages.size() + 1),
		"dry_mass": 3000.0,
		"fuel_capacity": 80000.0,
		"thrust": 1200000.0,
		"vacuum_thrust": 1500000.0,
		"flow": 300.0,
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
	var first: Dictionary = rocket_design["stages"][0]
	var initial_twr := float(first["thrust"]) * float(first.get("engine_count", 1)) / maxf(1.0, total_mass * 9.81)
	design_stats_label.text = "INITIAL MASS\n%.1f tonnes\n\nIDEAL ΔV\n%.2f km/s\n\nPAD TWR\n%.2f" % [total_mass / 1000.0, delta_v / 1000.0, initial_twr]
	design_error_label.text = "\n".join(errors) if not errors.is_empty() else "DESIGN VALID"
	if is_instance_valid(design_preview):
		design_preview.design = rocket_design
		design_preview.queue_redraw()

func _save_rocket_design() -> void:
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

func _show_settings() -> void:
	for child in get_children():
		child.queue_free()
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
	heading.text = "SIMULATION SETTINGS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 30)
	settings_root.add_child(heading)

	_add_setting_label(settings_root, "PHYSICS REALISM")
	var physics := OptionButton.new()
	for option in ["Arcade", "Standard", "Realistic", "Hardcore"]:
		physics.add_item(option)
	physics.select(["Arcade", "Standard", "Realistic", "Hardcore"].find(realism))
	physics.item_selected.connect(func(index: int): realism = physics.get_item_text(index))
	settings_root.add_child(physics)

	_add_setting_label(settings_root, "SOLAR SYSTEM SCALE")
	var scale := OptionButton.new()
	for option in ["Compressed", "Balanced", "Realistic distances"]:
		scale.add_item(option)
	scale.select(["Compressed", "Balanced", "Realistic distances"].find(world_scale))
	scale.item_selected.connect(func(index: int): world_scale = scale.get_item_text(index))
	settings_root.add_child(scale)

	_add_setting_label(settings_root, "CAREER PROGRESSION")
	var career := CheckButton.new()
	career.text = "Enable optional career progression"
	career.button_pressed = career_enabled
	career.toggled.connect(func(value: bool): career_enabled = value)
	settings_root.add_child(career)

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
	bottom.text = "W / ↑ ENGINE ON/OFF     S / ↓ CUTOFF     X STAGE     Q / E GIMBAL     A / D ROTATE\nH GUIDANCE     M SOLAR SYSTEM     P PREDICTED PATH     SPACE PAUSE     +/- WARP     F5 SAVE     F9 LOAD"
	bottom.add_theme_font_size_override("font_size", 12)
	bottom.add_theme_color_override("font_color", Color(0.65, 0.77, 0.9))
	hud_root.add_child(bottom)

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
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY and sim:
		realism = parsed.get("realism", realism)
		world_scale = parsed.get("world_scale", world_scale)
		career_enabled = parsed.get("career_enabled", career_enabled)
		sim.load_save_data(parsed)
		var saved_design: Variant = parsed.get("rocket_design", null)
		if saved_design is Dictionary:
			rocket_design = saved_design
		if status_label:
			status_label.text = "LOADED  •  SLOT %02d" % save_slot

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
