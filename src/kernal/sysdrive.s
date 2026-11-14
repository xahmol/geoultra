; The system drive, drive E (docs/DESIGN.md "System drive"; ARCHITECTURE
; "System drive"): GeoUltra's own GEOS files (geoFolder ...) on a
; read-only native image with folders (src/sysdrive.toml) at REU bank
; SYSDRV_BANK, relocated at build time (tools/sysreloc.py) so all its
; track/sector references use tracks SYSDRV_TRACK+1 to 255. The disk
; driver reads those tracks from drive E on every drive (reudrv.s,
; Locate), so a file found there can be read through the current drive,
; also by applications that keep track/sector pairs (geoWrite reads
; fonts by them). Searching E's directory borrows the current drive's
; slot for a moment (module 81, sysenter.s: native, E's tracks and root
; folder, ramBase = SYSDRV_BANK, the driver's flags with F_READONLY); the
; current drive's directory header (curDirHead) is kept in REU bank 1
; meanwhile, and the native BAM working copy is left alone.
; - FindFTypes (files.s) adds E's desk accessories and fonts;
; - FindFile through the jump table, GetFile and OpenRecordFile fall back
;   to E for a desk accessory or font not found on the current drive;
;   the kernal's other callers (DeleteFile, RenameFile, SaveFile ...) do
;   not, so they never change E's files.
; Not on a native drive with more than SYSDRV_TRACK tracks (its tracks are
; real).
; Own code.

        .include "geos.inc"
        .include "sysdrive.inc"
        .include "hw.inc"
        .include "drvflags.inc"

        .export SysFTypes, SysFindFile, AppGate, RefusedMsg, turboWant, turboNow
        .export AppFTypes, ftStart, ftAll, ftLeft
        .export sysName, sysActive, sysType, sysCurType, sysBase, sysFlags
        .export sysTracks, sysFolderT, sysFolderS, sysSlot, ownDesk, sysActive
        .export imgFlags, imgBank, imgType, imgTracks, uTouch, autoIdx
        .import OvlCall, FindFTypes, FindFile
        .import GetFHdrInfo, DoDlgBox, EnterDeskTop, RootFTypes, RootFind

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

        .segment "KEXT"                 ; (CODE is full)

; AppFTypes (FindFTypes through the jump table, for applications and the
; desktop): where the list starts and how many names fit noted for
; OvFTypes, which puts drive E's desk accessories first (the user,
; 2026-11-13: geoFolder fell off full menus). The kernal's own searches
; call FindFTypes directly and are left as they are.
AppFTypes:
        lda r6L
        sta ftStart
        lda r6H
        sta ftStart+1
        lda r7H
        sta ftCount
        jmp FindFTypes
ftStart:        .word 0
ftCount:        .byte 0         ; 0: no application's list pending
ftAll:          .byte 0         ; OvFTypes: names that fitted at the start
ftLeft:         .byte 0         ; and those left before E's search
                                ; (resident: Enter reloads module 15)
; A disk image gone into (engineimg.s, modules 88, 89): its copy in the
; REU kept between engine calls. imgFlags: bit 7 the copy is there and
; matches the file (cleared by a call that may write on the Ultimate,
; module 81, and by a resumed session, module 8), F_BACKUP and F_DIRTY
; carried from one showing to the next.
imgFlags:       .byte 0
imgBank:        .byte 0         ; its first REU bank
imgType:        .byte 0         ; its DRV_* type
imgTracks:      .byte 0         ; native: its tracks (else 0)
autoIdx:        .byte $FF       ; autoexec.s (module 92): the next auto-exec
                                ; of the cold start's list ($FF: none running)
uTouch:         .byte 0         ; module 88: a plain Ultimate path was
                                ; resolved in this call (module 81 clears it)

        .segment "CODE"

; Resident: survive nested overlay calls (overlay.s).
sysActive:      .byte 0         ; $80: the current slot shows drive E ($C0:
                                ; for the engine); $60: a disk image
                                ; gone into (engineimg.s; bit 7 clear: the
                                ; driver's rule for E's BAM stays off)
