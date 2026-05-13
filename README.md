# Perdita

Copy or move a defined subset of files from one directory to another, driven by a list you provide.

---

## Background

Genomics workflows (and many others) routinely produce many files in a single directory. When you need to pull out a defined subset — a cohort, a batch, a set of controls — `rsync` is heavyweight, `find` is awkward, and `cp` doesn't take a list.

Perdita does one thing well: you point it at a source directory, a destination directory, and a text file listing what you want, and it transfers exactly those files. The list can be either:

- **`filestems`** — one line per *sample*. By default perdita pulls every file in the source whose name starts with that stem; supply `--suffixes` to restrict to specific patterns.
- **`filenames`** — one line per *file*, transferred literally.

Works with any file type — `.fastq.gz`, `.bam`, `.txt`, `.docx`, and so on. It also handles common operational needs: dry-run preview, configurable behaviour when destination files already exist (skip, size-aware update, or overwrite), `--move` instead of copy, recursive search across subdirectories, and CRLF-safe input parsing.

> **Try it:** clone the repo and run `bash demo/demo.sh` from the repo root to see perdita transfer a small included dataset.

---

## Installation

1. Download `perdita.sh` and place it somewhere on your system, e.g. `~/my_bin/`
2. Make it executable:
```bash
chmod +x ~/my_bin/perdita.sh
```
3. Optionally add it to your PATH so you can call it from anywhere. Add this line to `~/.zshrc`:
```bash
export PATH="$HOME/my_bin:$PATH"
```
Then reload your shell:
```bash
source ~/.zshrc
```

---

## Quick run

The included demo runs from the repo root:

```bash
./perdita.sh \
  --src demo/fastq \
  --dest demo/result \
  --file demo/demo_filestems.txt \
  --input-mode filestems
```

This transfers every file in `demo/fastq/` whose name starts with one of the filestems in `demo/demo_filestems.txt`. The destination directory is created automatically if it doesn't exist.

---

## What the output looks like

```
Source:      demo/fastq
Destination: demo/result
Input file:  demo/demo_filestems.txt
Input mode:  filestems
Action:      copy
Recursive:   false
On exists:   update
Match:       discover, unanchored
Log file:    /path/to/perdita/logs/perdita_20260511T143215.log

  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R1.fastq.gz  (2.1M)
  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R2.fastq.gz  (2.3M)
  [copy] DMPX_MS408-N702-A-S506-A_S38_L001_R1.fastq.gz  (1.9M)
  [copy] DMPX_MS408-N702-A-S506-A_S38_L001_R2.fastq.gz  (2.0M)

Done. Copy: 4. Updated: 0. Matched: 0. Skipped: 0. Missing: 0. Stems with no match: 0.
Report:      demo/result/reports/perdita_report_20260511T143215.tsv
Summary:     demo/result/reports/perdita_summary_20260511T143215.txt
```

