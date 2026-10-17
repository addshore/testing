#!/bin/sh
set -eu

cd "${1:-/results}"
export GIT_TERMINAL_PROMPT=0
if [ "$CLONE_USER_AGENT" = explicit ]; then
    export GIT_HTTP_USER_AGENT='mwcli-clone-diagnostic/1.0 (https://github.com/addshore/testing)'
fi
git --version
curl --version
printf 'User-agent mode: %s\n' "$CLONE_USER_AGENT"
failed=0
for repository in Wikibase ParserFunctions; do
    url="https://gerrit.wikimedia.org/r/mediawiki/extensions/$repository"
    # Probe the same smart-HTTP endpoint Git uses, retaining headers and body.
    agent="${GIT_HTTP_USER_AGENT:-git/$(git --version | cut -d ' ' -f 3)}"
    curl --silent --show-error --max-time 30 --user-agent "$agent" \
        --dump-header "$repository-headers.log" \
        --output "$repository-response.log" \
        --write-out "$repository HTTP %{http_code}; remote %{remote_ip}\n" \
        "$url/info/refs?service=git-upload-pack" || true
    cat "$repository-headers.log"
    # Public endpoints only; no credentials are passed to Git or curl.
    if GIT_TRACE_CURL=1 GIT_TRACE_CURL_NO_DATA=1 \
        timeout 240 git clone --depth=1 --recurse-submodules \
        "$url" "$repository" > "$repository-clone.log" 2>&1; then
        printf '%s clone succeeded\n' "$repository"
    else
        failed=1
        printf '%s clone failed\n' "$repository"
    fi
    tail -n 35 "$repository-clone.log"
done
exit "$failed"
