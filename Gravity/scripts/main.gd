extends Control

const SimulationView = preload("res://scripts/simulation_view.gd")
const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketAssembly = preload("res://scripts/rocket_assembly.gd")
const RocketBuilder = preload("res://scripts/rocket_builder.gd")
const RocketVisual = preload("res://scripts/rocket_visual.gd")
const FlightComputer = preload("res://scripts/flight_computer.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")
const RoutePlanner = preload("res://scripts/route_planner.gd")
const OrbitalPropagator = preload("res://scripts/orbital_propagator.gd")
const SpaceDiscovery = preload("res://scripts/space_discovery.gd")
const MissionSystem = preload("res://scripts/mission_system.gd")
const SpaceObjectPhysics = preload("res://scripts/space_object_physics.gd")
const STARTING_FUNDS := 150000000.0
const LAUNCH_BASE_COST := 1000000.0
const LAUNCH_COST_PER_KG := 75.0
const SAVE_DIR := "user://saves"
const AUTOSAVE_INTERVAL := 60.0
const DOCKING_CAPTURE_DISTANCE := 100.0
const DOCKING_CAPTURE_SPEED := 2.5
const DOCKING_ASSIST_MAX_RANGE := 2000000.0
const DOCKING_ASSIST_ACCELERATION := 0.15
const DOCKING_ASSIST_MAX_CLOSING_SPEED := 8.0

var mode := "menu"
var realism := "Realistic"
var world_scale := "Compressed"
var career_enabled := false
var infinite_weightless_fuel := false
var simulate_belt_collisions := false
var save_slot := 1
var new_game_slot := 1
var sim
var fleet_sims: Array = []
var pending_debris: Array[Dictionary] = []
var debris_sequence := 0
var active_vehicle_index := 0
var fleet_time_backlog := 0.0
var discovery_state: Dictionary = SpaceDiscovery.new_campaign_state()
var funds := STARTING_FUNDS
var economy_last_sim_time := 0.0
var total_revenue_earned := 0.0
var total_operating_costs := 0.0
var funds_label: Label
var mission_state: Dictionary = MissionSystem.new_state()
var orbited_body_names: Dictionary = {}
var vehicle_selector: OptionButton
var telescope_button: Button
var docking_links: Array[Dictionary] = []
var docking_assists: Dictionary = {}
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
var flight_hud_top: PanelContainer
var flight_hud_right_scroll: ScrollContainer
var flight_hud_bottom: Label
var flight_hud_right: VBoxContainer
var scale_factor := 1.0
var rocket_design: Dictionary = RocketDesign.create_default()
var active_builder: Control
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
	_fit_windows_to_screen()
	if mode == "flight":
		_advance_fleet(delta)
		autosave_elapsed += delta
		if autosave_enabled and autosave_elapsed >= AUTOSAVE_INTERVAL:
			autosave_elapsed = 0.0
			_save_game(true)

func _fit_windows_to_screen() -> void:
	var screen_size := DisplayServer.screen_get_size()
	var available := Vector2i(maxi(320, screen_size.x - 32), maxi(240, screen_size.y - 64))
	for child in get_tree().root.find_children("*", "Window", true, false):
		if not child is Window:
			continue
		var window := child as Window
		window.min_size = Vector2i(mini(window.min_size.x, available.x), mini(window.min_size.y, available.y))
		var target_size := Vector2i(mini(window.size.x, available.x), mini(window.size.y, available.y))
		if target_size != window.size:
			window.size = target_size
		var target_position := Vector2i(
			clampi(window.position.x, 0, maxi(0, screen_size.x - window.size.x)),
			clampi(window.position.y, 0, maxi(0, screen_size.y - window.size.y))
		)
		if target_position != window.position:
			window.position = target_position

func _advance_fleet(delta: float) -> void:
	if fleet_sims.is_empty() or not is_instance_valid(sim):
		return
	_update_passive_orbit_states()
	for vehicle in fleet_sims:
		vehicle.time_warp = sim.time_warp
		vehicle.paused = sim.paused
		if vehicle == sim and vehicle.show_predicted_trajectory:
			vehicle.prediction_timer += delta
			if vehicle.prediction_timer >= 0.35:
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
			if vehicle.passive_orbit_active:
				continue
			var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position)
			var altitude: float = maxf(0.0, float(body.distance) - float(body.radius))
			var atmosphere_height: float = PlanetarySystem.planetary_atmosphere_height(str(body.get("name", "Earth")))
			if float(body.distance) < float(body.soi) and altitude < atmosphere_height:
				effective_warp = minf(effective_warp, 100.0)
		fleet_time_backlog = effective_warp * delta
		var iterations := 0
		var physics_budget_start_usec: int = Time.get_ticks_usec()
		_update_docked_masses()
		while fleet_time_backlog > 0.000001 and iterations < SimulationView.MAX_PHYSICS_STEPS_PER_FRAME and Time.get_ticks_usec() - physics_budget_start_usec < SimulationView.MAX_PHYSICS_BUDGET_USEC:
			var step_delta := fleet_time_backlog
			for vehicle in fleet_sims:
				if not _is_docked_child(vehicle.vehicle_name) and not vehicle.passive_orbit_active:
					step_delta = minf(step_delta, vehicle._adaptive_step_size())
				if vehicle.telescope_active and not vehicle.landed and not vehicle.crashed:
					var telescope_body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
					if not telescope_body.is_empty():
						var telescope_relative_position: Vector2 = telescope_body.get("relative_position", Vector2.ZERO)
						var telescope_relative_velocity: Vector2 = vehicle.velocity - Vector2(telescope_body.get("velocity", Vector2.ZERO))
						var telescope_orbit := FlightComputer.orbital_state(telescope_relative_position, telescope_relative_velocity, FlightComputer.G * float(telescope_body.get("mass", 0.0)))
						var telescope_period := float(telescope_orbit.get("period", INF))
						if bool(telescope_orbit.get("bound", false)) and telescope_period > 0.0 and is_finite(telescope_period):
							step_delta = minf(step_delta, telescope_period / 24.0)
			if step_delta <= 0.000001:
				break
			var positions_before: Dictionary = {}
			for vehicle in fleet_sims:
				positions_before[vehicle] = vehicle.rocket_position
			_apply_docking_assists(step_delta)
			for vehicle in fleet_sims:
				if not _is_docked_child(vehicle.vehicle_name) and not vehicle.passive_orbit_active:
					vehicle._physics_step(step_delta)
			for vehicle in fleet_sims:
				if vehicle.passive_orbit_active:
					_advance_passive_vehicle(vehicle, sim.sim_time)
			_resolve_spacecraft_collisions(positions_before)
			_sync_docked_vehicles()
			_scan_active_telescopes()
			fleet_time_backlog = maxf(0.0, fleet_time_backlog - step_delta)
			iterations += 1
		fleet_time_backlog = 0.0
	var separated_stages := pending_debris.duplicate(true)
	pending_debris.clear()
	for stage_data in separated_stages:
		_spawn_discarded_stage(stage_data)
	var removed_active_debris := false
	for index in range(fleet_sims.size() - 1, -1, -1):
		var vehicle: SimulationView = fleet_sims[index]
		if not vehicle.is_debris:
			continue
		var body := vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
		if body.is_empty() or float(body.get("distance", INF)) > float(body.get("radius", 0.0)) + 2.0:
			continue
		if vehicle == sim:
			removed_active_debris = true
		fleet_sims.remove_at(index)
		vehicle.queue_free()
	if removed_active_debris and not fleet_sims.is_empty():
		_switch_vehicle(0)
	elif removed_active_debris:
		sim = null
	_refresh_vehicle_selector()
	for vehicle in fleet_sims:
		vehicle.simulation_time_backlog = fleet_time_backlog
	if is_instance_valid(sim):
		sim.fleet_visuals.clear()
		for vehicle in fleet_sims:
			if vehicle == sim or _is_docked_child(vehicle.vehicle_name):
				continue
			var orbit_points := PackedVector2Array()
			if not vehicle.crashed and not vehicle.landed:
				var orbit_body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
				var orbit_relative_position: Vector2 = orbit_body.get("relative_position", Vector2.ZERO)
				var orbit_relative_velocity: Vector2 = vehicle.velocity - Vector2(orbit_body.get("velocity", Vector2.ZERO))
				var orbit_mu := FlightComputer.G * float(orbit_body.get("mass", 0.0))
				var orbit_state := FlightComputer.orbital_state(orbit_relative_position, orbit_relative_velocity, orbit_mu)
				if bool(orbit_state.get("bound", false)) and float(orbit_state.get("periapsis", 0.0)) > float(orbit_body.get("radius", 0.0)):
					var semi_major := -orbit_mu / (2.0 * (orbit_relative_velocity.length_squared() * 0.5 - orbit_mu / orbit_relative_position.length()))
					var eccentricity := float(orbit_state.get("eccentricity", 0.0))
					var direction := orbit_relative_position.angle()
					var host_position := vehicle.rocket_position - orbit_relative_position
					for point_index in range(97):
						var theta := TAU * float(point_index) / 96.0
						var orbit_radius := semi_major * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(theta))
						orbit_points.append(host_position + Vector2(cos(theta + direction), sin(theta + direction)) * orbit_radius)
			sim.fleet_visuals.append({
				"name": vehicle.vehicle_name,
				"position": vehicle.rocket_position,
				"rotation": vehicle.rotation_angle,
				"stage_index": vehicle.stage_index,
				"crashed": vehicle.crashed,
				"orbit_points": orbit_points,
				"design": {"name": vehicle.vehicle_name, "payload_mass": vehicle.payload_mass, "payload_type": vehicle.payload_type, "payload_visual": vehicle.payload_visual.duplicate(true), "stages": vehicle.rocket_stages.duplicate(true)}
			})
		_scan_active_telescopes()
		_update_discovery_state()
		_update_economy()
		_update_missions()
		sim.queue_redraw()

func _resolve_spacecraft_collisions(positions_before: Dictionary) -> void:
	for first_index in range(fleet_sims.size()):
		var first: SimulationView = fleet_sims[first_index]
		if first.landed or not positions_before.has(first):
			continue
		for second_index in range(first_index + 1, fleet_sims.size()):
			var second: SimulationView = fleet_sims[second_index]
			if second.landed or not positions_before.has(second) or (first.crashed and second.crashed):
				continue
			if _are_docked(first.vehicle_name, second.vehicle_name):
				continue
			if first.separation_grace_until > sim.sim_time and second.separation_parent_name == first.vehicle_name:
				continue
			if second.separation_grace_until > sim.sim_time and first.separation_parent_name == second.vehicle_name:
				continue
			var first_radius := RocketDesign.vehicle_collision_radius_m({"stages": first.rocket_stages}, first.stage_index)
			var second_radius := RocketDesign.vehicle_collision_radius_m({"stages": second.rocket_stages}, second.stage_index)
			var contact := SpaceObjectPhysics.swept_circle_contact(
				positions_before[first],
				first.rocket_position,
				first_radius,
				positions_before[second],
				second.rocket_position,
				second_radius
			)
			if contact.is_empty():
				continue
			var normal: Vector2 = contact.normal
			var midpoint: Vector2 = contact.impact_point
			var first_contact := midpoint + normal * first_radius
			var second_contact := midpoint - normal * second_radius
			first._set_rocket_position_components(first_contact.x, first_contact.y)
			second._set_rocket_position_components(second_contact.x, second_contact.y)
			first.crashed = true
			second.crashed = true
			first.input_enabled = false
			second.input_enabled = false
			first.passive_orbit_active = false
			second.passive_orbit_active = false
			first.passive_orbit_data.clear()
			second.passive_orbit_data.clear()
			if is_instance_valid(sim):
				var impact_speed := first.velocity.distance_to(second.velocity)
				sim.spawn_collision_effect(midpoint, clampf(impact_speed / 100.0, 0.7, 2.2))
			first.thrust_key_down = false
			second.thrust_key_down = false
			first.autopilot_enabled = false
			second.autopilot_enabled = false
			first.guidance_enabled = false
			second.guidance_enabled = false
			first.throttle = 0.0
			second.throttle = 0.0
			first.status_message = "COLLISION WITH %s" % second.vehicle_name.to_upper()
			second.status_message = "COLLISION WITH %s" % first.vehicle_name.to_upper()

