#!/usr/bin/env bash
# perdita.sh
#
# Selectively copy or move files from a source directory to a destination,
# driven by an external list of filestems or full filenames.
# Works with any file type: fastq.gz, bam, txt, docx, etc.
#
# Usage:
#   ./perdita.sh --src <dir> --dest <dir> --file <file> \
#                --input-mode <filestems|filenames> \
#                [--suffixes <suffix1,suffix2,...>] \
#                [--move] [--recursive] [--force] [--dry-run]
#
# See README.md for full documentation.

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
SRC_DIR=""; DEST_DIR=""; INPUT_FILE=""; INPUT_MODE=""; MODE="copy"
SUFFIXES_RAW=""; RECURSIVE=false; FORCE=false; DRY_RUN=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)         SRC_DIR="$2";       shift 2 ;;
    --dest)        DEST_DIR="$2";      shift 2 ;;
    --file)        INPUT_FILE="$2";    shift 2 ;;
    --input-mode)  INPUT_MODE="$2";    shift 2 ;;
    --suffixes)    SUFFIXES_RAW="$2";  shift 2 ;;
    --move)        MODE="move";        shift ;;
    --copy)        MODE="copy";        shift ;;
    --recursive)   RECURSIVE=true;     shift ;;
    --force)       FORCE=true;         shift ;;
    --dry-run)     DRY_RUN=true;       shift ;;
    --*)           echo "ERROR: Unknown flag: $1" >&2; exit 1 ;;
    *)             POSITIONAL+=("$1"); shift ;;
  esac
done

