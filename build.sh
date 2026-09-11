#!/usr/bin/env bash
# build.sh — SQLite3 ARM64 Android module builder
# Tears Burn / nikakvo
#
# Usage:
#   ./build.sh [--install DIR [--zip]] [--keep-build]
#
# Options:
#   --install DIR   after a verified build, copy the binaries into the module
#                   tree DIR; if the SQLite version changed, also update
#                   module.prop, update.json and the WebUI version badge
#   --zip           with --install: pack DIR into <id>-<version>.zip, ready to
#                   upload as a release asset
#   --keep-build    keep .build_tmp/ (it is always kept when the build fails)
#   -h, --help      this text
#
# Environment:
#   TOOLCHAIN=...          NDK LLVM toolchain (.../toolchains/llvm/prebuilt/<host>)
#   ANDROID_NDK_HOME, ANDROID_NDK_ROOT
#                          searched when TOOLCHAIN is unset, then the newest
#                          ~/android-ndk-*, ~/Android/Sdk/ndk/*, /opt/android-ndk*
#   API=21                 minimum Android API level
#   WITH_UPDATE_LIMIT=0    skip UPDATE/DELETE ... LIMIT. On by default: the
#                          amalgamation is regenerated from sqlite-src, which
#                          needs a host C compiler and make (about 10 s)
#   WITH_SCANSTATUS=1      enable SQLITE_ENABLE_STMT_SCANSTATUS (.scanstats);
#                          adds counters to every sqlite3_step()
#   SKIP_HOST_TEST=1       skip the functional test run on the build machine
#   HOST_CC=cc             host compiler for the amalgamation and the host test
#
# Build machine (Debian/Ubuntu/WSL):
#   sudo apt install build-essential unzip zip
#   Work inside the Linux file system (~/...), not under /mnt/c.
#   NO_COLOR=1             plain output
#
# Expects in the current directory, both for the same SQLite version:
#   sqlite-amalgamation-XYYZZPP.zip
#   sqlite-src-XYYZZPP.zip
#
# Output: android-module/{sqlite3.real,sqldiff,SHA256SUMS,BUILDINFO}

set -Eeuo pipefail
shopt -s nullglob

# ── Output ────────────────────────────────────────────────────────────────────
# Real escape bytes, only on a terminal: a build log piped to a file stays clean.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[0;33m'
    C=$'\033[0;36m'; W=$'\033[1;37m'; N=$'\033[0m'
else
    R=''; G=''; Y=''; C=''; W=''; N=''
fi

ok()   { printf '%s  [OK]%s    %s\n' "$G" "$N" "$*"; }
err()  { printf '%s  [ERR]%s   %s\n' "$R" "$N" "$*" >&2; }
info() { printf '%s  [INFO]%s  %s\n' "$C" "$N" "$*"; }
warn() { printf '%s  [WARN]%s  %s\n' "$Y" "$N" "$*"; }
step() { printf '\n%s── %s%s\n' "$W" "$*" "$N"; }
die()  { err "$*"; exit 1; }

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; }

# set -e alone exits without a word when a command fails unexpectedly
# (a missing tool, a failed unzip). Say where it happened.
trap 'err "unexpected failure at line $LINENO: $BASH_COMMAND"' ERR

WITH_UPDATE_LIMIT="${WITH_UPDATE_LIMIT:-1}"
WITH_SCANSTATUS="${WITH_SCANSTATUS:-0}"
SKIP_HOST_TEST="${SKIP_HOST_TEST:-0}"
for v in WITH_UPDATE_LIMIT WITH_SCANSTATUS SKIP_HOST_TEST; do
    case "${!v}" in 0|1) ;; *) printf '  [ERR]   %s must be 0 or 1\n' "$v" >&2; exit 1 ;; esac
done

START_TIME=$(date +%s)
WORK_DIR="$(pwd)"
BUILD_DIR="$WORK_DIR/.build_tmp"
OUT_DIR="$WORK_DIR/android-module"

# ── Arguments ─────────────────────────────────────────────────────────────────
INSTALL_DIR=""
KEEP_BUILD=0
MAKE_ZIP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --install)
            # The old parser ran `shift 2` unconditionally; a bare --install made
            # shift fail and set -e ended the script silently.
            [ $# -ge 2 ] && [ -n "$2" ] || die "--install needs a directory"
            INSTALL_DIR="$2"; shift 2 ;;
        --install=*) INSTALL_DIR="${1#*=}"; shift ;;
        --keep-build) KEEP_BUILD=1; shift ;;
        --zip) MAKE_ZIP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done

[ "$MAKE_ZIP" = "0" ] || [ -n "$INSTALL_DIR" ] || die "--zip needs --install DIR"

# Check the install target now, not after a multi-minute build.
if [ -n "$INSTALL_DIR" ]; then
    [ -d "$INSTALL_DIR" ] || die "Not a directory: $INSTALL_DIR"
    [ -f "$INSTALL_DIR/module.prop" ] || die "No module.prop in $INSTALL_DIR"
    INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
fi

BUILD_STARTED=0
on_exit() {
    local rc=$?
    [ "$BUILD_STARTED" = "1" ] || return 0
    if [ "$rc" -ne 0 ]; then
        err "build failed — intermediate files kept in $BUILD_DIR"
    elif [ "$KEEP_BUILD" = "1" ]; then
        info "Build directory kept: $BUILD_DIR"
    else
        rm -rf "$BUILD_DIR"
    fi
}
trap on_exit EXIT

printf '\n%s╔═══════════════════════════════════════╗%s\n' "$W" "$N"
printf '%s║  SQLite3 ARM64 Android Module Build   ║%s\n' "$W" "$N"
printf '%s╚═══════════════════════════════════════╝%s\n' "$W" "$N"

# ── Toolchain ─────────────────────────────────────────────────────────────────
step "Checking toolchain"