func _apply_docking_assists(delta: float) -> void:
	for vehicle_name_variant in docking_assists.keys():
		var vehicle_name := str(vehicle_name_variant)
		var target_name := str(docking_assists.get(vehicle_name, ""))
		var vehicle := _find_vehicle_by_name(vehicle_name)
		var target := _find_vehicle_by_name(target_name)
		if vehicle == null or target == null or vehicle == target or vehicle.landed or vehicle.crashed or target.landed or target.crashed or _is_vehicle_docked(vehicle_name) or _is_vehicle_docked(target_name):
			docking_assists.erase(vehicle_name)
			continue
		if vehicle.passive_orbit_active:
			vehicle.passive_orbit_active = false
			vehicle.passive_orbit_data.clear()
		var relative_position: Vector2 = target.rocket_position - vehicle.rocket_position
		var separation := relative_position.length()
		if separation > DOCKING_ASSIST_MAX_RANGE or separation < 0.001:
			docking_assists.erase(vehicle_name)
			continue
		var direction := relative_position / separation
		var desired_closing_speed := minf(DOCKING_ASSIST_MAX_CLOSING_SPEED, sqrt(2.0 * DOCKING_ASSIST_ACCELERATION * maxf(0.0, separation - DOCKING_CAPTURE_DISTANCE)))
		var desired_velocity: Vector2 = target.velocity + direction * desired_closing_speed
		var velocity_correction := (desired_velocity - vehicle.velocity).limit_length(DOCKING_ASSIST_ACCELERATION)
		vehicle.velocity += velocity_correction * maxf(0.0, delta)

func _launch_cost_for_design(design: Dictionary) -> float:
	return LAUNCH_BASE_COST + RocketDesign.total_initial_mass(design) * LAUNCH_COST_PER_KG

func _vehicle_in_stable_orbit(vehicle: SimulationView) -> bool:
	if vehicle.landed or vehicle.crashed:
		return false
	var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
	if body.is_empty() or float(body.get("distance", INF)) > float(body.get("soi", 0.0)):
		return false
	var relative_position: Vector2 = body.relative_position
	var relative_velocity: Vector2 = vehicle.velocity - Vector2(body.get("velocity", Vector2.ZERO))
	var orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(body.get("mass", 0.0)))
	if not bool(orbit.get("bound", false)):
		return false
	var body_radius := float(body.get("radius", 0.0))
	var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(str(body.get("name", "")), body_radius)
	var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(body.get("soi", 0.0)))
	return float(orbit.get("periapsis", 0.0)) > body_radius + minimum_altitude and float(orbit.get("apoapsis", INF)) < body_radius + maximum_altitude

func _update_economy() -> void:
	if not is_instance_valid(sim):
		return
	var previous_time := economy_last_sim_time
	var current_time: float = sim.sim_time
	var elapsed_seconds := maxf(0.0, current_time - previous_time)
	economy_last_sim_time = current_time
	if not career_enabled or elapsed_seconds <= 0.0:
		_refresh_economy_display()
		return
	for vehicle in fleet_sims:
		var profile: Dictionary = vehicle.payload_visual
		var role := str(profile.get("satellite_role", ""))
		var lifetime_days := float(profile.get("operational_lifetime_days", 0.0))
		if role.is_empty() or lifetime_days <= 0.0 or not _vehicle_in_stable_orbit(vehicle):
			continue
		var age_at_start: float = (previous_time - vehicle.launch_time) / 86400.0
		var age_at_end: float = (current_time - vehicle.launch_time) / 86400.0
		var active_days := maxf(0.0, minf(age_at_end, lifetime_days) - maxf(age_at_start, 0.0))
		if active_days <= 0.0:
			continue
		var revenue := maxf(0.0, float(profile.get("revenue_per_day", 0.0)))
		var operating_cost := maxf(0.0, float(profile.get("operating_cost_per_day", 0.0)))
		funds += (revenue - operating_cost) * active_days
		total_revenue_earned += revenue * active_days
		total_operating_costs += operating_cost * active_days
	_refresh_economy_display()

func _refresh_economy_display() -> void:
	if not is_instance_valid(funds_label):
		return
	funds_label.visible = career_enabled
	if career_enabled:
		funds_label.text = "FUNDS  •  %.1f M CREDITS" % (funds / 1000000.0)

func _update_missions() -> void:
	var planet_names: Array[String] = []
	for planet in PlanetarySystem.PLANETS:
		var planet_name := str(planet.get("name", ""))
		if planet_name != "Earth":
			planet_names.append(planet_name)
	var operational_satellites := 0
	for vehicle in fleet_sims:
		var profile: Dictionary = vehicle.payload_visual
		var role := str(profile.get("satellite_role", ""))
		var lifetime_days := float(profile.get("operational_lifetime_days", 0.0))
		var age_days := maxf(0.0, (sim.sim_time - vehicle.launch_time) / 86400.0)
		if not role.is_empty() and (lifetime_days <= 0.0 or age_days < lifetime_days) and _vehicle_in_stable_orbit(vehicle):
			operational_satellites += 1
	var completed_now := MissionSystem.evaluate(MissionSystem.definitions(), mission_state, discovery_state, orbited_body_names, planet_names, operational_satellites)
	for mission in completed_now:
		var reward := maxf(0.0, float(mission.get("reward", 0.0)))
		if career_enabled:
			funds += reward
		if is_instance_valid(status_label):
			status_label.text = "CONTRACT COMPLETE  •  %s%s" % [str(mission.get("title", "MISSION")).to_upper(), "  •  +%.1f M CREDITS" % (reward / 1000000.0) if career_enabled else ""]
	if not completed_now.is_empty():
		_refresh_economy_display()

func _show_missions_panel() -> void:
	var window := Window.new()
	window.title = "MISSIONS AND CONTRACTS"
	window.size = Vector2i(680, 560)
	window.min_size = Vector2i(500, 380)
	window.transient = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	window.add_child(layout)
	var heading := Label.new()
	heading.text = "EXPLORATION CONTRACTS  •  %d / %d COMPLETE" % [mission_state.get("completed", {}).size(), MissionSystem.definitions().size()]
	heading.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	layout.add_child(heading)
	if not career_enabled:
		var note := Label.new()
		note.text = "CAREER REWARDS ARE DISABLED IN THIS GAME MODE"
		layout.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 10)
	scroll.add_child(entries)
	var planet_names: Array[String] = []
	for planet in PlanetarySystem.PLANETS:
		var planet_name := str(planet.get("name", ""))
		if planet_name != "Earth":
			planet_names.append(planet_name)
	var operational_satellites := 0
	for vehicle in fleet_sims:
		var profile: Dictionary = vehicle.payload_visual
		var lifetime_days := float(profile.get("operational_lifetime_days", 0.0))
		var age_days := maxf(0.0, (sim.sim_time - vehicle.launch_time) / 86400.0)
		if not str(profile.get("satellite_role", "")).is_empty() and (lifetime_days <= 0.0 or age_days < lifetime_days) and _vehicle_in_stable_orbit(vehicle):
			operational_satellites += 1
	for mission in MissionSystem.definitions():
		var mission_id := str(mission.get("id", ""))
		var progress := MissionSystem.progress(mission, discovery_state, orbited_body_names, planet_names, operational_satellites)
		var completed := bool(mission_state.get("completed", {}).get(mission_id, false))
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 3)
		entries.add_child(card)
		var title_label := Label.new()
		title_label.text = "%s  •  %s" % ["COMPLETE" if completed else "AVAILABLE", str(mission.get("title", mission_id)).to_upper()]
		card.add_child(title_label)
		var description := Label.new()
		description.text = str(mission.get("description", ""))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(description)
		var reward_text := "%.1f M CREDITS" % (float(mission.get("reward", 0.0)) / 1000000.0)
		var progress_text := "COMPLETE" if completed else "%d / %d" % [int(progress.current), int(progress.target)]
		var detail := Label.new()
		detail.text = "%s  •  %s" % [progress_text, reward_text]
		card.add_child(detail)
	_add_button(layout, "CLOSE", func(): window.queue_free())
	window.popup_centered()

func _update_discovery_state() -> void:
	if fleet_sims.is_empty() or not is_instance_valid(sim):
		return
	var ephemeris := PlanetarySystem.gravity_body_states(sim.sim_time)
	var heliocentric_bodies: Array = ephemeris.get("heliocentric_bodies", [])
	var earth_position: Vector2 = ephemeris.get("earth_heliocentric_position", Vector2.ZERO)
	var newly_discovered: Array[String] = []
	for vehicle in fleet_sims:
		if vehicle.landed:
			var landed_name := str(vehicle.landed_body_name)
			if SpaceDiscovery.mark_spotted(discovery_state, landed_name) and not newly_discovered.has(landed_name):
				newly_discovered.append(landed_name)
			continue
		var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
		if body.is_empty() or float(body.get("distance", INF)) > float(body.get("soi", 0.0)):
			continue
		var body_name := str(body.get("name", ""))
		if SpaceDiscovery.mark_spotted(discovery_state, body_name) and not newly_discovered.has(body_name):
			newly_discovered.append(body_name)
		if vehicle.crashed:
			continue
		var relative_position: Vector2 = body.relative_position
		var relative_velocity: Vector2 = vehicle.velocity - Vector2(body.get("velocity", Vector2.ZERO))
		var orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(body.get("mass", 0.0)))
		if not bool(orbit.get("bound", false)):
			continue
		var body_radius := float(body.get("radius", 0.0))
		var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(body_name, body_radius)
		var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(body.get("soi", 0.0)))
		var stable_orbit := float(orbit.get("periapsis", 0.0)) > body_radius + minimum_altitude and float(orbit.get("apoapsis", INF)) < body_radius + maximum_altitude
		if stable_orbit:
			orbited_body_names[body_name] = true
		if stable_orbit and SpaceDiscovery.mark_visited(discovery_state, body_name) and not newly_discovered.has(body_name):
			newly_discovered.append(body_name)
	var spotted := SpaceDiscovery.spotted_names(discovery_state)
	var visited := SpaceDiscovery.visited_names(discovery_state)
	for vehicle in fleet_sims:
		vehicle.discovered_body_names = spotted.duplicate()
		vehicle.visited_body_names = visited.duplicate()
	if not newly_discovered.is_empty() and is_instance_valid(status_label):
		status_label.text = "NEW DISCOVERY  •  " + ", ".join(newly_discovered).to_upper()
	_refresh_telescope_control()

