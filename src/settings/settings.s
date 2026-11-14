; GeoUltra Settings (docs/SETTINGS.md): the core. The start, the frame
; (title, the side list of pages, OK, Cancel and Save), the pages handed
; to their overlays (ovl.s), and SETTINGS.INI: read whole at the start
; (src/inc/inifile.inc), changed in memory by the pages (ini.inc,
; choice.s), written on OK or Save. Without an Ultimate (VICE) nothing
; is read or written: the pages show their defaults. Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import FirstLoad, ReadChrome, Colours, PageColours
        .import TitleBar, MarkOn, MarkOff, RowTop, Dialog
        .import OvlInit, DeskDraw, DeskPress, PtrDraw, PtrPress, SysDraw, SysPress
        .import TimeDraw, TimePress, ThemeDraw, ThemePress, ReuDraw, ReuPress
        .export FileEngine, dirty, NoRoom, Write, UseSettings, UseTheme, themeDirty
        .export themeLoaded, themeNo, themeCount, themePart, themeNames
        .export themePath, themeTmp, noFile, DrawPage, page, repaint, BarOn, BarOff, ThemesFull, Ask2
        .import row
        .importzp SWATCH_X        ; (152: exported as zero page)
        .export IniPaths, IniLoad, IniEmpty, IniSet, IniFind, iniLen, iniPath

        .segment "ZEROPAGE"

feVec:          .res 2          ; the file engine's entry
pageVec:        .res 2          ; DrawPage, Press: the page's routine

        .segment "CODE"

; (ini.inc and inifile.inc are included at the end: Start stays at
; $0400, where GEOS starts the application.)

; Start: SETTINGS.INI read, the screen drawn on the Desktop page, the
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
        lda #0
        sta repaint
        jsr FirstLoad           ; (chrome.s: the theme in use, its chrome)
        jsr ReadChrome
        jsr UseSettings
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
        sta iniSkip             ; (ini.inc resets it after each call, but
                                ; the first one found BSS's leftovers: on
                                ; the U64 the first row read was wrong,
                                ; 2026-11-13)
        sta curText
        sta themeDirty
        sta themeLoaded
        jsr UseSettings
        lda #0
        sta dirty
        sta noFile
        jsr SettingsPaths
        bcs @none
        jsr IniLoad
        txa
        beq @end
@none:  inc noFile
        lda #0                  ; (an empty text: the defaults)
        sta iniLen
        sta iniLen+1
        jmp IniEmpty
@end:   rts

; SettingsPaths: inifile.inc's paths for SETTINGS.INI (C set: no home
; folder, no Ultimate).
SettingsPaths:
        lda #<IniName
        sta r0L
        lda #>IniName
        sta r0H
        lda #<TmpName
        sta r1L
        lda #>TmpName
        sta r1H
        jmp IniPaths

; UseSettings, UseTheme: ini.inc on SETTINGS.INI's text (iniText) or
; the theme file's (themeText; the Theme page): the other one's length
; kept (curText the one in use). Destroy A, X.
UseSettings:
        ldx #0
        beq Use
UseTheme:
        ldx #1
Use:    cpx curText
        beq @set
        lda iniLen              ; the length of the one left
        ldy curText
        sta textLenLo,y
        lda iniLen+1
        sta textLenHi,y
        stx curText
        lda textLenLo,x
        sta iniLen
        lda textLenHi,x
        sta iniLen+1
@set:   lda TextLo,x
        sta iniBase
        lda TextHi,x
        sta iniBase+1
        lda MaxLo,x
        sta iniMax
        lda MaxHi,x
        sta iniMax+1
        rts
TextLo: .byte <iniText, <themeText
TextHi: .byte >iniText, >themeText
MaxLo:  .byte <INI_MAX, <THEME_MAX
MaxHi:  .byte >INI_MAX, >THEME_MAX

; --- drawing

