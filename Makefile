# GeoUltra Makefile
#
# System (docs/reference/ARCHITECTURE.md, "Build"):
#   make              build build/geoultra64.crt
#   make vice         run it in VICE 3.10 (16 MB REU, 1351 mouse in port 1)
#   make vice-shot    run unattended, screenshot to build/vice.png
#   make deploy       the cartridge to the Ultimate's DEPLOYDIR
#                     (ULTIP1 and DEPLOYDIR in .env), to start it from there
#   make conformance81  the same for 1581 images (GEOS 2.0 on a 1581)
#   make conformance  compare kernal routines with GEOS 2.0 in VICE
#                     (tests/conformance/*.py; your own GEOS 2.0 disk:
#                     GEOS_ORACLE=path, default $(GEOS_DEV)/
#                     GEOS64-v2.0-unkeyed.d64; CONF_REBUILD=1 makes new
#                     snapshots of both systems)
#
# Hardware smoke tests (docs/design/DESIGN.md, "Verified on hardware"):
#   make smoke        build build/smoke/gusmoke.crt and guseek.prg
#   make smoke-vice   run the cartridge in VICE 3.10 with a 16 MB REU,
#                     screenshot to build/smoke/vice.png
#   make smoke-u64    run both on the Ultimate 64 (REU and Command
#                     Interface switched on temporarily, not saved;
#                     restore with make smoke-u64-restore)

# This PC's settings: .env (gitignored; copy .env.example and fill it
# in). Every key has a default that needs nothing of a particular PC;
# the scripts read the same file (tools/localcfg.py).
-include .env
ULTIP1 ?= <set_ULTIP1_in_.env>
VICE_BIN ?=
VICE_HEADLESS_BIN ?=
OSCAR64 ?= oscar64
GEOUTOOLS ?= ../GeoUTools
GEOS_DEV ?= private
export VICE_BIN VICE_HEADLESS_BIN GEOUTOOLS GEOS_DEV

CA65    = ca65
LD65    = ld65
# VICE 3.10 or later (the Megabyter cartridge): from VICE_BIN, else the PATH
VICE    = $(if $(VICE_BIN),$(VICE_BIN)/,)x64sc
# A headless VICE (no window, no sound) for unattended runs, if there is one
VICEHL  = $(if $(VICE_HEADLESS_BIN),$(VICE_HEADLESS_BIN)/x64sc,$(VICE))
C1541   = $(if $(VICE_BIN),$(VICE_BIN)/,)c1541
GEOSAPP = tools/dev/geosapp.py
PYTHON  = python3

UCILIB  = lib/ultimate-uci-oscar64/include
SMOKE   = build/smoke
REST    = http://$(ULTIP1)/v1
CARTCFG = $(REST)/configs/C64%20and%20Cartridge%20Settings
DEPLOYDIR ?= /SD/geoultra/

.PHONY: all docs samples release test-samples checkcfg vice vice-shot deploy conformance conformance81 test-settings test-bypass test-native test-d71 test-folders test-filedialog test-sysfont test-fonts test-print fonts test-desktop81 test-desktop test-desktop-u64 test-part81 test-engine test-engine-u64 test-gush test-gush-u64 smoke smoke-vice smoke-u64 smoke-u64-d64 smoke-u64-restore \
        check-deploy clean
GEOS_ORACLE ?= $(GEOS_DEV)/GEOS64-v2.0-unkeyed.d64

all: build/geoultra64.crt build/geoultra64.cfg

# The Ultimate settings for the cartridge, applied by firmware 3.15 when
# the .crt is started from its file browser (docs/design/DESIGN.md "Ultimate
# settings"); the kernal's start-up check covers the other ways.
build/geoultra64.cfg: src/cfg/geoultra64.cfg
	@mkdir -p build
	cp $< $@

# Every item and value of the .cfg against the Ultimate in .env.
checkcfg: check-deploy
	$(PYTHON) tools/dev/checkcfg.py src/cfg/geoultra64.cfg $(ULTIP1)

# --- System drive (drive E, docs/design/DESIGN.md "System drive") ------------

# GeoUltra's own GEOS files, assembled at $0400 and packed as CVT by
# tools/dev/geosapp.py (a copy of geos-oscar64 0.1.2's: it pads desk
# accessories to whole blocks), written to a D64 with VICE's c1541.
SYSFILES = build/tools/geofolder.cvt build/gush/gush.cvt build/cmds/wc.cvt build/desktop/desktop.cvt \
           build/settings/settings.cvt build/tools/splash.cvt build/fonts/.done \
           build/printer/epson.cvt build/printer/mps.cvt \
           build/printer/pdfa4.cvt build/printer/pdfa4data.cvt \
           build/printer/pdfletter.cvt build/printer/pdfletterdata.cvt build/psw/psw.cvt

build/tools/%.bin: src/tools/%.s src/tools/%.cfg
	@mkdir -p build/tools
	$(CA65) -I build/gen -o build/tools/$*.o $<
	$(LD65) -C src/tools/$*.cfg -o $@ build/tools/$*.o

# geoFolder's gush button, drawn like the system icons (tools/dev/mkicons.py).
build/gen/gushicon.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@ GushIcon gush

build/tools/geofolder.bin: build/gen/gushicon.inc

build/tools/%.cvt: build/tools/%.bin src/tools/%.toml
	$(PYTHON) $(GEOSAPP) src/tools/$*.toml $< $@

