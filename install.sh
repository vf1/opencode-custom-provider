#!/bin/sh
# opencode-custom-provider installer.
#
# Downloads the generated provider config from the release and adds/updates
# the "models" section of a provider in an opencode config. Everything else in
# the provider block (npm, name, options, apiKey) is left to the user.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/vf1/opencode-custom-provider/main/install.sh | sh
#   curl -fsSL ... | sh -s -- <provider-key>
#   curl -fsSL ... | sh -s -- --config /path/to/opencode.json <provider-key>
#
# Options:
#   --config PATH   target config (default: ~/.config/opencode/opencode.json)
#   -h, --help      show this help
# Env:
#   OCC_URL         download URL override (default: the commandcode.json
#                   release asset)
#
# The optional provider-key is the key to write into in the config. Without it
# the key(s) from the downloaded JSON are used (command-code). So if your
# config key differs (e.g. "commandcode"), pass it: sh -s -- commandcode

set -eu

URL="${OCC_URL:-https://github.com/vf1/opencode-custom-provider/releases/download/files/commandcode.json}"
CONFIG=""
KEY=""

usage() {
  printf '%s\n' \
    "usage: install.sh [--config PATH] [provider-key]" \
    "" \
    "  Downloads models from the opencode-custom-provider release and" \
    "  adds/updates provider.<key>.models in an opencode config." \
    "  Default config: ~/.config/opencode/opencode.json" \
    "  provider-key: config key to write into (default: the key(s) from" \
    "  the downloaded JSON, e.g. command-code). If your config key is" \
    "  different (e.g. commandcode), pass it." \
    "  Env OCC_URL overrides the download URL."
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --config)
      if [ $# -lt 2 ]; then
        echo "install.sh: --config needs a path" >&2
        exit 1
      fi
      CONFIG="$2"
      shift 2
      ;;
    --config=*)
      CONFIG="${1#*=}"
      shift
      ;;
    -*)
      echo "install.sh: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "$KEY" ]; then
        echo "install.sh: only one provider key expected" >&2
        exit 1
      fi
      KEY="$1"
      shift
      ;;
  esac
done

if [ -z "$CONFIG" ]; then
  if [ -z "${HOME:-}" ]; then
    echo "install.sh: HOME is not set, use --config PATH" >&2
    exit 1
  fi
  CONFIG="${HOME}/.config/opencode/opencode.json"
fi

