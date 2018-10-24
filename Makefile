ATF_BUILD := debug
BRANCH ?= my-hacks-1.2
LINUX_DIR := linux
DTS_DIR := $(LINUX_DIR)/arch/arm64/boot/dts
REMOTE_HOST ?= pinebook

all: pine64-pinebook pine64 pine64-plus pine64-sopine

help:
	# make pine64-pinebook
	# make pine64-plus
	# make pinebook_ums
	# make clean

sunxi-pack-tools:
	-rm -rf sunxi-pack-tools.tmp
	git clone --depth=1 --single-branch --branch=$(BRANCH) https://github.com/ayufan-pine64/sunxi-pack-tools.git sunxi-pack-tools.tmp
	make -C sunxi-pack-tools.tmp
	mv sunxi-pack-tools.tmp sunxi-pack-tools

sunxi-tools:
	-rm -rf sunxi-tools.tmp
	git clone https://github.com/linux-sunxi/sunxi-tools.git sunxi-tools.tmp
	make -C sunxi-tools.tmp
	mv sunxi-tools.tmp sunxi-tools

build/%-uboot.dtb: blobs/%-uboot.dts
	mkdir -p build
	dtc -Odtb -o $@ $<

build/%.fex: blobs/%.fex
	mkdir -p build
	cp $< $@
	unix2dos $@

build/sys_config_%.bin: build/sys_config_%.fex sunxi-pack-tools
	sunxi-pack-tools/bin/script $<

arm-trusted-firmware-pine64:
	git clone --depth=1 --single-branch --branch=$(BRANCH) https://github.com/ayufan-pine64/arm-trusted-firmware-pine64.git

arm-trusted-firmware-pine64/build/sun50iw1p1/release/bl31.bin: arm-trusted-firmware-pine64
	make -C arm-trusted-firmware-pine64 clean
	make -C arm-trusted-firmware-pine64 ARCH=arm CROSS_COMPILE="ccache aarch64-linux-gnu-" PLAT=sun50iw1p1 bl31

arm-trusted-firmware-pine64/build/sun50iw1p1/debug/bl31.bin: arm-trusted-firmware-pine64
	make -C arm-trusted-firmware-pine64 clean
	make -C arm-trusted-firmware-pine64 ARCH=arm CROSS_COMPILE="ccache aarch64-linux-gnu-" PLAT=sun50iw1p1 DEBUG=1 bl31

.INTERMEDIATE: build/bl31.bin
build/bl31.bin: arm-trusted-firmware-pine64/build/sun50iw1p1/$(ATF_BUILD)/bl31.bin
	cp $< $@

# build/bl31.bin: blobs/bl31.bin
# 	mkdir -p build
# 	cp $< $@

build/scp_%.bin: build/%_linux.dtb blobs/scp.bin
	cp blobs/scp.bin $@.tmp
	sunxi-pack-tools/bin/update_scp $@.tmp $<
	mv $@.tmp $@

.PHONY: scp
scp: build/scp_pinebook.bin build/scp_pine64.bin

u-boot-pine64:
	git clone --depth 1 --single-branch --branch=$(BRANCH) https://github.com/ayufan-pine64/u-boot-pine64.git

u-boot-pine64/include/configs/sun50iw1p1.h: u-boot-pine64

u-boot-pine64/include/autoconf.mk: u-boot-pine64/include/configs/sun50iw1p1.h
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE="ccache arm-linux-gnueabihf-" sun50iw1p1_config

u-boot-pine64/u-boot-sun50iw1p1.bin: u-boot-pine64/include/autoconf.mk
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE="ccache arm-linux-gnueabihf-" -j$(nproc)

u-boot-pine64/fes1_sun50iw1p1.bin u-boot-pine64/boot0_sdcard_sun50iw1p1.bin: u-boot-pine64/include/autoconf.mk
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE="ccache arm-linux-gnueabihf-" spl

.PHONY: uboot
uboot: u-boot-pine64/u-boot-sun50iw1p1.bin

.PHONY: spl
spl: u-boot-pine64/fes1_sun50iw1p1.bin u-boot-pine64/boot0_sdcard_sun50iw1p1.bin

linux/.git:
	git clone --depth 1 --single-branch --branch=my-hacks-1.2-with-drm https://github.com/ayufan-pine64/linux-pine64.git linux

linux: linux/.git

linux/.config: linux/.git
ifneq ($(BUILD_ANDROID),)
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" sun50iw1p1smp_android_defconfig
else
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" sun50iw1p1smp_linux_defconfig
endif