# Fall back to positional if named flags not used
[[ -z "$SRC_DIR"    && ${#POSITIONAL[@]} -ge 1 ]] && SRC_DIR="${POSITIONAL[0]}"
[[ -z "$DEST_DIR"   && ${#POSITIONAL[@]} -ge 2 ]] && DEST_DIR="${POSITIONAL[1]}"
[[ -z "$INPUT_FILE" && ${#POSITIONAL[@]} -ge 3 ]] && INPUT_FILE="${POSITIONAL[2]}"

# ── Validate ──────────────────────────────────────────────────────────────────
[[ -z "$SRC_DIR"    ]] && { echo "ERROR: --src required"  >&2; exit 1; }
[[ -z "$DEST_DIR"   ]] && { echo "ERROR: --dest required" >&2; exit 1; }
[[ -z "$INPUT_FILE" ]] && { echo "ERROR: --file required" >&2; exit 1; }
[[ -z "$INPUT_MODE" ]] && { echo "ERROR: --input-mode required (filestems or filenames)" >&2; exit 1; }
[[ "$INPUT_MODE" != "filestems" && "$INPUT_MODE" != "filenames" ]] && {
  echo "ERROR: --input-mode must be 'filestems' or 'filenames'" >&2; exit 1
}
[[ ! -d "$SRC_DIR"    ]] && { echo "ERROR: src dir not found: $SRC_DIR"       >&2; exit 1; }
[[ ! -f "$INPUT_FILE" ]] && { echo "ERROR: input file not found: $INPUT_FILE" >&2; exit 1; }

# ── Same-directory guard ──────────────────────────────────────────────────────
mkdir -p "$DEST_DIR"
SRC_ABS=$(cd "$SRC_DIR"  && pwd -P)
DEST_ABS=$(cd "$DEST_DIR" && pwd -P)
[[ "$SRC_ABS" == "$DEST_ABS" ]] && {
  echo "ERROR: --src and --dest resolve to the same directory: $SRC_ABS" >&2
  exit 1
}

# ── Parse suffixes ────────────────────────────────────────────────────────────
# Default to paired-end FASTQ if not specified (only relevant in filestems mode).
[[ -z "$SUFFIXES_RAW" ]] && SUFFIXES_RAW="_R1.fastq.gz,_R2.fastq.gz"
IFS=',' read -ra SUFFIXES <<< "$SUFFIXES_RAW"

# ── Header ────────────────────────────────────────────────────────────────────
echo "Source:      $SRC_DIR"
echo "Destination: $DEST_DIR"
echo "Input file:  $INPUT_FILE"
echo "Input mode:  $INPUT_MODE"
echo "Action:      $MODE$([[ "$DRY_RUN" == true ]] && echo " (dry-run)")"
echo "Recursive:   $RECURSIVE"
echo "Force:       $FORCE"
[[ "$INPUT_MODE" == "filestems" ]] && echo "Suffixes:    ${SUFFIXES[*]}"
echo ""

# ── Helper: trim CR and surrounding whitespace ────────────────────────────────
clean_line() {
  local s="$1"
  s="${s%$'\r'}"                              # strip trailing CR (CRLF safety)
  s="${s#"${s%%[![:space:]]*}"}"              # strip leading whitespace
  s="${s%"${s##*[![:space:]]}"}"              # strip trailing whitespace
  printf '%s' "$s"
}

# ── Helper: find a file in src (flat or recursive) ────────────────────────────
# Always returns exit 0; caller checks for empty output. Without this, under
# `set -e` a non-zero return from find_file would propagate through
# `src=$(find_file …)` and abort the script before [MISSING] is reported.
find_file() {
  local filename="$1"
  if [[ "$RECURSIVE" == true ]]; then
    local matches
    mapfile -t matches < <(find "$SRC_DIR" -type f -name "$filename" 2>/dev/null)
    if (( ${#matches[@]} > 1 )); then
      echo "  [WARN] $filename found ${#matches[@]} times under $SRC_DIR; using ${matches[0]}" >&2
    fi
    [[ ${#matches[@]} -gt 0 ]] && echo "${matches[0]}"
  else
    local candidate="$SRC_DIR/$filename"
    [[ -f "$candidate" ]] && echo "$candidate"
  fi
  return 0
}

# ── Transfer ──────────────────────────────────────────────────────────────────
ok=0; missing=0; skipped=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(clean_line "$line")
  [[ -z "$line" || "$line" == \#* ]] && continue

  if [[ "$INPUT_MODE" == "filenames" ]]; then
    files=("$(basename "$line")")
  else
    files=()
    for suffix in "${SUFFIXES[@]}"; do
      files+=("${line}${suffix}")
    done
  fi

  for file in "${files[@]}"; do
    src=$(find_file "$file")

    if [[ -z "$src" ]]; then
      echo "  [MISSING] $file" >&2
      missing=$((missing + 1))
      continue
    fi

    dest="$DEST_DIR/$file"
    if [[ -e "$dest" && "$FORCE" != true ]]; then
      echo "  [SKIP exists] $file" >&2
      skipped=$((skipped + 1))
      continue
    fi

    # File size for output (best effort, portable).
    size=$(du -h "$src" 2>/dev/null | cut -f1)

    if [[ "$DRY_RUN" == true ]]; then
      echo "  [DRY-${MODE}] $file  (${size})"
    else
      if [[ "$MODE" == "move" ]]; then
        mv "$src" "$dest"
      else
        cp "$src" "$dest"
      fi
      echo "  [${MODE}] $file  (${size})"
    fi
    ok=$((ok + 1))
  done

done < "$INPUT_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────
# Capitalise first letter of MODE in a bash-3.2-compatible way (macOS default).
mode_cap="$(tr '[:lower:]' '[:upper:]' <<< "${MODE:0:1}")${MODE:1}"

echo ""
if [[ "$DRY_RUN" == true ]]; then
  echo "Done (dry-run). Would ${MODE}: $ok files. Missing: $missing. Skipped (exists): $skipped."
else
  echo "Done. ${mode_cap}: $ok files. Missing: $missing. Skipped (exists): $skipped."
fi

# Exit non-zero only if files were missing — skips on existing files are
# not treated as errors so partial reruns don't break pipelines.
[[ $missing -gt 0 ]] && exit 1 || exit 0
