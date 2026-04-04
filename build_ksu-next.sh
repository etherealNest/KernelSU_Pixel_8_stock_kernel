#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Variables.conf
source "$PROJECT_ROOT/Variables.conf"

KSU_TYPE="KernelSU-Next"
KERNEL="$PROJECT_ROOT/pixel"
AOSP="$KERNEL/common/ack"
DEFCONFIG="$KERNEL/private/devices/google/shusky/shusky_defconfig"
PATCH_DIR="$PROJECT_ROOT/patches/ksu-next_susfs"

log() {
  printf '\nℹ️ ==> %s\n' "$1"
}

apply_patch_file() {
  local target="$1"
  local patch_file="$2"
  local optional="${3:-0}"

  printf '  -> %s\n' "$(basename "$patch_file")"
  if [[ "$optional" == "1" ]]; then
    patch -d "$target" -p1 < "$patch_file" || true
  else
    patch -d "$target" -p1 < "$patch_file"
  fi
}

log "Clean workspace"
sudo umount "$AOSP" 2>/dev/null || true
rm -rf "$PROJECT_ROOT/susfs4ksu" "$PROJECT_ROOT/KPatch-Next" "$PROJECT_ROOT/output" "$PROJECT_ROOT/AnyKernel3" 2>/dev/null || true

for kernel_folder in stable_source beta_source; do
cd "$PROJECT_ROOT/$kernel_folder"
git reset --hard HEAD
git clean -fdx
rm -rf Baseband-guard KernelSU-Next
done

cd "$KERNEL"
git reset --hard HEAD
git clean -fdx

cd "$PROJECT_ROOT"
git clone https://gitlab.com/simonpunk/susfs4ksu --single-branch -b gki-android14-6.1
cd "$PROJECT_ROOT/susfs4ksu"
git checkout "$SUSFS_COMMIT"

log "Mount kernel source"
printf '1) Использовать версию ядра из Stable ветки\n2) Использовать версию ядра из Beta ветки\n> '
read -r n
case $n in
  1) FOLDER_KERNEL="stable_source" TYPE_FIRMWARE="STABLE" ;; 
  2) FOLDER_KERNEL="beta_source" TYPE_FIRMWARE="BETA" ;; 
  *) echo "Неверный выбор" ;;
esac
sudo mount --bind "$PROJECT_ROOT/$FOLDER_KERNEL" "$AOSP"

log "Formation of variables"
rollback_index="${TYPE_FIRMWARE}_rollback_index"
salt="${TYPE_FIRMWARE}_salt"
os_version="${TYPE_FIRMWARE}_os_version"
fingerprint="${TYPE_FIRMWARE}_fingerprint"
security_patch="${TYPE_FIRMWARE}_security_patch"

log "Configure kernel"
cat >> "$DEFCONFIG" <<'EOF'
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_THREAD_INFO_IN_TASK=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF

rm -rf "$AOSP"/android/abi_gki_protected_exports_*
perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' "$AOSP/BUILD.bazel"
sed -i 's/echo -n -dirty/echo -n ""/g' "$KERNEL/build/kernel/kleaf/workspace_status_stamp.py"

KERNEL_VER="$(sed -n '2,4p' "$AOSP/Makefile" | grep -oE '[0-9]+' | paste -sd '.')"

log "Install KernelSU-Next"
cd "$AOSP"
curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" | bash -s dev
cd "$AOSP/KernelSU-Next"
git checkout "$KSU_NEXT_COMMIT"

log "Apply SUSFS patches"
cp "$PROJECT_ROOT/susfs4ksu/kernel_patches/fs/"* "$AOSP/fs/"
cp "$PROJECT_ROOT/susfs4ksu/kernel_patches/include/linux/"* "$AOSP/include/linux/"
apply_patch_file "$AOSP" "$PROJECT_ROOT/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch" 1
apply_patch_file "$AOSP/$KSU_TYPE" "$PROJECT_ROOT/susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" 1

log "Apply KernelSU-Next fixes"
for patch_name in "${KSU_NEXT_PATCHES[@]}"; do
  apply_patch_file "$AOSP/KernelSU-Next" "$PATCH_DIR/$patch_name"
done

