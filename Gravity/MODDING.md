# Modding guide

The game reads its built-in data from `data/content_catalog.json`. User mods are loaded from:

```
<Godot user data directory>/mods/content_catalog.json
```

Find the user data directory in-game with `OS.get_user_data_dir()`. Create the `mods` folder and place your JSON file there. Restart the game after changing it.

## Small changes

A mod can contain only the sections it changes. Unspecified values continue to use the built-in catalog.

For example, this adds another payload choice, engine-count choice and tank size without copying the full catalog:

```json
{
  "schema_version": 1,
  "rocket": {
    "builder_options": {
      "payloads_add": [
        {
          "id": "mapping_probe",
          "label": "Mapping probe · 2.4 t",
          "mass": 2400
        }
      ],
      "engine_counts_add": [5],
      "tank_scales_add": [
        {
          "label": "Oversized tank",
          "scale": 1.5
        }
      ]
    }
  }
}
```

## Adding a rocket stage part and preset

Stage parts are reusable components. Presets are vehicle designs made from stage-part IDs. Stages can be renamed and duplicated from the stage list, preserving their complete custom configuration. In the workshop, each stage also has an edit panel for its dry mass, propellant capacity, per-engine thrust and flow, visual proportions, and body colour. Engine-count changes preserve total stage thrust and flow; tank-scale changes scale dry mass and propellant capacity proportionally. Stage parts may also define `visual_length_factor`, `visual_diameter_factor`, `visual_color_rgb` and `engine_layout` to control their appearance in both the workshop and flight view. Engine layouts are `linear` (the default), `cluster` or `radial`; the stage editor can change this per craft. The factors are relative visual multipliers; the RGB array uses values from 0 to 1. Omit them to use the built-in defaults.

```json
{
  "schema_version": 1,
  "rocket": {
    "stage_parts_add": [
      {
        "id": "example_kick_stage",
        "label": "Example · Kick Stage",
        "name": "KICK STAGE",
        "dry_mass": 1000,
        "fuel_capacity": 4000,
        "thrust": 100000,
        "vacuum_thrust": 130000,
        "flow": 30,
        "engine_count": 1
      }
    ],
    "presets_add": {
      "EXAMPLE_PROBE": {
        "label": "Example · Probe launcher",
        "description": "A small launcher with an additional orbital kick stage.",
        "name": "Example Probe Launcher",
        "payload_mass": 2400,
        "payload_id": "mapping_probe",
        "stages": [
          "scout_booster",
          "scout_upper",
          "example_kick_stage"
        ]
      }
    }
  }
}
```

Payload entries may define `visual_type` (`probe`, `crew`, `satellite` or `cargo`), `visual_width_factor`, `visual_height_factor` and `visual_color_rgb`. The workshop also exposes these properties in the payload editor, so they can be changed per craft without editing the mod file. These settings control the payload silhouette in both the workshop and flight view. Custom payload entries without visual fields retain the default probe appearance. Payload visual settings are copied into saved craft designs, so their appearance survives changes to the catalog.

The workshop reads payload, engine-count and tank-scale choices from `rocket.builder_options`. Add choices with `payloads_add`, `engine_counts_add` and `tank_scales_add`. Payload mass, stage count, engine count, total vehicle mass and tank scale have no built-in upper design caps. A mod can optionally define `payload_mass_limits` when it wants to constrain its own payload choices. Engine counts must be positive whole numbers, and tank scales must be positive. The list must retain a 1.0 standard scale.

## Adding celestial bodies

Use `planets_add` to add a planet and `satellites_add` inside a planet object to add moons. These entries use the same fields and units as the matching entries in `data/content_catalog.json`. A planet needs its orbital elements, physical values, atmosphere object, solidity flag and display color. A satellite needs its mass, radius, orbit radius and period, phase, rotation rate, solidity and color.

The catalog uses SI units for physical values unless a field name or the built-in catalog documentation says otherwise. Planetary `a` is in AU, planet orbital angles are in degrees, and element rates are per Julian century. Satellite phase and rotation rate are radians and radians per second.

## How overlays work

- Objects merge recursively. You can override just one property, such as a planet's color.
- A key ending in `_add` extends the matching array or dictionary. For example: `stage_parts_add`, `planets_add`, `satellites_add`, `payloads_add` and `presets_add`.
- When an added array entry has the same `id` or `name` as an existing entry, its supplied properties update that entry instead of creating a duplicate.
- A normal array key replaces that whole array. Use this when you intentionally want to redefine a complete list.
- You can still use a complete copy of `content_catalog.json` as a full override.
- The combined catalog is validated at startup. Invalid JSON, missing required values, duplicate IDs or invalid physical ranges cause the mod to be ignored; the built-in catalog remains active.

## Practical notes

Back up your mod before changing it. Keep IDs stable once a saved vehicle or preset refers to them. Saved vehicle designs store stage data as well as part IDs, so a saved craft can continue to work even if its original catalog part is later renamed. Mods change data, not game scripts: adding new physics models or entirely new behaviours still requires a code mod or a project change.
