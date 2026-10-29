; Disk device selection: SetDevice, GetPtrCurDkNm. Written from the
; HG2G2022 descriptions. The disk routines themselves are in the disk
; driver at $9000 (src/drivers/reudrv.s); the jump table reaches them
; through its vectors.

        .include "geos.inc"

        .export SetDevice, GetPtrCurDkNm

        .segment "IOCODE"       ; (under I/O, as in GEOS 2.0)

; SetDevice: A = device (8-11 drives, else any serial device). Sets
; curDevice and, for a drive, curDrive and curType. Returns X = 0.
; Destroys A, Y.
SetDevice:
        sta curDevice
        cmp #8
        bcc @end
        cmp #12
        bcs @end
        sta curDrive
        tay
        lda driveType-8,y
        sta curType
@end:   ldx #0
        rts

        .segment "CODE"

; GetPtrCurDkNm: X = zero page word, set to the current drive's disk
; name buffer. Destroys A, Y.
GetPtrCurDkNm:
        ldy curDrive
        lda nameLo-8,y
        sta $00,x
        lda nameHi-8,y
        sta $01,x
        rts

nameLo: .byte <DrACurDkNm, <DrBCurDkNm, <DrCCurDkNm, <DrDCurDkNm
nameHi: .byte >DrACurDkNm, >DrBCurDkNm, >DrCCurDkNm, >DrDCurDkNm
