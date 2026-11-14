; GeoUltra Desktop: two panes (docs/DESKTOP.md, "Two panes": the
; user's decisions of 2026-11-12). Side by side, 160 pixels
; each, the sidebar hidden; each pane its own folder, list and
; selection (list.s keeps the active pane's state, SwapPane exchanges it
; with the other's in the REU). The panes show the list view (the
; detailed columns do not fit; the view chosen before comes back when
; two panes go off) and no title bars (the user, 2026-11-12): the path
; lines name the folders, the active pane's inverted. view > two panes,
; C=P and the toolbar
; switch them on and off (SETTINGS.INI's panes= keeps it: PanesSave,
; PanesOn at the start); a click in a pane or C=SPACE makes it the
; active one. CopyOther and MoveOther (C=T, C=M, the menus and a drop on
; the other pane, desktop.s DropDo) paste into the other pane's folder.
; Core code: Draw, Press, Key and the menus call it. Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import SwapPane, ListRead, ListDraw, FileEngine, path, sortPending
        .import SortList, Derive, viewMode, tTitle, listL, stripL, listR
        .import paneR, iconCard, nameX, tIcons, Back, FreeRead
        .export SetGeom, DrawPanes, PaneSwitch, TwoPanes, PaneAt, panes, active
        .export paneDim, CopyOther, MoveOther, CdPath, PanesOn
        .import PanesSave
        .import Copy, Cut, Paste


        .segment "CODE"

; TwoPanes (view > two panes, C=P, the toolbar): two panes on or off;
; the screen drawn again (Back: and the menus).
TwoPanes:
        jsr GotoFirstMenu
        lda panes
        bne @off
        jsr PanesOn
        beq @draw               ; (PanesOn ends with A = 0)
@off:   lda #0
        sta panes
        lda viewSave            ; the view and the title bar from before
        sta viewMode
        lda titleSave
        sta tTitle
@draw:  jsr PanesSave           ; (SETTINGS.INI's panes=; overlay 4)
        jsr Derive
        jmp Back

; PanesOn (TwoPanes; side.s SideLoad for "panes=2"): two panes on, not
; drawn: the list view in the panes, no title bars (the path lines name
; the folders; the active one's inverted), the left pane active; the
; caller runs Derive.
PanesOn:
        inc panes               ; on: the list view in the panes, no title
        lda viewMode            ; bars (the path lines name the folders;
        sta viewSave            ; the active one's inverted)
        lda #VIEW_LIST
        sta viewMode
        lda tTitle
        sta titleSave
        lda #ST_NONE
        sta tTitle
        lda #0
        sta active
        rts

; PaneSwitch (C=SPACE; Press, a click in the other pane): the other pane
; made the active one (its folder the file engine's current one), both
; drawn again.
PaneSwitch:
        lda panes
        beq @end
        lda #0                  ; (no double click across the panes: the
        sta dblClickCount       ; entry numbers are the other pane's)
        jsr Other
        jsr CdPath
        jsr FreeRead            ; (list.s: the status line's free space is
                                ; the active pane's drive's)
        jsr Other               ; the one that was active: drawn plainly
        jsr Plain
        jsr Other
        jmp ListDraw
@end:   rts

; DrawPanes (desktop.s, Draw): both panes read and drawn: the active
; one's folder taken from the file engine first (ListRead: FE_PWD; a
; desk accessory such as geoFolder may have chosen another; the user's
; test 2026-11-13), then the other one (read, sorted, drawn plainly),
; then the active one (read; list.s sorts and draws it from MainLoop,
; SortNow).
DrawPanes:
        jsr ListRead
        jsr Other
        jsr CdPath
        jsr ListRead
        jsr Sorted
        jsr Plain
        jsr Other
        jsr CdPath
        jsr ListRead
        jmp ListDraw            ; (waits for the sort: SortNow draws it)

; Sorted: the pane in list.s sorted now if it was read since (SortNow,
; from MainLoop, only sorts the active pane; this one is about to be the
; other).
Sorted: lda sortPending
        beq @end
        lda #0
        sta sortPending
        jmp SortList
@end:   rts

; Plain: the pane in list.s drawn as the inactive one (its path line
; not inverted: list.s, PaneMark).
Plain:  inc paneDim
        jsr ListDraw
        dec paneDim
        rts

; Other: the other pane's state into list.s (SwapPane), its geometry.
Other:  jsr SwapPane
        lda active
        eor #1
        sta active
        jmp SetGeom

; CdPath: the file engine's current folder = path (the pane's).
CdPath: lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FE_CD
        jmp FileEngine

; SetGeom (theme.s, Derive; Other): with two panes, the list's edges
; for the active pane (listL, stripL, listR, paneR, the icon column and
; the names' x); with one list, the strip's and edges' full-width
; values (listL is Derive's: beside the sidebar).
SetGeom:
        ldx #2                  ; (one list: entry 2)
        lda panes
        beq :+
        ldx active
        lda PaneL,x
        sta listL
:       lda StripLo,x
        sta stripL
        lda StripHi,x
        sta stripL+1
        lda stripL              ; listR = stripL - 3, paneR = stripL + 7
        sec
        sbc #3
        sta listR
        lda stripL+1
        sbc #0
        sta listR+1
        lda stripL
        clc
        adc #7
        sta paneR
        lda stripL+1
        adc #0
        sta paneR+1
        lda listL               ; the icon column and the names (as Derive)
        lsr a
        lsr a
        lsr a
        clc
        adc #1
        sta iconCard
        ldy #5
        lda tIcons
        bne :+
        ldy #18
:       tya
        clc
        adc listL
        sta nameX
        rts

; CopyOther, MoveOther (file menu, context menu, C=T, C=M): the
; selection copied or moved into the other pane's folder: copied or cut
; to the clipboard, pasted with the other pane active, then back and
; this pane read again (a move took the entries away). Nothing with one
; list.
CopyOther:
        lda #0
        beq ToOther
MoveOther:
        lda #1
ToOther:
        ldx panes
        beq @end
        tax
        bne @cut
        jsr Copy
        jmp @paste
@cut:   jsr Cut
@paste: jsr PaneSwitch          ; (the other pane active: pasted there)
        jsr Paste
        jsr Sorted              ; (it stays in view: sorted now)
        jsr PaneSwitch          ; (back)
        jsr ListRead
        jmp ListDraw
@end:   rts

; PaneAt: A = the pane under the pointer (0 left, 1 right).
PaneAt: lda mouseXPos+1
        bne @right
        lda mouseXPos
        cmp #PANE_W
        bcs @right
        lda #0
        rts
@right: lda #1
        rts

PaneL:  .byte 0, PANE_W
StripLo:.byte <(PANE_W - 8), <(2 * PANE_W - 8), <STRIP_LEFT
StripHi:.byte >(PANE_W - 8), >(2 * PANE_W - 8), >STRIP_LEFT

        .segment "DATA"

panes:          .byte 0         ; 1: two panes
active:         .byte 0         ; the active pane: 0 left, 1 right
viewSave:       .byte 0         ; the view before two panes
titleSave:      .byte 0         ; the title bar's style before two panes
paneDim:        .byte 0         ; 1 while the inactive pane is drawn
