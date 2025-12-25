# Testing
- `check-lua.sh` performs a syntax compile check on all Lua files using `luac`, `lua`, or `luajit`.
- Optional: set `LUAC_BIN`, `LUA_BIN`, or `LUAJIT_BIN` to point at custom executables.
- Full validation still requires loading the mod in Factorio, since data/control stages depend on the game runtime.
- Multiplayer smoke test: have a new player join to validate `on_player_created` initialization logic.
