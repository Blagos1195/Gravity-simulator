# GRAVITY release preparation

This file is the release-page and packaging checklist. It is not confirmation that a public build has been tested or released.

## Store page draft

### Short description

Build multi-stage rockets, launch into orbit and plan journeys across a procedural 2D solar system.

### Description

GRAVITY is a 2D spaceflight simulator focused on designing launch vehicles and flying them through a simplified, physically informed solar system.

Build and configure multi-stage rockets in the vehicle workshop, then launch, stage, circularise and plan transfers to planets and moons. Choose between four flight-model presets, adjust the displayed scale of the solar system, and use the onboard flight computer and autopilot to plan orbital manoeuvres.

The simulation includes atmospheric flight, engine performance changes with pressure, orbital telemetry, planetary encounters, powered landing guidance, spacecraft fleets and optional small-body collision encounters. Eight save slots support manual saves and automatic backups.

GRAVITY is an actively developed early prototype. Some systems are simplified, and features such as detailed terrain, parachutes, full career progression, docking systems, replay tools and multiplayer are not complete.

### Features

- Design and configure multi-stage launch vehicles
- Fly with Arcade, Standard, Realistic or Hardcore presets
- Launch, stage, circularise and perform orbital manoeuvres
- Plan transfers to modeled planets and moons
- Use the flight computer and destination autopilot
- Explore compressed, balanced or realistic-distance solar-system views
- Manage multiple vehicles and save campaigns across eight slots
- Extend the built-in planet and rocket catalog with JSON mods

## Before publishing

- [ ] Complete a clean Windows export using the matching Godot export templates.
- [ ] Test the exported build on a Windows machine without the Godot editor installed.
- [ ] Test first launch, new campaign, rocket workshop, launch, save, close and reload.
- [ ] Test the game at the minimum supported resolution and on a high-DPI display.
- [ ] Confirm save files are created in the per-user Godot application data directory, not beside the executable.
- [ ] Confirm the game starts without editor/debug tooling or a console window.
- [ ] Capture genuine screenshots from the tested release build.
- [ ] Check all screenshots and store copy against the actual released build.
- [ ] Include the MIT license and Godot Engine license notice with the release.
- [ ] Create a versioned ZIP containing the complete exported Windows folder, including any required PCK or data files.
- [ ] Upload the ZIP to the itch.io project page and test the download on a separate machine/account.

## Suggested screenshots

Capture these from the actual release build after the Windows export has passed testing:

1. Main menu
2. Rocket workshop showing the parts catalogue, assembly and staging/inspector
3. Launch with the vehicle and atmospheric telemetry visible
4. Orbital view with the flight computer open
5. Solar-system overview showing multiple planets

Do not use editor screenshots or mockups as screenshots of the game.

## Distribution

The recommended first public home is itch.io. Publish a free downloadable Windows project and upload the complete exported folder as a ZIP. Keep the project page private while checking its layout and downloads, then make it public when the build is ready.

A GitHub Release can provide a secondary versioned download and changelog. Do not use the source-code ZIP as the player download.

## Technical notes

- Engine: Godot 4.7 or newer, standard build, GDScript
- Current project version: 0.1.0
- Current repository licence: MIT
- Initial target: Windows desktop
- Save data uses Godot's `user://` location, separate from the install directory.
- The current project has not yet been packaged or verified as a standalone Windows release.

## Known prototype limitations

The README contains the detailed simulation assumptions and limitations. In particular, planetary ephemerides and atmospheric models are approximations; this is a planar 2D simulation; detailed terrain, parachutes, structural vehicle simulation, full career progression, missions, docking, replay tooling and multiplayer are not complete.
