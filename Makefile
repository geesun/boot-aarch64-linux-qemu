SRC_DIR 		:= $(shell pwd)/src
TOOLS_DIR 		:= $(shell pwd)/tools

CROSS_COMPILE 	:= $(TOOLS_DIR)/arm-gnu-toolchain-13.2.Rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
#CC 				:= CC=$(TOOLS_DIR)/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04/bin/clang
CC 				:= CC=$(CROSS_COMPILE)gcc

LD 				:= $(CROSS_COMPILE)ld
GRUB_BUSYBOX_IMG := $(shell pwd)/rootfs/grub-busybox.img

UBOOT_CONFIG 	:= qemu_arm64_defconfig
USE_BOOTARGS	:= "CONFIG_USE_BOOTARGS=y" 
BOOTCMD			:= "CONFIG_BOOTCOMMAND=\"booti 0x40400000 - 0x40000000\""
BOOTARGS		:= "CONFIG_BOOTARGS=\"console=ttyAMA0 earlycon=pl011,0x9000000 root=/dev/vda1 rw debug loglevel=9 nokaslr  kvm-arm.mode=protected \""

JOBS 			:= $(shell nproc)
PYENV       	:= tools/venv
FW_BIN          := src/tf-a/build/qemu/debug/flash.bin

.PHONY: all clone download u-boot.build u-boot.clean tf-a.build tf-a.clean \
	linux.build linux.clean linux.mod buildroot.build buildroot.clean \
	buildroot.savecfg  build run debug clean qemu.build qemu.clean  \

all: clone download build 

clone:
	@ mkdir -p $(SRC_DIR)
	@ [ -d "$(SRC_DIR)/u-boot" ] || git clone https://git.denx.de/u-boot $(SRC_DIR)/u-boot
	@ [ -d "$(SRC_DIR)/tf-a" ] || git clone https://git.trustedfirmware.org/TF-A/trusted-firmware-a  $(SRC_DIR)/tf-a
	@ [ -d "$(SRC_DIR)/linux" ] || git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git $(SRC_DIR)/linux
	@ [ -d "$(SRC_DIR)/buildroot" ] || git clone https://gitlab.com/buildroot.org/buildroot.git $(SRC_DIR)/buildroot
	@ [ -d "$(SRC_DIR)/qemu" ] || git clone https://gitlab.com/qemu-project/qemu.git $(SRC_DIR)/qemu

download:
	@ mkdir -p $(TOOLS_DIR)
	@ [ -f "$(TOOLS_DIR)/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz" ] || wget -P $(TOOLS_DIR) https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
	@ [ -f "$(TOOLS_DIR)/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz" ] || wget -P $(TOOLS_DIR) https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz
	@ [ -d "$(TOOLS_DIR)/arm-gnu-toolchain-13.2.Rel1-x86_64-aarch64-none-linux-gnu" ] || tar -C $(TOOLS_DIR) -xvf $(TOOLS_DIR)/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
	@ [ -d "$(TOOLS_DIR)/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04" ] || tar -C $(TOOLS_DIR) -xvf $(TOOLS_DIR)/clang+llvm-18.1.8-x86_64-linux-gnu-ubuntu-18.04.tar.xz

qemu.build:
ifeq ($(wildcard $(PYENV)),)
	python3 -m venv $(PYENV)
endif
	. $(PYENV)/bin/activate &&  cd src/qemu/ && ./configure --target-list=aarch64-softmmu --enable-virtfs 
	. $(PYENV)/bin/activate &&  make -C src/qemu  -j $(JOBS)

qemu.clean:
	make -C src/qemu  clean

u-boot.build:
	export ARCH=aarch64 ; \
	export CROSS_COMPILE=$(CROSS_COMPILE) ; \
	cd $(SRC_DIR)/u-boot ;\
	echo $(USE_BOOTARGS) > qemu.cfg; \
	echo $(BOOTARGS) >> qemu.cfg; \
	echo $(BOOTCMD) >> qemu.cfg; \
	make -j $(JOBS)  $(UBOOT_CONFIG);\
	scripts/kconfig/merge_config.sh -m -O ./ .config qemu.cfg; \
	make -j $(JOBS)  ;

u-boot.clean:
	make -C $(SRC_DIR)/u-boot clean 

tf-a.build: u-boot.build
	export CROSS_COMPILE=$(CROSS_COMPILE) ; \
	cd $(SRC_DIR)/tf-a; \
	make PLAT=qemu DEBUG=1 BL33=$(SRC_DIR)/u-boot/u-boot.bin all fip V=1 ENABLE_FEAT_MTE2=1 QEMU_USE_GIC_DRIVER=QEMU_GICV3
	rm -rf $(FW_BIN)
	dd if=src/tf-a/build/qemu/debug/bl1.bin of=$(FW_BIN) bs=4096 conv=notrunc
	dd if=src/tf-a/build/qemu/debug/fip.bin of=$(FW_BIN) seek=64 bs=4096 conv=notrunc

