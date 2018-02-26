#!/bin/bash
# ------------------------------------------------------------------
# [Author] Hesham Almatary
#          This script builds riscv-tools and seL4/sel4test ports
#          making sure that the correct/tested versions are used.
# ------------------------------------------------------------------

# --- Need to know where to install the tools ----------------------
if [ "x$RISCV" = "x" ]
then
  echo "Please set the RISCV environment variable to your preferred install path."
  exit 1
fi

# --- Export PATH to include RISC-V tools (e.g. gcc, spike, etc) ---
SRC_ROOT=$PWD
PATH="$RISCV/bin:$PATH"

# (1) Get riscv-tools
git clone https://github.com/riscv/riscv-tools.git

## Check out a revision that works (and tested) with seL4
cd riscv-tools
git checkout 9868299
git submodule update --init --recursive

## Get/Setup RISC-V QEMU
git clone https://github.com/riscv/riscv-qemu.git
cd riscv-qemu
git checkout 6256f8a
git submodule update --init dtc
./configure --target-list=riscv64-softmmu,riscv32-softmmu --prefix=$RISCV
make -j 8 && make install
cd ..

# (2) Setup riscv-tools/gnu-riscv to build "soft-float" toolchain
sed -i 's/build_project riscv-gnu-toolchain --prefix=$RISCV/build_project riscv-gnu-toolchain --prefix=$RISCV --with-arch=rv64ima --with-abi=lp64/g'

# (3) Build riscv-tools

## 64-bit
./build.sh

## 32-bit
./build-rv32ima.sh


# (4) Get sel4test/riscv
cd $SRC_ROOT
mkdir sel4test && cd sel4test
repo init -u ssh://git@bitbucket.keg.ertos.in.nicta.com.au:7999/~halmatary/sel4test-manifest.git -m sel4test-28022018.xml
repo sync

# (5) build, test and run RV64 sel4test
make bamboo_riscv64_defconfig
make -j8

## Put the sel4test image path in a variable to be used by bbl
SEL4_IMAGE=$PWD/images/sel4test-driver-image-riscv-spike

## Go to riscv-pk to build bbl (which should contain/embed sel4test image as a payload)
cd $SRC_ROOT/riscv-tools/riscv-pk/build
../configure --prefix=$RISCV --host=riscv64-unknown-elf --with-payload=$SEL4_IMAGE  --enable-logo
make clean && make -j8

# (6) Finally, run bbl/sel4test

# On QEMU
qemu-system-riscv64 -kernel ./bbl -nographic -machine spike_v1.10 -m 4095M

# On Spike
spike --isa=RV64 ./bbl
