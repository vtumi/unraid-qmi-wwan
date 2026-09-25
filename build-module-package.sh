#!/bin/bash
set -euo pipefail

KERNEL_RELEASE="${KERNEL_RELEASE:-6.18.38-Unraid}"
WORK_DIR="${WORK_DIR:-/work}"
KERNEL_DIR="${WORK_DIR}/linux-${KERNEL_RELEASE}"
OUTPUT_DIR="${WORK_DIR}/output"
JOBS="${JOBS:-$(nproc)}"
PACKAGE_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${PACKAGE_ROOT}"
}
trap cleanup EXIT

cd "${KERNEL_DIR}"

test -s .config
test -s Module.symvers
test "$(make -s kernelrelease)" = "${KERNEL_RELEASE}"
grep -Eq '^CONFIG_USB_USBNET=(m|y)$' .config

scripts/config --module USB_WDM
scripts/config --module USB_NET_QMI_WWAN
make olddefconfig

grep -Eq '^CONFIG_USB_WDM=m$' .config
grep -Eq '^CONFIG_USB_NET_QMI_WWAN=m$' .config

make -j"${JOBS}" prepare modules_prepare
make -j"${JOBS}" M=drivers/usb/class modules
make -j"${JOBS}" M=drivers/net/usb \
  KBUILD_EXTRA_SYMBOLS="${KERNEL_DIR}/drivers/usb/class/Module.symvers" \
  modules

install -Dm644 drivers/usb/class/cdc-wdm.ko \
  "${PACKAGE_ROOT}/lib/modules/${KERNEL_RELEASE}/kernel/drivers/usb/class/cdc-wdm.ko"
install -Dm644 drivers/net/usb/qmi_wwan.ko \
  "${PACKAGE_ROOT}/lib/modules/${KERNEL_RELEASE}/kernel/drivers/net/usb/qmi_wwan.ko"

find "${PACKAGE_ROOT}/lib/modules" -name '*.ko' \
  -exec xz --check=crc32 --lzma2 {} \;

mkdir -p "${PACKAGE_ROOT}/install" "${OUTPUT_DIR}"
printf '%s\n' \
  'qmi-wwan: qmi_wwan driver for Unraid' \
  'qmi-wwan:' \
  'qmi-wwan: Qualcomm QMI WWAN network driver.' \
  'qmi-wwan: Includes qmi_wwan and cdc-wdm kernel modules.' \
  > "${PACKAGE_ROOT}/install/slack-desc"

printf '%s\n' \
  '#!/bin/sh' \
  '' \
  '/sbin/depmod -a' \
  '/sbin/modprobe qmi_wwan' \
  '' \
  'exit 0' \
  > "${PACKAGE_ROOT}/install/doinst.sh"
chmod 755 "${PACKAGE_ROOT}/install/doinst.sh"

PACKAGE="${OUTPUT_DIR}/qmi-wwan-${KERNEL_RELEASE//-/_}-x86_64-1.txz"
rm -f "${PACKAGE}" "${PACKAGE}.md5" "${PACKAGE}.sha256"

cd "${PACKAGE_ROOT}"
makepkg -l n -c n "${PACKAGE}"

cd "${OUTPUT_DIR}"
PACKAGE_NAME="$(basename "${PACKAGE}")"
md5sum "${PACKAGE_NAME}" > "${PACKAGE_NAME}.md5"
sha256sum "${PACKAGE_NAME}" > "${PACKAGE_NAME}.sha256"

modinfo "${PACKAGE_ROOT}/lib/modules/${KERNEL_RELEASE}/kernel/drivers/usb/class/cdc-wdm.ko.xz"
modinfo "${PACKAGE_ROOT}/lib/modules/${KERNEL_RELEASE}/kernel/drivers/net/usb/qmi_wwan.ko.xz"
