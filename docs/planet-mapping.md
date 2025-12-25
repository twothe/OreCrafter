# Planet Mapping Notes
This document summarizes how OreCrafter infers which outputs belong to which planets and what to watch out for when reading map-gen data.

## Data sources used by OreCrafter
- Planet prototypes expose `map_gen_settings` with `autoplace_controls` and `autoplace_settings`. These are the primary inputs for per-planet output mapping.
- `autoplace_controls` is a dictionary keyed by `AutoplaceControl` names (for example, the control name `"trees"` exists alongside resource controls).
- `autoplace_settings` contains per-entity overrides and a `treat_missing_as_default` flag that can enable entities even when not explicitly listed.

## Practical implications
- A control name may represent a whole category, not a single entity (e.g., the control `"trees"` does not identify a specific tree prototype). Relying on controls alone can over-include outputs on planets that share a control but not a specific entity.
- `autoplace_settings.entity.settings` is more precise because it keys by entity name, but it can be incomplete when defaults apply or when a planet relies on `treat_missing_as_default`.
- Because map-gen defaults can implicitly enable entities, missing explicit entries does not always mean an entity never appears. Planet output mapping should prefer explicit entity listings, then fall back cautiously to controls.

## OreCrafter rules (current)
- Resources: prefer planet resource mappings derived from autoplace controls and resource entities.
- Trees: prefer per-entity planet listings (`autoplace_settings.entity.settings`) and only fall back to specific controls (avoid generic `"trees"`), preventing cross-planet leakage such as Vulcanus-only tree outputs appearing on Nauvis.
- If `Restrict planet resources` is enabled and a required mapping is missing, OreCrafter raises a clear error to force explicit mapping or a settings change.

## When to adjust mapping
- If a planet uses implicit defaults (missing explicit entries), you may need to add explicit entries or relax restrictions for accurate planet output lists.
- If a control is too broad (like `"trees"`), tighten mapping to per-entity settings to avoid assigning outputs to unrelated planets.

## References
- Factorio API: `MapGenSettings` and `AutoplaceSettings` describe map-gen controls, entity settings, and defaulting rules: https://lua-api.factorio.com/latest/Concepts.html#MapGenSettings and https://lua-api.factorio.com/latest/Concepts.html#AutoplaceSettings
- Factorio API: `AutoplaceControl` describes control keys such as `"trees"` and resource controls: https://lua-api.factorio.com/latest/Concepts.html#AutoplaceControl
- Factorio API: `PlanetPrototype` documents per-planet `map_gen_settings`: https://lua-api.factorio.com/latest/prototypes/PlanetPrototype.html
