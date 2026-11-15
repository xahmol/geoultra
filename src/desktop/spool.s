; GeoUltra Desktop: the print spooler's indicator and queue window
; (docs/DESIGN.md "Print spooler"; the user's decisions of
; 2026-11-15: the indicator in the menu bar left of the date, as the
; status line has no room with two panes; the window from a click on it
; and from geos > print queue; a job cancelled stops at once). The
; kernal's spooler (src/kernal/spool.s) answers through FE_SPOOL. The
; core asks once a second (SpoolTick, from ClockTick) and keeps the
; state; overlay 5 (with the clock, tooldraw.s) draws the indicator and
; opens the window. Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, TextWidth, tMenu, clockMode, clockX
        .import MenuCells, ShadowCells, px0, px1, py0, py1, BusyPause, BusyResume
        .import SpoolDraw, QueueWin     ; (ovl.s: overlay 5, below)
        .export SpoolTick, SpoolPress, spShown, spX, QPut, QDraw0
        .export Ov_SpoolDraw, Ov_QueueWin
Ov_SpoolDraw = QDraw
Ov_QueueWin = QWin

seconds         = year + 5      ; GEOS's clock
SP_MIN          = 152           ; the indicator: right of the menus (their
                                ; frame to x 150, desktop.s mainMenu)
SP_GAP          = 5             ; and this far left of the clock
SP_RIGHT        = 316           ; (no clock: the right edge, as the clock)
J_LEN           = 16            ; FE_SPOOL's job list (kernal spool.s J_*)
J_FLAGS         = 1
J_PAGES         = 2
J_NAME          = 3
ROWS            = 5             ; the window's job lines
ROW_LEN         = 44            ; one's text
WIN_TOP         = 24            ; the window: x 48-271, y 24-167
WIN_BOT         = 167
WIN_L           = 48
WIN_R           = 271
ROW0            = 22            ; the first job line's button (from the top)
ROW_STEP        = 18            ; buttons 16 high, 2 apart
TEXT_X          = 52            ; a line's text, right of its button
TEXT_DY         = 11            ; its baseline below the button's top
BTN_Y           = 122           ; pause or resume, close
COL_NAME        = 112           ; the columns (screen x): the program,
COL_PAGES       = 182           ; its pages, its state
COL_STATE       = 226
TITLE_STATE     = 200           ; the title's state ("paused")

; ======================================================================
; The core: the state and the click

        .segment "CODE"

; SpoolTick (ClockTick, appMain): once a second the queue's state
; (FE_SPOOL 0: the job printing, the jobs, paused) to spNew; when it
; differs from spState the indicator drawn again (overlay 5).
SpoolTick:
        lda seconds
        cmp spSec
        beq @end
        sta spSec
        lda #FE_SPOOL
        ldy #0
        jsr FileEngine
        cpx #0
        bne @end
        sta spNew
        lda r0L
        sta spNew + 1
        lda r0H
        sta spNew + 2
        ldx #2
@c:     lda spNew,x
        cmp spState,x
        bne @draw
        dex
        bpl @c
@end:   rts
@draw:  jmp SpoolDraw

; SpoolPress (desktop.s, Press): C clear when the press was on the
; indicator (the menu bar from spX): the queue window opened.
SpoolPress:
        lda mouseYPos
        cmp #MENU_BOTTOM
        bcs @no
        lda spShown
        beq @no
        lda mouseXPos
        cmp spX
        lda mouseXPos+1
        sbc spX+1
        bcc @no
        jsr QueueWin
        clc
        rts
@no:    sec
        rts

        .segment "BSS"

spNew:          .res 3          ; FE_SPOOL 0: A, r0L, r0H
spState:        .res 3          ; the one drawn
spSec:          .res 1          ; the second last asked
spX:            .res 2          ; the indicator's left and right edges
spR:            .res 2
spShown:        .res 1          ; nonzero: it is there

; ======================================================================
; Overlay 5: the indicator

        .segment "OV5"

; QDraw (SpoolTick: the state changed): spNew taken; the indicator
; drawn anew (QDraw0: as it is; tooldraw.s's ClockDraw without the
; clock).
QDraw:  ldx #2
@c:     lda spNew,x
        sta spState,x
        dex
        bpl @c
QDraw0: lda spShown
        beq QPut
        lda spX
        sta r3L
        lda spX+1
        sta r3H
        lda spR
        sta r4L
        lda spR+1
        sta r4H
        lda #0
        jsr SetPattern
        lda #1
        sta r2L
        lda #12
        sta r2H
        jsr Rectangle

