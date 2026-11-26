# GeoUltra and GEOS 2.0's code: the clean-room check

GeoUltra's kernal, disk driver and system programs are written from the
GEOS documentation (HG2G, "The Hitchhiker's Guide to GEOS", and
Berkeley's own programmer's references), not from GEOS 2.0's code. The
GEOS 2.0 kernal is still Berkeley Softworks' work; its reassembled
source (Michael Steil's mist64/geos) was read for questions of
behaviour, never copied. GEOS 2.0 itself, from the user's own disk,
serves as the test oracle: every kernal routine is run in both systems
in VICE and the results compared (`make conformance`, 304 cases).

This document says how that claim was checked, what the check found,
and what was done about it. The check is repeated before each release
(`tools/dev/cleanroom.py`).

## Why measure

Most of GeoUltra was written with an AI assistant (see the README,
"Use of AI"). An AI that has read the GEOS 2.0 source can reproduce
parts of it without being asked to. Saying "we never copied" is not
enough; a measurement shows where the code is the same and why.

## The method

`tools/dev/cleanroom.py MIST64_GEOS_CHECKOUT [--binary]` compares two
ways. Nothing of GEOS 2.0 is written into the repository: the reports
show file names, line numbers, addresses and lengths only.

1. **Source.** Every instruction of GeoUltra's assembler (`src/kernal`,
   `src/drivers`) and of GEOS 2.0's (mist64/geos `kernal/`, `drv/`;
   Wheels' source in the same repository left out) is reduced to its
   mnemonic and addressing mode. Names and numbers are dropped on
   purpose: a copy with everything renamed would still show. Windows of
   12 instructions in a row are compared, and a shared window is
   followed as far as both sides keep matching. Windows made of nothing
   but loading registers with constants and storing them (parameter
   set-up, which matches any other set-up) are skipped.
   **Calibration:** GeoUltra's desktop, a different program written the
   same way, is measured against GEOS 2.0 too. What it shares shows the
   level that 6502 idioms and GEOS conventions produce on their own.
