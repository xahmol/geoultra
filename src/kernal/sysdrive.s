; The system drive, drive E (docs/DESIGN.md "System drive"; ARCHITECTURE
; "System drive"): GeoUltra's own GEOS files (geoFolder ...) on a
; read-only 1541 image at REU bank SYSDRV_BANK, relocated at build time
; (tools/sysreloc.py) so all its track/sector references use tracks
; 221-255. The disk driver reads those tracks from drive E on every drive
; (reudrv.s, Locate), so a file found there can be read through the
; current drive, also by applications that keep track/sector pairs
; (geoWrite reads fonts by them). Searching E's directory borrows the
; current drive's slot for a moment (driveType and curType as a 1541,
; ramBase = SYSDRV_BANK, the driver's flags with F_READONLY); the
; current drive's directory header (curDirHead, which reading E's
; directory replaces) is kept in REU bank 1 meanwhile.
; - FindFTypes (files.s) adds E's desk accessories and fonts;
; - FindFile through the jump table, GetFile and OpenRecordFile fall back
;   to E for a desk accessory or font not found on the current drive;
;   the kernal's other callers (DeleteFile, RenameFile, SaveFile ...) do
;   not, so they never change E's files.
; Not on a native drive with more than 220 tracks (its tracks are real).
; Own code.

        .include "geos.inc"
        .include "sysdrive.inc"
        .include "hw.inc"

        .export SysFTypes, SysFindFile, AppGate, RefusedMsg, turboWant, turboNow
        .export sysName
        .import OvlCall, FindFTypes, FindFile, drvFlags, drvTracks, SysRAMOp
        .import GetFHdrInfo, DoDlgBox, EnterDeskTop, RootFTypes, RootFind

F_READONLY      = $02
HEAD_SAVE       = $1800         ; curDirHead's copy in REU bank 1
OFF_FNAME       = 3             ; the name in a directory entry
FONT            = 8             ; GEOS file type

        .segment "CODE"

SysFTypes:                      ; FindFTypes's end (files.s): the root
        jmp RootFTypes          ; folder's (rootmerge.s), then drive E's
AppGate:                        ; LdApplic, before an application loads
        jsr OvlCall
        .byte 15, 6
RefusedMsg:                     ; EnterDeskTop: the refusal, if any
        jsr OvlCall
        .byte 15, 9

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
@e:     jmp RootFind            ; the root folder, then drive E

; Resident: survive nested overlay calls (overlay.s).
sysActive:      .byte 0         ; $80: the current slot shows drive E
sysName:        .word 0         ; SysFindFile's name
sysR6:          .word 0         ; r6, A, Y after the failed FindFile
sysA:           .byte 0
sysRefused:     .byte 0         ; $80: an application was refused
sysY:           .byte 0
sysType:        .byte 0         ; the borrowed slot's values
sysCurType:     .byte 0
sysBase:        .byte 0
sysFlags:       .byte 0

        .segment "DATA"
turboWant:      .byte $FF       ; $D031 at full speed; $FF: no turbo (speed.s)
turboNow:       .byte $FF       ; $D031 now (a resumed session: Resumed)

        .segment "OVL15"                ; overlay module 15: drive E

        jmp OvFTypes            ; entry 0
        jmp OvFindFile          ; entry 3
        jmp OvAppGate           ; entry 6
        jmp OvRefused           ; entry 9

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
Enter:  ldy #REU_STASH
        jsr HeadDma
        ldx curDrive
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

; Leave: the slot back as it was, curDirHead too. X kept.
Leave:  txa
        pha
        ldy #REU_FETCH
        jsr HeadDma
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

; HeadDma: curDirHead to (Y = REU_STASH) or from (REU_FETCH) HEAD_SAVE in
; REU bank 1; r0-r3 kept (OvFindFile returns r1).
HeadDma:
        ldx #7
@save:  lda r0L,x
        pha
        dex
        bpl @save
        lda #<curDirHead
        sta r0L
        lda #>curDirHead
        sta r0H
        lda #<HEAD_SAVE
        sta r1L
        lda #>HEAD_SAVE
        sta r1H
        lda #0
        sta r2L
        lda #1
        sta r2H
        sta r3L                 ; bank 1
        jsr SysRAMOp
        ldx #0
