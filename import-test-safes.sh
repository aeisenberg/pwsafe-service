#!/bin/bash
set -euo pipefail

if [[ $# -gt 1 || ${1:-} == "--help" || ${1:-} == "-h" ]]; then
    echo "Usage: $0 [base-url]"
    echo "Upload backend/testdata/*.psafe3 with overwrite=true."
    echo "The default base URL is http://localhost:8080."
    if [[ $# -gt 1 ]]; then
        exit 1
    fi
    exit 0
fi

for command in curl jq; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
base_url="${1:-http://localhost:8080}"
base_url="${base_url%/}"
shopt -s nullglob
safes=("$script_dir"/backend/testdata/*.psafe3)
if [[ ${#safes[@]} -eq 0 ]]; then
    echo "No test safes found in $script_dir/backend/testdata." >&2
    exit 1
fi

temp_dir="$(mktemp -d)"
cleanup() {
    rm -f -- "$temp_dir/cookies"
    rmdir -- "$temp_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

csrf_token="$(curl --fail --silent --show-error "$base_url/web/" \
    | sed -n 's/.*window.__PWSAFE_CSRF_TOKEN="\([^"]*\)".*/\1/p')"
if [[ -z "$csrf_token" ]]; then
    echo "No CSRF token found at $base_url/web/." >&2
    exit 1
fi

auth_mode="$(curl --fail --silent --show-error "$base_url/api/auth/status" \
    | jq -er '.mode')"
case "$auth_mode" in
    enabled)
        read -r -s -p "Service password: " password
        printf '\n'
        printf '%s' "$password" | jq -Rs '{password: .}' \
            | curl --fail --silent --show-error \
                --cookie-jar "$temp_dir/cookies" \
                -H "X-PWSAFE-CSRF-Token: $csrf_token" \
                -H "Content-Type: application/json" \
                --data-binary @- \
                "$base_url/api/auth/login"
        unset password
        printf '\n'
        ;;
    disabled)
        touch "$temp_dir/cookies"
        ;;
    *)
        echo "Service authentication is not configured. Complete setup in the web UI first." >&2
        exit 1
        ;;
esac

for safe in "${safes[@]}"; do
    echo "Import: $(basename -- "$safe")"
    curl --fail --silent --show-error \
        --cookie "$temp_dir/cookies" \
        --cookie-jar "$temp_dir/cookies" \
        -H "X-PWSAFE-CSRF-Token: $csrf_token" \
        -F "file=@\"$safe\"" \
        "$base_url/api/providers/static/files?overwrite=true"
    printf '\n'
done

echo "Imported ${#safes[@]} test safes."
