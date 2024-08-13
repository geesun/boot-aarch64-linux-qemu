
在学习Linux的过程中，调试必不可少。之前有写了一篇 `在Arm FVP上使用Arm DS开发和调试  <{filename}/linux/setup/01_setup_tf_a_u_boot_linux_fvp.rst>`_ 。
虽然Arm的Base FVP已经可以免费使用，但是Arm DS还是需要收费的。没有Arm DS license的话，搭建起来就不是那么容易。 

这里就重新在开源的QEMU平台上搭建一个Trusted Firmware-A + U-boot + Linux kernel的开发环境，  
如下所有的步骤最终都汇聚在我的github `boot-aarch64-linux-qemu <https://github.com/geesun/boot-aarch64-linux-qemu/>`_  ，如果仅仅是使用，不需要知道它的具体细节的，建议直接使用github仓库提供的Makefile。 

开发环境准备
------------

1. 在Ububtu上安装必要的包

.. code-block:: sh 

	sudo apt-get install make autoconf build-essential git wget fuseext2 tmux 

2. 下载交叉编译工具

Arm gcc 可以在 `arm-gnu-toolchain-downloads <https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads>`_, 这里可以根据自己的系统来选择下载对应的gcc. 

一般我们使用的是x86_64 Linux host， 所以下载 `AArch64 GNU/Linux target for x86_64 Linux host <https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz>`_

可以在Ubuntu 终端中，使用如下命令： 

.. code-block:: sh 

	cd $(workspace)/tools
	wget https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
	tar -xvf arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz


下载代码
------------------

1. 下载 Qemu, TF-A，u-boot, Linux 和 buildroot 

要把linux boot起来，这里需要使用到Qemu, TF-A，u-boot,Linux和buildroot，这里使用的都是最新的代码，如果在使用过程中发现问题，可能需要使用某个比较稳定的版本。 

这里使用如下命令来下载代码： 

.. code-block:: sh 

	cd $(workspace)/src
	git clone https://git.denx.de/u-boot
	git clone https://git.trustedfirmware.org/TF-A/trusted-firmware-a tf-a 
	git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
	git clone https://gitlab.com/buildroot.org/buildroot.git
	git clone https://gitlab.com/qemu-project/qemu.git -b v9.0.2

经测试，在Ubuntu 20.04上，qemu最好使用v9.0.2。


编译代码
-----------

1. 编译qemu代码

编译qemu代码要使用到python virtualenv的环境，这里首先使用如下命令创建python的环境： 

.. code-block::sh 

	python3 -m venv $(workspace)/tools/venv

接下来就可以使用如下命令来配置和编译qemu： 

.. code-block:: sh 

	source $(workspace)/tools/venv/bin/activate &&  cd $(workspace)/src/qemu/ && ./configure --target-list=aarch64-softmmu --enable-virtfs
	source $(workspace)/tools/venv/bin/activate &&  make -C $(workspace)/src/qemu  

这里还有几个关键的信息，在后面编译u-boot的时候需要使用到，准备好所有的image之后，会使用如下命令来运行qemu，当然参数可以根据自己的情况进行调整： 

.. code-block:: sh 

	src/qemu/build/qemu-system-aarch64 \
		-M virt,gic-version=3,virtualization=on,type=virt,mte=on,secure=on \
		-nographic   \
		-cpu max -nographic -m 16G \
		-smp 16 \
		-bios src/tf-a/build/qemu/debug/flash.bin   \
		-device loader,file=src/linux/arch/arm64/boot/Image,addr=0x40400000 \
		-drive file=rootfs/rootfs.img,if=virtio,format=raw  \

所以在qemu平台上，有

- PL011串口的基地址：0x9000000 
- Kernel image加载地址：0x40400000 
- Device tree加载地址：0x40000000

	Qemu平台会根据运行给的参数，会自动生成device tree放在0x40000000地址。 

2. 编译u-boot代码

在编译u-boot代码之前，需要根据Linux kernel和rootfs的信息来配置u-boot的BOOTARGS和BOOTCOMMAND。 这里有几个比较关键的参数： 

- BOOTARGS中的root参数