2. **Binary (`--binary`).** GeoUltra and GEOS 2.0 are booted in VICE
   (GEOS 2.0 from the user's own disk) and their RAM at `$9000-$9FFF`
   (the disk driver) and `$C000-$FFFF` (the kernal) compared: runs of
   16 or more identical bytes, runs that are mostly one value (cleared
   memory, fills) left out.

## What the first measurement found (2026-11-20)

- **Source:** about 0.5% of the kernal's and driver's instruction
  windows also occurred in GEOS 2.0, in about 15 short routines, with
  shared runs of 14 to 26 instructions. (A first figure of 1.5% had
  counted Wheels' source in mist64/geos by mistake.) The desktop, for
  calibration: no shared run longer than 12.
- **Binary:** identical runs of 23 to 45 bytes in the file system
  routines (ReadFile, ReadByte, PointRecord, UpdateRecordFile,
  DeleteRecord, BldGDirEntry, CopyDate, ClassMatch) and the driver's
  SetNextFree and FindBAMBit, besides data tables.

Each routine was then read side by side with GEOS 2.0's and sorted.

### Forced by the specification and the 6502: kept, explained

When two programs implement the same interface on the same processor,
some code comes out the same:

- HG2G fixes each routine's inputs, outputs, the registers it destroys,
  and the data structures: directory entries, the VLIR index, the BAM,
  file headers, font headers. Code that walks such a structure field by
  field in its documented order looks alike.
- The 6502 has few sensible ways to do some things: a 16-bit add or
  decrement, a multiply by 17, reading a header with `lda (zp),y / sta /
  iny`.
- **LoadCharSet** copies the font header's fields in their order; the
  same instruction run even occurs in an unused leftover of GEOS 128
  (`junk_back`), unrelated code.
- **The keyboard tables and the screen-row address table** follow from
  the C64's keyboard matrix, GEOS's key codes and the VIC's bitmap
  layout.
- **ToBASIC's reset part** follows the C64 ROM's own reset sequence, as
  GEOS 2.0's does.
- **Registers left behind.** GEOS 2.0 leaves certain values in A, X and
  Y that HG2G does not promise, and programs do use some of them. The
  conformance tests demand the same values (for example A = the number
  of records and Y = the current record after OpenRecordFile), so the
  last instructions of such routines are fixed even where the routine
  is written differently.

### Kept by the user's decision: data

- **The system font's width table:** the widths decide where every
  existing document breaks its lines; other widths would re-flow every
  geoWrite document written under GEOS. The glyphs themselves are
  GeoUltra's own.
- **The standard fill patterns:** programs and documents refer to them
  by number; other patterns would change every drawing.

### Beyond the specification: rewritten

In twelve routines the matches went beyond what the specification
forces: the same order of independent steps, the same branch layout,
the same tricks. These were written anew from HG2G's descriptions, in
their own structure (2026-11-20 and 2026-11-25):

| Routine | What was the same | Now |
| --- | --- | --- |
| Sleep | the whole routine, with a flags trick | the entry filled first, made visible to the interrupt by one increment; a full table lets the caller go on |
| CRC | set-up, bit loop and byte counter | the byte-at-a-time form of the same checksum (each byte into the high half, eight shifts) |
| OpenRecordFile | counting the records, setting curRecord | counted in X, curRecord from a compare |
| ReadRecord, InsertRecord, DeleteRecord | the order of checks, the index move | own checks; the move from the end with offsets |
| FindFile | the name compare with $A0 padding | a separate compare routine through a pointer to the entry's name |
| FindFTypes | the steps around the 17-byte slots | the buffer cleared a slot at a time, names copied through that pointer |
| FollowChain, ReadFile, ReadByte | the store and copy loops | forwards and counted, the table pointer moved and restored |
| RenameFile, BldGDirEntry, CopyDate | the name copy and padding, the date copy | one loop with the padding as a state; the date backwards |
| ToBASIC | the command copy with a case trick, the clearing | the command from its end with its own end test, the clearing with Y |
| GetString | the key checks in the same order | own dispatch |
| DoIcons | the draw loop | own loop (largely forced by BitmapUp's parameters) |
| BlkAlloc (driver) | the block loop and the last block's byte count | own loop: the pair stored high byte first, the counter by subtraction, the end marker through X |

Also rewritten although they counted as forced: **NextDay** (the next
date: now count up first, then check the month's end) and the 1571
**BAM lookup and next free block** (own order of computation, the
directory tracks tested in one place).

Each change was checked against GEOS 2.0 by the conformance cases (all
304 on a 1541 and the 1581 set), the engine suite, the font, native,
1571, folder, file dialog, system font, shell, desktop and print suites.

## The measurement now

Measured on 2026-11-25, after the rewrites:

- **Source:** 18 of 22,458 instruction windows (0.1%) also occur in
  GEOS 2.0. No shared run is longer than 14 instructions; the longest
  is LoadCharSet's header copy (forced, above). The others are 12 or 13
  instructions long, about the level of the calibration (GeoUltra's
  desktop: one shared run of 12, in code that was never near GEOS 2.0's).
- **Binary:** 39 runs of 16 bytes or more, 1,016 of 20,480 bytes. By
  kind:
  - **Data kept by decision:** the system font's width table (195, 25
    and 20 bytes in three runs), the fill patterns (24).
  - **Fixed by hardware or format:** the keyboard tables (2 × 32), the
    screen-row address table (26), the jump table at `$C100` (the
    contract itself), the "GEOS format V1.0" disk signature, the
    message text "System error near".
  - **ToBASIC's reset part** (49, 31 and 20 bytes): the same steps as
    the C64 ROM's reset, which both follow.
  - **Short code, still the same byte for byte (18-34 bytes each):**
    PointRecord with RecordTS and SetRecordTS (kept so on purpose for
    the registers they leave, above), the link part of ReadFile and
    ReadByte, SetGDirEntry's copy and ClearWrite, a part of DoIcons,
    PromptTick, Changing, WriteRecord's size update, and two parts of
    the driver's 1541 BAM code (FindBAMBit, AllocateBlock). These are
    below the source measure's 12 instructions, and in bytes the same
    because both systems use GEOS's fixed variable addresses.

**The short code pieces, looked at one by one (2026-11-26):** each is
the plain implementation of a documented variable or format, at
GEOS's fixed addresses, where a rewrite would change how it looks
but not where it comes from, and would risk the registers GEOS 2.0
leaves behind (which the conformance cases demand):

| Piece | Why it is the same |
| --- | --- |
| PointRecord, RecordTS, SetRecordTS | a bounds check of the record number and a two-byte copy from or to the VLIR index; the registers left (A = r1H, Y = the index offset) are GEOS 2.0's, which programs may use |
| ReadFile's and ReadByte's link handling | the next block is the first two bytes of the block (the disk format); track 0 marks the last, its second byte the end |
| SetGDirEntry's copy, ClearWrite | copying a 30-byte directory entry into its block; a block cleared to zero with the link 0, $FF of an empty block |
| Changing, WriteRecord's empty record | the BAM read once before the first change (one flag); an empty record is the index entry 0, $FF (the VLIR format) |
| PromptTick | the documented meaning of `alphaFlag`: bit 7 active, bit 6 shown, the low bits counting `PROMPT_DELAY` down |
| DoIcons' press | the documented `iconSelFlag` (flash or invert) and `selectionFlash` |
| the driver's 1541 FindBAMBit, AllocateBlock | the 1541 BAM's layout: four bytes a track, a count and three bitmap bytes |

These are judgements; the measurement and this list are here so that
anyone can check them.

## Repeating it

    tools/dev/cleanroom.py PATH/TO/mist64/geos            # the source
    tools/dev/cleanroom.py PATH/TO/mist64/geos --binary   # and the RAM (VICE, GEOS_ORACLE)

Before a release: no shared source run longer than the desktop's
calibration level without an entry under "forced" above, and no binary
run outside the data kept by decision, the fixed-address tables and the
short pieces listed above (a new one is looked at the same way).
