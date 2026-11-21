# GRAVITY

A procedural 2D spaceflight simulator built with Godot 4.

## Current prototype

- Procedural starfield and vector-drawn spacecraft
- Earth-relative Newtonian flight dynamics evaluated in a heliocentric inertial gravity frame, including differential solar, lunar and planetary perturbations
- Time-dependent Keplerian planetary ephemerides for all eight planets, with position-consistent velocity estimates
- Double-precision rocket and ephemeris coordinates for local gravity, atmosphere, encounter and trajectory calculations
- Time-dependent circular Moon orbit and lunar gravity
- Layered standard-atmosphere pressure and temperature model through 120 km
- Vehicle assembly screen with 2–8 configurable stages and payload mass
- Adjustable stage dry mass, propellant capacity, engine count, sea-level/vacuum thrust and per-engine fuel flow
- Live vehicle preview, initial mass, ideal delta-v and launch thrust-to-weight estimates
- Rocket design validation for specific impulse, stage mass fraction, minimum upper-stage ignition TWR, burnout acceleration, total mass and total delta-v
- Local JSON save/load rejects invalid vehicle designs
- Custom vehicle parameters applied to flight mass, engine thrust, propellant use, staging and telemetry
- Surface launch pad with toggleable engine controls
- Multi-stage launch vehicle with automatic and manual staging
- Variable-mass thrust integrated with the rocket equation for each stage
- Optional infinite, massless propellant mode for experimentation
- Engine thrust varies with ambient atmospheric pressure rather than a linear altitude approximation
- Separate sea-level and vacuum engine performance
- Engine gimbal controls
- Adaptive substepping based on orbital timescale, atmospheric travel distance, drag, thrust and exact propellant depletion
- Sutton–Graves stagnation-point heating estimate and radiative heat-shield temperature response
- Earth rotation inherited at launch and rotating-atmosphere-relative aerodynamics
- Arcade, Standard, Realistic and Hardcore presets with progressively more atmospheric forces, lift and heating
- Live Mach number, dynamic-pressure and peak Max-Q telemetry
- Atmospheric heat-flux and radiative heat-shield temperature telemetry
- Differential gravity from the Moon, Sun and other planets
- Optional gravity-turn guidance assist
- Orbital flight computer with osculating orbit elements, circularisation burns, lunar transfers and heliocentric Hohmann estimates
- Destination planner for the Moon and all seven other planets, including ideal departure phase, transfer-window timing, hyperbolic departure orientation and capture delta-v estimates
- Orbit autopilot with ascent, coast-to-apoapsis and prograde/retrograde circularisation
- Destination autopilot selects any modeled planet or the Moon and a target orbit altitude; it can depart from the current body, search transfers, capture into an orbit reaching the requested altitude, then circularize there
- Destination-relative range and velocity telemetry, plus selected-planet rendering during interplanetary flight
- Planetary Hill-sphere encounter radii and target-relative ephemeris/velocity calculations
- Approximate Venus, Mars and gas-giant atmospheric density, temperature, rotation, drag, heating and engine-pressure effects
- Body-relative orbital telemetry and orbit drawing around the local planet
- Surface contact, low-speed landing and high-speed crash states for the Moon and rocky planets; gas-giant 1-bar reference levels are treated as atmospheric loss boundaries
- Powered landing guidance from a stable orbit around the Moon or a solid planet, with body-relative velocity control and variable throttle
- Deep-space adaptive integration with up to 1,000,000× time warp while retaining fine steps near Earth
- Automated orbital stability regression tests covering three LEO revolutions and one full MEO and GEO revolution
- Manual engine controls disengage autopilot; saved flight state preserves the selected target, departure burn vector and guidance phase
- Remaining ideal vehicle delta-v and thrust-to-weight telemetry
- Orbital trajectory, periapsis, apoapsis and thrust-to-weight readouts
- Adjustable time warp
- Compressed, balanced and realistic-distance display scales
- Solar-system overview showing catalog planets, animated planetary moons, rings, the main asteroid belt and Kuiper belt
- Optional small-body encounter mode: deterministic belt test particles follow individual Sun-centered paths and can collide with the spacecraft; mutual asteroid gravity is intentionally omitted
- Predicted rocket trajectory overlay using current flight state and engine settings
- Rocket and launch-pad graphics scale with camera zoom
- Extended close-up and far-out zoom range, including independent solar-system map zoom
- Resizable window with a minimum supported size and expanded viewport scaling
- Save-aware main menu with Continue, New Game, Game Load and global Settings
- New-game setup for physics preset, universe scale and optional career mode
- Global fullscreen, autosave, infinite-weightless-propellant and small-body collision preferences
- Persistent keyboard remapping for engine toggle/cutoff, rotation, pause, staging and guidance
- Distinct Arcade, Standard, Realistic and Hardcore aerodynamic/heating presets
- Peak dynamic-pressure (Max-Q) telemetry saved with flight state
- Optional career setting placeholder
- Eight selectable JSON save slots, manual save and 60-second automatic save

## Requirements

- Godot Engine 4.7 or newer
- Windows, Linux or macOS for development

## Run

1. Install Godot 4.
2. Open `project.godot` using Godot's Project Manager.
3. Press F6 or F5 to run the project.

## Development checks

Run the calculation tests from the project directory:

```powershell
godot --headless --path . --script res://tests/rocket_design_test.gd
godot --headless --path . --script res://tests/flight_computer_test.gd
godot --headless --path . --script res://tests/orbital_stability_test.gd
```

## Controls

| Input | Action |
|---|---|
| W | Toggle engine on/off; disengages autopilot for manual control |
| S | Cut engine; disengages autopilot for manual control |
| X | Separate current stage |
| Q / E | Adjust engine gimbal |
| A / D | Rotate left / right |
| H | Toggle guidance / disengage autopilot |

