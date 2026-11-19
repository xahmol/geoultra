; GeoUltra Desktop: the toolbar (docs/design/DESKTOP.md, "Toolbar and
; right-click"; the user's decisions and mock-up of 2026-11-11). A row
; under the menu bar across the full width, its height a view option
; (tbMode, theme.s: TB_TWO two lines, 16 px, framed 16 x 14 buttons;
; TB_ONE one line, 8 px, the icons flat; TB_OFF none). 17 buttons in
; five groups: back, forward, up, root | top, end | view, two panes,
; refresh | new folder, info, select all, copy, paste, delete |
; settings, gush (the user, 2026-11-12: settings in home's place; home
; stays in the go menu). Each button sits
; on two cards (BitmapUp places bitmaps on cards), 16 px apart from x 8
; with 8 px between the groups (the mock-up: 4 and 6, not on cards).
; The drawing is overlay 5 (tooldraw.s); here the presses, the colours
; and the buttons' places (Cards, used by both). Back and forward:
; history.s; info: ctxmenu.s. Own design.

        .include "geos.inc"
        .include "desktop.inc"

        .import topY, cToolbar, Paint, px0, px1, py0, py1, pcol
        .import Up, Into, ListKey, ListEnd, SelAll, ListRead, ListDraw
        .import View, viewMode, NewFolder, Copy, Paste, Delete, FileEngine
        .import HistBack, HistForward, text, Info, Gush, TwoPanes, Settings
homePath        = text          ; (side.s's text buffer: free between actions)
        .export ToolPress, ToolPaint, Cards, Root, Home, Top, Fonts
        .export Refresh

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
; Root: the list of all drives ("/").
Root:   lda #<RootPath
        ldx #>RootPath
        jmp Into
; Fonts (go > system fonts): the installed system fonts, /f (the file
; engine: FONTS.DNP, read-only; "not found" without it). The user's
; choice, 2026-11-19.
Fonts:  lda #<FontsPath
        ldx #>FontsPath
        jmp Into
FontsPath:      .byte "/f", 0
; Home: GeoUltra's folder on the Ultimate (FE_HOME, its last "/"
; dropped); nothing without an Ultimate.
Home:   lda #<homePath          ; FE_HOME ("/USB0/GEOULTRA/"; none
        sta r1L                 ; without an Ultimate: nothing)
        lda #>homePath
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        txa
        beq :+
        rts                     ; (no Ultimate: nothing)
:
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
; Top: the cursor on the first entry (the list's HOME key).
Top:    lda #KEY_HOME           ; (the list's own key)
        jmp ListKey
; ViewNext: the next view: list -> icons -> detailed -> list.
ViewNext:
        ldx viewMode
        inx
        txa
        cmp #VIEW_DETAILED + 1
        bcc :+
        lda #VIEW_LIST
:       jmp View
; Refresh: the folder read again (and sorted, list.s).
; Refresh (the toolbar; view > refresh): the list read
; again (the menu closed first when one is open).
Refresh:
        jsr GotoFirstMenu
        jsr ListRead
        jmp ListDraw
Acts:   .word HistBack-1, HistForward-1, Up-1, Root-1
        .word Top-1, ListEnd-1
        .word ViewNext-1, TwoPanes-1, Refresh-1
        .word NewFolder-1, Info-1, SelAll-1, Copy-1, Paste-1, Delete-1
        .word Settings-1, Gush-1
        .assert (* - Acts) / 2 = TB_BUTTONS, error, "an action per button"

; The buttons' cards: 16 px apart from x 8, 8 px between the groups.
Cards:  .byte 1, 3, 5, 7
        .byte 10, 12            ; top, end
        .byte 15, 17, 19        ; view, two panes, refresh
        .byte 22, 24, 26, 28, 30, 32
        .byte 35, 37            ; settings, gush (the user, 2026-11-12)
RootPath:       .byte "/", 0

        .segment "BSS"

card:           .res 1
