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

# Dirty function to mimick Google builds fingerprint and be able to use Google Apps without having to register our GSF ID online
mimick_google_builds(){
  log_header "${FUNCNAME[0]}"
  BUILD_LOWER=$(echo ${AOSP_BUILD_ID} | tr '[:upper:]' '[:lower:]')

  cd "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/"

  rm -rf "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/${DEVICE}-${BUILD_LOWER}/"
  rm -rf "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/boot.img"
  rm -rf "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/magisk-latest"
  rm -rf "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/magisk-latest.zip"
  rm -rf "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/BOOT_EXTRACT"

  unzip "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/${DEVICE}-${BUILD_LOWER}-factory-*.zip" >/dev/null 2>&1
  unzip "${AOSP_BUILD_DIR}/vendor/android-prepare-vendor/${DEVICE}/${BUILD_LOWER}/${DEVICE}-${BUILD_LOWER}/image-${DEVICE}-${BUILD_LOWER}.zip" boot.img >/dev/null 2>&1

  # Download latest Magisk release
  curl -s https://api.github.com/repos/topjohnwu/Magisk/releases | grep "Magisk-v.*.apk" |grep https|head -n 1| cut -d : -f 2,3|tr -d \" | wget -O magisk-latest.zip -qi -
  # Extract the downloaded APK/zip
  unzip -d magisk-latest magisk-latest.zip >/dev/null 2>&1
  # Make the fakely-librarized magiskboot executable
  chmod +x ./magisk-latest/lib/x86/libmagiskboot.so

  mkdir -p BOOT_EXTRACT
  cd BOOT_EXTRACT

  ../magisk-latest/lib/x86/libmagiskboot.so unpack ../boot.img >/dev/null 2>&1
  mkdir ramdisk
  cd ramdisk
  ../../magisk-latest/lib/x86/libmagiskboot.so cpio ../ramdisk.cpio extract >/dev/null 2>&1

  BUILD_DATETIME=$(cat default.prop | grep -i ro.build.date.utc | cut -d "=" -f 2)
  BUILD_USERNAME=$(cat default.prop | grep -i ro.build.user | cut -d "=" -f 2)
  BUILD_NUMBER=$(cat default.prop | grep -i ro.build.version.incremental | cut -d "=" -f 2)
  BUILD_HOSTNAME=$(cat default.prop | grep -i ro.build.host | cut -d "=" -f 2)

  printf "Values exported:\n BUILD_DATETIME=$BUILD_DATETIME\n BUILD_USERNAME=$BUILD_USERNAME\n BUILD_NUMBER=$BUILD_NUMBER\n BUILD_HOSTNAME=$BUILD_HOSTNAME"

  export BUILD_DATETIME
  export BUILD_USERNAME
  export BUILD_NUMBER
  export BUILD_HOSTNAME
  export PRODUCT_MAKEFILE="${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/${DEVICE}.mk"

  cd "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/"
  cp "aosp_${DEVICE}.mk" "${PRODUCT_MAKEFILE}"

  sed -i "s@PRODUCT_NAME := aosp_${DEVICE}@PRODUCT_NAME := ${DEVICE}@" "${PRODUCT_MAKEFILE}" || true
  sed -i "s@PRODUCT_BRAND := Android@PRODUCT_BRAND := google@" "${PRODUCT_MAKEFILE}" || true
  sed -i "s@aosp_${DEVICE}.mk@${DEVICE}.mk@g" "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/AndroidProducts.mk" || true

  # Already done in core repo config
  #sed -i "s/PRODUCT_MODEL := AOSP on ${DEVICE}/PRODUCT_MODEL := ${DEVICE_FRIENDLY}/" "${PRODUCT_MAKEFILE}"
}

patch_safetynet(){
 cd "${AOSP_BUILD_DIR}/system/security/"
 patch -p1 --no-backup-if-mismatch < "${CUSTOM_DIR}/patches/0003-keystore-Block-key-attestation-for-Google-Play-Servi.patch"
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

if [ "${ADD_MAGISK}" == "true" ]; then
    patch_mkbootfs
fi
patch_recovery

if [ "${ADD_BITGAPPS}" == "true" ]; then
  patch_bitgapps
fi

# Mimick Google builds
if [ "${MIMICK_GOOGLE_BUILDS}" == "true" ]; then
  mimick_google_builds
fi

# Use a cool alternative bootanimation
if [ "${USE_CUSTOM_BOOTANIMATION}" == "true" ]; then
  cp -f "${CUSTOM_DIR}/prebuilt/bootanimation.zip" "${AOSP_BUILD_DIR}/system/media/bootanimation.zip"
  echo -ne "\\nPRODUCT_COPY_FILES += \\\\\nsystem/media/bootanimation.zip:system/media/bootanimation.zip" >> "${AOSP_BUILD_DIR}/device/google/${DEVICE_FAMILY}/device.mk"
fi

# Patch Keystore to pass SafetyNet
if [ "${SAFETYNET_BYPASS}" == "true" ]; then
  patch_safetynet
fi