这里使用了 root=/dev/vda1, 这是因为后面做rootfs的时候，使用了qemu的virtio这个参数： 

.. code-block:: sh 

	-drive file=rootfs/grub-busybox.img,if=virtio,format=raw 

而制作rootfs 的时候，rootfs会放到第一个分区，所以就是vda1。

- BOOTCOMMAND中kernel Image 和device tree的地址

这里使用了 booti 0x40400000 - 0x40000000，这个是因为在启动qemu的时候，有如下参数： 

.. code-block:: sh 

    -device loader,file=src/linux/arch/arm64/boot/Image,addr=0x40400000 


根据上面的描述，使用如下命令来配置u-boot： 

.. code-block:: sh 

	cd $(workspace)/src/u-boot 
	echo "CONFIG_USE_BOOTARGS=y" > qemu.cfg 
	echo "CONFIG_BOOTARGS=\"console=ttyAMA0 earlycon=pl011,0x9000000 root=/dev/vda1 rw debug user_debug=31 nokaslr loglevel=9\"" >> qemu.cfg 
	echo "CONFIG_BOOTCOMMAND=\"booti 0x40400000 - 0x40000000\"" >> qemu.cfg 
	export ARCH=aarch64 ;
	export CROSS_COMPILE=$(CROSS_COMPILE) ;
	make qemu_arm64_defconfig;
	scripts/kconfig/merge_config.sh -m -O ./ .config qemu.cfg ;

这里的CROSS_COMPILE 可以根据前面下载的gcc来决定，这里可以把他设置成： 

.. code-block:: sh 

	export CROSS_COMPILE=$(workspace)/tools/arm-gnu-toolchain-13.2.Rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu- 


配置完成之后，可以打开u-boot目录下的.config 来确保CONFIG_USE_BOOTARGS,CONFIG_BOOTARGS 和 CONFIG_BOOTCOMMAND已经设置成期望的值。

.. code-block:: sh 

	CONFIG_BOOTARGS="console=ttyAMA0 earlycon=pl011,0x9000000 root=/dev/vda1 rw debug user_debug=31 nokaslr loglevel=9"
	CONFIG_BOOTCOMMAND="booti 0x40400000 - 0x40000000"


接下来使用如下命令来编译u-boot： 

.. code-block:: sh 

	cd $(workspace)/src/u-boot 
	export ARCH=aarch64 ;
	export CROSS_COMPILE=$(CROSS_COMPILE) ;
	make 

这一步做完，最终生成 src/u-boot/u-boot.bin. 


2. 编译tf-a代码

编译在tf-a的过程中，u-boot是作为tf-a的BL33的image，所以需要先编译前面的u-boot后，才能编译tf-a，使用如下命令： 

.. code-block:: sh 

	export CROSS_COMPILE=$(CROSS_COMPILE) 
	cd $(workspace)/src/tf-a
	make PLAT=qemu DEBUG=1 BL33=$(workspace)/src/u-boot/u-boot.bin all fip V=1 ENABLE_FEAT_MTE2=1 QEMU_USE_GIC_DRIVER=QEMU_GICV3
	dd if=build/qemu/debug/bl1.bin of=build/qemu/debug/flash.bin bs=4096 conv=notrunc
	dd if=build/qemu/debug/fip.bin of=build/qemu/debug/flash.bin seek=64 bs=4096 conv=notrunc

这里面仅仅是使用了tf-a的默认配置，如TTBR等feature 都有没有使能。 如果需要使能更多feature，可以根据自己的需求添加。 

从上面的命令可以看出, u-boot 是被打包到flash.bin里面，所以如果更改了u-boot，必须重新运行tf-a的编译过程，把u-boot重新打包到flash.bin里面。 

更多关于QEMU的TF-A， 参考 `QEMU virt Armv8-A <https://trustedfirmware-a.readthedocs.io/en/latest/plat/qemu.html>`_ .



3. 编译Linux kernel代码

编译Linux kernel，这里使用kernel中的默认配置，即defconfig。即使用如下命令来配置kernel： 

.. code-block:: sh 

	cd $(workspace)/src/linux
	make -C $(SRC_DIR)/linux ARCH=arm64 defconfig CROSS_COMPILE=$(CROSS_COMPILE)
	make -C $(SRC_DIR)/linux ARCH=arm64 olddefconfig CROSS_COMPILE=$(CROSS_COMPILE)
	

