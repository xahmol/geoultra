; GeoUltra Desktop: opening (docs/DESKTOP.md, step D3a). Open: the
; cursor's entry (RETURN, a double click): a folder or drive entered
; (FE_CD), an application started in the desktop's place, a desk
; accessory run (it comes back: the screen drawn again). Up (cursor
; left): the parent folder. Drive (a click on a sidebar line): that
; drive's root. Programs start as gush starts them (gush's prog.s, own
; code): FE_SELECT makes their drive and folder current, GetFile by the
; short name; on drive E (no slot stays E's, FILE_ENGINE.md) an
; application through FE_RUNSYS, a desk accessory through GetFile by
; its name (GetFile falls back to drive E). A document opens with its
; application (Document, step D3b). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, ListRead, ListDraw, Fetch, entryInfo, entryName
        .import cur, count, path, Redraw, RecentAdd, Mount, Neutral, SideArrows
        .export Open, Up, Drive, Into, Document, Back

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
        beq @enter
        cmp #K_UFILE            ; (a disk image: mounted, mount.s)
        bne :+
        jmp Mount
:
        cmp #K_GEOS
        bne @end
        lda entryInfo + FI_GTYPE
        cmp #APPLICATION
        beq Program
        cmp #AUTO_EXEC
        beq Program
        cmp #DESK_ACC
        beq Program
        jmp Document            ; (any other GEOS file: a document)
@end:   rts
@enter: lda #<entryName
        ldx #>entryName
Into:   sta r0L                 ; FE_CD (A/X), then the list read again
        stx r0H
        lda #FE_CD
        jsr FileEngine
        txa
        bne @end
        jsr ListRead
        jsr SideArrows          ; (desktop.s: the open drive's arrow)
        jmp ListDraw
@end:   rts

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
        jsr Neutral             ; (theme.s: GEOS's colours for it)
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
        rts                     ; (not found: nothing)
:       lda #<shortName
        sta r6L
        lda #>shortName
        sta r6H
Start:  jsr Neutral             ; (theme.s: GEOS's colours for it)
        lda #0                  ; GetFile (an application does not come
        sta r0L                 ; back)
        jsr GetFile
        jmp Back                ; (a desk accessory came back)

; Document: entryName (a GEOS file in path that is no program) opened
; with its application, as the deskTop passes a document: the parent's
; permanent name (the document's header at $75; the class is its first
; 12 characters) looked for among the applications of the document's
; folder (FE_SELECT makes it current; FindFTypes with that class), then
; in the root of each other drive A-D; started with ST_LD_DATA, r2 the
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
        lda #<entryName         ; its drive and folder current
        sta r0L
        lda #>entryName
        sta r0H
        lda #<docShort
        sta r1L
        lda #>docShort
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        bne @none
        lda curDrive
        sta docDrive
        jsr FindApp             ; in the document's folder
        bcc Launch
        lda #8                  ; then the other drives' roots
        sta drv
@drive: lda drv
        cmp docDrive
        beq @next
        tax
        lda driveType-8,x
        beq @next
        txa
        jsr SetDevice
        lda guExtTable          ; DirRoot (a drive without folders: an
        clc                     ; error, left: it has only its root)
        adc #DIR_ROOT
        sta @root+1
        lda guExtTable+1
        adc #0
        sta @root+2
@root:  jsr $FFFF
        jsr OpenDisk
        jsr FindApp
        bcc Launch
@next:  inc drv
        lda drv
        cmp #12
        bcc @drive
        lda docDrive            ; none: the document's drive current again
        jsr SetDevice
        jmp OpenDisk
@none:  rts

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
        jsr Neutral             ; (theme.s: GEOS's colours for it)
        lda #ST_LD_DATA
        sta r0L
        jsr GetFile
; Back: the screen drawn again after GetFile came back (a desk accessory
; ended, or the start failed), the menu bar too: Redraw clears it.
Back:   jsr Redraw
        jmp ReDoMenu

; FindApp: an application of class appClass in the current drive's
; current folder: its name to appName, C clear; C set when none.
FindApp:
        lda #<appName
        sta r6L
        lda #>appName
        sta r6H
        lda #APPLICATION
        sta r7L
        lda #1
        sta r7H
        lda #<appClass
        sta r10L
        lda #>appClass
        sta r10H
        jsr FindFTypes
        lda r7H                 ; (0: one found)
        cmp #1
        rts

DiskLo: .byte <DrACurDkNm, <DrBCurDkNm, <DrCCurDkNm, <DrDCurDkNm
DiskHi: .byte >DrACurDkNm, >DrBCurDkNm, >DrCCurDkNm, >DrDCurDkNm

DotDot:         .byte "..", 0

        .segment "DATA"

drivePath:      .byte "/a", 0
docDrive:       .byte 0
drv:            .byte 0

        .segment "BSS"

shortName:      .res 17
docShort:       .res 17
appName:        .res 17
appClass:       .res CLASS_LEN + 1
statInfo:       .res 16
