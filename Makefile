# GeoUltra Makefile
#
# For now only the hardware smoke tests (docs/DESIGN.md, "Verified on
# hardware"):
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

.PHONY: all smoke smoke-vice smoke-u64 smoke-u64-restore check-deploy clean

all: smoke

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