The engine, cutoff, rotation, pause, staging and guidance keys can be remapped in global Settings.
| Space | Pause / resume |
| + / - | Increase / decrease time warp |
| Mouse wheel | Zoom flight view or solar-system map |
| Home | Reset zoom |
| O | Toggle current rocket orbit display |
| M | Toggle full solar-system overview |
| P | Toggle predicted rocket trajectory |
| G | Toggle grid |
| V | Toggle velocity vector |
| F5 | Save current slot |
| F9 | Load current slot |
| Escape | Pause / resume |

Flight saves are stored in the user's Godot application data directory under `saves/`. The active vehicle design can be saved separately as `rocket_design.json` in the same user data area.

## Content catalog and mods

The editable built-in catalog is [`data/content_catalog.json`](data/content_catalog.json). To use a mod without changing the project files, copy it to `mods/content_catalog.json` inside the game's Godot user data directory (`user://`). The full directory can be found with `OS.get_user_data_dir()`. The game loads that override at startup; if it is missing or invalid, an error is logged and the built-in catalog is used.

The catalog is JSON with `schema_version: 1` and four main sections:

- `system`: gravitational constant, astronomical unit, Sun data and color, ephemeris epoch, Earth's atmosphere, and `small_body_belts`. Belt bounds use AU; particle count, seed, display size, opacity, and RGB color control their overview-map appearance. Optional `collision_radius_min_m` and `collision_radius_max_m` set the test-particle collision sizes in metres. Atmosphere profile arrays correspond by index; altitudes are metres, temperatures kelvin, lapse rates kelvin per metre, and pressures pascals.
- `moon`: mass and radius in SI units, orbital and rotation parameters, sphere-of-influence radius, solidity, and display color. The orbit elements ending in `_rad` are radians; periods are seconds.
- `planets`: each planet's mass (kg), radius (m), Keplerian elements and element rates, orbital period (days), rotation rate (rad/s), solidity, RGB display color, and atmosphere model. `a` is in astronomical units; angles are degrees and element rates are per Julian century. Each atmosphere provides its model (`none`, `standard`, or `exponential`), physical and visual height (m), surface density (kg/m³), scale height (m), temperature (K), gas constant (J/(kg·K)), heat-capacity ratio, and RGB color. `surface_color_rgb` can override a body's color in the close-up view; optional `rings` define inner/outer radius ratios, color, and opacity. `satellites` contains each moon's mass, radius, circular orbit radius and period, phase at the ephemeris epoch, optional `orbital_direction` (`-1` for retrograde, otherwise prograde), rotation rate, solidity, color, and optional atmosphere data.
- `rocket`: a default design and named presets reference reusable `stage_parts` by `id`. A stage part defines dry mass and fuel capacity (kg), sea-level and vacuum thrust (N per engine), fuel flow (kg/s per engine), and engine count.

Keep required fields and array lengths intact when editing. Preset/default stage references must match defined part IDs, and each design must contain 2–8 stages. The loader validates these relationships before accepting a mod.

## Important

The vehicle assembly system supports 2–8 configurable stages. It checks engine specific impulse (220–380 s sea-level and 250–465 s vacuum), stage mass fractions, ignition and burnout thrust-to-weight, total mass (maximum 5,000 tonnes) and total ideal delta-v (8.5–16.5 km/s). Invalid designs cannot be launched or saved. Stage-level values remain an abstraction rather than a detailed component-by-component engineering model. Infinite, weightless propellant is a global cheat setting; it removes propellant from vehicle mass and does not deplete fuel. Staging remains manual in this mode.

This remains an early Earth-centred prototype. The multi-stage vehicle, adaptive substepping, gimbal, lift, heating, gravity-turn and powered-landing guidance are simplified gameplay models, not validated launch-vehicle engineering. Planetary positions use time-dependent Keplerian orbital elements and approximate two-dimensional ephemerides rather than a live n-body solar-system integration. Major planetary moons are included as simplified circular, coplanar orbits and affect gravity and collision checks; rings remain visual-only. Belt particles are deterministic massless test particles with individual Sun-centered orbital paths; the optional small-body collision setting checks their swept paths against the spacecraft, but particles do not mutually interact or perturb the spacecraft gravitationally. Rocket gravity is evaluated in a heliocentric inertial frame and converted to Earth-relative acceleration, including differential solar, lunar, planetary and modeled satellite gravity. This is more consistent than a stationary-Earth approximation, but the planetary ephemerides remain approximate and do not model full three-dimensional motion. Godot's standard `Vector2` coordinates are single precision, so the flight state, ephemeris and interplanetary transfer-search integration now retain double-precision coordinate components internally, including collision checks and target-relative closest-approach calculations. Gravity, local-body distances, atmosphere sampling, and predicted trajectories use these components before conversion to display vectors. Rendering and legacy vector-based interfaces remain approximate at interplanetary scales, and planetary surface operations still require further validation. Interplanetary transfer estimates assume simplified planar trajectories; the autopilot calculates a transfer, captures into an ellipse with the selected orbit altitude as periapsis, and circularizes at that altitude. Powered landing guidance is available from a stable orbit around the Moon or a solid planet, but terrain, parachutes, landing legs and detailed surface operations are not implemented. Gas-giant reference levels are atmospheric loss boundaries, not solid surfaces. Lunar departure timing is a two-body phase estimate. Planetary atmospheric profiles and heating are approximations, and heating does not yet damage or destroy the vehicle. Detailed tank and engine structural modelling, higher-fidelity aerodynamic coefficients, career progression, missions, docking, replay tooling and multiplayer remain planned follow-on systems.
