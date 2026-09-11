# Changelog

## v3.53.4-r3

### Changed — the build

- **Two platform flags never took effect.** `HAVE_MALLOC_USABLE_SIZE=1` is
  ignored unless `HAVE_MALLOC_H=1` is also set, so SQLite kept its own 8-byte
  size header on every allocation; it now uses bionic's `malloc_usable_size()`.
  `HAVE_USLEEP=1` did nothing because SQLite sleeps with `nanosleep()`; it is
  gone.
- **`fdatasync()` instead of `fsync()`** (`HAVE_FDATASYNC=1`), so a commit no
  longer flushes file metadata as well. Date functions use `localtime_r()`
  (`HAVE_LOCALTIME_R=1`).
- **`UPDATE`/`DELETE … ORDER BY … LIMIT` works now.** Earlier builds passed
  `SQLITE_ENABLE_UPDATE_DELETE_LIMIT` to the official amalgamation, whose
  parser is already generated without it: the option appeared in
  `compile_options` while `DELETE … LIMIT` was a syntax error. `build.sh`
  regenerates `sqlite3.c` from `sqlite-src` with the grammar (about 10 s, needs
  `cc` and `make`; `WITH_UPDATE_LIMIT=0` skips it).
- **Double-quoted string literals are accepted again (`SQLITE_DQS=3`).** With
  `DQS=0`, an app database whose views or triggers use `"text"` as a string
  rejected queries on those views, `INSERT` into tables with such triggers, and
  `ALTER TABLE`. A tool for opening other apps' databases has to read what
  their SQLite reads.
- `-ldl` dropped; nothing calls `dlopen()` with extension loading omitted.
- **Verification covers more, and runs before anything is written.** A rejected
  build used to be left in `android-module/` anyway. Expected compile options
  are now derived from the flag list instead of a second hand-kept list, a
  wrong value is caught as well as a missing option, and platform flags are
  checked through the libc functions the binary imports. ELF checks run on
  both binaries and now also require BIND_NOW, RELRO and stripping; every LOAD
  segment must be 16 KB aligned (the old check looked only at one value), and
  any library besides `libc.so`, `libm.so` and `libdl.so` fails the build.
- **Functional test on the build machine.** The same sources and SQLite flags
  are compiled for the host and exercised: FTS5, FTS4 query syntax, R-Tree,
  Geopoly, JSON, math, percentile, soundex, dbstat, bytecode, `sqlite_offset`,
  `secure_delete` off, double-quoted strings, `DELETE … LIMIT`, `sqldiff`. Skip with
  `SKIP_HOST_TEST=1`.
- `sqlite3.c` is compiled once and linked into both programs, in parallel with
  `shell.c` and `sqldiff.c`, instead of being compiled twice.
- `sqlite-src` must be the same release as the amalgamation, and the version
  comes from `sqlite3.h`; a copied archive such as `… (1).zip` no longer
  produces a garbage version. SHA3-256 of both archives is printed for checking
  against the download page.
- The newest NDK on disk is used, not the alphabetically first, and its
  revision is printed. NDK `llvm-readelf`/`llvm-strings` are preferred, so a
  build machine without binutils works; before, a missing tool ended the
  script silently. Unexpected failures now report the line.
- `android-module/BUILDINFO` records the SQLite source ID, NDK revision, API
  level and defines.
- `--install` keeps `version=` when the SQLite version is unchanged (it used
  to turn `v3.53.4-r2` into `v3.53.4` and bump `versionCode` on every run).
  When the version does change it also updates `update.json` and the WebUI
  badge. A `module.prop` without a trailing newline no longer loses its last
  line. A bare `--install` ended the script silently; it is an error now.
- `--install DIR --zip` packs the module into `<id>-<version>.zip` with only
  module content (no README, `build.sh`, `update.json` or `.git`), ready to
  upload as the release asset.
- Under WSL, building on a Windows drive (`/mnt/c/...`) gives a warning; missing
  host tools are reported with the `apt` command that installs them.
