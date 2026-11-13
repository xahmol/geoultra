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
        .include "hw.inc"

        .import EntryUnder, pick, last, Modifiers, mods, ClearSel, Select, cur
        .import ListDraw, count, ThumbRows, top, path, Follow, Up, Into, step
        .import rows, listL, listTop, pathY, bottom, topY, stY0, stY1, tScroll
        .import openReq, text, TextWidth, rowH, IsSelected, stripL, sel
        .import panes, active, PaneAt, dropReq, Fetch, entryInfo, IconFor, Icons
        .import dropPath, entryName, path, sideW, sideCount, sideTops, sideLetters, Setup, Slot
        .import RowY, RowBox, ry, row, viewMode
        .export Ov_ListPress, Ov_ListKey, Ov_ListEnd, Ov_SelAll, Ov_PaneLetters
        .import lettersDue, paneR, Drive, FileEngine, rootsSeen
Ov_ListEnd = ListEnd
Ov_SelAll = SelAll
DrawSprite      = $C1C6         ; GEOS jump table
PosSprite       = $C1CF
EnablSprite     = $C1D2
DisablSprite    = $C1D5
DRAG_SPR        = 2             ; (0 the pointer, 1 the text cursor)
DRAG_MIN        = 5             ; pixels moved before a press is a drag
DRAG_HOLD       = 3             ; seconds by the clock (2-3) held still: a
                                ; click