case "$(uname -s)" in
    Linux)  HOST_TAG=linux-x86_64 ;;
    Darwin) HOST_TAG=darwin-x86_64 ;;   # the NDK uses this tag on Apple silicon too
    *) die "Unsupported build host: $(uname -s)" ;;
esac

API="${API:-21}"
case "$API" in
    '' | *[!0-9]*) die "API must be a number, got: $API" ;;
esac

cc_in() { printf '%s/toolchains/llvm/prebuilt/%s/bin/aarch64-linux-android%s-clang' "$1" "$HOST_TAG" "$API"; }

if [ -z "${TOOLCHAIN:-}" ]; then
    # Explicit NDK variables first, then the newest NDK found on disk. The old
    # loop took the first glob match, i.e. the alphabetically *oldest* NDK.
    CANDIDATES=()
    [ -n "${ANDROID_NDK_HOME:-}" ] && CANDIDATES+=("$ANDROID_NDK_HOME")
    [ -n "${ANDROID_NDK_ROOT:-}" ] && CANDIDATES+=("$ANDROID_NDK_ROOT")
    FOUND=( "$HOME"/android-ndk-* "$HOME"/Android/Sdk/ndk/* /opt/android-ndk* )
    if [ ${#FOUND[@]} -gt 0 ]; then
        while IFS= read -r d; do CANDIDATES+=("$d"); done \
            < <(printf '%s\n' "${FOUND[@]}" | sort -rV)
    fi
    for ndk in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do
        if [ -x "$(cc_in "$ndk")" ]; then
            TOOLCHAIN="$ndk/toolchains/llvm/prebuilt/$HOST_TAG"
            break
        fi
    done
fi
[ -n "${TOOLCHAIN:-}" ] || die "No Android NDK with aarch64-linux-android${API}-clang found.
  Set TOOLCHAIN, ANDROID_NDK_HOME or ANDROID_NDK_ROOT (and check API=$API).
  Example: TOOLCHAIN=/path/to/ndk/toolchains/llvm/prebuilt/$HOST_TAG ./build.sh"

CC="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang"
[ -x "$CC" ] || die "Compiler not found for API $API: $CC"

NDK_ROOT="$(cd "$TOOLCHAIN/../../../.." && pwd)"
NDK_REV=$(sed -n 's/^Pkg\.Revision *= *//p' "$NDK_ROOT/source.properties" 2>/dev/null || true)
CLANG_VER=$("$CC" --version | sed -n '1p')

ok   "Compiler: $CC"
info "NDK:      ${NDK_REV:-unknown} ($NDK_ROOT)"
info "Clang:    $CLANG_VER"
info "API:      $API"

# Prefer the NDK's own binutils: they are always there, system readelf/strings
# are not. A missing tool used to end the script silently under set -e.
pick_tool() {
    local t
    for t in "$TOOLCHAIN/bin/llvm-$1" "$(command -v "llvm-$1" || true)" "$(command -v "$1" || true)"; do
        [ -n "$t" ] && [ -x "$t" ] && { printf '%s' "$t"; return 0; }
    done
    return 1
}
READELF=$(pick_tool readelf) || die "readelf not found (neither in the NDK nor on PATH)"
STRINGS=$(pick_tool strings) || die "strings not found (neither in the NDK nor on PATH)"
command -v unzip >/dev/null || die "unzip is required (sudo apt install unzip)"
[ "$MAKE_ZIP" = "0" ] || command -v zip >/dev/null || die "--zip needs zip (sudo apt install zip)"
if command -v sha256sum >/dev/null; then SHA256=(sha256sum)
elif command -v shasum >/dev/null; then SHA256=(shasum -a 256)
else die "sha256sum or shasum is required"; fi

HOST_CC="${HOST_CC:-$(command -v cc || command -v gcc || command -v clang || true)}"
if [ "$WITH_UPDATE_LIMIT" = "1" ]; then
    { [ -n "$HOST_CC" ] && command -v make >/dev/null; } || die "UPDATE/DELETE LIMIT needs a host C compiler and make.
  Install them:  sudo apt install build-essential
  or build without the feature:  WITH_UPDATE_LIMIT=0 ./build.sh"
    info "Host CC:  $HOST_CC"
fi

# Windows drives under WSL (/mnt/c, ...) ignore chmod and are many times slower;
# configure scripts extracted there may not be executable.
case "$WORK_DIR" in
    /mnt/[a-z]/*) warn "Building under $WORK_DIR (a Windows drive). Use a directory in the WSL home (~/) instead." ;;
esac

# ── Source archives ───────────────────────────────────────────────────────────
step "Locating source archives"

AMALG_ALL=( "$WORK_DIR"/sqlite-amalgamation-*.zip )
[ ${#AMALG_ALL[@]} -gt 0 ] || die "sqlite-amalgamation-*.zip not found in $WORK_DIR
  Download from: https://www.sqlite.org/download.html"
AMALG_ZIP=$(printf '%s\n' "${AMALG_ALL[@]}" | sort -V | tail -n 1)

# Release archives carry the packed version XYYZZPP: 3530400 -> 3.53.4.
# Take the number from the exact name pattern — stripping every non-digit broke
# on copies such as "sqlite-amalgamation-3530400 (1).zip".
AMALG_NAME=$(basename "$AMALG_ZIP")
[[ "$AMALG_NAME" =~ ^sqlite-amalgamation-([0-9]{7})\.zip$ ]] \
    || die "Unexpected archive name: $AMALG_NAME (expected sqlite-amalgamation-XYYZZPP.zip)"
RAW_VER="${BASH_REMATCH[1]}"
ZIP_VERSION=$(printf '%d.%d.%d' \
    $(( 10#$RAW_VER / 1000000 )) \
    $(( (10#$RAW_VER % 1000000) / 10000 )) \
    $(( (10#$RAW_VER % 10000) / 100 )))

# sqldiff.c must come from the same release as sqlite3.c. The old script picked
# the newest of each zip independently, so two versions could be mixed.
SRC_ZIP="$WORK_DIR/sqlite-src-$RAW_VER.zip"
[ -f "$SRC_ZIP" ] || die "sqlite-src-$RAW_VER.zip not found in $WORK_DIR
  It must match $AMALG_NAME. Download from: https://www.sqlite.org/download.html"

info "Amalgamation: $AMALG_NAME"
info "Source:       $(basename "$SRC_ZIP")"

# Print SHA3-256 so the archives can be checked against the download page.
if openssl dgst -sha3-256 /dev/null >/dev/null 2>&1; then
    for z in "$AMALG_ZIP" "$SRC_ZIP"; do
        h=$(openssl dgst -sha3-256 -r "$z" | cut -d' ' -f1)
        info "SHA3-256 $(basename "$z"): $h"
    done
fi

# ── Prepare ───────────────────────────────────────────────────────────────────
step "Preparing build directory"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{amalg,src,obj,stage}
BUILD_STARTED=1

unzip -q "$AMALG_ZIP" -d "$BUILD_DIR/amalg"
AMALG_DIR=$(find "$BUILD_DIR/amalg" -name sqlite3.c -exec dirname {} \; | sed -n '1p')
[ -n "$AMALG_DIR" ] || die "sqlite3.c not found in $AMALG_NAME"
for f in sqlite3.c sqlite3.h shell.c; do
    [ -f "$AMALG_DIR/$f" ] || die "$f missing from $AMALG_NAME"
done
ok "amalgamation extracted"

# unzip exits 11 when a pattern matches nothing; that is reported below with a
# clear message instead of being hidden behind 2>/dev/null || true.
unzip -q "$SRC_ZIP" "*/tool/sqldiff.c" "*/ext/misc/sqlite3_stdio.h" -d "$BUILD_DIR/src" || true
SQLDIFF_C=$(find "$BUILD_DIR/src" -name sqldiff.c | sed -n '1p')
STDIO_H=$(find "$BUILD_DIR/src" -name sqlite3_stdio.h | sed -n '1p')
[ -n "$SQLDIFF_C" ] || die "tool/sqldiff.c not found in $(basename "$SRC_ZIP")"
[ -n "$STDIO_H" ]   || die "ext/misc/sqlite3_stdio.h not found in $(basename "$SRC_ZIP")"
# sqlite3_stdio.c is only needed on Windows; on unix the header is just macros.
ok "sqldiff sources extracted"

SQL_DIR="$AMALG_DIR"

# SQLITE_ENABLE_UPDATE_DELETE_LIMIT changes the grammar, and the parser inside
# the official amalgamation is already generated without it. Passing the flag
# to that file only adds a compile_options entry while `DELETE ... LIMIT` stays
# a syntax error. Regenerating sqlite3.c from the canonical sources is the only
# way to get the feature.
if [ "$WITH_UPDATE_LIMIT" = "1" ]; then
    step "Generating amalgamation with UPDATE/DELETE LIMIT"
    unzip -q "$SRC_ZIP" -d "$BUILD_DIR/srcfull"
    SRC_TOP=$(find "$BUILD_DIR/srcfull" -mindepth 2 -maxdepth 2 -name configure -exec dirname {} \; | sed -n '1p')
    [ -n "$SRC_TOP" ] || die "configure not found in $(basename "$SRC_ZIP")"
    chmod +x "$SRC_TOP/configure" "$SRC_TOP"/autosetup/autosetup* 2>/dev/null || true
    mkdir -p "$BUILD_DIR/gen"
    if ! ( cd "$BUILD_DIR/gen" \
           && CC="$HOST_CC" "$SRC_TOP/configure" --update-limit > configure.log 2>&1 \
           && make sqlite3.c shell.c > make.log 2>&1 ); then
        tail -n 20 "$BUILD_DIR/gen/configure.log" "$BUILD_DIR/gen/make.log" 2>/dev/null >&2 || true
        die "amalgamation generation failed — logs in $BUILD_DIR/gen/"
    fi
    SQL_DIR="$BUILD_DIR/gen"
    ok "sqlite3.c regenerated"
fi

cp "$SQL_DIR/sqlite3.c" "$SQL_DIR/sqlite3.h" "$SQL_DIR/shell.c" "$BUILD_DIR/src/"
cp "$SQLDIFF_C" "$STDIO_H" "$BUILD_DIR/src/"

# The header, not the file name, is the authority on what is being built.
SQLITE_VERSION=$(sed -n 's/^#define SQLITE_VERSION  *"\([0-9.]*\)".*/\1/p' "$BUILD_DIR/src/sqlite3.h")
SOURCE_ID=$(sed -n 's/^#define SQLITE_SOURCE_ID  *"\(.*\)"$/\1/p' "$BUILD_DIR/src/sqlite3.h")
[ -n "$SQLITE_VERSION" ] || die "Could not read SQLITE_VERSION from sqlite3.h"
[ "$SQLITE_VERSION" = "$ZIP_VERSION" ] \
    || die "sqlite3.h says $SQLITE_VERSION but the archive name says $ZIP_VERSION"
info "Version:      SQLite $SQLITE_VERSION"
info "Source ID:    $SOURCE_ID"

# ══════════════════════════════════════════════════════════════════════════════
#  COMPILE FLAGS
#
#  Rules learned the hard way:
#
#  1. Many SQLite options are tested with #ifdef, NOT by value. Writing
#     -DSQLITE_SECURE_DELETE=0 DEFINES the macro and therefore ENABLES secure
#     delete — the exact opposite of the intent. If you don't want a feature,
#     omit the flag entirely.
#
#  2. Some flags no longer exist. SQLITE_ENABLE_JSON1 and
#     SQLITE_ENABLE_DESERIALIZE appear nowhere in the SQLite source any more;
#     JSON is built in since 3.38 and deserialize since 3.36.
#
#  3. Some flags only work together or only work in certain builds.
#     HAVE_MALLOC_USABLE_SIZE is ignored unless HAVE_MALLOC_H is also set
#     (mem1.c: #if HAVE_MALLOC_H && HAVE_MALLOC_USABLE_SIZE), and
#     SQLITE_ENABLE_UPDATE_DELETE_LIMIT is ignored by a pre-generated
#     amalgamation (see WITH_UPDATE_LIMIT above).
#
#  Every flag below is verified against the produced binary: SQLite options
#  through the compile-option list embedded in it, platform HAVE_* flags
#  through the libc functions the binary imports.
# ══════════════════════════════════════════════════════════════════════════════

CORE_FLAGS=(
    -DSQLITE_THREADSAFE=1
    -DSQLITE_USE_URI=1
    -DSQLITE_OMIT_LOAD_EXTENSION
    # DQS=3 keeps double-quoted string literals working, as in a default
    # SQLite build. DQS=0 is stricter, but then an app database whose views or
    # triggers contain "text" rejects INSERT into the affected tables, ALTER
    # TABLE and queries on those views — this tool exists to open other apps'
    # databases, so compatibility wins.
    -DSQLITE_DQS=3
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS
    -DSQLITE_HAVE_ISNAN
    # NOTE: SQLITE_SECURE_DELETE is deliberately absent — see rule 1.
)

# The amalgamation has no configure step, so it cannot detect what bionic
# offers. These tell it; each one is checked against the binary's imports.
PLATFORM_FLAGS=(
    # malloc_usable_size() instead of an 8-byte size header on every
    # allocation. Needs both macros — earlier builds set only the second one,
    # so it did nothing.
    -DHAVE_MALLOC_H=1
    -DHAVE_MALLOC_USABLE_SIZE=1
    # SQLite falls back to fsync() unless told fdatasync() is trustworthy
    # (os_unix.c). On Linux it is; it skips flushing metadata such as mtime
    # on every commit.
    -DHAVE_FDATASYNC=1
    # Thread-safe localtime_r() instead of localtime() under a global mutex.
    -DHAVE_LOCALTIME_R=1
    # NOTE: HAVE_USLEEP=1 removed — SQLite sleeps with nanosleep() unless
    # HAVE_NANOSLEEP=0, so it never reached usleep().
)
# The libc function each platform flag must make the binary call.
platform_import() {
    case "$1" in
        HAVE_MALLOC_USABLE_SIZE) printf 'malloc_usable_size' ;;
        HAVE_FDATASYNC)          printf 'fdatasync' ;;
        HAVE_LOCALTIME_R)        printf 'localtime_r' ;;
    esac
}

