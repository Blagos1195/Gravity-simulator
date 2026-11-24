extends Node2D

const RocketDesign = preload("res://scripts/rocket_design.gd")
const RocketVisual = preload("res://scripts/rocket_visual.gd")
const PlanetarySystem = preload("res://scripts/planetary_system.gd")

const IMAGE_SIZE := Vector2(1920.0, 1080.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, IMAGE_SIZE), Color(0.008, 0.016, 0.035))
	for i in range(180):
		var x := fposmod(float(i) * 137.508 + 31.0, IMAGE_SIZE.x)
		var y := fposmod(float(i) * 83.17 + 17.0, IMAGE_SIZE.y)
		var radius := 0.7 + fposmod(float(i) * 0.37, 1.4)
		var alpha := 0.22 + fposmod(float(i) * 0.19, 0.62)
		draw_circle(Vector2(x, y), radius, Color(0.68, 0.82, 1.0, alpha))
	var earth_center := Vector2(1510.0, 1110.0)
	var earth_radius := 710.0
	var earth_visual := PlanetarySystem.planet_visual_data("Earth")
	var atmosphere_color: Color = earth_visual.get("atmosphere_color", Color(0.22, 0.55, 1.0))
	draw_circle(earth_center, earth_radius + 32.0, Color(atmosphere_color.r, atmosphere_color.g, atmosphere_color.b, 0.12))
	draw_circle(earth_center, earth_radius + 15.0, Color(atmosphere_color.r, atmosphere_color.g, atmosphere_color.b, 0.22))
	draw_circle(earth_center, earth_radius, earth_visual.get("surface_color", Color(0.13, 0.32, 0.48)))
	draw_circle(earth_center + Vector2(-105.0, -75.0), earth_radius * 0.83, Color(0.19, 0.43, 0.56, 0.32))
	draw_arc(earth_center, earth_radius, PI, TAU, 160, Color(0.58, 0.78, 1.0, 0.42), 3.0, true)
	draw_arc(earth_center, earth_radius + 18.0, PI, TAU, 160, Color(0.35, 0.68, 1.0, 0.68), 5.0, true)
	var design := RocketDesign.create_default()
	RocketVisual.draw_vehicle(self, design, Vector2(1165.0, 480.0), deg_to_rad(9.0), 5.8, 0, 0.0, false)
	var title_font := ThemeDB.fallback_font
	draw_string(title_font, Vector2(150.0, 495.0), "GRAVITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 104, Color(0.91, 0.96, 1.0))
	draw_string(title_font, Vector2(158.0, 548.0), "A 2D SPACEFLIGHT SIMULATOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.48, 0.68, 0.84))
	draw_line(Vector2(158.0, 575.0), Vector2(520.0, 575.0), Color(0.26, 0.58, 0.86, 0.8), 2.0)
