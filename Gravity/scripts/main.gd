extends Control

const SimulationView = preload("res://scripts/simulation_view.gd")
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
	_add_button(menu_root, "SETTINGS", _show_settings)
	_add_button(menu_root, "QUIT", _quit_game)

	var footer := Label.new()
	footer.text = "BUILD 0.1.0  •  PROCEDURAL SPACE SIMULATION"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(0.28, 0.38, 0.5))
	menu_root.add_child(footer)

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

	_add_button(right, "SAVE  [F5]", func(): _save_game(false))
	_add_button(right, "LOAD  [F9]", _load_game)
	_add_button(right, "PAUSE  [ESC]", _pause_simulation)
	_add_button(right, "RETURN TO MENU", _confirm_menu)

	var bottom := Label.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.position = Vector2(20, -34)
	bottom.size = Vector2(900, 24)
	bottom.text = "W / ↑ THRUST     A / D ROTATE     SPACE PAUSE     +/- TIME WARP     F5 SAVE     F9 LOAD"
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
	var data: Variant = JSON.parse_string(file.get_as_text())
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
