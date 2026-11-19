; GeoUltra Desktop: opening (docs/design/DESKTOP.md). Open: the
; cursor's entry (RETURN, a double click): a folder or drive entered
; (FE_CD), an application started in the desktop's place, a desk
; accessory run (it comes back: the screen drawn again), a printer
; driver made the printer (inifile.s UsePrinter). Up (cursor
; left): the parent folder. Drive (a click on a sidebar line): that
; drive's root. Programs start as gush starts them (gush's prog.s, own
; code): FE_SELECT makes their drive and folder current, GetFile by the
; short name; on drive E (no slot stays E's, FILE_ENGINE.md) an
; application through FE_RUNSYS, a desk accessory through GetFile by
; its name (GetFile falls back to drive E). A document opens with its
; application (Document). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, ListRead, ListDraw, Fetch, entryInfo, entryName
        .import cur, count, path, Redraw, RecentAdd, Mount, Leave, SideArrows
        .export Open, Up, Drive, Into, Document, Back
        .import HistAdd, IsImage, Error, UsePrinter, PrnUlt, AppFind, AppGo, OpenHere, Fonts
        .export appName, appClass, docDrive, docShort, RunE

DIR_ROOT        = 15            ; DirRoot: guExtTable + 15
ST_LD_DATA      = $80
O_GHP_FNAME     = $75           ; a document's parent application's name
CLASS_LEN       = 12

        .segment "CODE"

; Open: the cursor's entry opened (see above); a file on the Ultimate
; that is a disk image is mounted (mount.s). Nothing for other kinds.
Open:   lda count               ; (an empty folder: nothing)
        ora count+1
        beq @end
        lda cur
        ldx cur+1
        jsr Fetch
        lda entryInfo + FI_KIND
        cmp #K_FOLDER
        beq @enter
        cmp #K_UDIR
        beq @enter
        cmp #K_DRIVE
        bne :+
        lda path + 1            ; a drive below "/": the system fonts'
        beq @enter              ; entry in drive E (list.s ReadList)
        jmp Fonts               ; (toolbar.s: /f)
:       cmp #K_UFILE            ; a disk image: gone into like a folder
        bne @geos               ; (the user, 2026-11-13; the engine's
        jsr IsImage             ; engineimg.s); another file: Mount says
        bcs @mount              ; it is not opened here
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        lda #FE_CD
        jsr FileEngine
        txa
        bne @noimg
        jmp Entered
@noimg: cpx #INSUFF_SPACE       ; (here: the REU's room, not a drive's)
        bne @err
        ldx #ERR_REU
@err:   jmp Error               ; (the image's name on its first line)
@mount: jmp Mount
@geos:  cmp #K_GEOS
        bne @end
        lda entryInfo + FI_GTYPE
        cmp #APPLICATION
        beq Program
        cmp #AUTO_EXEC
        beq Program
        cmp #DESK_ACC
        beq Program
        cmp #PRINTER_FILE       ; a printer driver: the printer from now
        bne :+                  ; (inifile.s; as GEOS 2.0's deskTop), the
        jsr UsePrinter          ; Ultimate's printer set up for it
        jmp PrnUlt              ; (prnult.s)
:       jmp Document            ; (any other GEOS file: a document)
@end:   rts
@enter: lda #<entryName
        ldx #>entryName
Into:   sta r0L                 ; FE_CD (A/X), then the list read again
        stx r0H
        lda #FE_CD
        jsr FileEngine
        txa
        bne NoCd
Entered:                        ; (Open: a disk image gone into)
        jsr ListRead
        jsr HistAdd             ; (history.s: the toolbar's back, forward)
        jsr SideArrows          ; (desktop.s: the open drive's arrow)
        jmp ListDraw
NoCd:   rts

; Up: the parent folder (nothing at "/").
Up:     lda path + 1
        beq @end
        lda #<DotDot
        ldx #>DotDot
        jmp Into
@end:   rts

; Drive: A = a sidebar line's code: a drive letter ('a'-'e', its root)
; or an Ultimate root ('0' usb0, '1' usb1, 's' sd).
Drive:  cmp #'0'
        beq @usb0
        cmp #'1'
        beq @usb1
        cmp #'s'
        beq @sd
        sta drivePath + 1
        lda #<drivePath
        ldx #>drivePath
        jmp Into
@usb0:  lda #<Usb0
        ldx #>Usb0
        jmp Into
@usb1:  lda #<Usb1
        ldx #>Usb1
        jmp Into
@sd:    lda #<Sd
        ldx #>Sd
        jmp Into

Usb0:   .byte "/usb0", 0
Usb1:   .byte "/usb1", 0
Sd:     .byte "/sd", 0

; Program: entryName (in path) started (see above); a desk accessory
; comes back: the screen drawn again.
Program:
        lda path + 1            ; on drive E ("/e" or "/e/...")?
        cmp #'e'
        bne @select
        lda path + 2
        beq @e
        cmp #'/'
        bne @select
@e:     lda entryInfo + FI_GTYPE
        cmp #DESK_ACC
        beq @byName
        jsr Leave               ; (desktop.s: the panes kept, GEOS's colours)
        lda #<entryName         ; an application: FE_RUNSYS (back only
        sta r0L                 ; with an error)
        lda #>entryName
        sta r0H
        lda #FE_RUNSYS
        jsr FileEngine
        jmp Back
@byName:
        lda #<entryName         ; (E's names are short names)
        sta r6L
        lda #>entryName
        sta r6H
        jmp Start
@select:
        lda #<entryName         ; its drive and folder current, its
        sta r0L                 ; short name to shortName
        lda #>entryName
        sta r0H
        lda #<shortName
        sta r1L
        lda #>shortName
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        beq :+
        jmp InImage             ; (not found: nothing)
:       lda #<shortName
        sta r6L
        lda #>shortName
        sta r6H
Start:  jsr Leave               ; (desktop.s: the panes kept, GEOS's colours)
        lda #0                  ; GetFile (an application does not come
        sta r0L                 ; back)
        jsr GetFile
        jmp Back                ; (a desk accessory came back)

; InImage: X = FE_SELECT's error: inside a disk image gone into (its
; slot is lent for one engine call only: FE_NOT_SUPPORTED) the message
; that it must be mounted; else nothing (not found).
InImage:
        cpx #FE_NOT_SUPPORTED
        bne @end
        jmp OpenHere            ; (side.s: offered for mounting, then
@end:   rts                     ; opened from its drive)

; Document: entryName (a GEOS file in path that is no program) opened
; with its application, as the deskTop passes a document: the parent's
; permanent name (the document's header at $75; the class is its first
; 12 characters) looked for among the applications of the document's
; folder (FE_SELECT makes it current) and on each drive A-D in its root
; and the folders right below it, the newest version taken (appfind.s,
; overlay 6; the user, 2026-11-18); started with ST_LD_DATA, r2 the
; document disk's name, r3 the document's name. An application finds
; its document on its own drive in its own folder, or by the disk's
; name on another drive (geoWrite 2.1's findDocDevice, mist64/geowrite,
; read for this behaviour only). Nothing when none is found. The document
; goes to the top of the recent ones (side.s) first.
Document:
        lda #<entryName         ; its header: the parent's name
        sta r0L
        lda #>entryName
        sta r0H
        lda #<statInfo
        sta r1L
        lda #>statInfo
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        beq :+
        rts                     ; (not there: nothing)
:       ldy #CLASS_LEN - 1
@class: lda fileHeader + O_GHP_FNAME,y
        sta appClass,y
        dey
        bpl @class
        lda #0
        sta appClass + CLASS_LEN
        lda appClass            ; (no parent named: nothing)
        beq @none
        jsr RecentAdd           ; (side.s: to the recent documents)
        jsr Select              ; its drive and folder current
        txa
        beq :+
        jmp InImage
:       lda curDrive
        sta docDrive
        jsr AppFind             ; (appfind.s, overlay 6: the newest
        bcs @none               ; version on any drive, folders too)
        jsr Select              ; the document's drive and folder again
        jsr AppGo               ; (the search moved them), then the
        jmp Launch              ; winner's
@none:  jsr Select              ; (none: as the document left them)
        rts

; Select: entryName's drive and folder current, its short name in
; docShort (FE_SELECT). X = its error.
Select: lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        lda #<docShort
        sta r1L
        lda #>docShort
        sta r1H
        lda #FE_SELECT
        jmp FileEngine

; Launch: appName (on the current drive, in its current folder) started
; with docShort of docDrive (an application does not come back; an error
; leaves the desktop drawn again).
Launch: ldx docDrive
        lda DiskLo-8,x
        sta r2L
        lda DiskHi-8,x
        sta r2H
        lda #<docShort
        sta r3L
        lda #>docShort
        sta r3H
        lda #<appName
        sta r6L
        lda #>appName
        sta r6H
        jsr Leave               ; (desktop.s: the panes kept, GEOS's colours)
        lda #ST_LD_DATA
        sta r0L
        jsr GetFile
; Back: the screen drawn again after GetFile came back (a desk accessory
; ended, or the start failed), the menu bar too: Redraw clears it.
Back:   jsr Redraw
        jmp ReDoMenu

; RunE (ctxmenu.s MakePS): appName on drive E started with docShort of
; docDrive (FE_RUNDOC), as Launch for an application on E; resident,
; as Leave calls an overlay. Back only after an error, the desktop drawn
; again; C clear.
RunE:   jsr Leave
        lda #<appName
        sta r0L
        lda #>appName
        sta r0H
        lda #<docShort
        sta r1L
        lda #>docShort
        sta r1H
        ldx docDrive
        lda DiskLo-8,x
        sta r2L
        lda DiskHi-8,x
        sta r2H
        lda #FE_RUNDOC
        jsr FileEngine
        jsr Back
        clc
        rts

DiskLo: .byte <DrACurDkNm, <DrBCurDkNm, <DrCCurDkNm, <DrDCurDkNm
DiskHi: .byte >DrACurDkNm, >DrBCurDkNm, >DrCCurDkNm, >DrDCurDkNm

DotDot:         .byte "..", 0

        .segment "DATA"

drivePath:      .byte "/a", 0
docDrive:       .byte 0

        .segment "BSS"

shortName:      .res 17
docShort:       .res 17
appName:        .res 17
appClass:       .res CLASS_LEN + 1
statInfo:       .res 16
