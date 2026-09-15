#!/bin/bash
# req-fixtures.sh — shared fixtures for Step 2->3 and Step 3->4 gate tests.
# Usage: `. tests/lib/req-fixtures.sh` then use the exported strings.
#
# VDGG_REQ_COMMON:            3-section prefix for requirements.md (Step 2->3 tests).
# VDGG_INV_COMMON:            full 7-heading investigation.md that passes the Step 3->4 gate.
# VDGG_INV_MISSING_H5:        6 headings with '## 5. Side effects and risks' dropped (must block).
# VDGG_INV_ADJACENT_H3_H4:    7 headings but heading 3 has an empty body (heading 4 follows immediately, must block).

VDGG_REQ_COMMON=$'## Goal\ngoal\n\n## Constraints\nnone\n\n## Acceptance criteria\nnone\n'

VDGG_INV_COMMON=$'## 1. Related files\nbody\n\n## 2. Existing implementation patterns\nbody\n\n## 3. Impact surface\nbody\n\n## 4. Prior similar implementations\nbody\n\n## 5. Side effects and risks\nbody\n\n## 6. Constraints\nbody\n\n## 7. Verification strategy\nbody\n'

VDGG_INV_MISSING_H5=$'## 1. Related files\nb\n## 2. Existing implementation patterns\nb\n## 3. Impact surface\nb\n## 4. Prior similar implementations\nb\n## 6. Constraints\nb\n## 7. Verification strategy\nb\n'

VDGG_INV_ADJACENT_H3_H4=$'## 1. Related files\nb\n## 2. Existing implementation patterns\nb\n## 3. Impact surface\n## 4. Prior similar implementations\nb\n## 5. Side effects and risks\nb\n## 6. Constraints\nb\n## 7. Verification strategy\nb\n'