seconds         = year + 5      ; GEOS's clock (geos.inc: year)
DRAG_COLOR      = 6             ; blue (the pointer's, kernal load.s)
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


; --- Two panes: the drive letters on the path lines (the user's decisions
; 2026-11-13). At the right end of each pane's path line, packed: the
; drives with an image (A-D), E, and U when the Ultimate has roots (sd,
; usb0 ... : a list, RootMenu); only those, so the path keeps the rest of
; the line. The pane's own drive inverted (U for an Ultimate folder); a
; click on a letter opens its root in the active pane (core's Drive).
; Drawn from ClockTick (lettersDue, set by list.s PaneMark), as ListDraw
; also runs inside other overlays.

LETTERS         = 6             ; A-E and U at most
LET_U           = 5
DRIVE_LETTERS   = 5
LET_PITCH       = 9

; Ov_PaneLetters: both panes' letters drawn.
Ov_PaneLetters:
        lda #0
        sta lettersDue
        lda panes
        beq @end
        jsr BuildSet
        lda #0
        jsr PaneRow
        lda #1
        jsr PaneRow
@end:   rts

; BuildSet: lset = the letters to show (0-3 the drives with an image, 4
; E, 5 U when the Ultimate has roots: rootsSeen, counted once), ln their
; number.
BuildSet:
        ldy #0
        ldx #0
@drv:   lda driveType,x
        beq :+
        txa
        sta lset,y
        iny
:       inx
        cpx #4
        bcc @drv
        lda #4                  ; E
        sta lset,y
        iny
        sty ln
        lda rootsSeen           ; (0: not counted yet; 1: none; 2: some)
        bne :+
        jsr ReadRoots
        ldx #1
        lda rootN
        beq @seen
        inx
@seen:  stx rootsSeen
:       lda rootsSeen
        cmp #2
        bne @end
        ldy ln
        lda #LET_U
        sta lset,y
        inc ln
@end:   rts

; PaneRow: pane A's letters: the area cleared, the letters, its drive's
; inverted, the whole inverted again when it is the active pane (its
; path line is: list.s PaneMark).
PaneRow:
        sta lpane
        jsr PaneDrive           ; lcur = its drive letter's index or $FF
        jsr AreaRegs
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda #0
        sta li
@one:   jsr LetX                ; r11 = slot li's x
        lda pathY
        sta r1H
        ldx li
        lda lset,x
        clc
        adc #'A'
        cmp #'A' + LET_U
        bne :+
        lda #'U'
:       jsr PutChar
        ldx li
        lda lset,x
        cmp lcur
        bne @next
        jsr LetX                ; its box inverted
        jsr LetBox
        jsr InvertRectangle
@next:  inc li
        lda li
        cmp ln
        bcc @one
        lda lpane
        cmp active
        bne @end
        jsr AreaRegs
        jmp InvertRectangle
@end:   rts

; PaneDrive: lcur = pane lpane's drive (0 A .. 4 E, 5 U for an Ultimate
; folder) from its path, $FF for "/".
PaneDrive:
        lda lpane
        cmp active
        bne @other
        lda path + 1
        ldx path + 2
        jmp @which
@other: lda #<lbuf              ; the other pane's path: its first bytes
        sta r0L                 ; from the REU (list.s SwapPane's state)
        lda #>lbuf
        sta r0H
        lda #0
        sta r1L
        sta r2H
        lda #PANE_PAGE
        sta r1H
        lda #3
        sta r2L
        lda #PANE_BANK
        sta r3L
        jsr FetchRAM
        lda lbuf + 1
        ldx lbuf + 2
@which: cmp #0                  ; "/": none
        beq @none
        cpx #0                  ; one letter only (then the end or "/"):
        beq :+                  ; a drive; a longer first part: the
        cpx #'/'                ; Ultimate's (usb0, sd ...): U
        bne @ult
:       sec
        sbc #'a'
        cmp #DRIVE_LETTERS
        bcs @ult
        sta lcur
        rts
@ult:   lda #LET_U
        sta lcur
        rts
@none:  lda #$FF
        sta lcur
        rts

; AreaRegs: r2-r4 = pane lpane's letters' area (ln of them).
AreaRegs:
        lda pathY
        sec
        sbc #7
        sta r2L
        clc
        adc #8
        sta r2H
        jsr PaneEnd             ; r4 = its right end
        lda #0
        ldx ln
@w:     dex
        bmi :+
        clc
        adc #LET_PITCH
        bne @w
:       sta rtmp
        lda r4L
        sec
        sbc rtmp
        sta r3L
        lda r4H
        sbc #0
        sta r3H
        rts

; PaneEnd: r4 = pane lpane's path line's right end (a pixel inside the
; frame).
PaneEnd:
        ldx lpane
        lda EndLo,x
        sta r4L
        lda EndHi,x
        sta r4H
        rts
EndLo:  .byte <(PANE_W - 2), <(2 * PANE_W - 2)
EndHi:  .byte >(PANE_W - 2), >(2 * PANE_W - 2)

; LetX: r11 = slot li's glyph x (pane lpane): end - (ln - li) * pitch + 2.
LetX:   jsr PaneEnd
        lda ln
        sec
        sbc li
        tax
        lda r4L
@sub:   sec
        sbc #LET_PITCH
        bcs :+
        dec r4H
:       dex
        bne @sub
        clc
        adc #2
        sta r11L
        lda r4H
        adc #0
        sta r11H
        rts

; LetBox: r2-r4 = slot li's box (r11 its glyph's x, LetX).
LetBox: lda pathY
        sec
        sbc #7
        sta r2L
        clc
        adc #8
        sta r2H
        lda r11L
        sec
        sbc #2
        sta r3L
        lda r11H
        sbc #0
        sta r3H
        lda r3L
        clc
        adc #LET_PITCH - 2
        sta r4L
        lda r3H
        adc #0
        sta r4H
        rts

; LetterUnder (ListPress, a press on the path line): with two panes and
; the pointer on a letter, C clear and A = its code ('a'-'e' for Drive,
; 'U' for RootMenu); else C set.
LetterUnder:
        lda panes
        beq @no
        jsr BuildSet
        lda active
        sta lpane
        lda #0
        sta li
@try:   lda li
        cmp ln
        bcs @no
        jsr LetX
        jsr LetBox
        jsr IsMseInRegion
        bne @hit
        inc li
        bne @try
@no:    sec
        rts
@hit:   ldx li
        lda lset,x
        cmp #LET_U
        bne :+
        lda #'U'                ; (RootMenu)
        clc
        rts
:       clc
        adc #'a'
        clc
        rts

; ReadRoots: rootN = the Ultimate's roots (the root listing's Ultimate
; folders, ROOTS_MAX at most), their names in roots.
ReadRoots:
        lda #0
        sta rootN
        lda #<SlashText
        sta r0L
        lda #>SlashText
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta rhandle
        txa
        bne @end