sysName:        .word 0         ; SysFindFile's name
sysR6:          .word 0         ; r6, A, Y after the failed FindFile
sysA:           .byte 0
sysRefused:     .byte 0         ; $80: an application was refused
sysY:           .byte 0
sysType:        .byte 0         ; the borrowed slot's values
sysCurType:     .byte 0
sysBase:        .byte 0
sysFlags:       .byte 0
sysTracks:      .byte 0
sysFolderT:     .byte 0
sysFolderS:     .byte 0
sysSlot:        .byte 0         ; the slot E (or a disk image, engineimg.s)
                                ; is shown in: its device, 8-11
ownDesk:        .byte $80       ; $80: EnterDeskTop starts GeoUltra's desktop
                                ; (always since 2026-11-13: desktop=geos
                                ; dropped, user; 0 kept for a test that
                                ; wants GEOS 2.0's deskTop)

        .segment "DATA"
turboWant:      .byte $FF       ; $D031 at full speed; $FF: no turbo (speed.s)
turboNow:       .byte $FF       ; $D031 now (a resumed session: Resumed)

        .segment "OVL15"                ; overlay module 15: drive E

        jmp OvFTypes            ; entry 0
        jmp OvFindFile          ; entry 3
        jmp OvAppGate           ; entry 6
        jmp OvRefused           ; entry 9

        .include "sysenter.inc" ; Enter, Leave, Usable (module 81)

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
        bne @room
        lda ftCount             ; an application's full list of desk
        beq @end                ; accessories: its last place for E's
        lda r7L                 ; one (geoFolder; the user, 2026-11-13)
        cmp #DESK_ACC
        bne @end
        inc r7H
        lda r6L
        sec
        sbc #17
        sta r6L
        bcs @room
        dec r6H
@room:  jsr Usable
        bcs @ok
        clc                     ; FindFTypes moved r6 back by the name's
        lda r6L                 ; offset: forward again for the second run
        adc #OFF_FNAME
        sta r6L
        bcc @e
        inc r6H
@e:     lda ftCount             ; an application's list? (taken here and
        sta ftAll               ; cleared: E's own search ends in
        lda #0                  ; OvFTypes too)
        sta ftCount
        lda r7H
        sta ftLeft
        jsr Enter
        jsr FindFTypes
        jsr Leave
        lda r7L
        cmp #DESK_ACC
        bne @ok
        lda ftAll
        beq @ok
        jsr EFirst
@ok:    ldx #0
@end:   ldy #0                  ; (no list pending after this search)
        sty ftCount
        rts

EFirst: jsr OvlCall             ; (rootmerge.s, module 17: room)
        .byte 17, 6

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

        .segment "OVL55"                ; overlay module 55: FE_RUNSYS
        .scope Mod55

        .include "engine.inc"

        jmp OvRunSys            ; entry 0

        .include "sysenter.inc"

LdApplic        = $C21D         ; GEOS jump table

; OvRunSys (FE_RUNSYS, from the file engine's dispatcher; gush at the cold
; start and from geoFolder): r0 = the name of an application on drive E,
; started (LdApplic from E's entry; its blocks show as E's tracks on
; every drive, so they load from the current one). Back only with X =
; FILE_NOT_FOUND, STRUCT_MISMAT (no application), DEV_NOT_FOUND (E cannot
; be shown on this drive) or LdApplic's error.
OvRunSys:
        ldx #DEV_NOT_FOUND
        jsr Usable
        bcs @end
        lda argR0
        sta r6L
        lda argR0+1
        sta r6H
        jsr Enter
        jsr FindFile
        jsr Leave
        txa
        bne @end
        ldx #STRUCT_MISMAT
        lda dirEntryBuf + OFF_GFILE_TYPE
        cmp #APPLICATION
        bne @end
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        lda #0                  ; (no data file)
        sta r0L
        jmp LdApplic
@end:   rts

        .endscope