PERF_FLAGS=(
    # TEMP_STORE=2: temp tables default to memory but PRAGMA temp_store can
    # still override. =3 forces memory unconditionally, which can OOM the
    # process on a large temp table.
    -DSQLITE_TEMP_STORE=2
    -DSQLITE_DEFAULT_MEMSTATUS=0
    -DSQLITE_DEFAULT_CACHE_SIZE=-16000
    -DSQLITE_STMTJRNL_SPILL=-1
    -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1
    -DSQLITE_DEFAULT_SYNCHRONOUS=1
    -DSQLITE_DEFAULT_FOREIGN_KEYS=1
    -DSQLITE_DEFAULT_MMAP_SIZE=268435456
    -DSQLITE_MAX_MMAP_SIZE=1099511627776
    # Parallel sorter: speeds up large CREATE INDEX / ORDER BY on multi-core
    # phones.
    -DSQLITE_MAX_WORKER_THREADS=4
    -DSQLITE_DEFAULT_WORKER_THREADS=2
    -DSQLITE_ENABLE_SORTER_REFERENCES
)

FEATURE_FLAGS=(
    # Full-text search
    -DSQLITE_ENABLE_FTS3_PARENTHESIS
    -DSQLITE_ENABLE_FTS4
    -DSQLITE_ENABLE_FTS5
    # Geospatial, stats, math
    -DSQLITE_ENABLE_RTREE
    -DSQLITE_ENABLE_GEOPOLY
    -DSQLITE_ENABLE_STAT4
    -DSQLITE_ENABLE_MATH_FUNCTIONS
    -DSQLITE_ENABLE_PERCENTILE
    -DSQLITE_ENABLE_OFFSET_SQL_FUNC
    # Session / sync
    -DSQLITE_ENABLE_SESSION
    -DSQLITE_ENABLE_PREUPDATE_HOOK
    -DSQLITE_ENABLE_SNAPSHOT
    -DSQLITE_ENABLE_RBU
    -DSQLITE_ENABLE_UNLOCK_NOTIFY
    # Introspection virtual tables
    -DSQLITE_ENABLE_DBSTAT_VTAB
    -DSQLITE_ENABLE_DBPAGE_VTAB
    -DSQLITE_ENABLE_STMTVTAB
    -DSQLITE_ENABLE_BYTECODE_VTAB
    -DSQLITE_ENABLE_CARRAY
    # Language / API
    -DSQLITE_ENABLE_COLUMN_METADATA
    -DSQLITE_ENABLE_NORMALIZE
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS
    -DSQLITE_ENABLE_UNKNOWN_SQL_FUNCTION
    -DSQLITE_ENABLE_NULL_TRIM
    -DSQLITE_ENABLE_API_ARMOR
    -DSQLITE_SOUNDEX
)

