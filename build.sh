#!/usr/bin/env bash

 #
 # Script For Building Android Kernel
 #

# Bail out if script fails
set -e

##----------------------------------------------------------##
# Basic Information
KERNEL_DIR="$(pwd)"
VERSION=R1
MODEL=Xiaomi
DEVICE=Gauguin
DEFCONFIG=gauguin_defconfig
IMAGE=$(pwd)/out/arch/arm64/boot/Image
DTBO=$(pwd)/out/arch/arm64/boot/dtbo.img
DTB=$(pwd)/out/arch/arm64/boot/dts/vendor/qcom/gauguin-sm6350.dtb
##----------------------------------------------------------##
## Export Variables and Info
function exports() {
export ARCH=arm64
export SUBARCH=arm64
export LOCALVERSION="-${VERSION}"
export KBUILD_BUILD_HOST=NexGang
export KBUILD_BUILD_USER="kawaaii"
export KBUILD_BUILD_VERSION="1"
export PROCS=$(nproc --all)
export DISTRO=$(source /etc/os-release && echo "${NAME}")

# Variables
KERVER=$(make kernelversion)
COMMIT_HEAD=$(git log --oneline -1)
DATE=$(TZ=Asia/Kolkata date +"%Y%m%d-%T")
TANGGAL=$(date +"%F%S")

# Compiler and Build Information
TOOLCHAIN=atomx # List ( gcc = eva | nexus9 | nexus12 ) (clang = nexus | aosp | sdclang | proton | atomx )
LINKER=ld.lld # List ( ld.lld | ld.bfd | ld.gold | ld )

if [[ "$TOOLCHAIN" == "eva" || "$TOOLCHAIN" == "nexus9" || "$TOOLCHAIN" == "nexus12" ]]; then
       COMPILER=gcc
elif [[ "$TOOLCHAIN" == "nexus" || "$TOOLCHAIN" == "proton" || "$TOOLCHAIN" == "aosp" || "$TOOLCHAIN" == "sdclang" || "$TOOLCHAIN" == "atomx" ]]; then
       COMPILER=clang
fi

VERBOSE=0
ZIPNAME=NexusKernel
FINAL_ZIP=${ZIPNAME}-${VERSION}-${DEVICE}-${TANGGAL}.zip

# CI
        if [ "$CI" ]; then
           if [ "$CIRCLECI" ]; then
                  export CI_BRANCH=${CIRCLE_BRANCH}
           elif [ "$DRONE" ]; then
                export CI_BRANCH=${DRONE_BRANCH}
           elif [ "$CIRRUS_CI" ]; then
                  export CI_BRANCH=${CIRRUS_BRANCH}
           fi
        fi
}
##----------------------------------------------------------##
## Telegram Bot Integration
function post_msg() {
       curl -s -X POST "https://api.telegram.org/bot$token/sendMessage" \
       -d chat_id="$chat_id" \
       -d "disable_web_page_preview=true" \
       -d "parse_mode=html" \
       -d text="$1"
       }

function push() {
       curl -F document=@$1 "https://api.telegram.org/bot$token/sendDocument" \
       -F chat_id="$chat_id" \
       -F "disable_web_page_preview=true" \
       -F "parse_mode=html" \
       -F caption="$2"
       }
