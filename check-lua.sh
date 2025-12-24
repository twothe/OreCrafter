#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v rg >/dev/null 2>&1; then
	mapfile -d '' lua_files < <(rg --files -g '*.lua' -0 "${ROOT_DIR}")
else
	mapfile -d '' lua_files < <(find "${ROOT_DIR}" -type f -name '*.lua' -print0)
fi

if (( ${#lua_files[@]} == 0 )); then
	echo "No Lua files found."
	exit 0
fi

if [[ -n "${LUAC_BIN:-}" ]] && [[ -x "${LUAC_BIN}" ]]; then
	check_file() { "${LUAC_BIN}" -p "$1"; }
	checker="${LUAC_BIN} -p"
elif [[ -n "${LUA_BIN:-}" ]] && [[ -x "${LUA_BIN}" ]]; then
	check_file() { "${LUA_BIN}" -e "assert(loadfile(arg[1]))" "$1"; }
	checker="${LUA_BIN} loadfile"
elif [[ -n "${LUAJIT_BIN:-}" ]] && [[ -x "${LUAJIT_BIN}" ]]; then
	check_file() { "${LUAJIT_BIN}" -e "assert(loadfile(arg[1]))" "$1"; }
	checker="${LUAJIT_BIN} loadfile"
elif command -v luac >/dev/null 2>&1; then
	check_file() { luac -p "$1"; }
	checker="luac -p"
elif command -v lua >/dev/null 2>&1; then
	check_file() { lua -e "assert(loadfile(arg[1]))" "$1"; }
	checker="lua loadfile"
elif command -v luajit >/dev/null 2>&1; then
	check_file() { luajit -e "assert(loadfile(arg[1]))" "$1"; }
	checker="luajit loadfile"
else
	echo "Error: no Lua compiler/interpreter found."
	echo "Set LUAC_BIN, LUA_BIN, or LUAJIT_BIN to an executable path."
	exit 1
fi

echo "Checking ${#lua_files[@]} Lua files with ${checker}..."
for file in "${lua_files[@]}"; do
	check_file "${file}"
done

echo "OK"