@entry: lda rootN
        cmp #ROOTS_MAX
        bcs @close
        lda #<rinfo
        sta r1L
        lda #>rinfo
        sta r1H
        lda rootN               ; its name into roots + n * ROOT_LEN
        asl a
        asl a
        asl a
        clc
        adc #<roots
        sta r2L
        lda #>roots
        adc #0
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy rhandle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        lda rinfo               ; (FI_KIND)
        cmp #K_UDIR
        bne @entry
        lda rootN               ; (a name kept within its 8 bytes)
        asl a
        asl a
        asl a
        tax
        lda #0
        sta roots + ROOT_LEN - 1,x
        inc rootN
        bne @entry
@close: ldy rhandle
        lda #FE_CLOSE
        jsr FileEngine
@end:   rts

; RootMenu (U on the active pane's path line): the Ultimate's roots that
; are there (the root listing's Ultimate folders, as the sidebar's
; Ultimate lines: sd, usb0, usb1, usb2 ...) in a list under the button,
; the item under the pointer inverted; a click opens that root in the
; pane, a click elsewhere or RUN/STOP closes it (the pane drawn again).
; Its own loop, as the context menu's. C clear.
ROOTS_MAX       = 4
ROOT_LEN        = 8             ; a root's name and its zero
ROOT_H          = 12
ROOT_W          = 44
RootMenu:
        jsr ReadRoots
@drawn: lda rootN
        bne :+
        clc                     ; (none: nothing to show)
        rts
:       jsr MenuBox             ; the list: cleared, framed, its names
        lda #0
        jsr SetPattern
        jsr Rectangle
        jsr MenuBox
        lda #$FF
        jsr FrameRectangle
        lda #0
        sta li
@name:  lda li
        jsr ItemTop
        clc
        adc #9
        sta r1H
        lda r3L
        clc
        adc #4
        sta r11L
        lda r3H
        adc #0
        sta r11H
        lda li
        asl a
        asl a
        asl a
        clc
        adc #<roots
        sta r0L
        lda #>roots
        adc #0
        sta r0H
        jsr PutString
        jsr MenuBox             ; (r3 again for the next)
        inc li
        lda li
        cmp rootN
        bcc @name
        lda #$FF
        sta rhover
        jsr Unpress
@loop:  jsr RootUnder
        cmp rhover
        beq @input
        pha
        lda rhover
        jsr RootInv
        pla
        sta rhover
        jsr RootInv
@input: jsr GetNextChar
        cmp #KEY_STOP
        beq @shut
        lda pressFlag
        and #MOUSE_BIT
        beq @loop
        jsr Unpress
        lda mouseData
        bmi @loop               ; (a release: on)
        jsr RootUnder
        cmp #$FF
        beq @shut
        asl a                   ; "/" and its name: the path to open
        asl a
        asl a
        tax
        ldy #1
@cp:    lda roots,x
        sta rpath,y
        beq @go
        inx
        iny
        cpy #ROOT_LEN + 1
        bcc @cp
        lda #0
        sta rpath,y
@go:    lda #'/'
        sta rpath
        lda #<rpath
        ldx #>rpath
        jsr Into                ; (open.s: read and drawn)
        clc
        rts
@shut:  jsr ListDraw            ; (the pane again: the list away)
        clc
        rts

; MenuBox: r2-r4 = the roots' list under the U button (right-aligned to
; the pane's end).
MenuBox:
        lda pathY
        clc
        adc #2
        sta r2L
        lda rootN
        jsr ItemTop             ; (rows from r2L + 1)
        clc
        adc #ROOT_H
        sta r2H
        lda active
        sta lpane
        jsr PaneEnd             ; r4 = the pane's end
        lda r4L
        sec
        sbc #ROOT_W - 1
        sta r3L
        lda r4H
        sbc #0
        sta r3H
        rts

; ItemTop: A = the top line of the roots' item A (r2L the box's top).
ItemTop:
        sta rtmp
        asl a                   ; * 12
        clc
        adc rtmp
        asl a
        asl a
        sec                     ; + r2L + 1
        adc r2L
        rts