func _scan_active_telescopes() -> void:
	if fleet_sims.is_empty() or not is_instance_valid(sim):
		return
	var has_active_telescope := false
	for vehicle in fleet_sims:
		if vehicle.telescope_active and not vehicle.crashed and not vehicle.landed:
			has_active_telescope = true
			break
	if not has_active_telescope:
		return
	var ephemeris := PlanetarySystem.gravity_body_states(sim.sim_time)
	var heliocentric_bodies: Array = ephemeris.get("heliocentric_bodies", [])
	var earth_position: Vector2 = ephemeris.get("earth_heliocentric_position", Vector2.ZERO)
	for vehicle in fleet_sims:
		if not vehicle.telescope_active or vehicle.crashed or vehicle.landed or str(vehicle.payload_visual.get("visual_type", "")) != "satellite":
			continue
		var telescope_range_au := float(vehicle.payload_visual.get("telescope_range_au", 0.0))
		var lifetime_days := float(vehicle.payload_visual.get("operational_lifetime_days", 0.0))
		var operational := lifetime_days <= 0.0 or maxf(0.0, (sim.sim_time - vehicle.launch_time) / 86400.0) < lifetime_days
		if telescope_range_au <= 0.0 or not operational:
			continue
		var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
		if body.is_empty() or float(body.get("distance", INF)) > float(body.get("soi", 0.0)):
			continue
		var relative_position: Vector2 = body.get("relative_position", Vector2.ZERO)
		var relative_velocity: Vector2 = vehicle.velocity - Vector2(body.get("velocity", Vector2.ZERO))
		var orbit := FlightComputer.orbital_state(relative_position, relative_velocity, FlightComputer.G * float(body.get("mass", 0.0)))
		if not bool(orbit.get("bound", false)):
			continue
		var body_name := str(body.get("name", ""))
		var body_radius := float(body.get("radius", 0.0))
		var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(body_name, body_radius)
		var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(body.get("soi", 0.0)))
		if float(orbit.get("periapsis", 0.0)) <= body_radius + minimum_altitude or float(orbit.get("apoapsis", INF)) >= body_radius + maximum_altitude:
			continue
		var host_heliocentric_position := earth_position
		for heliocentric_body in heliocentric_bodies:
			if str(heliocentric_body.get("name", "")) == body_name:
				host_heliocentric_position = Vector2(heliocentric_body.get("position", earth_position))
				break
		var telescope_position: Vector2 = host_heliocentric_position + (vehicle.rocket_position - relative_position)
		vehicle.telescope_direction_angle = relative_velocity.angle()
		var discoveries := SpaceDiscovery.scan_telescope(discovery_state, telescope_position, telescope_range_au * PlanetarySystem.ASTRONOMICAL_UNIT, heliocentric_bodies, vehicle.telescope_direction_angle, vehicle.telescope_field_of_view)
		if not discoveries.is_empty() and is_instance_valid(status_label):
			status_label.text = "NEW DISCOVERY  •  " + ", ".join(discoveries).to_upper()

func _update_passive_orbit_states() -> void:
	for vehicle in fleet_sims:
		if vehicle == sim or _is_docked_child(vehicle.vehicle_name) or vehicle.passive_orbit_forced or vehicle.landed or vehicle.autopilot_enabled or vehicle.thrust_key_down or vehicle.throttle > 0.001 or vehicle.manual_burn_tracking_enabled:
			vehicle.passive_orbit_active = false
			vehicle.passive_orbit_data.clear()
			continue
		if vehicle.passive_orbit_active:
			if _passive_orbit_near_active_vehicle(vehicle):
				vehicle.passive_orbit_active = false
				vehicle.passive_orbit_data.clear()
			continue
		var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
		if body.is_empty() or float(body.get("distance", INF)) > float(body.get("soi", 0.0)):
			continue
		var relative_position: Vector2 = body.relative_position
		var relative_velocity: Vector2 = vehicle.velocity - Vector2(body.get("velocity", Vector2.ZERO))
		var mu := FlightComputer.G * float(body.get("mass", 0.0))
		var orbit := FlightComputer.orbital_state(relative_position, relative_velocity, mu)
		if not bool(orbit.get("bound", false)):
			continue
		var body_radius := float(body.get("radius", 0.0))
		var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(str(body.get("name", "")), body_radius)
		var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(body.get("soi", 0.0)))
		if float(orbit.get("periapsis", 0.0)) <= body_radius + minimum_altitude or float(orbit.get("apoapsis", INF)) >= body_radius + maximum_altitude:
			continue
		var elements := OrbitalPropagator.elements_from_state(relative_position, relative_velocity, mu, vehicle.sim_time)
		if elements.is_empty():
			continue
		vehicle.passive_orbit_data = {"host_body_name": str(body.get("name", "")), "elements": elements}
		vehicle.passive_orbit_active = true

func _passive_orbit_near_active_vehicle(vehicle: SimulationView) -> bool:
	return vehicle.rocket_position.distance_to(sim.rocket_position) <= 20000000.0

func _advance_passive_vehicle(vehicle: SimulationView, target_time: float) -> void:
	var host_name := str(vehicle.passive_orbit_data.get("host_body_name", ""))
	var elements: Dictionary = vehicle.passive_orbit_data.get("elements", {})
	if host_name.is_empty() or elements.is_empty():
		vehicle.passive_orbit_active = false
		vehicle.passive_orbit_data.clear()
		return
	vehicle.sim_time = target_time
	var host := vehicle._surface_body_state(host_name)
	var local_state := OrbitalPropagator.propagate(elements, target_time)
	if host.is_empty() or local_state.is_empty():
		vehicle.passive_orbit_active = false
		vehicle.passive_orbit_data.clear()
		return
	var host_components: PackedFloat64Array = vehicle._body_position_components(host)
	var local_position: Vector2 = local_state.position
	vehicle._set_rocket_position_components(host_components[0] + local_position.x, host_components[1] + local_position.y)
	vehicle.velocity = Vector2(host.get("velocity", Vector2.ZERO)) + Vector2(local_state.velocity)
	vehicle.rotation_angle = local_position.angle() + PI * 0.5

func _set_selected_vehicle_full_simulation() -> void:
	if not is_instance_valid(sim):
		return
	sim.passive_orbit_forced = not sim.passive_orbit_forced
	if sim.passive_orbit_forced:
		sim.passive_orbit_active = false
		sim.passive_orbit_data.clear()
		if status_label:
			status_label.text = "FULL SIMULATION FORCED  •  %s" % sim.vehicle_name.to_upper()
	else:
		if status_label:
			status_label.text = "AUTOMATIC ORBIT SIMULATION ENABLED  •  %s" % sim.vehicle_name.to_upper()

func _show_time_skip_dialog() -> void:
	if not is_instance_valid(sim) or sim.paused:
		return
	var window := Window.new()
	window.title = "FAST FORWARD TIME"
	window.size = Vector2i(620, 300)
	window.min_size = Vector2i(520, 260)
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	window.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var description := Label.new()
	description.text = "Skip ahead while every vehicle is landed or in a safe, stable orbit. Active burns, autopilot, close encounters and unstable trajectories prevent skipping."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(description)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	layout.add_child(options)
	for option in [{"label": "1 DAY", "seconds": 86400.0}, {"label": "7 DAYS", "seconds": 604800.0}, {"label": "30 DAYS", "seconds": 2592000.0}, {"label": "1 YEAR", "seconds": 31557600.0}, {"label": "5 YEARS", "seconds": 157788000.0}]:
		var button := Button.new()
		button.text = str(option.label)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			if _fast_forward_simulation(float(option.seconds)):
				window.queue_free()
			else:
				description.text = "Cannot skip safely right now. Land all vehicles or place them in stable orbits, stop burns and autopilot, and move spacecraft apart."
		)
		options.add_child(button)
	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(window.queue_free)
	layout.add_child(close)
	window.popup_centered()


func _fast_forward_simulation(seconds: float) -> bool:
	if not is_instance_valid(sim) or sim.paused or seconds <= 0.0 or seconds > 157788000.0:
		return false
	if not docking_assists.is_empty():
		return false
	var orbit_data: Dictionary = {}
	for vehicle in fleet_sims:
		if vehicle.crashed:
			continue
		if vehicle.autopilot_enabled or vehicle.thrust_key_down or vehicle.throttle > 0.001 or vehicle.manual_burn_tracking_enabled or vehicle.guidance_enabled:
			return false
		if vehicle.landed:
			continue
		var body: Dictionary = vehicle._nearest_body_state(vehicle.rocket_position, vehicle.rocket_position_precise)
		if body.is_empty() or float(body.get("distance", INF)) > float(body.get("soi", 0.0)):
			return false
		var relative_position: Vector2 = body.get("relative_position", Vector2.ZERO)
		var relative_velocity: Vector2 = vehicle.velocity - Vector2(body.get("velocity", Vector2.ZERO))
		var mu := FlightComputer.G * float(body.get("mass", 0.0))
		var orbit := FlightComputer.orbital_state(relative_position, relative_velocity, mu)
		if not bool(orbit.get("bound", false)):
			return false
		var body_radius := float(body.get("radius", 0.0))
		var minimum_altitude := FlightComputer.minimum_safe_orbit_altitude(str(body.get("name", "")), body_radius)
		var maximum_altitude := FlightComputer.maximum_stable_orbit_altitude(body_radius, float(body.get("soi", 0.0)))
		if float(orbit.get("periapsis", 0.0)) <= body_radius + minimum_altitude or float(orbit.get("apoapsis", INF)) >= body_radius + maximum_altitude:
			return false
		var elements := OrbitalPropagator.elements_from_state(relative_position, relative_velocity, mu, vehicle.sim_time)
		if elements.is_empty():
			return false
		orbit_data[vehicle] = {"host_body_name": str(body.get("name", "")), "elements": elements}
	for first_index in range(fleet_sims.size()):
		for second_index in range(first_index + 1, fleet_sims.size()):
			if fleet_sims[first_index].rocket_position.distance_to(fleet_sims[second_index].rocket_position) < 20000000.0:
				return false
	var start_time := sim.sim_time
	var target_time := start_time + seconds
	var scan_samples := mini(2000, maxi(1, ceili(seconds / 86400.0)))
	var scan_step := seconds / float(scan_samples)
	for sample_index in range(1, scan_samples + 1):
		var sample_time := start_time + scan_step * float(sample_index)
		for vehicle in fleet_sims:
			if not vehicle.telescope_active or vehicle.crashed or vehicle.landed or not orbit_data.has(vehicle):
				continue
			vehicle.passive_orbit_data = orbit_data[vehicle]
			vehicle.passive_orbit_active = true
			_advance_passive_vehicle(vehicle, sample_time)
		_scan_active_telescopes()
	fleet_time_backlog = 0.0
	for vehicle in fleet_sims:
		vehicle.simulation_time_backlog = 0.0
		vehicle.ephemeris_cache_time = -INF
		vehicle.ephemeris_output_cache_time = -INF
		if vehicle.crashed:
			vehicle.sim_time = target_time
		elif vehicle.landed:
			vehicle._physics_step(seconds)
		else:
			vehicle.passive_orbit_data = orbit_data[vehicle]
			vehicle.passive_orbit_active = true
			_advance_passive_vehicle(vehicle, target_time)
		vehicle.sim_time = target_time
		vehicle.ephemeris_cache_time = -INF
		vehicle.ephemeris_output_cache_time = -INF
	sim.sim_time = target_time
	_update_docked_masses()
	_scan_active_telescopes()
	_update_discovery_state()
	_update_economy()
	_update_missions()
	_refresh_vehicle_selector()
	if status_label:
		status_label.text = "TIME SKIPPED  •  %s" % sim._format_time(sim.sim_time)
	sim.queue_redraw()
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if mode != "flight" or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		_save_game(false)
	elif event.keycode == KEY_F9:
		_load_game()
	elif event.keycode == KEY_ESCAPE:
		_pause_simulation()
	elif event.keycode == KEY_J:
		_show_time_skip_dialog()

func _build_menu() -> void:
	mode = "menu"
	fleet_sims.clear()
	sim = null
	vehicle_selector = null
	fleet_time_backlog = 0.0
	docking_links.clear()
	docking_assists.clear()
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
	var screen_size := DisplayServer.screen_get_size()
	var menu_width := minf(480.0, maxf(280.0, screen_size.x - 48.0))
	var menu_height := minf(640.0, maxf(240.0, screen_size.y - 48.0))
	var menu_scroll := ScrollContainer.new()
	menu_scroll.custom_minimum_size = Vector2(menu_width, menu_height)
	menu_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	center.add_child(menu_scroll)
	menu_root = VBoxContainer.new()
	menu_root.custom_minimum_size = Vector2(menu_width, 0)
	menu_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_root.add_theme_constant_override("separation", 18)
	menu_scroll.add_child(menu_root)

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
		if child == sim or child == hud_root:
			child.visible = false
			child.set_process(false)
			child.set_physics_process(false)
		else:
			child.queue_free()
	mode = "editor"
	_show_vehicle_component_editor(0)


