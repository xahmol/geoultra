; GeoUltra Desktop: the list's mouse and key handling (overlay 8,
; ovl.s; moved out of list.s on 2026-11-12 to give the core room for two
; panes). ListPress (a press in the list: the path line, a row or cell,
; the scroll strip), ListKey (the cursor keys, RETURN, cursor left) and
; their helpers. Opening an entry is the core's (Open may start a
; program or mount an image, overlay 3: an overlay calls no other):
; here openReq is set, and desktop.s's Press and Key open it after the
; call. Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import EntryUnder, pick, last, Modifiers, mods, ClearSel, Select, cur
        .import ListDraw, count, ThumbRows, top, path, Follow, Up, Into, step
        .import rows, listL, listTop, pathY, bottom, topY, stY0, stY1, tScroll
        .import openReq, text, TextWidth, rowH, IsSelected, stripL, sel
        .import panes, active, PaneAt, dropReq, dropAt, Fetch, entryInfo, IconFor, Icons
        .export Ov_ListPress, Ov_ListKey, Ov_ListEnd, Ov_SelAll
Ov_ListEnd = ListEnd
Ov_SelAll = SelAll
DrawSprite      = $C1C6         ; GEOS jump table
PosSprite       = $C1CF
EnablSprite     = $C1D2
DisablSprite    = $C1D5
DRAG_SPR        = 2             ; (0 the pointer, 1 the text cursor)
DRAG_MIN        = 5             ; pixels moved before a press is a drag
cutPath = text                  ; (list.s's PathPress buffer: side.s's text)
Ov_ListPress = ListPress
Ov_ListKey = ListKey

        .segment "OV8"

