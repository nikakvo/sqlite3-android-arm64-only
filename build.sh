#!/usr/bin/env bash
# build.sh — SQLite3 ARM64 Android module builder
# Tears Burn / nikakvo
#
# Usage:
#   ./build.sh                      build into ./android-module/
#   ./build.sh --install ../module  build, then copy the binaries into the
#                                   module tree and update its module.prop
#
# Environment:
#   TOOLCHAIN=/path/to/ndk/toolchains/llvm/prebuilt/linux-x86_64
#   API=21                          minimum Android API level
#   WITH_SCANSTATUS=1               re-enable SQLITE_ENABLE_STMT_SCANSTATUS
#                                   (adds per-step counters — costs performance)
#
# Expects in the current directory:
#   sqlite-amalgamation-*.zip
#   sqlite-src-*.zip

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

ok()   { printf "${G}  [OK]${N}    %s\n" "$*"; }
err()  { printf "${R}  [ERR]${N}   %s\n" "$*" >&2; }
info() { printf "${C}  [INFO]${N}  %s\n" "$*"; }
warn() { printf "${Y}  [WARN]${N}  %s\n" "$*"; }
step() { printf "\n${W}── %s${N}\n" "$*"; }

die()  { err "$*"; exit 1; }

# ── Arguments ─────────────────────────────────────────────────────────────────
INSTALL_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --install) INSTALL_DIR="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Toolchain ─────────────────────────────────────────────────────────────────
API="${API:-21}"

if [ -z "${TOOLCHAIN:-}" ]; then
    for cand in \
        "${ANDROID_NDK_HOME:-}/toolchains/llvm/prebuilt/linux-x86_64" \
        "${ANDROID_NDK_ROOT:-}/toolchains/llvm/prebuilt/linux-x86_64" \
        "$HOME"/android-ndk-*/toolchains/llvm/prebuilt/linux-x86_64 \
        /opt/android-ndk*/toolchains/llvm/prebuilt/linux-x86_64; do
        [ -d "$cand" ] && { TOOLCHAIN="$cand"; break; }
    done
fi
TOOLCHAIN="${TOOLCHAIN:-/home/tears/android-ndk-r26d/toolchains/llvm/prebuilt/linux-x86_64}"
CC="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang"

WORK_DIR="$(pwd)"
BUILD_DIR="$WORK_DIR/.build_tmp"
OUT_DIR="$WORK_DIR/android-module"

printf "\n${W}╔═══════════════════════════════════════╗${N}\n"
printf "${W}║  SQLite3 ARM64 Android Module Build   ║${N}\n"
printf "${W}╚═══════════════════════════════════════╝${N}\n\n"

step "Checking toolchain"
[ -f "$CC" ] || die "Compiler not found: $CC
  Set TOOLCHAIN, ANDROID_NDK_HOME or ANDROID_NDK_ROOT.
  Example: TOOLCHAIN=/path/to/ndk/toolchains/llvm/prebuilt/linux-x86_64 ./build.sh"
ok "Compiler: $CC"
info "Clang:    $("$CC" --version | head -n 1)"

# ── Source archives ───────────────────────────────────────────────────────────
step "Locating source archives"

AMALG_ZIP=$(ls "$WORK_DIR"/sqlite-amalgamation-*.zip 2>/dev/null | sort -V | tail -1 || true)
SRC_ZIP=$(ls "$WORK_DIR"/sqlite-src-*.zip 2>/dev/null | sort -V | tail -1 || true)

[ -n "$AMALG_ZIP" ] || die "sqlite-amalgamation-*.zip not found in $WORK_DIR
  Download from: https://www.sqlite.org/download.html"
[ -n "$SRC_ZIP" ] || die "sqlite-src-*.zip not found in $WORK_DIR
  Download from: https://www.sqlite.org/download.html"