; QPut (its place already cleared: ClockDraw clears from spX): "printing
; 2/5" (job 2 of the 5 since the queue was last empty) or "print paused",
; right-aligned left of the clock; the short "print 2/5" or "paused" when
; that does not fit beside the menus; nothing when the queue is empty.
QPut:   lda #0
        sta spShown
        lda spState
        beq @end
        lda #0
        jsr Text
        jsr Place
        bcc @put
        lda #1
        jsr Text
        jsr Place
        bcs @end
@put:   lda #10
        sta r1H
        lda #<qText
        sta r0L
        lda #>qText
        sta r0H
        jsr PutString
        inc spShown
@end:   rts

; Text: A = 0 the long form, 1 the short one, into qText.
Text:   sta form
        lda #<qText
        sta r5L
        lda #>qText
        sta r5H
        ldy #0
        bit spState + 2
        bpl @run
        lda form                ; paused: "print paused", "paused"
        bne :+
        ldx #PrintW - Words
        jsr Word
        jsr Space
:       ldx #PausedW - Words
        jsr Word
        jmp Zero
@run:   ldx #PrintW - Words     ; "printing 2/5", "print 2/5"
        jsr Word
        lda form
        bne :+
        ldx #IngW - Words
        jsr Word
:       jsr Space
        lda spState
        jsr Decimal
        lda #'/'
        jsr Char
        lda spState + 1
        jsr Decimal
Zero:   lda #0
        sta (r5),y
        rts

; Place: qText's right edge left of the clock (no clock: SP_RIGHT) to
; spR, its left edge to spX and r11 (TextWidth: r2). C set when that is
; left of SP_MIN (it would cover the menus).
Place:  lda #<qText
        sta r0L
        lda #>qText
        sta r0H
        jsr TextWidth
        lda #<SP_RIGHT
        sta spR
        lda #>SP_RIGHT
        sta spR+1
        lda tMenu
        cmp #ST_CLOCK
        bne @at
        lda clockMode
        cmp #CLOCK_OFF
        beq @at
        lda clockX
        sec
        sbc #SP_GAP
        sta spR
        lda clockX+1
        sbc #0
        sta spR+1
@at:    lda spR
        sec
        sbc r2L
        sta spX
        sta r11L
        lda spR+1
        sbc r2H
        sta spX+1
        sta r11H
        lda spX
        cmp #<SP_MIN
        lda spX+1
        sbc #>SP_MIN
        bcc @no
        clc
        rts
@no:    sec
        rts

; Word: the text at Words + X to r5 + Y (Y after it). Space, Char: a
; space, A. Destroys A, X.
Word:   lda Words,x
        beq @end
        sta (r5),y
        iny
        inx
        bne Word
@end:   rts
Space:  lda #' '
Char:   sta (r5),y
        iny
        rts

; Decimal: A (0-255) in decimal at r5 + Y, without leading zeros (Y after
; it). Destroys A, X.
Decimal:
        sta num
        lda #0
        sta lead
        ldx #2
@d:     lda #0
        sta dig
@s:     lda num
        cmp Pow,x
        bcc @o
        sbc Pow,x
        sta num
        inc dig
        bne @s
@o:     lda dig
        ora lead
        bne @w
        cpx #0
        bne @n
@w:     lda dig
        ora #'0'
        sta (r5),y
        iny
        sta lead
@n:     dex
        bpl @d
        rts
Pow:    .byte 1, 10, 100

Words:
PrintW:         .byte "print", 0
IngW:           .byte "ing", 0
PausedW:        .byte "paused", 0
PageW:          .byte " page", 0
PrintingW:      .byte "printing", 0
WaitingW:       .byte "waiting", 0
CancelledW:     .byte "cancelled", 0
DesktopW:       .byte "desktop", 0
ErrorW:         .byte "printer error", 0
        .assert * - Words < 256, error, "Word: X indexes the words"

form:           .byte 0
num:            .byte 0
dig:            .byte 0
lead:           .byte 0
qText:          .res 17         ; "printing 255/255" and its zero

; ======================================================================
; Overlay 5: the queue window

; QWin (a click on the indicator, geos > print queue): the jobs not yet
; printed (ROWS of them), each with its cancel button, pause or resume,
; close. Reopened after each button and when the queue's state changes
; meanwhile (QTick), so it shows the queue as it is.
QWin:   lda #0
        sta again
        lda #FE_SPOOL
        ldy #0
        jsr FileEngine
        sta qState
        lda r0L
        sta qState + 1
        lda r0H
        sta qState + 2
        lda r1L
        sta qErr
        ldx #2                  ; the indicator too (the core's tick does
@ind:   lda qState,x            ; not run while the window is open)
        sta spNew,x
        dex
        bpl @ind
        jsr QDraw
        lda #<list
        sta r0L
        lda #>list
        sta r0H
        lda #FE_SPOOL
        ldy #4
        jsr FileEngine
        cmp #ROWS
        bcc :+
        lda #ROWS
