#!/bin/sh
# opencode-custom-provider installer.
#
# Downloads the generated provider config from the release and adds/updates
# the "command-code" provider in an opencode config. If the provider is
# missing it is created as a full working block (npm, name, options.baseURL,
# models); if it exists, only "models" is replaced and the rest of the block
# (npm, name, options, apiKey) is left untouched.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/vf1/opencode-custom-provider/main/install.sh | sh
#   curl -fsSL ... | sh -s -- --config /path/to/opencode.json
#
# Options:
#   --config PATH   target config (default: ~/.config/opencode/opencode.json)
#   -h, --help      show this help
# Env:
#   OCC_URL         download URL override (default: the commandcode.json
#                   release asset)

set -eu

URL="${OCC_URL:-https://github.com/vf1/opencode-custom-provider/releases/download/files/commandcode.json}"
CONFIG=""

usage() {
  printf '%s\n' \
    "usage: install.sh [--config PATH]" \
    "" \
    "  Downloads models from the opencode-custom-provider release and" \
    "  adds/updates provider.\"command-code\" in an opencode config." \
    "  If the provider is missing, a full block (npm, name, options," \
    "  models) is created; otherwise only \"models\" is updated." \
    "  Default config: ~/.config/opencode/opencode.json" \
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
      echo "install.sh: unexpected argument: $1" >&2
      usage >&2
      exit 1
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
    if (k == key) { FVS = p; FVE = q; FKEY = i; return 1 }
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
function pad(n,   out) {
  out = ""
  while (n > 0) { out = out " "; n-- }
  return out
}
function indof(s, pos,   i, n) {
  i = pos
  while (i > 1 && substr(s, i - 1, 1) != "\n") i--
  n = 0
  while (substr(s, i + n, 1) == " ") n++
  return n
}
function fmt(s, i, j, ci,   c, out, p, q, k, first, end) {
  i = skipws(s, i)
  c = substr(s, i, 1)
  end = skipval(s, i) - 1
  if (c == "{") {
    p = skipws(s, i + 1)
    if (substr(s, p, 1) == "}") return "{}"
    out = "{"
    first = 1
    while (p < end) {
      p = skipws(s, p)
      if (substr(s, p, 1) == "}") break
      if (substr(s, p, 1) == ",") { p = skipws(s, p + 1); continue }
      q = skipstr(s, p)
      k = substr(s, p, q - p)
      p = skipws(s, q)
      p = skipws(s, p + 1)
      q = skipval(s, p)
      out = out (first ? "" : ",") "\n" pad(ci) k ": " fmt(s, p, q, ci + 2)
      first = 0
      p = q
    }
    return out "\n" pad(ci - 2) "}"
  }
  if (c == "[") {
    p = skipws(s, i + 1)
    if (substr(s, p, 1) == "]") return "[]"
    out = "["
    first = 1
    while (p < end) {
      p = skipws(s, p)
      if (substr(s, p, 1) == "]") break
      if (substr(s, p, 1) == ",") { p = skipws(s, p + 1); continue }
      q = skipval(s, p)
      out = out (first ? "" : ",") "\n" pad(ci) fmt(s, p, q, ci + 2)
      first = 0
      p = q
    }
    return out "\n" pad(ci - 2) "]"
  }
  return substr(s, i, j - i)
}
function cmdblock(ci,   out) {
  out = pad(ci) "\"command-code\": {\n"
  out = out pad(ci + 2) "\"npm\": \"@ai-sdk/openai-compatible\",\n"
  out = out pad(ci + 2) "\"name\": \"command-code\",\n"
  out = out pad(ci + 2) "\"options\": {\n"
  out = out pad(ci + 4) "\"baseURL\": \"https://api.commandcode.ai/provider/v1\"\n"
  out = out pad(ci + 2) "},\n"
  out = out pad(ci + 2) "\"models\": " fmt(models, 1, length(models) + 1, ci + 4)
  out = out "\n" pad(ci) "}"
  return out
}
function memind(s, opos,   p) {
  p = skipws(s, opos + 1)
  if (substr(s, p, 1) == "}") return indof(s, opos) + 2
  return indof(s, p)
}
function insert_add(s, opos, ins,   cpos, w, closei) {
  cpos = skipval(s, opos) - 1
  closei = indof(s, cpos)
  if (emptyobj(s, opos)) {
    return substr(s, 1, opos) "\n" ins "\n" pad(closei) substr(s, cpos)
  }
  w = cpos
  while (w > 1 && substr(s, w - 1, 1) ~ /[ \t\r\n]/) w--
  return substr(s, 1, w - 1) ",\n" ins "\n" pad(closei) substr(s, cpos)
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
  if (!findkey(s, 1, "provider") || !findkey(s, FVS, "command-code") || !findkey(s, FVS, "models")) {
    print "install.sh: provider \"command-code\" not found in downloaded file" > "/dev/stderr"
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
    ri = memind(cfg, root)
    ins = pad(ri) "\"provider\": {\n" cmdblock(ri + 2) "\n" pad(ri) "}"
    out = insert_add(cfg, root, ins)
    status = "created " n
  } else if (!findkey(cfg, FVS, "command-code")) {
    out = insert_add(cfg, FVS, cmdblock(memind(cfg, FVS)))
    status = "created " n
  } else {
    pobj = FVS
    if (findkey(cfg, pobj, "models")) {
      out = substr(cfg, 1, FVS - 1) fmt(models, 1, length(models) + 1, indof(cfg, FKEY) + 2) substr(cfg, FVE)
    } else {
      ci = memind(cfg, pobj)
      out = insert_add(cfg, pobj, pad(ci) "\"models\": " fmt(models, 1, length(models) + 1, ci + 2))
    }
    status = "updated " n
  }
  printf "%s", out > OUT
  close(OUT)
  print status
}
'

made_config=0
if [ ! -e "$CONFIG" ]; then
  mkdir -p "$(dirname "$CONFIG")"
  printf '%s\n' \
    '{' \
    '  "$schema": "https://opencode.ai/config.json",' \
    '  "provider": {}' \
    '}' > "$CONFIG"
  made_config=1
  echo "install.sh: created $CONFIG"
fi

status=$(awk -v NEWF="$NEW" -v CFGF="$CONFIG" -v OUT="$OUT" "$PROG")
if cmp -s "$OUT" "$CONFIG"; then
  rm -f "$OUT"
  echo "provider command-code: unchanged"
  echo "config: $CONFIG (no changes)"
else
  if [ "$made_config" -eq 0 ]; then
    cp "$CONFIG" "$CONFIG.bak"
  fi
  mv "$OUT" "$CONFIG"
  action=${status%% *}
  n=${status#* }
  echo "provider command-code: $action ($n models)"
  if [ "$made_config" -eq 1 ]; then
    echo "config: $CONFIG"
  else
    echo "config: $CONFIG (backup: $CONFIG.bak)"
  fi
fi