tf-a.clean: 
	export CROSS_COMPILE=$(CROSS_COMPILE) ; \
	rm -rf $(FW_BIN)
	make PLAT=qemu -C $(SRC_DIR)/tf-a  realclean

linux.build: 
	[ -f "$(SRC_DIR)/linux/.config" ] ||  make -C $(SRC_DIR)/linux ARCH=arm64 defconfig $(CC) CROSS_COMPILE=$(CROSS_COMPILE)
	make -C $(SRC_DIR)/linux ARCH=arm64 $(CC) CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig
	make -C $(SRC_DIR)/linux ARCH=arm64 -j $(JOBS) $(CC) CROSS_COMPILE=$(CROSS_COMPILE) Image dtbs

linux.mod:
	make -C $(SRC_DIR)/linux ARCH=arm64 -j $(JOBS) $(CC) CROSS_COMPILE=$(CROSS_COMPILE) modules
	make -C $(SRC_DIR)/linux ARCH=arm64 -j $(JOBS) $(CC) CROSS_COMPILE=$(CROSS_COMPILE) INSTALL_MOD_PATH=$(shell pwd)/rootfs/overlay  modules_install

linux.menuconfig:
	[ -f "$(SRC_DIR)/linux/.config" ] ||  make -C $(SRC_DIR)/linux ARCH=arm64 defconfig $(CC) CROSS_COMPILE=$(CROSS_COMPILE)
	make -C $(SRC_DIR)/linux ARCH=arm64 $(CC) CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig
	make -C $(SRC_DIR)/linux ARCH=arm64 -j $(JOBS) $(CC) CROSS_COMPILE=$(CROSS_COMPILE) menuconfig

linux.clean:
	make -C $(SRC_DIR)/linux ARCH=arm64 clean 

buildroot.build:
	cp buildroot.cfg $(SRC_DIR)/buildroot/configs/arm_aem_fvp_defconfig
	make -C $(SRC_DIR)/buildroot arm_aem_fvp_defconfig
	make -C $(SRC_DIR)/buildroot  -j $(JOBS)
	mkdir -p rootfs/tmp/rootfs/ -p && cd rootfs/tmp/rootfs && tar -xvf $(SRC_DIR)/buildroot/output/images/rootfs.tar
	[ -z "$(shell ls -A rootfs/overlay)" ] || cp rootfs/overlay/* rootfs/tmp/rootfs/ -a
	cd rootfs/tmp && ../gen-rootfs
	rm -rf rootfs/tmp

buildroot.clean:
	make -C $(SRC_DIR)/buildroot clean

buildroot.savecfg:
	make -C $(SRC_DIR)/buildroot savedefconfig
	cp $(SRC_DIR)/buildroot/configs/arm_aem_fvp_defconfig  buildroot.cfg
		


build: u-boot.build tf-a.build linux.build buildroot.build qemu.build

dtb.dump:
	src/qemu/build/qemu-system-aarch64 \
		-M virt,gic-version=3,virtualization=on,type=virt,mte=on,secure=on \
		-nographic   \
	  	-cpu max -nographic -m 16G \
	    -smp 16 \
		-machine dumpdtb=qemu.dtb  
	src/linux/scripts/dtc/dtc -o qemu.dts -O dts -I dtb qemu.dtb

dtb.build:
	src/linux/scripts/dtc/dtc -o qemu.dtb -O dtb -I dts qemu.dts

ifneq ($(wildcard qemu.dtb),)
DTB_OPTION 		:=-dtb qemu.dtb
endif 

run:
	src/qemu/build/qemu-system-aarch64 \
		-M virt,gic-version=3,virtualization=on,type=virt,mte=on,secure=on \
		-nographic   \
	  	-cpu max -nographic -m 16G \
	    -smp 16 \
	    -bios $(FW_BIN)   \
		-device loader,file=src/linux/arch/arm64/boot/Image,addr=0x40400000 \
		$(DTB_OPTION) \
		-drive file=rootfs/grub-busybox.img,if=virtio,format=raw  \

debug:
	src/qemu/build/qemu-system-aarch64 \
		-M virt,gic-version=3,virtualization=on,type=virt,mte=on,secure=on \
		-nographic   \
	  	-cpu max -nographic -m 16G \
	    -smp 16 \
	    -bios $(FW_BIN)   \
		-device loader,file=src/linux/arch/arm64/boot/Image,addr=0x40400000 \
		$(DTB_OPTION) \
		-drive file=rootfs/grub-busybox.img,if=virtio,format=raw  \
		-s -S 

clean: fs.clean linux.clean tf-a.clean u-boot.clean buildroot.clean qemu.clean 

distclean:
	rm -rf $(GRUB_BUSYBOX_IMG)
	rm -rf $(SRC_DIR) $(TOOLS_DIR)