func _show_vehicle_component_editor(stage_index: int) -> void:
	if is_instance_valid(active_builder):
		active_builder.free()
		active_builder = null
	if stage_index < 0 or stage_index >= rocket_design.get("stages", []).size():
		return
	var builder := RocketBuilder.new()
	builder.name = "RocketBuilder"
	active_builder = builder
	builder.tree_exited.connect(func():
		if active_builder == builder:
			active_builder = null
	)
	builder.configure(rocket_design, stage_index)
	builder.design_changed.connect(func(updated_design: Dictionary):
		rocket_design = updated_design.duplicate(true)
		_update_design_stats()
	)
	builder.save_requested.connect(_save_rocket_design)
	builder.load_requested.connect(_load_rocket_design)
	builder.payload_edit_requested.connect(_show_payload_editor)
	builder.launch_requested.connect(func():
		if is_instance_valid(active_builder):
			active_builder.queue_free()
			active_builder = null
		_launch_designed_vehicle()
	)
	builder.back_requested.connect(func():
		if is_instance_valid(active_builder):
			active_builder.queue_free()
			active_builder = null
		_show_new_game_setup()
	)
	builder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(builder)


func _duplicate_stage(stage_index: int) -> void:
	if stage_index < 0 or stage_index >= rocket_design["stages"].size():
		return
	var duplicate: Dictionary = rocket_design["stages"][stage_index].duplicate(true)
	rocket_design["stages"].insert(stage_index + 1, duplicate)
	_show_vehicle_editor()


func _show_payload_editor() -> void:
	var visual: Dictionary = rocket_design.get("payload_visual", {}).duplicate(true)
	var visual_type := str(visual.get("visual_type", rocket_design.get("payload_type", "probe")))
	if not ["probe", "crew", "satellite", "cargo"].has(visual_type):
		visual_type = "probe"
	var dialog := ConfirmationDialog.new()
	dialog.title = "EDIT PAYLOAD APPEARANCE"
	dialog.dialog_text = "Change the payload silhouette independently of its physical mass."
	dialog.min_size = Vector2i(500, 390)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	dialog.add_child(content)
	var type_row := HBoxContainer.new()
	var type_label := Label.new()
	type_label.text = "Payload shape"
	type_label.custom_minimum_size.x = 220
	type_row.add_child(type_label)
	var type_selector := OptionButton.new()
	for option in ["probe", "crew", "satellite", "cargo"]:
		type_selector.add_item(option.capitalize())
		type_selector.set_item_metadata(type_selector.item_count - 1, option)
	var selected_type_index := ["probe", "crew", "satellite", "cargo"].find(visual_type)
	type_selector.select(maxi(0, selected_type_index))
	type_row.add_child(type_selector)
	content.add_child(type_row)
	var color: Variant = visual.get("visual_color_rgb", [0.82, 0.87, 0.93])
	if not color is Array or color.size() != 3:
		color = [0.82, 0.87, 0.93]
	var fields := [
		{"key": "visual_width_factor", "label": "Width multiplier", "step": 0.05, "minimum": 0.25, "maximum": 4.0, "default_value": float(visual.get("visual_width_factor", 1.0))},
		{"key": "visual_height_factor", "label": "Height multiplier", "step": 0.05, "minimum": 0.25, "maximum": 4.0, "default_value": float(visual.get("visual_height_factor", 1.0))},
		{"key": "visual_color_r", "label": "Body colour · red", "step": 0.01, "minimum": 0.0, "maximum": 1.0, "default_value": float(color[0])},
		{"key": "visual_color_g", "label": "Body colour · green", "step": 0.01, "minimum": 0.0, "maximum": 1.0, "default_value": float(color[1])},
		{"key": "visual_color_b", "label": "Body colour · blue", "step": 0.01, "minimum": 0.0, "maximum": 1.0, "default_value": float(color[2])}
	]
	var inputs: Dictionary = {}
	for field in fields:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(field.label)
		label.custom_minimum_size.x = 220
		row.add_child(label)
		var input := SpinBox.new()
		input.min_value = float(field.minimum)
		input.max_value = float(field.maximum)
		input.step = float(field.step)
		input.value = float(field.default_value)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.tooltip_text = str(field.key)
		row.add_child(input)
		content.add_child(row)
		inputs[str(field.key)] = input
	dialog.get_ok_button().text = "APPLY"
	dialog.get_cancel_button().text = "CANCEL"
	dialog.confirmed.connect(func():
		var values: Dictionary = {"visual_type": str(type_selector.get_item_metadata(type_selector.selected))}
		for key in inputs:
			values[key] = inputs[key].value
		_apply_payload_editor_values(values)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	dialog.close_requested.connect(func():
		dialog.queue_free()
	)
	add_child(dialog)
	if is_inside_tree():
		dialog.popup_centered()


func _apply_payload_editor_values(values: Dictionary) -> void:
	var visual: Dictionary = rocket_design.get("payload_visual", {}).duplicate(true)
	var visual_type := str(values.get("visual_type", visual.get("visual_type", rocket_design.get("payload_type", "probe"))))
	if not ["probe", "crew", "satellite", "cargo"].has(visual_type):
		return
	visual["visual_type"] = visual_type
	for key in ["visual_width_factor", "visual_height_factor"]:
		if values.has(key):
			visual[key] = clampf(float(values[key]), 0.25, 4.0)
	var color: Variant = visual.get("visual_color_rgb", [0.82, 0.87, 0.93])
	if not color is Array or color.size() != 3:
		color = [0.82, 0.87, 0.93]
	color = color.duplicate()
	for channel in range(3):
		var key: String = ["visual_color_r", "visual_color_g", "visual_color_b"][channel]
		if values.has(key):
			color[channel] = clampf(float(values[key]), 0.0, 1.0)
	visual["visual_color_rgb"] = color
	rocket_design["payload_visual"] = visual
	if is_instance_valid(active_builder) and active_builder is RocketBuilder:
		active_builder.design = rocket_design.duplicate(true)
		active_builder._changed()
	_update_design_stats()


func _show_booster_editor(stage_index: int) -> void:
	if stage_index < 0 or stage_index >= rocket_design.get("stages", []).size():
		return
	var window := Window.new()
	window.title = "STAGE %02d BOOSTER MODULES" % (stage_index + 1)
	window.size = Vector2i(520, 390)
	window.min_size = Vector2i(440, 300)
	window.transient = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	window.add_child(layout)
	var stage: Dictionary = rocket_design["stages"][stage_index]
	var boosters: Array = stage.get("boosters", [])
	var heading := Label.new()
	heading.text = "ATTACHED PAIRS  •  %d" % boosters.size()
	layout.add_child(heading)
	var entries_scroll := ScrollContainer.new()
	entries_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(entries_scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_scroll.add_child(entries)
	for booster_index in range(boosters.size()):
		var booster_entry: Dictionary = boosters[booster_index]
		var definition := RocketDesign.booster_definition_for_entry(booster_entry)
		var row := HBoxContainer.new()
		var details := Label.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.text = "%s  •  %.0f t dry  •  %.0f t propellant  •  %.2f MN thrust" % [
			str(definition.get("label", booster_entry.get("id", "Unknown booster"))),
			RocketDesign.stage_booster_stats({"boosters": [booster_entry]}).dry_mass / 1000.0,
			RocketDesign.stage_booster_stats({"boosters": [booster_entry]}).fuel_capacity / 1000.0,
			RocketDesign.stage_booster_stats({"boosters": [booster_entry]}).thrust / 1000000.0
		]
		row.add_child(details)
		var remove_button := Button.new()
		remove_button.text = "REMOVE"
		remove_button.pressed.connect(func():
			RocketDesign.remove_booster_pair(rocket_design, stage_index, booster_index)
			_update_design_stats()
			window.queue_free()
			_show_booster_editor(stage_index)
		)
		row.add_child(remove_button)
		entries.add_child(row)
	var add_row := HBoxContainer.new()
	var booster_selector := OptionButton.new()
	booster_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var options := RocketDesign.booster_options()
	for option in options:
		booster_selector.add_item(str(option.get("label", option.get("id", "Booster"))))
		booster_selector.set_item_metadata(booster_selector.item_count - 1, str(option.get("id", "")))
	if booster_selector.item_count > 0:
		booster_selector.select(0)
	add_row.add_child(booster_selector)
	var add_button := Button.new()
	add_button.text = "ADD PAIR"
	add_button.disabled = options.is_empty()
	add_button.pressed.connect(func():
		if RocketDesign.add_booster_pair(rocket_design, stage_index, str(booster_selector.get_selected_metadata())):
			_update_design_stats()
			window.queue_free()
			_show_booster_editor(stage_index)
	)
	add_row.add_child(add_button)
	layout.add_child(add_row)
	_add_button(layout, "CLOSE", func(): window.queue_free())
	window.popup_centered()

func _show_stage_editor(stage_index: int) -> void:
	if stage_index < 0 or stage_index >= rocket_design["stages"].size():
		return
	var stage: Dictionary = rocket_design["stages"][stage_index].duplicate(true)
	var dialog := ConfirmationDialog.new()
	dialog.title = "EDIT STAGE %02d" % (stage_index + 1)
	dialog.dialog_text = "Physical values are per engine. Visual factors change the workshop and flight model."
	var screen_size := DisplayServer.screen_get_size()
	dialog.min_size = Vector2i(mini(520, screen_size.x - 40), mini(480, screen_size.y - 80))
	var content_scroll := ScrollContainer.new()
	content_scroll.custom_minimum_size = Vector2(0, mini(390, screen_size.y - 190))
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content)
	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Stage name"
	name_label.custom_minimum_size.x = 220
	name_row.add_child(name_label)
	var name_input := LineEdit.new()
	name_input.text = str(stage.get("name", "CUSTOM STAGE"))
	name_input.placeholder_text = "Stage name"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.tooltip_text = "stage_name"
	name_row.add_child(name_input)
	content.add_child(name_row)
	var layout_row := HBoxContainer.new()
	var layout_label := Label.new()
	layout_label.text = "Engine arrangement"
	layout_label.custom_minimum_size.x = 220
	layout_row.add_child(layout_label)
	var engine_layout_selector := OptionButton.new()
	var engine_layout := str(stage.get("engine_layout", "linear"))
	if not ["linear", "cluster", "radial"].has(engine_layout):
		engine_layout = "linear"
	for layout_option in ["linear", "cluster", "radial"]:
		engine_layout_selector.add_item(layout_option.capitalize())
		engine_layout_selector.set_item_metadata(engine_layout_selector.item_count - 1, layout_option)
	engine_layout_selector.select(["linear", "cluster", "radial"].find(engine_layout))
	layout_row.add_child(engine_layout_selector)
	content.add_child(layout_row)
	var default_color := [0.35, 0.57, 0.71] if stage_index % 2 == 0 else [0.43, 0.63, 0.75]
	var stage_color: Variant = stage.get("visual_color_rgb", default_color)
	if not stage_color is Array or stage_color.size() != 3:
		stage_color = default_color
	var fields := [
		{"key": "dry_mass", "label": "Dry mass (kg)", "step": 1.0},
		{"key": "fuel_capacity", "label": "Propellant capacity (kg)", "step": 1.0},
		{"key": "thrust", "label": "Sea-level thrust per engine (N)", "step": 100.0},
		{"key": "vacuum_thrust", "label": "Vacuum thrust per engine (N)", "step": 100.0},
		{"key": "flow", "label": "Fuel flow per engine (kg/s)", "step": 0.1},
		{"key": "visual_length_factor", "label": "Visual length multiplier", "step": 0.05, "minimum": 0.25, "maximum": 100.0},
		{"key": "visual_diameter_factor", "label": "Visual diameter multiplier", "step": 0.05, "minimum": 0.25, "maximum": 100.0},
		{"key": "visual_color_r", "label": "Body colour · red", "step": 0.01, "minimum": 0.0, "maximum": 1.0, "default_value": float(stage_color[0])},
		{"key": "visual_color_g", "label": "Body colour · green", "step": 0.01, "minimum": 0.0, "maximum": 1.0, "default_value": float(stage_color[1])},
		{"key": "visual_color_b", "label": "Body colour · blue", "step": 0.01, "minimum": 0.0, "maximum": 1.0, "default_value": float(stage_color[2])}
	]
	var inputs: Dictionary = {}
	for field in fields:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(field.label)
		label.custom_minimum_size.x = 220
		row.add_child(label)
		var input := SpinBox.new()
		input.min_value = float(field.get("minimum", 0.001))
		input.max_value = float(field.get("maximum", 1.0e300))
		input.step = float(field.step)
		input.value = float(field.get("default_value", stage.get(str(field.key), 1.0)))
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.tooltip_text = str(field.key)
		row.add_child(input)
		content.add_child(row)
		inputs[str(field.key)] = input
	dialog.get_ok_button().text = "APPLY"
	dialog.get_cancel_button().text = "CANCEL"
	dialog.confirmed.connect(func():
		var values: Dictionary = {"name": name_input.text.strip_edges(), "engine_layout": str(engine_layout_selector.get_item_metadata(engine_layout_selector.selected))}
		for key in inputs:
			values[key] = inputs[key].value
		_apply_stage_editor_values(stage_index, values)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	dialog.close_requested.connect(func():
		dialog.queue_free()
	)
	add_child(dialog)
	if is_inside_tree():
		dialog.popup_centered()

func _apply_stage_editor_values(stage_index: int, values: Dictionary) -> void:
	if stage_index < 0 or stage_index >= rocket_design["stages"].size():
		return
	var updated_stage: Dictionary = rocket_design["stages"][stage_index].duplicate(true)
	if values.has("name"):
		var stage_name := str(values["name"]).strip_edges()
		updated_stage["name"] = stage_name if not stage_name.is_empty() else "CUSTOM STAGE"
	if values.has("engine_layout"):
		updated_stage["engine_layout"] = str(values["engine_layout"])
	for key in ["dry_mass", "fuel_capacity", "thrust", "vacuum_thrust", "flow", "visual_length_factor", "visual_diameter_factor"]:
		if values.has(key):
			updated_stage[key] = float(values[key])
	var color_keys := ["visual_color_r", "visual_color_g", "visual_color_b"]
	var has_color_value := false
	var color: Variant = updated_stage.get("visual_color_rgb", [0.35, 0.57, 0.71] if stage_index % 2 == 0 else [0.43, 0.63, 0.75])
	if not color is Array or color.size() != 3:
		color = [0.35, 0.57, 0.71] if stage_index % 2 == 0 else [0.43, 0.63, 0.75]
	color = color.duplicate()
	for channel in range(color_keys.size()):
		if values.has(color_keys[channel]):
			color[channel] = clampf(float(values[color_keys[channel]]), 0.0, 1.0)
			has_color_value = true
	if has_color_value:
		updated_stage["visual_color_rgb"] = color
	rocket_design["stages"][stage_index] = updated_stage
	_update_design_stats()


func _update_design_stats() -> void:
	if not is_instance_valid(design_stats_label) or not is_instance_valid(design_error_label):
		return
	var errors := RocketDesign.validation_errors(rocket_design)
	var total_mass := RocketDesign.total_initial_mass(rocket_design)
	var delta_v := RocketDesign.total_delta_v(rocket_design)
	var stages: Array = rocket_design["stages"]
	var first: Dictionary = stages[0]
	var initial_twr := RocketDesign.stage_total_thrust(first) / maxf(1.0, total_mass * 9.80665)
	var engine_report := PackedStringArray()
	for i in range(stages.size()):
		var stage: Dictionary = stages[i]
		var sea_isp := RocketDesign.stage_specific_impulse(stage, false)
		var vacuum_isp := RocketDesign.stage_specific_impulse(stage, true)
		var ignition_mass := RocketDesign.stage_ignition_mass(rocket_design, i)
		var stage_thrust := RocketDesign.stage_total_thrust(stage, i != 0)
		var stage_twr := stage_thrust / maxf(1.0, ignition_mass * 9.80665)
		engine_report.append("STAGE %d  •  Isp %.0f / %.0f s  •  TWR %.2f" % [i + 1, sea_isp, vacuum_isp, stage_twr])
	design_stats_label.text = "INITIAL MASS\n%.1f tonnes\n\nIDEAL ΔV\n%.2f km/s\n\nPAD TWR\n%.2f\n\n%s" % [total_mass / 1000.0, delta_v / 1000.0, initial_twr, "\n".join(engine_report)]
	design_error_label.text = "\n".join(errors) if not errors.is_empty() else "DESIGN VALID"
	if is_instance_valid(design_preview):
		design_preview.design = rocket_design
		design_preview.queue_redraw()

func _design_library_directory() -> String:
	return "user://rocket_designs"


func _design_library_files() -> PackedStringArray:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_design_library_directory()))
	var files := PackedStringArray()
	var directory := DirAccess.open(_design_library_directory())
	if directory == null:
		return files
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.get_extension().to_lower() == "json":
			files.append(filename)
		filename = directory.get_next()
	directory.list_dir_end()
	files.sort()
	if files.is_empty() and FileAccess.file_exists("user://rocket_design.json"):
		var legacy_file := FileAccess.open("user://rocket_design.json", FileAccess.READ)
		if legacy_file != null:
			var legacy_design: Variant = JSON.parse_string(legacy_file.get_as_text())
			legacy_file.close()
			if legacy_design is Dictionary and RocketDesign.validation_errors(legacy_design).is_empty():
				var legacy_name := str(legacy_design.get("name", "Imported Design"))
				var safe_name := legacy_name.to_lower().replace(" ", "_")
				var safe_chars := ""
				for character in safe_name:
					if character.is_valid_identifier() or character in ["-", "_"]:
						safe_chars += character
				if safe_chars.is_empty():
					safe_chars = "imported_design"
				var migrated := FileAccess.open("%s/%s.json" % [_design_library_directory(), safe_chars], FileAccess.WRITE)
				if migrated != null:
					migrated.store_string(JSON.stringify(legacy_design, "\t"))
					migrated.close()
					files.append("%s.json" % safe_chars)
	return files


