# SQLite3 Android ARM64 Only

A standalone **max-feature SQLite3 shell** for rooted Android ARM64 devices.

Built from the official SQLite source with the Android NDK and packaged as a Magisk / KernelSU / SukiSU Ultra / APatch module. It replaces only the `sqlite3` command-line shell. Android's `libsqlite.so` is untouched, so apps and the framework keep using the stock library exactly as before.

<img width="300" alt="sqlite3" src="https://raw.githubusercontent.com/nikakvo/sqlite3-android-arm64-only/main/Sqlite3.jpg" />

---

## What you get

- Upstream SQLite **3.53.4**, ARM64, NDK-built (API 21+), verified after linking
- **`sqldiff`**, **`sqlite3-tool`** and **`sqlite3-doctor`** alongside the shell
- Nearly every stable SQLite feature compiled in (see below)
- `busy_timeout` of 5 s and a RAM-scaled `mmap_size` on every start
- Parallel sorter, so large `CREATE INDEX` and `ORDER BY` use more than one core
- 16 KB page aligned, PIE, RELRO + BIND_NOW, no extension loading
- Offline help page in the module's WebUI, and a clean uninstall

## What it does differently from a plain SQLite build

| | |
|---|---|
| `UPDATE` / `DELETE … ORDER BY … LIMIT` | works — the parser is regenerated from `sqlite-src`, since the flag alone does nothing with the ready-made amalgamation |
| Double-quoted strings (`DQS=3`) | accepted, so app databases whose views or triggers use `"text"` can be read, written and altered |
| `fdatasync()` on commit | no metadata flush on every sync |
| `malloc_usable_size()` | no 8-byte size header in front of every allocation |
| `secure_delete` | **off** — freed pages are not zero-filled, which saves writes on flash |
| Extension loading | omitted |

---

## Compiled-in extensions

| Category | Extensions |
|---|---|
| Full-text search | FTS4 (with FTS3), FTS5, FTS3 parenthesized queries |
| Geospatial | RTREE, GEOPOLY |
| Sync & bulk | SESSION, PREUPDATE HOOK, SNAPSHOT, RBU, UNLOCK NOTIFY |
| Virtual tables | DBSTAT, DBPAGE, BYTECODE, STMTVTAB, CARRAY |
| Math & stats | MATH FUNCTIONS, PERCENTILE, STAT4, SORTER REFERENCES |
| Developer | API ARMOR, NORMALIZE, COLUMN METADATA, SOUNDEX, UPDATE/DELETE LIMIT, EXPLAIN COMMENTS, OFFSET SQL FUNC, NULL TRIM, UNKNOWN SQL FUNCTION |

> **FTS4 is there for Android's own databases** (contacts, calendar, SMS); FTS5 is an independent engine with BM25 ranking and prefix queries.
>
> **JSON and `sqlite3_deserialize()` work**, but their old flags no longer exist in SQLite, so `sqlite_compileoption_used()` returns 0 for both — test the feature, not the flag.
>
> **`STMT_SCANSTATUS` is opt-in**, since it adds counters to every `sqlite3_step()`. Rebuild with `WITH_SCANSTATUS=1 ./build.sh` if you want `.scanstats`.

### Compile-time defaults

Applied to every connection, including ones made with `.open`:

| Setting | Value |
|---|---|
| `THREADSAFE` | 1 (full mutex serialization) |
| `TEMP_STORE` | 2 — memory, `PRAGMA temp_store` can override |
| `DEFAULT_CACHE_SIZE` | -16000 (~16 MB) |
| `DEFAULT_SYNCHRONOUS` / `DEFAULT_WAL_SYNCHRONOUS` | 1 (NORMAL) |
| `DEFAULT_FOREIGN_KEYS` | 1 (ON) |
| `DEFAULT_MMAP_SIZE` / `MAX_MMAP_SIZE` | 256 MB / 1 TB |
| `MAX_WORKER_THREADS` / `DEFAULT_WORKER_THREADS` | 4 / 2 |
| `DQS` | 3 |

---

## Tools

| Tool | Purpose |
|---|---|
| `sqlite3` | wrapper: sets `busy_timeout` and a RAM-scaled `mmap_size`, then runs `sqlite3.real` |
| `sqlite3.real` | the compiled binary |
| `sqldiff` | official SQLite tool — diff two databases |
| `sqlite3-tool` | 16 helper commands for inspection and maintenance |
| `sqlite3-doctor` | full diagnostic, exits non-zero on problems |

### sqlite3-tool

```
Inspect:   info · tables · indexes · schema · size · biggest · doctor
Maintain:  integrity · vacuum · analyze · optimize · wal-checkpoint
Data:      backup · restore
Build:     compile-options · version
```

```sh
sqlite3-tool info /data/data/com.example/databases/app.db
sqlite3-tool backup /data/data/com.example/databases/app.db /sdcard/app.db
sqlite3-tool biggest /sdcard/big.db 10
sqlite3-tool compile-options WORKER
```

`backup` and `restore` go through SQLite's online backup API, not `cp`: safe on a live database, no write access needed to the source, owner and SELinux label preserved, verified with `integrity_check` before the destination is replaced — a failed backup leaves the previous copy untouched. `biggest` lists the largest tables and indexes on disk via `dbstat`, the part of `sqlite3_analyzer` people actually want without needing TCL to build it.

Every command waits up to 5 s on a busy database, refuses files that are not SQLite databases, and shows SQLite's own error when a write fails. Environment: `SQLITE3_BIN`, `SQLITE3_BUSY_MS` (default 5000), `NO_COLOR`.