case "$KEY" in
  *[\"\\]*)
    echo "install.sh: invalid provider key: $KEY" >&2
    exit 1
    ;;
esac

command -v curl >/dev/null 2>&1 || { echo "install.sh: curl is required" >&2; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "install.sh: awk is required" >&2; exit 1; }

if command -v mktemp >/dev/null 2>&1; then
  NEW=$(mktemp "${TMPDIR:-/tmp}/occ-new.XXXXXX")
else
  NEW="${TMPDIR:-/tmp}/occ-new.$$"
  : > "$NEW"
fi
OUT="$CONFIG.tmp.$$"
trap 'rm -f "$NEW" "$OUT"' EXIT INT HUP TERM

if ! curl -fsSL "$URL" -o "$NEW"; then
  echo "install.sh: cannot download $URL (release not published yet?)" >&2
  exit 1
fi

PROG='
function skipws(s, i) {
  while (i <= length(s) && substr(s, i, 1) ~ /[ \t\r\n]/) i++
  return i
}
function skipstr(s, i,   c) {
  i++
  while (i <= length(s)) {
    c = substr(s, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "\"") return i + 1
    i++
  }
  return 0
}
function skipnum(s, i,   c) {
  while (i <= length(s)) {
    c = substr(s, i, 1)
    if (c !~ /[-+0-9.eE]/) break
    i++
  }
  return i
}
function skipval(s, i,   c, q) {
  i = skipws(s, i)
  c = substr(s, i, 1)
  if (c == "\"") return skipstr(s, i)
  if (c == "{") return skipobj(s, i)
  if (c == "[") return skiparr(s, i)
  if (c == "-" || c ~ /[0-9]/) return skipnum(s, i)
  if (substr(s, i, 4) == "true") return i + 4
  if (substr(s, i, 5) == "false") return i + 5
  if (substr(s, i, 4) == "null") return i + 4
  return 0
}
function skipobj(s, i,   c, q) {
  i = skipws(s, i + 1)
  if (substr(s, i, 1) == "}") return i + 1
  while (i <= length(s)) {
    i = skipws(s, i)
    if (substr(s, i, 1) != "\"") return 0
    q = skipstr(s, i)
    if (q == 0) return 0
    i = skipws(s, q)
    if (substr(s, i, 1) != ":") return 0
    i = skipval(s, i + 1)
    if (i == 0) return 0
    i = skipws(s, i)
    c = substr(s, i, 1)
    if (c == ",") { i++; continue }
    if (c == "}") return i + 1
    return 0
  }
  return 0
}
function skiparr(s, i,   c) {
  i = skipws(s, i + 1)
  if (substr(s, i, 1) == "]") return i + 1
  while (i <= length(s)) {
    i = skipval(s, i)
    if (i == 0) return 0
    i = skipws(s, i)
    c = substr(s, i, 1)
    if (c == ",") { i++; continue }
    if (c == "]") return i + 1
    return 0
  }
  return 0
}
function valid(s,   i, q) {
  i = skipws(s, 1)
  q = skipval(s, i)
  if (q == 0) return 0
  q = skipws(s, q)
  return q > length(s)
}
function emptyobj(s, i,   p) {
  p = skipws(s, i + 1)
  return substr(s, p, 1) == "}"
}
function findkey(s, i, key,   c, k, ke, p, q) {
  i = skipws(s, i)
  if (substr(s, i, 1) != "{") return 0
  i++
  while (i <= length(s)) {
    i = skipws(s, i)
    c = substr(s, i, 1)
    if (c == "}" || c == "") return 0
    if (c == ",") { i++; continue }
    if (c != "\"") return 0
    ke = skipstr(s, i)
    if (ke == 0) return 0
    k = substr(s, i + 1, ke - i - 2)
    p = skipws(s, ke)
    if (substr(s, p, 1) != ":") return 0
    p = skipws(s, p + 1)
    q = skipval(s, p)
    if (q == 0) return 0
    if (k == key) { FVS = p; FVE = q; return 1 }
    i = q
  }
  return 0
}
function countkeys(s, i,   c, ke, p, q, n) {
  i = skipws(s, i)
  if (substr(s, i, 1) != "{") return -1
  i++
  n = 0
  while (i <= length(s)) {
    i = skipws(s, i)
    c = substr(s, i, 1)
    if (c == "}") return n
    if (c == ",") { i++; continue }
    if (c != "\"") return -1
    ke = skipstr(s, i)
    if (ke == 0) return -1
    p = skipws(s, ke)
    if (substr(s, p, 1) != ":") return -1
    p = skipws(s, p + 1)
    q = skipval(s, p)
    if (q == 0) return -1
    n++
    i = q
  }
  return -1
}
function listkeys(s, i,   c, k, ke, p, q) {
  i = skipws(s, i)
  if (substr(s, i, 1) != "{") return 0
  i++
  while (i <= length(s)) {
    i = skipws(s, i)
    c = substr(s, i, 1)
    if (c == "}") return 1
    if (c == ",") { i++; continue }
    if (c != "\"") return 0
    ke = skipstr(s, i)
    if (ke == 0) return 0
    k = substr(s, i + 1, ke - i - 2)
    p = skipws(s, ke)
    if (substr(s, p, 1) != ":") return 0
    p = skipws(s, p + 1)
    q = skipval(s, p)
    if (q == 0) return 0
    print k
    i = q
  }
  return 0
}
function insert_add(s, opos, ins,   cpos) {
  cpos = skipval(s, opos) - 1
  if (emptyobj(s, opos)) return substr(s, 1, cpos - 1) ins substr(s, cpos)
  return substr(s, 1, cpos - 1) "," ins substr(s, cpos)
}
function readfile(f,   line, s) {
  s = ""
  while ((getline line < f) > 0) s = s line "\n"
  close(f)
  return s
}
BEGIN {
  s = readfile(NEWF)
  if (!valid(s)) {
    print "install.sh: downloaded file is not valid JSON" > "/dev/stderr"
    exit 1
  }
  if (MODE == "listkeys") {
    if (!findkey(s, 1, "provider")) {
      print "install.sh: no provider section in downloaded file" > "/dev/stderr"
      exit 1
    }
    if (!listkeys(s, FVS)) {
      print "install.sh: cannot parse provider section in downloaded file" > "/dev/stderr"
      exit 1
    }
    exit 0
  }
  if (!findkey(s, 1, "provider") || !findkey(s, FVS, SRC) || !findkey(s, FVS, "models")) {
    print "install.sh: provider \"" SRC "\" not found in downloaded file" > "/dev/stderr"
    exit 1
  }
  models = substr(s, FVS, FVE - FVS)
  n = countkeys(s, FVS)
  if (n < 0) {
    print "install.sh: cannot parse models in downloaded file" > "/dev/stderr"
    exit 1
  }
  cfg = readfile(CFGF)
  if (!valid(cfg)) {
    print "install.sh: config is not valid strict JSON (jsonc comments/trailing commas unsupported): " CFGF > "/dev/stderr"
    exit 1
  }
  root = skipws(cfg, 1)
  if (substr(cfg, root, 1) != "{") {
    print "install.sh: config root is not a JSON object: " CFGF > "/dev/stderr"
    exit 1
  }
  if (!findkey(cfg, 1, "provider")) {
    out = insert_add(cfg, root, "\"provider\":{\"" DST "\":{\"models\":" models "}}")
    status = "created " n
  } else if (!findkey(cfg, FVS, DST)) {
    out = insert_add(cfg, FVS, "\"" DST "\":{\"models\":" models "}")
    status = "created " n
  } else {
    pobj = FVS
    if (findkey(cfg, pobj, "models")) {
      out = substr(cfg, 1, FVS - 1) models substr(cfg, FVE)
    } else {
      out = insert_add(cfg, pobj, "\"models\":" models)
    }
    status = "updated " n
  }
  printf "%s", out > OUT
  close(OUT)
  print status
}
'

newkeys=$(awk -v MODE=listkeys -v NEWF="$NEW" "$PROG")
if [ -z "$newkeys" ]; then
  echo "install.sh: no providers in downloaded file" >&2
  exit 1
fi

made_config=0
if [ ! -e "$CONFIG" ]; then
  mkdir -p "$(dirname "$CONFIG")"
  printf '%s\n' '{"$schema":"https://opencode.ai/config.json","provider":{}}' > "$CONFIG"
  made_config=1
  echo "install.sh: created $CONFIG"
fi

backed=0
merge_one() {
  src="$1"
  dst="$2"
  status=$(awk -v MODE=merge -v SRC="$src" -v DST="$dst" -v NEWF="$NEW" -v CFGF="$CONFIG" -v OUT="$OUT" "$PROG")
  if cmp -s "$OUT" "$CONFIG"; then
    rm -f "$OUT"
    echo "provider $dst: unchanged"
    return 0
  fi
  if [ "$backed" -eq 0 ] && [ "$made_config" -eq 0 ]; then
    cp "$CONFIG" "$CONFIG.bak"
    backed=1
  fi
  mv "$OUT" "$CONFIG"
  action=${status%% *}
  n=${status#* }
  echo "provider $dst: $action ($n models)"
  if [ "$action" = "created" ]; then
    printf '%s\n' \
      "note: provider \"$dst\" now contains \"models\" only - add the rest yourself:" \
      "      \"npm\": \"@ai-sdk/openai-compatible\"," \
      "      \"options\": { \"baseURL\": \"https://api.example.com/v1\", \"apiKey\": \"...\" }"
  fi
}

if [ -n "$KEY" ]; then
  found=0
  for k in $newkeys; do
    if [ "$k" = "$KEY" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 1 ]; then
    merge_one "$KEY" "$KEY"
  else
    nkeys=0
    for k in $newkeys; do
      nkeys=$((nkeys + 1))
    done
    if [ "$nkeys" -ne 1 ]; then
      echo "install.sh: provider \"$KEY\" not in downloaded file, available:" >&2
      printf '%s\n' "$newkeys" >&2
      exit 1
    fi
    for k in $newkeys; do
      merge_one "$k" "$KEY"
    done
  fi
else
  for k in $newkeys; do
    merge_one "$k" "$k"
  done
fi

if [ "$backed" -eq 1 ]; then
  echo "config: $CONFIG (backup: $CONFIG.bak)"
else
  echo "config: $CONFIG (no changes)"
fi
