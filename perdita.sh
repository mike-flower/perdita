#!/usr/bin/env bash
# perdita.sh
#
# Selectively copy or move files from a source directory to a destination,
# driven by an external list of file stems or full filenames.
# Works with any file type: fastq.gz, bam, txt, docx, etc.
#
# Usage:
#   bash perdita.sh --src <dir> --dest <dir> --file <file> \
#                        --input-mode <stems|files> \
#                        [--suffixes <suffix1,suffix2,...>] \
#                        [--move] [--recursive]
#
# --input-mode stems  : each line is a stem; --suffixes are appended to find files
# --input-mode files  : each line is a full filename, transferred one-for-one
# --suffixes          : comma-separated list of suffixes to append in stems mode
#                       (default: "_R1.fastq.gz,_R2.fastq.gz")
# --move              : move files instead of copying (default: copy)
# --recursive         : search subdirectories of --src for each file

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
SRC_DIR=""; DEST_DIR=""; INPUT_FILE=""; INPUT_MODE=""; MODE="copy"
SUFFIXES_RAW=""; RECURSIVE=false
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
    --recursive)   RECURSIVE=true;    shift ;;
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
[[ -z "$INPUT_MODE" ]] && { echo "ERROR: --input-mode required (stems or files)" >&2; exit 1; }
[[ "$INPUT_MODE" != "stems" && "$INPUT_MODE" != "files" ]] && {
  echo "ERROR: --input-mode must be 'stems' or 'files'" >&2; exit 1
}
[[ ! -d "$SRC_DIR"    ]] && { echo "ERROR: src dir not found: $SRC_DIR"       >&2; exit 1; }
[[ ! -f "$INPUT_FILE" ]] && { echo "ERROR: input file not found: $INPUT_FILE" >&2; exit 1; }

# ── Parse suffixes ────────────────────────────────────────────────────────────
# Default to paired-end FASTQ if not specified
[[ -z "$SUFFIXES_RAW" ]] && SUFFIXES_RAW="_R1.fastq.gz,_R2.fastq.gz"

IFS=',' read -ra SUFFIXES <<< "$SUFFIXES_RAW"

mkdir -p "$DEST_DIR"

echo "Source:      $SRC_DIR"
echo "Destination: $DEST_DIR"
echo "Input file:  $INPUT_FILE"
echo "Input mode:  $INPUT_MODE"
echo "Action:      $MODE"
echo "Recursive:   $RECURSIVE"
[[ "$INPUT_MODE" == "stems" ]] && echo "Suffixes:    ${SUFFIXES[*]}"
echo ""

# ── Helper: find a file in src (flat or recursive) ────────────────────────────
find_file() {
  local filename="$1"
  if [[ "$RECURSIVE" == true ]]; then
    find "$SRC_DIR" -type f -name "$filename" 2>/dev/null | head -1
  else
    local candidate="$SRC_DIR/$filename"
    [[ -f "$candidate" ]] && echo "$candidate"
  fi
}

# ── Transfer ──────────────────────────────────────────────────────────────────
ok=0; missing=0

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue   # skip blanks/comments

  if [[ "$INPUT_MODE" == "files" ]]; then
    files=("$(basename "$line")")
  else
    files=()
    for suffix in "${SUFFIXES[@]}"; do
      files+=("${line}${suffix}")
    done
  fi

  for file in "${files[@]}"; do
    src=$(find_file "$file")
    if [[ -n "$src" ]]; then
      if [[ "$MODE" == "move" ]]; then
        mv "$src" "$DEST_DIR/$file"
      else
        cp "$src" "$DEST_DIR/$file"
      fi
      echo "  [${MODE}] $file"
      (( ok++ )) || true
    else
      echo "  [MISSING] $file" >&2
      (( missing++ )) || true
    fi
  done

done < "$INPUT_FILE"

echo ""
echo "Done. ${MODE^}: $ok files. Missing: $missing."
[[ $missing -gt 0 ]] && exit 1 || exit 0