@back:  pla
        sta r0L,x
        inx
        cpx #8
        bne @back
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
; dirEntryBuf, r1 and r5 as FindFile leaves them (E's tracks), else A, Y
; and r6 as the failed FindFile left them and X = FILE_NOT_FOUND
; (OpenRecordFile's Y is compared with GEOS 2.0's, tests/conformance).
OvFindFile:
        sta sysA
        sty sysY
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
        ldy sysY
        lda sysA
        ldx #FILE_NOT_FOUND
@end:   rts

; OvAppGate (LdApplic, r9 = the entry of an application or auto-exec
; file about to load): applications that cannot work with GeoUltra are
; refused before they overwrite the caller: the desktop is started anew
; and shows why (OvRefused). The GEOS 2.0 deskTop does not expect
; LdApplic to return ("System error near $4D77" followed), and a dialog
; shown at that moment also left it broken: by then it has dismantled
; part of itself for the launch. X = 0 to go on. Refused: GEOS 2.0's CONFIGURE (permanent name
; "Configure"), which loads its own disk drivers over $9000 and crashed
; GeoUltra (U64, 2026-10-30); GeoUltra Settings does its job.
; r0-r15 kept (GetFHdrInfo changes r1, r7, which LdApplic still needs).
OvAppGate:
        ldx #0
@save:  lda r0L,x
        pha
        inx
        cpx #32
        bne @save
        lda r0L                 ; only loaded, not started (bit 0): fine
        lsr                     ; (a conformance case loads CONFIGURE's
        bcs @go                 ; record 0 that way)
        jsr GetFHdrInfo
        txa
        bne @go                 ; (LdApplic reports it again)
        ldx #REFUSE_LEN - 1
@cmp:   lda fileHeader + O_GHFNAME,x
        cmp refuseName,x
        bne @speed
        dex
        bpl @cmp
        lda #$80                ; refused
        sta sysRefused
        jmp EnterDeskTop        ; (resets the stack)
@speed: jsr SpeedFor            ; its turbo speed (speed.s)
@go:    ldx #0
        stx sysA
        ldx #31
@back:  pla
        sta r0L,x
        dex
        bpl @back
        ldx sysA
        rts

SpeedFor:                       ; (a stub here: the return goes to the
        jsr OvlCall             ; caller, back in this module)
        .byte 16, 0

; OvRefused (EnterDeskTop, after InitMachine and the background): the
; refusal dialog when an application was refused. It is built in the
; stack page, above the stack pointer: the slot cannot hold it (DoDlgBox
; calls overlays, which replace the slot), the calls it makes stay below
; it, and DoDlgBox returns with the stack as it was.
OvRefused:
        bit sysRefused
        bpl @end
        lda #0
        sta sysRefused
        tsx                     ; DLG_LEN bytes of stack room
        txa
        sec
        sbc #DLG_LEN
        tax
        txs
        inx
        stx r0L                 ; r0 = $0100 + SP + 1, the dialog
        lda #>$0100
        sta r0H
        ldy #DLG_LEN - 1
@copy:  lda dlgTemplate,y
        sta (r0),y
        dey
        bpl @copy
        clc                     ; the text pointers into the copy (the
        lda r0L                 ; block ends at most at $01FF: no carry)
        adc #DLG_TEXT1
        ldy #4
        sta (r0),y
        clc
        lda r0L
        adc #DLG_TEXT2
        ldy #9
        sta (r0),y
        jsr DoDlgBox
        tsx                     ; the room given back
        txa
        clc
        adc #DLG_LEN
        tax
        txs
@end:   rts

refuseName:     .byte "Configure"
REFUSE_LEN      = * - refuseName
dlgTemplate:    .byte DEF_DB_POS | 1
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6, 0, >$0100
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6, 0, >$0100
                .byte OK, DBI_X_2, DBI_Y_2
                .byte 0
DLG_TEXT1       = * - dlgTemplate
                .byte BOLDON, "Configure is not", 0
DLG_TEXT2       = * - dlgTemplate
                .byte "for GeoUltra", 0
DLG_LEN         = * - dlgTemplate
