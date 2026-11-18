; Drive B and the document's drive swapped while a program runs (overlay
; module 118; docs/DESIGN.md "Drives"; the user's decision of
; 2026-11-18). geoWrite 2.1, started with a document, looks for it on
; drive A when the disk names match and otherwise always on drive B
; (findDocDevice in mist64/geowrite, read for this behaviour only), so a
; document on C or D was not found. The desktop (appfind.s AppGo) asks
; for FE_DRVSWAP with the document's drive before it starts the program:
; drives B and C (or D) trade everything that makes them what they are,
; so the document's drive answers as B; EnterDeskTop swaps them back
; (load.s, after the write-back). Swapped: the driver's tables
; (driveType, ramBase, drvFlags, drvTracks), the current folders
; (folderT, folderS), the disk names (DrBCurDkNm and DrC/DrDCurDkNm), the
; native BAM working copy's owner (natLoaded), and in REU bank 1 each
; drive's mount table entry, image path and dirty map (enginemount.s).
; A task switched to meanwhile sees the letters swapped too. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "engine.inc"

        .import drvTracks, drvFlags, folderT, folderS, natLoaded, SysRAMOp
        .export swapDrv

SYS_BANK        = 1
                                ; REU bank 1 (engine.inc, enginemount.s):
ENTRY_LEN       = 32            ; a drive's mount table entry,
MOUNT_PATH      = MOUNT_PATHS   ; its image path,
PATH_LEN        = 64
DIRTY_MAPS      = $2000         ; its dirty map
MAP_LEN         = $2000
NAME_LEN        = 18            ; a disk name's room (DrACurDkNm...)
REU_SWAP        = $92           ; execute now, C64 <-> REU
BUF             = diskBlkBuf    ; (free: no disk call runs meanwhile)
CHUNK           = 256

        .segment "KCODE"

swapDrv:        .byte 0         ; 0, or the drive (10, 11) swapped with B

        .segment "OVL118"
        .scope Mod118

        jmp FeSwap              ; entry 0 (FE_DRVSWAP, the file engine)
        jmp Back                ; entry 3 (EnterDeskTop)

; FE_DRVSWAP: r0L (argR0) = 10 or 11: that drive swapped with B (a
; swap still in place is undone first); 0: swapped back. X = 0, or
; FE_BAD_PATH for another drive.
FeSwap: jsr Back
        lda argR0
        beq @ok
        cmp #10
        bcc @bad
        cmp #12
        bcs @bad
        sta swapDrv
        jsr Swap
@ok:    ldx #0
        rts
@bad:   ldx #FE_BAD_PATH
        rts

; Back: swapped back when a swap is in place.
Back:   lda swapDrv
        beq @end
        jsr Swap
        lda #0
        sta swapDrv
@end:   rts

; Swap: drive B and drive swapDrv trade their state (see above).
; Destroys A, X, Y, r0-r3, diskBlkBuf.
Swap:   lda swapDrv
        sec
        sbc #8
        sta other               ; its slot (2, 3)
        ldx #TABLES - 1         ; the tables, one byte each
@tab:   lda TabLo,x
        sta r0L
        lda TabHi,x
        sta r0H
        ldy #1
        lda (r0),y
        pha
        ldy other
        lda (r0),y
        ldy #1
        sta (r0),y
        pla
        ldy other
        sta (r0),y
        dex
        bpl @tab
        ldx other               ; the disk names
        lda NameLo-2,x
        sta r0L
        lda NameHi-2,x
        sta r0H
        ldy #NAME_LEN - 1
@name:  lda DrBCurDkNm,y
        pha
        lda (r0),y
        sta DrBCurDkNm,y
        pla
        sta (r0),y
        dey
        bpl @name
        lda natLoaded           ; the BAM working copy's owner
        cmp #9
        bne :+
        lda swapDrv
        bne @nat                ; (always)
:       cmp swapDrv
        bne @reu
        lda #9
@nat:   sta natLoaded
@reu:   ldx #0                  ; REU bank 1: entry, path, dirty map
@area:  stx area
        lda AreaBase,x          ; r4 = B's place, r5 = the other's
        sta r4L
        lda AreaBaseH,x
        sta r4H
        lda AreaLenH,x          ; (lengths: a multiple of 32; the map's
        sta lenH                ; high byte counts its pages)
        lda AreaLen,x
        sta lenL
        clc                     ; + 1 * length: B
        lda r4L
        adc lenL
        sta r4L
        lda r4H
        adc lenH
        sta r4H
        lda r4L                 ; + other * length: the other
        sta r5L
        lda r4H
        sta r5H
        ldy other
        dey
@mul:   clc
        lda r5L
        adc lenL
        sta r5L
        lda r5H
        adc lenH
        sta r5H
        dey
        bne @mul
@chunk: lda lenH                ; one chunk: the rest, at most a page
        bne @full
        lda lenL
        beq @done
        bne @part               ; (always)
@full:  lda #0                  ; (256)
@part:  sta cnt
        jsr Trade
        lda cnt                 ; the places on, the rest less
        beq @page
        clc
        adc r4L
        sta r4L
        bcc :+
        inc r4H
:       lda cnt
        clc
        adc r5L
        sta r5L
        bcc :+
        inc r5H
:       lda lenL
        sec
        sbc cnt
        sta lenL
        bcs @chunk
        dec lenH
        jmp @chunk
@page:  inc r4H                 ; (a whole page)
        inc r5H
        dec lenH
        jmp @chunk
@done:  ldx area
        inx
        cpx #AREAS
        bcs :+
        jmp @area
:       rts

; Trade: cnt bytes (0: 256) at REU r4 and r5 (bank 1) exchanged through
; BUF: r4's to BUF, BUF swapped with r5's, BUF to r4.
Trade:  lda r4L
        ldx r4H
        ldy #REU_FETCH
        jsr Op
        lda r5L
        ldx r5H
        ldy #REU_SWAP
        jsr Op
        lda r4L
        ldx r4H
        ldy #REU_STASH
; Op: Y = command, A/X = REU address in bank 1, cnt bytes with BUF.
Op:     sta r1L
        stx r1H
        lda #<BUF
        sta r0L
        lda #>BUF
        sta r0H
        lda cnt
        sta r2L
        lda #0
        sta r2H
        lda cnt
        bne :+
        inc r2H                 ; (0: 256)
:       lda #SYS_BANK
        sta r3L
        jmp SysRAMOp

TabLo:  .byte <driveType, <ramBase, <drvFlags, <drvTracks, <folderT, <folderS
TabHi:  .byte >driveType, >ramBase, >drvFlags, >drvTracks, >folderT, >folderS
TABLES  = * - TabHi
NameLo: .byte <DrCCurDkNm, <DrDCurDkNm
NameHi: .byte >DrCCurDkNm, >DrDCurDkNm
AreaBase:       .byte <MOUNT_ENTRY, <MOUNT_PATH, <DIRTY_MAPS
AreaBaseH:      .byte >MOUNT_ENTRY, >MOUNT_PATH, >DIRTY_MAPS
AreaLen:        .byte <ENTRY_LEN, <PATH_LEN, <MAP_LEN
AreaLenH:       .byte >ENTRY_LEN, >PATH_LEN, >MAP_LEN
AREAS   = * - AreaLenH

other:  .byte 0
area:   .byte 0
lenL:   .byte 0
lenH:   .byte 0
cnt:    .byte 0

        .endscope