# STMT_SCANSTATUS adds counters to every sqlite3_step() call. It powers
# .scanstats, but you pay for it on every query whether you use it or not.
if [ "$WITH_SCANSTATUS" = "1" ]; then
    FEATURE_FLAGS+=( -DSQLITE_ENABLE_STMT_SCANSTATUS )
    warn "STMT_SCANSTATUS enabled — .scanstats works, every query pays for it"
fi
if [ "$WITH_UPDATE_LIMIT" = "1" ]; then
    FEATURE_FLAGS+=( -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT )
fi

DEFS=( "${CORE_FLAGS[@]}" "${PLATFORM_FLAGS[@]}" "${PERF_FLAGS[@]}" "${FEATURE_FLAGS[@]}" )

CFLAGS=(
    -O2
    -march=armv8-a
    -fPIE
    -fomit-frame-pointer
    -fvisibility=hidden
    -ffunction-sections
    -fdata-sections
    -fstack-protector-strong
)

# shellcheck disable=SC2054  # the commas are part of -Wl, options
LDFLAGS=(
    -fuse-ld=lld
    -pie
    -Wl,--gc-sections
    # --as-needed drops libraries nothing references (liblog.so used to be
    # linked without a single call into it).
    -Wl,--as-needed
    -Wl,--strip-all
    -Wl,-O2
    -Wl,--build-id=none
    -Wl,-z,relro
    -Wl,-z,now
    # 16 KB page size devices
    -Wl,-z,max-page-size=16384
    -Wl,-z,common-page-size=16384
)

