# Changelog

## v3.53.3

> SQLite 3.53.3 — 2026-06-26

Bugfix patch release. No new features.

Fixes for problems in 3.53.0 / 3.53.1 / 3.53.2, mostly reported by AI-generated issues.

---

**SQLite source info:**
- `SQLITE_SOURCE_ID`: `2026-06-26 20:14:12 d4c0e51e4aeb96955b99185ab9cde75c339e2c29c3f3f12428d364a10d782c62`
- `SHA3-256 (sqlite3.c)`: `28e484abdaa43630e34040ef6ed92be973a1ad54107803d8af5145b889c23ed7`

---

## v3.53.2-r1 — 2026-06-13

### SQLite
- Updated to **SQLite 3.53.2** (2026-06-03)

### New binaries
- **`sqldiff`** — official SQLite diff tool; outputs SQL to transform one database into another. Supports `--schema`, `--table`, `--summary`, `--transaction` and `--vtab` flags. Built from the same source with identical compile flags.

### New scripts
- **`sqlite3-doctor`** — full database diagnostics in one command. Checks file validity, WAL state, page info, freelist/fragmentation, `integrity_check`, `quick_check`, foreign key violations and table stats. Outputs a color-coded report with a summary at the end.
- **`sqlite3-tool`** — helper wrapper with 13 ready-to-use commands: `integrity`, `vacuum`, `analyze`, `optimize`, `wal-checkpoint`, `tables`, `indexes`, `schema`, `size`, `info`, `backup`, `restore`, `doctor`. Backup is WAL-aware: runs `wal_checkpoint(FULL)` and copies `-wal`/`-shm` files automatically.

### Build
- Added `build.sh` — fully automated build script. Drop the two SQLite zip archives (`sqlite-amalgamation-*.zip` and `sqlite-src-*.zip`) in the working directory and run `./build.sh`. Extracts sources, builds all binaries and writes results to `android-module/`. No manual steps required for future version updates.
- Added `SQLITE_ENABLE_STMTVTAB` and `SQLITE_ENABLE_BYTECODE_VTAB` compile flags (were missing in previous builds).

### Help page (`index.html`)
- Added **Tools** section with dedicated pages for `sqldiff`, `sqlite3-doctor` and `sqlite3-tool`.
- Added **Tools** tab to mobile navigation.
- Updated section numbering (Verify → 16, Uninstall → 17).

### Module
- `customize.sh` — updated to set permissions for all new binaries. Each binary is optional: if absent from the zip it is silently skipped, so older zips remain compatible.
- `uninstall.sh` — updated to clean up temp files created by `sqlite3-doctor` and `sqlite3-tool`.

---

## v3.53.2 — 2026-06-03

### Initial Release

- SQLite 3.53.2 built from official amalgamation source
- Android NDK, API 21+, ARM64 target (`-march=armv8-a`)
- PIE binary with `-fstack-protector-strong` and LLD linker
- 16 KB page alignment for Android 15+ compatibility (`-Wl,-z,max-page-size=16384`)

**Wrapper architecture:**
- `sqlite3` is a shell script wrapper; `sqlite3.real` is the compiled binary
- Adaptive `mmap_size` detection from `/proc/meminfo` at startup (64 / 128 / 256 MB)
- Session PRAGMAs injected via `-cmd` — no `$HOME` or `.sqliterc` dependency

**Session defaults applied automatically:**
- `cache_size = -20000` (~20 MB page cache)
- `temp_store = MEMORY`
- `busy_timeout = 5000`
- `synchronous = NORMAL`
- `wal_autocheckpoint = 500`
- `foreign_keys = ON`
- `recursive_triggers = ON`
- `analysis_limit = 1000`

**Extensions enabled:**
- FTS4 (includes FTS3) + FTS3 Parenthesized Queries + FTS5
- JSON1, RTREE, GEOPOLY
- SESSION + PREUPDATE HOOK + DESERIALIZE + UNLOCK NOTIFY
- DBSTAT, DBPAGE, BYTECODE, STMTVTAB, CARRAY virtual tables
- MATH FUNCTIONS, PERCENTILE, STAT4
- API ARMOR, STMT SCAN STATUS, NORMALIZED SQL, SOUNDEX, and more

**Deployed files:**
- `/system/bin/sqlite3` — wrapper script
- `/system/bin/sqlite3.real` — compiled binary
- `/data/local/.sqliterc-full` + `/.sqliterc-full` — full reference config
- `uninstall.sh` — removes all deployed files on uninstall
