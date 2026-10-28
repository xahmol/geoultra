# GeoUltra Makefile
#
# System (docs/ARCHITECTURE.md, "Build"):
#   make              build build/geoultra64.crt
#   make vice         run it in VICE 3.10 (16 MB REU, 1351 mouse in port 1)
#   make vice-shot    run unattended, screenshot to build/vice.png
#   make conformance  compare kernal routines with GEOS 2.0 in VICE
#                     (tests/conformance/*.py; your own GEOS 2.0 disk:
#                     GEOS_ORACLE=path, default ~/geos-dev/u64-usb/
#                     GEOS64-v2.0-unkeyed.d64; CONF_REBUILD=1 makes new
#                     snapshots of both systems)
#
# Hardware smoke tests (docs/DESIGN.md, "Verified on hardware"):
#   make smoke        build build/smoke/gusmoke.crt and guseek.prg
#   make smoke-vice   run the cartridge in VICE 3.10 with a 16 MB REU,
#                     screenshot to build/smoke/vice.png
#   make smoke-u64    run both on the Ultimate 64 (REU and Command
#                     Interface switched on temporarily, not saved;
#                     restore with make smoke-u64-restore)

-include .env
ULTIP1 ?= <set_ULTIP1_in_.env>

CA65    = ca65
LD65    = ld65
OSCAR64 = /home/xahmol/oscar64/bin/oscar64
VICE    = $(HOME)/.local/opt/vice-3.10/bin/x64sc
PYTHON  = python3

UCILIB  = lib/ultimate-uci-oscar64/include
SMOKE   = build/smoke
REST    = http://$(ULTIP1)/v1
CARTCFG = $(REST)/configs/C64%20and%20Cartridge%20Settings

.PHONY: all vice vice-shot conformance smoke smoke-vice smoke-u64 smoke-u64-restore check-deploy clean

all: build/geoultra64.crt

# --- System -----------------------------------------------------------

GEN      = build/gen
KOBJ     = build/kernal
KSRCS    = $(wildcard src/kernal/*.s)
INPSRCS  = src/input/mouse1351.s
INCS     = $(wildcard src/inc/*.inc)
KOBJS    = $(patsubst src/kernal/%.s,$(KOBJ)/%.o,$(KSRCS)) \
           $(KOBJ)/mouse1351.o $(KOBJ)/jumptab.o
VICEOPTS = -default +sound -cartcrt build/geoultra64.crt -reu -reusize 16384 \
           -mouse -controlport1device 3

$(GEN)/jumptab.s: src/kernal/jumptab.txt tools/genjumptab.py $(KSRCS) $(INPSRCS)
	@mkdir -p $(GEN)
	$(PYTHON) tools/genjumptab.py $< $@ $(KSRCS) $(INPSRCS)

$(KOBJ)/%.o: src/kernal/%.s $(INCS)
	@mkdir -p $(KOBJ)
	$(CA65) -I src/inc -o $@ $<

$(KOBJ)/mouse1351.o: src/input/mouse1351.s $(INCS)
	@mkdir -p $(KOBJ)
	$(CA65) -I src/inc -o $@ $<

$(KOBJ)/jumptab.o: $(GEN)/jumptab.s
	@mkdir -p $(KOBJ)
	$(CA65) -o $@ $<

build/kernal64.bin: $(KOBJS) src/kernal/kernal64.cfg
	$(LD65) -C src/kernal/kernal64.cfg -m build/kernal64.map -Ln build/kernal64.lbl \
		-o $@ $(KOBJS)

$(GEN)/image.bin $(GEN)/image.inc: build/kernal64.bin tools/mkimage.py
	@mkdir -p $(GEN)
	$(PYTHON) tools/mkimage.py $(GEN)/image.bin $(GEN)/image.inc build/kernal64.bin@C000

build/boot.o: src/boot/boot.s $(GEN)/image.inc $(INCS)
	$(CA65) -I src/inc -I $(GEN) -o $@ $<

build/boot.bin: build/boot.o src/boot/boot.cfg
	$(LD65) -C src/boot/boot.cfg -o $@ $<

build/geoultra64.crt: build/boot.bin $(GEN)/image.bin tools/mkcrt.py
	$(PYTHON) tools/mkcrt.py $@ "GEOULTRA" build/boot.bin $(GEN)/image.bin

vice: build/geoultra64.crt
	$(VICE) $(VICEOPTS) -moncommands build/kernal64.lbl

vice-shot: build/geoultra64.crt
	$(VICE) $(VICEOPTS) -warp -limitcycles 6000000 -exitscreenshot build/vice.png; true

conformance: build/geoultra64.crt
	$(PYTHON) tools/harness/harness.py $(if $(CONF_REBUILD),--rebuild) tests/conformance/*.py

# --- Smoke tests ------------------------------------------------------

smoke: $(SMOKE)/gusmoke.crt $(SMOKE)/guseek.prg

$(SMOKE)/gusmoke.o: tests/smoke/gusmoke.s
	@mkdir -p $(SMOKE)
	$(CA65) -o $@ $<

$(SMOKE)/bank0.bin: $(SMOKE)/gusmoke.o tests/smoke/smoke.cfg
	$(LD65) -C tests/smoke/smoke.cfg -o $@ $<

$(SMOKE)/gusmoke.crt: $(SMOKE)/bank0.bin tools/mkcrt.py
	$(PYTHON) tools/mkcrt.py $@ "GEOULTRA SMOKE" $< --pattern 7

$(SMOKE)/guseek.prg: tests/smoke/guseek.c $(UCILIB)/ultimate_common_lib.c \
                     $(UCILIB)/ultimate_common_lib.h \
                     $(UCILIB)/ultimate_dos_lib.c $(UCILIB)/ultimate_dos_lib.h
	@mkdir -p $(SMOKE)
	$(OSCAR64) -i=$(UCILIB) -tm=c64 -tf=prg -O2 -dNOFLOAT -n -o=$@ $<

smoke-vice: $(SMOKE)/gusmoke.crt
	$(VICE) -default -warp +sound -cartcrt $< -reu -reusize 16384 \
		-limitcycles 4000000 -exitscreenshot $(SMOKE)/vice.png; true

check-deploy:
	@curl -s --connect-timeout 3 $(REST)/info >/dev/null 2>&1 || \
		(echo "ERROR: Cannot reach the Ultimate at $(ULTIP1) -- check ULTIP1 in .env" && false)

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

smoke-u64-restore: check-deploy
	curl -s -X PUT "$(CARTCFG)/RAM%20Expansion%20Unit?value=Disabled" >/dev/null
	curl -s -X PUT "$(CARTCFG)/Command%20Interface?value=Disabled" >/dev/null
	curl -s -Q "DELE /Temp/gutest.bin" "ftp://$(ULTIP1)/" -o /dev/null; true
	curl -s -X PUT "$(REST)/machine:reset" >/dev/null

clean:
	rm -rf build