- Colours only on a terminal; `--help` no longer prints lines of code.

### Fixed — the tools

- **`sqlite3-tool backup` could delete the database it was backing up.** It
  started with `rm -f "$DEST"`, so `sqlite3-tool backup app.db app.db` removed
  the source, and any failed backup destroyed the previous good copy. It now
  refuses when source and destination are the same file, writes to a temporary
  file next to the destination, checks it with `integrity_check`, and only then
  moves it into place.
- **`sqlite3-tool restore` could corrupt a database that was still open.** It
  copied the file with `cp` and then deleted `-wal` and `-shm` beside it;
  removing `-shm` under a live connection is unsafe, and the copy could land
  mid-write. Restore now uses `.restore`, which goes through SQLite's backup
  API with proper locking, handles WAL itself, and keeps the file's owner and
  SELinux label so the app can still open its database. The result is verified
  with `integrity_check`.
- Paths containing `'` broke `backup`: dot-command arguments do not use SQL
  quoting. They are now quoted the way the shell expects.
- `sqlite3-tool --help` printed literal `\033[1;37m` sequences in a colour
  terminal, because the colour variables held the text `\033` and the help
  text goes through `cat`. They hold real escape bytes now.
- `sqlite3-doctor` reported an empty (0-byte) `-wal` file as an unmerged WAL
  and exited 1. Apps that keep a WAL database open always leave one; only a
  non-empty WAL is flagged now.
- `sqlite3-tool` hid SQLite's error messages everywhere. A file that is not a
  database printed empty fields; `vacuum`, `analyze`, `optimize` and
  `wal-checkpoint` failed without saying why. The tool now checks the database
  header first, and commands that change the database show SQLite's own error
  ("database is locked", "disk I/O error", ...).
- `sqlite3-tool wal-checkpoint` reported success when the checkpoint could not
  finish because another connection was reading. It now reads the result:
  frames checkpointed, a warning when it is incomplete, and a clear message for
  a database that is not in WAL mode.
- `sqlite3-tool optimize` printed a stray `1000` (the value of
  `PRAGMA analysis_limit`).
- `sqlite3-tool schema <db> <table>` also lists the table's indexes and
  triggers, ends every statement with `;` so it can be pasted back, and says so
  when the name does not exist.
- `sqlite3-tool backup <db> <directory>` put the temporary file into the
  directory under its temporary name; it now backs up to `<directory>/<db name>`.
  `restore` into a directory is refused.
- `sqlite3-tool biggest` uses dbstat's aggregate mode (one row per object
  instead of one per page) and no longer claims dbstat is missing when asked
  for the top 0.
- `sqlite3-doctor` could not tell "the check found problems" from "the check
  could not run": a database that could not be read reported
  `No foreign key violations`. Checks now show SQLite's error text, and a
  locked or unreadable database is reported as such right away (the probe was
  `page_size`, which SQLite answers without reading the file).
- `sqlite3-doctor` reports a 0-byte file as empty instead of "bad magic
  header", and multi-line check results are indented consistently.
- Database paths starting with `-` were taken as options by `head` and
  `sqlite3`; `sqlite3-doctor -- <file>` works too.
- Both tools are v2.2.

### Fixed — the module

- `customize.sh` ran `pkill -x sqlite3`, which never matched anything — the
  wrapper `exec`s into `sqlite3.real` — and was not needed, since the new files
  are only mounted after a reboot. Removed.
- `service.sh` dropped the last line of `module.prop` at boot when the file
  had no trailing newline — normally `updateJson=`, which silently disabled
  update checks.
- `files/sqliterc-full` set the busy timeout with a PRAGMA that printed `5000`
  at startup when loaded with `-init`. It uses `.timeout 5000` now.

### Fixed — the WebUI help page

Every example was run against a build with the same flags as the shipped
binary.

