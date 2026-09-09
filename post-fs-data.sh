#!/system/bin/sh
# Only fast, critical work belongs here — post-fs-data blocks boot for EVERY
# module, so any delay adds up with the rest of your module list and can trip
# a bootloop protector.
#
# customize.sh already sets these permissions; this is a cheap safety net for
# the case where the module directory was updated by hand.

MODDIR=${0%/*}

for f in sqlite3 sqlite3.real sqldiff sqlite3-tool sqlite3-doctor; do
    [ -f "$MODDIR/system/bin/$f" ] && chmod 755 "$MODDIR/system/bin/$f" 2>/dev/null
done
exit 0