Each line in the body shows what happened to one file. Every run also writes a log file alongside the script and two artefacts into the destination directory — see [Logs, reports and summaries](#logs-reports-and-summaries) below.

The tags that can appear:

| Tag | Meaning | Stream |
|-----|---------|--------|
| `[copy]` / `[move]` | New file written to dest | stdout |
| `[update]` | Existing dest file overwritten (under `--on-exists update` or `overwrite`) | stdout |
| `[DRY-copy]` / `[DRY-move]` / `[DRY-update]` | What would happen under `--dry-run` | stdout |
| `[match]` | Under `--on-exists update`: dest file already matches src size, skipped | stderr |
| `[SKIP exists]` | Under `--on-exists skip`: dest file already exists, no comparison done | stderr |
| `[MISSING]` | File not found in `--src` (filenames mode, or filestems with `--suffixes`) | stderr |
| `[NO MATCH]` | Filestem matched zero files in `--src` (discover mode) | stderr |
| `[WARN]` | `--recursive` found the same filename at multiple paths under `--src`; the lexicographically first path is used and the rest are dropped (status `duplicate-ignored` in the TSV). Sizes are shown for every candidate so any mismatch is visible. | stderr |
| `[PREFIX COLLISION]` | Pre-flight detected one filestem is a prefix of another — script will refuse to run | stderr |

The split between stdout and stderr lets you redirect transfer logs and error messages independently:

```bash
./perdita.sh ... > transfers.log 2> errors.log
```

The script exits with code `0` if everything resolved cleanly, or `1` if any files were missing or any filestems matched zero files.

---

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `--src` | Yes | Directory containing the source files |
| `--dest` | Yes | Destination directory (created if it doesn't exist) |
| `--file` | Yes | Path to your input list (filestems or filenames) |
| `--input-mode` | Yes | `filestems` or `filenames` |
| `--suffixes` | No | Filestems mode only. Comma-separated suffixes restricting which files match (whitelist). If omitted, perdita runs in discover mode and pulls everything matching the stem. |
| `--anchors` | No | Filestems mode only. Characters that must follow the stem for a file to count as a match (e.g. `"_."`). Use this to disambiguate stems like `S1` vs `S10`. Mutually exclusive with `--suffixes`. |
| `--move` | No | Move files instead of copying (default: copy) |
| `--recursive` | No | Search subdirectories of `--src` for each file |
| `--on-exists` | No | How to handle files that already exist in `--dest`: `skip`, `update` (default), or `overwrite`. See [How perdita handles existing files](#how-perdita-handles-existing-files-in---dest) below. |
| `--dry-run` | No | Show what would happen without transferring anything |
| `--no-log` | No | Don't write a log file for this run |
| `--no-report` | No | Don't write the TSV report or text summary |

---

## Choosing between filestems and filenames

The two modes solve different problems. Use this table to decide which fits your situation; the detailed sections below explain how each works.

| Question | Answer |
|----------|--------|
| All my files share predictable stems (sample IDs, run IDs, etc.)? | **`filestems`** |
| I want to list each sample once and pull everything for it? | **`filestems`** |
| My filenames don't share a pattern, or I'm mixing arbitrary types? | **`filenames`** |
| I already have an explicit list of complete filenames? | **`filenames`** |

---

## How filestems mode works

When you run perdita in filestems mode, each line of your input file is a filestem — a shared name fragment that identifies a group of related files. How perdita turns those filestems into actual filenames depends on which flags you supply:

### Default: discover mode

With **no** `--suffixes` and **no** `--anchors`, perdita pulls every file in `--src` whose basename starts with the filestem. This is the most general behaviour and is usually what you want for sample-based bioinformatics workflows.

Input file (`filestems.txt`):
```
sample_A
sample_B
```

Source directory:
```
sample_A_R1.fastq.gz
sample_A_R2.fastq.gz
sample_A.bam
sample_A.bam.bai
sample_B_R1.fastq.gz
sample_B_R2.fastq.gz
sample_B.ccs_report.txt
```

Run:
```bash
./perdita.sh --src /data --dest /subset --file filestems.txt --input-mode filestems
```

All seven files are transferred, four attributed to `sample_A` and three to `sample_B`. The per-stem counts appear in the summary file.

### Safety: prefix-collision pre-flight

Discover mode has one known failure mode: if one filestem is a prefix of another (e.g. `S1` and `S10`), unanchored matching for `S1` would scoop up `S10`'s files too. Perdita detects this before transferring anything and refuses to run:

```
  [PREFIX COLLISION] 'S1' is a prefix of 'S10'

ERROR: 1 filestem prefix collision(s) detected.
Without --anchors, an unanchored prefix match would scoop one stem's files into another.
Resolve by:
  - Adding --anchors "_." (or similar) to require a separator after the stem, or
  - Adding --suffixes to enumerate explicit suffixes, or
  - Renaming filestems so none is a prefix of another.
```

For long, unique sample identifiers (e.g. `DMPX_MS408-N702-A-S505-A_S26_L001`) this almost never fires. For sequential numbering schemes (`S1`, `S2`, …, `S10`, `S11`) it's a real risk and the script catches it for you.

### Anchored discover mode

Add `--anchors "<chars>"` to require that the filestem be followed by one of the given characters (or be an exact match) for a file to count. Each character in the value is treated as a valid anchor.

```bash
./perdita.sh --src /data --dest /subset --file filestems.txt \
             --input-mode filestems --anchors "_."
```

With `--anchors "_."`:

| Filestem | File | Match? |
|----------|------|--------|
| `sample_A` | `sample_A_R1.fastq.gz` | ✓ (`_` separator) |
| `sample_A` | `sample_A.bam` | ✓ (`.` separator) |
| `sample_A` | `sample_A.bam.bai` | ✓ |
| `sample_A` | `sample_A` | ✓ (exact) |
| `S1` | `S10_R1.fastq.gz` | ✗ (`0` is not in `_.`) |
| `sample_A` | `sample_Aprocessed.bam` | ✗ |

Common anchor sets:

- `"_."` — covers almost all standard bioinformatics naming (e.g. `sample_R1.fastq.gz`, `sample.bam`)
- `"_.-"` — also allows hyphen for names like `sample-A-R1.fastq.gz`
- `"_"` — strict, only underscore

### Whitelist mode: `--suffixes`

To restrict transfers to specific patterns, supply `--suffixes`. Each line is then a filestem, and perdita constructs exact filenames by appending each suffix:

```bash
./perdita.sh --src /data --dest /subset --file filestems.txt \
             --input-mode filestems \
             --suffixes "_R1.fastq.gz,_R2.fastq.gz"
```

Input file:
```
sample_A
sample_B
```

Files transferred (and only these):
```
sample_A_R1.fastq.gz
sample_A_R2.fastq.gz
sample_B_R1.fastq.gz
sample_B_R2.fastq.gz
```

`sample_A.bam`, `sample_B.ccs_report.txt` etc. are left behind. This is the strictest mode — use it when you know exactly which file types you want and the source directory contains extras you don't want to transfer.

Other useful suffix sets:

- `"_R1.fastq.gz,_R2.fastq.gz"` — paired-end FASTQ
- `".bam,.bam.bai"` — BAM + index
- `".vcf.gz,.vcf.gz.tbi"` — VCF + index

---

## Filenames mode

In filenames mode, each line is a **literal, complete filename** transferred as-is. Any leading path is stripped — only the basename is used.

Use this when:
- Your filenames don't follow any regular pattern
- You want to mix file types in a single transfer
- You already have a manifest of exact filenames from somewhere else

Input file (`filenames.txt`):
```
sample_A_R1.fastq.gz
QC_report.html
metadata.docx
alignment.bam
```

Run:
```bash
./perdita.sh --src /data --dest /subset --file filenames.txt --input-mode filenames
```

All four files are transferred exactly as named.

---

## How perdita handles existing files in `--dest`

The `--on-exists` flag controls what happens when the destination already has a file with the same name as one perdita is about to transfer:

| Scenario | `--on-exists skip` | `--on-exists update` (default) | `--on-exists overwrite` |
|----------|--------------------|--------------------------------|-------------------------|
| Dest file doesn't exist | Transfer (`copied`/`moved`) | Transfer (`copied`/`moved`) | Transfer (`copied`/`moved`) |
| Dest file exists, **same size** as src | Skip (`skipped`) | Skip (`matched`) | Overwrite (`updated`) |
| Dest file exists, **different size** from src | Skip (`skipped`) | Overwrite (`updated`) | Overwrite (`updated`) |

When to pick which:

- **`update`** — default. Re-runs against the same destination are idempotent: matching files are left alone, files that have changed in the source get overwritten. The size comparison is fast (no content read), and the matched/updated counts let you see exactly what changed between runs. This is the rsync-style behaviour for typical use.
- **`skip`** — leaves dest files completely untouched, even if they differ from source. Useful when dest contains files you've manually edited or curated and you only want perdita to fill in what's missing.
- **`overwrite`** — overwrites everything in dest regardless of state. Use only when you genuinely want a clean replacement, for example restoring a corrupted output directory from a known-good source.

---

## Handling duplicate source paths under `--recursive`

When you run with `--recursive`, perdita walks every subdirectory of `--src` looking for matches. If the same filename appears at more than one path under that tree, perdita keeps a single copy and drops the rest. The picking rule is **lexicographically first full path wins** – a deterministic alphabetical order, not whatever the filesystem happens to return first.

For each set of duplicates perdita prints a `[WARN]` block listing every candidate path with its size:

```
  [WARN] sample_A_R1.fastq.gz found 2 times under --src; SIZES DIFFER – using first by sort order
         [USED]    /data/runs/run01/sample_A_R1.fastq.gz (1.4G, 1503948732 bytes)
         [ignored] /data/runs/run02/sample_A_R1.fastq.gz (1.2G, 1289334210 bytes)
  [copy] sample_A_R1.fastq.gz  (1.4G)
```

The dropped paths are also written to the TSV with status `duplicate-ignored` so the audit trail is complete – you can later see exactly which path was chosen and which were rejected. Sizes match the rounded `du -h` format in the size column; the warning text includes exact byte counts whenever the duplicates actually differ in size, so a real disagreement between two copies is unambiguous regardless of file scale.

The summary file's "Outcomes" section gains a `Source duplicates ignored: N` line, and the terminal's `Done.` line appends the same count whenever it's non-zero.

Deduplication operates on the basename (the full filename), not on the filestem. Different files sharing a stem – for example `..._R1.fastq.gz` and `..._R2.fastq.gz` for the same stem – are different basenames and both stay. Only exact-filename collisions are consolidated.

---

## Input file format

Both filestems and filenames modes share the same file format conventions:

- One entry per line
- Lines beginning with `#` are comments and are ignored
- Blank lines are ignored
- Leading and trailing whitespace is stripped automatically
- Windows line endings (CRLF) are handled automatically — you can edit input files in Excel or on Windows without breaking lookups

Example with comments and grouping:
```
# Cohort A samples
sample_A
sample_B

# Cohort B samples
sample_C
sample_D
```

For longer worked examples, see `www/example_filestems.txt` and `www/example_filenames.txt`.

Duplicate entries are tolerated: the script processes each line and reports the duplicate count in the summary so you know.

---

## Safety features

- **Prefix-collision pre-flight.** In unanchored discover mode, perdita refuses to run if any filestem is a prefix of another, naming the offending pair(s) and pointing at the fix.
- **Size-aware updates by default.** With `--on-exists update` (the default), files in `--dest` that already match the source by size are left alone.
- **Mutually exclusive matching flags.** `--anchors` and `--suffixes` can't both be set — they encode conflicting intents for how to match files.
- **Same-directory guard.** If `--src` and `--dest` resolve to the same directory, the script exits with an error before doing anything.
- **Dry-run mode.** `--dry-run` shows exactly what would be transferred without touching any files. Recommended before any `--move` operation.
- **Deterministic deduplication in recursive mode.** When `--recursive` finds the same filename at multiple paths under `--src`, perdita keeps the lexicographically first path and drops the rest with a `[WARN]` listing every candidate and its size. Dropped paths are also written to the TSV with status `duplicate-ignored`, so you can audit exactly which copy was used. When the duplicates differ in size, the warning highlights that explicitly and includes byte counts.

---

## Logs, reports and summaries

Every run leaves three artefacts behind so you can audit what happened. The report and summary go into a `reports/` subdirectory inside `--dest` so they don't clutter the directory of transferred files.

**1. A full log** at `<script_dir>/logs/perdita_<timestamp>.log` capturing the complete transcript — header, every per-file line, warnings, missing files, and the summary. Disable with `--no-log`.

**2. A TSV per-file report** at `<dest>/reports/perdita_report_<timestamp>.tsv`. Header records the invocation; body is one row per file with columns `filestem`, `status`, `filename`, `source_path`, `size`. The `status` column is one of `copied`, `moved`, `updated`, `matched`, `skipped`, `missing`, `no-match`, or `duplicate-ignored` (with `would-` prefixes under `--dry-run`). The `filestem` column shows which input line pulled each file – `-` in filenames mode, and `-` for `duplicate-ignored` rows arising in filenames mode. Easy to grep:

```bash
# List every file pulled in by a particular sample
awk -F'\t' '$1=="sample_A"{print $3}' reports/perdita_report_*.tsv

# Filestems that came back empty
awk -F'\t' '$2=="no-match"{print $1}' reports/perdita_report_*.tsv

# Source paths that were dropped because a duplicate basename won out
awk -F'\t' '$2=="duplicate-ignored"{print $3"\t"$4}' reports/perdita_report_*.tsv
```

**3. A human-readable summary** at `<dest>/reports/perdita_summary_<timestamp>.txt`:

```
Perdita transfer summary
========================

Generated:    2026-05-11 14:32:15 UTC

Run parameters
--------------
Source:       /data/demultiplex
Destination:  /analysis/2026.05.11_msn/bam
Input file:   /analysis/2026.05.11_msn/filestems.txt
Input mode:   filestems
Action:       copy
Recursive:    true
On exists:    update
Match:        discover, anchored on [_.]

Input
-----
Entries in input file:   12
Unique entries:          12

Outcomes (per file)
-------------------
  Copy (new):             87
  Updated (differ):       0
  Matched (same size):    0
  Skipped (exists):       0
  Missing:                0
  Stems with no match:    1
  Source duplicates ignored: 0

Files pulled per filestem
-------------------------
Filestems with no matches:
  sample_X

Per-stem counts:
  sample_A: 8
  sample_B: 8
  sample_C: 8
  ...
  sample_X: 0

Artefacts
---------
Log file:     /path/to/perdita/logs/perdita_20260511T143215.log
TSV report:   /analysis/2026.05.11_msn/bam/reports/perdita_report_20260511T143215.tsv

Exit code:    1  (some files / filestems unresolved — see report for details)
```

Both the TSV report and the text summary are disabled together with `--no-report`. Each run gets a fresh timestamped set, so nothing is overwritten between runs.

---

## More examples

**Preview a destructive move before running it:**
```bash
./perdita.sh --src /data/raw --dest /archive --file filestems.txt \
             --input-mode filestems --move --dry-run
```

**Re-run against the same destination — size-aware update is the default:**
```bash
./perdita.sh --src /data --dest /subset \
             --file filestems.txt --input-mode filestems
```

**Disambiguate stems that share prefixes (S1, S10, …):**
```bash
./perdita.sh --src /data --dest /subset --file filestems.txt \
             --input-mode filestems --anchors "_."
```

**Restrict to paired-end FASTQ only:**
```bash
./perdita.sh --src /data --dest /subset --file filestems.txt \
             --input-mode filestems \
             --suffixes "_R1.fastq.gz,_R2.fastq.gz"
```

**Restrict to BAM + index:**
```bash
./perdita.sh --src /data/aligned --dest /data/subset \
             --file filestems.txt --input-mode filestems \
             --suffixes ".bam,.bam.bai"
```

**Mixed file types, explicit filenames, move instead of copy:**
```bash
./perdita.sh --src /data/results --dest /data/archive \
             --file filenames.txt --input-mode filenames --move
```

**Files spread across subdirectories:**
```bash
./perdita.sh --src /data/all_runs --dest /data/subset \
             --file filestems.txt --input-mode filestems --recursive
```

**Fill in only missing files, leave existing dest files untouched:**
```bash
./perdita.sh --src /data --dest /subset \
             --file filestems.txt --input-mode filestems --on-exists skip
```

**Force a refresh (overwrite existing files unconditionally):**
```bash
./perdita.sh --src /data --dest /subset \
             --file filestems.txt --input-mode filestems --on-exists overwrite
```

---

## Notes

- `--on-exists update` compares file sizes only, not content. For most real-world data (FASTQs, BAMs, etc.) this catches all the cases that matter; for files where two different versions could plausibly have identical sizes, use `--on-exists overwrite`, or run an md5 check separately
- When using `--move`, files are removed from the source after transfer — always preview with `--dry-run` first
- `--suffixes` entries must include any separator character: `.bam` not `bam`, `_R1.fastq.gz` not `R1.fastq.gz`
- `--anchors` entries are single characters; the value `"_."` means underscore-or-period, not the two-character string
- Bash 3.2 compatible (works on stock macOS bash without Homebrew)
