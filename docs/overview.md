# OreCrafter Overview
OreCrafter dynamically creates duplication recipes for resources, fluids, and selected plants based on the current prototype set. Recipes are generated during `data-final-fixes.lua`, after all other mods have registered their prototypes.

## Data Stage Flow
- `data.lua` defines the item-group and subgroups used to categorize the duplication recipes.
- `data-final-fixes.lua`:
	- Boots the shared `lib` framework with data-stage logic enabled.
- Scans resources and trees, using autoplace controls or planet map-gen entity entries plus `minable` definitions to detect valid ore sources.
- Scans rock-like simple entities that are part of planet map generation (counted as rocks for deconstruction) to capture additional ground-stone outputs.
- Generates per-resource recipes that consume some amount of the resource to output more of the same resource, selecting the earliest-tech output when multiple results exist.
	- Scans planet map-gen settings to map which resources, plants, and tile fluids naturally occur on each planet.
	- Scans Gleba plant prototypes to add duplication recipes for yumako and jellynut, crafted only in biochambers.
	- Adds optional `surface_conditions` to duplication recipes so they can only be crafted on planets where the resource naturally occurs.
	- Builds planet bootstrap recipes that yield low-probability outputs for resources occurring on each planet and unlock on first arrival.

## Control Stage Flow
- `control.lua` removes early-game mining drills and furnaces from starter inventory.
- Grants assembling machines, power poles, and a fusion generator entity for bootstrapping.

## Shared Library
- `lib/lib_data.lua` provides `proto` helpers (results, lab packs, autoplace control checks, etc.).
- `lib/lib_data_logic.lua` provides scanning logic that assembles the "hand" of accessible items/recipes/technologies.

## Planet Rules
- Planet restriction can limit duplication recipes to planets where the resource naturally occurs.
- Missing planet mappings or surface properties stop loading with a clear error when restrictions are enabled.
- When planet restriction is enabled, duplication recipes append the planet label to the recipe name (for example, “Coal (Nauvis)”).
- Bootstrap recipes unlock when a player first arrives on the planet.

## Configuration
See `docs/configuration.md` for the full setting list and defaults.