; PathPress (ListPress: a press on the path line): the folder whose part
; of the path the pointer is on (the system font's widths from the
; line's start); the last part, the current folder, does nothing. C
; clear (the list's).
PathPress:
        lda listL               ; (Text's x for the path)
        clc
        adc #4
        sta numL
        lda #0
        sta numH
        tay
@ch:    lda path,y
        beq @done               ; (past the end: nothing)
        sty tmp
        jsr GetCharWidth
        clc
        adc numL
        sta numL
        bcc :+
        inc numH
:       ldy tmp
        lda mouseXPos+1         ; the pointer before this character's end?
        cmp numH
        bcc @found
        bne @next
        lda mouseXPos
        cmp numL
        bcc @found
@next:  iny
        bne @ch
@found: cpy #0                  ; its part's end: the next "/" (the root's
        bne @end                ; "/" ends at 1)
        iny
        bne @cut
@end:   lda path,y
        beq @done               ; (the last part: the current folder)
        cmp #'/'
        beq @cut
        iny
        bne @end
@cut:   tya
        tax
        ldy #0
@copy:  lda path,y
        sta cutPath,y
        iny
        dex
        bne @copy
        lda #0
        sta cutPath,y
        lda #<cutPath
        ldx #>cutPath
        jsr Into
@done:  clc
        rts


; ListPress (a mouse press right of the sidebar; desktop.s). C clear
; when it was the list's: the path line, a row, the scroll strip (its
; arrows a line, above or below the thumb a page).
ListPress:
        lda mouseXPos+1
        bne :+
        lda mouseXPos
        cmp listL
        bcc @out                ; (the sidebar)
:       lda mouseYPos
        cmp topY
        bcc @out
        cmp listTop
        bcs @below
        lda pathY               ; above the rows: the path line, else the
        sec                     ; title bar (nothing)
        sbc #8
        cmp mouseYPos
        bcs @title
        jmp PathPress
@title: clc
        rts
@below: lda bottom              ; (below it: the status line, not ours)
        cmp mouseYPos
        bcs :+
@out:   sec
        rts
:       lda mouseXPos           ; the strip? (x >= stripL)
        cmp stripL
        lda mouseXPos+1
        sbc stripL+1
        bcc @list
        jmp @strip
@list:  jsr EntryUnder
        bcs @done               ; (no entry there)
        sta pick
        stx pick+1
        jsr Drag                ; (a selected entry dragged: C clear)
        bcs :+
        clc
        rts
:       jsr Double              ; (the same entry clicked again in time)
        bcs @open
        jsr Modifiers
        lda mods
        and #MOD_CBM
        bne @toggle
        lda mods
        and #MOD_SHIFT
        bne @range
        jsr ClearSel            ; alone
        lda pick
        ldx pick+1
        ldy #1
        jsr Select
        jmp @cursor
@toggle:
        lda pick
        ldx pick+1
        ldy #2
        jsr Select
        jmp @cursor
@range: jsr Range               ; cursor .. pick selected
@cursor:
        lda pick
        sta cur
        lda pick+1
        sta cur+1
@done:  jsr ListDraw
@none:  clc
        rts
@open:  lda pick                ; a double click: the entry opened (by
        sta cur                 ; the core: Open may start a program or
        lda pick+1              ; mount, overlay 3; desktop.s, Press)
        sta cur+1
        inc openReq
        clc
        rts
@strip: lda tScroll             ; the arrows (their boxes: 9 lines)
        bne @page
        lda mouseYPos
        sec
        sbc stY0
        cmp #9
        bcs :+
        jsr LineUp
        jmp @redraw
:       lda stY1
        sec
        sbc mouseYPos
        cmp #9
        bcs @page
        jsr LineDown
        jmp @redraw
@page:  lda count               ; above or below the thumb: a page
        ora count+1
        beq @none
        lda mouseYPos
        pha
        jsr ThumbRows
        pla
        cmp r2L
        bcc @up
        jsr PageDown
        jmp @redraw
@up:    jsr PageUp
@redraw:
        jsr ListDraw
        clc
        rts


; LineUp, LineDown: top a row up or down (within the table; step
; entries: one, or the icon view's row of cells).
LineUp: lda top
        sec
        sbc step
        tax
        lda top+1
        sbc #0
        bcs :+
        lda #0                  ; (above the first: the first)
        tax
:       stx top
        sta top+1
        rts
LineDown:
        lda top                 ; top + rows < count: a step on
        clc
        adc rows
        tax
        lda top+1
        adc #0
        cmp count+1
        bne :+
        cpx count
:       bcs @end
        lda top
        clc
        adc step
        sta top
        bcc @end
        inc top+1
@end:   rts


; Double: C set when pick is the entry clicked last and GEOS's double-
; click count still runs; else that count started for this click.
Double: lda dblClickCount
        beq @new
        lda pick
        cmp last
        bne @new
        lda pick+1
        cmp last+1
        bne @new
        lda #0
        sta dblClickCount
        sec
        rts
@new:   lda pick
        sta last
        lda pick+1
        sta last+1
        lda #CLICK_COUNT
        sta dblClickCount
        clc
        rts


; Range: entries cur to pick (either way round) selected.
Range:  lda cur
        sta lo
        lda cur+1
        sta lo+1
        lda pick
        sta hi
        lda pick+1
        sta hi+1
        lda hi+1                ; lo <= hi
        cmp lo+1
        bne :+
        lda hi
        cmp lo
:       bcs @loop
        ldx lo                  ; (swapped)
        lda hi
        sta lo
        stx hi
        ldx lo+1
        lda hi+1
        sta lo+1
        stx hi+1
@loop:  lda lo
        ldx lo+1
        ldy #1
        jsr Select
        lda lo
        cmp hi
        bne :+
        lda lo+1
        cmp hi+1
        beq @end
:       inc lo
        bne @loop
        inc lo+1
        bne @loop
@end:   rts


; PageUp, PageDown: top a screen up or down (within the table).
PageUp: lda top
        sec
        sbc rows
        tax
        lda top+1
        sbc #0
        bcs :+
        lda #0
        tax
:       stx top
        sta top+1
        rts
PageDown:
        lda top
        clc
        adc rows
        tax
        lda top+1
        adc #0
        cmp count+1             ; still within the table?
        bne :+
        cpx count
:       bcs @end
        stx top
        sta top+1
@end:   rts


; ListKey: A = a key (keyVector, desktop.s). C clear when it was the
; list's.
ListKey:
        sta key
        and #$7F
        cmp #KEY_DOWN
        beq @down
        cmp #KEY_UP
        beq @up
        cmp #KEY_HOME
        beq @home
        cmp #CR
        beq @open
        cmp #KEY_LEFT
        beq @parent
        sec
        rts
@open:  inc openReq             ; (opened by the core: desktop.s, Key)
        clc
        rts
@parent:
        jsr Up
        clc
        rts
@home:  lda #0
        sta cur
        sta cur+1
        sta top
        sta top+1
        jmp @moved
@down:  lda cur                 ; (not past the last)
        clc
        adc #1
        tax
        lda cur+1
        adc #0
        cmp count+1
        bne :+
        cpx count
:       bcs @show
        stx cur
        sta cur+1
        jmp @moved
@up:    lda cur
        ora cur+1
        beq @show
        lda cur
        bne :+
        dec cur+1
:       dec cur
@moved: bit key                 ; C= held: the selection extended, else
        bmi @extend             ; only the cursor's entry
        jsr ClearSel
@extend:
        lda cur
        ldx cur+1
        ldy #1
        jsr Select
        jsr Follow
@show:  jsr ListDraw
        clc
        rts

; --- Drag and drop (two panes P6; the user's decisions of 2026-11-12)

; Drag (ListPress, a press on entry pick): when pick is selected and the
; pointer moves DRAG_MIN pixels with the button held, the selection is
; dragged (its icon as sprite DRAG_SPR) until the button is released;
; dropped on the other pane, or on a folder of this list that is not
; selected, the core copies or moves it there (dropReq, desktop.s
; DropDo: the actions are overlay 2's): the same drive moves, another
; copies, C= held the other way. C set: no drag (a click: on as usual):
; an entry not selected, the second press of a double click, a release
; before the move, or a press held still for about two seconds (the wait
; keeps MainLoop, the clock and processes, from running).
Drag:   lda pick
        ldx pick+1
        jsr IsSelected
        beq @click
        lda dblClickCount       ; (the same entry pressed again in time)
        beq :+
        lda pick
        cmp last
        bne :+
        lda pick+1
        cmp last+1
        beq @click
:       lda mouseXPos
        sta dx
        lda mouseYPos
        sta dy
        lda #0
        sta waitL
        sta waitH
@wait:  inc waitL               ; (65536 rounds: about two seconds)
        bne :+
        inc waitH
        beq @click
:       lda mouseData           ; released before it moved: a click
        bpl :+
@click: sec
        rts
:       lda mouseYPos
        sec
        sbc dy
        jsr Far
        bcs @drag
        lda mouseXPos
        sec
        sbc dx
        jsr Far
        bcc @wait
@drag:  jsr Sprite              ; the entry's icon at the pointer
@track: lda #DRAG_SPR
        sta r3L
        lda mouseXPos
        clc
        adc #8
        sta r4L
        lda mouseXPos+1
        adc #0
        sta r4H
        lda mouseYPos
        clc
        adc #8
        sta r5L
        jsr PosSprite
        lda mouseData
        bpl @track              ; (held)
        lda #DRAG_SPR
        sta r3L
        jsr DisablSprite
        jsr Modifiers           ; (C= held: the other way)
        lda mods
        and #MOD_CBM
        sta flip
        lda panes               ; the other pane?
        beq @entry
        jsr PaneAt
        cmp active
        beq @entry
        jsr SameDrive           ; (Z set: the same drive: a move)
        beq :+
        lda #DROP_OTHER_COPY
        bne @req
:       lda #DROP_OTHER_MOVE
        bne @req
@entry: jsr EntryUnder          ; a folder of this list, not selected?
        bcs @none
        sta dropAt
        stx dropAt+1
        jsr IsSelected
        bne @none
        lda dropAt
        ldx dropAt+1
        jsr Fetch
        lda entryInfo + FI_KIND
        cmp #K_FOLDER
        beq :+
        cmp #K_UDIR
        bne @none
:       lda #DROP_IN_MOVE       ; (the same list: the same drive)
@req:   ldx flip                ; C=: the other way (move <-> copy)
        beq :+
        eor #1
:       sta dropReq
@none:  clc
        rts

; Far: C set when A (a signed difference) is DRAG_MIN or more away.
Far:    bpl :+
        eor #$FF
        clc
        adc #1
:       cmp #DRAG_MIN
        rts

; Sprite: the dragged entry's 8 x 8 icon (icons.s) as sprite DRAG_SPR,
; enabled.
Sprite: lda pick
        ldx pick+1
        jsr Fetch
        jsr IconFor             ; A = its icon
        sta dx                  ; r4 = its rows: Icons + A * 9 + 1
        asl a
        asl a
        asl a
        adc dx
        adc #<(Icons + 1)
        sta r4L
        lda #>(Icons + 1)
        adc #0
        sta r4H
        ldx #63                 ; the image: 8 rows in its first column
        lda #0
@clr:   sta sprite,x
        dex
        bpl @clr
        ldy #7
@row:   lda (r4),y
        pha
        tya
        sta dy                  ; (row * 3)
        asl a
        adc dy
        tax
        pla
        sta sprite,x
        dey
        bpl @row
        lda #DRAG_SPR
        sta r3L
        lda #<sprite
        sta r4L
        lda #>sprite
        sta r4H
        jsr DrawSprite
        lda #DRAG_SPR
        sta r3L
        jmp EnablSprite

; SameDrive: Z set when the other pane's path is on the same drive as
; path (their first parts: "/a", "/usb0" ...). The other pane's path:
; its first 16 bytes from the REU (list.s SwapPane's first part).
SameDrive:
        lda #<other
        sta r0L
        lda #>other
        sta r0H
        lda #0
        sta r1L
        sta r2H
        lda #PANE_PAGE
        sta r1H
        lda #16
        sta r2L
        lda #PANE_BANK
        sta r3L
        jsr FetchRAM
        ldy #0
@ch:    iny
        lda path,y              ; path's first part ended (0 or "/")?
        beq @pend
        cmp #'/'
        beq @pend
        cmp other,y             ; no: the same character in the other's
        beq @ch
@diff:  lda #1                  ; (Z clear: another drive)
        rts
@pend:  lda other,y             ; yes: the other's must end here too
        beq :+
        cmp #'/'
        bne @diff
:       lda #0                  ; (Z set: the same drive)
        rts

; --- ListEnd and SelAll (moved from list.s, 2026-11-12: room in the core)

; ListEnd (the toolbar's end button): the cursor on the last entry,
; only it selected, the list drawn.
ListEnd:
        lda count
        ora count+1
        beq @end
        lda count
        sec
        sbc #1
        sta cur
        lda count+1
        sbc #0
        sta cur+1
        jsr ClearSel
        lda cur
        ldx cur+1
        ldy #1
        jsr Select
        jsr Follow
        jmp ListDraw
@end:   rts

; SelAll (the toolbar's select all): every entry selected but ".." (the
; first, below "/"), the list drawn.
SelAll: jsr ClearSel
        lda count               ; whole bytes: count / 8
        sta tmp
        lda count+1
        sta tmpH
        ldx #3
@div:   lsr tmpH
        ror tmp
        dex
        bne @div
        ldx tmp                 ; (ENTRY_MAX entries: 256 bytes, X 0 and
        lda tmpH                ; tmpH 1: all 256 filled)
        bne :+
        txa
        beq @rest
:       lda #$FF
@all:   dex
        sta sel,x
        bne @all
@rest:  lda count               ; the last byte's bits: count & 7
        and #7
        tay
        lda #0
@bit:   dey
        bmi @last
        sec
        rol a
        bne @bit
@last:  ldx tmpH                 ; (all 256 bytes full: no rest)
        bne @dotdot
        ldx tmp
        ora sel,x
        sta sel,x
@dotdot:
        lda path + 1            ; below "/": ".." not
        beq @draw
        lda #0
        tax
        tay
        jsr Select
@draw:  jmp ListDraw
        .assert ENTRY_MAX <= 2048, error, "SelAll: sel at most 256 bytes"

; Scratch (overlay data: fetched anew with the overlay)
dx:     .byte 0                 ; Drag: where the press was
waitL:  .byte 0                 ; Drag: rounds waited for a move
waitH:  .byte 0
dy:     .byte 0
flip:   .byte 0                 ; C= held at the drop
sprite: .res 64                 ; the dragged icon's sprite image
other:  .res 16                 ; SameDrive: the other pane's path's start
lo:     .word 0                 ; Range
hi:     .word 0
key:    .byte 0                 ; ListKey
numL:   .byte 0                 ; PathPress
numH:   .byte 0
tmp:    .byte 0
tmpH:   .byte 0
