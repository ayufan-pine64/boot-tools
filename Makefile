ATF_BUILD := release
BRANCH := master

KERNEL_DIR := linux
DTS_DIR := $(KERNEL_DIR)/arch/arm64/boot/dts

all: pinebook pine64

help:
	# make pinebook
	# make pine64
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

build/%_uboot.dtb: blobs/%.dts
	mkdir -p build
	dtc -Odtb -o $@ $<

build/%.fex: blobs/%.fex
	mkdir -p build
	cp $< $@
	unix2dos $@

build/sys_config_%.bin: build/sys_config_%.fex sunxi-pack-tools
	sunxi-pack-tools/bin/script $<

arm-trusted-firmware-pine64:
	git clone --depth=1 --single-branch https://github.com/ayufan-pine64/arm-trusted-firmware-pine64.git

arm-trusted-firmware-pine64/build/sun50iw1p1/release/bl31.bin: arm-trusted-firmware-pine64
	make -C arm-trusted-firmware-pine64 clean
	make -C arm-trusted-firmware-pine64 ARCH=arm CROSS_COMPILE="ccache aarch64-linux-gnu-" PLAT=sun50iw1p1 bl31

arm-trusted-firmware-pine64/build/sun50iw1p1/debug/bl31.bin: arm-trusted-firmware-pine64
	make -C arm-trusted-firmware-pine64 clean
	make -C arm-trusted-firmware-pine64 ARCH=arm CROSS_COMPILE="ccache aarch64-linux-gnu-" PLAT=sun50iw1p1 DEBUG=1 bl31

build/bl31.bin: arm-trusted-firmware-pine64/build/sun50iw1p1/$(ATF_BUILD)/bl31.bin
	mkdir -p build
	cp $< $@

build/bl31.bin: blobs/bl31.bin
	mkdir -p build
	cp $< $@

u-boot-pine64:
	git clone --depth 1 --single-branch --branch=$(BRANCH) https://github.com/ayufan-pine64/u-boot-pine64.git

u-boot-pine64/include/configs/sun50iw1p1.h: u-boot-pine64

u-boot-pine64/include/autoconf.mk: u-boot-pine64/include/configs/sun50iw1p1.h
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE="ccache arm-linux-gnueabi-" sun50iw1p1_config

u-boot-pine64/u-boot-sun50iw1p1.bin: u-boot-pine64/include/autoconf.mk
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE="ccache arm-linux-gnueabi-"

u-boot-pine64/fes1_sun50iw1p1.bin u-boot-pine64/boot0_sdcard_sun50iw1p1.bin: u-boot-pine64/include/autoconf.mk
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE="ccache arm-linux-gnueabi-" spl

linux:
	git clone --depth 1 --single-branch --branch=$(BRANCH) https://github.com/ayufan-pine64/linux-pine64.git linux

linux/.config: linux
	make -C linux ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" sun50iw1p1smp_linux_defconfig

build/boot0_%.bin: build/sys_config_%.bin u-boot-pine64/boot0_sdcard_sun50iw1p1.bin
	cp u-boot-pine64/boot0_sdcard_sun50iw1p1.bin $@.tmp
	sunxi-pack-tools/bin/update_boot0 $@.tmp $< sdmmc_card
	mv $@.tmp $@

build/fes1_%.bin: build/sys_config_%.bin u-boot-pine64/fes1_sun50iw1p1.bin
	cp u-boot-pine64/fes1_sun50iw1p1.bin $@.tmp
	sunxi-pack-tools/bin/update_boot0 $@.tmp $< sdmmc_card
	mv $@.tmp $@

build/u-boot-sun50iw1p1-with-%-dtb.bin: build/%_uboot.dtb u-boot-pine64/u-boot-sun50iw1p1.bin sunxi-pack-tools \
		build/sys_config_uboot.bin sunxi-pack-tools
	sunxi-pack-tools/bin/update_uboot_fdt u-boot-pine64/u-boot-sun50iw1p1.bin $< $@.tmp
	sunxi-pack-tools/bin/update_uboot $@.tmp build/sys_config_uboot.bin
	mv $@.tmp $@

build/u-boot-sun50iw1p1-secure-with-%-dtb.bin: build/%_uboot.dtb u-boot-pine64/u-boot-sun50iw1p1.bin \
		build/bl31.bin blobs/scp.bin build/sys_config_uboot.bin sunxi-pack-tools
	sunxi-pack-tools/bin/merge_uboot u-boot-pine64/u-boot-sun50iw1p1.bin build/bl31.bin $@.tmp secmonitor
	sunxi-pack-tools/bin/merge_uboot $@.tmp blobs/scp.bin $@.tmp2 scp
	sunxi-pack-tools/bin/update_uboot_fdt $@.tmp2 $< $@.tmp3
	sunxi-pack-tools/bin/update_uboot $@.tmp3 build/sys_config_uboot.bin
	mv $@.tmp3 $@
	rm $@.tmp $@.tmp2

