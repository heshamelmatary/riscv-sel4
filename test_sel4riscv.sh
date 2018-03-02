#!/bin/bash
# ------------------------------------------------------------------
# [Author] Hesham Almatary
#          This script builds riscv-tools and seL4/sel4test ports
#          making sure that the correct/tested versions are used.
# ------------------------------------------------------------------

# Assuming OS is Ubuntu 16.04.3 LTS, the following packages (or equivalent, depending on your OS) are required
# in order to build the tools.
#
# General packages:
# sudo apt-get install git repo
#
# For RISC-V tools:
# sudo apt-get install autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev libusb-1.0-0-dev gawk build-essential bison flex texinfo gperf libtool patchutils bc zlib1g-dev device-tree-compiler pkg-config
#
# For RISC-V QEMU:
# sudo apt-get install libglib2.0-dev zlib1g-dev libpixman-1-dev
#
# For seL4:
# sudo apt-get install build-essential realpath libxml2-utils python-pip
# sudo apt-get install gcc-multilib ccache ncurses-dev cpio
# sudo pip install --upgrade pip
# sudo pip install sel4-deps

# --- Need to know where to install the tools ----------------------
if [ "x$RISCV" = "x" ]
then
  echo "Please set the RISCV environment variable to your preferred install path."
  exit 1
fi

GREEN='\033[0;32m'
NC='\033[0m'

# --- Export PATH to include RISC-V tools (e.g. gcc, spike, etc) ---
SRC_ROOT=$PWD
export PATH="$RISCV/bin:$PATH"

set -e

# (1) Get riscv-tools
echo -e "${GREEN}########## Get RISC-V Toolchain (riscv-tools) ########${NC}"
git clone https://github.com/riscv/riscv-tools.git

## Check out a revision that works (and tested) with seL4
cd riscv-tools
git checkout priv-1.10
git submodule update --init --recursive

## Get/Setup RISC-V QEMU
echo -e "${GREEN}########## Get RISC-V QEMU ########${NC}"
git clone https://github.com/heshamelmatary/riscv-qemu.git
cd riscv-qemu
git checkout sfence
git submodule update --init dtc
echo -e "${GREEN}########## Build RISC-V QEMU ########${NC}"
./configure --target-list=riscv64-softmmu,riscv32-softmmu --prefix=$RISCV
make -j 8 && make install
cd ..

# (2) Setup riscv-tools/gnu-riscv to build "soft-float" toolchain
sed -i 's/build_project riscv-gnu-toolchain --prefix=$RISCV/build_project riscv-gnu-toolchain --prefix=$RISCV --with-arch=rv64imafdc --with-abi=lp64 --enable-multilib/g' ./build.sh

# (3) Build riscv-tools

## 64-bit
echo -e "${GREEN}########## Build 64-bit Toolchain ########${NC}"
./build.sh

## 32-bit
echo -e "${GREEN}########## Build 32-bit Toolchain ########${NC}"
./build-rv32ima.sh


# (4) Get sel4test/riscv
echo -e "${GREEN}########## Get sel4test/riscv ########${NC}"
cd $SRC_ROOT
mkdir sel4test && cd sel4test
repo init -u http://halmatary@bitbucket.keg.ertos.in.nicta.com.au/scm/~halmatary/sel4test-manifest.git -m sel4test-28022018.xml
repo sync

# (5) build, test and run RV64 sel4test
echo -e "${GREEN}########## Build sel4test (RV64) ########${NC}"
make bamboo_riscv64_defconfig
make -j8

## Put the sel4test image path in a variable to be used by bbl
export SEL4_IMAGE=$PWD/images/sel4test-driver-image-riscv-spike

## Go to riscv-pk to build bbl (which should contain/embed sel4test image as a payload)
echo -e "${GREEN}########## Build riscv-pk/bbl with sel4test image ########${NC}"
cd $SRC_ROOT/riscv-tools/riscv-pk/build
../configure --prefix=$RISCV --host=riscv64-unknown-elf --with-payload=${SEL4_IMAGE}  --enable-logo
make clean && make -j8

# (6) Finally, run bbl/sel4test

# On QEMU
echo -e "${GREEN}########## Run sel4test (RV64) on QEMU ########${NC}"
qemu-system-riscv64 -kernel ./bbl -nographic -machine spike_v1.10 -m 4095M

# On Spike
echo -e "${GREEN}########## Run sel4test (RV64) on Spike ########${NC}"
spike --isa=RV64 ./bbl