log "Install Baseband-guard"
cd "$AOSP"
wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash
echo "CONFIG_BBG=y" >> "$DEFCONFIG"
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' "$AOSP/security/Kconfig"

log "Correction of the .sh script used for build"
sed -i '/zuma_shusky_dist/q' $KERNEL/build_shusky.sh
sed -i 's/zuma_shusky_dist/kernel/' $KERNEL/build_shusky.sh
sed -i 's/bazel run/bazel build/' $KERNEL/build_shusky.sh

log "Build kernel"
cd "$KERNEL"
read -r -p "Press Enter to start build..."
tools/bazel clean --expunge
KLEAF_REPO_MANIFEST=aosp_manifest.xml ./build_shusky.sh --config=fast --lto=thin --keep_going
read -r -p "Build complete. Press Enter to continue..."

log "Prepare boot.img"
DIST="$(find "$KERNEL/out/bazel/output_user_root" -type d -name kernel_kbuild_mixed_tree)"
TMPDIR="$(mktemp -d)"
mkdir -p "$TMPDIR/gki"

curl -fsSL 'https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/mkbootimg.py?format=TEXT' | base64 -d > "$TMPDIR/mkbootimg.py"
curl -fsSL 'https://android.googlesource.com/platform/system/tools/mkbootimg/+/refs/heads/main/gki/generate_gki_certificate.py?format=TEXT' | base64 -d > "$TMPDIR/gki/generate_gki_certificate.py"
curl -fsSL 'https://android.googlesource.com/platform/external/avb/+/refs/heads/main-kernel/avbtool.py?format=TEXT' | base64 -d > "$TMPDIR/avbtool.py"
: > "$TMPDIR/gki/__init__.py"

lz4 -l -12 -f "$DIST/Image" "$TMPDIR/kernel"
: > "$TMPDIR/ramdisk"

python3 "$TMPDIR/mkbootimg.py" \
  --header_version 4 \
  --pagesize 4096 \
  --kernel "$TMPDIR/kernel" \
  --ramdisk "$TMPDIR/ramdisk" \
  --cmdline '' \
  --os_patch_level "${!security_patch}" \
  -o "$DIST/boot.img"

log "Prepare patched boot.img"
mkdir -p "$PROJECT_ROOT/KPatch-Next" "$PROJECT_ROOT/output"

cd "$PROJECT_ROOT/KPatch-Next"
gh release download --repo KernelSU-Next/KPatch-Next -p 'kpimg-linux' -p 'kptools-linux' --clobber
chmod +x kptools-linux
./kptools-linux -p -i "$DIST/Image" -k kpimg-linux -o "$DIST/Image_patched"
mv -f "$DIST/Image_patched" "$DIST/Image"

gh release download v30.2 --repo topjohnwu/Magisk -p 'Magisk*.apk' --clobber
unzip -oj Magisk*.apk lib/x86_64/libmagiskboot.so
mv -f libmagiskboot.so magiskboot
chmod +x magiskboot

cp "$DIST/boot.img" "$PROJECT_ROOT/output/"
cd "$PROJECT_ROOT/output"
"$PROJECT_ROOT/KPatch-Next/magiskboot" unpack boot.img
cp -f "$DIST/Image" ./kernel
"$PROJECT_ROOT/KPatch-Next/magiskboot" repack boot.img boot_patched.img
mv -f boot_patched.img boot.img

python3 "$TMPDIR/avbtool.py" add_hash_footer \
  --image "$PROJECT_ROOT/output/boot.img" \
  --partition_name boot \
  --partition_size 67108864 \
  --hash_algorithm sha256 \
  --algorithm NONE \
  --rollback_index "${!rollback_index}" \
  --rollback_index_location 0 \
  --flags 0 \
  --salt "${!salt}" \
  --prop "com.android.build.boot.os_version:${!os_version}" \
  --prop "com.android.build.boot.fingerprint:${!fingerprint}" \
  --prop "com.android.build.boot.security_patch:${!security_patch}"

rm -rf *kernel* ramdisk* header* dtb* unknown*
rm -rf "$TMPDIR"

BOOT_ZIP_NAME="${KERNEL_VER}_boot.img_${KSU_TYPE}.zip"
zip -m "$BOOT_ZIP_NAME" boot.img

printf '\nDone: output/%s\n' "$BOOT_ZIP_NAME"
