#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# HPE Sales Platform — smoke test
# Run after EVERY change to index.html, before committing.
#   ./smoke.sh
# Exits non-zero if anything fails, so it's safe to chain:  ./smoke.sh && git add -A
# ---------------------------------------------------------------------------
set -uo pipefail

FILE="${1:-index.html}"
EXPECTED_DUP_IDS=6
fail=0

# Portable temp dir + utf-8 stdout so we work on Windows (git-bash) too,
# where /tmp/ means different things to native Python vs Node-via-bash.
SMOKE_TMP="$(mktemp -d)"
trap 'rm -rf "$SMOKE_TMP"' EXIT
export PYTHONIOENCODING=utf-8

if [[ ! -f "$FILE" ]]; then
  echo "✗ $FILE not found (pass a path as the first arg if it's elsewhere)"
  exit 1
fi

echo "── Smoke test: $FILE ──────────────────────────────────"

# 1) JS SYNTAX — extract every non-src <script> block, concat, node --check.
python3 - "$FILE" "$SMOKE_TMP" <<'PY'
import re, sys, os
h = open(sys.argv[1], encoding='utf-8', errors='replace').read()
blocks = re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', h, flags=re.S | re.I)
open(os.path.join(sys.argv[2], 'hpe_smoke.js'), 'w', encoding='utf-8').write('\n\n'.join(blocks))
PY
if node --check "$SMOKE_TMP/hpe_smoke.js" 2>"$SMOKE_TMP/hpe_smoke.err"; then
  echo "✓ JS syntax OK"
else
  echo "✗ JS syntax FAILED:"
  cat "$SMOKE_TMP/hpe_smoke.err"
  fail=1
fi

# 2) DUPLICATE-ID SCAN — must equal exactly the known baseline.
#    Baseline dupes are EXPECTED (they're template-literal IDs / repeated widgets):
#      set-apikey, list-col-vis-style, '+id+', cv-main-img, cv-thumb-'+i+', pkg-list-${b.name}
#    A 7th means new markup introduced a real collision — investigate before shipping.
dupcount=$(python3 - "$FILE" "$SMOKE_TMP" <<'PY'
import re, sys, os, json
from collections import Counter
c = Counter(re.findall(r'\sid="([^"]+)"', open(sys.argv[1], encoding='utf-8', errors='replace').read()))
dups = {i: n for i, n in c.items() if n > 1}
print(len(dups))
open(os.path.join(sys.argv[2], 'hpe_dups.json'), 'w').write(json.dumps(dups))
PY
)
if [[ "$dupcount" -eq "$EXPECTED_DUP_IDS" ]]; then
  echo "✓ Duplicate-IDs = $dupcount (baseline)"
else
  echo "✗ Duplicate-IDs = $dupcount (expected $EXPECTED_DUP_IDS)"
  echo "  Current dupes:"
  SMOKE_TMP="$SMOKE_TMP" python3 -c "import json,os;[print('   ',k,'x',v) for k,v in json.load(open(os.path.join(os.environ['SMOKE_TMP'],'hpe_dups.json'))).items()]"
  fail=1
fi

# 3) VERSION CONSISTENCY — the three touchpoints must all carry the same version.
python3 - "$FILE" <<'PY'
import re, sys
h = open(sys.argv[1], encoding='utf-8', errors='replace').read()
title = re.search(r'<title>HPE Sales Platform v([0-9.]+)</title>', h)
pill  = re.search(r'flex-shrink:0;cursor:pointer">v([0-9.]+)</div>', h)
cfg   = re.search(r"version:\s*'([0-9.]+)'", h)
vals = {'title': title and title.group(1),
        'topbar pill': pill and pill.group(1),
        'config.version': cfg and cfg.group(1)}
uniq = set(v for v in vals.values() if v)
if None in vals.values():
    print('⚠ version touchpoint not found:', {k: v for k, v in vals.items() if v is None})
    sys.exit(2)
if len(uniq) == 1:
    print('✓ Version consistent across 3 touchpoints: v' + uniq.pop())
else:
    print('✗ Version MISMATCH across touchpoints:', vals)
    sys.exit(2)
PY
[[ $? -ne 0 ]] && fail=1

echo "───────────────────────────────────────────────────────"
if [[ $fail -eq 0 ]]; then
  echo "✓ ALL CHECKS PASSED"
  exit 0
else
  echo "✗ SMOKE TEST FAILED — do not commit until green."
  exit 1
fi
