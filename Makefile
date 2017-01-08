ATF_BUILD := release

all: pinebook pine64

help:
	# make pinebook
	# make pine64
	# make pinebook_ums

sunxi-pack-tools:
	-rm -rf sunxi-pack-tools.tmp
	git clone https://github.com/longsleep/sunxi-pack-tools.git sunxi-pack-tools.tmp
	make -C sunxi-pack-tools.tmp
	mv sunxi-pack-tools.tmp sunxi-pack-tools

sunxi-tools:
	-rm -rf sunxi-tools.tmp
	git clone https://github.com/linux-sunxi/sunxi-tools.git sunxi-tools.tmp
	make -C sunxi-tools.tmp
	mv sunxi-tools.tmp sunxi-tools

build/%.dtb: blobs/%.dts
	mkdir -p build
	dtc -Odtb -o $@ $<

build/sys_config.fex: blobs/sys_config.fex
	mkdir -p build
	cp $< $@
	unix2dos $@

build/sys_config.bin: build/sys_config.fex sunxi-pack-tools
	sunxi-pack-tools/bin/script $<

arm-trusted-firmware-pine64:
	git clone --branch allwinner-a64-bsp --single-branch https://github.com/longsleep/arm-trusted-firmware.git arm-trusted-firmware-pine64

arm-trusted-firmware-pine64/build/sun50iw1p1/release/bl31.bin: arm-trusted-firmware-pine64
	make -C arm-trusted-firmware-pine64 clean
	make -C arm-trusted-firmware-pine64 ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50iw1p1 bl31

arm-trusted-firmware-pine64/build/sun50iw1p1/debug/bl31.bin: arm-trusted-firmware-pine64
	make -C arm-trusted-firmware-pine64 clean
	make -C arm-trusted-firmware-pine64 ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50iw1p1 DEBUG=1 bl31

build/bl31.bin: arm-trusted-firmware-pine64/build/sun50iw1p1/$(ATF_BUILD)/bl31.bin
	mkdir -p build
	cp $< $@

u-boot-pine64:
	git clone --depth 1 --branch pine64-usb-mass-storage --single-branch https://github.com/ayufan-pine64/u-boot-pine64.git u-boot-pine64

u-boot-pine64/include/configs/sun50iw1p1.h: u-boot-pine64

u-boot-pine64/config.mk: u-boot-pine64/include/configs/sun50iw1p1.h
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sun50iw1p1_config

u-boot-pine64/u-boot-sun50iw1p1.bin: u-boot-pine64/config.mk
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j

u-boot-pine64/fes1_sun50iw1p1.bin u-boot-pine64/boot0_sdcard_sun50iw1p1.bin: u-boot-pine64/config.mk
	make -C u-boot-pine64 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- spl -j

build/%.bin: u-boot-pine64/%.bin
	mkdir -p build
	cp $< $@

build/u-boot-sun50iw1p1-with-%-dtb.bin: build/%.dtb u-boot-pine64/u-boot-sun50iw1p1.bin sunxi-pack-tools
	sunxi-pack-tools/bin/update_uboot_fdt u-boot-pine64/u-boot-sun50iw1p1.bin $< $@

build/u-boot-sun50iw1p1-secure-with-%-dtb.bin: build/u-boot-sun50iw1p1-with-%-dtb.bin \
		build/bl31.bin build/sys_config.bin sunxi-pack-tools
	sunxi-pack-tools/bin/merge_uboot $< build/bl31.bin $@.tmp secmonitor
	sunxi-pack-tools/bin/merge_uboot $@.tmp blobs/scp.bin $@.tmp scp
	-sunxi-pack-tools/bin/update_uboot $@.tmp build/sys_config.bin
	mv $@.tmp $@

pinebook: build/fes1_sun50iw1p1.bin \
		build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
		build/u-boot-sun50iw1p1-secure-with-pinebook-dtb.bin

pine64: build/fes1_sun50iw1p1.bin \
		build/u-boot-sun50iw1p1-with-pine64-dtb.bin \
		build/u-boot-sun50iw1p1-secure-with-pine64-dtb.bin

pinebook_ums: build/fes1_sun50iw1p1.bin \
		build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
			sunxi-tools

	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: EMMC
	sunxi-tools/sunxi-fel -v spl build/fes1_sun50iw1p1.bin \
		write-with-progress 0x4A000000 build/u-boot-sun50iw1p1-with-pinebook-dtb.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x2 \
		exe 0x4A000000

pine64_ums: build/fes1_sun50iw1p1.bin \
		build/u-boot-sun50iw1p1-with-pine64-dtb.bin \
			sunxi-tools

	# 0x4A0000e0: is a work mode: the 0x55 is a special work mode used to force USB mass storage
	# 0x4A0000e4: is a storage type: SD card
	sunxi-tools/sunxi-fel -v spl build/fes1_sun50iw1p1.bin \
		write-with-progress 0x4A000000 build/u-boot-sun50iw1p1-with-pine64-dtb.bin \
		writel 0x4A0000e0 0x55 \
		writel 0x4A0000e4 0x0 \
		exe 0x4A000000
