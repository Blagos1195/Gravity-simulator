# GRAVITY

A procedural 2D spaceflight simulator built with Godot 4.

## Current prototype

- Procedural starfield and vector-drawn spacecraft
- Earth-centred Newtonian gravity with lunar perturbations
- Centralised planetary data for all eight planets
- Time-dependent circular Moon orbit and lunar gravity
- Exponential Earth atmosphere model
- Vehicle assembly screen with 2–8 configurable stages and payload mass
- Adjustable stage dry mass, propellant capacity, engine count, sea-level/vacuum thrust and per-engine fuel flow
- Live vehicle preview, initial mass, ideal delta-v and launch thrust-to-weight estimates
- Rocket design validation and local JSON save/load
- Custom vehicle parameters applied to flight mass, engine thrust, propellant use, staging and telemetry
- Surface launch pad with toggleable engine controls
- Multi-stage launch vehicle with automatic and manual staging
- Variable-mass thrust and propellant consumption for each stage
- Separate sea-level and vacuum engine performance
- Engine gimbal controls
- Adaptive substepping based on local flight conditions
- Earth rotation inherited at launch and rotating-atmosphere-relative aerodynamics
- Atmospheric drag and approximate lift in Realistic and Hardcore modes
- Simplified atmospheric heating and heat-shield temperature telemetry
- Differential gravity from the Moon, Sun and other planets
- Optional gravity-turn guidance assist
- Remaining ideal vehicle delta-v and thrust-to-weight telemetry
- Orbital trajectory, periapsis, apoapsis and thrust-to-weight readouts
- Adjustable time warp
- Compressed, balanced and realistic-distance display scales
- Solar-system overview showing the Sun and orbital paths of all eight planets
- Predicted rocket trajectory overlay using current flight state and engine settings
- Rocket and launch-pad graphics scale with camera zoom
- Extended close-up and far-out zoom range, including independent solar-system map zoom
- Resizable window with a minimum supported size and expanded viewport scaling
- Physics presets
- Optional career setting placeholder
- Eight selectable JSON save slots, manual save and 60-second automatic save

## Requirements

- Godot Engine 4.3 or newer
- Windows, Linux or macOS for development

## Run

1. Install Godot 4.
2. Open `project.godot` using Godot's Project Manager.
3. Press F6 or F5 to run the project.

## Development checks

Run the rocket design calculation tests from the project directory:

```powershell
godot --headless --path . --script res://tests/rocket_design_test.gd
```

## Controls

| Input | Action |
|---|---|
| W / Up | Toggle engine on/off |
| S / Down | Cut engine |
| X | Separate current stage |
| Q / E | Adjust engine gimbal |
| A / Left | Rotate left |
| D / Right | Rotate right |
| H | Toggle gravity-turn guidance assist |
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

The vehicle assembly system supports 2–8 configurable stages. It edits stage-level performance values rather than placing individual physical parts, and the preview is illustrative.

This remains an early Earth-centred prototype. The two-stage vehicle, adaptive substepping, gimbal, lift, heating and gravity-turn guidance are simplified gameplay models, not validated launch-vehicle engineering. Planetary gravity uses circular coplanar orbits and differential perturbations rather than accurate ephemerides or a full n-body solar-system integration. Atmospheric heating is an estimate and does not yet damage or destroy the vehicle. The rocket editor, vehicle structural limits, detailed aerodynamic coefficients, career progression, missions, docking, replay tooling and multiplayer remain planned follow-on systems.