# -ldl dropped: with SQLITE_OMIT_LOAD_EXTENSION nothing calls dlopen().
LIBS=(-lm)

# ── Build ─────────────────────────────────────────────────────────────────────
# sqlite3.c is compiled once and linked into both programs; the old script
# compiled the 9 MB amalgamation twice. The three objects build in parallel.
step "Compiling (3 objects in parallel)"

cd "$BUILD_DIR/obj"
compile() { # <object> <source>
    "$CC" "${CFLAGS[@]}" "${DEFS[@]}" -I "$BUILD_DIR/src" -c -o "$1" "$2" > "$1.log" 2>&1
}
PIDS=()
{ compile sqlite3.o "$BUILD_DIR/src/sqlite3.c" || exit 1; } & PIDS+=($!)
{ compile shell.o   "$BUILD_DIR/src/shell.c"   || exit 1; } & PIDS+=($!)
{ compile sqldiff.o "$BUILD_DIR/src/sqldiff.c" || exit 1; } & PIDS+=($!)
COMPILE_FAILED=0
for p in "${PIDS[@]}"; do wait "$p" || COMPILE_FAILED=1; done
for o in sqlite3.o shell.o sqldiff.o; do
    if [ -s "$o.log" ]; then
        warn "$o: $(wc -l < "$o.log" | tr -d ' ') line(s) of compiler output — see below"
        sed 's/^/        /' "$o.log" | tail -n 40
    fi
done
[ "$COMPILE_FAILED" = "0" ] || die "compilation failed"
ok "sqlite3.o, shell.o, sqldiff.o"

step "Linking"
"$CC" "${LDFLAGS[@]}" -o "$BUILD_DIR/stage/sqlite3.real" sqlite3.o shell.o "${LIBS[@]}"
ok "sqlite3.real — $(du -h "$BUILD_DIR/stage/sqlite3.real" | cut -f1)"
"$CC" "${LDFLAGS[@]}" -o "$BUILD_DIR/stage/sqldiff" sqldiff.o sqlite3.o "${LIBS[@]}"
ok "sqldiff — $(du -h "$BUILD_DIR/stage/sqldiff" | cut -f1)"
cd "$WORK_DIR"

# ══════════════════════════════════════════════════════════════════════════════
#  VERIFICATION
#  Runs on the staged binaries. Nothing reaches android-module/ unless all of
#  it passes — the old script verified after writing there, so a rejected
#  build was still sitting in the output directory.
# ══════════════════════════════════════════════════════════════════════════════
step "Verifying compile options"

FAILED=0
fail() { err "$*"; FAILED=1; }

NL=$'\n'
BIN="$BUILD_DIR/stage/sqlite3.real"
# Captured into a variable and matched with case: piping into `grep -q` makes
# the writer die of SIGPIPE, which pipefail reports as a failed lookup.
OPTS="${NL}$("$STRINGS" -a "$BIN")${NL}"
has_line()   { case "$OPTS" in *"${NL}$1${NL}"*) return 0 ;; esac; return 1; }
has_prefix() { case "$OPTS" in *"${NL}$1"*) return 0 ;; esac; return 1; }

# The expected list is derived from the flag arrays, so a flag cannot be added
# above and forgotten here. ctime.c reports some options with their value
# (DQS=3) and some without (USE_URI), so both forms are accepted — but a
# different value is an error.
CHECKED=0
for f in "${DEFS[@]}"; do
    d="${f#-D}"
    name="${d%%=*}"
    val=""
    case "$d" in *=*) val="${d#*=}" ;; esac
    case "$name" in HAVE_*) continue ;; esac     # platform flags: checked via imports
    name="${name#SQLITE_}"
    CHECKED=$((CHECKED + 1))
    if [ -n "$val" ] && has_line "$name=$val"; then continue; fi
    if [ -n "$val" ] && has_prefix "$name="; then
        fail "compile option $name has the wrong value (wanted $val)"; continue
    fi
    has_line "$name" || fail "missing compile option: $name"
done

MUST_NOT_HAVE=( SECURE_DELETE FAST_SECURE_DELETE OMIT_DESERIALIZE OMIT_JSON )
[ "$WITH_SCANSTATUS" = "1" ]   || MUST_NOT_HAVE+=( ENABLE_STMT_SCANSTATUS )
[ "$WITH_UPDATE_LIMIT" = "1" ] || MUST_NOT_HAVE+=( ENABLE_UPDATE_DELETE_LIMIT )
for o in "${MUST_NOT_HAVE[@]}"; do
    if has_line "$o"; then
        fail "unwanted compile option present: $o"
        case "$o" in
            SECURE_DELETE) err "  (did a -DSQLITE_SECURE_DELETE=0 sneak back in? #ifdef, not value!)" ;;
            ENABLE_UPDATE_DELETE_LIMIT) err "  (it does nothing without WITH_UPDATE_LIMIT=1)" ;;
        esac
    fi
    CHECKED=$((CHECKED + 1))