- **The FTS5 and FTS4 test commands failed through `su -c`** with
  `/system/bin/sh: syntax error: unexpected '('`. `su -c` joins its arguments
  and re-parses them, so the quotes around the SQL are lost. The tests now feed
  SQL through a here-document into `:memory:`, which works directly, through
  `su -c`, and leaves no file behind. Basic Usage explains the `su -c` pitfall.
- `percentile_cont(0.95) WITHIN GROUP (ORDER BY value)` is not SQLite syntax;
  it is `percentile_cont(value, 0.95)`. The p50/p95/p99 example queried a table
  that did not exist.
- The scan-status example used `.scanstatus` (the command is `.scanstats`) and
  claimed `STMT_SCANSTATUS` was compiled in. It is opt-in; the page shows
  `.eqp on` instead and explains how to get `.scanstats`.
- `log()` is base 10 in SQLite; the natural-log example now uses `ln()`.
  `floor()`/`ceil()` return `3.0 | 4.0`, not `3 | 4`.
- The Geopoly example used a column `shape`; the column is `_shape`. It also
  inserts a polygon now, so the query returns a row.
- `sqlite_compileoption_used('DQS')` returns 1 (the option is present,
  whatever its value), and `ENABLE_DESERIALIZE` returns 0 — both examples
  claimed the opposite. `PRAGMA temp_store` reports 0, not 2.
- The Session Config section still described the old nine-PRAGMA wrapper
  (`cache_size=-20000`, `wal_autocheckpoint=500`, `recursive_triggers`, …). It
  now lists what the wrapper really sets, what is compiled in, and the `.open`
  caveat. The mmap table includes the 512 MB tier.
- The compile-flag tables match the new build (see above). Rows for flags
  that no longer exist or were removed (`SECURE_DELETE=0`, `HAVE_USLEEP`,
  `ENABLE_JSON1`, `ENABLE_DESERIALIZE`) are gone.
- **The help page is readable on a phone.** Flag and setting tables were two
  columns wide; a long flag name pushed the description past the edge of the
  screen, where it was cut off and could not be scrolled to. On narrow screens
  the name now sits above its description, inline code no longer splits in the
  middle, and the `sqlite3-tool` command list is a table instead of a
  sideways-scrolling code block.
- New example for `UPDATE` / `DELETE … LIMIT`; the overview lists what is new
  in r2; the `sqlite3-tool` and `sqlite3-doctor` sections describe v2.2.
- The linker table listed `-llog` and `-ldl` as required; the binary needs only
  `libc.so` and `libm.so`. Added `--as-needed`, `-z relro`, `-z now` and
  `common-page-size`.
- Shell examples used `-- comments`, which the copy button pasted as command
  arguments. Shell blocks use `#`, and COPY now strips comments entirely. It
  also falls back to `execCommand` where the WebView has no clipboard API.
- The sqlite3-doctor example output was a v1.0 transcript and rendered inside
  the block header because of a missing `</div>`. An unclosed `<strong>` made
  the backup note bold to the end. Both fixed; the output is from v2.1.
- The safe-area padding targeted a `.header` class that did not exist, and
  navigation from the mobile drawer scrolled past the section heading. Fixed.

---

## v3.53.4-r2

### Fixed — the tools

- **`sqlite3-tool backup` could delete the database it was backing up.** It
  started with `rm -f "$DEST"`, so `sqlite3-tool backup app.db app.db` removed
  the source, and any failed backup destroyed the previous good copy. It now
  refuses when source and destination are the same file, writes to a temporary
  file next to the destination, checks it with `integrity_check`, and only then
  moves it into place.
- **`sqlite3-tool restore` could corrupt a database that was still open.** It
  copied the file with `cp` and then deleted `-wal` and `-shm` beside it;
  removing `-shm` under a live connection is unsafe, and the copy could land
  mid-write. Restore now uses `.restore`, which goes through SQLite's backup
  API with proper locking, handles WAL itself, and keeps the file's owner and
  SELinux label so the app can still open its database. The result is verified
  with `integrity_check`.