; RootUnder: A = the item under the pointer, $FF outside the list.
RootUnder:
        jsr MenuBox
        jsr IsMseInRegion
        beq @none
        lda mouseYPos
        sec
        sbc r2L
        sbc #1
        bcc @none
        ldx #$FF
@div:   inx
        sec
        sbc #ROOT_H
        bcs @div
        cpx rootN
        bcs @none
        txa
        rts
@none:  lda #$FF
        rts

; RootInv: item A inverted ($FF: nothing).
RootInv:
        cmp #$FF
        beq @end
        pha
        jsr MenuBox
        pla
        jsr ItemTop
        sta r2L
        clc
        adc #ROOT_H - 1
        sta r2H
        inc r3L                 ; (inside the frame)
        bne :+
        inc r3H
:       lda r4L
        bne :+
        dec r4H
:       dec r4L
        jsr InvertRectangle
@end:   rts

; Unpress: the mouse bit of pressFlag cleared (safe against the IRQ).
Unpress:
        php
        sei
        lda pressFlag
        and #$FF - MOUSE_BIT
        sta pressFlag
        plp
        rts

SlashText:      .byte "/", 0
rootN:  .byte 0
rhandle:.byte 0
rhover: .byte 0
rtmp:   .byte 0
rinfo:  .res INFO_LEN
roots:  .res ROOTS_MAX * ROOT_LEN
rpath:  .res ROOT_LEN + 2