done
[ "$FAILED" -eq 0 ] && ok "$CHECKED compile-option assertions passed"

step "Verifying the ELF files"

elf_check() { # <file>
    local f="$1" n hdr dyn prog sects needed lib a
    n=$(basename "$f")
    hdr=$("$READELF" -h "$f")
    dyn=$("$READELF" -d "$f")
    prog=$("$READELF" -lW "$f")
    sects=$("$READELF" -SW "$f")

    case "$hdr" in *AArch64*) ;; *) fail "$n: not an AArch64 binary" ;; esac
    case "$dyn" in *PIE*) ;; *) fail "$n: not a position-independent executable" ;; esac
    case "$dyn" in *BIND_NOW*) ;; *) fail "$n: BIND_NOW missing (-z now)" ;; esac
    case "$prog" in *GNU_RELRO*) ;; *) fail "$n: no GNU_RELRO segment (-z relro)" ;; esac
    case "$sects" in *.symtab*) fail "$n: not stripped" ;; esac

    # Every LOAD segment must be aligned for 16 KB pages. The old check looked
    # only at the lexically largest value, which hid a single 0x1000 segment.
    while read -r a; do
        [ -n "$a" ] || continue
        if [ $((a)) -lt 16384 ]; then fail "$n: LOAD segment aligned to $a (needs >= 0x4000)"; fi
    done < <(printf '%s\n' "$prog" | awk '$1 == "LOAD" {print $NF}')

    # Anything outside bionic's base libraries would not load on a phone
    # (libc++_shared.so, a stray host library, ...).
    needed=$(printf '%s\n' "$dyn" | sed -n 's/.*NEEDED.*\[\(.*\)\].*/\1/p')
    while read -r lib; do
        [ -n "$lib" ] || continue
        case "$lib" in
            libc.so | libm.so | libdl.so) ;;
            *) fail "$n: unexpected shared library dependency: $lib" ;;
        esac
    done <<< "$needed"
    info "$n NEEDED: $(printf '%s' "$needed" | tr '\n' ' ')"
}
elf_check "$BUILD_DIR/stage/sqlite3.real"
elf_check "$BUILD_DIR/stage/sqldiff"

# Platform flags leave no trace in compile_options, but they change which libc
# functions are called — so check the imports.
SYMS="${NL}$("$READELF" --dyn-syms -W "$BIN" | awk '$7 == "UND" {sub(/@.*/, "", $8); print $8}')${NL}"
for f in "${PLATFORM_FLAGS[@]}"; do
    name="${f#-D}"; name="${name%%=*}"
    imp=$(platform_import "$name")
    [ -n "$imp" ] || continue
    case "$SYMS" in
        *"${NL}$imp${NL}"*) ;;
        *) fail "$name had no effect: sqlite3.real does not call $imp()" ;;
    esac
done
[ "$FAILED" -eq 0 ] && ok "ELF, 16 KB alignment, dependencies and platform imports OK"

# ── Functional test on the build machine ──────────────────────────────────────
# The ARM binary cannot run here, but the same sources with the same SQLite
# flags can. This catches the kind of mistake the compile-option list cannot:
# a feature that is "enabled" but does not work (UPDATE ... LIMIT, secure_delete
# default, FTS query syntax, ...). Platform HAVE_* flags are left out on purpose;
# they describe bionic, not the build machine.
if [ "$SKIP_HOST_TEST" = "1" ] || [ -z "$HOST_CC" ]; then
    if [ "$SKIP_HOST_TEST" = "1" ]; then
        warn "host functional test skipped (SKIP_HOST_TEST=1)"
    else
        warn "no host C compiler — functional test skipped (set HOST_CC, or SKIP_HOST_TEST=1)"
    fi
    [ "$WITH_UPDATE_LIMIT" = "1" ] && warn "UPDATE/DELETE LIMIT is therefore NOT verified"
