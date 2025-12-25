# Release Process
Use `./release.sh` to create a Factorio-compatible ZIP in `dist/`.

## Output
- `dist/<mod-name>_<version>/` staging folder
- `dist/<mod-name>_<version>.zip` upload-ready archive

## Notes
- The release script excludes dev-only files and folders (e.g., `docs`, `scripts`, `AGENTS.md`, `release.sh`).
- The script requires `zip` and either `node` or `jq` to read `info.json`.
