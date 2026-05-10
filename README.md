# perdita.sh

Copy or move a defined subset of files from one directory to another, based on a list you provide. Works with any file type — `.fastq.gz`, `.bam`, `.txt`, `.docx`, and so on.

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

## Quick start

You need three things: a **source directory**, a **destination directory**, and a **list** of what to transfer. The example below uses the included demo dataset, so it works as-is from the repo root.

```bash
./perdita.sh \
  --src demo/fastq \
  --dest demo/result \
  --file demo/demo_filestems.txt \
  --input-mode filestems
```

Output:
```
Source:      demo/fastq
Destination: demo/result
Input file:  demo/demo_filestems.txt
Input mode:  filestems
Action:      copy
Recursive:   false
Force:       false
Suffixes:    _R1.fastq.gz _R2.fastq.gz

  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R1.fastq.gz  (2.1M)
  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R2.fastq.gz  (2.3M)
  [copy] DMPX_MS408-N702-A-S506-A_S38_L001_R1.fastq.gz  (1.9M)
  [copy] DMPX_MS408-N702-A-S506-A_S38_L001_R2.fastq.gz  (2.0M)

Done. Copy: 4 files. Missing: 0. Skipped (exists): 0.
```

The destination directory is created automatically if it does not exist.

---

## Choosing between `filestems` and `filenames`

The two modes solve different problems. The names describe what each line of your input file contains.

### `filestems` mode — one input line per **sample**

Each line in your input file is a **shared name fragment** (a filestem). The script appends each suffix from `--suffixes` to that filestem to construct the actual filenames it looks for.

The point: files in genomics workflows almost always come in groups that share a filestem — paired FASTQ (`_R1.fastq.gz`, `_R2.fastq.gz`), BAM with index (`.bam`, `.bam.bai`), VCF with index (`.vcf.gz`, `.vcf.gz.tbi`). With `filestems`, you list each sample once and the script works out which files to grab.

Input file (`filestems.txt`):
```
sample_A
sample_B
```

Run:
```bash
./perdita.sh --src /data --dest /subset --file filestems.txt --input-mode filestems
```

Files transferred (default suffixes `_R1.fastq.gz,_R2.fastq.gz`):
```
sample_A_R1.fastq.gz
sample_A_R2.fastq.gz
sample_B_R1.fastq.gz
sample_B_R2.fastq.gz
```

Same input file, different suffixes:
```bash
./perdita.sh --src /data --dest /subset --file filestems.txt --input-mode filestems \
             --suffixes ".bam,.bam.bai"
```
Now transfers:
```
sample_A.bam
sample_A.bam.bai
sample_B.bam
sample_B.bam.bai
```

The same `filestems.txt` works for FASTQ today, BAMs tomorrow, VCFs next week — just change `--suffixes`.

### `filenames` mode — one input line per **file**

Each line in your input file is a **literal, complete filename**. The script transfers it as-is, with no suffix expansion. Any leading path is stripped — only the basename is used.

Use this when:
- Your filenames don't follow a regular pattern
- You want to mix file types in a single transfer (a BAM, a TSV, a Word doc)
- You already have a manifest of exact filenames from somewhere else

Input file (`filenames.txt`):
```
sample_A_R1.fastq.gz
sample_A_R2.fastq.gz
QC_report.html
metadata.docx
alignment.bam
alignment.bam.bai
```

Run:
```bash
./perdita.sh --src /data --dest /subset --file filenames.txt --input-mode filenames
```

All six files are transferred exactly as named.

### Quick decision rule

| Question | Answer |
|----------|--------|
| Are all my files predictable from a shared sample/run identifier plus a known suffix pattern? | **`filestems`** |
| Do I want to list each sample once and have the script find R1+R2 (or BAM+BAI, etc.)? | **`filestems`** |
| Will I reuse this list across different file types? | **`filestems`** |
| Are my filenames irregular, or do I want to mix file types in one go? | **`filenames`** |
| Do I already have an explicit list of complete filenames? | **`filenames`** |

