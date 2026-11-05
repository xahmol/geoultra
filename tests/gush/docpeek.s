; DocPeek: a test application for gush's "program document" (tests/gush/
; g9.py). At its start it keeps what GEOS passed it at $5000: r0L, the
; current drive, dataDiskName (18 bytes) and dataFileName (17), then $A5
; at $5030; it then stays in MainLoop. Own code.

        .include "geos.inc"

PEEK            = $5000

        .segment "CODE"

Start:  lda r0L
        sta PEEK
        lda curDrive
        sta PEEK + 1
        ldy #17
@disk:  lda dataDiskName,y
        sta PEEK + 2,y
        dey
        bpl @disk
        ldy #16
@file:  lda dataFileName,y
        sta PEEK + 20,y
        dey
        bpl @file
        lda #$A5
        sta PEEK + $30
        rts
