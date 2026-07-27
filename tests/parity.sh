#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${PII_REDACTOR_CONFIG:-$script_dir/../wp-config.php}"

if [[ ! -f "$config" ]]; then
    echo "Parity test requires wp-config.php: $config" >&2
    exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

compare_case() {
    local name="$1"
    shift

    local python_output="$tmpdir/$name.python"
    local phel_output="$tmpdir/$name.phel"

    (
        cd "$script_dir/.."
        python3 scripts/pii-redactor.py --config "$config" "$@"
    ) 2>&1 | sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2} //' >"$python_output"

    (
        cd "$script_dir"
        ./pii-redactor.php --config "$config" "$@"
    ) 2>&1 | sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2} //' >"$phel_output"

    diff -u "$python_output" "$phel_output"
    echo "Python/Phel parity ($name): OK"
}

compare_case full-dry-run --dry-run --verbose
compare_case disabled-types --dry-run --no-names --no-urls --no-ips
compare_case single-table --dry-run --table wp_users
compare_case whitelist --dry-run --verbose --whitelist-users admin
compare_case summary --summary
