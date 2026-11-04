; Shared by the folder modules 12, 13 and 14 (src/kernal/folders.s):
; assembled into each, as an overlay module cannot call another's code.

; Native: X = slot (curDrive - 8), C clear; else C set, X = STRUCT_MISMAT.
Native: ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_NATIVE
        bne @no
        txa
        sec
        sbc #8
        tax
        clc
        rts
@no:    ldx #STRUCT_MISMAT
        sec
        rts

; FindDir: r0 = name; the entry (dirEntryBuf, r1 = its block, r5 = it in
; diskBlkBuf) of a folder. C set and X = error when there is none.
FindDir:
        lda r0L
        sta r6L
        sta nameLo
        lda r0H
        sta r6H
        sta nameHi
        jsr FindFile
        txa
        bne @fail
        lda dirEntryBuf
        and #$07
        cmp #6                  ; DIR
        beq @ok
        ldx #STRUCT_MISMAT
@fail:  sec
        rts
@ok:    clc
        rts

        .include "foldername.inc"
