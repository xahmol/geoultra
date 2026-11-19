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
        .export fontsOn, sysShow
        .import taskName
NAME_LEN        = 13            ; (task.s: taskName's length)
        .import OvlCall, FindFTypes, FindFile, MoveData, drvTracks
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

; SysFindFile: FindFile (r6 = name), then drive E for a desk accessory,
; a font or a printer driver that is not on the current drive.
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
fontsOn:        .byte 0         ; $80: the system fonts loaded (FONTS.DNP,
                                ; banks FONT_BANK on; mount.s LoadFonts)
sysShow:        .byte SYSDRV_BANK ; the bank module 81's Enter shows: E's,
                                ; FONT_BANK while module 123 searches
        .assert SYSDRV_TRACKS = FONT_TRACKS, error, "sysdrive.s: Enter shows both with E's track count"

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

ftAfterF        = $9F9C         ; r7H after the installed fonts (module 15
                                ; -> 116; the overlay scratch, as 116's)
; Modules 116 and 124 (one entry per font ID), in the overlay scratch
; (Enter and Leave are overlay calls: a module's own bytes come back new
; after them; no engine call meanwhile).
fids            = $9F70         ; each entry's font ID (15 words)
nUser           = $9F8E         ; the drive's fonts in the list (first)
nF              = $9F8F         ; the installed ones' (after them)
nE              = $9F90         ; drive E's (last)
nAll            = $9F91
at              = $9F92         ; the entry looked at
fid             = $9F93         ; (word) IdOf's answer ($FFFF: none)
save6           = $9F95         ; (word) the caller's r6
save7           = $9F97         ; (word) the caller's r7
count           = $9F99         ; Ids: entries still to read; Has: its end
MARKED          = $FFFE         ; an entry's ID once it is to be taken out
        .assert fids + 2 * 15 <= nUser, error, "sysdrive.s: fids"
        .assert count < ftAfterF, error, "sysdrive.s: scratch over ftAfterF"

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
        lda ftCount             ; an application's list? (taken here and
        sta ftAll               ; cleared: E's own search ends in
        lda #0                  ; OvFTypes too)
        sta ftCount
        lda r7H
        sta ftLeft
        jsr FFTypes             ; the installed fonts first: they win
        lda r7H                 ; over E's (module 123); where their part
        sta ftAfterF            ; ends (module 116)
        beq @list               ; (no room left for E's)
        clc                     ; FindFTypes moved r6 back by the name's
        lda r6L                 ; offset: forward again for E's run
        adc #OFF_FNAME
        sta r6L
        bcc @e
        inc r6H
@e:     jsr Enter
        jsr FindFTypes
        jsr Leave
@list:  lda ftAll               ; (an application's list only)
        beq @ok
        lda r7L
        cmp #DESK_ACC
        bne @font
        jsr EFirst
        jmp @ok
@font:  jsr Once                ; fonts: one entry per ID (module 116)
@ok:    ldx #0
@end:   ldy #0                  ; (no list pending after this search)
        sty ftCount
        rts

EFirst: jsr OvlCall             ; (rootmerge.s, module 17: room)
        .byte 17, 6
Once:   jsr OvlCall             ; (module 116: E's fonts whose ID the
        .byte 116, 0            ; user's already have taken out)
FFTypes:jsr OvlCall             ; (module 123: the system fonts' too)
        .byte 123, 0
FFind:  jsr OvlCall             ; (module 123: a font in the system
        .byte 123, 3            ; fonts)

; OvFindFile (FindFile failed with FILE_NOT_FOUND): the name in drive E's
; directory; found there as a desk accessory, font or printer driver, X = 0 with
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
        cmp #PRINTER_FILE       ; (GeoUltra's printer drivers live on E:
        beq @end                ; applications load PrntFilename's)
@not:   jsr FFind               ; (not on E: a system font? module 123)
        txa
        beq @end
        lda sysR6
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
; Started (not only loaded): its name for the task list, its turbo
; speed, the colour matrix in screencolors.
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
@speed: ldx #NAME_LEN - 2       ; its permanent name: the task's (task.s)
@nm:    lda fileHeader + O_GHFNAME,x
        sta taskName,x
        dex
        bpl @nm
        lda #0
        sta taskName + NAME_LEN - 1
        jsr SpeedFor            ; its turbo speed (speed.s)
        lda screencolors        ; the colour matrix in GEOS's colours, as
        ldx #0                  ; GEOS 2.0's deskTop leaves it: a program
@col:   sta COLOR_MATRIX,x      ; started another way (gush, a test) found
        sta COLOR_MATRIX+$100,x ; its launcher's colour cells (the user,
        sta COLOR_MATRIX+$200,x ; 2026-11-15: geoWrite with the desktop's
        sta COLOR_MATRIX+$2E8,x ; cells in it)
        inx
        bne @col
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
        jmp OvRunDoc            ; entry 3

        .include "sysenter.inc"

LdApplic        = $C21D         ; GEOS jump table
ST_LD_DATA      = $80

; OvRunSys (FE_RUNSYS, from the file engine's dispatcher; gush at the cold
; start and from geoFolder): r0 = the name of an application on drive E,
; started (LdApplic from E's entry; its blocks show as E's tracks on
; every drive, so they load from the current one). Back only with X =
; FILE_NOT_FOUND, STRUCT_MISMAT (no application), DEV_NOT_FOUND (E cannot
; be shown on this drive) or LdApplic's error.
; OvRunDoc (FE_RUNDOC, 2026-11-19: GU PostScript from the desktop and
; gush): the same with a document, as the deskTop passes one: r1 its
; name, r2 its disk's name (LdApplic with ST_LD_DATA: dataFileName,
; dataDiskName; the application finds the document's drive by the
; disk's name). FE_RUNSYS stays as it was for its callers, which leave
; r1 and r2 as they happen to be.
; The option waits on the stack: Enter is a nested overlay call, after
; which this module's own bytes are fetched again (overlay.s).
OvRunDoc:
        lda #ST_LD_DATA
        .byte $2C               ; (bit abs: the next lda skipped)
OvRunSys:
        lda #0
        pha
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
        lda argR1               ; (FE_RUNDOC: the document and its disk;
        sta r3L                 ; LdApplic reads them only with
        lda argR1+1             ; ST_LD_DATA)
        sta r3H
        lda argR2
        sta r2L
        lda argR2+1
        sta r2H
        pla                     ; (no data file, or ST_LD_DATA)
        sta r0L
        jmp LdApplic
@end:   pla                     ; (the option; X kept)
        rts

        .endscope

; ======================================================================

        .segment "OVL116"
        .scope Mod116

        jmp Once                ; entry 0 (module 15, OvFTypes)

        .include "sysenter.inc"

GetBlock        = $C1E4         ; GEOS jump table
FONT_ID         = $80           ; a font file's header: its ID (word)
ENTRY           = 17            ; FindFTypes: a name and its zero
MAXN            = 15            ; names the list can hold

; Once (an application's font list just got the installed fonts and
; drive E's: ftStart the list, ftAll the names that fitted, ftLeft those
; left before the installed ones' search, ftAfterF after it, r7H after
; E's): one entry per font ID, by the user's rules (2026-11-15 and
; 2026-11-18): a drive's own font wins over GeoUltra's GU fonts on E (their
; LW_Roma, ID 27, hides GU Serif), an installed font (FONTS.DNP) wins
; over both; with the hide switch (fontsOn bit 6, [system] diskfonts=
; hide) the drive's fonts are all left out. r6 and r7H as if those taken
; out had not been found; r0-r5 destroyed (FindFTypes destroys them too).
Once:   lda r6L
        sta save6
        lda r6H
        sta save6+1
        lda r7L
        sta save7
        lda r7H
        sta save7+1
        lda ftAll
        sec
        sbc ftLeft
        sta nUser
        lda ftLeft
        sec
        sbc ftAfterF
        sta nF
        lda ftAfterF
        sec
        sbc r7H
        sta nE
        clc
        adc nF
        adc nUser
        sta nAll
        beq @end
        cmp #MAXN + 1
        bcs @end
        lda #0
        sta at
        lda nUser               ; the IDs: the drive's fonts, the installed
        jsr Ids                 ; ones' and E's (each shown in the slot)
        lda nF
        beq :+
        lda #FONT_BANK
        sta sysShow
        jsr Enter
        lda nF
        jsr Ids
        jsr Leave
        lda #SYSDRV_BANK
        sta sysShow
:       lda nE
        beq :+
        jsr Enter
        lda nE
        jsr Ids
        jsr Leave
:       jsr Marks
        ldx nAll                ; taken out from the last one back
@out:   dex
        bmi @end
        stx at
        jsr Marked
        bne :+
        jsr Remove
:       ldx at
        jmp @out
@end:   lda save6
        sta r6L
        lda save6+1
        sta r6H
        lda save7
        sta r7L
        lda save7+1
        sta r7H
        rts

; Ids: A entries from entry at on: their font IDs into fids (IdOf on
; the drive shown now). at moves past them.
Ids:    sta count
@one:   lda count
        beq @end
        jsr IdOf
        lda at
        asl a
        tax
        lda fid
        sta fids,x
        lda fid+1
        sta fids+1,x
        inc at
        dec count
        jmp @one
@end:   rts

Marks:  jsr OvlCall             ; (module 124: the entries to take out
        .byte 124, 0            ; get the ID MARKED)

; Marked: Z set when entry at is to be taken out (its ID MARKED).
Marked: lda at
        asl a
        tax
        lda fids,x
        cmp #<MARKED
        bne :+
        lda fids+1,x
        cmp #>MARKED
:       rts

; At: r0 = entry at of the list (ftStart + at * 17). Destroys A, X.
At:     lda ftStart
        sta r0L
        lda ftStart+1
        sta r0H
        ldx at
        beq @end
@add:   clc
        lda r0L
        adc #ENTRY
        sta r0L
        bcc :+
        inc r0H
:       dex
        bne @add
@end:   rts

; IdOf: fid = the font ID of the font named by entry at, from its header
; block on the drive shown (FindFile, GetBlock into diskBlkBuf); $FFFF
; when it cannot be read.
IdOf:   lda #$FF
        sta fid
        sta fid+1
        jsr At
        lda r0L
        sta r6L
        lda r0H
        sta r6H
        jsr FindFile
        txa
        bne @end
        lda dirEntryBuf + OFF_GHDR_PTR
        sta r1L
        lda dirEntryBuf + OFF_GHDR_PTR + 1
        sta r1H
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        bne @end
        lda diskBlkBuf + FONT_ID
        sta fid
        lda diskBlkBuf + FONT_ID + 1
        sta fid+1
@end:   rts

; Remove: entry at taken out, the nAll - at - 1 after it moved up, nAll
; one less; the caller's r6 back by an entry, r7H one more.
Remove: jsr At
        lda r0L                 ; r1 = this entry, r0 = the next
        sta r1L
        clc
        adc #ENTRY
        sta r0L
        lda r0H
        sta r1H
        adc #0
        sta r0H
        lda nAll                ; length: (nAll - at - 1) * 17
        sec
        sbc at
        tax
        lda #0
        sta r2L
        sta r2H
@len:   dex
        beq @move
        clc
        lda r2L
        adc #ENTRY
        sta r2L
        bcc @len
        inc r2H
        bne @len
@move:  lda r2L
        ora r2H
        beq :+
        jsr MoveData
:       dec nAll
        sec
        lda save6
        sbc #ENTRY
        sta save6
        bcs :+
        dec save6+1
:       inc save7+1
        rts

        .endscope

        .segment "OVL124"               ; overlay module 124: the system
        .scope Mod124                   ; fonts' rules for module 116

        jmp Marks                       ; entry 0

; Marks: the entries to take out get the ID MARKED (Once's rules, module
; 116): a drive's font when the drive's fonts are hidden or an installed
; font has its ID; one of E's when a drive's font (not hidden) or an
; installed one has its ID. Entries are marked in order, so a marked
; drive's font no longer counts for E's (an installed font has its ID
; then: E's goes too).
Marks:  ldx #0
@one:   stx at
        cpx nUser
        bcs @sys
        bit fontsOn             ; a drive's font: out when hidden or an
        bvs @mark               ; installed font has its ID
        jsr InF
        bcs @mark
        bcc @next
@sys:   txa                     ; the installed ones (next): kept; E's
        sec                     ; (last): out when a drive's font (not
        sbc nUser               ; hidden) or an installed one has its ID
        cmp nF
        bcc @next
        bit fontsOn
        bvs :+
        ldx #0
        ldy nUser
        jsr Has
        bcs @mark
:       jsr InF
        bcc @next
@mark:  lda at
        asl a
        tay
        lda #<MARKED
        sta fids,y
        lda #>MARKED
        sta fids+1,y
@next:  ldx at
        inx
        cpx nAll
        bcc @one
        rts

; InF: C set when an installed font (nF entries after the drive's) has
; entry at's ID. Has: the same for entries X to Y - 1. An unknown ID
; ($FFFF) never.
InF:    ldx nUser
        lda nUser
        clc
        adc nF
        tay
Has:    sty count
        lda at
        asl a
        tay
        lda fids,y
        sta fid
        lda fids+1,y
        sta fid+1
        and fid
        cmp #$FF
        beq @no
@cmp:   cpx count
        bcs @no
        txa
        asl a
        tay
        lda fids,y
        cmp fid
        bne @next
        lda fids+1,y
        cmp fid+1
        beq @yes
@next:  inx
        bne @cmp
@no:    clc
        rts
@yes:   sec
        rts

        .endscope

; ======================================================================

        .segment "OVL123"               ; overlay module 123: the system
        .scope Mod123                   ; fonts searched (docs/DESIGN.md
                                        ; "System font folder")
        jmp FTypes                      ; entry 0 (module 15, OvFTypes)
        jmp Find                        ; entry 3 (module 15, OvFindFile)

        .include "sysenter.inc"         ; Enter, Leave, Usable (module 81)

; FTypes (module 15's OvFTypes, after drive E's fonts: r6 where that
; search stopped, moved back by the name's offset, r7H the room left):
; the system fonts' (FONTS.DNP, banks FONT_BANK) added after them, when
; loaded and when they can be shown (Here). Destroys A, X, Y, r0-r5.
FTypes: lda r7L
        cmp #FONT
        bne @end
        lda r7H
        beq @end
        jsr Here
        bcs @end
        clc                             ; forward again by the name's
        lda r6L                         ; offset, as module 15 does for E
        adc #OFF_FNAME
        sta r6L
        bcc :+
        inc r6H
:       jsr Show
        jsr FindFTypes
        jsr Gone
@end:   rts

; Find (module 15's OvFindFile, the name not on the drive nor on E):
; sysName in the system fonts; found as a font: X = 0 with dirEntryBuf,
; r1 and r5 as FindFile leaves them (tracks FONT_TRACK+1 on), else X
; not 0.
Find:   jsr Here
        bcs @no
        lda sysName
        sta r6L
        lda sysName+1
        sta r6H
        jsr Show
        jsr FindFile
        jsr Gone
        txa
        bne @end
        lda dirEntryBuf + OFF_GFILE_TYPE
        cmp #FONT
        beq @end
@no:    ldx #FILE_NOT_FOUND
@end:   rts

; Here: C clear when the system fonts can be shown: loaded (fontsOn),
; nothing shown already (Usable, module 81), and not a native drive
; whose own tracks reach FONT_TRACK + 1 (they are its own there).
Here:   sec
        bit fontsOn
        bpl @end
        jsr Usable
        bcs @end
        ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_NATIVE
        bcc @end
        lda drvTracks-8,x
        cmp #FONT_TRACK + 1
@end:   rts

; Show / Gone: Enter / Leave with the system fonts' bank instead of E's.
Show:   lda #FONT_BANK
        sta sysShow
        jmp Enter
Gone:   jsr Leave
        lda #SYSDRV_BANK
        sta sysShow
        rts

        .endscope

