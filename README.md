# perdita.sh

Copy or move a defined subset of files from one directory to another, based on a list you provide. Works with any file type — `.fastq.gz`, `.bam`, `.txt`, `.docx`, and so on.

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

You need three things: a **source directory**, a **destination directory**, and a **list of files** you want to transfer.

```bash
./perdita.sh \
  --src "/Users/michaelflower/my_bin/file_handling/subset_files/demo/fastq" \
  --dest "/Users/michaelflower/my_bin/file_handling/subset_files/demo/result" \
  --file "/Users/michaelflower/my_bin/file_handling/subset_files/demo/demo_stems.txt" \
  --input-mode stems
```

Output:
```
Source:      .../demo/fastq
Destination: .../demo/result
Input file:  .../demo/demo_stems.txt
Input mode:  stems
Action:      copy
Recursive:   false
Suffixes:    _R1.fastq.gz _R2.fastq.gz

  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R1.fastq.gz
  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R2.fastq.gz
  [copy] DMPX_MS408-N702-A-S506-A_S38_L001_R1.fastq.gz
  [copy] DMPX_MS408-N702-A-S506-A_S38_L001_R2.fastq.gz

Done. Copy: 4 files. Missing: 0.
```

The destination directory is created automatically if it does not exist.

---

## Input files

### The file list

A plain text file with one entry per line. Lines beginning with `#` and blank lines are ignored.

There are two formats, selected with `--input-mode`:

**Stems** (`--input-mode stems`)

Each line is a filename stem — the shared part of the filename before the suffix. The script appends each suffix from `--suffixes` to construct the full filenames. This is useful for paired-end reads where R1 and R2 share the same stem.

```
# demo_stems.txt
DMPX_MS408-N702-A-S505-A_S26_L001
DMPX_MS408-N702-A-S506-A_S38_L001
```

With the default suffixes (`_R1.fastq.gz,_R2.fastq.gz`), this transfers four files:
```
DMPX_MS408-N702-A-S505-A_S26_L001_R1.fastq.gz
DMPX_MS408-N702-A-S505-A_S26_L001_R2.fastq.gz
DMPX_MS408-N702-A-S506-A_S38_L001_R1.fastq.gz
DMPX_MS408-N702-A-S506-A_S38_L001_R2.fastq.gz
```

**Full filenames** (`--input-mode files`)

Each line is a complete filename including extension. Files are transferred one-for-one with no suffix expansion. Any leading path is stripped — only the basename matters.

```
# filelist.txt
DMPX_MS408-N702-A-S505-A_S26_L001_R1.fastq.gz
DMPX_MS408-N702-A-S505-A_S26_L001_R2.fastq.gz
sample_report.txt
metadata.docx
alignment.bam
alignment.bam.bai
```

### The source directory

The directory containing your files. Use `--recursive` if files are spread across subdirectories.

---

## Parameters

| Flag | Required | Description |
|------|----------|-------------|
| `--src` | Yes | Directory containing the source files |
| `--dest` | Yes | Destination directory (created if it doesn't exist) |
| `--file` | Yes | Path to your file list (stems or full filenames) |
| `--input-mode` | Yes | `stems` or `files` |
| `--suffixes` | No | Comma-separated suffixes for stems mode. Default: `_R1.fastq.gz,_R2.fastq.gz` |
| `--move` | No | Move files instead of copying |
| `--recursive` | No | Search subdirectories of `--src` for each file |

---

## Output

The script prints each file as it is transferred, then a summary:

```
  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R1.fastq.gz
  [copy] DMPX_MS408-N702-A-S505-A_S26_L001_R2.fastq.gz

Done. Copy: 2 files. Missing: 0.
```

Any files not found in the source are flagged as missing but do not stop the run:

```
  [MISSING] DMPX_MS408-N702-A-S999-A_S99_L001_R1.fastq.gz

Done. Copy: 2 files. Missing: 1.
```

The script exits with code `0` if all files transferred successfully, or `1` if any were missing — useful for chaining into pipelines.

---

## More examples

**BAM + index files:**
```bash
./perdita.sh \
  --src /data/aligned \
  --dest /data/subset \
  --file stems.txt \
  --input-mode stems \
  --suffixes ".bam,.bam.bai"
```

**Single suffix (e.g. VCF):**
```bash
./perdita.sh \
  --src /data/variants \
  --dest /data/subset \
  --file stems.txt \
  --input-mode stems \
  --suffixes ".vcf.gz"
```

**Mixed file types, explicit filenames, move instead of copy:**
```bash
./perdita.sh \
  --src /data/results \
  --dest /data/archive \
  --file filelist.txt \
  --input-mode files \
  --move
```

**Files spread across subdirectories:**
```bash
./perdita.sh \
  --src /data/all_runs \
  --dest /data/subset \
  --file stems.txt \
  --input-mode stems \
  --recursive
```

---

## Notes

- Suffixes must include any separator character: `.bam` not `bam`, `_R1.fastq.gz` not `R1.fastq.gz`
- When using `--move`, files are removed from the source after transfer — use with care
- File integrity is not checked after transfer; for critical transfers consider running an md5 checksum step afterwards
