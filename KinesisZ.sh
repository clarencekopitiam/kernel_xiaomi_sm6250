#!/bin/bash

# Script Name: KinesisZ.sh (Z stands for ZyC Clang)
# Description: Builds Kinesis Kernel using prebuilt ZyCromerZ Clang.

# Function to send Telegram message with error handling and decoding
tg() {
  local msg="$1"
  local response=$(curl -s -o /dev/null -w "%{http_code}" "https://api.telegram.org/bot$BOTID/sendMessage?chat_id=$TGID&text=$msg")

  if [[ "$response" != "200" ]]; then
    echo "❌ Error sending Telegram message. HTTP Code: $response"
    echo "Response body:"
    curl -s "https://api.telegram.org/bot$BOTID/sendMessage?chat_id=$TGID&text=$msg"
  fi
}

# Function to send Telegram document with error handling and decoding
tg_doc() {
  local file="$1"
  local caption="$2"
  local response=$(curl -s -o /dev/null -w "%{http_code}" -F document=@"$file" "https://api.telegram.org/bot$BOTID/sendDocument" -F chat_id=$TGID" -F caption="$caption")

  if [[ "$response" != "200" ]]; then
    echo "❌ Error sending Telegram document. HTTP Code: $response"
    echo "Response body:"
    curl -s -F document=@"$file" "https://api.telegram.org/bot$BOTID/sendDocument" -F chat_id="$TGID" -F caption="$caption"
  fi
}

# 🌳 Clone the kernel source to Azyr_Kernel directory
git clone "$KT_LINK" -b "$KT_BRANCH" Azyr_Kernel --depth=1 --single-branch
cd Azyr_Kernel || { echo "❌ Failed to cd into Azyr_Kernel"; exit 1; }

# 🧰 Set up ccache
export CCACHE_DIR=/tmp/ccache
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
ccache -M 10G
ccache -o compression=true
ccache -z

# ⬇️ Download and setup prebuilt ZyCromerZ Clang
echo "⬇️ Downloading prebuilt ZyCromerZ Clang..."
wget -O ZyC-Clang.tar.gz "https://github.com/ZyCromerZ/Clang/releases/download/20.0.0git-20241220-release/Clang-20.0.0git-20241220.tar.gz"
mkdir -p "$HOME/ZyC-Clang"
tar -xvf ZyC-Clang.tar.gz -C "$HOME/ZyC-Clang" --strip-components=1
rm ZyC-Clang.tar.gz

# ⚙️ Build configuration
SECONDS=0
DEFCONFIG="vendor/xiaomi/miatoll_defconfig"

# 🧰 Set up environment variables for the build
export PATH="$HOME/ZyC-Clang/bin:$PATH" # Use the prebuilt ZyCromerZ Clang
export ARCH=arm64
export KBUILD_BUILD_USER=AzyrRuthless # 🪪 Set build user
export KBUILD_BUILD_HOST=GitHub-Actions # 🤖 Set build host
export KBUILD_BUILD_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC") # ⌚ Set build timestamp
# Use ZyCromerZ Clang for compilation
export CC=clang

# 🚀 Start compilation
echo -e "\n🚀 Starting compilation...\n"
mkdir -p out
make O=out mrproper # 🧹 Clean previous build artifacts and configuration
make O=out $DEFCONFIG

# Unset potentially problematic environment variables
unset CFLAGS HOSTCFLAGS CXXFLAGS

# Handle flags for cleaning or regenerating defconfig
if [[ "$1" == "-c" || "$1" == "--clean" ]]; then
  echo "🧹 Cleaning output directory..."
  make O=out clean
  echo "✅ Output directory cleaned."
fi

if [[ "$1" == "-r" || "$1" == "--regen" ]]; then
  echo "🔄 Regenerating defconfig..."
  make O=out ARCH=arm64 $DEFCONFIG savedefconfig
  cp out/defconfig arch/arm64/configs/$DEFCONFIG
  echo "✅ Defconfig regenerated."
  exit 0
fi

make -j$(nproc --all) O=out ARCH=arm64 | tee build.log

# Check for build success
if [[ $? -ne 0 ]]; then
  echo -e "\n❌ Compilation failed!"
  tg "❌ Kernel build failed!"
  tg_doc "build.log" "❌ Build failed after $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)"
fi

# Build success actions
echo -e "\n✅ Kernel compiled successfully! Zipping up...\n"

# 🌳 Clone AnyKernel3 from osm0sis and prepare the zip
if ! git clone -q https://github.com/osm0sis/AnyKernel3; then
  echo -e "\n❌ Cloning AnyKernel3 repo failed! Aborting..."
  exit 1
fi

# 🗜️ Create the zip file outside of AnyKernel3 directory
ZIP_NAME="Kinesis-Kernel-$(date '+%Y%m%d-%H%M')-sm6250.zip" # 🗜️ Define a user-friendly ZIP name

# Copy kernel build outputs to AnyKernel3 directory
if [[ $? -eq 0 ]]; then
  echo -e "\n✅ Copying Kernel Image, dtbo, and dtb...\n"
  cp out/arch/arm64/boot/Image.gz AnyKernel3
  cp out/arch/arm64/boot/dtbo.img AnyKernel3
  cp out/arch/arm64/boot/dts/qcom/cust-atoll-ab.dtb AnyKernel3/dtb
else
  echo -e "\n❌ Kernel Image, dtbo, or dtb not found. Skipping...\n"
fi

rm -f ./*zip
cd AnyKernel3 || { echo "❌ Failed to cd into AnyKernel3"; exit 1; }

zip -r9 "../$ZIP_NAME" ./* -x '*.git*' README.md
cd .. || { echo "❌ Failed to cd back to parent directory"; exit 1; }

# 🧹 Cleanup
rm -rf AnyKernel3 out

# 🎉 Build completion message
BUILD_TIME_MINUTES=$((SECONDS / 60))
BUILD_TIME_SECONDS=$((SECONDS % 60))
echo -e "\n🎉 Completed in ${BUILD_TIME_MINUTES} minute(s) and ${BUILD_TIME_SECONDS} second(s) !"
echo "🗜️ Zip: $ZIP_NAME"

# 📢 Send success notification to Telegram
RELEASE_MESSAGE=$(cat << EOF
✅ **Kinesis Kernel Build Successful!**

**Kernel:** Kinesis
**Device:** SM6250
**Date:** $(date '+%Y-%m-%d %H:%M')
**Compiler:** ZyCromerZ Clang 20.0.0
**Built by:** ${KBUILD_BUILD_USER}
**Build Host:** ${KBUILD_BUILD_HOST}
**Build Time:** ${BUILD_TIME_MINUTES} minute(s) and ${BUILD_TIME_SECONDS} second(s)
**Commit:** $(git rev-parse --short HEAD)

EOF
)

# 📢 Send completion notification to Telegram regardless of the build result
tg "🔔 Kernel build process completed! $ZIP_NAME"
tg_doc "$ZIP_NAME" "$RELEASE_MESSAGE"
