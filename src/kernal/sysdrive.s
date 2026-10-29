; The system drive, drive E (docs/DESIGN.md "System drive"; ARCHITECTURE
; "System drive"): GeoUltra's own GEOS files (geoFolder ...) on a
; read-only 1541 image at REU bank SYSDRV_BANK, relocated at build time
; (tools/sysreloc.py) so all its track/sector references use tracks
; 221-255. The disk driver reads those tracks from drive E on every drive
; (reudrv.s, Locate), so a file found there can be read through the
; current drive, also by applications that keep track/sector pairs
; (geoWrite reads fonts by them). Searching E's directory borrows the
; current drive's slot for a moment (driveType and curType as a 1541,
; ramBase = SYSDRV_BANK, the driver's flags with F_READONLY).
; - FindFTypes (files.s) adds E's desk accessories and fonts;
; - FindFile through the jump table, GetFile and OpenRecordFile fall back
;   to E for a desk accessory or font not found on the current drive;
;   the kernal's other callers (DeleteFile, RenameFile, SaveFile ...) do
;   not, so they never change E's files.
; Not on a native drive with more than 220 tracks (its tracks are real).
; Own code.

        .include "geos.inc"
        .include "sysdrive.inc"

        .export SysFTypes, SysFindFile
        .import OvlCall, FindFTypes, FindFile, drvFlags, drvTracks

F_READONLY      = $02
OFF_FNAME       = 3             ; the name in a directory entry
FONT            = 8             ; GEOS file type

        .segment "CODE"

SysFTypes:                      ; FindFTypes's end (files.s)
        jsr OvlCall
        .byte 15, 0

; SysFindFile: FindFile (r6 = name), then drive E for a desk accessory or
; a font that is not on the current drive.
SysFindFile:
        lda r6L
        sta sysName
        lda r6H
        sta sysName+1
        jsr FindFile
        cpx #FILE_NOT_FOUND
        beq @e
        rts
@e:     jsr OvlCall
        .byte 15, 3

; Resident: survive nested overlay calls (overlay.s).
sysActive:      .byte 0         ; $80: the current slot shows drive E
sysName:        .word 0         ; SysFindFile's name
sysR6:          .word 0         ; r6 after the failed FindFile
sysType:        .byte 0         ; the borrowed slot's values
sysCurType:     .byte 0
sysBase:        .byte 0
sysFlags:       .byte 0

        .segment "OVL15"                ; overlay module 15: drive E

        jmp OvFTypes            ; entry 0
        jmp OvFindFile          ; entry 3

; Usable: C clear when drive E can be shown on the current drive (not a
; native one with more than SYSDRV_TRACK tracks, and not shown already).
Usable: sec
        bit sysActive
        bmi @end
        ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_NATIVE
        bcc @end
        lda drvTracks-8,x
        cmp #SYSDRV_TRACK + 1
@end:   rts

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
        lda #SYSDRV_BANK
        sta ramBase-8,x
        lda drvFlags-8,x
        sta sysFlags
        ora #F_READONLY
        sta drvFlags-8,x
        lda #$80
        sta sysActive
        rts

; Leave: the slot back as it was. X kept.
Leave:  txa
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
        rts

; OvFTypes (after FindFTypes, X its error, r6/r7H where it stopped): for
; desk accessories and fonts with room left, drive E's are added.
OvFTypes:
        txa
        bne @end
        lda r7L
        cmp #DESK_ACC
        beq @type
        cmp #FONT
        bne @end
@type:  lda r7H
        beq @end
        jsr Usable
        bcs @ok
        clc                     ; FindFTypes moved r6 back by the name's
        lda r6L                 ; offset: forward again for the second run
        adc #OFF_FNAME
        sta r6L
        bcc @e
        inc r6H
@e:     jsr Enter
        jsr FindFTypes
        jsr Leave
@ok:    ldx #0
@end:   rts

; OvFindFile (FindFile failed with FILE_NOT_FOUND): the name in drive E's
; directory; found there as a desk accessory or font, X = 0 with
; dirEntryBuf, r1 and r5 as FindFile leaves them (E's tracks), else r6 as
; the failed FindFile left it and X = FILE_NOT_FOUND.
OvFindFile:
        lda r6L
        sta sysR6
        lda r6H
        sta sysR6+1
        jsr Usable
        bcs @not
        lda sysName
        sta r6L
        lda sysName+1
        sta r6H
        jsr Enter
        jsr FindFile
        jsr Leave
        txa
        bne @not
        lda dirEntryBuf + OFF_GFILE_TYPE
        cmp #DESK_ACC
        beq @end
        cmp #FONT
        beq @end
@not:   lda sysR6
        sta r6L
        lda sysR6+1
        sta r6H
        ldx #FILE_NOT_FOUND
@end:   rts