### sqlite3-doctor

```sh
sqlite3-doctor [--quick|--full] <database.db>
```

Header validation, WAL state, page and freelist analysis, `quick_check`, `integrity_check`, `foreign_key_check` and per-table row counts. A check that cannot run — locked or unreadable database — is reported with SQLite's error and counted as a problem rather than passed over. Row counts are skipped above 256 MB unless `--full`; `--quick` skips `integrity_check` and row counts. Exits 1 on problems, so it works in scripts.

---

## Wrapper

`/system/bin/sqlite3` is a small shell script: it reads `/proc/meminfo`, picks an `mmap_size` (64 / 128 / 256 / 512 MB by RAM), passes that and `busy_timeout` via `-cmd`, and hands every argument to `sqlite3.real`. Everything else is a compile-time default. `SQLITE3_NO_WRAPPER=1` bypasses it.

> PRAGMAs set at startup belong to the connection open at that moment. Running `.open` inside the shell creates a **new** connection with `busy_timeout` back to 0 and `mmap_size` back to 256 MB. Pass the database on the command line when those matter.

## `.sqliterc-full`

An annotated reference config is deployed to `/data/local/.sqliterc-full`: every tunable PRAGMA with notes on what it does and when it is unsafe, all commented out. The module rewrites it at every boot, so copy it before uncommenting anything and load your copy instead.

```sh
sqlite3 -init /data/local/.sqliterc-full /path/to/database.db
```

---

## Installation

1. Download the latest `.zip` from [Releases](https://github.com/nikakvo/sqlite3-android-arm64-only/releases)
2. Install via **Magisk**, **KernelSU**, **SukiSU Ultra** or **APatch**
3. Reboot
4. Verify:

```sh
sqlite3 --version
sqlite3-tool version
sqlite3 :memory: "SELECT sqlite_compileoption_used('SECURE_DELETE');"   # 0
```

The installer stops if the package is incomplete or the shipped binary will not execute on your device, rather than installing something that fails later.

| Requirement | Details |
|---|---|
| Architecture | ARM64 only |
| Root manager | Magisk · KernelSU · SukiSU Ultra · APatch |
| Android (Magisk) | 6.0+ (API 23+) |
| Android (KernelSU / SukiSU) | 12+ |
| WebUI | needs a manager that renders `webroot` (KernelSU, SukiSU, APatch, MMRL) |

---

## Building

Linux or WSL. Under WSL, work in the Linux home (`~/`), not under `/mnt/c`.

```sh
sudo apt install build-essential unzip zip
# put sqlite-amalgamation-XYYZZPP.zip and the matching sqlite-src-XYYZZPP.zip next to build.sh
export ANDROID_NDK_HOME=/path/to/android-ndk
./build.sh                                    # -> ./android-module/
./build.sh --install /path/to/module          # also copies the binaries into the module
./build.sh --install /path/to/module --zip    # ... and packs <id>-<version>.zip for the release
./build.sh --help                             # all options
```

| Variable | Effect |
|---|---|
| `API=21` | minimum Android API level |
| `WITH_UPDATE_LIMIT=0` | leave out `UPDATE`/`DELETE … LIMIT`. On by default, which regenerates `sqlite3.c` from `sqlite-src` and needs `cc` and `make` |
| `WITH_SCANSTATUS=1` | enable `.scanstats` |
| `SKIP_HOST_TEST=1` | skip the functional test on the build machine |

Key flags — the full list, with what each one does, is in the module's help page:

```
-O2 -march=armv8-a -fPIE -pie -fuse-ld=lld
-fstack-protector-strong -ffunction-sections -fdata-sections
-Wl,--gc-sections -Wl,--as-needed -Wl,--strip-all
-Wl,-z,relro -Wl,-z,now -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384
```

### The build verifies itself

Nothing is written to `android-module/` until the staged binaries pass every check:

- **Compile options** read back out of the binary and checked against the flag list — missing, wrong-valued, and unwanted options (`SECURE_DELETE`, …) all fail the build.
- **Platform flags** leave no trace in the option list, so it checks that the binary really imports `malloc_usable_size()`, `fdatasync()` and `localtime_r()`.
- **ELF**, both binaries: AArch64, PIE, BIND_NOW, RELRO, stripped, 16 KB aligned segments, no libraries besides `libc.so`, `libm.so`, `libdl.so`.
- **Functional test**: the same sources and SQLite flags built for the host and run through FTS5, FTS4, R-Tree, Geopoly, JSON, math, percentile, dbstat, double-quoted strings, `DELETE … LIMIT` and `sqldiff`.

It then writes `SHA256SUMS` and `BUILDINFO` (SQLite source ID, NDK revision, API level, defines).

Worth knowing before you edit the flag list: most SQLite options are tested with `#ifdef`, not by value, so `-DSQLITE_SECURE_DELETE=0` **enables** secure delete. Builds up to v3.53.4 shipped that way by mistake. If you don't want a feature, leave the flag out entirely — the verification step exists to catch exactly this.

---

## Module Info

| Property | Value |
|---|---|
| Module ID | `sqlite3-arm64-only` |
| Author | Tears Burn |
| Architecture | ARM64 |
| SQLite version | 3.53.4 |
| Build type | Standalone max-feature shell |

[Changelog](CHANGELOG.md) · [SQLite](https://www.sqlite.org/) · Android NDK

*Intended for developers, power users, database inspection, forensic analysis, and advanced Android maintenance workflows.*
