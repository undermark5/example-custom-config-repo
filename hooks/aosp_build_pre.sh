#!/usr/bin/env bash

cd "${AOSP_BUILD_DIR}"

patch_mkbootfs(){
  cd "${AOSP_BUILD_DIR}/system/core"
  patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0001_allow_dotfiles_in_cpio.patch"
}

patch_recovery(){
  cd "${AOSP_BUILD_DIR}/bootable/recovery/"
  patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0002_recovery_add_mark_successful_option.patch"
}

patch_bitgapps(){
  log_header "${FUNCNAME[0]}"

  retry git clone https://github.com/BiTGApps/aosp-build.git "${AOSP_BUILD_DIR}/vendor/gapps"
  cd "${AOSP_BUILD_DIR}/vendor/gapps"
  git lfs pull

  echo -ne "\\nTARGET_ARCH := arm64" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
  echo -ne "\\nTARGET_SDK_VERSION := 30" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
  echo -ne "\\n\$(call inherit-product, vendor/gapps/gapps.mk)" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
}

# apply microg sigspoof patch
#echo "applying microg sigspoof patch"
#patch -p1 --no-backup-if-mismatch < "platform/prebuilts/microg/00002-microg-sigspoof.patch"

# apply community patches
echo "applying community patch 00001-global-internet-permission-toggle.patch"
community_patches_dir="${ROOT_DIR}/community_patches"
rm -rf "${community_patches_dir}"
git clone https://github.com/rattlesnakeos/community_patches "${community_patches_dir}"
patch -p1 --no-backup-if-mismatch < "${community_patches_dir}/00001-global-internet-permission-toggle.patch"

# apply custom hosts file
custom_hosts_file="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
echo "applying custom hosts file ${custom_hosts_file}"
retry wget -q -O "${AOSP_BUILD_DIR}/system/core/rootdir/etc/hosts" "${custom_hosts_file}"

patch_mkbootfs
patch_recovery

if [ "${ADD_BITGAPPS}" = true ]; then
  patch_bitgapps
fi