func _save_rocket_design() -> void:
	var errors := RocketDesign.validation_errors(rocket_design)
	if not errors.is_empty():
		_update_design_stats()
		return
	var window := Window.new()
	window.title = "SAVE VEHICLE DESIGN"
	window.size = Vector2i(520, 190)
	window.min_size = Vector2i(440, 170)
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 10)
	layout.add_theme_constant_override("margin_left", 16)
	layout.add_theme_constant_override("margin_right", 16)
	layout.add_theme_constant_override("margin_top", 14)
	layout.add_theme_constant_override("margin_bottom", 14)
	window.add_child(layout)
	var name_input := LineEdit.new()
	name_input.text = str(rocket_design.get("name", "Custom Vehicle"))
	name_input.placeholder_text = "Design name"
	layout.add_child(name_input)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(actions)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.pressed.connect(window.queue_free)
	actions.add_child(cancel)
	var save := Button.new()
	save.text = "SAVE TO LIBRARY"
	save.pressed.connect(func():
		var design_name := name_input.text.strip_edges()
		if design_name.is_empty():
			return
		var safe_name := design_name.to_lower().replace(" ", "_")
		var safe_chars := ""
		for character in safe_name:
			if character.is_valid_identifier() or character in ["-", "_"]:
				safe_chars += character
		if safe_chars.is_empty():
			return
		var saved_design := rocket_design.duplicate(true)
		saved_design["name"] = design_name
		var path := "%s/%s.json" % [_design_library_directory(), safe_chars]
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return
		file.store_string(JSON.stringify(saved_design, "\t"))
		file.close()
		rocket_design = saved_design
		if is_instance_valid(active_builder) and active_builder is RocketBuilder:
			active_builder.load_design(saved_design)
		if is_instance_valid(design_error_label):
			design_error_label.text = "DESIGN SAVED TO LIBRARY"
		window.queue_free()
	)
	actions.add_child(save)
	window.popup_centered()


func _load_rocket_design() -> void:
	var files := _design_library_files()
	if files.is_empty():
		if is_instance_valid(design_error_label):
			design_error_label.text = "NO DESIGNS IN LIBRARY"
		return
	var window := Window.new()
	window.title = "ROCKET DESIGN LIBRARY"
	window.size = Vector2i(620, 420)
	window.min_size = Vector2i(500, 320)
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(window.queue_free)
	add_child(window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	window.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for filename in files:
		var path := "%s/%s" % [_design_library_directory(), filename]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary and RocketDesign.validation_errors(parsed).is_empty():
			selector.add_item(str(parsed.get("name", filename.get_basename())))
			selector.set_item_metadata(selector.item_count - 1, filename)
	layout.add_child(selector)
	var info := Label.new()
	info.text = "Saved designs are stored locally and remain available between sessions."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(info)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(actions)
	var close := Button.new()
	close.text = "CLOSE"
	close.pressed.connect(window.queue_free)
	actions.add_child(close)
	var delete := Button.new()
	delete.text = "DELETE"
	delete.disabled = selector.item_count == 0
	delete.pressed.connect(func():
		if selector.item_count == 0:
			return
		var filename := str(selector.get_item_metadata(selector.selected))
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [_design_library_directory(), filename]))
		window.queue_free()
		_load_rocket_design()
	)
	actions.add_child(delete)
	var load := Button.new()
	load.text = "LOAD DESIGN"
	load.disabled = selector.item_count == 0
	load.pressed.connect(func():
		if selector.item_count == 0:
			return
		var filename := str(selector.get_item_metadata(selector.selected))
		var path := "%s/%s" % [_design_library_directory(), filename]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary and RocketDesign.validation_errors(parsed).is_empty():
			rocket_design = parsed.duplicate(true)
			if is_instance_valid(active_builder) and active_builder is RocketBuilder:
				active_builder.load_design(rocket_design)
			else:
				_show_vehicle_editor()
			window.queue_free()
	)
	actions.add_child(load)
	window.popup_centered()

func _launch_designed_vehicle() -> void:
	var errors := RocketDesign.validation_errors(rocket_design)
	if not errors.is_empty():
		_update_design_stats()
		return
	_start_flight()

func _begin_new_game() -> void:
	discovery_state = SpaceDiscovery.new_campaign_state()
	funds = STARTING_FUNDS
	economy_last_sim_time = 0.0
	total_revenue_earned = 0.0
	total_operating_costs = 0.0
	mission_state = MissionSystem.new_state()
	orbited_body_names.clear()
	rocket_design = RocketDesign.create_default()
	infinite_weightless_fuel = false
	new_game_slot = 1
	for slot in range(1, 9):
		if not _save_exists(slot):
			new_game_slot = slot
			break
	_show_new_game_setup()