- Paths containing `'` broke `backup`: dot-command arguments do not use SQL
  quoting. They are now quoted the way the shell expects.
- `sqlite3-tool --help` printed literal `\033[1;37m` sequences in a colour
  terminal, because the colour variables held the text `\033` and the help
  text goes through `cat`. They hold real escape bytes now.
- `sqlite3-doctor` reported an empty (0-byte) `-wal` file as an unmerged WAL
  and exited 1. Apps that keep a WAL database open always leave one; only a
  non-empty WAL is flagged now.
- Both tools are v2.1.

### Fixed — the module

- `customize.sh` ran `pkill -x sqlite3`, which never matched anything — the
  wrapper `exec`s into `sqlite3.real` — and was not needed, since the new files
  are only mounted after a reboot. Removed.
- `files/sqliterc-full` set the busy timeout with a PRAGMA that printed `5000`
  at startup when loaded with `-init`. It uses `.timeout 5000` now.

### Fixed — the WebUI help page

Every example was run against a build with the same flags as the shipped
binary.

- **The FTS5 and FTS4 test commands failed through `su -c`** with
  `/system/bin/sh: syntax error: unexpected '('`. `su -c` joins its arguments
  and re-parses them, so the quotes around the SQL are lost. The tests now feed
  SQL through a here-document into `:memory:`, which works directly, through
  `su -c`, and leaves no file behind. Basic Usage explains the `su -c` pitfall.
- `percentile_cont(0.95) WITHIN GROUP (ORDER BY value)` is not SQLite syntax;
  it is `percentile_cont(value, 0.95)`. The p50/p95/p99 example queried a table
  that did not exist.
- The scan-status example used `.scanstatus` (the command is `.scanstats`) and
  claimed `STMT_SCANSTATUS` was compiled in. It is opt-in; the page shows
  `.eqp on` instead and explains how to get `.scanstats`.
- `log()` is base 10 in SQLite; the natural-log example now uses `ln()`.
  `floor()`/`ceil()` return `3.0 | 4.0`, not `3 | 4`.
- The Geopoly example used a column `shape`; the column is `_shape`. It also
  inserts a polygon now, so the query returns a row.
- `sqlite_compileoption_used('DQS')` returns 1 (the option is present with
  value 0), and `ENABLE_DESERIALIZE` returns 0 — both examples claimed the
  opposite. `PRAGMA temp_store` reports 0, not 2.
- The Session Config section still described the old nine-PRAGMA wrapper
  (`cache_size=-20000`, `wal_autocheckpoint=500`, `recursive_triggers`, …). It
  now lists what the wrapper really sets, what is compiled in, and the `.open`
  caveat. The mmap table includes the 512 MB tier.
- `SQLITE_ENABLE_UPDATE_DELETE_LIMIT` is documented as having no effect: SQLite
  only honours it when the parser is regenerated from canonical sources, and
  this build compiles the amalgamation, so `DELETE … LIMIT` is a syntax error.
- The linker table listed `-llog` and `-ldl` as required; the binary needs only
  `libc.so` and `libm.so`. Added `--as-needed`, `-z relro`, `-z now` and
  `common-page-size`.
- Shell examples used `-- comments`, which the copy button pasted as command
  arguments. Shell blocks use `#`, and COPY now strips comments entirely. It
  also falls back to `execCommand` where the WebView has no clipboard API.
- The sqlite3-doctor example output was a v1.0 transcript and rendered inside
  the block header because of a missing `</div>`. An unclosed `<strong>` made
  the backup note bold to the end. Both fixed; the output is from v2.1.
- The safe-area padding targeted a `.header` class that did not exist, and
  navigation from the mobile drawer scrolled past the section heading. Fixed.

---

---

## v3.53.4-r1

Same SQLite release, rebuilt. The changes are in how it was compiled and in the
scripts around it.

### Fixed — the build

