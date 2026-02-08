#!/usr/bin/zsh
set -e
echo "    ✨ Шаг 1: Подготовка"
echo "       🧩 Клонирование модулей от GrapheneOS"
git clone https://gitlab.com/grapheneos/kernel_pixel.git -b 16-qpr2 --depth=1 bauen/kernel_pixel

echo "       🧩 Клонирование исходного кода aosp нужной версии"
git clone https://android.googlesource.com/kernel/common -b android14-6.1-2025-08 --depth=1 bauen/kernel_source

echo "       🧩 Клонирование репозитория susfs"
git clone https://gitlab.com/simonpunk/susfs4ksu -b gki-android14-6.1

# Определение переменных
export KERNEL=$(pwd)/bauen/kernel_pixel
export DEFCONFIG=$KERNEL/private/devices/google/shusky/shusky_defconfig
export DIST=$KERNEL/out/shusky/dist

cd bauen

# Монтирование исходного кода в aosp
sudo mount --bind kernel_source ${KERNEL}/aosp 

echo "    ✨ Шаг 2: Применение патчей"
# Удаление проверки ABI и метки dirty в наименовании ядра
echo "      Удаление ABI & -dirty"
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" $KERNEL/build/kernel/kleaf/impl/stamp.bzl
sed -i 's/-dirty//' $KERNEL/aosp/scripts/setlocalversion
rm -rf $KERNEL/aosp/android/abi_gki_protected_exports_*
perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' $KERNEL/aosp/BUILD.bazel
sed -i "s/echo -n -dirty/echo -n \"\"/g" $KERNEL/build/kernel/kleaf/workspace_status_stamp.py

echo "       🧩 Интеграция KernlSU Next в ядро"
(cd $KERNEL/aosp && curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/dev/kernel/setup.sh" | bash -s dev)
KSU_COMMIT=314fbc5a2cf4edfee68bcaefce55f465ae6795ec
SUSFS_COMMIT=700af50a692ec8a7279bce005ffce0f91195eab1

echo "      Смена коммита KernelSU-Next на $KSU_COMMIT"
(cd $KERNEL/aosp/KernelSU-Next && git checkout $KSU_COMMIT)
echo "           🛠️ Смена коммита SUSFS на $SUSFS_COMMIT"
(cd ../susfs4ksu && git checkout $SUSFS_COMMIT)

echo "       🧩 Интеграция susfs в ядро"
echo "           🛠️ Применение патчей SUSFS к ядру"
cp ../susfs4ksu/kernel_patches/fs/* $KERNEL/aosp/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* $KERNEL/aosp/include/linux/
patch -d "$KERNEL/aosp" -p1 < ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch || true
echo "              🔧 Починка base.c"
patch -d "$KERNEL/aosp" -p1 < ../patches/base.c.patch

echo "           🛠️ Применение патча к самому KernelSU"
patch -d "$KERNEL/aosp/KernelSU-Next" -p1 < ../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch || true
echo "              🔧 Починка патча 10_enable_susfs_for_ksu.patch"
patch -d "$KERNEL/aosp/KernelSU-Next" -p1 < ../patches/ksu-next_susfs/global.patch

echo "       🧩 Интеграция GrapheneOS репозитория c исходным кодом ядра"
patch -d "$KERNEL/aosp" -p2 < ../patches/fix_tcpm.c.patch
patch -d "$KERNEL/aosp" -p2 < ../patches/fix_tcpm.h.patch

sed -i '/tcpm_unregister_port/a \
  tcpm_update_sink_capabilities' $KERNEL/aosp/android/abi_gki_aarch64_pixel
grep -A 1 'tcpm_unregister_port' $KERNEL/aosp/android/abi_gki_aarch64_pixel

sed -i '/#endif	\/\* _LINUX_MINMAX_H \*\//i \
#define MIN(a, b) __cmp(min, a, b)\
#define MAX(a, b) __cmp(max, a, b)' $KERNEL/aosp/include/linux/minmax.h
grep -B 2 '#endif	/\* _LINUX_MINMAX_H \*/' $KERNEL/aosp/include/linux/minmax.h

sed -i '/#define MAX(a, b) ((a) >= (b) ? (a) : (b))/i \
#ifdef MAX\
#undef MAX\
#endif' $KERNEL/aosp/mm/zsmalloc.c
grep -B 3 '#define MAX(a, b) ((a) >= (b) ? (a) : (b))' $KERNEL/aosp/mm/zsmalloc.c

echo "       🧩 Интеграция Baseband-guard к исходному коду ядра"
(cd $KERNEL/aosp && wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash)
echo "CONFIG_BBG=y" >> $DEFCONFIG
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' $KERNEL/aosp/security/Kconfig

# Добавление конфигурации в ядро 
cat >> $DEFCONFIG << EOF
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_THREAD_INFO_IN_TASK=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
EOF
