#!/usr/bin/zsh
set -e
echo "    ✨ Шаг 1: Подготовка"
echo "       🧩 Клонирование модулей от GrapheneOS"
git clone https://gitlab.com/grapheneos/kernel_pixel.git -b 16-qpr2 --depth=1 bauen/kernel_pixel

echo "       🧩 Клонирование исходного кода aosp нужной версии"
git clone https://android.googlesource.com/kernel/common -b android14-6.1-2025-08 --depth=1 bauen/kernel_source

echo "       🧩 Клонирование репозитория susfs"
git clone https://gitlab.com/simonpunk/susfs4ksu -b gki-android14-6.1 --depth=1

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
(cd $KERNEL/aosp && curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s main)
KSU_COMMIT=d0351b01f8ee2889251f6ff81a8e77f06cf04dfb
echo "           🛠️ Смена коммита KernelSU на $KSU_COMMIT"
(cd $KERNEL/aosp/KernelSU && git checkout $KSU_COMMIT && sleep 7)

echo "       🧩 Интеграция susfs в ядро"
# Копирование файлов
echo "           🛠️ Применение патчей SUSFS к ядру"
cp ../susfs4ksu/kernel_patches/fs/* $KERNEL/aosp/fs/
cp ../susfs4ksu/kernel_patches/include/linux/* $KERNEL/aosp/include/linux/

patch -d "$KERNEL/aosp" -p1 < ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch || true
patch -d "$KERNEL/aosp" -p1 < ../patches/base.c.patch

# Добавление собственной подписи для APK менеджера KSU
patch -d "$KERNEL/aosp/KernelSU" -p1 < ../patches/fix_apk_sign.c.patch

echo "           🛠️ Применение патча к самому KernelSU Next"
patch -d "$KERNEL/aosp/KernelSU" -p1 < ../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch

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
EOF

# Начало сборки
echo "    ✨ Шаг 3: Сборка"
(cd $KERNEL && tools/bazel clean --expunge && KLEAF_REPO_MANIFEST=aosp_manifest.xml ./build_shusky.sh --config=fast --lto=thin --keep_going)

echo "      Копирование артефактов сборки в папку"
mkdir output
cp ${DIST}/boot.img \
${DIST}/vendor_kernel_boot.img \
${DIST}/dtbo.img \
${DIST}/system_dlkm.img \
${DIST}/vendor_dlkm.img \
./output