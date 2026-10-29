// GeoUltra hardware probe: can a disk image file be loaded into the REU?
// (The UCI manual reports "89,NOT A DISK IMAGE" for a plain read-open of
// a disk image; GeoUltra's drives load whole images with LOAD_REU.)
//
// /Temp/probe.d64 (a copy of a 35-track D64, uploaded by make
// smoke-u64-d64) is opened with attribute $01 and $03; when an open
// succeeds the whole image is loaded to REU $400000 and block 18/0 is
// compared with the expected first bytes ($12 $01 $41 $00). Then the
// firmware's GEOS RAM disk commands: LOAD_INTO_RAMDISK as a trial run
// (whatif) and GET_RAMDISK_INFO.
//
// Results at $C000: "GUD6"; $C004 = 1 when the image arrived in the REU
// (header byte 2 as expected), $C00C-$C00F the header's first 4 bytes;
// status digits at $C010 + 2 * step; the LOAD_REU reply at $C040 (32
// bytes); GET_RAMDISK_INFO's 8 bytes at $C060.

#include <stdio.h>
#include <string.h>
#include "ultimate_common_lib.h"
#include "ultimate_dos_lib.h"

#define REU_CMD   (*(volatile char *)0xdf01)
#define REU_C64   (*(volatile unsigned *)0xdf02)
#define REU_ADDRL (*(volatile unsigned *)0xdf04)
#define REU_BANK  (*(volatile char *)0xdf06)
#define REU_LEN   (*(volatile unsigned *)0xdf07)
#define REU_CTRL  (*(volatile char *)0xdf0a)
#define REU_FETCH 0x91

#define RES ((volatile char *)0xc000)
#define REU_IMG   0x400000UL
// Defaults: the D64 in /Temp. Other images on the build line, e.g.
// -dPROBE_DIR="/USB0/Geos/" -dPROBE_NAME="x.d81" -dPROBE_SIZE=819200UL
// -dPROBE_HEAD=0x61800UL -dPROBE_ID=0x44 -dPROBE_READONLY (no $03 open).
#ifndef PROBE_DIR
#define PROBE_DIR  "/Temp/"
#define PROBE_NAME "probe.d64"
#endif
#ifndef PROBE_SIZE
#define PROBE_SIZE 174848UL             // 35-track D64
#define PROBE_HEAD 0x16500UL            // block 18/0
#define PROBE_ID   0x41                 // header byte 2: 'A'
#endif

static volatile char buf[8];
static char dir[] = PROBE_DIR;
static char name[] = PROBE_NAME;

static __noinline void reu_fetch(volatile void *c64, unsigned long addr, unsigned len)
{
	REU_C64 = (unsigned)c64;
	REU_ADDRL = (unsigned)addr;
	REU_BANK = (char)(addr >> 16);
	REU_LEN = len;
	REU_CTRL = 0;
	REU_CMD = REU_FETCH;
}

static char ok(void)
{
	return uii_status[0] == '0' && uii_status[1] == '0';
}

static void step(char n, const char *what)
{
	RES[0x10 + 2 * n] = uii_status[0];
	RES[0x11 + 2 * n] = uii_status[1];
	printf("%d %s: %s\n", n, what, uii_status);
}

static void load(void)
{
	uii_load_reu_at(REU_IMG, PROBE_SIZE);
	for (char i = 0; i < 32 && uii_data[i]; i++)
		RES[0x40 + i] = uii_data[i];
	printf("  %s\n", uii_data);
	reu_fetch(buf, REU_IMG + PROBE_HEAD, 4);
	if (buf[2] == PROBE_ID)
		RES[4] = 1;
	for (char i = 0; i < 4; i++)
		RES[0x0c + i] = buf[i];
}

int main(void)
{
	memset((char *)RES, 0, 0x80);
	printf("GEOULTRA D64 PROBE\n");
	uii_wait_for_uci(5);
	uii_change_dir(dir);
	step(0, "CD");

	uii_open_file(0x01, name);
	step(1, "OPEN $01");
	if (ok())
		load();
	step(2, "LOAD");
	uii_close_file();

#ifndef PROBE_READONLY
	uii_open_file(0x03, name);
	step(3, "OPEN $03");
	if (ok() && !RES[4])
		load();
	uii_close_file();
#endif

	uii_loadIntoRamDisk(8, name, 1);
	step(4, "RAMDISK TRIAL");
	uii_get_ramdisk_info();
	step(5, "RAMDISK INFO");
	for (char i = 0; i < 8; i++)
		RES[0x60 + i] = uii_data[i];

	printf("IMAGE IN REU: %s\n", RES[4] ? "YES" : "NO");
	RES[0] = 'G';
	RES[1] = 'U';
	RES[2] = 'D';
	RES[3] = '6';
	return 0;
}
