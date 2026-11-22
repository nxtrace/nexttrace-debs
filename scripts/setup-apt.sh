#!/usr/bin/env bash

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

source_entry() {
    printf '%s\n' 'Types: deb' "URIs: $1/" 'Suites: ./' "${@:2}"
}

check_other_sources() {
    local file
    for file in /etc/apt/sources.list "$source_dir"/*.list "$source_dir"/*.sources; do
        [[ "$file" != "$source_path" && -f "$file" ]] || continue
        [[ -r "$file" ]] || fail "Cannot read APT source: $file"
        # Ignore commented lines and disabled deb822 stanzas.
        if awk -v legacy="$legacy" -v mirror="$mirror" -v file="$file" '
            function check_uris(line, fields, count, i) {
                count = split(line, fields, /[[:space:]]+/)
                for (i = 1; i <= count; i++) {
                    sub(/\/+$/, "", fields[i])
                    if (tolower(fields[i]) == legacy || tolower(fields[i]) == mirror)
                        matches = 1
                }
            }
            function finish() {
                if (matches && !disabled) found = 1
                matches = disabled = continuation = 0
            }
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { finish(); next }
            file !~ /\.sources$/ {
                if ($0 ~ /^[[:space:]]*deb(-src)?[[:space:]]/) {
                    sub(/#.*/, "")
                    check_uris($0)
                    finish()
                }
                next
            }
            /^[[:space:]]/ { if (continuation) check_uris($0); next }
            {
                continuation = 0
                line = tolower($0)
                if (line ~ /^enabled:[[:space:]]*no[[:space:]]*$/) disabled = 1
                if (line ~ /^uris:/) {
                    sub(/^uris:[[:space:]]*/, "", line)
                    check_uris(line)
                    continuation = 1
                }
            }
            END { finish(); exit !found }
        ' "$file"; then
            fail "NextTrace APT source found in $file. Follow the manual steps: $manual"
        elif (( $? != 1 )); then
            fail "Could not check APT source: $file"
        fi
    done
}

verify_key() {
    local digest
    digest=$(sha256sum < "$1")
    [[ "${digest%% *}" == "$key_sha256" ]]
}

write_file() {
    local destination="$2" staged
    staged=$("${privilege[@]}" mktemp "${destination}.XXXXXXXX")
    if ! "${privilege[@]}" install -m 0644 -- "$1" "$staged" ||
       ! "${privilege[@]}" mv -fT -- "$staged" "$destination"; then
        "${privilege[@]}" rm -f -- "$staged"
        fail "Could not write $destination"
    fi
}

main() (
    set -euo pipefail

    local mirror=https://apt.nxtrace.org
    local legacy=https://github.com/nxtrace/nexttrace-debs/releases/latest/download
    local manual=https://github.com/nxtrace/nexttrace-debs/blob/main/README.md
    local keyring=/etc/apt/keyrings/nexttrace.gpg
    local key_sha256=8788228a58068eb7cc6b9d2efa3c7c42593aa1dca6a8afe541778b97de39f05f
    local source_dir=/etc/apt/sources.list.d
    local source_path="$source_dir/nexttrace.sources"
    local staged backup change_source=true migrate=false
    local -a privilege=()

    [[ -d "$source_dir" ]] || fail "APT source directory not found: $source_dir"
    if (( EUID != 0 )); then
        command -v sudo >/dev/null || fail "Run this script as root or with sudo available."
        privilege=(sudo)
    fi

    staged=$(mktemp -d)
    trap 'rm -rf -- "$staged"' EXIT
    source_entry "$mirror" "Signed-By: $keyring" 'By-Hash: force' > "$staged/new.sources"
    source_entry "$legacy" "Signed-By: $keyring" > "$staged/legacy.sources"
    source_entry "$legacy" 'Trusted: yes' > "$staged/legacy-trusted.sources"

    if [[ -e "$source_path" || -L "$source_path" ]]; then
        [[ -f "$source_path" && ! -L "$source_path" ]] ||
            fail "Cannot replace $source_path. Follow the manual steps: $manual"
        if cmp -s "$staged/new.sources" "$source_path"; then
            change_source=false
        elif cmp -s "$staged/legacy.sources" "$source_path" ||
             cmp -s "$staged/legacy-trusted.sources" "$source_path"; then
            migrate=true
        else
            fail "Custom APT source at $source_path. Follow the manual steps: $manual"
        fi
    fi
    check_other_sources

    if [[ -e "$keyring" || -L "$keyring" ]]; then
        [[ -f "$keyring" && ! -L "$keyring" ]] && verify_key "$keyring" ||
            fail "Unexpected archive key at $keyring. Follow the manual steps: $manual"
    else
        curl -fsSL -o "$staged/archive.gpg" "$mirror/nexttrace-archive-keyring.gpg"
        verify_key "$staged/archive.gpg" || fail "NextTrace archive key SHA-256 mismatch."
    fi

    if [[ "$migrate" == true ]]; then
        backup=$("${privilege[@]}" mktemp --suffix=.bak "$source_path.XXXXXXXX")
        if ! "${privilege[@]}" install -m 0644 -- "$source_path" "$backup"; then
            "${privilege[@]}" rm -f -- "$backup"
            fail "Could not back up $source_path"
        fi
        printf 'Backed up the GitHub source to %s\n' "$backup"
    fi
    if [[ -f "$staged/archive.gpg" ]]; then
        if [[ ! -d "${keyring%/*}" ]]; then
            "${privilege[@]}" install -d -m 0755 -- "${keyring%/*}"
        fi
        write_file "$staged/archive.gpg" "$keyring"
    elif [[ "$(stat -c '%a' -- "$keyring")" != 644 ]]; then
        "${privilege[@]}" chmod 0644 -- "$keyring"
    fi
    if [[ "$change_source" == true ]]; then
        write_file "$staged/new.sources" "$source_path"
    fi
    printf '%s\n' 'NextTrace APT source configured. Run sudo apt update to refresh package lists.'
)

main