func _confirm_new_game_slot() -> void:
	if _save_exists(new_game_slot):
		var confirmation := ConfirmationDialog.new()
		confirmation.title = "OVERWRITE SAVE?"
		confirmation.dialog_text = "SLOT %02d already contains a game. Starting here will replace that save. Its previous state will be kept in save history." % new_game_slot
		confirmation.ok_button_text = "OVERWRITE SLOT %02d" % new_game_slot
		confirmation.confirmed.connect(func():
			save_slot = new_game_slot
			_show_vehicle_editor()
		)
		add_child(confirmation)
		confirmation.popup_centered()
		return
	save_slot = new_game_slot
	_show_vehicle_editor()

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
	var screen_size := DisplayServer.screen_get_size()
	var setup_width := minf(560.0, maxf(280.0, screen_size.x - 48.0))
	var setup_height := minf(720.0, maxf(240.0, screen_size.y - 48.0))
	var setup_scroll := ScrollContainer.new()
	setup_scroll.custom_minimum_size = Vector2(setup_width, setup_height)
	setup_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	setup_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	setup_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	center.add_child(setup_scroll)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(setup_width, 0)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	setup_scroll.add_child(root)
	var heading := Label.new()
	heading.text = "NEW GAME SETUP"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	heading.add_theme_color_override("font_color", Color(0.78, 0.9, 1.0))
	root.add_child(heading)
	_add_setting_label(root, "SAVE SLOT")
	var slot_picker := OptionButton.new()
	for slot in range(1, 9):
		var slot_status := "EMPTY" if not _save_exists(slot) else "EXISTING SAVE  •  OVERWRITE"
		slot_picker.add_item("SLOT %02d  •  %s" % [slot, slot_status])
	slot_picker.select(new_game_slot - 1)
	slot_picker.item_selected.connect(func(index: int): new_game_slot = index + 1)
	root.add_child(slot_picker)
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
	_add_button(root, "CONTINUE TO ROCKET BUILDER", _confirm_new_game_slot)
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
	layout.custom_minimum_size = Vector2(minf(620.0, DisplayServer.screen_get_size().x - 48.0), 0)
	layout.add_theme_constant_override("separation", 12)
	center.add_child(layout)
	var heading := Label.new()
	heading.text = "LOAD GAME"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 32)
	layout.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(620.0, DisplayServer.screen_get_size().x - 48.0), minf(560.0, DisplayServer.screen_get_size().y - 220.0))
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
				var vehicle_count: int = 1
				var saved_vehicles: Variant = parsed.get("vehicles", [])
				if saved_vehicles is Array:
					vehicle_count = saved_vehicles.size()
				var saved_at := int(parsed.get("saved_at_unix", FileAccess.get_modified_time(path)))
				var saved_text := Time.get_datetime_string_from_unix_time(saved_at, true)
				var save_name := str(parsed.get("save_name", "Unnamed campaign"))
				var label := "SLOT %02d  •  %s  •  %d VEHICLES  •  %s" % [slot, save_name, vehicle_count, saved_text]
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
			var history_kind := "MANUAL BACKUP" if history_path.get_file().begins_with("manual_") else "AUTOSAVE"
			var history_label := "     ↳ %s  •  %s" % [history_kind, Time.get_datetime_string_from_unix_time(history_time, true)]
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
	var screen_size := DisplayServer.screen_get_size()
	var settings_width := minf(520.0, maxf(280.0, screen_size.x - 48.0))
	var settings_height := minf(720.0, maxf(240.0, screen_size.y - 48.0))
	var settings_scroll := ScrollContainer.new()
	settings_scroll.custom_minimum_size = Vector2(settings_width, settings_height)
	settings_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	settings_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	center.add_child(settings_scroll)
	settings_root = VBoxContainer.new()
	settings_root.custom_minimum_size = Vector2(settings_width, 0)
	settings_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_root.add_theme_constant_override("separation", 14)
	settings_scroll.add_child(settings_root)
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
	vehicle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vehicle.set_rocket_design(design)
	vehicle.stage_separated.connect(_queue_discarded_stage)
	add_child(vehicle)
	vehicle.set_process(false)
	if not saved_state.is_empty() and not vehicle.load_save_data(saved_state):
		vehicle.queue_free()
		return null
	vehicle.input_enabled = false
	vehicle.visible = false
	vehicle.set_process(false)
	return vehicle

func _queue_discarded_stage(stage_data: Dictionary) -> void:
	pending_debris.append(stage_data.duplicate(true))

func _spawn_discarded_stage(stage_data: Dictionary) -> void:
	var stage: Variant = stage_data.get("stage", {})
	if not stage is Dictionary or stage.is_empty():
		return
	debris_sequence += 1
	var debris_name := "Debris %04d" % debris_sequence
	var design := {
		"name": debris_name,
		"payload_mass": 0.001,
		"payload_type": "debris",
		"stages": [stage.duplicate(true)]
	}
	var debris := _create_vehicle(design, debris_name)
	if debris == null:
		return
	var remaining_fuel := maxf(0.0, float(stage_data.get("fuel", 0.0)))
	debris.fuel = remaining_fuel
	debris.infinite_fuel_stage_remaining = remaining_fuel
	debris.stage_fuel_remaining[0] = remaining_fuel
	var position_components: Variant = stage_data.get("position_components", PackedFloat64Array([0.0, 0.0]))
	if position_components is PackedFloat64Array and position_components.size() >= 2:
		debris._set_rocket_position_components(float(position_components[0]), float(position_components[1]))
	elif position_components is Array and position_components.size() >= 2:
		debris._set_rocket_position_components(float(position_components[0]), float(position_components[1]))
	debris.velocity = stage_data.get("velocity", Vector2.ZERO)
	debris.separation_parent_name = str(stage_data.get("parent_vehicle_name", ""))
	debris.rotation_angle = float(stage_data.get("rotation_angle", 0.0))
	debris.sim_time = float(stage_data.get("sim_time", sim.sim_time if is_instance_valid(sim) else 0.0))
	debris.launch_time = float(stage_data.get("launch_time", debris.sim_time))
	debris.time_warp = sim.time_warp if is_instance_valid(sim) else 1.0
	debris.is_debris = true
	debris.input_enabled = false
	debris.infinite_weightless_fuel = false
	debris.thrust_key_down = false
	debris.guidance_enabled = false
	debris.autopilot_enabled = false
	debris.throttle = 0.0
	debris.landed = false
	debris.crashed = false
	fleet_sims.append(debris)
	_refresh_vehicle_selector()

func _start_flight() -> void:
	if is_instance_valid(active_builder):
		active_builder.free()
		active_builder = null
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
		"payload_type": sim.payload_type,
		"payload_visual": sim.payload_visual.duplicate(true),
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
	var launch_cost := _launch_cost_for_design(design)
	if career_enabled and funds < launch_cost:
		if status_label:
			status_label.text = "INSUFFICIENT FUNDS  •  NEED %.1f M CREDITS" % (launch_cost / 1000000.0)
		return
	var new_name := "Vehicle %d" % (fleet_sims.size() + 1)
	var vehicle := _create_vehicle(design, new_name)
	vehicle.sim_time = sim.sim_time
	vehicle.launch_time = sim.sim_time
	vehicle.time_warp = sim.time_warp
	if career_enabled:
		funds -= launch_cost
	_refresh_economy_display()
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
		"payload_type": sim.payload_type,
		"payload_visual": sim.payload_visual.duplicate(true),
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
	var custom_button := Button.new()
	custom_button.text = "BUILD A CUSTOM ROCKET"
	custom_button.custom_minimum_size.y = 40
	custom_button.pressed.connect(func():
		window.queue_free()
		_show_fleet_custom_builder()
	)
	layout.add_child(custom_button)
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
	if is_inside_tree():
		window.call_deferred("popup_centered")

func _show_fleet_custom_builder() -> void:
	rocket_design = RocketDesign.create_blank()
	var window := Window.new()
	window.title = "CUSTOM VEHICLE WORKSHOP"
	window.size = Vector2i(1440, 900)
	window.min_size = Vector2i(900, 620)
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(func():
		if active_builder is RocketBuilder:
			active_builder = null
		window.queue_free()
	)
	add_child(window)
	var builder := RocketBuilder.new()
	builder.configure(rocket_design, 0)
	active_builder = builder
	builder.tree_exited.connect(func():
		if active_builder == builder:
			active_builder = null
	)
	builder.design_changed.connect(func(updated_design: Dictionary):
		rocket_design = updated_design.duplicate(true)
	)
	builder.save_requested.connect(_save_rocket_design)
	builder.load_requested.connect(func():
		_load_rocket_design()
	)
	builder.payload_edit_requested.connect(_show_payload_editor)
	builder.launch_requested.connect(func():
		var errors := RocketDesign.validation_errors(rocket_design)
		if not errors.is_empty():
			return
		_launch_vehicle_design(rocket_design.duplicate(true))
		if active_builder == builder:
			active_builder = null
		window.queue_free()
	)
	builder.back_requested.connect(func():
		if active_builder == builder:
			active_builder = null
		window.queue_free()
	)
	builder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(builder)
	window.popup_centered()

func _populate_fleet_builder_stages(stage_list: VBoxContainer, design: Dictionary, window: Window) -> void:
	for child in stage_list.get_children():
		child.queue_free()
	var part_options := RocketDesign.stage_part_options()
	var engine_options := RocketDesign.engine_count_options()
	var tank_options := RocketDesign.tank_scale_options()
	for stage_index in range(design.get("stages", []).size()):
		var stage: Dictionary = design["stages"][stage_index]
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		stage_list.add_child(row)
		var controls := HBoxContainer.new()
		row.add_child(controls)
		var part_selector := OptionButton.new()
		part_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected_part := 0
		for i in range(part_options.size()):
			part_selector.add_item(str(part_options[i].get("label", part_options[i].get("id", "Stage"))))
			part_selector.set_item_metadata(i, str(part_options[i].get("id", "")))
			if str(stage.get("part_id", "")) == str(part_options[i].get("id", "")):
				selected_part = i
		if part_selector.item_count > 0:
			part_selector.select(selected_part)
		part_selector.item_selected.connect(func(option_index: int):
			var replacement := RocketDesign.configure_stage(str(part_selector.get_item_metadata(option_index)), int(stage.get("engine_count", 1)), float(stage.get("tank_scale", 1.0)))
			if not replacement.is_empty():
				design["stages"][stage_index] = replacement
				_populate_fleet_builder_stages(stage_list, design, window)
		)
		controls.add_child(part_selector)
		var edit_stage_button := Button.new()
		edit_stage_button.text = "EDIT"
		edit_stage_button.pressed.connect(func(): _show_stage_editor(stage_index))
		controls.add_child(edit_stage_button)
		var engine_selector := OptionButton.new()
		for count in engine_options:
			engine_selector.add_item("%d engines" % int(count))
			engine_selector.set_item_metadata(engine_selector.item_count - 1, int(count))
		var current_engine := int(stage.get("engine_count", 1))
		var engine_index := engine_options.find(current_engine)
		if engine_index >= 0:
			engine_selector.select(engine_index)
		engine_selector.item_selected.connect(func(option_index: int):
			var configured := RocketDesign.reconfigure_stage(design["stages"][stage_index], int(engine_selector.get_item_metadata(option_index)), float(stage.get("tank_scale", 1.0)))
			if not configured.is_empty():
				design["stages"][stage_index] = configured
				_populate_fleet_builder_stages(stage_list, design, window)
		)
		controls.add_child(engine_selector)
		var tank_selector := OptionButton.new()
		var tank_index := 0
		for i in range(tank_options.size()):
			tank_selector.add_item(str(tank_options[i].get("label", "Tank")))
			tank_selector.set_item_metadata(i, float(tank_options[i].get("scale", 1.0)))
			if is_equal_approx(float(stage.get("tank_scale", 1.0)), float(tank_options[i].get("scale", 1.0))):
				tank_index = i
		if tank_selector.item_count > 0:
			tank_selector.select(tank_index)
		tank_selector.item_selected.connect(func(option_index: int):
			var configured := RocketDesign.reconfigure_stage(design["stages"][stage_index], int(stage.get("engine_count", 1)), float(tank_selector.get_item_metadata(option_index)))
			if not configured.is_empty():
				design["stages"][stage_index] = configured
				_populate_fleet_builder_stages(stage_list, design, window)
		)
		controls.add_child(tank_selector)
		var booster_button := Button.new()
		booster_button.text = "BOOSTERS (%d)" % stage.get("boosters", []).size()
		booster_button.pressed.connect(func():
			rocket_design = design
			_show_booster_editor(stage_index)
		)
		controls.add_child(booster_button)
		var remove_button := Button.new()
		remove_button.text = "REMOVE"
		remove_button.disabled = design["stages"].size() <= RocketDesign.MIN_STAGES
		remove_button.pressed.connect(func():
			design["stages"].remove_at(stage_index)
			_populate_fleet_builder_stages(stage_list, design, window)
		)
		controls.add_child(remove_button)
		var stage_name := Label.new()
		stage_name.text = "STAGE %02d  •  %s" % [stage_index + 1, str(stage.get("name", "CUSTOM STAGE"))]
		row.add_child(stage_name)


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
	sim.discovered_body_names = SpaceDiscovery.spotted_names(discovery_state)
	sim.visited_body_names = SpaceDiscovery.visited_names(discovery_state)
	sim.input_enabled = not _is_docked_child(sim.vehicle_name) and not sim.crashed
	sim.visible = true
	sim.time_warp = fleet_sims[0].time_warp
	if sim.show_predicted_trajectory:
		sim._calculate_predicted_trajectory()
	rocket_design = {
		"name": sim.vehicle_name,
		"payload_mass": sim.payload_mass,
		"payload_type": sim.payload_type,
		"payload_visual": sim.payload_visual.duplicate(true),
		"stages": sim.rocket_stages.duplicate(true)
	}
	_refresh_vehicle_selector()
	_refresh_telescope_control()
	if status_label:
		if _is_docked_child(sim.vehicle_name):
			for link in docking_links:
				if str(link.get("child_name", "")) == sim.vehicle_name:
					status_label.text = "%s  •  DOCKED TO %s" % [sim.vehicle_name.to_upper(), str(link.get("parent_name", "")).to_upper()]
					return
		status_label.text = "%s  •  %s" % [sim.vehicle_name.to_upper(), sim.status_message]

