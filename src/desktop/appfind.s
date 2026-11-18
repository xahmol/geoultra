; GeoUltra Desktop: the application for a document, the newest version
; (overlay 6, ovl.s; docs/DESKTOP.md "Opening"; the user's decisions of
; 2026-11-18: an old geoWrite document on a disk with geoWrite 1.x on it
; opened in that 1.x, not in geoWrite 2.1 on another drive, which would
; have converted it; and geoWrite 2.1 lives in a folder, /c/Writing).
; AppFind, from Document (open.s) with the document's drive and folder
; current (FE_SELECT), appClass set (the parent's class: its permanent
; name's first 12 characters) and docDrive: looks in the document's
; folder, then on each drive A-D in its root and in every folder right
; below the root (one level: the root's folders listed with FE_OPENDIR,
; at most FOLD_MAX); each application found has its version read from
; its header (the permanent name's last 4 characters, "V2.1"); the
; highest one wins, the document's folder first among equals, then the
; order searched. The search changes the drives' current folders, so
; Document makes the document's drive and folder current again
; (FE_SELECT) and then calls AppGo, which makes the winner's current (an
; application looks for its document on the document's drive in that
; drive's current folder). GEOS 2.0's deskTop takes the first one found,
; on the document's disk first; the search over folders and the choice
; between versions are GeoUltra's. Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import appName, appClass, docDrive, FileEngine
        .export Ov_AppFind, Ov_AppGo

FindFile        = $C20B         ; (GEOS jump table)
GetFHdrInfo     = $C229
SET_CUR_DIR     = 5             ; the extension table: SetCurDir, r0 = name
DIR_ROOT        = 15            ; DirRoot (as open.s)
VER_AT          = O_GHFNAME + 12 ; the version in a header ("V2.1")
VER_LEN         = 4
NAME_MAX        = 17            ; a short name's room (appName's too)
FOLD_MAX        = 40            ; folders below a root looked in
NONE            = 0             ; bestDrv: nothing found yet
DOC_FOLDER      = $FF           ; subNow, bestSub: the document's folder

        .segment "OV6"

Ov_AppFind = AppFind
Ov_AppGo = AppGo

; AppFind: see above. C clear: one found (best*), C set: none. The
; current drive and folders are left as the search left them. Destroys
; A, X, Y, r0-r15.
AppFind:
        lda #NONE
        sta bestDrv
        jsr FindApp             ; the document's folder
        bcs :+
        lda #DOC_FOLDER
        sta subNow
        lda docDrive
        jsr Consider
:       lda #8                  ; each drive: its root, the folders below
        sta drv
@drive: ldx drv
        lda driveType-8,x
        beq @next
        jsr Folders             ; (its root's folders listed first)
        lda drv
        jsr SetDevice
        jsr Root
        jsr OpenDisk
        lda #0                  ; the root
        sta subNow
        jsr FindApp
        bcs :+
        lda drv
        jsr Consider
:       lda #0
        sta sub
@sub:   lda sub
        cmp nFold
        bcs @next
        jsr Root
        jsr SubName             ; r0 = folder `sub`'s name
        lda #SET_CUR_DIR
        jsr Ext
        txa
        bne @skip
        jsr OpenDisk
        jsr FindApp
        bcs @skip
        ldx sub                 ; (subNow: the folder's number + 1)
        inx
        stx subNow
        lda drv
        jsr Consider
@skip:  inc sub
        bne @sub                ; (always)
@next:  inc drv
        lda drv
        cmp #12
        bcc @drive
        lda bestDrv
        beq @none
        clc
        rts
@none:  sec
        rts

; AppGo (after AppFind found one and Document made the document's drive
; and folder current again): the winner's drive and folder current, its
; name in appName; then SwapDoc. Destroys A, X, Y, r0-r15.
AppGo:  ldx #NAME_MAX - 1
@name:  lda bestName,x
        sta appName,x
        dex
        bpl @name
        lda bestSub
        cmp #DOC_FOLDER         ; the document's folder: current already
        beq @end
        lda bestDrv
        jsr SetDevice
        jsr Root
        lda bestSub
        beq @open               ; (the root)
        lda #<bestFold
        sta r0L
        lda #>bestFold
        sta r0H
        lda #SET_CUR_DIR
        jsr Ext
@open:  jsr OpenDisk
@end:   ; (on into SwapDoc)

; SwapDoc (AppGo's end): a document on drive C or D: drives B and its
; drive swapped (FE_DRVSWAP, drvswap.s; swapped back by EnterDeskTop):
; geoWrite 2.1 looks for a document on drive A or else on B only (the
; user, 2026-11-18). The program's drive is current again under its
; new letter, docDrive B.
SwapDoc:
        lda docDrive
        cmp #10
        bcc @end
        sta r0L
        lda #FE_DRVSWAP
        jsr FileEngine
        txa
        bne @end                ; (not swapped: as it was)
        lda curDrive            ; the program's drive under its new letter
        cmp #9
        bne :+
        lda docDrive            ; (B -> the document's old letter)
        bne @cur                ; (always)
:       cmp docDrive
        bne @cur
        lda #9                  ; (the document's drive -> B)
@cur:   jsr SetDevice
        jsr OpenDisk
        lda #9
        sta docDrive
@end:   rts

; Folders: the folders right below drive drv's root (FE_OPENDIR "/x"),
; their short names into fold (nFold of them, at most FOLD_MAX); none on
; an error or a drive without folders.
Folders:
        lda #0
        sta nFold
        lda drv                 ; "/a" ... "/d"
        clc
        adc #'a' - 8
        sta dirPath + 1
        lda #<dirPath
        sta r0L
        lda #>dirPath
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        cpx #0
        bne @end
        sta handle
@read:  lda nFold               ; the short name straight into its place
        sta sub                 ; in fold (kept only for a folder)
        jsr SubName
        lda r0L
        sta r3L
        lda r0H
        sta r3H
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<longName
        sta r2L
        lda #>longName
        sta r2H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close              ; (FE_END_OF_DIR, or an error)
        lda info + FI_KIND
        cmp #K_FOLDER
        bne @read
        inc nFold
        lda nFold
        cmp #FOLD_MAX
        bcc @read
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@end:   rts

; SubName: r0 = folder `sub`'s short name in fold (sub * NAME_MAX).
; Destroys A, X.
SubName:
        lda #<fold
        sta r0L
        lda #>fold
        sta r0H
        ldx sub
        beq @end
@add:   clc
        lda r0L
        adc #NAME_MAX
        sta r0L
        bcc :+
        inc r0H
:       dex
        bne @add
@end:   rts

; Root: the current drive's root folder (DirRoot; a drive without folders:
; an error, left, it has only its root).
Root:   lda #DIR_ROOT
; Ext: the extension table's entry at offset A. X = its error.
Ext:    clc
        adc guExtTable
        sta @call+1
        lda guExtTable+1
        adc #0
        sta @call+2
@call:  jmp $FFFF

; Consider (A = the drive, subNow = where: DOC_FOLDER, 0 the root, else
; folder subNow - 1 below it): appName, found on the current drive in
; its current folder, read for its version; it becomes the best when
; there is none yet or its version is higher.
Consider:
        sta drvNow
        lda #<appName
        sta r6L
        lda #>appName
        sta r6H
        jsr FindFile
        txa
        bne @end
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr GetFHdrInfo
        txa
        bne @end
        lda bestDrv
        beq @take
        ldx #0                  ; compare with the best, character by
@cmp:   lda fileHeader + VER_AT,x ; character ("V1.3" < "V2.1")
        cmp bestVer,x
        bcc @end
        bne @take
        inx
        cpx #VER_LEN
        bcc @cmp
        rts                     ; (equal: the earlier one stays)
@take:  lda drvNow
        sta bestDrv
        lda subNow
        sta bestSub
        ldx #VER_LEN - 1
@v:     lda fileHeader + VER_AT,x
        sta bestVer,x
        dex
        bpl @v
        ldx #NAME_MAX - 1
@n:     lda appName,x
        sta bestName,x
        dex
        bpl @n
        lda subNow              ; a folder below the root: its name
        beq @end
        cmp #DOC_FOLDER
        beq @end
        lda sub                 ; (sub: that folder's number now)
        jsr SubName
        ldy #NAME_MAX - 1
@f:     lda (r0),y
        sta bestFold,y
        dey
        bpl @f
@end:   rts

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

dirPath:        .byte "/a", 0
drv:            .byte 0
drvNow:         .byte 0
sub:            .byte 0
subNow:         .byte 0
nFold:          .byte 0
handle:         .byte 0
bestDrv:        .byte 0
bestSub:        .byte 0
bestVer:        .res VER_LEN
bestName:       .res NAME_MAX
bestFold:       .res NAME_MAX
info:           .res INFO_LEN
longName:       .res 61
fold:           .res FOLD_MAX * NAME_MAX
