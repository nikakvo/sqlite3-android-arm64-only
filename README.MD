# SQLite3 Android ARM64 Only

A standalone **max-feature SQLite3 shell** for rooted Android ARM64 devices.

Built directly from the official SQLite source tree using the Android NDK and packaged as a Magisk / KernelSU / SukiSU Ultra module. Replaces only the interactive `sqlite3` command-line shell — Android's system `libsqlite.so` is completely untouched.

---

## Features

- Official upstream SQLite 3.53.2 build
- ARM64-only, compiled with Android NDK (API 21+)
- Wrapper + real binary architecture (`sqlite3` → `sqlite3.real`)
- Automatic runtime tuning based on device RAM
- Adaptive `mmap_size` — 64 / 128 / 256 MB depending on available memory
- Session PRAGMAs injected automatically via `-cmd` on every shell start
- No dependency on `$HOME` or `.sqliterc`
- Safe to uninstall — `uninstall.sh` cleans up all deployed files
- Android framework and installed applications remain completely unaffected

---

## Included SQLite Extensions

Nearly every stable compile-time feature available in SQLite is enabled:

| Category | Extensions |
|---|---|
| Full-Text Search | FTS4 (includes FTS3), FTS5, FTS3 Parenthesized Queries |
| JSON | JSON1 |
| Geospatial | RTREE, GEOPOLY |
| Sync | SESSION, PREUPDATE HOOK, DESERIALIZE, UNLOCK NOTIFY |
| Virtual Tables | DBSTAT, DBPAGE, BYTECODE, STMTVTAB, CARRAY |
| Math & Stats | MATH FUNCTIONS, PERCENTILE, STAT4 |
| Developer | API ARMOR, STMT SCAN STATUS, NORMALIZED SQL, COLUMN METADATA, SOUNDEX, UPDATE/DELETE LIMIT, EXPLAIN COMMENTS, OFFSET SQL FUNC, NULL TRIM |

> **FTS4 and FTS5 are separate engines.** FTS4 is included because Android system databases (contacts, calendar, SMS) use FTS4 tables. FTS5 is a completely independent rewrite with BM25 ranking and prefix queries.

---

## Wrapper Architecture

The installed `/system/bin/sqlite3` is a lightweight shell script wrapper. On every invocation it:

1. Reads `/proc/meminfo` to detect available device RAM
2. Selects an appropriate `mmap_size` (64 / 128 / 256 MB)
3. Injects performance PRAGMAs via `-cmd`
4. Calls the actual compiled binary — `sqlite3.real`

This approach avoids any dependency on `.sqliterc` or `$HOME`, and works consistently across all Android environments.

---

## Automatic Session Configuration

Every shell session automatically receives these defaults — no manual setup needed:

| PRAGMA | Value | Note |
|---|---|---|
| `cache_size` | -20000 | ~20 MB page cache in RAM |
| `temp_store` | MEMORY | Temp tables in RAM, not on flash |
| `busy_timeout` | 5000 | Wait up to 5s on locked DB |
| `mmap_size` | Adaptive | 64 / 128 / 256 MB based on RAM |
| `synchronous` | NORMAL | Balanced speed and safety |
| `wal_autocheckpoint` | 500 | Checkpoint after ~2 MB WAL |
| `foreign_keys` | ON | FK enforcement always active |
| `recursive_triggers` | ON | Triggers can call themselves |
| `analysis_limit` | 1000 | ANALYZE samples 1000 rows per index |

> When opening an existing DB path, `journal_mode`, `foreign_keys`, and `wal_autocheckpoint` are intentionally skipped to avoid incompatibility with Android system databases.

---

## `.sqliterc-full`

The module deploys a complete reference configuration file to:

```
/data/local/.sqliterc-full
```

It contains every tunable PRAGMA with explanations — including advanced options like `page_size`, `locking_mode`, `auto_vacuum`, and device-class mmap tuning. Everything is commented out by default.

Load manually when needed:

```sh
sqlite3 -init /data/local/.sqliterc-full /path/to/database.db
```

---

## Installation

1. Download the latest `.zip` from [Releases](https://github.com/nikakvo/sqlite3-android-arm64-only/releases)
2. Install via **Magisk**, **KernelSU**, or **SukiSU Ultra**
3. Reboot
4. Verify:

```sh
sqlite3 --version
```
<img width="300" alt="dnscrypt" src="https://raw.githubusercontent.com/nikakvo/sqlite3-android-arm64-only/main/Sqlite3.jpg" />
```

```

## Requirements

| Requirement | Details |
|---|---|
| Architecture | ARM64 only |
| Root manager | Magisk · KernelSU · SukiSU Ultra |
| Android (Magisk) | 6.0+ (API 23+) |
| Android (KernelSU / SukiSU) | 12+ |

---

## Build Information

Built from the official [SQLite amalgamation](https://www.sqlite.org/download.html) source using the Android NDK.

Key compiler flags:

```
-O2 -march=armv8-a -fPIE -pie -fuse-ld=lld
-fstack-protector-strong -ffunction-sections -fdata-sections
-Wl,--gc-sections -Wl,--strip-all -Wl,-z,max-page-size=16384
```

Full compile flag list is documented in the module's built-in help page (`webroot/index.html`).

---

## Safety

This module **does not replace or modify Android's internal SQLite library (`libsqlite.so`)**.

Only the standalone `sqlite3` command-line shell is replaced. All applications and the Android framework continue using the stock system library exactly as before.

---

## Module Info

| Property | Value |
|---|---|
| Module ID | `sqlite3-arm64-only` |
| Author | Tears Burn |
| Architecture | ARM64 |
| SQLite Version | 3.53.2 |
| Build Type | Standalone Max-Feature Shell |

---

## Credits

- [SQLite Development Team](https://www.sqlite.org/)
- Android NDK
- SukiSU Ultra / KernelSU / Magisk projects

---

*Intended for developers, power users, database inspection, forensic analysis, and advanced Android maintenance workflows.*