:       sta qCount
        jsr Build
        lda #WIN_L / 8
        sta px0
        lda #(WIN_R + 8) / 8
        sta px1
        lda #WIN_TOP / 8
        sta py0
        lda #(WIN_BOT + 8) / 8
        sta py1
        jsr MenuCells
        jsr BusyPause           ; (icons.s: the arrow while it is open)
        lda #<dlg
        sta r0L
        lda #>dlg
        sta r0H
        jsr DoDlgBox
        jsr BusyResume
        lda #WIN_L / 8
        sta px0
        lda #(WIN_R + 8) / 8
        sta px1
        lda #WIN_TOP / 8
        sta py0
        lda #(WIN_BOT + 8) / 8
        sta py1
        jsr ShadowCells
        lda again
        beq :+
        jmp QWin
:       rts

; Build: the dialog's table (dlg) and its texts: the title (with
; "paused" or "printer error"), a line per job (its button, its text),
; or "No print jobs."; pause or resume, close.
Build:  ldy #0                  ; the title
        lda #<title
        sta r5L
        lda #>title
        sta r5H
        ldx #TitleW - Words2
        jsr Word2
        bit qState + 2
        bpl @title
        lda #GOTOX
        jsr Char
        lda #<TITLE_STATE
        jsr Char
        lda #>TITLE_STATE
        jsr Char
        ldx #PausedW - Words
        lda qErr
        beq :+
        ldx #ErrorW - Words
:       jsr Word
@title: jsr Zero
        ldx #0                  ; the table: its head
@h:     lda DlgHead,x
        sta dlg,x
        inx
        cpx #DlgHead_n
        bne @h
        lda qCount
        bne @rows
        ldy #0                  ; no jobs
@n:     lda NoJobs,y
        sta dlg,x
        inx
        iny
        cpy #NoJobs_n
        bne @n
        beq @tail
@rows:  lda #0
        sta at
@row:   jsr Line
        lda #DBUSRICON          ; its button: CancelRecs + at * 8
        jsr Put
        lda #1
        jsr Put
        lda at
        jsr RowY
        jsr Put
        lda at
        asl a
        asl a
        asl a
        clc
        adc #<CancelRecs
        jsr Put
        lda #>CancelRecs
        adc #0
        jsr Put
        lda #DBTXTSTR
        jsr Put
        lda #TEXT_X
        jsr Put
        lda at
        jsr RowY
        clc
        adc #TEXT_DY
        jsr Put
        jsr TextAt
        lda r5L
        jsr Put
        lda r5H
        jsr Put
        inc at
        lda at
        cmp qCount
        bcc @row
@tail:  ldy #0                  ; pause or resume, close, the end
        bit qState + 2
        bpl :+
        ldy #DlgTail_n
:       lda #DlgTail_n
        sta tmp
:       lda DlgTail,y
        sta dlg,x
        inx
        iny
        dec tmp
        bne :-
        rts
        .assert DlgHead_n + ROWS * 10 + 2 * DlgTail_n <= 96, error, "dlg: too small"

; Put: A to dlg + X (X after it). RowY: A = line A's top (from the
; window's). TextAt: r5 = line at's text.
Put:    sta dlg,x
        inx
        rts
RowY:   sta tmp
        asl a                   ; * 18: * 16 + * 2 (small: no carry)
        asl a
        asl a
        asl a
        clc
        adc tmp
        adc tmp
        adc #ROW0
        rts
TextAt: lda #<rowText
        sta r5L
        lda #>rowText
        sta r5H
        ldy at
        beq @end
@add:   clc
        lda r5L
        adc #ROW_LEN
        sta r5L
        bcc :+
        inc r5H
:       dey
        bne @add
@end:   rts

; Line: job at's line: its place, the program (none: the desktop), its
; pages, its state (the first: printing or paused; cancelled; waiting).
Line:   txa
        pha
        jsr TextAt
        lda at                  ; (its entry: list + at * J_LEN)
        asl a
        asl a
        asl a
        asl a
        sta ent
        ldy #0
        lda at
        clc
        adc #1
        jsr Decimal
        lda #COL_NAME
        jsr GoX
        ldx ent
        lda list + J_NAME,x
        bne @name
        ldx #DesktopW - Words
        jsr Word
        jmp @pages
@name:  lda list + J_NAME,x
        beq @trim
        jsr Char
        inx
        bne @name
