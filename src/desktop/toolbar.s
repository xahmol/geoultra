; GeoUltra Desktop: the toolbar (docs/DESKTOP.md, "Toolbar and
; right-click"; the user's decisions and mock-up of 2026-11-11). A row
; under the menu bar across the full width, its height a view option
; (tbMode, theme.s: TB_TWO two lines, 16 px, framed 16 x 14 buttons;
; TB_ONE one line, 8 px, the icons flat; TB_OFF none). 15 buttons in
; four groups: back, forward, up, root, home | top, end | view, refresh
; | new folder, info, select all, copy, paste, delete. Each button sits
; on two cards (BitmapUp places bitmaps on cards), 16 px apart from x 8
; with 8 px between the groups (the mock-up: 4 and 6, not on cards).
; The drawing is overlay 5 (tooldraw.s); here the presses, the colours
; and the buttons' places (Cards, used by both). Back and forward:
; history.s. Info does nothing yet (the Info dialog comes with the
; context menu). Own design.

        .include "geos.inc"
        .include "desktop.inc"

        .import tbMode, topY, cToolbar, Paint, px0, px1, py0, py1, pcol
        .import Up, Into, ListKey, ListEnd, SelAll, ListRead, ListDraw
        .import View, viewMode, NewFolder, Copy, Paste, Delete, FileEngine
        .import HistBack, HistForward
        .export ToolPress, ToolPaint, Cards

        .segment "CODE"

; ToolPaint: the toolbar's cells in the theme's toolbar colours
; (cToolbar; theme.s's PaintAll).
ToolPaint:
        lda topY
        lsr a
        lsr a
        lsr a
        tax
        dex
        cpx #TB_Y / 8           ; (off: no rows)
        bcc @end
        stx py1
        lda #TB_Y / 8
        sta py0
        lda #0
        sta px0
        lda #39
        sta px1
        lda cToolbar
        sta pcol
        jmp Paint
@end:   rts

; ToolPress: C clear when the press (mouseXPos, mouseYPos) was on the
; toolbar's row (a button's action done, or nothing between buttons);
; C set when it was below it.
ToolPress:
        lda mouseYPos
        cmp topY
        bcc :+
        rts                     ; (C set: below the toolbar)
:       lda mouseXPos+1         ; the card: x / 8
        lsr a
        lda mouseXPos
        ror a
        lsr a
        lsr a
        sta card
        ldx #TB_BUTTONS - 1
@b:     lda card
        sec
        sbc Cards,x
        cmp #2                  ; (on its two cards; left of it: large)
        bcc @hit
        dex
        bpl @b
        clc                     ; (between buttons: nothing)
        rts
@hit:   txa
        asl a
        tax
        lda Acts+1,x
        pha
        lda Acts,x
        pha
        rts                     ; (the action's rts: back with C as left)

; The buttons' actions (C on return does not matter: Press ends).
Root:   lda #<RootPath
        ldx #>RootPath
        jmp Into
Home:   lda #<homePath          ; FE_HOME ("/USB0/GEOULTRA/"; none
        sta r1L                 ; without an Ultimate: nothing)
        lda #>homePath
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        txa
        bne Nothing
        ldy #0                  ; its last "/" dropped
@end:   lda homePath,y
        beq :+
        iny
        bne @end
:       dey
        beq :+                  ; ("/" alone stays)
        lda homePath,y
        cmp #'/'
        bne :+
        lda #0
        sta homePath,y
:       lda #<homePath
        ldx #>homePath
        jmp Into
Top:    lda #KEY_HOME           ; (the list's own key)
        jmp ListKey
ViewNext:                       ; list -> detailed -> list (icons: a
        lda #VIEW_DETAILED      ; later step)
        ldx viewMode
        cpx #VIEW_LIST
        beq :+
        lda #VIEW_LIST
:       jmp View
Refresh:
        jsr ListRead
        jmp ListDraw
Nothing:
        rts

Acts:   .word HistBack-1, HistForward-1, Up-1, Root-1, Home-1
        .word Top-1, ListEnd-1
        .word ViewNext-1, Refresh-1
        .word NewFolder-1, Nothing-1, SelAll-1, Copy-1, Paste-1, Delete-1
        .assert (* - Acts) / 2 = TB_BUTTONS, error, "an action per button"

; The buttons' cards: 16 px apart from x 8, 8 px between the groups.
Cards:  .byte 1, 3, 5, 7, 9
        .byte 12, 14
        .byte 17, 19
        .byte 22, 24, 26, 28, 30, 32
RootPath:       .byte "/", 0

        .segment "BSS"

card:           .res 1
homePath:       .res 64
