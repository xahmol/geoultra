; Shared by the folder modules 12, 13 and 14 (src/kernal/folders.s):
; assembled into each, as an overlay module cannot call another's code.

; Is1581, Native: C clear and X = slot (curDrive - 8) when the current
; drive is a 1581 / a native drive, else C set and X = STRUCT_MISMAT.
; IsType: the same for the drive type in A.
Is1581: lda #DRV_1581
        bne IsType
Native: lda #DRV_NATIVE
IsType: ldx curDrive
        eor driveType-8,x       ; (only the type bits compared)
        and #$0F
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