@trim:  dey                     ; (a GEOS name is padded with spaces; the
        lda (r5),y              ; GOTOX's bytes before it end the search)
        cmp #' '
        beq @trim
        iny
@pages: lda #COL_PAGES
        jsr GoX
        ldx ent
        lda list + J_PAGES,x
        pha
        jsr Decimal
        ldx #PageW - Words
        jsr Word
        pla
        cmp #1
        beq :+
        lda #'s'
        jsr Char
:       lda #COL_STATE
        jsr GoX
        ldx ent
        lda list + J_FLAGS,x
        bpl :+
        ldx #CancelledW - Words
        bne @state
:       ldx #WaitingW - Words
        lda at
        bne @state
        ldx #PrintingW - Words
        bit qState + 2
        bpl @state
        ldx #PausedW - Words
@state: jsr Word
        jsr Zero
        pla
        tax
        rts

; GoX: GOTOX to screen x A (< 256).
GoX:    pha
        lda #GOTOX
        jsr Char
        pla
        jsr Char
        lda #0
        jmp Char

; Word2: as Word, from Words2 (the window's own).
Word2:  lda Words2,x
        beq @end
        sta (r5),y
        iny
        inx
        bne Word2
@end:   rts

; QStart (the dialog's DB_USR_ROUT): QTick as appMain while it is open
; (DoDlgBox gives the desktop's back after).
QStart: lda #<QTick
        sta appMain
        lda #>QTick
        sta appMain+1
        lda seconds
        sta tickSec
        rts

; QTick: once a second the queue's state; changed: the window again.
QTick:  lda seconds
        cmp tickSec
        beq @end
        sta tickSec
        lda #FE_SPOOL
        ldy #0
        jsr FileEngine
        cmp qState
        bne Again
        lda r0L
        cmp qState + 1
        bne Again
        lda r0H
        cmp qState + 2
        bne Again
@end:   rts

; The buttons' routines (DBUSRICON): cancel line n's job, pause, resume
; (each: the window again), close.
Cancel0:
        ldy #0 * J_LEN
        beq Cancel
Cancel1:
        ldy #1 * J_LEN
        bne Cancel
Cancel2:
        ldy #2 * J_LEN
        bne Cancel
Cancel3:
        ldy #3 * J_LEN
        bne Cancel
Cancel4:
        ldy #4 * J_LEN
Cancel: lda list,y              ; (its number: J_SEQ, 0)
        sta r0L
        ldy #3
        bne Fe
Pause:  ldy #1
        bne Fe
Resume: ldy #2
Fe:     lda #FE_SPOOL
        jsr FileEngine
Again:  lda #1
        sta again
Close:  lda #OK
        sta sysDBData
        jmp RstrFrmDialogue

        .include "qicons.inc"

; DBUSRICON records: picture, x and y (from the table), width in cards,
; height, routine.
CancelRecs:
        .word CancelIcon
        .byte 0, 0, 5, 16
        .word Cancel0
        .word CancelIcon
        .byte 0, 0, 5, 16
        .word Cancel1
        .word CancelIcon
        .byte 0, 0, 5, 16
        .word Cancel2
        .word CancelIcon
        .byte 0, 0, 5, 16
        .word Cancel3
        .word CancelIcon
        .byte 0, 0, 5, 16
        .word Cancel4
        .assert ROWS = 5, error, "CancelRecs: one per line"
PauseRec:
        .word PauseIcon
        .byte 0, 0, 6, 16
        .word Pause
ResumeRec:
        .word ResumeIcon
        .byte 0, 0, 6, 16
        .word Resume
CloseRec:
        .word CloseIcon
        .byte 0, 0, 6, 16
        .word Close

DlgHead:
        .byte SET_DB_POS | 1, WIN_TOP, WIN_BOT
        .word WIN_L, WIN_R
        .byte DBTXTSTR, 8, 14
        .word title
        .byte DB_USR_ROUT
        .word QStart
DlgHead_n = * - DlgHead
NoJobs: .byte DBTXTSTR, 16, ROW0 + TEXT_DY
        .word NoJobsText
NoJobs_n = * - NoJobs
DlgTail:                        ; (running: pause; paused: resume)
        .byte DBUSRICON, 1, BTN_Y
        .word PauseRec
        .byte DBUSRICON, 21, BTN_Y
        .word CloseRec
        .byte 0
DlgTail_n = * - DlgTail
        .byte DBUSRICON, 1, BTN_Y
        .word ResumeRec
        .byte DBUSRICON, 21, BTN_Y
        .word CloseRec
        .byte 0

Words2:
TitleW:         .byte BOLDON, "Print queue", PLAINTEXT, 0
NoJobsText:     .byte "No print jobs.", 0

again:          .byte 0
qCount:          .byte 0
at:             .byte 0
ent:            .byte 0
tmp:            .byte 0
tickSec:        .byte 0
qState:         .res 3
qErr:           .byte 0
title:          .res 32
dlg:            .res 96
rowText:        .res ROWS * ROW_LEN
list:           .res 256        ; FE_SPOOL 4: 16 jobs of J_LEN