##----------------------------------------------------------------##
## Get Dependencies
function clone() {
# Get Toolchain
if [[ $TOOLCHAIN == "eva" ]]; then
       git clone --depth=1 https://github.com/mvaisakh/gcc-arm64 gcc64
       git clone --depth=1 https://github.com/mvaisakh/gcc-arm gcc32
elif [[ $TOOLCHAIN == "nexus9" ]]; then
       git clone --depth=1 https://github.com/reaPeR1010/arm64-gcc -b gcc-9 gcc64
       git clone --depth=1 https://github.com/reaPeR1010/arm32-gcc -b gcc-9 gcc32
elif [[ $TOOLCHAIN == "nexus12" ]]; then
       git clone --depth=1 https://github.com/reaPeR1010/arm64-gcc -b gcc-12 gcc64
       git clone --depth=1 https://github.com/reaPeR1010/arm32-gcc -b gcc-12 gcc32
elif [[ $TOOLCHAIN == "proton" ]]; then
       git clone --depth=1 https://github.com/kdrag0n/proton-clang clang
elif [[ $TOOLCHAIN == "nexus" ]]; then
       git clone --depth=1  https://gitlab.com/Project-Nexus/nexus-clang clang
elif [[ $TOOLCHAIN == "atomx" ]]; then
       git clone --depth=1  https://gitlab.com/ElectroPerf/atom-x-clang.git clang
elif [[ $TOOLCHAIN == "aosp" ]]; then
       mkdir clang
       cd clang || exit
       wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r450784e.tar.gz
       tar -xf clang*
       cd .. || exit
       git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 gcc64
       git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git --depth=1 gcc32
elif [[ $TOOLCHAIN == "sdclang" ]]; then
       git clone --depth=1 https://github.com/ZyCromerZ/SDClang clang
       git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 gcc64
       git clone https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git --depth=1 gcc32
fi

# Get AnyKernel3
git clone --depth=1 https://github.com/reaPeR1010/AnyKernel3 AK3

# Set PATH
if [[ "$COMPILER" == "gcc" ]]; then
       PATH="${KERNEL_DIR}/gcc64/bin/:${KERNEL_DIR}/gcc32/bin/:/usr/bin:${PATH}"
elif [[ "$TOOLCHAIN" == "nexus" || "$TOOLCHAIN" == "proton" || "$TOOLCHAIN" == "atomx" ]]; then
       PATH="${KERNEL_DIR}/clang/bin:${PATH}"
elif [[ "$TOOLCHAIN" == "aosp" || "$TOOLCHAIN" == "sdclang" ]]; then
       PATH="${KERNEL_DIR}/clang/bin:${KERNEL_DIR}/gcc64/bin:${KERNEL_DIR}/gcc32/bin:${PATH}"
fi

# Export KBUILD_COMPILER_STRING
if [[ "$COMPILER" == "gcc" ]]; then
       export KBUILD_COMPILER_STRING=$(${KERNEL_DIR}/gcc64/bin/aarch64-elf-gcc --version | head -n 1)
elif [[ "$COMPILER" == "clang" ]]; then
       export KBUILD_COMPILER_STRING=$(${KERNEL_DIR}/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
fi
}
##----------------------------------------------------------------##
function compile() {
START=$(date +"%s")

# Push Notification
post_msg "<b>$KBUILD_BUILD_VERSION CI Build Triggered</b>%0A<b>Docker OS: </b><code>$DISTRO</code>%0A<b>Kernel Version : </b><code>$KERVER</code>%0A<b>Date : </b><code>$(TZ=Asia/Kolkata date)</code>%0A<b>Device : </b><code>$MODEL [$DEVICE]</code>%0A<b>Version : </b><code>$VERSION</code>%0A<b>Pipeline Host : </b><code>$KBUILD_BUILD_HOST</code>%0A<b>Host Core Count : </b><code>$PROCS</code>%0A<b>Compiler Used : </b><code>$KBUILD_COMPILER_STRING</code>%0A<b>Linker : </b><code>$LINKER</code>%0a<b>Branch : </b><code>$CI_BRANCH</code>%0A<b>Top Commit : </b><a href='$DRONE_COMMIT_LINK'>$COMMIT_HEAD</a>"

# Generate .config
if [[ $COMPILER == "gcc" ]]; then
make O=out ARCH=arm64 ${DEFCONFIG}
elif [[ $COMPILER == "clang" ]]; then
make O=out LLVM=1 ARCH=arm64 ${DEFCONFIG}
fi

# Start Compilation
if [[ "$COMPILER" == "gcc" ]]; then
     MAKE+=( HOSTLD=ld.lld CROSS_COMPILE_COMPAT=arm-eabi- CROSS_COMPILE=aarch64-elf- LD=aarch64-elf-${LINKER} AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip OBJSIZE=llvm-size )
elif [[ "$COMPILER" == "clang" ]]; then
     MAKE+=( LLVM=1 LLVM_IAS=1 HOSTLD=ld.lld HOSTAR=llvm-ar )
     if [[ "$TOOLCHAIN" == "aosp" || "$TOOLCHAIN" == "sdclang" ]]; then
     MAKE+=( CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_COMPAT=arm-linux-androideabi- )
     else
     MAKE+=( CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-)
     fi
fi

make -kj$PROCS ARCH=arm64 O=out V=$VERBOSE "${MAKE[@]}" 2>&1 | tee error.log

# Verify Files
       if ! [ -a "$IMAGE" ];
          then
              push "error.log" "Build Throws Errors"
              exit 1
          else
              post_msg " Kernel Compilation Finished. Started Zipping "
       fi
}
##----------------------------------------------------------------##
function zipping() {
# Copy Files To AnyKernel3 Zip
cp $IMAGE AK3
cp $DTBO AK3
cp $DTB AK3/dtb

# Zipping and Push Kernel
cd AK3 || exit 1
zip -r9 ${FINAL_ZIP} *
MD5CHECK=$(md5sum "$FINAL_ZIP" | cut -d' ' -f1)
push "$FINAL_ZIP" "Build took : $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) second(s) | For <b>$MODEL ($DEVICE)</b> | <b>${KBUILD_COMPILER_STRING}</b> | <b>MD5 Checksum : </b><code>$MD5CHECK</code>"
cd ..
}
##----------------------------------------------------------##
# Functions
exports
clone
compile
END=$(date +"%s")
DIFF=$(($END - $START))
zipping
##------------------------*****-----------------------------##