# SQLite release archives are named with the packed version number XYYZZPP:
#   3530400 -> 3.53.4      (X=3, YY=53, ZZ=04, PP=00)
# The old decoder divided by 1000 and produced "3.530.400".
decode_version() {
    local v="$1"
    printf '%d.%d.%d' \
        $(( v / 1000000 )) \
        $(( (v % 1000000) / 10000 )) \
        $(( (v % 10000) / 100 ))
}

RAW_VER=$(basename "$AMALG_ZIP" | sed 's/[^0-9]//g')
if [ ${#RAW_VER} -ge 7 ]; then
    SQLITE_VERSION=$(decode_version "$RAW_VER")
else
    SQLITE_VERSION="unknown"
    warn "Could not decode a version from $(basename "$AMALG_ZIP")"
fi

info "Amalgamation: $(basename "$AMALG_ZIP")"
info "Source:       $(basename "$SRC_ZIP")"
info "Version:      SQLite $SQLITE_VERSION"

# ── Prepare ───────────────────────────────────────────────────────────────────
step "Preparing build directory"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

info "Extracting amalgamation..."
unzip -q "$AMALG_ZIP" -d "$BUILD_DIR/amalg"

AMALG_DIR=$(find "$BUILD_DIR/amalg" -name sqlite3.c -exec dirname {} \; | head -1)
[ -n "$AMALG_DIR" ] || die "sqlite3.c not found in the amalgamation zip"
ok "sqlite3.c, shell.c found"

info "Extracting tool sources..."
unzip -q "$SRC_ZIP" \
    "*/tool/sqldiff.c" \
    "*/ext/misc/sqlite3_stdio.h" \
    "*/ext/misc/sqlite3_stdio.c" \
    -d "$BUILD_DIR/src" 2>/dev/null || true

SQLDIFF=$(find "$BUILD_DIR/src" -name sqldiff.c    | head -1)
STDIO_H=$(find "$BUILD_DIR/src" -name sqlite3_stdio.h | head -1)
STDIO_C=$(find "$BUILD_DIR/src" -name sqlite3_stdio.c | head -1)

[ -n "$SQLDIFF" ] || die "sqldiff.c not found in the source zip"
[ -n "$STDIO_H" ] || die "sqlite3_stdio.h not found in the source zip"
ok "sqldiff.c found"
ok "sqlite3_stdio.h found"

cp "$AMALG_DIR/sqlite3.c" "$AMALG_DIR/sqlite3.h" "$AMALG_DIR/shell.c" "$BUILD_DIR/"
cp "$SQLDIFF" "$STDIO_H" "$BUILD_DIR/"
[ -n "$STDIO_C" ] && cp "$STDIO_C" "$BUILD_DIR/"

# ══════════════════════════════════════════════════════════════════════════════
#  COMPILE FLAGS
#
#  Two rules learned the hard way:
#
#  1. Many SQLite options are tested with #ifdef, NOT by value. Writing
#     -DSQLITE_SECURE_DELETE=0 DEFINES the macro and therefore ENABLES secure
#     delete — the exact opposite of the intent. btree.c:
#         #if defined(SQLITE_SECURE_DELETE)
#             pBt->btsFlags |= BTS_SECURE_DELETE;
#     If you don't want a feature, omit the flag entirely.
#
#  2. Some flags no longer exist. SQLITE_ENABLE_JSON1 and
#     SQLITE_ENABLE_DESERIALIZE appear nowhere in the SQLite source any more;
#     JSON is built in since 3.38 and deserialize since 3.36 (disable with
#     SQLITE_OMIT_DESERIALIZE). Passing them does nothing, and
#     sqlite_compileoption_used() on them returns 0, which looks like a
#     broken build.
#
#  Every flag below is verified against the produced binary at the end of
#  this script.
# ══════════════════════════════════════════════════════════════════════════════

CORE_FLAGS=(
    -DSQLITE_THREADSAFE=1
    -DSQLITE_USE_URI=1
    -DSQLITE_OMIT_LOAD_EXTENSION
    -DSQLITE_DQS=0
    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS
    -DSQLITE_HAVE_ISNAN
    -DHAVE_USLEEP=1
    -DHAVE_MALLOC_USABLE_SIZE=1
    # NOTE: SQLITE_SECURE_DELETE is deliberately absent — see rule 1 above.
)

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
    # phones. Both were 0 before, which disabled it entirely.
    -DSQLITE_MAX_WORKER_THREADS=4
    -DSQLITE_DEFAULT_WORKER_THREADS=2
    -DSQLITE_ENABLE_SORTER_REFERENCES
    # NOTE: SQLITE_MAX_EXPR_DEPTH=1000 removed — that is already the default.
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
    -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT
    -DSQLITE_ENABLE_EXPLAIN_COMMENTS
    -DSQLITE_ENABLE_UNKNOWN_SQL_FUNCTION
    -DSQLITE_ENABLE_NULL_TRIM
    -DSQLITE_ENABLE_API_ARMOR
    -DSQLITE_SOUNDEX
    # NOTE: SQLITE_ENABLE_JSON1 and SQLITE_ENABLE_DESERIALIZE removed —
    # both are no-ops on modern SQLite. The features themselves are built in.
)

# STMT_SCANSTATUS adds counters to every sqlite3_step() call. It powers
# .scanstats, but you pay for it on every query whether you use it or not.
if [ "${WITH_SCANSTATUS:-0}" = "1" ]; then
    FEATURE_FLAGS+=( -DSQLITE_ENABLE_STMT_SCANSTATUS )
    warn "STMT_SCANSTATUS enabled — .scanstats works, every query pays for it"
fi

CFLAGS=(
    -O2
    -march=armv8-a
    -fPIE -pie
    -fuse-ld=lld
    -fomit-frame-pointer
    -fvisibility=hidden
    -ffunction-sections
    -fdata-sections
    -fstack-protector-strong
)

# shellcheck disable=SC2054  # the commas are part of -Wl, options
LDFLAGS=(
    -Wl,--gc-sections
    # --as-needed drops libraries nothing actually references. Without it the
    # binary carried a NEEDED entry for liblog.so despite never calling a
    # single __android_log_* symbol.
    -Wl,--as-needed
    -Wl,--strip-all
    -Wl,-O2
    -Wl,--build-id=none
    -Wl,-z,relro
    -Wl,-z,now
    # 16 KB page size devices (Pixel 8+, and required by Google from Nov 2025)
    -Wl,-z,max-page-size=16384
    -Wl,-z,common-page-size=16384
)

LIBS=(-ldl -lm)

ALL_FLAGS=("${CFLAGS[@]}" "${CORE_FLAGS[@]}" "${PERF_FLAGS[@]}" "${FEATURE_FLAGS[@]}" "${LDFLAGS[@]}")

cd "$BUILD_DIR"

# ── Build ─────────────────────────────────────────────────────────────────────
step "Building sqlite3.real"
"$CC" "${ALL_FLAGS[@]}" -o "$OUT_DIR/sqlite3.real" sqlite3.c shell.c "${LIBS[@]}"
chmod 755 "$OUT_DIR/sqlite3.real"
ok "sqlite3.real — $(du -h "$OUT_DIR/sqlite3.real" | cut -f1)"

step "Building sqldiff"
"$CC" "${ALL_FLAGS[@]}" -o "$OUT_DIR/sqldiff" sqldiff.c sqlite3.c "${LIBS[@]}"
chmod 755 "$OUT_DIR/sqldiff"
ok "sqldiff — $(du -h "$OUT_DIR/sqldiff" | cut -f1)"

cd "$WORK_DIR"
rm -rf "$BUILD_DIR"

# ══════════════════════════════════════════════════════════════════════════════
#  VERIFICATION
#  The compile-option list is embedded in the binary, so we can read back what
#  actually landed instead of trusting the command line. This is what would
#  have caught SECURE_DELETE being on for four releases.
# ══════════════════════════════════════════════════════════════════════════════
step "Verifying the produced binary"

# Read the option strings once, wrapped in newlines so an exact-line match is a
# plain substring test.
#
# Do NOT pipe this into `grep -q`: grep exits at the first match, the writer on
# the left then dies of SIGPIPE (141), and with `set -o pipefail` a SUCCESSFUL
# lookup is reported as a failed pipeline. That made every assertion below fail,
# including the MUST_NOT_HAVE ones, so a bad build would have passed silently.
# The case statement is a shell builtin — no pipe, no subprocess, no surprises.
NL=$'\n'
OPTS="${NL}$(strings -a "$OUT_DIR/sqlite3.real")${NL}"

has_opt() {
    case "$OPTS" in
        *"${NL}$1${NL}"*) return 0 ;;
    esac
    return 1
}
FAILED=0