; DrawAll: the whole screen in the theme (chrome.s): cleared, the
; colours, a frame round it, the title bar, the lines between the parts,
; the side list, the page.
DrawAll:
        lda #0
        jsr SetPattern
        jsr Screen
        jsr Rectangle
Repaint:                        ; (the Theme page's "use": the buttons'
        jsr Colours             ; strip keeps DoIcons's buttons)
        jsr Screen
        lda #$FF
        jsr FrameRectangle
        jsr TitleBar
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

; Screen: r2-r4 = the whole screen.
Screen: lda #0
        sta r2L
        sta r3L
        sta r3H
        lda #199
        sta r2H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        rts

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

; DrawSide: the page names, the current one marked (chrome.s MarkOn).
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
        jmp MarkOn

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
        lda #<(SCREEN_RIGHT - 1)  ; (inside the frame)
        sta r4L
        lda #>(SCREEN_RIGHT - 1)
        sta r4H
        jsr Rectangle
        jsr PageColours
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
        jsr MarkOff             ; marked, its page drawn
        lda at
        sta page
        jsr MarkOn
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
        jsr @go
        lda repaint             ; the Theme page's "use": all of it again
        beq @end                ; in the theme (from here: an overlay may
        lda #0                  ; not call one)
        sta repaint
        lda #0                  ; above the buttons' strip cleared
        jsr SetPattern
        jsr Screen
        lda #BUTTON_LINE - 1
        sta r2H
        jsr Rectangle
        jmp Repaint
@go:    jmp (pageVec)
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
        ora themeDirty
        beq @leave
        lda #<LeaveDlg
        ldx #>LeaveDlg
        jsr Plain
        cmp #YES
        beq @leave
        rts
@leave: jmp EnterDeskTop

; Write: SETTINGS.INI written when changed (inifile.inc IniSave). C set
; when it failed (the error shown).
Write:  lda noFile              ; (no Ultimate: nothing to write)
        bne @ok
        lda dirty
        beq @theme
        jsr UseSettings         ; SETTINGS.INI (its paths again: the theme's
        jsr SettingsPaths       ; took inifile.inc's)
        jsr IniSave
        txa
        bne @fail
        lda #0
        sta dirty
@theme: lda themeDirty          ; the theme file (the Theme page)
        beq @ok
        jsr UseTheme
        lda #<themePath
        sta r0L
        lda #>themePath
        sta r0H
        lda #<themeTmp
        sta r1L
        lda #>themeTmp
        sta r1H
        jsr IniPaths
        jsr IniSave
        stx at                  ; (its error, across the switch back)
        jsr UseSettings
        ldx at
        txa
        bne @fail
        lda #0
        sta themeDirty
@ok:    jsr UseSettings
        clc
        rts
@fail:  jsr Hex                 ; "Not saved: error $xx"
        lda #<FailDlg
        ldx #>FailDlg
        jsr Plain
        sec
        rts

; Ask2 (the Theme page's questions, ptheme.s): the dialog at A/X over the
; page's plain colours, r5 (NameDlg's input) kept; A = its answer. The
; caller draws its part again (moved here from the page: its overlay is
; full).
Ask2:   pha
        txa
        pha
        lda r5L
        pha
        lda r5H
        pha
        jsr PageColours
        pla
        sta r5H
        pla
        sta r5L
        pla
        sta r0H
        pla
        sta r0L
        jmp Dialog              ; (chrome.s: over the desk's colours)

; ThemesFull (the Theme page's copy): no room for another theme file.
ThemesFull:
        lda #<FullDlg
        ldx #>FullDlg
        jmp Plain

; NoRoom (choice.s): the INI text is full; the change is not made.
NoRoom: lda #<RoomDlg
        ldx #>RoomDlg
        ; (falls into Plain)

; BarOn, BarOff (the Theme page's swatch rows, ptheme.s): a one-pixel
; frame round card row `row`'s 16 swatches drawn or taken away, just
; outside their cells (in the page's colours), so a swatch in the
; page's own colour shows too (the user, 2026-11-13). Destroys A, r2-r4.
BarOn:  lda #$FF
        bne BarFrame
BarOff: lda #0
BarFrame:
        pha
        lda row
        asl a
        asl a
        asl a
        sta r2H                 ; (the row's top)
        sec
        sbc #1
        sta r2L
        lda r2H
        clc
        adc #8
        sta r2H
        lda #<(SWATCH_X - 1)
        sta r3L
        lda #>(SWATCH_X - 1)
        sta r3H
        lda #<(SWATCH_X + 8 * 16)
        sta r4L
        lda #>(SWATCH_X + 8 * 16)
        sta r4H
        pla
        jmp FrameRectangle

; Plain: the dialog at A/X over the page's plain colours (a dialog draws
; no colours: the Theme page's swatches and preview showed through; the
; user's test 2026-11-13), then the page drawn again; A = the answer.
Plain:  pha
        txa
        pha
        jsr PageColours
        pla
        sta r0H
        pla
        sta r0L
        jsr Dialog              ; (chrome.s: over the desk's colours)
        pha
        jsr DrawPage
        pla
        rts

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

SIDE_X          = 6
SIDE_BASE       = 11            ; a page name's baseline below its row top

; Each page's drawing and click routines (stubs into its overlay, ovl.s;
; Later and NoPress for the pages still to come), in PAGE_* order.
DrawLo:         .byte <ThemeDraw, <DeskDraw, <SysDraw, <TimeDraw, <Later, <ReuDraw
                .byte <PtrDraw
DrawHi:         .byte >ThemeDraw, >DeskDraw, >SysDraw, >TimeDraw, >Later, >ReuDraw
                .byte >PtrDraw
PressLo:        .byte <ThemePress, <DeskPress, <SysPress, <TimePress, <NoPress, <ReuPress
                .byte <PtrPress
PressHi:        .byte >ThemePress, >DeskPress, >SysPress, >TimePress, >NoPress, >ReuPress
                .byte >PtrPress
        .assert * - PressHi = PAGES_N, error, "a press routine per page"

NameLo:         .byte <N0, <N1, <N2, <N3, <N4, <N5, <N6
NameHi:         .byte >N0, >N1, >N2, >N3, >N4, >N5, >N6
N0:             .byte "Theme", 0
N1:             .byte "Desktop", 0
N2:             .byte "System", 0
N3:             .byte "Time", 0
N4:             .byte "Drives", 0
N5:             .byte "REU", 0
N6:             .byte "Pointer", 0
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
FullDlg:        .byte DEF_DB_POS | 1
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
                .word FullText
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
                .word FullText2
                .byte OK, 1, DBI_Y_2
                .byte 0
FullText:       .byte BOLDON, "Room for 10 themes.", PLAINTEXT, 0
FullText2:      .byte "Delete one first.", 0
        .assert THEMES_MAX = 10, error, "FullText: the number"

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
themeText:      .res THEME_MAX + 1 ; a theme file's text (the Theme page)
repaint:        .res 1          ; the Theme page's "use": DrawAll after its
                                ; click (Press)
curText:        .res 1          ; ini.inc's text: 0 SETTINGS.INI, 1 the theme
textLenLo:      .res 2          ; the other text's length while one is used
textLenHi:      .res 2
themeDirty:     .res 1          ; the theme's text changed since written
themeLoaded:    .res 1          ; the Theme page read its theme (once)
themeNo:        .res 1          ; the theme shown (themeNames)
themeCount:     .res 1          ; theme files listed
themePart:      .res 1          ; the part shown (themedef.inc's lines)
themeNames:     .res THEMES_MAX * THEME_NAME ; the theme files' names
themePath:      .res THEME_NAME + 11 ; "THEMES/<name>.ini" (inifile.inc),
themeTmp:       .res THEME_NAME + 11 ; "THEMES/<name>.tmp"