func _refresh_telescope_control() -> void:
	if not is_instance_valid(telescope_button) or not is_instance_valid(sim):
		return
	var available := str(sim.payload_visual.get("visual_type", "")) == "satellite" and float(sim.payload_visual.get("telescope_range_au", 0.0)) > 0.0
	telescope_button.disabled = not available
	telescope_button.text = "TELESCOPE ACTIVE  [T]" if sim.telescope_active else "ACTIVATE TELESCOPE  [T]"
	if available:
		telescope_button.tooltip_text = "Continuously scans a 30-degree field in the direction of orbital travel while in stable orbit."
	else:
		telescope_button.tooltip_text = "Select a satellite equipped with a telescope."

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
	if docking_assists.has(previous_name):
		docking_assists[clean_name] = docking_assists[previous_name]
		docking_assists.erase(previous_name)
	for assist_vehicle in docking_assists.keys():
		if str(docking_assists[assist_vehicle]) == previous_name:
			docking_assists[assist_vehicle] = clean_name
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
		var simulation_state := "PASSIVE ORBIT" if vehicle.passive_orbit_active else "FULL SIMULATION"
		var profile: Dictionary = vehicle.payload_visual
		var role := str(profile.get("satellite_role", ""))
		var lifetime_days := float(profile.get("operational_lifetime_days", 0.0))
		var age_days := maxf(0.0, (sim.sim_time - vehicle.launch_time) / 86400.0)
		var operation_state := ""
		if not role.is_empty():
			operation_state = "SATELLITE  •  %s  •  %s" % [role.to_upper(), "EXPIRED" if lifetime_days > 0.0 and age_days >= lifetime_days else "OPERATIONAL"]
		else:
			operation_state = "GENERAL SPACECRAFT"
			if lifetime_days > 0.0:
				operation_state += "  •  %.1f YEARS LEFT" % (maxf(0.0, lifetime_days - age_days) / 365.25)
			var telescope_range := float(profile.get("telescope_range_au", 0.0))
			if telescope_range > 0.0:
				operation_state += "  •  %.1f AU TELESCOPE" % telescope_range
		var details := Label.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.text = "%s\n%s  •  %s  •  %.0f km altitude  •  %.0f%% fuel\n%s  •  %s" % [vehicle.vehicle_name, state, str(body.get("name", "Deep space")), altitude / 1000.0, fuel_percent, simulation_state, operation_state]
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
		var remove_button := Button.new()
		remove_button.text = "DECOMMISSION"
		remove_button.disabled = fleet_sims.size() <= 1 or _is_vehicle_docked(vehicle.vehicle_name)
		remove_button.pressed.connect(_show_decommission_vehicle_dialog.bind(vehicle, window))
		row.add_child(remove_button)
	_add_button(layout, "CLOSE", func(): window.queue_free())
	window.popup_centered()


func _show_decommission_vehicle_dialog(vehicle: SimulationView, fleet_window: Window) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "DECOMMISSION SPACECRAFT"
	dialog.dialog_text = "Permanently remove %s from the active fleet?" % vehicle.vehicle_name
	dialog.confirmed.connect(func():
		if _decommission_vehicle(vehicle):
			fleet_window.queue_free()
			_show_fleet_management_panel()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _decommission_vehicle(vehicle: SimulationView) -> bool:
	if fleet_sims.size() <= 1 or _is_vehicle_docked(vehicle.vehicle_name):
		return false
	var index := fleet_sims.find(vehicle)
	if index < 0:
		return false
	if index == active_vehicle_index:
		var replacement_index := -1
		for candidate_index in range(fleet_sims.size()):
			if candidate_index != index and not _is_docked_child(fleet_sims[candidate_index].vehicle_name):
				replacement_index = candidate_index
				break
		if replacement_index < 0:
			return false
		_switch_vehicle(replacement_index)
		if index < active_vehicle_index:
			active_vehicle_index -= 1
	elif index < active_vehicle_index:
		active_vehicle_index -= 1
	fleet_sims.remove_at(index)
	vehicle.queue_free()
	active_vehicle_index = clampi(active_vehicle_index, 0, fleet_sims.size() - 1)
	_refresh_vehicle_selector()
	_switch_vehicle(active_vehicle_index)
	return true

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
			"rotation": parent.rotation_angle,
			"design": {"name": child.vehicle_name, "payload_mass": child.payload_mass, "payload_type": child.payload_type, "payload_visual": child.payload_visual.duplicate(true), "stages": child.rocket_stages},
			"stage_index": child.stage_index
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
	if _is_docked_child(sim.vehicle_name) or _is_vehicle_docked(target.vehicle_name):
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
	docking_assists.erase(sim.vehicle_name)
	docking_assists.erase(target.vehicle_name)
	for assist_vehicle in docking_assists.keys():
		if str(docking_assists[assist_vehicle]) == target.vehicle_name:
			docking_assists.erase(assist_vehicle)
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
	mode = "flight"
	if is_instance_valid(hud_root):
		hud_root.queue_free()
	if is_instance_valid(sim):
		sim.visible = true
		sim.set_process(false)
		sim.set_physics_process(false)
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(hud_root)

	var top := PanelContainer.new()
	top.custom_minimum_size = Vector2(0, 0)
	flight_hud_top = top
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
	funds_label = Label.new()
	funds_label.visible = career_enabled
	info.add_child(funds_label)
	_refresh_economy_display()

	var right_scroll := ScrollContainer.new()
	right_scroll.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_scroll.anchor_bottom = 1.0
	right_scroll.offset_left = -270
	right_scroll.offset_right = -18
	right_scroll.offset_top = 18
	right_scroll.offset_bottom = -78
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	flight_hud_right_scroll = right_scroll
	hud_root.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 0
	flight_hud_right = right
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)

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
	_add_button(right, "TOGGLE FULL SIMULATION", _set_selected_vehicle_full_simulation)
	_add_button(right, "BUILD / LAUNCH VEHICLE", _show_new_vehicle_dialog)
	_add_button(right, "FLEET MANAGER", _show_fleet_management_panel)
	_add_button(right, "DOCKING & FUEL", _show_docking_panel)
	telescope_button = Button.new()
	telescope_button.text = "ACTIVATE TELESCOPE  [T]"
	telescope_button.disabled = true
	telescope_button.pressed.connect(func():
		if not is_instance_valid(sim):
			return
		sim.telescope_active = not sim.telescope_active
		_refresh_telescope_control()
		if is_instance_valid(status_label):
			status_label.text = "TELESCOPE ACTIVE  •  PROGRADE SCANNING" if sim.telescope_active else "TELESCOPE STANDBY"
	)
	right.add_child(telescope_button)

	_add_button(right, "SOLAR SYSTEM VIEW  [M]", func(): sim.show_solar_system = not sim.show_solar_system)
	_add_button(right, "VELOCITY VECTOR  [V]", func(): sim.show_vectors = not sim.show_vectors)
	_add_button(right, "MISSIONS / CONTRACTS", _show_missions_panel)
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
	bottom.text = "W ENGINE ON/OFF     S CUTOFF     X STAGE     Q / E GIMBAL     A / D ROTATE\nH GUIDANCE     T TELESCOPE ON/OFF     V VELOCITY VECTOR     M SOLAR SYSTEM     P PREDICTED PATH     SPACE PAUSE     +/- WARP     J FAST FORWARD     F5 SAVE     F9 LOAD  •  REMAP IN SETTINGS"
	bottom.add_theme_font_size_override("font_size", 12)
	bottom.add_theme_color_override("font_color", Color(0.65, 0.77, 0.9))
	hud_root.add_child(bottom)
	hud_root.resized.connect(_layout_flight_hud)
	_layout_flight_hud()

