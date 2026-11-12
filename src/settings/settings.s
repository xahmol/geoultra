; GeoUltra Settings (docs/SETTINGS.md): the core. The start, the frame
; (title, the side list of pages, OK, Cancel and Save), the pages handed
; to their overlays (ovl.s), and SETTINGS.INI: read whole at the start
; (src/inc/inifile.inc), changed in memory by the pages (ini.inc,
; choice.s), written on OK or Save. Without an Ultimate (VICE) nothing
; is read or written: the pages show their defaults. Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import OvlInit, DeskDraw, DeskPress, PtrDraw, PtrPress
        .export FileEngine, dirty, NoRoom

        .segment "ZEROPAGE"

feVec:          .res 2          ; the file engine's entry
pageVec:        .res 2          ; DrawPage, Press: the page's routine

        .segment "CODE"

INI_BUF = iniText               ; (ini.inc, inifile.inc: included at the
                                ; end, Start must stay at $0400)

; Start: (the entry: GEOS starts the application at $0400) SETTINGS.INI read, the screen drawn on the Desktop page, the
; buttons and the mouse and keys taken; back to MainLoop.
Start:  jsr OvlInit             ; (ovl.s: the pages into the REU, while
                                ; dirEntryBuf still holds our entry)
        lda guExtTable          ; the file engine: guExtTable + FE_ENTRY
        clc
        adc #FE_ENTRY
        sta feVec
        lda guExtTable+1
        adc #0
        sta feVec+1
        jsr UseSystemFont
        lda #ST_WR_FORE | ST_WR_BACK ; both screens: dialogs give back
        sta dispBufferOn        ; what was under them
        jsr Load
        lda #PAGE_DESKTOP
        sta page
        jsr DrawAll
        lda #<Press
        sta otherPressVec
        lda #>Press
        sta otherPressVec+1
        lda #<Buttons
        sta r0L
        lda #>Buttons
        sta r0H
        jmp DoIcons

; FileEngine: A = the function (docs/FILE_ENGINE.md).
FileEngine:
        jmp (feVec)

; Load: SETTINGS.INI in the home folder into the INI text; noFile set
; when there is none to write (no Ultimate, or too large or unreadable:
; then it is left alone).
Load:   lda #0
        sta dirty
        sta noFile
        lda #<IniName
        sta r0L
        lda #>IniName
        sta r0H
        lda #<TmpName
        sta r1L
        lda #>TmpName
        sta r1H
        jsr IniPaths
        bcs @none
        jsr IniLoad
        txa
        beq @end
@none:  inc noFile
        lda #0                  ; (an empty text: the defaults)
        sta iniLen
        sta iniLen+1
        sta INI_BUF
@end:   rts

; --- drawing

; DrawAll: the whole screen: cleared, the title, the lines, the side
; list, the page.
DrawAll:
        lda #0
        jsr SetPattern
        lda #0
        sta r2L
        sta r3L
        sta r3H
        lda #199
        sta r2H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        jsr Rectangle
        lda #<Title             ; the title, bold
        sta r0L
        lda #>Title
        sta r0H
        lda #<TITLE_X
        sta r11L
        lda #>TITLE_X
        sta r11H
        lda #TITLE_Y
        sta r1H
        jsr PutString
        lda #TITLE_LINE         ; the lines: under the title, above the
        jsr HLine               ; buttons, between the list and the page
        lda #BUTTON_LINE
        jsr HLine
        lda #TITLE_LINE
        sta r3L
        lda #BUTTON_LINE
        sta r3H
        lda #<SIDE_LINE
        sta r4L
        lda #>SIDE_LINE
        sta r4H
        lda #$FF
        jsr VerticalLine
        jsr DrawSide
        jmp DrawPage

; HLine: a full-width line at y A.
HLine:  sta r11L
        lda #0
        sta r3L
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        lda #$FF
        jmp HorizontalLine

; DrawSide: the page names, the current one inverted.
DrawSide:
        ldx #0