else
    step "Functional test (host build, same SQLite flags)"
    HOST_DEFS=()
    for f in "${DEFS[@]}"; do
        case "$f" in -DHAVE_*) ;; *) HOST_DEFS+=("$f") ;; esac
    done
    H="$BUILD_DIR/host"
    mkdir -p "$H"
    if ! ( cd "$H" \
           && "$HOST_CC" -O0 -w "${HOST_DEFS[@]}" -I "$BUILD_DIR/src" -c "$BUILD_DIR/src/sqlite3.c" -o sqlite3.o \
           && "$HOST_CC" -O0 -w "${HOST_DEFS[@]}" -I "$BUILD_DIR/src" -o sqlite3 "$BUILD_DIR/src/shell.c" sqlite3.o -lm -lpthread \
           && "$HOST_CC" -O0 -w "${HOST_DEFS[@]}" -I "$BUILD_DIR/src" -o sqldiff "$BUILD_DIR/src/sqldiff.c" sqlite3.o -lm -lpthread ) > "$H/build.log" 2>&1; then
        sed 's/^/        /' "$H/build.log" | tail -n 20 >&2
        die "host build failed"
    fi

    TESTS=0
    t_sql() { # <description> <expected> <sql>
        local got
        TESTS=$((TESTS + 1))
        got=$(printf '%s\n' "$3" | "$H/sqlite3" -batch :memory: 2>&1) || true
        [ "$got" = "$2" ] || fail "$1: expected [$2], got [$got]"
    }
    t_err() { # <description> <sql> — the statement must be rejected
        TESTS=$((TESTS + 1))
        if printf '%s\n' "$2" | "$H/sqlite3" -batch :memory: >/dev/null 2>&1; then
            fail "$1: statement was accepted"
        fi
    }

    t_sql "version"            "$SQLITE_VERSION" "SELECT sqlite_version();"
    t_sql "secure_delete off"  "0"  "PRAGMA secure_delete;"
    t_sql "foreign_keys on"    "1"  "PRAGMA foreign_keys;"
    t_sql "FTS5"               "hello world" \
          "CREATE VIRTUAL TABLE t USING fts5(c); INSERT INTO t VALUES('hello world'); SELECT * FROM t WHERE t MATCH 'hello';"
    t_sql "FTS4 enhanced query syntax" "hello world" \
          "CREATE VIRTUAL TABLE t USING fts4(c); INSERT INTO t VALUES('hello world'); SELECT * FROM t WHERE t MATCH 'hello AND (world OR earth)';"
    t_sql "R-Tree"             "1" \
          "CREATE VIRTUAL TABLE g USING rtree(id, a, b); INSERT INTO g VALUES(1, 0, 10); SELECT id FROM g WHERE a <= 5 AND b >= 5;"
    t_sql "Geopoly"            "A" \
          "CREATE VIRTUAL TABLE z USING geopoly(name); INSERT INTO z(name,_shape) VALUES('A','[[0,0],[1,0],[1,1],[0,1],[0,0]]'); SELECT name FROM z WHERE geopoly_contains_point(_shape, 0.5, 0.5);"
    t_sql "JSON"               "1"   "SELECT json_extract('{\"a\":1}', '\$.a');"
    t_sql "math functions"     "1.0" "SELECT round(ln(exp(1)), 6);"
    t_sql "percentile"         "2.0" "SELECT median(column1) FROM (VALUES(1),(2),(9));"
    t_sql "soundex"            "R163" "SELECT soundex('Robert');"
    t_sql "dbstat"             "1"   "CREATE TABLE a(x); SELECT count(*) > 0 FROM dbstat;"
    t_sql "bytecode vtab"      "1"   "SELECT count(*) > 0 FROM bytecode('SELECT 1');"
    t_sql "sqlite_offset()"    "1"   "CREATE TABLE a(x); INSERT INTO a VALUES(1); SELECT sqlite_offset(x) > 0 FROM a;"
    t_sql "legacy double-quoted strings (DQS=3)" "abc" 'SELECT "abc";'
    if [ "$WITH_UPDATE_LIMIT" = "1" ]; then
        t_sql "DELETE ... LIMIT" "2,3" \
              "CREATE TABLE a(x); INSERT INTO a VALUES(1),(2),(3); DELETE FROM a ORDER BY x LIMIT 1; SELECT group_concat(x) FROM a;"
    else
        t_err "DELETE ... LIMIT unavailable without WITH_UPDATE_LIMIT" \
              "CREATE TABLE a(x); DELETE FROM a LIMIT 1;"
    fi

    # sqldiff
    TESTS=$((TESTS + 1))
    rm -f "$H/a.db" "$H/b.db"
    printf 'CREATE TABLE t(x); INSERT INTO t VALUES(1);\n'          | "$H/sqlite3" "$H/a.db"
    printf 'CREATE TABLE t(x); INSERT INTO t VALUES(1),(2);\n'      | "$H/sqlite3" "$H/b.db"
    got=$("$H/sqldiff" --summary "$H/a.db" "$H/b.db" 2>&1) || true
    [ "$got" = "t: 0 changes, 1 inserts, 0 deletes, 1 unchanged" ] || fail "sqldiff --summary: got [$got]"

    # Every option the host build reports should be in the ARM binary too.
    HOST_OPTS=$(printf 'PRAGMA compile_options;\n' | "$H/sqlite3" -batch :memory:)
    MISSING=()
    while IFS= read -r o; do
        case "$o" in ''|COMPILER=*) continue ;; esac
        has_line "$o" || MISSING+=("$o")
    done <<< "$HOST_OPTS"
    if [ ${#MISSING[@]} -gt 0 ]; then
        warn "reported by the host build but not found in sqlite3.real: ${MISSING[*]}"
    fi

    [ "$FAILED" -eq 0 ] && ok "$TESTS functional tests passed"
fi

[ "$FAILED" -eq 0 ] || die "Verification failed — nothing was written to $OUT_DIR"

# ── Publish ───────────────────────────────────────────────────────────────────
step "Writing android-module/"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/sqlite3.real" "$OUT_DIR/sqldiff" "$OUT_DIR/SHA256SUMS" "$OUT_DIR/BUILDINFO"
chmod 755 "$BUILD_DIR/stage/sqlite3.real" "$BUILD_DIR/stage/sqldiff"
mv "$BUILD_DIR/stage/sqlite3.real" "$BUILD_DIR/stage/sqldiff" "$OUT_DIR/"
( cd "$OUT_DIR" && "${SHA256[@]}" sqlite3.real sqldiff > SHA256SUMS )

{
    printf 'sqlite_version=%s\n' "$SQLITE_VERSION"
    printf 'sqlite_source_id=%s\n' "$SOURCE_ID"
    printf 'ndk_revision=%s\n' "${NDK_REV:-unknown}"
    printf 'clang=%s\n' "$CLANG_VER"
    printf 'api=%s\n' "$API"
    printf 'with_scanstatus=%s\n' "$WITH_SCANSTATUS"
    printf 'with_update_limit=%s\n' "$WITH_UPDATE_LIMIT"
    printf 'built=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'defines=%s\n' "${DEFS[*]}"
} > "$OUT_DIR/BUILDINFO"

while read -r h f; do info "$f  ${h:0:16}…"; done < "$OUT_DIR/SHA256SUMS"
ok "SHA256SUMS and BUILDINFO written"

# ── Optional install into a module tree ──────────────────────────────────────
# Rewrites KEY=VALUE in a file. `|| [ -n "$line" ]` keeps a last line that has
# no trailing newline; a plain `while read` silently drops it.
set_kv() { # <file> <key> <value>
    local file="$1" key="$2" value="$3" tmp="$1.tmp.$$" line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "$key="*) printf '%s=%s\n' "$key" "$value" ;;
            *)        printf '%s\n' "$line" ;;
        esac
    done < "$file" > "$tmp"
    mv -f "$tmp" "$file"
}