如果想要对kernel 进行额外的配置，使用如下命令：

.. code-block:: sh 

	cd $(workspace)/src/linux
	make -C $(SRC_DIR)/linux ARCH=arm64 menuconfig CROSS_COMPILE=$(CROSS_COMPILE)

配置完成之后，如下命令可以用来进行编译： 

.. code-block:: sh 

	cd $(workspace)/src/linux
	make -C $(SRC_DIR)/linux ARCH=arm64 Image CROSS_COMPILE=$(CROSS_COMPILE) Image dtbs scripts_gdb


编译buildroot
-------------------

第一步要配置buildroot，这里根据toolchain的情况，在buildroot目录下面的configs建立如下配置文件 configs/arm_qemu_defconfig： 

.. code-block:: sh 

	cd $(workspace)/src/buildroot
	$cat configs/arm_qemu_defconfig
		BR2_aarch64=y
		BR2_TOOLCHAIN_EXTERNAL=y
		BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y
		BR2_TOOLCHAIN_EXTERNAL_PATH="../../tools/arm-gnu-toolchain-13.2.Rel1-x86_64-aarch64-none-linux-gnu/"
		# BR2_STRIP_strip is not set
		BR2_OPTIMIZE_0=y
		BR2_TARGET_GENERIC_HOSTNAME="Qemu"
		BR2_TARGET_GENERIC_ISSUE="Welcome to Qemu"
		BR2_PACKAGE_GDB=y
		BR2_PACKAGE_GDB_SERVER=y
		BR2_PACKAGE_GDB_DEBUGGER=y
		BR2_PACKAGE_KEXEC=y
		BR2_PACKAGE_KEXEC_ZLIB=y
		BR2_PACKAGE_BINUTILS=y
		BR2_PACKAGE_BINUTILS_TARGET=y
		BR2_PACKAGE_TREE=y
		BR2_PACKAGE_E2FSPROGS=y
		BR2_PACKAGE_E2FSPROGS_DEBUGFS=y
		BR2_PACKAGE_KVMTOOL=y
		BR2_PACKAGE_MAKEDUMPFILE=y
		BR2_TARGET_ROOTFS_EXT2=y
		BR2_TARGET_ROOTFS_EXT2_3=y
		BR2_TARGET_ROOTFS_EXT2_SIZE="256M"

第二步根据需求修改buildroot的配置，如下命令：

.. code-block:: sh 

	make -C $(SRC_DIR)/buildroot arm_qemu_defconfig
	make -C $(SRC_DIR)/buildroot menuconfig  # 这步可以修改配置文件
	make -C $(SRC_DIR)/buildroot savedefconfig  # 这步会把.config 复制到configs/arm_qemu_defconfig里面


第三步编译buildroot，如下命令： 

.. code-block:: sh 

	make -C $(SRC_DIR)/buildroot arm_qemu_defconfig
	make -C $(SRC_DIR)/buildroot 

最终buildroot会生成$(workspace)/src/buildroot/output/images/rootfs.tar


重制rootfs
-------------------

buildroot本身其实会生成ext2/3的rootfs格式，参考文件 $(workspace)/src/buildroot/output/images/，QEMU也是可以直接使用这些格式的。

但是有些时候可能需要往文件系统里面加一些文件来进行调试，所以下面的步骤就记录一下如何把rootfs重新打包成gdisk文件。 

1. 解压rootfs.tar  

.. code-block:: sh 

	mkdir -p $(workspace)/rootfs/tmp/rootfs/ -p 
	cd rootfs/tmp/rootfs 
	tar -xvf $(workspace)/src/buildroot/output/images/rootfs.tar


2. 修改rootfs 

在目录 $(workspace)/src/rootfs/tmp/rootfs ，可以根据自己的需求来增加或者删减文件。

这一步不是必须的，是根据需求来决定的，如果没有改动需求，这一步可以跳过。 


3. 生成rootfs的partition文件

