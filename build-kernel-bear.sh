#!/bin/bash

set -e

# ===== 彩色输出函数 =====
info()    { echo -e "\033[1;32m[INFO]\033[0m $1"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m $1"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $1"; }
section() { echo -e "\n\033[1;36m==== $1 ====\033[0m\n"; }

# ===== 检查 Bear 工具 =====
if ! command -v bear &> /dev/null; then
    error "未找到 bear 工具，请先安装: sudo apt install bear"
    exit 1
fi

# ===== 配置变量 =====
K_SRC=$(pwd)
K_OUT="$K_SRC/out"

K_CM5_OUT="$K_OUT/cm5"
K_BUILD_OUT="$K_OUT/build"
K_MOD_OUT="$K_OUT/modules"
K_HDR_OUT="$K_OUT/headers"

K_VERSION="6.1.75"
DEFCONFIG="coolpi_linux_preempt_full_rt_defconfig"
LOCALVERSION=""
CPU_CORES=$(nproc)

# ===== 检测并设置交叉编译器 =====
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    export CROSS_COMPILE=aarch64-linux-gnu-
    info "使用交叉编译器: $CROSS_COMPILE"
fi

# ===== 清理构建目录 =====
section "1/8 清理构建目录"
rm -rf "$K_CM5_OUT"
mkdir -p "$K_CM5_OUT/extlinux" "$K_BUILD_OUT" "$K_MOD_OUT" "$K_HDR_OUT/usr/src/linux-headers-${K_VERSION}-rt23"

# ===== 清理构建输出(正确使用 O=)=====
section "2/8 清理构建输出目录(mrproper)"
make ARCH=arm64 O="$K_BUILD_OUT" mrproper

# ===== 配置 & 准备头文件 =====
section "3/8 配置内核并准备头文件"
make ARCH=arm64 O="$K_BUILD_OUT" LOCALVERSION="$LOCALVERSION" "$DEFCONFIG"
make ARCH=arm64 O="$K_BUILD_OUT" LOCALVERSION="$LOCALVERSION" prepare
make ARCH=arm64 O="$K_BUILD_OUT" LOCALVERSION="$LOCALVERSION" scripts

# ===== 使用 Bear 编译并生成 compile_commands.json =====
section "4/8 使用 Bear 编译内核并生成 compile_commands.json"
bear -- make ARCH=arm64 O="$K_BUILD_OUT" LOCALVERSION="$LOCALVERSION" -j"$CPU_CORES"

# ===== 编译模块与安装头文件 =====
section "5/8 构建模块并安装到 out_modules / out_headers"
make ARCH=arm64 O="$K_BUILD_OUT" LOCALVERSION="$LOCALVERSION" modules -j"$CPU_CORES"
make ARCH=arm64 O="$K_BUILD_OUT" LOCALVERSION="$LOCALVERSION" modules_install INSTALL_MOD_PATH="$K_MOD_OUT"
make ARCH=arm64 O="$K_BUILD_OUT" LOCALVERSION="$LOCALVERSION" headers_install INSTALL_HDR_PATH="$K_HDR_OUT/usr/src/linux-headers-${K_VERSION}"

# ===== 拷贝镜像与配置文件 =====
section "6/8 拷贝 Image / dtb / extlinux.conf / initrd.img"
cp -af "$K_BUILD_OUT/arch/arm64/boot/Image" "$K_CM5_OUT/Image"
cp -af "$K_BUILD_OUT/arch/arm64/boot/dts/rockchip/"*.dtb "$K_CM5_OUT"
cp -af demo-cfgs/extlinux_def_cm5_evb.conf "$K_CM5_OUT/extlinux/extlinux.conf"
cp -af demo-cfgs/initrd.img "$K_CM5_OUT/initrd.img"

# ===== 设置内核模块头文件软链接 =====
section "7/8 设置 source / build 软链接"
cd "$K_MOD_OUT/lib/modules/$K_VERSION"
unlink source 2>/dev/null || true
unlink build 2>/dev/null || true
ln -sf "/usr/src/linux-headers-${K_VERSION}" build
ln -sf "/usr/src/linux-headers-${K_VERSION}" source

# ===== 打包模块与头文件 =====
section "8/8 打包模块与头文件"
cd "$K_MOD_OUT/lib/"
tar -czf "$K_CM5_OUT/modules.tar.gz" *

cd "$K_HDR_OUT/usr/"
tar -czf "$K_CM5_OUT/headers.tar.gz" *

section "🎉 编译完成"
info "内核镜像路径: $K_CM5_OUT/Image"
info "模块包:       $K_CM5_OUT/modules.tar.gz"
info "头文件包:     $K_CM5_OUT/headers.tar.gz"
info "VSCode代码跳转配置: compile_commands.json 生成于 $K_OUT/compile_commands.json"

# ===== 自动复制 compile_commands.json 到根目录和 .vscode =====
section "拷贝 compile_commands.json 到项目根目录和 .vscode"
cp -af "$K_OUT/compile_commands.json" "$K_SRC/compile_commands.json"
info "✔ 已复制到项目根目录: $K_SRC/compile_commands.json"

if [ ! -d "$K_SRC/.vscode" ]; then
    mkdir -p "$K_SRC/.vscode"
    info "已创建 .vscode/ 目录"
fi

cp -af "$K_SRC/compile_commands.json" "$K_SRC/.vscode/compile_commands.json"
info "✔ 已复制到: $K_SRC/.vscode/compile_commands.json"

exit 0