- **`SQLITE_SECURE_DELETE` was enabled in every previous build.** The flag was
  passed as `-DSQLITE_SECURE_DELETE=0`, but SQLite tests it with `#ifdef`, not
  by value:

  ```c
  /* btree.c */
  #if defined(SQLITE_SECURE_DELETE)
      pBt->btsFlags |= BTS_SECURE_DELETE;
  ```

  Defining it as `0` still defines it. Every `DELETE` was zero-filling its
  freed pages and every `VACUUM` was doing extra write work — the exact
  opposite of what the documentation claimed. The flag is now omitted
  entirely. Use `PRAGMA secure_delete=ON` per connection if you want it, or
  `SQLITE_FAST_SECURE_DELETE` for the cheaper in-page variant.

- **Two flags did nothing at all.** `SQLITE_ENABLE_JSON1` and
  `SQLITE_ENABLE_DESERIALIZE` appear nowhere in the SQLite source any more —
  JSON has been built in since 3.38 and deserialize since 3.36 (you disable it
  with `SQLITE_OMIT_DESERIALIZE`). Both were removed. Nothing is lost; the
  features were always there. The old docs told you to verify them with
  `sqlite_compileoption_used()`, which returned 0 and looked like a broken
  build.

- **`liblog.so` was linked but never used.** `readelf` showed it as a `NEEDED`
  dependency while the binary contained no `__android_log_*` symbol at all.
  `-Wl,--as-needed` drops it.

- **The version decoder was wrong.** `sqlite-amalgamation-3530400.zip` has no
  dots, so the `grep -oP '\d+\.\d+\.\d+'` never matched and the fallback did
  `minor = (v % 1000000) / 1000`, printing **3.530.400** instead of 3.53.4.
  The packed format is `XYYZZPP`; the decoder now handles it correctly.

- `SQLITE_MAX_EXPR_DEPTH=1000` was removed — that is already the default.

### Added — the build

- **Parallel sorter.** `SQLITE_MAX_WORKER_THREADS=4` and
  `SQLITE_DEFAULT_WORKER_THREADS=2`. Both were implicitly 0, which disabled
  parallel sorting entirely. Large `CREATE INDEX` and `ORDER BY` get faster on
  a multi-core phone.
- `SQLITE_ENABLE_SORTER_REFERENCES` — less memory when sorting wide rows.
- `SQLITE_ENABLE_SNAPSHOT`, `SQLITE_ENABLE_RBU`.
- `HAVE_MALLOC_USABLE_SIZE=1` — bionic has it.
- `SQLITE_TEMP_STORE=2` instead of `3`. Three forces temp tables into memory
  unconditionally and ignores `PRAGMA temp_store`, which can OOM the process
  on a large temp table.
- `SQLITE_ENABLE_STMT_SCANSTATUS` is now **opt-in** (`WITH_SCANSTATUS=1
  ./build.sh`). It adds counters to every `sqlite3_step()` whether you use
  `.scanstats` or not.
- Hardening and packaging: `-Wl,-z,relro`, `-Wl,-z,now`,
  `-Wl,-z,common-page-size=16384` alongside the existing `max-page-size` for
  16 KB page devices.

- **`build.sh` now verifies its own output.** After linking it reads the
  compile-option list back out of the binary and asserts that every expected
  option is present and that `SECURE_DELETE` is absent, checks the ELF
  architecture, PIE status, 16 KB segment alignment and the `NEEDED` library
  list, and refuses to finish if anything is off. It also writes `SHA256SUMS`,
  auto-detects the NDK from `ANDROID_NDK_HOME`/`ANDROID_NDK_ROOT`, and can
  install straight into a module tree with `--install DIR`, bumping
  `module.prop` for you.

### Fixed — the tools

- **`sqlite3-tool backup` used `cp`.** The comment claimed it used SQLite's
  online backup API; the code ran `wal_checkpoint(FULL)` and then copied the
  file. That writes to the source (so it fails on a read-only database) and is
  not atomic — a concurrent writer produces a corrupt backup. It now uses
  `.backup`, which is the real online backup API, and verifies the result with
  `integrity_check` before reporting success.
