; The system drive, drive E (docs/DESIGN.md "System drive"; ARCHITECTURE
; "System drive"): GeoUltra's own GEOS files (geoFolder ...) on a
; read-only D64 at REU bank SYS_BANK, copied there from the cartridge.
; Drive E is outside A-D: the kernal borrows the current drive's slot for
; a moment (driveType, curType, ramBase, the driver's flags with
; F_READONLY) and puts it back. Desk accessories on E are added to an
; application's list (FindFTypes) and load from E when they are not on
; the application's drive (GetFile; LdDeskAcc gives the slot back before
; the accessory runs). Own code.

        .include "geos.inc"

        .export SysFTypes, SysGetFile, SysLeave
        .import OvlCall, drvFlags, FindFTypes, FindFile, LdDeskAcc, LoadArgs

SYS_BANK        = 4             ; tools/mkimage.py: build/sysdrive.d64@BANK4
OFF_FNAME       = 3             ; the name in a directory entry
F_READONLY      = $02

        .segment "CODE"

SysFTypes:                      ; FindFTypes's end (files.s): add E's DAs
        jsr OvlCall
        .byte 15, 0
SysGetFile:                     ; GetFile's "not found" (load.s): try E
        jsr OvlCall
        .byte 15, 3
SysLeave:                       ; LdDeskAcc before the accessory runs
        jsr OvlCall
        .byte 15, 6

; Resident: survive nested overlay calls (overlay.s).
sysActive:      .byte 0         ; $80: the current slot shows drive E
sysType:        .byte 0         ; the borrowed slot's values
sysCurType:     .byte 0
sysBase:        .byte 0
sysFlags:       .byte 0

        .segment "OVL15"                ; overlay module 15: drive E

        jmp OvFTypes            ; entry 0
        jmp OvGetFile           ; entry 3
        jmp OvLeave             ; entry 6

; Enter: the current slot shows drive E (a read-only 1541 image).
Enter:  ldx curDrive
        lda driveType-8,x
        sta sysType
        and #$F0                ; (the REU drive bit kept)
        ora #DRV_1541
        sta driveType-8,x
        lda curType
        sta sysCurType
        and #$F0
        ora #DRV_1541
        sta curType
        lda ramBase-8,x
        sta sysBase
        lda #SYS_BANK
        sta ramBase-8,x
        lda drvFlags-8,x
        sta sysFlags
        ora #F_READONLY
        sta drvFlags-8,x
        lda #$80
        sta sysActive
        rts

; OvLeave: the slot back as it was (nothing when drive E is not shown).
OvLeave:
        bit sysActive
        bpl @end
        txa
        pha
        ldx curDrive
        lda sysType
        sta driveType-8,x
        lda sysCurType
        sta curType
        lda sysBase
        sta ramBase-8,x
        lda sysFlags
        sta drvFlags-8,x
        lda #0
        sta sysActive
        pla
        tax
@end:   rts

; OvFTypes (after FindFTypes, X its error, r6/r7H where it stopped): for
; desk accessories with room left, those of drive E are added.
OvFTypes:
        txa
        bne @end
        bit sysActive           ; (FindFTypes on E itself)
        bmi @end
        lda r7L
        cmp #DESK_ACC
        bne @end
        lda r7H
        beq @end
        clc                     ; FindFTypes moved r6 back by the name's
        lda r6L                 ; offset: forward again for the second run
        adc #OFF_FNAME
        sta r6L
        bcc @e
        inc r6H
@e:     jsr Enter
        jsr FindFTypes
        jsr OvLeave
        ldx #0
@end:   rts

; OvGetFile (GetFile's FindFile failed, X its error; the name at r6 + 3):
; a desk accessory of that name on drive E is loaded and started from
; there.
OvGetFile:
        cpx #FILE_NOT_FOUND
        bne @end
        bit sysActive
        bmi @end
        clc
        lda r6L
        adc #OFF_FNAME
        sta r6L
        bcc @e
        inc r6H
@e:     jsr Enter
        jsr FindFile
        txa
        bne @back
        lda dirEntryBuf + OFF_GFILE_TYPE
        cmp #DESK_ACC
        bne @none
        jsr LoadArgs            ; (r10L for the accessory, as GetFile)
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr LdDeskAcc           ; (gives the slot back before it runs)
@back:  jmp OvLeave
@none:  ldx #FILE_NOT_FOUND
        bne @back
@end:   rts