# GU PostScript (src/psw, docs/design/DESIGN.md "PostScript writer"): psw.s
# first (its Start at $0400), then the other modules.
PSWSRCS = src/psw/psw.s $(filter-out src/psw/psw.s,$(wildcard src/psw/*.s))
PSWOBJS = $(patsubst src/psw/%.s,build/psw/%.o,$(PSWSRCS))

build/psw/%.o: src/psw/%.s src/psw/psw.inc
	@mkdir -p build/psw
	$(CA65) -g -I src/psw -I build/gen -o $@ $<

# Its options box's buttons, drawn like the system icons.
build/gen/pswicons.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon build/gen/pswa4.inc IconA4 "A4"
	$(PYTHON) tools/dev/mkicons.py --icon build/gen/pswletter.inc IconLetter "Letter"
	$(PYTHON) tools/dev/mkicons.py --icon build/gen/pswreal.inc IconReal "Real"
	$(PYTHON) tools/dev/mkicons.py --icon build/gen/pswc64.inc IconC64 "C64"
	cat build/gen/pswa4.inc build/gen/pswletter.inc build/gen/pswreal.inc build/gen/pswc64.inc > $@

build/psw/options.o: build/gen/pswicons.inc

build/psw/psw.bin: $(PSWOBJS) src/psw/psw.cfg
	$(LD65) -C src/psw/psw.cfg -m build/psw/psw.map -Ln build/psw/psw.lbl -o $@ $(PSWOBJS)

build/psw/psw.cvt: build/psw/psw.bin src/psw/psw.toml
	$(PYTHON) $(GEOSAPP) src/psw/psw.toml $< $@

# The boot splash as a data file on drive E (bitmap, then colours), which
# the desktop's GeoUltra info shows (ctxmenu.s).
# Its status line says how to leave it (mksplash.py's own mode).
build/tools/splash.bin: tools/dev/splash/mksplash.py tools/dev/splash/idi8b-logo.png tools/fonts/system9.py
	@mkdir -p build/tools build/gen
	GU_VERSION=v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH) $(PYTHON) tools/dev/splash/mksplash.py build/gen/splashinfo.bin build/gen/splashinfo_col.bin \
		build/gen/splashinfo.png "A key or a click: back to the desktop"
	cat build/gen/splashinfo.bin build/gen/splashinfo_col.bin > $@

# gush, the GeoUltra shell (docs/design/GUSH.md): src/gush, its font generated by
# tools/fonts/gush6.py.
GUSHSRCS = src/gush/gush.s $(filter-out src/gush/gush.s,$(wildcard src/gush/*.s))
GUSHOBJS = $(patsubst src/gush/%.s,build/gush/%.o,$(GUSHSRCS))   # gush.o first: its Start at $0400

build/gen/gushfont.inc: tools/fonts/gush6.py
	@mkdir -p build/gen
	$(PYTHON) $< $@

build/gush/%.o: src/gush/%.s src/gush/gush.inc $(wildcard src/inc/*.inc) build/gen/gushfont.inc
	@mkdir -p build/gush
	$(CA65) -g -I src/inc -I src/gush -I build/gen -o $@ $<

build/gush/gush.bin: $(GUSHOBJS) src/gush/gush.cfg
	$(LD65) -C src/gush/gush.cfg -m build/gush/gush.map -Ln build/gush/gush.lbl -o $@ $(GUSHOBJS)

build/gush/gush.cvt: build/gush/gush.bin src/gush/gush.toml tools/dev/vlircvt.py
	$(PYTHON) $(GEOSAPP) src/gush/gush.toml $< build/gush/gush-seq.cvt
	$(PYTHON) tools/dev/vlircvt.py build/gush/gush-seq.cvt $@ $<.1 $<.2 $<.3 $<.4

# GeoUltra's desktop (docs/design/DESKTOP.md): src/desktop, on drive E.
DESKSRCS = $(wildcard src/desktop/*.s)
# The question's "Yes to all" button (64 pixels), drawn like the system icons.
# The icon view's 24 x 21 generic icons (own drawings, text art in the tool).
build/gen/bigicons.inc: tools/dev/mkbigicons.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkbigicons.py $@
build/gen/yesall.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@ YesAllIcon "Yes to all" 64

# The mount dialog's drive buttons, drawn like the system icons.
DRVICONS = $(patsubst %,build/gen/drvicon_%.inc,A B C D)
build/gen/drvicon_%.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@ DriveIcon$* $*

# The print queue window's buttons (src/desktop/spool.s).
build/gen/qicons.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@.1 CancelIcon cancel 40
	$(PYTHON) tools/dev/mkicons.py --icon $@.2 PauseIcon pause
	$(PYTHON) tools/dev/mkicons.py --icon $@.3 ResumeIcon resume
	$(PYTHON) tools/dev/mkicons.py --icon $@.4 CloseIcon close
	cat $@.1 $@.2 $@.3 $@.4 > $@ && rm $@.1 $@.2 $@.3 $@.4

build/gen/splashicon.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@ SplashIcon splash

build/desktop/desktop.cvt: $(DESKSRCS) src/desktop/desktop.inc $(DRVICONS) build/gen/yesall.inc build/gen/splashicon.inc build/gen/qicons.inc build/gen/bigicons.inc src/desktop/desktop.cfg src/desktop/desktop.toml $(wildcard src/inc/*.inc)
	@mkdir -p build/desktop
	for f in $(DESKSRCS); do $(CA65) -g -I src/inc -I build/gen -o build/desktop/$$(basename $$f .s).o $$f || exit 1; done
	$(LD65) -C src/desktop/desktop.cfg -m build/desktop/desktop.map -Ln build/desktop/desktop.lbl -o build/desktop/desktop.bin build/desktop/desktop.o $(patsubst src/desktop/%.s,build/desktop/%.o,$(filter-out src/desktop/desktop.s,$(DESKSRCS)))
	$(PYTHON) $(GEOSAPP) src/desktop/desktop.toml build/desktop/desktop.bin build/desktop/desktop-seq.cvt
	$(PYTHON) tools/dev/vlircvt.py build/desktop/desktop-seq.cvt $@ build/desktop/desktop.bin.1 build/desktop/desktop.bin.2 build/desktop/desktop.bin.3 build/desktop/desktop.bin.4 build/desktop/desktop.bin.5 build/desktop/desktop.bin.6 build/desktop/desktop.bin.7 build/desktop/desktop.bin.8 build/desktop/desktop.bin.9

# GeoUltra Settings (docs/design/SETTINGS.md): src/settings, on drive E; its
# OK, Cancel and Save buttons drawn like the system icons.
SETSRCS = $(wildcard src/settings/*.s)
SETICONS = build/gen/okicon.inc build/gen/cancelicon.inc build/gen/saveicon.inc
build/gen/okicon.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@ OkIcon OK
build/gen/cancelicon.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@ CancelIcon Cancel
build/gen/saveicon.inc: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p build/gen
	$(PYTHON) tools/dev/mkicons.py --icon $@ SaveIcon Save

build/settings/settings.cvt: $(SETSRCS) src/settings/settings.inc $(SETICONS) build/gen/pointers.inc src/settings/settings.cfg src/settings/settings.toml $(wildcard src/inc/*.inc)
	@mkdir -p build/settings
	for f in $(SETSRCS); do $(CA65) -g -I src/inc -I src/settings -I build/gen -o build/settings/$$(basename $$f .s).o $$f || exit 1; done
	$(LD65) -C src/settings/settings.cfg -m build/settings/settings.map -Ln build/settings/settings.lbl -o build/settings/settings.bin build/settings/settings.o $(patsubst src/settings/%.s,build/settings/%.o,$(filter-out src/settings/settings.s,$(SETSRCS)))
	$(PYTHON) $(GEOSAPP) src/settings/settings.toml build/settings/settings.bin build/settings/settings-seq.cvt
	$(PYTHON) tools/dev/vlircvt.py build/settings/settings-seq.cvt $@ build/settings/settings.bin.1 build/settings/settings.bin.2 build/settings/settings.bin.3 build/settings/settings.bin.4 build/settings/settings.bin.5 build/settings/settings.bin.6 build/settings/settings.bin.7 build/settings/settings.bin.8

# External gush commands (docs/reference/GUSH_COMMANDS.md): src/cmds/NAME.s linked
# at gush's transient area (src/cmds/cmd.cfg), a GEOS APPL_DATA file of
# class "gush cmd" (src/cmds/NAME.toml).
build/cmds/%.cvt: src/cmds/%.s src/cmds/%.toml src/cmds/cmd.cfg src/cmds/gushapi.inc $(wildcard src/inc/*.inc)
	@mkdir -p build/cmds
	$(CA65) -I src/inc -I src/cmds -o build/cmds/$*.o $<
	$(LD65) -C src/cmds/cmd.cfg -m build/cmds/$*.map -o build/cmds/$*.bin build/cmds/$*.o
	$(PYTHON) $(GEOSAPP) src/cmds/$*.toml build/cmds/$*.bin $@

# DocPeek, the test application of tests/gush/g9.py (gush's "program
# document"): linked like gush.
build/gush/docpeek.cvt: tests/gush/docpeek.s tests/gush/docpeek.toml src/gush/gush.cfg
	@mkdir -p build/gush
	$(CA65) -I src/inc -o build/gush/docpeek.o $<
	$(LD65) -C src/gush/gush.cfg -o build/gush/docpeek.bin build/gush/docpeek.o
	$(PYTHON) $(GEOSAPP) tests/gush/docpeek.toml build/gush/docpeek.bin $@

# Drive E (docs/reference/ARCHITECTURE.md "System drive"): build/sysdrive-plain.dnp
# is an ordinary native image with folders (src/sysdrive.toml,
# tools/mkappsdnp.py); build/sysdrive.dnp, the one in the cartridge, has
# its track numbers moved above SYSDRV_TRACK (tools/dev/sysreloc.py,
# src/inc/sysdrive.inc) and ends after its last used track.
SYSDRV_TRACK  := $(shell sed -n 's/^SYSDRV_TRACK  *= *\([0-9]*\).*/\1/p' src/inc/sysdrive.inc)
SYSDRV_TRACKS := $(shell sed -n 's/^SYSDRV_TRACKS *= *\([0-9]*\).*/\1/p' src/inc/sysdrive.inc)
build/sysdrive.dnp: $(SYSFILES) src/sysdrive.toml src/inc/sysdrive.inc tools/mkappsdnp.py tools/dev/sysreloc.py
	$(PYTHON) tools/mkappsdnp.py src/sysdrive.toml
	$(PYTHON) tools/dev/sysreloc.py build/sysdrive-plain.dnp $@ $(SYSDRV_TRACK) $(SYSDRV_TRACKS)

# --- System -----------------------------------------------------------

GEN      = build/gen
KOBJ     = build/kernal
# BYPASS=0 builds without the serial-number-per-application module
# (src/kernal/bypass.s, docs/design/DESIGN.md "Serial number").
BYPASS  ?= 1
ifeq ($(BYPASS),1)
KSRCS    = $(wildcard src/kernal/*.s)
KDEFS    = -D BYPASS=1
else
KSRCS    = $(filter-out src/kernal/bypass.s,$(wildcard src/kernal/*.s))
KDEFS    =
endif
DRVSRCS  = $(wildcard src/drivers/*.s)
INPSRCS  = src/input/mouse1351.s
INCS     = $(wildcard src/inc/*.inc)
KOBJS    = $(patsubst src/kernal/%.s,$(KOBJ)/%.o,$(KSRCS)) \
           $(patsubst src/drivers/%.s,$(KOBJ)/%.o,$(DRVSRCS)) \
           $(KOBJ)/mouse1351.o $(KOBJ)/jumptab.o $(KOBJ)/sysfont.o $(KOBJ)/sysicons.o
VICEOPTS = -default +sound -cartcrt build/geoultra64.crt -reu -reusize 16384 \
           -mouse -controlport1device 3

$(GEN)/jumptab.s: src/kernal/jumptab.txt tools/dev/genjumptab.py $(KSRCS) $(INPSRCS)
	@mkdir -p $(GEN)
	$(PYTHON) tools/dev/genjumptab.py $< $@ $(KSRCS) $(INPSRCS)

# The version: vMAJOR.MINOR.PATCH-YYYYMMDD-HHMM (as UBoot64-v2), the
# time stamp the build's. The kernal's info block holds the numbers
# (src/kernal/info.s, $C0E2 and $C0F5), GeoUltra info shows them; the
# clock also starts at the build date (VICE; on the Ultimate the cold
# start then reads its real-time clock).
VERSION_MAJOR = 0
VERSION_MINOR = 9
VERSION_PATCH = 0
BUILD_STAMP  := $(shell date "+%y %m %d %H %M")
BUILDDATE    := $(shell echo $(BUILD_STAMP) | awk '{printf "-D BUILD_YEAR=%d -D BUILD_MONTH=%d -D BUILD_DAY=%d -D BUILD_HOUR=%d -D BUILD_MINUTE=%d", $$1, $$2, $$3, $$4, $$5}') \
                -D VERSION_MAJOR=$(VERSION_MAJOR) -D VERSION_MINOR=$(VERSION_MINOR) \
                -D VERSION_PATCH=$(VERSION_PATCH)

# The time stamp follows every change of the kernal or the system drive.
$(KOBJ)/info.o: $(KSRCS) $(DRVSRCS) build/sysdrive.dnp

# Rebuild the kernal objects when BYPASS changes.
$(KOBJ)/.bypass: FORCE
	@mkdir -p $(KOBJ)
	@echo $(BYPASS) | cmp -s - $@ || echo $(BYPASS) > $@

FORCE:

# The hibernation file carries the kernal's build ID: these two objects are
# rebuilt with every kernal change (src/kernal/hibernate.s).
BUILD_ID := $(shell expr $$(date +%s) % 65536)
$(KOBJ)/hibernate.o $(KOBJ)/hibresume.o: $(KSRCS) $(DRVSRCS)

$(KOBJ)/%.o: src/kernal/%.s $(INCS) $(KOBJ)/.bypass
	@mkdir -p $(KOBJ)
	$(CA65) -g -I src/inc $(BUILDDATE) $(KDEFS) -D BUILD_ID=$(BUILD_ID) -o $@ $<

# The mouse pointer's designs (own drawings, text art in the tool), for
# module 86 (src/kernal/pointer.s).
$(GEN)/pointers.inc: tools/dev/mkpointers.py
	@mkdir -p $(GEN)
	$(PYTHON) tools/dev/mkpointers.py $@

$(KOBJ)/pointer.o: src/kernal/pointer.s $(GEN)/pointers.inc $(INCS) $(KOBJ)/.bypass
	@mkdir -p $(KOBJ)
	$(CA65) -I src/inc -I $(GEN) -o $@ $<

$(KOBJ)/%.o: src/drivers/%.s $(INCS)
	@mkdir -p $(KOBJ)
	$(CA65) -I src/inc -o $@ $<

$(KOBJ)/mouse1351.o: src/input/mouse1351.s $(INCS)
	@mkdir -p $(KOBJ)
	$(CA65) -I src/inc -o $@ $<

$(GEN)/sysfont.s: tools/fonts/system9.py tools/mkfont.py
	@mkdir -p $(GEN)
	$(PYTHON) tools/mkfont.py $< $@ SystemFont

$(GEN)/sysicons.s: tools/dev/mkicons.py tools/fonts/system9.py
	@mkdir -p $(GEN)
	$(PYTHON) tools/dev/mkicons.py $@

$(KOBJ)/sysicons.o: $(GEN)/sysicons.s
	@mkdir -p $(KOBJ)
	$(CA65) -o $@ $<

$(KOBJ)/sysfont.o: $(GEN)/sysfont.s
	@mkdir -p $(KOBJ)
	$(CA65) -o $@ $<

$(KOBJ)/jumptab.o: $(GEN)/jumptab.s
	@mkdir -p $(KOBJ)
	$(CA65) -o $@ $<

build/kernal64.bin build/reudrv64.bin build/init64.bin build/overlays64.bin build/kbf64.bin &: $(KOBJS) \
		src/kernal/kernal64.cfg
	$(LD65) -C src/kernal/kernal64.cfg -m build/kernal64.map -Ln build/kernal64.lbl \
		-o $@ $(KOBJS)

# The overlay modules ($1F0 bytes each from the linker) spread to a stride
# of $200 in the REU, so OvlLoad computes a module's address (overlay.s).
build/overlays64s.bin: build/overlays64.bin
	$(PYTHON) -c "import sys; d=open(sys.argv[1],'rb').read(); n=len(d)//0x1F0; assert len(d)==n*0x1F0; open(sys.argv[2],'wb').write(b''.join(d[i*0x1F0:(i+1)*0x1F0]+bytes(0x10) for i in range(n)))" $< $@

SPLASH   = $(GEN)/splash.bin $(GEN)/splash_col.bin $(GEN)/splash_msg.bin $(GEN)/splash.inc

$(SPLASH) &: tools/dev/splash/mksplash.py tools/dev/splash/idi8b-logo.png tools/fonts/system9.py build/kernal64.bin
	@mkdir -p $(GEN)
	GU_KERNAL=build/kernal64.bin $(PYTHON) tools/dev/splash/mksplash.py --boot $(SPLASH)

# The splash comes first: the boot ROM copies it with the CPU (--cpu 2).
$(GEN)/image.bin $(GEN)/image.inc: build/kernal64.bin build/reudrv64.bin build/init64.bin build/kbf64.bin \
		build/overlays64s.bin build/sysdrive.dnp \
		$(SPLASH) tools/dev/mkimage.py
	@mkdir -p $(GEN)
	$(PYTHON) tools/dev/mkimage.py --cpu 2 $(GEN)/image.bin $(GEN)/image.inc build/overlays64s.bin@REU \
		$(GEN)/splash.bin@A000 $(GEN)/splash_col.bin@8C00 build/kbf64.bin@BF40 build/kernal64.bin@C000 \
		build/reudrv64.bin@9000 build/init64.bin@4F00 build/sysdrive.dnp@BANK4

build/boot.o: src/boot/boot.s $(GEN)/image.inc $(SPLASH) $(INCS)
	$(CA65) -I src/inc -I $(GEN) --bin-include-dir $(GEN) -o $@ $<

build/boot.bin: build/boot.o src/boot/boot.cfg
	$(LD65) -C src/boot/boot.cfg -o $@ $<

build/geoultra64.crt: build/boot.bin $(GEN)/image.bin tools/dev/mkcrt.py
	$(PYTHON) tools/dev/mkcrt.py $@ "GEOULTRA" build/boot.bin $(GEN)/image.bin

vice: build/geoultra64.crt
	$(VICE) $(VICEOPTS) -moncommands build/kernal64.lbl

vice-shot: build/geoultra64.crt
	$(VICEHL) $(VICEOPTS) -sounddev dummy -warp -limitcycles 6000000 -exitscreenshot build/vice.png; true

conformance: build/geoultra64.crt
	$(PYTHON) tools/dev/harness/harness.py $(if $(CONF_REBUILD),--rebuild) tests/conformance/*.py

# The same against GEOS 2.0 on a 1581 (GEOS_ORACLE81, default
# $(GEOS_DEV)/GEOS64.D81): GeoUltra's 1581 image drive.
conformance81: build/geoultra64.crt
	$(PYTHON) tools/dev/harness/harness.py --set d81 $(if $(CONF_REBUILD),--rebuild) \
		tests/conformance81/*.py

# --- Smoke tests ------------------------------------------------------

smoke: $(SMOKE)/gusmoke.crt $(SMOKE)/guseek.prg $(SMOKE)/gud64.prg

$(SMOKE)/gusmoke.o: tests/smoke/gusmoke.s
	@mkdir -p $(SMOKE)
	$(CA65) -o $@ $<

$(SMOKE)/bank0.bin: $(SMOKE)/gusmoke.o tests/smoke/smoke.cfg
	$(LD65) -C tests/smoke/smoke.cfg -o $@ $<

$(SMOKE)/gusmoke.crt: $(SMOKE)/bank0.bin tools/dev/mkcrt.py
	$(PYTHON) tools/dev/mkcrt.py $@ "GEOULTRA SMOKE" $< --pattern 7

$(SMOKE)/guseek.prg: tests/smoke/guseek.c $(UCILIB)/ultimate_common_lib.c \
                     $(UCILIB)/ultimate_common_lib.h \
                     $(UCILIB)/ultimate_dos_lib.c $(UCILIB)/ultimate_dos_lib.h
	@mkdir -p $(SMOKE)
	$(OSCAR64) -i=$(UCILIB) -tm=c64 -tf=prg -O2 -dNOFLOAT -n -o=$@ $<

$(SMOKE)/gud64.prg: tests/smoke/gud64.c $(UCILIB)/ultimate_common_lib.c \
                    $(UCILIB)/ultimate_common_lib.h \
                    $(UCILIB)/ultimate_dos_lib.c $(UCILIB)/ultimate_dos_lib.h
	@mkdir -p $(SMOKE)
	$(OSCAR64) -i=$(UCILIB) -tm=c64 -tf=prg -O2 -dNOFLOAT -n -o=$@ $<

smoke-vice: $(SMOKE)/gusmoke.crt
	$(VICEHL) -default -sounddev dummy -warp +sound -cartcrt $< -reu -reusize 16384 \
		-limitcycles 4000000 -exitscreenshot $(SMOKE)/vice.png; true

# The cartridge where the user starts it from (user, 2026-11-11).
# Drive C for testing (the user, 2026-11-11): the user's own GEOS software
# sorted into folders, private/geoultra-apps.dnp from private/apps.toml
# (tools/mkappsdnp.py; private, never committed), as a native REU drive:
# a copy in the test folder (MOUNTS.INI C=). A running session writes its
# own copy back over it, so a new one counts from the next boot.
APPS_DNP := $(if $(wildcard private/apps.toml),private/geoultra-apps.dnp)
private/geoultra-apps.dnp: private/apps.toml tools/mkappsdnp.py
	$(PYTHON) tools/mkappsdnp.py private/apps.toml

deploy: check-deploy build/geoultra64.crt build/geoultra64.cfg
	curl -sS --max-time 120 --ftp-create-dirs -T build/geoultra64.crt ftp://$(ULTIP1)$(DEPLOYDIR)
	curl -sS --max-time 60 --ftp-create-dirs -T build/geoultra64.cfg ftp://$(ULTIP1)$(DEPLOYDIR)

# The release archive (make release): what a user needs, nothing of the
# design record; the PC tools are used from the repository (tools
# manual). RELEASE_TAG names a pre-release (beta1); empty for a release.
RELEASE_TAG ?= beta1
RELEASE_NAME = geoultra-$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_PATCH)$(if $(RELEASE_TAG),-$(RELEASE_TAG))
release: build/geoultra64.crt build/geoultra64.cfg docs samples
	rm -rf build/release && mkdir -p build/release/$(RELEASE_NAME)/samples
	cp build/geoultra64.crt build/geoultra64.cfg LICENSE README.pdf \
	   docs/manuals/GEOULTRA_MANUAL.pdf docs/manuals/TOOLS_MANUAL.pdf build/release/$(RELEASE_NAME)/
	cp build/samples/geoultra-samples.d81 build/samples/brochure.pdf build/samples/quickstart.pdf \
	   build/release/$(RELEASE_NAME)/samples/
	cd build/release && zip -qr ../../$(RELEASE_NAME).zip $(RELEASE_NAME)
	@echo "$(RELEASE_NAME).zip"; unzip -l $(RELEASE_NAME).zip

# The PDFs of the README and the user documents (pandoc with XeLaTeX;
# ~/.claude/makefile_conventions.md); committed, so they ship in releases.
DOCPDFS = README.pdf docs/manuals/GEOULTRA_MANUAL.pdf docs/manuals/TOOLS_MANUAL.pdf
docs: $(DOCPDFS)

%.pdf: %.md pandoc-defaults.yaml pandoc-header.tex
	@if which pandoc >/dev/null 2>&1; then \
		pandoc --defaults=pandoc-defaults.yaml $< -o $@; \
	else \
		echo "WARNING: pandoc not found -- $@ not updated (install: sudo apt install pandoc texlive-xetex)"; \
	fi

# The sample documents (samples/build.py): brochure, quick start guide,
# letter and logo on build/samples/geoultra-samples.d81, and the PDFs.
samples: build/geoultra64.crt fonts
	$(PYTHON) samples/build.py

# The private applications image to the test folder, only on request: it
# is drive C there, and a new copy replaces what was written to it (the
# user's test files) at the next boot (2026-11-13: deploy did it each time).
deploy-apps: check-deploy $(APPS_DNP)
	$(if $(APPS_DNP),curl -s -T $(APPS_DNP) ftp://$(ULTIP1)/USB0/GEOULTRA/test/geoultra-apps.dnp)

check-deploy:
	@curl -s --connect-timeout 3 --max-time 5 $(REST)/info >/dev/null 2>&1 || \
		(echo "ERROR: The Ultimate at $(ULTIP1) does not answer (ULTIP1 in .env; a network stuck after long use: reboot it)" && false)

# Results: $C000 block, see the comments at the top of both sources.
smoke-u64: check-deploy smoke
	curl -s -X PUT "$(CARTCFG)/RAM%20Expansion%20Unit?value=Enabled" >/dev/null
	curl -s -X PUT "$(CARTCFG)/Command%20Interface?value=Enabled" >/dev/null
	curl -s -X POST --data-binary @$(SMOKE)/gusmoke.crt "$(REST)/runners:run_crt" >/dev/null
	sleep 4
	@echo "cartridge, first start:"; curl -s "$(REST)/machine:readmem?address=C000&length=16" | xxd
	curl -s -X PUT "$(REST)/machine:reset" >/dev/null
	sleep 4
	@echo "cartridge, after reset:"; curl -s "$(REST)/machine:readmem?address=C000&length=16" | xxd
	curl -s -X POST --data-binary @$(SMOKE)/guseek.prg "$(REST)/runners:run_prg" >/dev/null
	sleep 8
	@echo "seek test:"; curl -s "$(REST)/machine:readmem?address=C000&length=48" | xxd

# Disk image into the REU: a copy of GEOS_ORACLE in /Temp (results: $C000
# block, see tests/smoke/gud64.c); then REU and Command Interface off.
smoke-u64-d64: check-deploy $(SMOKE)/gud64.prg
	curl -s -T "$(GEOS_ORACLE)" "ftp://$(ULTIP1)/Temp/probe.d64"
	curl -s -X PUT "$(CARTCFG)/RAM%20Expansion%20Unit?value=Enabled" >/dev/null
	curl -s -X PUT "$(CARTCFG)/Command%20Interface?value=Enabled" >/dev/null
	curl -s -X POST --data-binary @$(SMOKE)/gud64.prg "$(REST)/runners:run_prg" >/dev/null
	sleep 10
	@echo "d64 probe:"; curl -s "$(REST)/machine:readmem?address=C000&length=112" | xxd
	curl -s -Q "DELE /Temp/probe.d64" "ftp://$(ULTIP1)/" -o /dev/null; true
	$(MAKE) smoke-u64-restore

smoke-u64-restore: check-deploy
	curl -s -X PUT "$(CARTCFG)/RAM%20Expansion%20Unit?value=Disabled" >/dev/null
	curl -s -X PUT "$(CARTCFG)/Command%20Interface?value=Disabled" >/dev/null
	curl -s -Q "DELE /Temp/gutest.bin" "ftp://$(ULTIP1)/" -o /dev/null; true
	curl -s -X PUT "$(REST)/machine:reset" >/dev/null

# Writing to a native (DNP) drive (tests/drives/write.py native; GEOS_NATIVE_DISK,
# default $(GEOS_DEV)/ramapps.DNP, is only read).
test-native: all
	$(PYTHON) tests/drives/write.py native

# Folders on a native drive (tests/drives/folders.py, on a copy of the
# same DNP).
test-folders: all
	$(PYTHON) tests/drives/folders.py

# Folders in geoWrite 2.0's Open dialog (tests/drives/filedialog.py, on a
# copy of the same DNP), and MegaPatch 3's DBGETFILES flags in geoWrite
# 2.1 from a folder (tests/drives/mpdialog.py, the private apps DNP).
test-filedialog: all
	$(PYTHON) tests/drives/filedialog.py
	$(PYTHON) tests/drives/mpdialog.py

# 1581 partitions as folders, against a D81 made and read back by the real
# 1581 DOS (VICE true drive emulation; no private files).
test-part81: all
	$(PYTHON) tests/drives/part81.py

# The file engine, steps E1 (tests/engine/e1.py: paths, stat, listings,
# folders, rename, delete), E2 (e2.py: copy, move, streams) and L
# (long.py: long names) on the
# part81 reference D81 as drive B (the GEOS 2.0 disk as drive A, only
# read); the real 1581 DOS reads it back.
test-engine: all
	$(PYTHON) tests/engine/e1.py
	$(PYTHON) tests/engine/e2.py
	$(PYTHON) tests/engine/long.py
	$(PYTHON) tests/engine/dst.py

# gush, the GeoUltra shell (tests/gush/g*.py, docs/design/GUSH.md): started from a
# test D81 in VICE, keys through keyVector and GEOS's key queue, its screen
# read from its text shadow.
test-gush: all build/gush/docpeek.cvt
	$(PYTHON) tests/gush/gtables.py
	$(PYTHON) tests/gush/g1.py
	$(PYTHON) tests/gush/g2.py
	$(PYTHON) tests/gush/g3.py
	$(PYTHON) tests/gush/g4.py
	$(PYTHON) tests/gush/g5.py
	$(PYTHON) tests/gush/g6.py
	$(PYTHON) tests/gush/g7.py
	$(PYTHON) tests/gush/g8.py
	$(PYTHON) tests/gush/g9.py
	$(PYTHON) tests/gush/g10.py
	$(PYTHON) tests/gush/g11.py
	$(PYTHON) tests/gush/g12.py
	$(PYTHON) tests/gush/g13.py
	$(PYTHON) tests/gush/g14.py
	$(PYTHON) tests/gush/g15.py
	$(PYTHON) tests/gush/g16.py
	$(PYTHON) tests/gush/g17.py
	$(PYTHON) tests/gush/g18.py
	$(PYTHON) tests/gush/g19.py
	$(PYTHON) tests/gush/g20.py
	$(PYTHON) tests/gush/g21.py
	$(PYTHON) tests/gush/g22.py

# gush on the U64 (tests/gush/gu64.py): the Ultimate's file system, a desk
# accessory; gush written onto drive A's test copy first.
test-gush-u64: check-deploy all
	$(PYTHON) tests/gush/gu64.py build/geoultra64.crt

# The file engine on the Ultimate (tests/engine/e3u64.py): the
# cartridge into the U64's flash and a reboot, then the Ultimate's file
# system and raw copies; only in /USB0/GEOULTRA/test and on the test
# images (MOUNTS.INI pointing at them), everything removed again.
test-engine-u64: check-deploy all build/uciprobe.bin
	$(PYTHON) tests/engine/e3u64.py build/geoultra64.crt
	$(PYTHON) tests/engine/e4u64.py build/geoultra64.crt
	$(PYTHON) tests/engine/mntu64.py build/geoultra64.crt
	$(PYTHON) tests/engine/imgu64.py build/geoultra64.crt
	$(PYTHON) tests/engine/longu64.py build/geoultra64.crt
	$(PYTHON) tests/engine/sizeu64.py build/geoultra64.crt
	$(PYTHON) tests/engine/autou64.py build/geoultra64.crt

# A UCI probe run inside GeoUltra on the U64 (feu64.py, U64.uci): raw
# commands while developing.
build/uciprobe.bin: tests/engine/uciprobe.s tests/engine/uciprobe.cfg src/inc/uci.inc
	$(CA65) -I src/inc -o build/uciprobe.o $<
	$(LD65) -C tests/engine/uciprobe.cfg -o $@ build/uciprobe.o

# A font on drive E in geoWrite (the user's own disks: SYSFONT_DISK,
# GEOS_APPS_DISK); screens in build/harness/sysfont-*.png.
# The sample documents in geoWrite 2.1 (your own GEOS 2.0 disk:
# GEOS_ORACLE81), and the refusal question without the serial.
test-samples: all samples
	$(PYTHON) tests/apps/samples.py

test-sysfont: all
	$(PYTHON) tests/drives/sysfont.py

# GeoUltra's printer drivers (docs/design/DESIGN.md "Printing"): PRINTER files
# for drive E, assembled at $7900 (src/printer/printer.cfg; their own
# folder: the kernal links every file in src/drivers); their file icon
# drawn by tools/dev/mkprnicon.py (a letter for the printer).
build/printer/%.icon: tools/dev/mkprnicon.py
	@mkdir -p build/printer
	$(PYTHON) tools/dev/mkprnicon.py $(PRNLETTER_$*) $@
PRNLETTER_epson = E
PRNLETTER_mps = C
PRNLETTER_pdf = P

# GU PDF A4 and GU PDF Letter: one source (pdf.s, LETTER for Letter), and
# their scripts (pdfdata.s, assembled at 0) as the data files pdfa4 and
# pdfletter.
PDF_DEF_a4 =
PDF_DEF_letter = -D LETTER
build/printer/pdfa4.cvt build/printer/pdfletter.cvt: build/printer/pdf%.cvt: src/printer/pdf.s src/printer/pdfscript.inc src/printer/prnserial.inc src/printer/pdf%.toml src/printer/printer.cfg build/printer/pdf.icon src/inc/geos.inc
	@mkdir -p build/printer
	$(CA65) -I src/inc -I src/printer $(PDF_DEF_$*) -o build/printer/pdf$*.o $<
	$(LD65) -C src/printer/printer.cfg -o build/printer/pdf$*.bin -m build/printer/pdf$*.map build/printer/pdf$*.o
	$(PYTHON) $(GEOSAPP) src/printer/pdf$*.toml build/printer/pdf$*.bin $@
build/printer/pdfa4data.cvt build/printer/pdfletterdata.cvt: build/printer/pdf%data.cvt: src/printer/pdfdata.s src/printer/pdfscript.inc src/printer/pdfdata.cfg src/printer/pdf%data.toml
	@mkdir -p build/printer
	$(CA65) -I src/inc -I src/printer $(PDF_DEF_$*) -o build/printer/pdf$*data.o $<
	$(LD65) -C src/printer/pdfdata.cfg -o build/printer/pdf$*data.bin build/printer/pdf$*data.o
	$(PYTHON) $(GEOSAPP) src/printer/pdf$*data.toml build/printer/pdf$*data.bin $@

build/printer/%.cvt: src/printer/%.s src/printer/prnserial.inc src/printer/%.toml src/printer/printer.cfg build/printer/%.icon src/inc/geos.inc
	@mkdir -p build/printer
	$(CA65) -I src/inc -I src/printer -o build/printer/$*.o $<
	$(LD65) -C src/printer/printer.cfg -o build/printer/$*.bin -m build/printer/$*.map build/printer/$*.o
	$(PYTHON) $(GEOSAPP) src/printer/$*.toml build/printer/$*.bin $@

# GeoUltra's own GEOS fonts (docs/design/DESIGN.md "Fonts"): build/fonts/*.cvt
# from the copies in tools/fonts/src (TeX Gyre, Adobe 75-dpi bitmaps).
FONTSRCS = $(wildcard tools/fonts/src/*/*) $(wildcard tools/fonts/gu*_fix.py)
fonts: build/fonts/.done
build/fonts/.done: tools/dev/mkgufonts.py tools/mkgeosfont.py $(FONTSRCS)
	$(PYTHON) tools/dev/mkgufonts.py build/fonts
	@touch $@

test-fonts: all
	$(PYTHON) tests/fonts/mkgeosfont_test.py
	$(PYTHON) tests/fonts/fontlist.py

# GeoUltra's printer drivers in VICE (docs/design/DESIGN.md "Printing"): their
# bytes caught at the ROM's serial routines and checked dot for dot.
test-print: all
	$(PYTHON) tests/print/ep1.py
	$(PYTHON) tests/print/mp1.py
	$(PYTHON) tests/print/pdfsim.py
	$(PYTHON) tests/print/pdf1.py
	$(PYTHON) tests/print/gwcross.py
	$(PYTHON) tests/print/psref.py
	$(PYTHON) tests/print/psc64.py

# The GEOS 2.0 deskTop with a 1581 drive A (the driver called between
# InitForIO and DoneWithIO, the KERNAL ROM in; tests/drives/desktop81.py).
test-desktop81: all
	$(PYTHON) tests/drives/desktop81.py

# GeoUltra Settings (docs/design/SETTINGS.md): the shared INI module and the
# application's frame and Desktop page in VICE.
test-settings: all
	$(PYTHON) tests/settings/ini.py
	$(PYTHON) tests/settings/s1.py
	$(PYTHON) tests/settings/s1g.py
	$(PYTHON) tests/settings/s2.py
	$(PYTHON) tests/settings/s3.py
	$(PYTHON) tests/settings/s3b.py
	$(PYTHON) tests/settings/s4.py
	$(PYTHON) tests/settings/s6.py
	$(PYTHON) tests/settings/s7.py
	$(PYTHON) tests/settings/s8.py

# GeoUltra's own desktop (docs/design/DESKTOP.md): VICE; test-desktop-u64 on the
# U64 (SETTINGS.INI desktop=geoultra, made and deleted again).
test-desktop: all
	$(PYTHON) tests/desktop/d1.py
	$(PYTHON) tests/desktop/d2.py
	$(PYTHON) tests/desktop/d3.py
	$(PYTHON) tests/desktop/d3doc.py
	$(PYTHON) tests/desktop/d4.py
	$(PYTHON) tests/desktop/d5.py
	$(PYTHON) tests/desktop/d8.py
	$(PYTHON) tests/desktop/d9.py
	$(PYTHON) tests/desktop/d11.py
	$(PYTHON) tests/desktop/d12.py
	$(PYTHON) tests/desktop/d13.py
	$(PYTHON) tests/desktop/d16.py
	$(PYTHON) tests/desktop/d17.py
	$(PYTHON) tests/desktop/d18.py
	$(PYTHON) tests/desktop/d20.py
	$(PYTHON) tests/desktop/d21.py
	$(PYTHON) tests/desktop/d22.py
	$(PYTHON) tests/desktop/d23.py
	$(PYTHON) tests/desktop/d24.py
	$(PYTHON) tests/desktop/d25.py
	$(PYTHON) tests/desktop/d26.py
	$(PYTHON) tests/desktop/d27.py
	$(PYTHON) tests/spool/sp1.py
	$(PYTHON) tests/spool/sp2.py
	$(PYTHON) tests/spool/sp3.py
	$(PYTHON) tests/spool/sp4.py
	$(PYTHON) tests/spool/sp5.py
	$(PYTHON) tests/apps/geoludo.py
	$(PYTHON) tests/apps/geowrite.py
	$(PYTHON) tests/apps/clipboard.py

test-desktop-u64: check-deploy all
	$(PYTHON) tests/desktop/du64.py build/geoultra64.crt
	$(PYTHON) tests/desktop/d16u64.py build/geoultra64.crt
	$(PYTHON) tests/desktop/d19u64.py build/geoultra64.crt
	$(PYTHON) tests/settings/s5u64.py build/geoultra64.crt
	$(PYTHON) tests/desktop/tasku64.py build/geoultra64.crt
	$(PYTHON) tests/desktop/hibtasku64.py build/geoultra64.crt
	$(PYTHON) tests/spool/hibspoolu64.py build/geoultra64.crt
	$(PYTHON) tests/apps/geoludou64.py build/geoultra64.crt
	$(PYTHON) tests/apps/themeu64.py build/geoultra64.crt
	$(PYTHON) tests/spool/spu64.py build/geoultra64.crt
	$(PYTHON) tests/settings/s3cu64.py build/geoultra64.crt

# Writing to a 1571 drive, on a D71 the test formats itself.
test-d71: all
	$(PYTHON) tests/drives/write.py d71

# The answer to an application's first-run disk check (tests/bypass/hook.py).
test-bypass: all
	$(PYTHON) tests/bypass/hook.py

clean:
	rm -rf build