- **`sqlite3-tool restore` copied `-wal` and `-shm` from the backup.** A stale
  `-shm` next to a restored database is at best useless and at worst harmful.
  They are now deleted at the destination instead.
- **Neither tool set a busy timeout.** Both called `sqlite3.real` directly,
  bypassing the wrapper, so the first query against any live database returned
  `database is locked` immediately. Every command now sets one
  (`SQLITE3_BUSY_MS`, default 5000).
- **Table names were interpolated into SQL unquoted.** A table named
  `weird "quoted" name` broke every row count. Identifiers and string literals
  are now escaped properly.
- **Colours never worked.** Both scripts tested `[ "$(tput colors)" -ge 8 ]`,
  but Android's toybox has no `tput`, so the test always failed silently and
  the whole colour block was dead. They use `TERM` now, and honour `NO_COLOR`.
- **`sqlite3-doctor` ran `dd` twice** and threw the first result away
  (`MAGIC=$(dd ...)` was assigned and never used). The header check is a single
  `head -c 15` now.
- `sqlite3-doctor` always exited 0. It now exits 1 when it finds problems, so
  it can be used in a script.

### Added — the tools

- `sqlite3-tool biggest <db> [n]` — largest tables and indexes on disk via
  `dbstat`. This is the part of `sqlite3_analyzer` people actually want;
  `sqlite3_analyzer` itself needs TCL to build and was never shipped, though
  `customize.sh` checked for it.
- `sqlite3-tool compile-options [filter]` — see exactly how your `sqlite3` was
  built.
- `sqlite3-tool version`.
- `sqlite3-doctor --quick` (skip `integrity_check` and row counts) and
  `--full`. Row counts are skipped automatically on databases over 256 MB
  unless `--full` is given, so the doctor no longer takes minutes by surprise.
- Both tools honour `SQLITE3_BIN`, which also makes them testable against any
  sqlite3 build.

### Changed — the wrapper

`/system/bin/sqlite3` injected nine PRAGMAs. Five of them just repeated a
compile-time default that already applies to every connection, and the rest are
reset the moment you run `.open` inside the shell, because that creates a new
connection. Only two are worth setting: `busy_timeout`, which has no
compile-time equivalent, and `mmap_size`, which is scaled to the device.
The rest are gone, along with a fork per invocation. `SQLITE3_NO_WRAPPER=1`
bypasses it entirely.

The `.open` caveat is now documented rather than silently not working.

### Other

- `customize.sh` now refuses to install a broken package instead of installing
  it and failing later. It aborts if `sqlite3` or `sqlite3.real` is missing from
  the zip, and aborts if the shipped binary will not execute on the device
  (wrong architecture or corrupt file), printing `uname -m` and
  `ro.product.cpu.abi` so the report is actionable. `sqldiff`, `sqlite3-tool`
  and `sqlite3-doctor` are treated as optional and only warn. It also warns when
  `module.prop` and the binary disagree about the version — the signature of a
  package assembled from mismatched parts — and when the build has
  `SECURE_DELETE` on. The architecture check reads `ro.product.cpu.abi` as well
  as `uname -m`, and the dead `sqlite3_analyzer` branch is gone.
- `service.sh` rebuilds `module.prop` with a read loop instead of `sed -i`, and
  only when the status text actually changed.
- `uninstall.sh` no longer tries to delete `/.sqliterc-full` in the filesystem
  root — nothing ever created it.
- `files/sqliterc-full` documents which PRAGMAs are already compiled in, so it
  no longer suggests setting things that are set.
- The WebUI no longer requests Google Fonts (it fails on a device with no
  network), uses `viewport-fit=cover` with safe-area padding, and its flag
  table now matches the binary.

---

## v3.53.4

- Updated SQLite to version 3.53.4.
- Includes the latest upstream bug fixes and stability improvements.

---

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
