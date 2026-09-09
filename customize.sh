#!/system/bin/sh
# SQLite3 (Arm64 Only) — installer

# ── Architecture check ────────────────────────────────────────────────────────
ARCH=$(uname -m 2>/dev/null)
ABI=$(getprop ro.product.cpu.abi 2>/dev/null)

case "$ARCH$ABI" in
    *aarch64* | *arm64*) ;;
    *)
        ui_print "*******************************"
        ui_print "  ERROR: Incompatible device!  "
        ui_print "  This module requires Arm64.  "
        ui_print "  uname -m : $ARCH"
        ui_print "  cpu.abi  : $ABI"
        ui_print "*******************************"
        abort "Installation aborted."
        ;;
esac

MOD_VER=$(sed -n 's/^version=//p' "$MODPATH/module.prop" | head -1)

ui_print " "
ui_print "***********************************"
ui_print "  SQLite3 $MOD_VER — Arm64 Only"
ui_print "  by Tears Burn"
ui_print "***********************************"
ui_print " "
ui_print "* Target: /system/bin/"
ui_print " "

# A running sqlite3 keeps the old binary mapped; ask it to exit before the
# mount changes underneath it.
command -v pkill >/dev/null 2>&1 && pkill -x sqlite3 2>/dev/null

# ── Package integrity ─────────────────────────────────────────────────────────
# Without sqlite3.real the module is dead weight: the wrapper would install
# fine and then fail on every invocation. Fail loudly here instead.
for f in sqlite3 sqlite3.real; do
    if [ ! -f "$MODPATH/system/bin/$f" ]; then
        ui_print " "
        ui_print "  ! FATAL: $f is missing from this package."
        ui_print "    The zip is incomplete or was repacked incorrectly."
        abort "Broken package — installation aborted."
    fi
done

# ── Permissions ───────────────────────────────────────────────────────────────
ui_print "* Setting permissions..."
set_perm_recursive "$MODPATH" 0 0 0755 0644

for f in sqlite3 sqlite3.real sqldiff sqlite3-tool sqlite3-doctor; do
    if [ -f "$MODPATH/system/bin/$f" ]; then
        set_perm "$MODPATH/system/bin/$f" 0 0 0755
        ui_print "  + $f"
    else
        # Optional companions — the module still works without them.
        ui_print "  ! missing (optional): $f"
    fi
done

# ── Sanity check on the shipped binary ────────────────────────────────────────
# The module directory is not mounted yet, so run it straight from $MODPATH.
BIN_VER=$("$MODPATH/system/bin/sqlite3.real" --version 2>/dev/null | cut -d' ' -f1)

if [ -z "$BIN_VER" ]; then
    ui_print " "
    ui_print "  ! FATAL: sqlite3.real will not execute on this device."
    ui_print "    Wrong architecture, or the binary is corrupt."
    ui_print "    uname -m : $ARCH"
    ui_print "    cpu.abi  : $ABI"
    abort "Unusable binary — installation aborted."
fi

ui_print " "
ui_print "* Binary check: SQLite $BIN_VER OK"

# Compare only the SQLite part: module.prop may carry a module revision
# suffix (v3.53.4-r1) that the binary knows nothing about.
MOD_VER_BASE="${MOD_VER#v}"
MOD_VER_BASE="${MOD_VER_BASE%%-*}"

if [ "$BIN_VER" != "$MOD_VER_BASE" ]; then
    ui_print "  ! WARNING: module.prop says $MOD_VER but the binary is $BIN_VER."
    ui_print "    The package was assembled from mismatched parts."
fi

if "$MODPATH/system/bin/sqlite3.real" ":memory:" \
    "PRAGMA compile_options;" 2>/dev/null | grep -qx "SECURE_DELETE"; then
    ui_print "  ! WARNING: this build has SECURE_DELETE enabled."
    ui_print "    Every DELETE zero-fills its freed pages and VACUUM does extra"
    ui_print "    write work. Rebuild without -DSQLITE_SECURE_DELETE (the flag is"
    ui_print "    tested with #ifdef, so =0 still turns it ON)."
fi

ui_print " "
ui_print "* Done! Reboot to activate."
ui_print " "
