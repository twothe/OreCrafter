# AGENTS
- Project: OreCrafter Factorio mod (currently 1.1) that generates ore duplication recipes from detected resources/trees.
- Data stage: `data.lua` declares item-group/subgroups; `data-final-fixes.lua` scans resources/trees and builds recipes.
- Control stage: `control.lua` adjusts starter inventory and adds assemblers + fusion generator.
- Settings: `settings.lua` defines startup tuning for item/fluid duplication and fusion generator power.
- Libraries: `lib/` provides `proto` + `logic` helpers; `lib_data_logic.lua` drives resource/recipe scanning.
- Conventions: use tabs for indentation; keep `docs/` and `testcases.md` current; maintain `todo.md` during multi-step work.