func _layout_flight_hud() -> void:
	if not is_instance_valid(hud_root) or not is_instance_valid(flight_hud_top) or not is_instance_valid(flight_hud_right_scroll) or not is_instance_valid(flight_hud_bottom) or not is_instance_valid(flight_hud_right):
		return
	var viewport_size := hud_root.size
	var compact := viewport_size.x < 900.0 or viewport_size.y < 600.0
	if compact:
		flight_hud_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
		flight_hud_top.offset_left = 12
		flight_hud_top.offset_right = -12
		flight_hud_top.offset_top = 12
		flight_hud_top.offset_bottom = 104
		flight_hud_top.custom_minimum_size.x = 0
		flight_hud_right_scroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		flight_hud_right_scroll.offset_left = 12
		flight_hud_right_scroll.offset_right = -12
		flight_hud_right_scroll.offset_top = -maxf(180.0, viewport_size.y * 0.48)
		flight_hud_right_scroll.offset_bottom = -12
		flight_hud_right.custom_minimum_size.x = 0
		flight_hud_bottom.visible = false
	else:
		flight_hud_top.set_anchors_preset(Control.PRESET_TOP_LEFT)
		flight_hud_top.position = Vector2(18, 18)
		flight_hud_top.custom_minimum_size = Vector2(330, 0)
		flight_hud_right_scroll.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		flight_hud_right_scroll.anchor_bottom = 1.0
		flight_hud_right_scroll.offset_left = -270
		flight_hud_right_scroll.offset_right = -18
		flight_hud_right_scroll.offset_top = 18
		flight_hud_right_scroll.offset_bottom = -78
		flight_hud_right.custom_minimum_size.x = 235
		flight_hud_bottom.visible = true
		flight_hud_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		flight_hud_bottom.offset_left = 350
		flight_hud_bottom.offset_right = -20
		flight_hud_bottom.offset_top = -58
		flight_hud_bottom.offset_bottom = -8

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
		var history_kind := "MANUAL BACKUP" if history_path.get_file().begins_with("manual_") else "AUTOSAVE"
		var history_label := "LOAD  •  %s  •  %s" % [history_kind, Time.get_datetime_string_from_unix_time(history_time, true)]
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
	var panel_scroll := ScrollContainer.new()
	panel_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_scroll.offset_left = 12
	panel_scroll.offset_right = -12
	panel_scroll.offset_top = 12
	panel_scroll.offset_bottom = -12
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window.add_child(panel_scroll)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_scroll.add_child(root)
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
		var planet_name := str(planet.get("name", "Unknown"))
		if SpaceDiscovery.is_spotted(discovery_state, planet_name):
			planet_dropdown.add_item(planet_name, planet_index)
			planet_dropdown.set_item_disabled(planet_dropdown.item_count - 1, not SpaceDiscovery.is_visited(discovery_state, planet_name))
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
			if SpaceDiscovery.is_spotted(discovery_state, "Moon"):
				moon_dropdown.add_item("Moon", -1)
				moon_dropdown.set_item_disabled(moon_dropdown.item_count - 1, not SpaceDiscovery.is_visited(discovery_state, "Moon"))
		else:
			var parent_name := FlightComputer.target_body_name(parent_target_index)
			for satellite in FlightComputer.satellite_targets_for_host(parent_name):
				var satellite_name := str(satellite.get("name", ""))
				if SpaceDiscovery.is_spotted(discovery_state, satellite_name):
					moon_dropdown.add_item(str(satellite.get("display_name", satellite.get("name", "Unknown"))), int(satellite.get("id", -1)))
					moon_dropdown.set_item_disabled(moon_dropdown.item_count - 1, not SpaceDiscovery.is_visited(discovery_state, satellite_name))
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
	window.size = Vector2i(500, 580)
	window.min_size = Vector2i(420, 480)
	window.transient = true
	window.exclusive = true
	add_child(window)
	window.close_requested.connect(window.queue_free)
	var panel_scroll := ScrollContainer.new()
	panel_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_scroll.offset_left = 12
	panel_scroll.offset_right = -12
	panel_scroll.offset_top = 12
	panel_scroll.offset_bottom = -12
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	window.add_child(panel_scroll)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_scroll.add_child(layout)
	var intro := Label.new()
	intro.text = "Use rendezvous assist to match the other spacecraft's velocity and close the gap. Docking still requires a slow, close approach."
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
	var assist_button := Button.new()
	assist_button.text = "START RENDEZVOUS ASSIST"
	assist_button.custom_minimum_size.y = 44
	layout.add_child(assist_button)
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
			assist_button.disabled = true
			undock_button.disabled = true
			transfer_button.disabled = true
			fuel_direction.disabled = true
			return
		if target_selector.item_count == 0:
			status.text = "Launch another vehicle before attempting to dock."
			dock_button.disabled = true
			assist_button.disabled = true
			undock_button.disabled = true
			transfer_button.disabled = true
			fuel_direction.disabled = true
			return
		var target_name := str(target_selector.get_item_metadata(target_selector.selected))
		var target := _find_vehicle_by_name(target_name)
		if target == null:
			status.text = "The selected spacecraft is no longer available."
			dock_button.disabled = true
			assist_button.disabled = true
			undock_button.disabled = true
			transfer_button.disabled = true
			return
		var separation: float = sim.rocket_position.distance_to(target.rocket_position)
		var relative_speed: float = (sim.velocity - target.velocity).length()
		var docked := _are_docked(parent_name, target_name)
		var assist_active := str(docking_assists.get(parent_name, "")) == target_name
		var free_flying: bool = not _is_vehicle_docked(parent_name) and not _is_vehicle_docked(target_name) and not sim.landed and not sim.crashed and not target.landed and not target.crashed
		var available_to_dock: bool = not docked and free_flying and separation <= DOCKING_CAPTURE_DISTANCE and relative_speed <= DOCKING_CAPTURE_SPEED
		var available_to_assist: bool = not docked and free_flying and separation <= DOCKING_ASSIST_MAX_RANGE
		if docked:
			status.text = "DOCKED  •  %s\nCombined mass is included in the parent spacecraft's flight dynamics." % target_name
		elif available_to_dock:
			status.text = "DOCKING CONDITIONS MET\nRange: %.1f m  •  Relative speed: %.2f m/s" % [separation, relative_speed]
		elif assist_active:
			status.text = "RENDEZVOUS ASSIST ACTIVE\nRange: %.1f m  •  Relative speed: %.2f m/s\nGuidance is matching velocity and closing at up to %.1f m/s." % [separation, relative_speed, DOCKING_ASSIST_MAX_CLOSING_SPEED]
		else:
			status.text = "Range: %.1f m / %.0f m\nRelative speed: %.2f / %.2f m/s\nRendezvous assist works within %.0f km." % [separation, DOCKING_CAPTURE_DISTANCE, relative_speed, DOCKING_CAPTURE_SPEED, DOCKING_ASSIST_MAX_RANGE / 1000.0]
		dock_button.disabled = not available_to_dock
		assist_button.disabled = not available_to_assist and not assist_active
		assist_button.text = "STOP RENDEZVOUS ASSIST" if assist_active else "START RENDEZVOUS ASSIST"
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
		docking_assists.erase(parent_name)
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
	assist_button.pressed.connect(func():
		if sim.vehicle_name != parent_name or target_selector.item_count == 0:
			refresh_panel.call()
			return
		var target_name := str(target_selector.get_item_metadata(target_selector.selected))
		if str(docking_assists.get(parent_name, "")) == target_name:
			docking_assists.erase(parent_name)
		else:
			docking_assists[parent_name] = target_name
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
		if (filename.begins_with("auto_") or filename.begins_with("manual_")) and filename.ends_with(".json"):
			paths.append(directory.path_join(filename))
	paths.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b)
	)
	return paths

func _prune_autosave_history(slot: int, keep_count: int = 10) -> void:
	var paths: Array[String] = _autosave_history_paths(slot)
	var autosaves: Array[String] = []
	var manual_backups: Array[String] = []
	for path in paths:
		if path.get_file().begins_with("manual_"):
			manual_backups.append(path)
		else:
			autosaves.append(path)
	for i in range(keep_count, autosaves.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(autosaves[i]))
	for i in range(keep_count, manual_backups.size()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(manual_backups[i]))

func _write_save_file(path: String, data: Dictionary) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return false
	if FileAccess.file_exists(path):
		var previous_path := absolute_path + ".previous"
		if FileAccess.file_exists(previous_path):
			DirAccess.remove_absolute(previous_path)
		var backup_error := DirAccess.rename_absolute(absolute_path, previous_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
		var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
		if replace_error != OK:
			DirAccess.rename_absolute(previous_path, absolute_path)
			DirAccess.remove_absolute(temporary_path)
			return false
		DirAccess.remove_absolute(previous_path)
	else:
		var install_error := DirAccess.rename_absolute(temporary_path, absolute_path)
		if install_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
	return true

func _save_game(automatic: bool) -> void:
	if not sim or fleet_sims.is_empty():
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
	data["docking_assists"] = docking_assists.duplicate(true)
	data["realism"] = realism
	data["world_scale"] = world_scale
	data["career_enabled"] = career_enabled
	data["slot"] = save_slot
	data["save_version"] = 2
	data["saved_at_unix"] = int(Time.get_unix_time_from_system())
	data["save_name"] = str(sim.vehicle_name)
	data["discovery_state"] = discovery_state.duplicate(true)
	data["funds"] = funds
	data["total_revenue_earned"] = total_revenue_earned
	data["total_operating_costs"] = total_operating_costs
	data["mission_state"] = mission_state.duplicate(true)
	data["orbited_body_names"] = orbited_body_names.duplicate(true)

	var history_directory := "%s/history/slot_%02d" % [SAVE_DIR, save_slot]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(history_directory))
	var path := "%s/slot_%02d.json" % [SAVE_DIR, save_slot]
	if FileAccess.file_exists(path):
		var history_prefix := "auto" if automatic else "manual"
		var history_name := "%s_%d_%d.json" % [history_prefix, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
		var history_path := history_directory.path_join(history_name)
		var current_file := FileAccess.open(path, FileAccess.READ)
		if current_file == null:
			if status_label:
				status_label.text = "EXISTING SAVE COULD NOT BE BACKED UP"
			return
		var current_data := current_file.get_as_text()
		current_file.close()
		var history_file := FileAccess.open(history_path, FileAccess.WRITE)
		if history_file == null:
			if status_label:
				status_label.text = "SAVE HISTORY COULD NOT BE WRITTEN"
			return
		history_file.store_string(current_data)
		history_file.flush()
		var history_error := history_file.get_error()
		history_file.close()
		if history_error != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(history_path))
			if status_label:
				status_label.text = "SAVE HISTORY COULD NOT BE WRITTEN"
			return
		_prune_autosave_history(save_slot)
	if not _write_save_file(path, data):
		if status_label:
			status_label.text = "SAVE COULD NOT BE WRITTEN  •  ORIGINAL PRESERVED"
		return
	if status_label:
		status_label.text = ("AUTOSAVED" if automatic else "SAVED") + "  •  SLOT %02d" % save_slot

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
	funds = float(parsed.get("funds", STARTING_FUNDS))
	total_revenue_earned = maxf(0.0, float(parsed.get("total_revenue_earned", 0.0)))
	total_operating_costs = maxf(0.0, float(parsed.get("total_operating_costs", 0.0)))
	economy_last_sim_time = fleet_sims[active_vehicle_index].sim_time if not fleet_sims.is_empty() else 0.0
	_refresh_economy_display()
	discovery_state = SpaceDiscovery.sanitize_state(parsed.get("discovery_state", SpaceDiscovery.new_campaign_state()))
	mission_state = MissionSystem.sanitize_state(parsed.get("mission_state", MissionSystem.new_state()))
	var saved_orbited_bodies: Variant = parsed.get("orbited_body_names", {})
	orbited_body_names = saved_orbited_bodies.duplicate(true) if saved_orbited_bodies is Dictionary else {}
	for vehicle in fleet_sims:
		vehicle.discovered_body_names = SpaceDiscovery.spotted_names(discovery_state)
		vehicle.visited_body_names = SpaceDiscovery.visited_names(discovery_state)
	docking_links.clear()
	var saved_docking_links: Variant = parsed.get("docking_links", [])
	if saved_docking_links is Array:
		var linked_children: Dictionary = {}
		var linked_parents: Dictionary = {}
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
			if linked_children.has(child_name) or linked_children.has(parent_name) or linked_parents.has(child_name):
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
			linked_children[child_name] = true
			linked_parents[parent_name] = true
	_update_docked_masses()
	_sync_docked_vehicles()
	docking_assists.clear()
	var saved_assists: Variant = parsed.get("docking_assists", {})
	if saved_assists is Dictionary:
		for vehicle_name_variant in saved_assists:
			var vehicle_name := str(vehicle_name_variant)
			var target_name := str(saved_assists[vehicle_name_variant])
			var vehicle := _find_vehicle_by_name(vehicle_name)
			var target := _find_vehicle_by_name(target_name)
			if vehicle != null and target != null and not vehicle.landed and not vehicle.crashed and not target.landed and not target.crashed and not _is_vehicle_docked(vehicle_name) and not _is_vehicle_docked(target_name):
				docking_assists[vehicle_name] = target_name
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
	const RocketVisual = preload("res://scripts/rocket_visual.gd")
	var design: Dictionary = {}

	func _draw() -> void:
		if design.get("stages", []).is_empty():
			return
		var scale := minf(1.0, maxf(0.55, (size.y - 52.0) / 190.0))
		RocketVisual.draw_vehicle(self, design, Vector2(size.x * 0.5, size.y * 0.48), 0.0, scale, 0, 0.0, false, true)
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
