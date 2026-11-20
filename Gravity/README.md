# GRAVITY

A procedural 2D spaceflight simulator built with Godot 4.

## Current prototype

- Procedural starfield and vector-drawn spacecraft
- Earth-centred Newtonian gravity with lunar perturbations
- Centralised planetary data for all eight planets
- Time-dependent circular Moon orbit and lunar gravity
- Exponential Earth atmosphere model
- Surface launch pad with toggleable engine controls
- Variable-mass rocket thrust and propellant consumption
- Engine thrust interpolates from sea-level to vacuum performance
- Earth rotation inherited at launch and rotating-atmosphere-relative drag
- Atmospheric drag in Realistic and Hardcore modes
- Remaining ideal delta-v and thrust-to-weight telemetry
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
| A / Left | Rotate left |
| D / Right | Rotate right |
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

This is the first playable foundation, not the finished simulator. The current flight model is still an Earth-centred prototype. It now accounts for variable rocket mass, altitude-dependent engine thrust, Earth's rotational launch velocity and atmospheric co-rotation, but it does not yet model multiple rocket stages, engine gimbal, lift, heating, structural limits or a full aerodynamic coefficient model. The Moon follows a simplified circular orbit, and the planetary catalogue is data groundwork rather than a complete heliocentric simulation. Accurate planetary ephemerides, an adaptive high-accuracy integrator, the vehicle assembly system, career progression, missions, docking, re-entry heating, replay tooling and multiplayer remain planned follow-on systems.