@name:  stx at
        lda NameLo,x
        sta r0L
        lda NameHi,x
        sta r0H
        lda #SIDE_X
        sta r11L
        lda #0
        sta r11H
        txa
        jsr RowTop
        clc
        adc #SIDE_BASE
        sta r1H
        jsr PutString
        ldx at
        inx
        cpx #PAGES_N
        bcc @name
        lda page
; Mark: page A's name inverted (again: back to normal).
Mark:   jsr RowTop
        sta r2L
        clc
        adc #SIDE_ROW - 1
        sta r2H
        lda #0
        sta r3L
        sta r3H
        sta r4H
        lda #SIDE_W - 1
        sta r4L
        jmp InvertRectangle

; RowTop: A = page A's row top (SIDE_TOP + A * SIDE_ROW).
RowTop: tax
        lda #SIDE_TOP
@add:   dex
        bmi @end
        clc
        adc #SIDE_ROW
        bne @add
@end:   rts

; DrawPage: the page area cleared, the current page drawn (its
; overlay), or a note for pages still to come.
DrawPage:
        lda #0
        jsr SetPattern
        lda #PAGE_TOP
        sta r2L
        lda #PAGE_BOTTOM
        sta r2H
        lda #<PAGE_LEFT
        sta r3L
        lda #>PAGE_LEFT
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        jsr Rectangle
        ldx page                ; the page's own drawing (its overlay)
        lda DrawLo,x
        sta pageVec
        lda DrawHi,x
        sta pageVec+1
        jmp (pageVec)

; Later: the note on a page still to come.
Later:  lda #<LaterText
        sta r0L
        lda #>LaterText
        sta r0H
        lda #<(PAGE_LEFT + 2)
        sta r11L
        lda #>(PAGE_LEFT + 2)
        sta r11H
        lda #PAGE_TOP + 16
        sta r1H
        jmp PutString

; --- the mouse

; Press (otherPressVec; the buttons are DoIcons's): a page name makes
; that page the current one; a click in the page goes to its overlay.
Press:  lda mouseData
        bmi @end                ; (a release)
        lda mouseXPos+1
        bne @page
        lda mouseXPos
        cmp #SIDE_W
        bcs @page
        lda mouseYPos           ; the side list: which row?
        sec
        sbc #SIDE_TOP
        bcc @end
        ldx #0
@row:   cmp #SIDE_ROW
        bcc @got
        sbc #SIDE_ROW
        inx
        cpx #PAGES_N
        bcc @row
        rts
@got:   cpx page
        beq @end
        stx at
        lda page                ; the old name back to normal, the new one
        jsr Mark                ; inverted, its page drawn
        lda at
        sta page
        jsr Mark
        jmp DrawPage
@page:  lda mouseYPos           ; the page area?
        cmp #PAGE_TOP
        bcc @end
        cmp #PAGE_BOTTOM + 1
        bcs @end
        ldx page                ; the page's own (its overlay)
        lda PressLo,x
        sta pageVec
        lda PressHi,x
        sta pageVec+1
        jmp (pageVec)
@end:   rts

NoPress:
        rts

; --- the buttons (DoIcons)

; DoOk: the settings written (when changed), then back to the desktop;
; a failed write keeps the application open (the error said).
DoOk:   jsr Write
        bcs :+
        jmp EnterDeskTop
:       rts

; DoSave: the settings written, the application stays.
DoSave: jmp Write

; DoCancel: back to the desktop without writing; asked first when
; something was changed.
DoCancel:
        lda dirty
        beq @leave
        lda #<LeaveDlg
        sta r0L
        lda #>LeaveDlg
        sta r0H
        jsr DoDlgBox
        lda r0L
        cmp #YES
        beq @leave
        rts
@leave: jmp EnterDeskTop

; Write: SETTINGS.INI written when changed (inifile.inc IniSave). C set
; when it failed (the error shown).
Write:  lda dirty
        beq @ok
        lda noFile              ; (no Ultimate: nothing to write)
        bne @ok
        jsr IniSave
        txa
        bne @fail
        lda #0
        sta dirty
@ok:    clc
        rts
@fail:  jsr Hex                 ; "Not saved: error $xx"
        lda #<FailDlg
        sta r0L
        lda #>FailDlg
        sta r0H
        jsr DoDlgBox
        sec
        rts

; NoRoom (choice.s): the INI text is full; the change is not made.
NoRoom: lda #<RoomDlg
        sta r0L
        lda #>RoomDlg
        sta r0H
        jmp DoDlgBox

; Hex: A as two hex digits into FailText's end.
Hex:    pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr Digit
        sta FailHex
        pla
        and #$0F
        jsr Digit
        sta FailHex + 1
        rts
Digit:  cmp #10
        bcc :+
        adc #'A' - 10 - 1       ; (C set)
        rts
:       adc #'0'
        rts

; --- data

TITLE_X         = 112
SIDE_X          = 6
SIDE_BASE       = 9             ; a page name's baseline below its row top

; Each page's drawing and click routines (stubs into its overlay, ovl.s;
; Later and NoPress for the pages still to come), in PAGE_* order.
DrawLo:         .byte <Later, <DeskDraw, <Later, <Later, <Later, <PtrDraw
DrawHi:         .byte >Later, >DeskDraw, >Later, >Later, >Later, >PtrDraw
PressLo:        .byte <NoPress, <DeskPress, <NoPress, <NoPress, <NoPress, <PtrPress
PressHi:        .byte >NoPress, >DeskPress, >NoPress, >NoPress, >NoPress, >PtrPress

