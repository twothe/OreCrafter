#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROOT_DIR="${ROOT_DIR}" python - <<'PY'
import json
import os
import shutil
import zipfile
from pathlib import Path

root=Path(os.environ["ROOT_DIR"])
info=json.loads((root / "info.json").read_text(encoding="utf-8"))
name=info["name"]
version=info["version"]

dist=root / "dist"
staging=dist / f"{name}_{version}"
zip_path=dist / f"{name}_{version}.zip"

dist.mkdir(parents=True, exist_ok=True)
if staging.exists():
	shutil.rmtree(staging)
if zip_path.exists():
	zip_path.unlink()

exclude_names={
	".git",
	".idea",
	".vscode",
	"dist",
	"scripts",
	"AGENTS.md",
	"testcases.md",
	"docs",
}

def ignore(path, names):
	ignored=[]
	for n in names:
		if n in exclude_names or n.endswith("~") or n.endswith(".tmp"):
			ignored.append(n)
	return set(ignored)

shutil.copytree(root, staging, ignore=ignore)

with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
	for path in staging.rglob("*"):
		if path.is_dir():
			continue
		zf.write(path, path.relative_to(dist))

print(str(zip_path))
PY