### Side-by-side: same outcome, both modes

To transfer `sample_A_R1.fastq.gz` and `sample_A_R2.fastq.gz`:

| `filestems.txt` | `filenames.txt` |
|-----------------|-----------------|
| `sample_A` | `sample_A_R1.fastq.gz`<br>`sample_A_R2.fastq.gz` |

---

## Input file format

Both modes share the same file format conventions:

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

---

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `--src` | Yes | Directory containing the source files |
| `--dest` | Yes | Destination directory (created if it doesn't exist) |
| `--file` | Yes | Path to your input list (filestems or filenames) |
| `--input-mode` | Yes | `filestems` or `filenames` |
| `--suffixes` | No | Comma-separated suffixes for filestems mode. Default: `_R1.fastq.gz,_R2.fastq.gz` |
| `--move` | No | Move files instead of copying (default: copy) |
| `--recursive` | No | Search subdirectories of `--src` for each file |
| `--force` | No | Overwrite existing files in `--dest` (default: skip them) |
| `--dry-run` | No | Show what would happen without transferring anything |

---

## Output

The script prints each transfer with the file size, then a summary:

```
  [copy] sample_A_R1.fastq.gz  (1.2G)
  [copy] sample_A_R2.fastq.gz  (1.3G)

Done. Copy: 2 files. Missing: 0. Skipped (exists): 0.
```

The tags that can appear:

| Tag | Meaning | Stream |
|-----|---------|--------|
| `[copy]` / `[move]` | Successfully transferred | stdout |
| `[DRY-copy]` / `[DRY-move]` | Would be transferred (under `--dry-run`) | stdout |
| `[MISSING]` | Not found in `--src` | stderr |
| `[SKIP exists]` | Already exists in `--dest` (use `--force` to overwrite) | stderr |
| `[WARN]` | Multiple matches in `--recursive` mode; first one used | stderr |

The split between stdout and stderr lets you redirect transfer logs and error messages independently:

```bash
./perdita.sh ... > transfers.log 2> errors.log
```

The script exits with code `0` if no files were missing, or `1` if any were missing. Skipped files (already in dest) do **not** trigger a non-zero exit, so partial reruns work cleanly in pipelines.

---

## Safety features

- **Skip-by-default on existing files.** If a file already exists in `--dest`, it is skipped, not overwritten. Use `--force` to overwrite.
- **Same-directory guard.** If `--src` and `--dest` resolve to the same directory, the script exits with an error before doing anything.
- **Dry-run mode.** `--dry-run` shows exactly what would be transferred without touching any files. Recommended before any `--move` operation.
- **Duplicate warning in recursive mode.** If `--recursive` finds the same filename in multiple subdirectories, the script warns and uses the first match.

---

## More examples

**Preview a destructive move before running it:**
```bash
./perdita.sh --src /data/raw --dest /archive --file filestems.txt \
             --input-mode filestems --move --dry-run
```

**BAM + index files:**
```bash
./perdita.sh --src /data/aligned --dest /data/subset \
             --file filestems.txt --input-mode filestems \
             --suffixes ".bam,.bam.bai"
```

**Single suffix (e.g. VCF):**
```bash
./perdita.sh --src /data/variants --dest /data/subset \
             --file filestems.txt --input-mode filestems \
             --suffixes ".vcf.gz"
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

**Resume a partial transfer (existing files are skipped automatically):**
```bash
./perdita.sh --src /data --dest /subset \
             --file filestems.txt --input-mode filestems
```

**Force a refresh (overwrite existing files):**
```bash
./perdita.sh --src /data --dest /subset \
             --file filestems.txt --input-mode filestems --force
```

---

## Notes

- Suffixes must include any separator character: `.bam` not `bam`, `_R1.fastq.gz` not `R1.fastq.gz`
- When using `--move`, files are removed from the source after transfer — always preview with `--dry-run` first
- File integrity is not checked after transfer; for critical transfers consider running an md5 checksum step afterwards
- Bash 3.2 compatible (works on stock macOS bash without Homebrew)
