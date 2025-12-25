#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFO_PATH="${ROOT_DIR}/info.json"
DIST_DIR="${ROOT_DIR}/dist"

require_command() {
	local command_name="$1"
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "error: required command not found: ${command_name}" >&2
		exit 1
	fi
}

read_json_field() {
	local key="$1"
	local value=""

	if command -v node >/dev/null 2>&1; then
		value="$(node -e "const fs=require('fs');const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));const v=data[process.argv[2]];if(typeof v!=='string'){console.error('error: info.json missing string field '+process.argv[2]);process.exit(1);}console.log(v);" "${INFO_PATH}" "${key}")"
	elif command -v jq >/dev/null 2>&1; then
		value="$(jq -r ".${key}" "${INFO_PATH}")"
		if [ "${value}" = "null" ] || [ -z "${value}" ]; then
			echo "error: info.json missing string field ${key}" >&2
			exit 1
		fi
	else
		echo "error: node or jq is required to read info.json" >&2
		exit 1
	fi

	printf '%s\n' "${value}"
}

require_command tar
require_command zip

if [ ! -f "${INFO_PATH}" ]; then
	echo "error: info.json not found at ${INFO_PATH}" >&2
	exit 1
fi

name="$(read_json_field name)"
version="$(read_json_field version)"

staging_dir="${DIST_DIR}/${name}_${version}"
zip_path="${DIST_DIR}/${name}_${version}.zip"

mkdir -p "${DIST_DIR}"
rm -rf "${staging_dir}" "${zip_path}"
mkdir -p "${staging_dir}"

exclude_args=(
	"--exclude=.git"
	"--exclude=.idea"
	"--exclude=.vscode"
	"--exclude=dist"
	"--exclude=scripts"
	"--exclude=docs"
	"--exclude=AGENTS.md"
	"--exclude=testcases.md"
	"--exclude=todo.md"
	"--exclude=release.sh"
	"--exclude=*~"
	"--exclude=*.tmp"
)

(
	cd "${ROOT_DIR}"
	tar "${exclude_args[@]}" -cf - . | tar -xf - -C "${staging_dir}"
)

(
	cd "${DIST_DIR}"
	zip -r "$(basename "${zip_path}")" "$(basename "${staging_dir}")"
)

printf '%s\n' "${zip_path}"