Title:          .byte BOLDON, "GeoUltra Settings", PLAINTEXT, 0
NameLo:         .byte <N0, <N1, <N2, <N3, <N4, <N5
NameHi:         .byte >N0, >N1, >N2, >N3, >N4, >N5
N0:             .byte "Theme", 0
N1:             .byte "Desktop", 0
N2:             .byte "System", 0
N3:             .byte "Drives", 0
N4:             .byte "REU", 0
N5:             .byte "Pointer", 0
LaterText:      .byte "This page comes in a later step.", 0
IniName:        .byte "SETTINGS.INI", 0
TmpName:        .byte "SETTINGS.TMP", 0

Buttons:        .byte 3                 ; DoIcons: three, the pointer on OK
                .word BUTTON_OK_X * 8 + 24
                .byte BUTTON_Y + 8
                .word OkIcon
                .byte BUTTON_OK_X, BUTTON_Y, 6, 16
                .word DoOk
                .word CancelIcon
                .byte BUTTON_OK_X + 6, BUTTON_Y, 6, 16
                .word DoCancel
                .word SaveIcon
                .byte BUTTON_OK_X + 12, BUTTON_Y, 6, 16
                .word DoSave
BUTTON_OK_X     = 21                    ; (cards: OK 21, Cancel 27, Save 33)

LeaveDlg:       .byte DEF_DB_POS | 1
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
                .word LeaveText
                .byte YES, 1, DBI_Y_2
                .byte NO, DBI_X_2, DBI_Y_2
                .byte 0
LeaveText:      .byte BOLDON, "Leave without saving?", PLAINTEXT, 0
FailDlg:        .byte DEF_DB_POS | 1
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
                .word FailText
                .byte OK, 1, DBI_Y_2
                .byte 0
FailText:       .byte BOLDON, "Not saved: error $"
FailHex:        .byte "00", PLAINTEXT, 0
RoomDlg:        .byte DEF_DB_POS | 1
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
                .word RoomText
                .byte OK, 1, DBI_Y_2
                .byte 0
RoomText:       .byte BOLDON, "SETTINGS.INI is full.", PLAINTEXT, 0

        .include "okicon.inc"
        .include "cancelicon.inc"
        .include "saveicon.inc"

        .include "ini.inc"
        .include "inifile.inc"

        .segment "BSS"

page:           .res 1          ; the page shown (PAGE_*)
at:             .res 1
dirty:          .res 1          ; something changed since the last write
noFile:         .res 1          ; nothing to write (no Ultimate)
iniText:        .res INI_MAX + 1 ; SETTINGS.INI's text and its zero