.. code-block:: sh 

	cd $(workspace)/src/rootfs/tmp

	export BLOCK_SIZE=512
	export SEC_PER_MB=$((1024*2))
	export EXT3_SIZE_MB=512
	export PART_START=$((1*SEC_PER_MB))
	export EXT3_SIZE=$((EXT3_SIZE_MB*SEC_PER_MB))
	dd if=/dev/zero of=ext3_part bs=$BLOCK_SIZE count=$EXT3_SIZE
	mkdir -p mnt
	mkfs.ext3 -F ext3_part
	fuse-ext2 ext3_part mnt -o rw+
	cp -rf rootfs/* mnt/
	sync
	fusermount -u mnt
	rm -rf mnt

这里rootfs的最大大小是512M，如果需要调整大小，可以调整EXT3_SIZE_MB=512的值。

完成这一步，就生成了一个ext3的rootfs partition文件ext3_part，下一步会把这个分区文件放在磁盘映像文件的第一个分区。  

4. 使用gdisk生成rootfs的磁盘映像文件

.. code-block:: sh 

	cd $(workspace)/src/rootfs/tmp

	export BLOCK_SIZE=512
	export SEC_PER_MB=$((1024*2))
	export EXT3_SIZE_MB=512
	export PART_START=$((1*SEC_PER_MB))
	export EXT3_SIZE=$((EXT3_SIZE_MB*SEC_PER_MB))
	export IMG_BB=../rootfs.img 
	dd if=/dev/zero of=part_table bs=$BLOCK_SIZE count=$PART_START

	cat part_table > $IMG_BB
	cat ext3_part >> $IMG_BB
	cat part_table >> $IMG_BB
	(echo n; echo 1; echo $PART_START; echo +$((EXT3_SIZE)); echo 8300; echo w; echo y) | gdisk $IMG_BB

这里就完成了把上一步生成的ext3_part放在$(workspace)/src/rootfs/rootfs.img 的第一个分区。 

文件$(workspace)/src/rootfs/rootfs.img就是最终的要传给QEMU的rootfs。


在QEMU上运行Linux
------------------

确保前面几节已经准备了如下的images： 

.. code-block:: sh
  
	$(workspace)/src/tf-a/build/fvp/debug/flash.bin 
	$(workspace)/src/linux/arch/arm64/boot/Image  
	$(workspace)/rootfs/rootfs.img


接下来就可以使用下面的命令来运行Linux：

.. code-block:: sh 

	cd $(workspace)
	src/qemu/build/qemu-system-aarch64 \
		-M virt,gic-version=3,virtualization=on,type=virt,mte=on,secure=on \
		-nographic   \
		-cpu max -nographic -m 16G \
		-smp 16 \
		-bios src/tf-a/build/qemu/debug/flash.bin   \
		-device loader,file=src/linux/arch/arm64/boot/Image,addr=0x40400000 \
		-drive file=rootfs/rootfs.img,if=virtio,format=raw  \


在GDB上调试Linux
---------------------

如果要启动GDB调试整个software stack，在启动QEMU的时候需要加上： -S -s 这些参数，这样QEMU就会停在那里等待GDB开始调试。 

启动脚本： 

.. code-block:: sh 

	cd $(workspace)
	src/qemu/build/qemu-system-aarch64 \
		-M virt,gic-version=3,virtualization=on,type=virt,mte=on,secure=on \
		-nographic   \
		-cpu max -nographic -m 16G \
		-smp 16 \
		-bios src/tf-a/build/qemu/debug/flash.bin   \
		-device loader,file=src/linux/arch/arm64/boot/Image,addr=0x40400000 \
		-drive file=rootfs/rootfs.img,if=virtio,format=raw  \
		-S -s 

新开一个窗口，使用aarch64-linux-gdb 或者gdb-multiarch 就可以开始调试啦： 

.. code-block:: sh 

	src/linux$ cat gdb.ds
	target remote :1234
	add-symbol-file ../../src/tf-a/build/qemu/debug/bl1/bl1.elf
	add-symbol-file ../../src/tf-a/build/qemu/debug/bl2/bl2.elf
	add-symbol-file ../../src/tf-a/build/qemu/debug/bl31/bl31.elf

	add-symbol-file vmlinux -o  0x7fffc0400000
	add-symbol-file vmlinux


	src/linux$ gdb-multiarch  vmlinux
	GNU gdb (Ubuntu 9.2-0ubuntu1~20.04.2) 9.2
	Copyright (C) 2020 Free Software Foundation, Inc.
	License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>
	This is free software: you are free to change and redistribute it.
	There is NO WARRANTY, to the extent permitted by law.
	Type "show copying" and "show warranty" for details.
	This GDB was configured as "x86_64-linux-gnu".
	Type "show configuration" for configuration details.
	For bug reporting instructions, please see:
	<http://www.gnu.org/software/gdb/bugs/>.
	Find the GDB manual and other documentation resources online at:
	    <http://www.gnu.org/software/gdb/documentation/>.

	For help, type "help".
	Type "apropos word" to search for commands related to "word"...
	Reading symbols from vmlinux...
	(gdb) source gdb.ds
	0x0000000000000000 in ?? ()
	add symbol table from file "../../src/tf-a/build/qemu/debug/bl1/bl1.elf"
	add symbol table from file "../../src/tf-a/build/qemu/debug/bl2/bl2.elf"
	add symbol table from file "../../src/tf-a/build/qemu/debug/bl31/bl31.elf"
	add symbol table from file "vmlinux" with all sections offset by 0x7fffc0400000
	add symbol table from file "vmlinux"
	(gdb) break bl31_main
	Breakpoint 1 at 0xe0a23d0: file bl31/bl31_main.c, line 130.
	(gdb) break _text
	Breakpoint 2 at 0x40400000: _text. (2 locations)
	(gdb) break start_kernel
	Breakpoint 3 at 0x42010928: start_kernel. (2 locations)
	(gdb) c
	Continuing.

	Thread 1 hit Breakpoint 1, bl31_main () at bl31/bl31_main.c:130
	130             cm_manage_extensions_el3();
	(gdb) bt
	#0  bl31_main () at bl31/bl31_main.c:130
	#1  0x000000000e0a00c0 in bl31_entrypoint () at bl31/aarch64/bl31_entrypoint.S:93
	Backtrace stopped: previous frame identical to this frame (corrupt stack?)
	(gdb) c
	Continuing.

	Thread 1 hit Breakpoint 2, _text () at arch/arm64/kernel/head.S:60
	60              efi_signature_nop                       // special NOP to identity as PE/COFF executable
	(gdb) x/4i $pc
	=> 0x40400000 <_text>:  ccmp    x18, #0x0, #0xd, pl  // pl = nfrst
	   0x40400004 <_text+4>:        b       0x420000e0 <primary_entry>
	   0x40400008 <_text+8>:        .inst   0x00000000 ; undefined
	   0x4040000c <_text+12>:       .inst   0x00000000 ; undefined
	(gdb) c
	Continuing.

	Thread 1 hit Breakpoint 3, start_kernel () at init/main.c:908
	908             set_task_stack_end_magic(&init_task);
	(gdb) l
	903     void start_kernel(void)
	904     {
	905             char *command_line;
	906             char *after_dashes;
	907
	908             set_task_stack_end_magic(&init_task);
	909             smp_setup_processor_id();
	910             debug_objects_early_init();
	911             init_vmlinux_build_id();



至于为什么vmlinux 要被加两遍符号表，因为如果要调试在MMU没有enable的代码，就需要加： 

.. code-block:: sh 

	add-symbol-file vmlinux -o  0x7fffc0400000

计算方法： 

.. code-block:: sh 

	0x40400000 - 0xffff800080000000 = 0x7fffc0400000 

0x40400000 为u-boot kernel加载的地址，而0xffff800080000000 是 _text在linux kernel符号表的位置： 

.. code-block:: sh 

	grep " _text"  src/linux/System.map
	ffff800080000000 T _text



更多可以参考 

- `Running a full arm64 system stack under QEMU <https://cdn.kernel.org/pub/linux/kernel/people/will/docs/qemu/qemu-arm64-howto.html>`_ .

- `Debugging kernel and modules via gdb <https://docs.kernel.org/dev-tools/gdb-kernel-debugging.html#examples-of-using-the-linux-provided-gdb-helpers>`_ .




