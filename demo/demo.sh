#!/usr/bin/env bash
#
# Demo invocation — copies the included paired-FASTQ samples to demo/result/.
#
# To try one of the optional flags below: add a trailing \ to the line above
# the option (and to each non-final option, if uncommenting more than one),
# then remove the leading # from the option you want.

./perdita.sh \
  --src "/Users/michaelflower/my_bin/utils/winter_tale/subset_files/perdita/demo/fastq" \
  --dest "/Users/michaelflower/my_bin/utils/winter_tale/subset_files/perdita/demo/result" \
  --file "/Users/michaelflower/my_bin/utils/winter_tale/subset_files/perdita/demo/demo_filestems.txt" \
  --input-mode filestems
  # --dry-run                                    # Preview without transferring
  # --recursive                                  # Search subdirectories of --src
  # --anchors "_."                               # Require _ or . after stem (S1 vs S10 disambiguation)
  # --suffixes "_R1.fastq.gz,_R2.fastq.gz"       # Whitelist: only paired-end FASTQ
  # --on-exists skip                             # Don't touch existing dest files
  # --on-exists overwrite                        # Overwrite unconditionally
  # --move                                       # Move instead of copy