linux/scripts/dtc/dtc: linux/.config
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" scripts/dtc/
	touch "$@"

linux/arch/arm64/boot/dts/sun50iw1p1-soc.dts: linux

build/%.dtb.dts: $(DTS_DIR)/%.dts $(wildcard $(DTS_DIR)/*.dts*)
	$(CROSS_COMPILE)gcc -E -nostdinc -I$(DTS_DIR) -I$(LINUX_DIR)/include -D__DTS__  -x assembler-with-cpp -o $@.tmp $<
	mv $@.tmp $@

build/sys_config_%.fex.fix: blobs/sys_config_%.fex
	sed -e "s/\(\[dram\)_para\(\]\)/\1\2/g" \
		-e "s/\(\[nand[0-9]\)_para\(\]\)/\1\2/g" $< > $@.tmp
	mv $@.tmp $@

build/%-linux.dtb: build/sys_config_%.fex.fix build/sun50iw1p1-soc.dtb.dts $(LINUX_DIR)/scripts/dtc/dtc
	$(LINUX_DIR)/scripts/dtc/dtc -O dtb -o $@ \
		-F $< -R 512 \
		build/sun50iw1p1-soc.dtb.dts

build/boot0-%.bin: build/sys_config_%.bin u-boot-pine64/boot0_sdcard_sun50iw1p1.bin
	echo Blob needs to be at most 32KB && \
		test $$(stat -c%s $(word 2,$^)) -le 32768
	cp  $(word 2,$^) $@.tmp
	sunxi-pack-tools/bin/update_boot0 $@.tmp $< sdmmc_card
	mv $@.tmp $@

build/fes1-%.bin: build/sys_config_%.bin u-boot-pine64/fes1_sun50iw1p1.bin
	echo Blob needs to be at most 32KB && \
		test $$(stat -c%s $(word 2,$^)) -le 32768
	cp  $(word 2,$^) $@.tmp
	sunxi-pack-tools/bin/update_boot0 $@.tmp $< sdmmc_card
	mv $@.tmp $@

build/u-boot-sun50iw1p1-with-%-dtb.bin: build/%-linux.dtb build/sys_config_%.bin u-boot-pine64/u-boot-sun50iw1p1.bin sunxi-pack-tools \
		build/sys_config_uboot.bin sunxi-pack-tools
	sunxi-pack-tools/bin/update_uboot_fdt u-boot-pine64/u-boot-sun50iw1p1.bin $< $@.tmp
	sunxi-pack-tools/bin/update_uboot $@.tmp $(word 2,$^)
	mv $@.tmp $@

build/u-boot-sun50iw1p1-secure-with-%-dtb.bin: build/%-linux.dtb build/sys_config_%.bin u-boot-pine64/u-boot-sun50iw1p1.bin \
		build/bl31.bin blobs/scp.bin sunxi-pack-tools
	sunxi-pack-tools/bin/merge_uboot u-boot-pine64/u-boot-sun50iw1p1.bin build/bl31.bin $@.tmp secmonitor
	sunxi-pack-tools/bin/merge_uboot $@.tmp blobs/scp.bin $@.tmp2 scp
	sunxi-pack-tools/bin/update_uboot_fdt $@.tmp2 $< $@.tmp3
	sunxi-pack-tools/bin/update_uboot $@.tmp3 $(word 2,$^)
	echo Blob needs to be at most 1MB && \
		test $$(stat -c%s $@.tmp3) -le 1048576
	mv $@.tmp3 $@
	rm $@.tmp $@.tmp2

.PHONY: pine64-pinebook
pine64-pinebook: \
		boot/pine64/sun50i-a64-pine64-pinebook.dtb \
		boot/pine64/boot0-pine64-pinebook.bin \
		boot/pine64/fes1-pine64-pinebook.bin \
		boot/pine64/u-boot-pine64-pinebook.bin \
		boot/pine64/sun50i-a64-pine64-pinebook1080p.dtb \
		boot/pine64/boot0-pine64-pinebook1080p.bin \
		boot/pine64/fes1-pine64-pinebook1080p.bin \
		boot/pine64/u-boot-pine64-pinebook1080p.bin \
		boot/boot.scr \
		boot/boot.cmd \
		boot/uEnv.txt

.PHONY: pine64-sopine
pine64-sopine: boot/pine64/sun50i-a64-pine64-sopine.dtb \
		boot/pine64/boot0-pine64-sopine.bin \
		boot/pine64/fes1-pine64-sopine.bin \
		boot/pine64/u-boot-pine64-sopine.bin \
		boot/boot.scr \
		boot/boot.cmd \
		boot/uEnv.txt

.PHONY: pine64
pine64: boot/pine64/sun50i-a64-pine64.dtb \
		boot/pine64/boot0-pine64.bin \
		boot/pine64/fes1-pine64.bin \
		boot/pine64/u-boot-pine64.bin \
		boot/boot.scr \
		boot/boot.cmd \
		boot/uEnv.txt

.PHONY: pine64-plus
pine64-plus: boot/pine64/sun50i-a64-pine64-plus.dtb \
		boot/pine64/boot0-pine64-plus.bin \
		boot/pine64/fes1-pine64-plus.bin \
		boot/pine64/u-boot-pine64-plus.bin \
		boot/boot.scr \
		boot/boot.cmd \
		boot/uEnv.txt

.PHONY: pinebook_ums
pinebook_ums: sunxi-tools
	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: EMMC
	sunxi-tools/sunxi-fel -v spl boot/pine64/fes1-pine64-pinebook.bin
	sunxi-tools/sunxi-fel write-with-progress 0x4A000000 boot/pine64/u-boot-pine64-pinebook.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x2 \
		exe 0x4A000000

.PHONY: sopine_ums sopine_boot
sopine_ums: sunxi-tools
	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: SD card
	sunxi-tools/sunxi-fel -v spl boot/pine64/fes1-pine64-sopine.bin
	sunxi-tools/sunxi-fel write-with-progress 0x4A000000 boot/pine64/u-boot-pine64-sopine.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x2 \
		exe 0x4A000000

sopine_boot: sunxi-tools
	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: SD card
	sunxi-tools/sunxi-fel -v spl boot/pine64/fes1-pine64-pinebook.bin
	sunxi-tools/sunxi-fel write-with-progress 0x4A000000 boot/pine64/u-boot-pine64-sopine.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x2 \
		exe 0x4A000000

.PHONY: pine64_ums
pine64_ums: sunxi-tools
	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: SD card
	sunxi-tools/sunxi-fel -v spl boot/pine64/fes1-pine64-plus.bin
	sunxi-tools/sunxi-fel write-with-progress 0x4A000000 boot/pine64/u-boot-pine64-plus.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x0 \
		exe 0x4A000000

boot/pine64:
	mkdir -p boot/pine64

boot/pine64/sun50i-a64-%.dtb: build/%-linux.dtb
	cp $< $@

boot/pine64/fes1-%.bin: build/fes1-%.bin
	cp $< $@

boot/pine64/boot0-%.bin: build/boot0-%.bin
	cp $< $@

boot/pine64/u-boot-%.bin: build/u-boot-sun50iw1p1-secure-with-%-dtb.bin
	cp $< $@

boot/pine64/u-boot-%.bin: build/u-boot-sun50iw1p1-secure-with-%-dtb.bin
	cp $< $@

boot/boot.scr: blobs/boot.cmd
	mkimage -C none -A arm -T script -d $< $@

boot/uEnv.txt: blobs/uEnv.txt
	cp $< $@

boot/boot.cmd: blobs/boot.cmd
	cp $< $@

.PHONY: pine64_write
pine64_write: boot build/boot0-pine64.bin build/u-boot-sun50iw1p1-secure-with-pine64-dtb.bin
	@if [[ -z "$(DISK)" ]]; then echo "Missing DISK, use: make pine64_write DISK=/dev/diskX"; exit 1; fi
	-sudo umount $(DISK)*
	sudo dd conv=notrunc bs=1k seek=8 of="$(DISK)" if=build/boot0-pine64.bin
	sudo dd conv=notrunc bs=1k seek=19096 of="$(DISK)" if=build/u-boot-sun50iw1p1-secure-with-pine64-dtb.bin
	cd boot/ && sudo mcopy -n -v -s -m -i $(DISK)?1 * ::

.PHONY: pinebook_write
pinebook_write: boot build/boot0-pinebook.bin build/u-boot-sun50iw1p1-secure-with-pinebook-dtb.bin
	@if [ -z "$(DISK)" ]; then echo "Missing DISK, use: make pinebook_write DISK=/dev/diskX"; exit 1; fi
	-sudo umount $(DISK)*
	sudo dd conv=notrunc bs=1k seek=8 of="$(DISK)" if=build/boot0-pinebook.bin
	sudo dd conv=notrunc bs=1k seek=19096 of="$(DISK)" if=build/u-boot-sun50iw1p1-secure-with-pinebook-dtb.bin
	cd boot/ && sudo mcopy -n -v -s -m -i $(DISK)?1 * ::

.PHONY: clean
clean:
	rm -r -f build/* \
		arm-trusted-firmware-pine64 \
		u-boot-pine64 \
		sunxi-pack-tools \
		linux

.PHONY: compile_linux_kernel
compile_linux_kernel: linux/.config
	# Compiling...
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" -j4 Image

.PHONY: compile_linux_modules
compile_linux_modules: linux/.config
	# Compiling...
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" -j4 modules
	make -C linux LOCALVERSION=$(LINUX_LOCALVERSION) M=modules/gpu/mali400/kernel_mode/driver/src/devicedrv/mali \
		ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" \
		CONFIG_MALI400=m CONFIG_MALI450=y CONFIG_MALI400_PROFILING=y \
		CONFIG_MALI_DMA_BUF_MAP_ON_ATTACH=y CONFIG_MALI_DT=y \
		EXTRA_DEFINES="-DCONFIG_MALI400=1 -DCONFIG_MALI450=1 -DCONFIG_MALI400_PROFILING=1 -DCONFIG_MALI_DMA_BUF_MAP_ON_ATTACH -DCONFIG_MALI_DT"

	# Installing modules...
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" -j4 modules_install INSTALL_MOD_PATH=$(CURDIR)/linux_modules_install/
	make -C linux LOCALVERSION=$(LINUX_LOCALVERSION) M=modules/gpu/mali400/kernel_mode/driver/src/devicedrv/mali \
		ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" \
		CONFIG_MALI400=m CONFIG_MALI450=y CONFIG_MALI400_PROFILING=y \
		CONFIG_MALI_DMA_BUF_MAP_ON_ATTACH=y CONFIG_MALI_DT=y \
		EXTRA_DEFINES="-DCONFIG_MALI400=1 -DCONFIG_MALI450=1 -DCONFIG_MALI400_PROFILING=1 -DCONFIG_MALI_DMA_BUF_MAP_ON_ATTACH -DCONFIG_MALI_DT" \
		modules_install INSTALL_MOD_PATH=$(CURDIR)/linux_modules_install/

.PHONY: update_kernel
update_kernel: all compile_linux_kernel
	make upload_to_host

.PHONY: update_kernel_and_modules
update_kernel_and_modules: all compile_linux_kernel compile_linux_modules
	make upload_to_host

.PHONY: upload_to_host
upload_to_host: all
ifneq ($(UPDATE_ANDROID),)
	mkdir -p android_system_install/system/vendor/modules
	find linux_modules_install/ -name '*.ko' -exec cp -u {} android_system_install/system/vendor/modules/ \;
	adb remount
	adb push linux/arch/arm64/boot/Image /bootloader/kernel
	export ANDROID_PRODUCT_OUT="$(CURDIR)/android_system_install" && adb sync system
else
	# Syncing...
	rsync --partial --checksum -rv linux/arch/arm64/boot/Image root@$(REMOTE_HOST):$(DESTDIR)/boot/kernel
	rsync --partial --checksum -av linux_modules_install/lib/ root@$(REMOTE_HOST):$(DESTDIR)/lib
	rsync --partial --checksum --exclude="uEnv.txt" -r boot/ root@$(REMOTE_HOST):$(DESTDIR)/boot
ifneq ($(UPDATE_UBOOT),)
	dd if=boot/pine64/u-boot-pine64-pinebook.bin bs=1M | ssh root@$(REMOTE_HOST) dd conv=notrunc bs=1k seek=19096 oflag=sync of=/dev/mmcblk0
endif
endif

update_boot: all
	[ -n "$(REMOTE_MODEL)" ] # specify REMOTE_MODEL=sopine|pinebook|plus
	[ -n "$(REMOTE_DISK)" ] # specify REMOTE_DISK=0|1
	dd if=boot/pine64/boot0-pine64-$(REMOTE_MODEL).bin bs=1M | ssh root@$(REMOTE_HOST) dd conv=notrunc bs=1k seek=8 oflag=sync of=/dev/mmcblk$(REMOTE_DISK)
	dd if=boot/pine64/u-boot-pine64-$(REMOTE_MODEL).bin bs=1M | ssh root@$(REMOTE_HOST) dd conv=notrunc bs=1k seek=19096 oflag=sync of=/dev/mmcblk$(REMOTE_DISK)
