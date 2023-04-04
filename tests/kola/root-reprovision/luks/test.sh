#!/bin/bash
## kola:
##   # This test reprovisions the rootfs.
##   tags: "platform-independent reprovision"
##   # Root reprovisioning requires at least 4GiB of memory.
##   minMemory: 4096
##   # A TPM backend device is not available on s390x to suport TPM.
##   architectures: "!s390x"
##   # This test includes a lot of disk I/O and needs a higher
##   # timeout value than the default.
##   timeoutMin: 15

set -xeuo pipefail

. $KOLA_EXT_DATA/commonlib.sh

srcdev=$(findmnt -nvr / -o SOURCE)
[[ ${srcdev} == /dev/mapper/myluksdev ]]

blktype=$(lsblk -o TYPE "${srcdev}" --noheadings)
[[ ${blktype} == crypt ]]

fstype=$(findmnt -nvr / -o FSTYPE)
[[ ${fstype} == xfs ]]
ok "source is XFS on LUKS device"

rootflags=$(findmnt /sysroot -no OPTIONS)
if ! grep prjquota <<< "${rootflags}"; then
    fatal "missing prjquota in root mount flags: ${rootflags}"
fi
ok "root mounted with prjquota"

table=$(dmsetup table myluksdev)
if ! grep -q allow_discards <<< "${table}"; then
    fatal "missing allow_discards in root DM table: ${table}"
fi
if ! grep -q no_read_workqueue <<< "${table}"; then
    fatal "missing no_read_workqueue in root DM table: ${table}"
fi
ok "discard and custom option enabled for root LUKS"

# while we're here, sanity-check that boot is mounted by UUID
if ! systemctl cat boot.mount | grep -q What=/dev/disk/by-uuid; then
  systemctl cat boot.mount
  fatal "boot mounted not by UUID"
fi
ok "boot mounted by UUID"

case "${AUTOPKGTEST_REBOOT_MARK:-}" in
  "")
      # check that ignition-ostree-growfs ran
      if [ ! -e /run/ignition-ostree-growfs.stamp ]; then
          fatal "ignition-ostree-growfs did not run"
      fi

      # reboot once to sanity-check we can find root on second boot
      /tmp/autopkgtest-reboot rebooted
      ;;

  rebooted)
      grep root=UUID= /proc/cmdline
      grep rd.luks.name= /proc/cmdline
      ok "found root kargs"

      # while we're here, sanity-check that we have a boot=UUID karg too
      grep boot=UUID= /proc/cmdline
      ok "found boot karg"
      ;;
  *) fatal "unexpected mark: ${AUTOPKGTEST_REBOOT_MARK}";;
esac