if [ -n "$INSTALL_DIR" ]; then
    step "Installing into $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/system/bin"
    install -m 755 "$OUT_DIR/sqlite3.real" "$INSTALL_DIR/system/bin/sqlite3.real"
    install -m 755 "$OUT_DIR/sqldiff"      "$INSTALL_DIR/system/bin/sqldiff"
    ok "binaries copied"

    PROP="$INSTALL_DIR/module.prop"
    CUR_VER=$(sed -n 's/^version=//p' "$PROP" | sed -n '1p')
    CUR_BASE="${CUR_VER#v}"
    CUR_BASE="${CUR_BASE%%-*}"

    if [ -z "$CUR_VER" ]; then
        warn "module.prop has no version= line — version not updated"
    elif [ "$CUR_BASE" = "$SQLITE_VERSION" ]; then
        # The old script reset version= to v$SQLITE_VERSION and bumped
        # versionCode on every run: v3.53.4-r2 became v3.53.4 and running
        # --install twice skipped a versionCode.
        info "module.prop stays at $CUR_VER — same SQLite version."
        info "If this rebuild is a release, bump the -rN revision and versionCode yourself."
    else
        OLD_CODE=$(sed -n 's/^versionCode=//p' "$PROP" | sed -n '1p')
        case "$OLD_CODE" in '' | *[!0-9]*) die "versionCode in $PROP is not a number: '$OLD_CODE'" ;; esac
        NEW_VER="v$SQLITE_VERSION"
        NEW_CODE=$((OLD_CODE + 1))
        set_kv "$PROP" version "$NEW_VER"
        set_kv "$PROP" versionCode "$NEW_CODE"
        ok "module.prop: $CUR_VER -> $NEW_VER (versionCode $OLD_CODE -> $NEW_CODE)"

        CUR_VER_RE="${CUR_VER//./\\.}"
        if [ -f "$INSTALL_DIR/update.json" ]; then
            sed -i.bak \
                -e "s/$CUR_VER_RE/$NEW_VER/g" \
                -e "s/\"versionCode\": *[0-9][0-9]*/\"versionCode\": $NEW_CODE/" \
                "$INSTALL_DIR/update.json"
            rm -f "$INSTALL_DIR/update.json.bak"
            ok "update.json: version, versionCode and zipUrl updated"
        fi

        HTML="$INSTALL_DIR/webroot/index.html"
        if [ -f "$HTML" ]; then
            CUR_BASE_RE="${CUR_BASE//./\\.}"
            sed -i.bak \
                -e "s#<span class=\"version-badge\">v$CUR_BASE_RE</span>#<span class=\"version-badge\">v$SQLITE_VERSION</span>#" \
                -e "s#SQLite3 v$CUR_BASE_RE · #SQLite3 v$SQLITE_VERSION · #" \
                "$HTML"
            rm -f "$HTML.bak"
            if grep -q "version-badge\">v$SQLITE_VERSION<" "$HTML"; then
                ok "WebUI version badge and footer updated"
            else
                warn "WebUI version badge not found in $HTML — update it by hand"
            fi
        fi
        warn "Add a CHANGELOG entry for $NEW_VER"
    fi

    if [ "$MAKE_ZIP" = "1" ]; then
        step "Packing the module"
        MOD_ID=$(sed -n 's/^id=//p' "$PROP" | sed -n '1p')
        MOD_VER=$(sed -n 's/^version=//p' "$PROP" | sed -n '1p')
        [ -n "$MOD_ID" ] && [ -n "$MOD_VER" ] || die "module.prop needs id= and version= for --zip"
        for f in module.prop customize.sh META-INF/com/google/android/update-binary \
                 META-INF/com/google/android/updater-script system/bin/sqlite3 system/bin/sqlite3.real; do
            [ -f "$INSTALL_DIR/$f" ] || die "missing from the module tree: $f"
        done
        # Only module content. A repository checkout also holds README, build.sh,
        # update.json, .git, ... none of which belong in the installable zip.
        ENTRIES=()
        for f in META-INF system files webroot module.prop customize.sh \
                 post-fs-data.sh service.sh uninstall.sh action.sh; do
            [ -e "$INSTALL_DIR/$f" ] && ENTRIES+=("$f")
        done
        ZIP_OUT="$WORK_DIR/${MOD_ID}-${MOD_VER}.zip"
        rm -f "$ZIP_OUT"
        ( cd "$INSTALL_DIR" && zip -qr9 -X "$ZIP_OUT" "${ENTRIES[@]}" -x '*.bak' '*.tmp.*' '*/.DS_Store' )
        unzip -l "$ZIP_OUT" | grep -q ' module.prop$' || die "module.prop is not at the root of $ZIP_OUT"
        ok "$(basename "$ZIP_OUT") — $(du -h "$ZIP_OUT" | cut -f1), $("${SHA256[@]}" "$ZIP_OUT" | cut -c1-16)…"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n%s╔═══════════════════════════════════════╗%s\n' "$W" "$N"
printf '%s║            Build complete             ║%s\n' "$W" "$N"
printf '%s╚═══════════════════════════════════════╝%s\n\n' "$W" "$N"

info "SQLite version: $SQLITE_VERSION"
info "NDK / API:      ${NDK_REV:-unknown} / $API"
info "Output dir:     $OUT_DIR"
[ -z "${ZIP_OUT:-}" ] || info "Release zip:    $ZIP_OUT"
info "Time:           $(( $(date +%s) - START_TIME )) s"
printf '\n'
ls -lh "$OUT_DIR/"
printf '\n'
if [ -z "$INSTALL_DIR" ]; then
    info "Copy these into the module:"
    printf '  %ssystem/bin/sqlite3.real%s  ← main binary\n' "$G" "$N"
    printf '  %ssystem/bin/sqldiff%s       ← diff tool\n' "$G" "$N"
    printf '  or re-run with: %s./build.sh --install /path/to/module%s\n\n' "$G" "$N"
fi
