#!/usr/bin/env bash
# Licensed under the GNU General Public License v2 (GPLv2); see LICENSE.
# Copyright (C) 2026 Ding Zheng Yuan
# Run the in-app self test in a real Xournal++ with a throwaway config dir.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/config/xournalpp/plugins"
ln -s "$here/Bookmarks" "$tmp/config/xournalpp/plugins/Bookmarks"
ln -s "$here/tests/selftest" "$tmp/config/xournalpp/plugins/BookmarksSelfTest"

cat <<'EOF' > "$tmp/doc.xopp"
<?xml version="1.0" standalone="no"?>
<xournal creator="xournalpp 1.3.8" fileversion="4">
<title>Bookmarks selftest</title>
<page width="595.27559100" height="841.88976400"><background type="solid" color="#ffffffff" style="ruled"/><layer name="Layer 1"/></page>
<page width="595.27559100" height="841.88976400"><background type="solid" color="#ffffffff" style="ruled"/><layer name="Layer 1"/></page>
</xournal>
EOF

export BM_PLUGIN_DIR="$here/Bookmarks" BM_DOC="$tmp/doc.xopp" BM_OUT="$tmp/result.txt" BM_TMP="$tmp"
XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data" \
  timeout "${SELFTEST_TIMEOUT:-60}" xournalpp >"$tmp/xournalpp.log" 2>&1 && rc=0 || rc=$?

cat "$tmp/result.txt" 2>/dev/null || echo "no result file"
if grep -qi "lua\|plugin" "$tmp/xournalpp.log"; then
  echo "--- xournalpp log (plugin/lua lines) ---"
  grep -i "lua\|plugin" "$tmp/xournalpp.log" | head -20
fi

saved_xml="$(gzip -dc "$tmp/doc.xopp" 2>/dev/null || cat "$tmp/doc.xopp")"
echo "--- saved bookmarks ---"
echo "$saved_xml" | grep -o 'Bookmark::[^"]*' || true
echo "--- xournalpp exit code: $rc ---"

grep -q "DONE failures=0" "$tmp/result.txt" && \
  grep -q 'Plugin "Bookmarks" UI initialized' "$tmp/xournalpp.log" && \
  echo "$saved_xml" | grep -q 'Bookmark::' && \
  [[ $rc -eq 0 ]]
