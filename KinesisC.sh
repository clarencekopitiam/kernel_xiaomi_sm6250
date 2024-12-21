#!/bin/bash

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
  local response=$(curl -s -o /dev/null -w "%{http_code}" -F document=@"$file" "https://api.telegram.org/bot$BOTID/sendDocument" -F chat_id="$TGID" -F caption="$caption")

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

# 🪚 Revert to cosmic-clang from GitLab (Like Previous "Safe" Version)
if [ ! -d "$HOME/cosmic" ]; then
  echo "🪚 Clang not found! Cloning..."
  # ⚠️ Ensure this URL is correct and matches the "safe" version
  if ! git clone https://gitlab.com/GhostMaster69-dev/cosmic-clang.git --depth=1 --single-branch $HOME/cosmic; then
    echo "❌ Cloning clang failed! Aborting..."
    exit 1
  fi
fi

# ⚙️ Build configuration
SECONDS=0
DEFCONFIG="vendor/xiaomi/miatoll_defconfig"

# 🧰 Set up environment variables for the build
export PATH="$HOME/cosmic/bin:$PATH"
export ARCH=arm64
export KBUILD_BUILD_USER=AzyrRuthless
export KBUILD_COMPILER_STRING="$("$HOME/cosmic/bin/clang" --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

# 🚀 Start compilation
echo -e "\n🚀 Starting compilation...\n"
mkdir -p out
make O=out $DEFCONFIG

# Handle flags for cleaning or regenerating defconfig
if [[ "$1" == "-c" || "$1" == "--clean" ]]; then
  echo "🧹 Cleaning output directory..."
  rm -rf out
  echo "✅ Output directory cleaned."
fi

if [[ "$1" == "-r" || "$1" == "--regen" ]]; then
  echo "🔄 Regenerating defconfig..."
  make O=out ARCH=arm64 $DEFCONFIG savedefconfig
  cp out/defconfig arch/arm64/configs/$DEFCONFIG
  echo "✅ Defconfig regenerated."
  exit 0
fi

make -j$(nproc --all) O=out ARCH=arm64 CC=clang LLVM=1 LLVM_IAS=1 LD=ld.lld CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- | tee build.log

# Check for build success
if [[ $? -ne 0 ]]; then
  echo -e "\n❌ Compilation failed!"
  tg "❌ Kernel build failed!"
  tg_doc "build.log" "❌ Build failed after $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)"
  exit 1
fi

# Build success actions
echo -e "\n✅ Kernel compiled successfully! Zipping up...\n"

# 🌳 Clone AnyKernel3 and prepare the zip
if ! git clone -q https://github.com/ihsanulrahman/AnyKernel3 -b udc; then
  echo -e "\n❌ Cloning AnyKernel3 repo failed! Aborting..."
  exit 1
fi

cp out/arch/arm64/boot/Image.gz AnyKernel3
cp out/arch/arm64/boot/dtbo.img AnyKernel3
cp out/arch/arm64/boot/dts/qcom/cust-atoll-ab.dtb AnyKernel3/dtb

rm -f ./*zip
cd AnyKernel3 || { echo "❌ Failed to cd into AnyKernel3"; exit 1; }
zip -r9 "../$ZIPNAME" ./* -x '*.git*' README.md ./*placeholder
cd .. || { echo "❌ Failed to cd back to parent directory"; exit 1; }

# 🧹 Cleanup
rm -rf AnyKernel3 out

# 🎉 Build completion message
echo -e "\n🎉 Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "🗜️ Zip: $ZIPNAME"

# 📢 Send success notification
tg "✅ Kernel build completed! $ZIPNAME"
tg_doc "$ZIPNAME" "✅ Build finished after $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)"
