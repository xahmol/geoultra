; GeoUltra Desktop: opening (docs/DESKTOP.md, step D3a). Open: the
; cursor's entry (RETURN, a double click): a folder or drive entered
; (FE_CD), an application started in the desktop's place, a desk
; accessory run (it comes back: the screen drawn again). Up (cursor
; left): the parent folder. Drive (a click on a sidebar line): that
; drive's root. Programs start as gush starts them (gush's prog.s, own
; code): FE_SELECT makes their drive and folder current, GetFile by the
; short name; on drive E (no slot stays E's, FILE_ENGINE.md) an
; application through FE_RUNSYS, a desk accessory through GetFile by
; its name (GetFile falls back to drive E). Documents: step D3b.
; Own code.

        .include "geos.inc"

        .import FileEngine, ListRead, ListDraw, Fetch, entryInfo, entryName
        .import cur, count, path, Redraw
        .export Open, Up, Drive

GetFile         = $C208         ; GEOS jump table

FE_CD           = 11
FE_SELECT       = 21
FE_RUNSYS       = 22
FI_KIND         = 0
FI_GTYPE        = 3
K_DRIVE         = 1
K_FOLDER        = 2
K_GEOS          = 3
K_UDIR          = 6

        .segment "CODE"

; Open: the cursor's entry opened (see above). Nothing for other kinds
; yet.
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
        cmp #K_GEOS
        bne @end
        lda entryInfo + FI_GTYPE
        cmp #APPLICATION
        beq Program
        cmp #AUTO_EXEC
        beq Program
        cmp #DESK_ACC
        beq Program
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
        jmp ListDraw
@end:   rts

; Up: the parent folder (nothing at "/").
Up:     lda path + 1
        beq @end
        lda #<DotDot
        ldx #>DotDot
        jmp Into
@end:   rts

; Drive: A = a drive letter ('a'-'e'): its root.
Drive:  sta drivePath + 1
        lda #<drivePath
        ldx #>drivePath
        jmp Into

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
        lda #<entryName         ; an application: FE_RUNSYS (back only
        sta r0L                 ; with an error)
        lda #>entryName
        sta r0H
        lda #FE_RUNSYS
        jmp FileEngine
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
Start:  lda #0                  ; GetFile (an application does not come
        sta r0L                 ; back)
        jsr GetFile
        jmp Redraw              ; (a desk accessory came back)

DotDot:         .byte "..", 0

        .segment "DATA"

drivePath:      .byte "/a", 0

        .segment "BSS"

shortName:      .res 17
