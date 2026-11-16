#!/system/bin/sh
# SQLite3 Android Arm64 - uninstall cleanup
# Removes files deployed outside the module directory.
# system/bin/* is unmounted automatically by Magisk/KSU.

rm -f /data/local/.sqliterc-full

# sqlite3-tool writes a backup to "<destination>.sqlite3-tool-<pid>.tmp" and
# removes it itself; these only exist if it was killed mid-backup. Neither tool
# ever wrote to /data/local/tmp, which the old cleanup tried to clear.
#
# KernelSU / SukiSU run this script early in boot (post-fs-data), before
# /sdcard is mounted and unlocked, so an rm right here saw an empty directory
# and removed nothing. Wait in the background, without holding up the boot,
# until the boot has finished and /sdcard/Download is there (at most 10
# minutes), then clean up. The subshell needs nothing from the module
# directory, which is deleted right after this script.
(
    i=0
    while [ "$(getprop sys.boot_completed)" != "1" ] || [ ! -d /sdcard/Download ]; do
        i=$((i + 1))
        [ "$i" -gt 120 ] && exit 0
        sleep 5
    done
    rm -f /sdcard/*.sqlite3-tool-*.tmp /sdcard/Download/*.sqlite3-tool-*.tmp
) < /dev/null > /dev/null 2>&1 &

exit 0