MUST_HAVE=(
    THREADSAFE=1 USE_URI OMIT_LOAD_EXTENSION DQS=0
    LIKE_DOESNT_MATCH_BLOBS HAVE_ISNAN TEMP_STORE=2
    DEFAULT_FOREIGN_KEYS DEFAULT_SYNCHRONOUS=1 DEFAULT_WAL_SYNCHRONOUS=1
    STMTJRNL_SPILL=-1
    DEFAULT_MEMSTATUS=0 DEFAULT_CACHE_SIZE=-16000
    DEFAULT_MMAP_SIZE=268435456 MAX_MMAP_SIZE=1099511627776
    MAX_WORKER_THREADS=4 DEFAULT_WORKER_THREADS=2
    ENABLE_SORTER_REFERENCES
    ENABLE_FTS3_PARENTHESIS ENABLE_FTS4 ENABLE_FTS5
    ENABLE_RTREE ENABLE_GEOPOLY ENABLE_STAT4 ENABLE_MATH_FUNCTIONS
    ENABLE_OFFSET_SQL_FUNC
    ENABLE_SESSION ENABLE_PREUPDATE_HOOK ENABLE_SNAPSHOT ENABLE_RBU
    ENABLE_UNLOCK_NOTIFY
    ENABLE_DBSTAT_VTAB ENABLE_DBPAGE_VTAB ENABLE_STMTVTAB
    ENABLE_BYTECODE_VTAB
    ENABLE_COLUMN_METADATA ENABLE_NORMALIZE ENABLE_UPDATE_DELETE_LIMIT
    ENABLE_EXPLAIN_COMMENTS ENABLE_UNKNOWN_SQL_FUNCTION
    ENABLE_NULL_TRIM ENABLE_API_ARMOR SOUNDEX
)

