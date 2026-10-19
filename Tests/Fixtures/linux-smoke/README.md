This is a test-only save, never a user's save.
`scripts/linux-smoke.sh` copies it into a new per-run directory and never writes to this file.
The `claimedDate` is a placeholder, and the script replaces it with the local date in the copy so that no first-run credit fires.