pinebook: build/boot0_pinebook.bin \
		build/fes1_pinebook.bin \
		build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
		build/u-boot-sun50iw1p1-secure-with-pinebook-dtb.bin \
		boot/pine64/sun50i-a64-pine64-pinebook.dtb \
		boot/boot.scr \
		boot/uEnv.txt

pine64: build/boot0_pine64.bin \
		build/fes1_pine64.bin \
		build/u-boot-sun50iw1p1-with-pine64-dtb.bin \
		build/u-boot-sun50iw1p1-secure-with-pine64-dtb.bin \
		boot/pine64/sun50i-a64-pine64-plus.dtb \
		boot/boot.scr \
		boot/uEnv.txt

pinebook_ums: build/fes1_pinebook.bin \
		build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
			sunxi-tools

	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: EMMC
	sunxi-tools/sunxi-fel -v spl build/fes1_pinebook.bin \
		write-with-progress 0x4A000000 build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x2 \
		exe 0x4A000000

pinebook_boot: build/fes1_pinebook.bin \
		build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
			sunxi-tools

	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: EMMC
	sunxi-tools/sunxi-fel -v spl build/fes1_pinebook.bin \
		write-with-progress 0x4A000000 build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
		writel 0x4A0000e0 0x0 \
		writel 0x4A0000e4 0x2 \
		exe 0x4A000000

pine64_ums: build/fes1_pine64.bin \
		build/u-boot-sun50iw1p1-with-pine64-dtb.bin \
			sunxi-tools

	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: SD card
	sunxi-tools/sunxi-fel -v spl build/fes1_pine64.bin \
		write-with-progress 0x4A000000 build/u-boot-sun50iw1p1-with-pine64-dtb.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x0 \
		exe 0x4A000000

boot/pine64:
	mkdir -p boot/pine64

build/%.dtb.dts: $(DTS_DIR)/%.dts $(wildcard $(DTS_DIR)/*.dts*)
	$(CROSS_COMPILE)gcc -E -nostdinc -I$(DTS_DIR) -I$(KERNEL_DIR)/include -D__DTS__  -x assembler-with-cpp -o $@.tmp $<
	mv $@.tmp $@

build/sys_config_%.fex.fix: blobs/sys_config_%.fex
	sed -e "s/\(\[dram\)_para\(\]\)/\1\2/g" \
		-e "s/\(\[nand[0-9]\)_para\(\]\)/\1\2/g" $< > $@.tmp
	mv $@.tmp $@

build/%_linux.dtb: build/sys_config_%.fex.fix build/sun50iw1p1-soc.dtb.dts
	$(KERNEL_DIR)/scripts/dtc/dtc -O dtb -o $@ \
		-F $< \
		build/sun50iw1p1-soc.dtb.dts

boot/pine64/sun50i-a64-pine64-pinebook.dtb: build/pinebook_linux.dtb
	cp $< $@

boot/pine64/sun50i-a64-pine64-plus.dtb: build/pine64_linux.dtb
	cp $< $@

boot/boot.scr: blobs/boot.cmd
	mkimage -C none -A arm -T script -d $< $@

boot/uEnv.txt: blobs/uEnv.txt
	cp $< $@

pine64_write: boot build/boot0_pine64.bin build/u-boot-sun50iw1p1-secure-with-pine64-dtb.bin
	@if [[ -z "$(DISK)" ]]; then echo "Missing DISK, use: make pine64_write DISK=/dev/diskX"; exit 1; fi
	-sudo umount $(DISK)*
	sudo dd conv=notrunc bs=1k seek=8 of="$(DISK)" if=build/boot0_pine64.bin
	sudo dd conv=notrunc bs=1k seek=19096 of="$(DISK)" if=build/u-boot-sun50iw1p1-secure-with-pine64-dtb.bin
	cd boot/ && sudo mcopy -n -v -s -m -i $(DISK)?1 * ::

pinebook_write: boot build/boot0_pinebook.bin build/u-boot-sun50iw1p1-secure-with-pinebook-dtb.bin
	@if [ -z "$(DISK)" ]; then echo "Missing DISK, use: make pinebook_write DISK=/dev/diskX"; exit 1; fi
	-sudo umount $(DISK)*
	sudo dd conv=notrunc bs=1k seek=8 of="$(DISK)" if=build/boot0_pinebook.bin
	sudo dd conv=notrunc bs=1k seek=19096 of="$(DISK)" if=build/u-boot-sun50iw1p1-secure-with-pinebook-dtb.bin
	cd boot/ && sudo mcopy -n -v -s -m -i $(DISK)?1 * ::

clean:
	rm -r -f build \
		arm-trusted-firmware-pine64 \
		u-boot-pine64 \
		sunxi-pack-tools