lset:   .res LETTERS                ; BuildSet: the letters shown
ln:     .byte 0                 ; and their number
lpane:  .byte 0                 ; the pane at hand
li:     .byte 0                 ; the letter at hand
lcur:   .byte 0                 ; the pane's drive (0-4, $FF: none)
lbuf:   .res 3                  ; the other pane's path's start

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
        jsr LetterUnder         ; (two panes: a drive letter there?)
        bcs :+
        cmp #'U'
        bne @drive
        jmp RootMenu            ; (the Ultimate's roots: a list)
@drive: jmp Drive               ; (open.s: its root; C clear after it)
:       jmp PathPress
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
; dropped on the other pane, on a folder of this list that is not
; selected, or on a sidebar drive or favourite, the core copies or moves
; it there (dropReq; dropPath the target folder; desktop.s DropDo): the
; same drive moves, another
; copies, C= held the other way. An entry not selected becomes the
; selection when the drag starts (the user's test 2026-11-13: press and
; drag at once). C set: no drag (a click: on as usual): the second press
; of a double click, a release before the move, or a press held still
; for two to three seconds (the wait keeps MainLoop, the clock and
; processes, from running).
Drag:   lda pick
        ldx pick+1
        jsr IsSelected
        sta wasSel
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
        lda seconds             ; (the wait timed by GEOS's clock, not by
        sta waitL               ; rounds: at the U64's turbo 65536 rounds
@wait:  lda seconds             ; took 30 ms; the user's test 2026-11-13)
        sec
        sbc waitL
        bcs :+
        adc #60                 ; (the minute turned)
:       cmp #DRAG_HOLD
        bcs @click
        lda mouseData           ; released before it moved: a click
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
@drag:  lda wasSel              ; not selected: it alone the selection
        bne :+
        jsr ClearSel
        lda pick
        ldx pick+1
        ldy #1
        jsr Select
        jsr ListDraw
:       jsr Sprite              ; the entry's icon at the pointer
        lda #0
        sta hover
@track: jsr Hover               ; (the target under the pointer marked)
        lda #DRAG_SPR
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
        lda #0                  ; (the mark taken away)
        jsr MarkTo
        lda #DRAG_SPR
        sta r3L
        jsr DisablSprite
        jsr Modifiers           ; (C= held: the other way)
        lda mods
        and #MOD_CBM
        sta flip
        lda panes               ; the other pane?
        beq @side
        jsr PaneAt
        cmp active
        beq @entry
        jsr OtherPath           ; (its path: for the comparisons)
        jsr SamePath            ; (the same folder in both: nothing)
        beq @none
        lda #DROP_OTHER_COPY
        bne @req
@side:  jsr SideTarget          ; a sidebar drive or favourite?
        bcc @path
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
:       jsr EntryPath           ; dropPath = path "/" its name
@path:  jsr SamePath            ; (into its own folder: nothing to do)
        beq @none
        lda #DROP_PATH_COPY
@req:   sta dropReq             ; the same drive: a move (bit 0); C= at
        jsr SameDrive           ; the release: the other way
        bne :+
        inc dropReq
:       lda flip
        beq @none
        lda dropReq
        eor #1
        sta dropReq
@none:  clc
        rts

; EntryPath: dropPath = path, "/" (unless it ends in one), entryName;
; cut at its end when too long (Paste then fails on it and says so).
EntryPath:
        ldy #$FF
@p:     iny
        lda path,y
        sta dropPath,y
        bne @p
        lda path-1,y            ; (the root "/": no second one)
        cmp #'/'
        beq :+
        lda #'/'
        sta dropPath,y
        iny
:       ldx #0
@n:     lda entryName,x
        sta dropPath,y
        beq @end
        inx
        iny
        bne @n
        dey
        lda #0
        sta dropPath,y
@end:   rts

; SideTarget: C clear when the pointer is over a sidebar drive or
; favourite line (one list: the sidebar shown), dropPath then its path:
; "/a" ... "/e", "/usb0", "/usb1", "/sd", or the favourite's folder. A
; recent document's line is no target. The lines as desktop.s's Press
; finds them (sideTops, sideLetters).
SideTarget:
        jsr SideLine
        bcc @hit
@no:    sec
        rts
@hit:   lda sideLetters,x
        bmi @fav
        ldx #RootSd - Roots     ; an Ultimate root ('0', '1', 's'), or
        cmp #'s'                ; "/" and the drive's letter
        beq @root
        ldx #RootUsb1 - Roots
        cmp #'1'
        beq @root
        ldx #RootUsb0 - Roots
        cmp #'0'
        beq @root
        sta dropPath+1
        lda #'/'
        sta dropPath
        lda #0
        sta dropPath+2
        clc
        rts
@root:  ldy #0
:       lda Roots,x
        sta dropPath,y
        beq @ok
        inx
        iny
        bne :-
@fav:   cmp #CODE_REC           ; (a recent document: none)
        bcs @no
        and #$0F
        pha
        ldx #L_FAV
        jsr Setup
        pla
        jsr Slot                ; r6 = its path
        ldy #PATH_LEN - 1
:       lda (r6),y
        sta dropPath,y
        dey
        bpl :-
@ok:    clc
        rts

; SideLine: C clear and X = the sidebar line under the pointer when it
; is a drive or a favourite (a recent document's line: C set).
SideLine:
        lda mouseXPos+1
        bne @no
        ldx sideW
        dex
        cpx mouseXPos
        bcc @no
        beq @no
        ldx #0
@line:  cpx sideCount
        bcs @no
        lda mouseYPos
        sec
        sbc sideTops,x
        bcc @next
        cmp rowH
        bcc @hit
@next:  inx
        bne @line
@no:    sec
        rts
@hit:   lda sideLetters,x
        cmp #CODE_REC
        bcs @no                 ; (C set)
        rts                     ; (C clear)

; Hover (Drag, while the button is held): the drop target under the
; pointer marked (MarkTo): a sidebar drive or favourite line with one
; list, or a folder of this pane's list that is not selected (the list
; and detailed views; the icon view gets no mark).
Hover:  lda panes
        bne @list
        jsr SideLine
        bcs @list
        txa
        ora #$80
        bne MarkTo
@list:  lda viewMode
        cmp #VIEW_ICONS
        beq @none
        lda panes
        beq :+
        jsr PaneAt
        cmp active
        bne @none
:       jsr EntryUnder
        bcs @none
        stx dropAt+1
        sta dropAt
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
:       lda row                 ; (EntryUnder's)
        clc
        adc #1
        bne MarkTo
@none:  lda #0
; MarkTo: the mark moved to A (0 none, row + 1, or $80 + a sidebar
; line): the old one inverted back, the new one inverted.
MarkTo: cmp hover
        beq @end
        pha
        lda hover
        jsr Flip
        pla
        sta hover
        jmp Flip
@end:   rts

; Flip: mark A (as MarkTo's) inverted on the screen.
Flip:   tax
        beq @end
        bpl @row
        and #$7F                ; a sidebar line: x 0 to its line - 2
        tax
        lda sideTops,x
        sta r2L
        clc
        adc rowH
        sbc #0                  ; (C clear: - 1 more)
        sta r2H
        lda #0
        sta r3L
        sta r3H
        sta r4H
        ldx sideW
        dex
        dex
        stx r4L
        jmp InvertRectangle
@row:   dex                     ; a row of the list (RowBox)
        txa
        jsr RowY
        sta ry
        jsr RowBox
        jmp InvertRectangle
@end:   rts

Roots:
RootUsb0:       .byte "/usb0", 0
RootUsb1:       .byte "/usb1", 0
RootSd:         .byte "/sd", 0

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
        php                     ; its colour (the kernal sets only sprites
        sei                     ; 0 and 1): as the pointer's
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda #DRAG_COLOR
        sta vicSpr0Color + DRAG_SPR
        pla
        sta CPU_PORT
        plp
        lda #DRAG_SPR
        sta r3L
        jmp EnablSprite

; OtherPath: dropPath = the other pane's path, from the REU (list.s
; SwapPane's first part, 256 bytes).
OtherPath:
        lda #<dropPath
        sta r0L
        lda #>dropPath
        sta r0H
        lda #0
        sta r1L
        sta r2L
        lda #PANE_PAGE
        sta r1H
        lda #1
        sta r2H
        lda #PANE_BANK
        sta r3L
        jmp FetchRAM

; SamePath: Z set when dropPath names path's folder itself (the same
; text; a sidebar line of the folder shown, say).
SamePath:
        ldy #$FF
@ch:    iny
        lda path,y
        cmp dropPath,y
        bne @end
        cmp #0
        bne @ch
@end:   rts

; SameDrive: Z set when dropPath is on the same drive as path (their
; first parts: "/a", "/usb0" ...).
SameDrive:
        ldy #0
@ch:    iny
        lda path,y              ; path's first part ended (0 or "/")?
        beq @pend
        cmp #'/'
        beq @pend
        cmp dropPath,y          ; no: the same character in the other's
        beq @ch
@diff:  lda #1                  ; (Z clear: another drive)
        rts
@pend:  lda dropPath,y          ; yes: the other's must end here too
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
        ldx tmp                 ; (whole bytes; with tmpH 1, 256 of them:
        lda tmpH                ; only when SEL_LEN is 256)
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
@last:  ldx tmpH                 ; (256 bytes full: no rest)
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
        .assert SEL_LEN <= 256, error, "SelAll: sel at most 256 bytes"

; Scratch (overlay data: fetched anew with the overlay)
dx:     .byte 0                 ; Drag: where the press was
hover:  .byte 0                 ; Drag: the mark shown (MarkTo)
wasSel: .byte 0                 ; Drag: pick selected at the press
dropAt: .word 0                 ; Drag, Hover: the folder entry under it
waitL:  .byte 0                 ; Drag: the second the wait began
dy:     .byte 0
flip:   .byte 0                 ; C= held at the drop
sprite: .res 64                 ; the dragged icon's sprite image
lo:     .word 0                 ; Range
hi:     .word 0
key:    .byte 0                 ; ListKey
numL:   .byte 0                 ; PathPress
numH:   .byte 0
tmp:    .byte 0
tmpH:   .byte 0