# Reported by ctime.c only on newer SQLite releases — warn, do not fail.
SHOULD_HAVE=( ENABLE_PERCENTILE ENABLE_CARRAY )

MUST_NOT_HAVE=( SECURE_DELETE FAST_SECURE_DELETE OMIT_DESERIALIZE )
[ "${WITH_SCANSTATUS:-0}" = "1" ] || MUST_NOT_HAVE+=( ENABLE_STMT_SCANSTATUS )

for o in "${MUST_HAVE[@]}"; do
    has_opt "$o" || { err "missing compile option: $o"; FAILED=1; }
done
for o in "${SHOULD_HAVE[@]}"; do
    has_opt "$o" || warn "compile option not reported: $o (older SQLite may not list it)"
done
for o in "${MUST_NOT_HAVE[@]}"; do
    if has_opt "$o"; then
        err "unwanted compile option present: $o"
        [ "$o" = "SECURE_DELETE" ] && err "  (did a -DSQLITE_SECURE_DELETE=0 sneak back in? #ifdef, not value!)"
        FAILED=1
    fi
done

[ "$FAILED" -eq 0 ] && ok "all $(( ${#MUST_HAVE[@]} + ${#MUST_NOT_HAVE[@]} )) compile-option assertions passed"

# Shared library dependencies
step "Linked libraries"
NEEDED=$(readelf -d "$OUT_DIR/sqlite3.real" 2>/dev/null \
         | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p' | tr '\n' ' ')
info "NEEDED: ${NEEDED:-<none>}"
case "$NEEDED" in
    *liblog*) warn "liblog.so is linked but SQLite never calls it — is --as-needed still in LDFLAGS?" ;;
