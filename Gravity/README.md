# GRAVITY

A procedural 2D spaceflight simulator built with Godot 4.

## Current prototype

- Procedural starfield and vector-drawn spacecraft
- Earth-centred Newtonian gravity with lunar perturbations
- Centralised planetary data for all eight planets
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
- Destination autopilot with parking-orbit insertion, transfer-window waiting, hyperbolic departure alignment, calculated injection burn, target-relative encounter detection and a one-burn circular capture at closest approach
- Destination-relative range and velocity telemetry, plus selected-planet rendering during interplanetary flight
- Planetary Hill-sphere encounter radii and target-relative ephemeris/velocity calculations
- Approximate Venus, Mars and gas-giant atmospheric density, temperature, rotation, drag, heating and engine-pressure effects
- Body-relative orbital telemetry and orbit drawing around the local planet
- Surface contact, low-speed landing and high-speed crash states for the Moon and rocky planets; gas-giant 1-bar reference levels are treated as atmospheric loss boundaries
- Deep-space adaptive integration with up to 1,000,000× time warp while retaining fine steps near Earth
- Manual engine controls disengage autopilot; saved flight state preserves the selected target, departure burn vector and guidance phase
- Remaining ideal vehicle delta-v and thrust-to-weight telemetry
- Orbital trajectory, periapsis, apoapsis and thrust-to-weight readouts
- Adjustable time warp
- Compressed, balanced and realistic-distance display scales
- Solar-system overview showing the Sun and orbital paths of all eight planets
- Predicted rocket trajectory overlay using current flight state and engine settings
- Rocket and launch-pad graphics scale with camera zoom
- Extended close-up and far-out zoom range, including independent solar-system map zoom
- Resizable window with a minimum supported size and expanded viewport scaling
- Save-aware main menu with Continue, New Game, Game Load and global Settings
- New-game setup for physics preset, universe scale and optional career mode
- Global fullscreen and autosave preferences
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

## Important

The vehicle assembly system supports 2–8 configurable stages. It checks engine specific impulse (220–380 s sea-level and 250–465 s vacuum), stage mass fractions, ignition and burnout thrust-to-weight, total mass (maximum 5,000 tonnes) and total ideal delta-v (8.5–16.5 km/s). Invalid designs cannot be launched or saved. Stage-level values remain an abstraction rather than a detailed component-by-component engineering model.

This remains an early Earth-centred prototype. The multi-stage vehicle, adaptive substepping, gimbal, lift, heating and gravity-turn guidance are simplified gameplay models, not validated launch-vehicle engineering. Planetary gravity uses circular coplanar orbits and differential perturbations rather than accurate ephemerides or a full n-body solar-system integration. Interplanetary transfer estimates assume circular coplanar Hohmann transfers; the autopilot currently performs parking-orbit insertion, departure-window alignment and injection, then coasts; arrival targeting, capture and landing are not yet implemented. Lunar departure timing is a two-body phase estimate. Atmospheric heating is an estimate and does not yet damage or destroy the vehicle. Detailed tank and engine structural modelling, detailed aerodynamic coefficients, career progression, missions, docking, replay tooling and multiplayer remain planned follow-on systems.
