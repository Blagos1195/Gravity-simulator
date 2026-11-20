# GRAVITY

A procedural 2D spaceflight simulator built with Godot 4.

## Current prototype

- Procedural starfield and vector-drawn spacecraft
- Earth-centred Newtonian gravity with lunar perturbations
- Centralised planetary data for all eight planets
- Time-dependent circular Moon orbit and lunar gravity
- Exponential Earth atmosphere model
- Surface launch pad with toggleable engine controls
- Two-stage launch vehicle with automatic and manual staging
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
| Mouse wheel | Zoom |
| O | Toggle orbit display |
| G | Toggle grid |
| V | Toggle velocity vector |
| F5 | Save current slot |
| F9 | Load current slot |
| Escape | Pause / resume |

Saves are stored in the user's Godot application data directory under `saves/`.

## Important

This remains an early Earth-centred prototype. The two-stage vehicle, adaptive substepping, gimbal, lift, heating and gravity-turn guidance are simplified gameplay models, not validated launch-vehicle engineering. Planetary gravity uses circular coplanar orbits and differential perturbations rather than accurate ephemerides or a full n-body solar-system integration. Atmospheric heating is an estimate and does not yet damage or destroy the vehicle. The rocket editor, vehicle structural limits, detailed aerodynamic coefficients, career progression, missions, docking, replay tooling and multiplayer remain planned follow-on systems.
