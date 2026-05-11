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
#                [--anchors <chars>] \
#                [--move] [--recursive] [--dry-run] \
#                [--on-exists <skip|update|overwrite>] \
#                [--no-log] [--no-report]
#
# In filestems mode, when --suffixes is omitted the script runs in DISCOVER mode:
# for each filestem, it pulls every file in --src whose basename starts with
# that stem. Without --anchors, prefix collisions among filestems (e.g. S1 vs
# S10) are detected up-front and the script refuses to run. With --anchors,
# the filestem must be followed by one of the supplied characters (or be an
# exact match) for a file to count.
#
# Every run writes:
#   - a full transcript to <script_dir>/logs/perdita_<timestamp>.log
#   - a TSV per-file report to <dest>/perdita_report_<timestamp>.tsv
#   - a human-readable summary to <dest>/perdita_summary_<timestamp>.txt

set -euo pipefail

# ── Resolve script directory (for logs/) ──────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# ── Argument parsing ──────────────────────────────────────────────────────────
SRC_DIR=""; DEST_DIR=""; INPUT_FILE=""; INPUT_MODE=""; MODE="copy"
SUFFIXES_RAW=""; RECURSIVE=false; DRY_RUN=false
ANCHORS=""
ON_EXISTS="update"
NO_LOG=false; NO_REPORT=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)         SRC_DIR="$2";       shift 2 ;;
    --dest)        DEST_DIR="$2";      shift 2 ;;
    --file)        INPUT_FILE="$2";    shift 2 ;;
    --input-mode)  INPUT_MODE="$2";    shift 2 ;;
    --suffixes)    SUFFIXES_RAW="$2";  shift 2 ;;
    --anchors)     ANCHORS="$2";       shift 2 ;;
    --move)        MODE="move";        shift ;;
    --copy)        MODE="copy";        shift ;;
    --recursive)   RECURSIVE=true;     shift ;;
    --on-exists)   ON_EXISTS="$2";     shift 2 ;;
    --dry-run)     DRY_RUN=true;       shift ;;
    --no-log)      NO_LOG=true;        shift ;;
    --no-report)   NO_REPORT=true;     shift ;;
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
[[ "$ON_EXISTS" != "skip" && "$ON_EXISTS" != "update" && "$ON_EXISTS" != "overwrite" ]] && {
  echo "ERROR: --on-exists must be 'skip', 'update', or 'overwrite' (got: '$ON_EXISTS')" >&2; exit 1
}
[[ -n "$ANCHORS" && "$INPUT_MODE" != "filestems" ]] && {
  echo "ERROR: --anchors only makes sense with --input-mode filestems" >&2; exit 1
}
[[ -n "$ANCHORS" && -n "$SUFFIXES_RAW" ]] && {
  echo "ERROR: --anchors and --suffixes are mutually exclusive — suffixes already define what to match" >&2; exit 1
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

# ── Set up logging ────────────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
LOG_FILE=""
if [[ "$NO_LOG" != true ]]; then
  LOG_DIR="$SCRIPT_DIR/logs"
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/perdita_$TIMESTAMP.log"
  exec > >(tee -a "$LOG_FILE")
  exec 2> >(tee -a "$LOG_FILE" >&2)
fi

# ── Decide on suffixes / discover mode ────────────────────────────────────────
DISCOVER_MODE=false
SUFFIXES=()
if [[ -n "$SUFFIXES_RAW" ]]; then
  IFS=',' read -ra SUFFIXES <<< "$SUFFIXES_RAW"
elif [[ "$INPUT_MODE" == "filestems" ]]; then
  DISCOVER_MODE=true
fi

# ── Header ────────────────────────────────────────────────────────────────────
echo "Source:      $SRC_DIR"
echo "Destination: $DEST_DIR"
echo "Input file:  $INPUT_FILE"
echo "Input mode:  $INPUT_MODE"
echo "Action:      $MODE$([[ "$DRY_RUN" == true ]] && echo " (dry-run)")"
echo "Recursive:   $RECURSIVE"
echo "On exists:   $ON_EXISTS"
if [[ "$INPUT_MODE" == "filestems" ]]; then
  if [[ "$DISCOVER_MODE" == true ]]; then
    if [[ -n "$ANCHORS" ]]; then
      echo "Match:       discover, anchored on [$ANCHORS]"
    else
      echo "Match:       discover, unanchored"
    fi
  else
    echo "Suffixes:    ${SUFFIXES[*]}"
  fi
fi
[[ -n "$LOG_FILE" ]] && echo "Log file:    $LOG_FILE"
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────
clean_line() {
  local s="$1"
  s="${s%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Portable file size in bytes via wc -c.
file_size_bytes() {
  wc -c < "$1" | tr -d ' '
}

# Look up an exact filename in --src. Always returns 0.
find_file() {
  local filename="$1"
  if [[ "$RECURSIVE" == true ]]; then
    local first=""; local count=0; local match=""
    while IFS= read -r match; do
      count=$((count + 1))
      [[ -z "$first" ]] && first="$match"
    done < <(find "$SRC_DIR" -type f -name "$filename" 2>/dev/null)
    if (( count > 1 )); then
      echo "  [WARN] $filename found $count times under $SRC_DIR; using $first" >&2
    fi
    [[ -n "$first" ]] && echo "$first"
  else
    local candidate="$SRC_DIR/$filename"
    [[ -f "$candidate" ]] && echo "$candidate"
  fi
  return 0
}

# Discover all files in --src whose basename matches the filestem under the
# active anchoring rule. Returns one path per line, exit 0 even if no matches.
discover_files() {
  local stem="$1"
  local matches=()

  if [[ "$RECURSIVE" == true ]]; then
    local m=""
    while IFS= read -r m; do
      matches+=("$m")
    done < <(find "$SRC_DIR" -type f -name "${stem}*" 2>/dev/null)
  else
    local f
    for f in "$SRC_DIR"/"${stem}"*; do
      [[ -f "$f" ]] && matches+=("$f")
    done
  fi

  # Apply anchor filter when --anchors is set.
  if [[ -n "$ANCHORS" ]]; then
    local kept=()
    local f base rest first_char
    for f in ${matches[@]+"${matches[@]}"}; do
      base=$(basename "$f")
      if [[ "$base" == "$stem" ]]; then
        kept+=("$f")
        continue
      fi
      rest="${base#"$stem"}"
      first_char="${rest:0:1}"
      if [[ -n "$first_char" && "$ANCHORS" == *"$first_char"* ]]; then
        kept+=("$f")
      fi
    done
    matches=( ${kept[@]+"${kept[@]}"} )
  fi

  for m in ${matches[@]+"${matches[@]}"}; do
    echo "$m"
  done
  return 0
}

# ── Read input ────────────────────────────────────────────────────────────────
RAW_ENTRIES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(clean_line "$line")
  [[ -z "$line" || "$line" == \#* ]] && continue
  RAW_ENTRIES+=("$line")
done < "$INPUT_FILE"

entries_total=${#RAW_ENTRIES[@]}
entries_unique=0
if (( entries_total > 0 )); then
  entries_unique=$(printf '%s\n' "${RAW_ENTRIES[@]}" | LC_ALL=C sort -u | wc -l | tr -d ' ')
fi
duplicates=$((entries_total - entries_unique))

# ── Pre-flight check (unanchored discover mode only) ──────────────────────────
# Reject runs where one filestem is a prefix of another (e.g. S1 vs S10) under
# unanchored discovery — they'd silently scoop each other's files.
if [[ "$DISCOVER_MODE" == true && -z "$ANCHORS" && $entries_unique -gt 1 ]]; then
  preflight_sorted=$(printf '%s\n' "${RAW_ENTRIES[@]}" | LC_ALL=C sort -u)
  preflight_prev=""
  preflight_collisions=0
  while IFS= read -r s; do
    if [[ -n "$preflight_prev" && "$s" == "$preflight_prev"* && "$s" != "$preflight_prev" ]]; then
      echo "  [PREFIX COLLISION] '$preflight_prev' is a prefix of '$s'" >&2
      preflight_collisions=$((preflight_collisions + 1))
    fi
    preflight_prev="$s"
  done <<< "$preflight_sorted"
  if (( preflight_collisions > 0 )); then
    echo "" >&2
    echo "ERROR: $preflight_collisions filestem prefix collision(s) detected." >&2
    echo "Without --anchors, an unanchored prefix match would scoop one stem's files into another." >&2
    echo "Resolve by:" >&2
    echo "  - Adding --anchors \"_.\" (or similar) to require a separator after the stem, or" >&2
    echo "  - Adding --suffixes to enumerate explicit suffixes, or" >&2
    echo "  - Renaming filestems so none is a prefix of another." >&2
    exit 1
  fi
fi

# ── Transfer ──────────────────────────────────────────────────────────────────
copied_count=0
updated_count=0
matched_count=0
skipped_count=0
missing_count=0
stem_no_match_count=0   # filestems that yielded zero matches under discover mode

REPORT_ROWS=()           # final per-file rows: filestem \t status \t filename \t src \t size
REPORT_MISSING_STEMS=()  # stems with zero matches (discover mode)
STEM_COUNTS=()           # parallel array: "stem<TAB>count" for the summary

# Process one (filestem, file, src) triple and append to REPORT_ROWS.
# Updates the *_count globals.
process_one_file() {
  local filestem="$1" file="$2" src="$3"

  if [[ -z "$src" ]]; then
    echo "  [MISSING] $file" >&2
    missing_count=$((missing_count + 1))
    REPORT_ROWS+=("$filestem"$'\t'"missing"$'\t'"$file"$'\t'-$'\t'-)
    return
  fi

  local dest="$DEST_DIR/$file"
  local prior_exists=false
  [[ -e "$dest" ]] && prior_exists=true

  local action_present="" action_past=""
  if [[ "$prior_exists" == true ]]; then
    case "$ON_EXISTS" in
      skip)
        echo "  [SKIP exists] $file" >&2
        skipped_count=$((skipped_count + 1))
        REPORT_ROWS+=("$filestem"$'\t'"skipped"$'\t'"$file"$'\t'"$src"$'\t'-)
        return
        ;;
      update)
        if [[ "$(file_size_bytes "$src")" == "$(file_size_bytes "$dest")" ]]; then
          echo "  [match] $file" >&2
          matched_count=$((matched_count + 1))
          REPORT_ROWS+=("$filestem"$'\t'"matched"$'\t'"$file"$'\t'"$src"$'\t'-)
          return
        fi
        action_present="update"; action_past="updated"
        ;;
      overwrite)
        action_present="update"; action_past="updated"
        ;;
    esac
  else
    if [[ "$MODE" == "copy" ]]; then
      action_present="copy"; action_past="copied"
    else
      action_present="move"; action_past="moved"
    fi
  fi

  local size
  size=$(du -h "$src" 2>/dev/null | cut -f1)
  local status
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DRY-${action_present}] $file  (${size})"
    status="would-${action_present}"
  else
    if [[ "$MODE" == "move" ]]; then
      mv "$src" "$dest"
    else
      cp "$src" "$dest"
    fi
    echo "  [${action_present}] $file  (${size})"
    status="$action_past"
  fi

  if [[ "$action_present" == "update" ]]; then
    updated_count=$((updated_count + 1))
  else
    copied_count=$((copied_count + 1))
  fi
  REPORT_ROWS+=("$filestem"$'\t'"$status"$'\t'"$file"$'\t'"$src"$'\t'"$size")
}

for line in ${RAW_ENTRIES[@]+"${RAW_ENTRIES[@]}"}; do

  files_for_this_stem=0

  if [[ "$INPUT_MODE" == "filenames" ]]; then
    file=$(basename "$line")
    src=$(find_file "$file")
    process_one_file "-" "$file" "$src"
    # filenames mode: stem-counts section not emitted

  elif [[ "$DISCOVER_MODE" == true ]]; then
    discovered=$(discover_files "$line")
    if [[ -z "$discovered" ]]; then
      echo "  [NO MATCH] filestem '$line' matched zero files in --src" >&2
      stem_no_match_count=$((stem_no_match_count + 1))
      REPORT_MISSING_STEMS+=("$line")
      REPORT_ROWS+=("$line"$'\t'"no-match"$'\t'-$'\t'-$'\t'-)
    else
      while IFS= read -r src; do
        file=$(basename "$src")
        process_one_file "$line" "$file" "$src"
        files_for_this_stem=$((files_for_this_stem + 1))
      done <<< "$discovered"
    fi
    STEM_COUNTS+=("$line"$'\t'"$files_for_this_stem")

  else
    # filestems mode with --suffixes (whitelist)
    for suffix in "${SUFFIXES[@]}"; do
      file="${line}${suffix}"
      src=$(find_file "$file")
      process_one_file "$line" "$file" "$src"
      [[ -n "$src" ]] && files_for_this_stem=$((files_for_this_stem + 1))
    done
    STEM_COUNTS+=("$line"$'\t'"$files_for_this_stem")
  fi
done

# ── Summary line to terminal ──────────────────────────────────────────────────
mode_cap="$(tr '[:lower:]' '[:upper:]' <<< "${MODE:0:1}")${MODE:1}"

echo ""
if [[ "$DRY_RUN" == true ]]; then
  printf "Done (dry-run). Would %s: %d. Would update: %d. Matched: %d. Skipped: %d. Missing: %d." \
    "$MODE" "$copied_count" "$updated_count" "$matched_count" "$skipped_count" "$missing_count"
else
  printf "Done. %s: %d. Updated: %d. Matched: %d. Skipped: %d. Missing: %d." \
    "$mode_cap" "$copied_count" "$updated_count" "$matched_count" "$skipped_count" "$missing_count"
fi
if [[ "$DISCOVER_MODE" == true ]]; then
  printf " Stems with no match: %d." "$stem_no_match_count"
fi
printf "\n"

# ── Write report (TSV) and summary (plain text) ───────────────────────────────
REPORT_FILE=""
SUMMARY_FILE=""
if [[ "$NO_REPORT" != true ]]; then
  REPORT_FILE="$DEST_DIR/perdita_report_$TIMESTAMP.tsv"
  {
    echo "# Perdita per-file report"
    echo "# Generated:   $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "# Source:      $SRC_DIR"
    echo "# Destination: $DEST_DIR"
    echo "# Input file:  $INPUT_FILE"
    echo "# Input mode:  $INPUT_MODE"
    if [[ "$DRY_RUN" == true ]]; then
      echo "# Action:      $MODE (dry-run)"
    else
      echo "# Action:      $MODE"
    fi
    echo "# Recursive:   $RECURSIVE"
    echo "# On exists:   $ON_EXISTS"
    if [[ "$INPUT_MODE" == "filestems" ]]; then
      if [[ "$DISCOVER_MODE" == true ]]; then
        if [[ -n "$ANCHORS" ]]; then
          echo "# Match:       discover, anchored on [$ANCHORS]"
        else
          echo "# Match:       discover, unanchored"
        fi
      else
        echo "# Suffixes:    ${SUFFIXES[*]}"
      fi
    fi
    [[ -n "$LOG_FILE" ]] && echo "# Log file:    $LOG_FILE"
    echo "#"
    printf "filestem\tstatus\tfilename\tsource_path\tsize\n"
    for row in ${REPORT_ROWS[@]+"${REPORT_ROWS[@]}"}; do
      printf "%s\n" "$row"
    done
  } > "$REPORT_FILE"

  SUMMARY_FILE="$DEST_DIR/perdita_summary_$TIMESTAMP.txt"
  {
    echo "Perdita transfer summary"
    echo "========================"
    echo ""
    echo "Generated:    $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
    echo "Run parameters"
    echo "--------------"
    echo "Source:       $SRC_DIR"
    echo "Destination:  $DEST_DIR"
    echo "Input file:   $INPUT_FILE"
    echo "Input mode:   $INPUT_MODE"
    if [[ "$DRY_RUN" == true ]]; then
      echo "Action:       $MODE (dry-run)"
    else
      echo "Action:       $MODE"
    fi
    echo "Recursive:    $RECURSIVE"
    echo "On exists:    $ON_EXISTS"
    if [[ "$INPUT_MODE" == "filestems" ]]; then
      if [[ "$DISCOVER_MODE" == true ]]; then
        if [[ -n "$ANCHORS" ]]; then
          echo "Match:        discover, anchored on [$ANCHORS]"
        else
          echo "Match:        discover, unanchored"
        fi
      else
        echo "Suffixes:     ${SUFFIXES[*]}"
      fi
    fi
    echo ""
    echo "Input"
    echo "-----"
    printf "Entries in input file:   %d\n" "$entries_total"
    printf "Unique entries:          %d" "$entries_unique"
    if (( duplicates > 0 )); then
      printf " (with %d duplicate%s)\n" "$duplicates" "$([[ $duplicates -eq 1 ]] && echo "" || echo "s")"
    else
      printf "\n"
    fi
    echo ""
    echo "Outcomes (per file)"
    echo "-------------------"
    if [[ "$DRY_RUN" == true ]]; then
      printf "  Would %s (new):       %d\n" "$MODE" "$copied_count"
      printf "  Would update (differ):    %d\n" "$updated_count"
    else
      printf "  %s (new):             %d\n" "$mode_cap" "$copied_count"
      printf "  Updated (differ):         %d\n" "$updated_count"
    fi
    printf "  Matched (same size):      %d\n" "$matched_count"
    printf "  Skipped (exists):         %d\n" "$skipped_count"
    printf "  Missing:                  %d\n" "$missing_count"
    if [[ "$DISCOVER_MODE" == true ]]; then
      printf "  Stems with no match:      %d\n" "$stem_no_match_count"
    fi
    echo ""

    # Per-filestem file counts (filestems mode only)
    if [[ "$INPUT_MODE" == "filestems" ]]; then
      echo "Files pulled per filestem"
      echo "-------------------------"
      if (( ${#REPORT_MISSING_STEMS[@]} > 0 )); then
        echo "Filestems with no matches:"
        for s in "${REPORT_MISSING_STEMS[@]}"; do
          printf "  %s\n" "$s"
        done
        echo ""
      fi
      echo "Per-stem counts:"
      for row in ${STEM_COUNTS[@]+"${STEM_COUNTS[@]}"}; do
        stem="${row%%$'\t'*}"
        count="${row##*$'\t'}"
        printf "  %s: %d\n" "$stem" "$count"
      done
      echo ""
    fi

    echo "Artefacts"
    echo "---------"
    [[ -n "$LOG_FILE"    ]] && echo "Log file:     $LOG_FILE"
    [[ -n "$REPORT_FILE" ]] && echo "TSV report:   $REPORT_FILE"
    echo ""
    if (( missing_count > 0 || stem_no_match_count > 0 )); then
      echo "Exit code:    1  (some files / filestems unresolved — see report for details)"
    else
      echo "Exit code:    0"
    fi
  } > "$SUMMARY_FILE"

  echo "Report:      $REPORT_FILE"
  echo "Summary:     $SUMMARY_FILE"
fi

# Exit non-zero if anything was unresolved.
if (( missing_count > 0 || stem_no_match_count > 0 )); then
  exit 1
fi
exit 0
