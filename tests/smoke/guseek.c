// GeoUltra smoke test: partial write-back of an REU range into a file.
//
// 1. Write a 64 KB file of 'A' from the REU (SAVE_REU at address).
// 2. Reopen it, seek to $1000, SAVE_REU 256 bytes of 'B'.
// 3. Load the whole file back into the REU and check: 'A' up to $0FFF,
//    'B' at $1000-$10FF, 'A' from $1100, size still 64 KB.
// 4. Reopen, seek to $1000, LOAD_REU 256 bytes: must read the 'B' run.
//
// Results at $C000: "GUSK", then per step the two status digits from the
// Ultimate at $C010 + 2 * step, verdicts at $C004 (step 3) and $C005
// (step 4): 1 = pass, 0 = fail; $C006-$C009 = file size (LSB first).

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

#define REU_STASH 0x90
#define REU_FETCH 0x91
#define REU_FIX_C64 0x80

#define RES ((volatile char *)0xc000)

#define REU_A    0x020000UL
#define REU_B    0x030000UL
#define REU_BACK 0x040000UL
#define REU_SEEK 0x050000UL

// volatile and a __noinline reu(): the REU reads and writes buf by DMA,
// which the compiler cannot see; inlined, the 'A' store was dropped as
// dead (rule in docs/OSCAR64_MANUAL.md, REU section).
static volatile char buf[260];
static char dir[] = "/Temp/";
static char name[] = "gutest.bin";

// Transfer len bytes (0 = 64 KB) between C64 memory and the REU.
static __noinline void reu(char cmd, char ctrl, volatile void *c64, unsigned long addr, unsigned len)
{
	REU_C64 = (unsigned)c64;
	REU_ADDRL = (unsigned)addr;
	REU_BANK = (char)(addr >> 16);
	REU_LEN = len;
	REU_CTRL = ctrl;
	REU_CMD = cmd;
}

static void step(char n, const char *what)
{
	RES[0x10 + 2 * n] = uii_status[0];
	RES[0x11 + 2 * n] = uii_status[1];
	printf("%d %s: %s\n", n, what, uii_status);
}

int main(void)
{
	memset((char *)RES, 0, 0x30);
	printf("GEOULTRA SEEK TEST\n");
	uii_wait_for_uci(5);

	buf[0] = 'A';
	reu(REU_STASH, REU_FIX_C64, buf, REU_A, 0);
	buf[0] = 'B';
	reu(REU_STASH, REU_FIX_C64, buf, REU_B, 256);

	uii_change_dir(dir);
	step(0, "CD");
	uii_delete_file(name);
	uii_open_file(0x06, name);
	step(1, "CREATE");
	uii_save_reu_at(REU_A, 0x10000UL);
	step(2, "SAVE 64K");
	uii_close_file();

	uii_open_file(0x03, name);
	step(3, "OPEN RW");
	uii_seek_file(0x00, 0x10, 0x00, 0x00);
	step(4, "SEEK");
	uii_save_reu_at(REU_B, 256);
	step(5, "SAVE 256");
	uii_close_file();

	uii_open_file(0x01, name);
	step(6, "OPEN R");
	unsigned long size = uii_file_size();
	uii_load_reu_at(REU_BACK, 0x10000UL);
	step(7, "LOAD 64K");
	uii_close_file();
	RES[6] = (char)size;
	RES[7] = (char)(size >> 8);
	RES[8] = (char)(size >> 16);
	RES[9] = (char)(size >> 24);

	reu(REU_FETCH, 0, buf, REU_BACK + 0x0fff, 258);
	char ok = size == 0x10000UL && buf[0] == 'A' && buf[257] == 'A';
	for (unsigned i = 1; i < 257; i++)
		if (buf[i] != 'B')
			ok = 0;
	RES[4] = ok;
	printf("PARTIAL WRITE: %s, SIZE %lu\n", ok ? "PASS" : "FAIL", size);

	uii_open_file(0x01, name);
	uii_seek_file(0x00, 0x10, 0x00, 0x00);
	step(8, "SEEK R");
	uii_load_reu_at(REU_SEEK, 256);
	step(9, "LOAD 256");
	uii_close_file();
	reu(REU_FETCH, 0, buf, REU_SEEK, 258);
	ok = buf[0] == 'B' && buf[255] == 'B';
	RES[5] = ok;
	printf("SEEK + LOAD: %s\n", ok ? "PASS" : "FAIL");

	RES[0] = 'G';
	RES[1] = 'U';
	RES[2] = 'S';
	RES[3] = 'K';
	return 0;
}