esac

# ELF sanity
step "ELF checks"
FILE_INFO=$(file -b "$OUT_DIR/sqlite3.real")
info "$FILE_INFO"
case "$FILE_INFO" in
    *"ARM aarch64"*) ok "architecture: aarch64" ;;
    *) err "wrong architecture!"; FAILED=1 ;;
esac
case "$FILE_INFO" in
    *"pie executable"*) ok "position independent executable" ;;
    *) warn "not a PIE binary" ;;
esac

ALIGN=$(readelf -lW "$OUT_DIR/sqlite3.real" 2>/dev/null \
        | awk '/LOAD/ {print $NF}' | sort -u | tail -1)
if [ "$ALIGN" = "0x4000" ]; then
    ok "16 KB page alignment"
else
    warn "segment alignment is $ALIGN — expected 0x4000 for 16 KB page devices"
fi

[ "$FAILED" -eq 0 ] || die "Verification failed — not shipping this build."

# ── Checksums ─────────────────────────────────────────────────────────────────
step "Checksums"
( cd "$OUT_DIR" && sha256sum sqlite3.real sqldiff > SHA256SUMS )
while read -r h f; do info "$f  ${h:0:16}…"; done < "$OUT_DIR/SHA256SUMS"
ok "written to android-module/SHA256SUMS"

# ── Optional install into a module tree ──────────────────────────────────────
if [ -n "$INSTALL_DIR" ]; then
    step "Installing into $INSTALL_DIR"
    [ -d "$INSTALL_DIR" ] || die "Not a directory: $INSTALL_DIR"
    [ -f "$INSTALL_DIR/module.prop" ] || die "No module.prop in $INSTALL_DIR"

    mkdir -p "$INSTALL_DIR/system/bin"
    install -m 755 "$OUT_DIR/sqlite3.real" "$INSTALL_DIR/system/bin/sqlite3.real"
    install -m 755 "$OUT_DIR/sqldiff"      "$INSTALL_DIR/system/bin/sqldiff"
    ok "binaries copied"

    if [ "$SQLITE_VERSION" != "unknown" ]; then
        OLD_CODE=$(sed -n 's/^versionCode=//p' "$INSTALL_DIR/module.prop" | head -1)
        NEW_CODE=$(( ${OLD_CODE:-0} + 1 ))
        tmp="$INSTALL_DIR/module.prop.tmp"
        while IFS= read -r line; do
            case "$line" in
                version=*)     printf 'version=v%s\n' "$SQLITE_VERSION" ;;
                versionCode=*) printf 'versionCode=%s\n' "$NEW_CODE" ;;
                *)             printf '%s\n' "$line" ;;
            esac
        done < "$INSTALL_DIR/module.prop" > "$tmp"
        mv -f "$tmp" "$INSTALL_DIR/module.prop"
        ok "module.prop → v$SQLITE_VERSION (versionCode $NEW_CODE)"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${W}╔═══════════════════════════════════════╗${N}\n"
printf "${W}║            Build complete             ║${N}\n"
printf "${W}╚═══════════════════════════════════════╝${N}\n\n"

info "SQLite version: $SQLITE_VERSION"
info "Output dir:     $OUT_DIR"
printf "\n"
ls -lh "$OUT_DIR/"
printf "\n"
if [ -z "$INSTALL_DIR" ]; then
    info "Copy these into the module:"
    printf "  ${G}system/bin/sqlite3.real${N}  ← main binary\n"
    printf "  ${G}system/bin/sqldiff${N}       ← diff tool\n"
    printf "  or re-run with: ${G}./build.sh --install /path/to/module${N}\n\n"
fi
