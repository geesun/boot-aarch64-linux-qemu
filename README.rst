=======================================================================================
Build and boot Arm64 Linux Kernel on Qemu with TF-A and u-boot 
=======================================================================================

This Makefile mainly demonstrates how to achieve booting the latest Linux kernel on QEMU platform using `Arm Trusted Firmware-A <https://www.trustedfirmware.org/projects/tf-a>`_ and `u-boot <https://source.denx.de/u-boot/u-boot>`_ through simple steps.
It also shows how to quickly debug the Linux Kernel using gdb with simple configurations.

Setup up environment 
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

1. Download toolchain 

.. code-block:: sh 

    make download

The latest toolchain can be found at the links below. 

- `AArch64 GNU/Linux target <https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads>`_

2. Clone all source

.. code-block:: sh 

    make clone

Build all images 
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

1. Build u-boot tf-a linux and rootfs in one step

.. code-block:: sh 

    make  build

2. Build u-boot tf-a linux and rootfs seperate step 

.. code-block:: sh 

    make  u-boot.build 
    make  tf-a.build 
    make  linux.build 
    make  buildroot.build
    make  qemu.build

3. Clean u-boot tf-a linux and rootfs in one step or seperate step 

.. code-block:: sh 

    make  clean  

.. code-block:: sh 

    make  u-boot.clean  
    make  tf-a.clean 
    make  linux.clean 
    make  buildroot.clean 
    make  qemu.clean 


Run and debug with gdb
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

1. Run the images on qemu

.. code-block:: sh 

    make  run 

2. Run the image with gdb 

.. code-block:: sh 

    make  debug 

