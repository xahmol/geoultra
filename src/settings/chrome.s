; GeoUltra Settings: the theme in the core (docs/SETTINGS.md). The
; theme files (THEMES/<name>.ini) listed and read, their lines parsed
; (moved here from the Theme page, ptheme.s, 2026-11-14: Settings now
; draws itself in the theme in use, and the Theme page's overlay was
; full), and Settings' own screen in that theme: the title bar in the
; theme's title bar style and colours, the side list in the side bar's,
; its current page marked as the theme's selection, the page in the
; desk's colours, the buttons' strip in the menu bar's, the border
; (the user, 2026-11-13). Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"
        .include "hw.inc"

        .import FileEngine, IniFind, IniPaths, IniLoad, IniEmpty, iniLen
        .import UseSettings, UseTheme, themeDirty, themeLoaded, themeNo
        .import themeCount, themePart, themeNames, themePath, themeTmp, noFile
        .import KeyLo, KeyHi, LColKind, WordsLo, WordsHi, ColourNames
        .importzp CK_NONE, CK_PAPER
        .import TextWidth, page, iniPath

        .export FirstLoad, InUse, DeleteTheme, AddName, NameAt, LoadTheme
        .export ThemePaths, ReadLine, LineKey, HasWords
        .export NextWord, Colour
        .export OnText, SDesktop, KTheme, STheme
        .export tmp, idx, line, style, ink, paper, name
        .export val, buf, pbuf
        .exportzp vp
        .export ReadChrome, Colours, PageColours, TitleBar
        .export MarkOn, MarkOff, RowTop, Dialog
        .export cColour, iType

; The theme's lines the chrome reads (themedef.inc's order), C_* their
; places in cStyle and cColour.
C_BORDER        = 0
C_DESK          = 1
C_MENU          = 2
C_SIDE          = 3
C_TITLE         = 4
C_SEL           = 5
CHROME_N        = 6
T_SOLID         = 1             ; titlebar's words: stripes, solid, line,
T_LINE          = 2             ; none
S_BAR           = 1             ; selection's: invert, bar, frame
S_FRAME         = 2
TITLE_LEFT      = 8             ; line, none: the title's x
BOLD_EXTRA      = 17            ; the title's width in bold over plain (a
                                ; pixel per character)
DB_CARD_L       = 8             ; DEF_DB_POS: x 64-255, y 32-127, and its
DB_CARD_R       = 32            ; shadow (8 more): its cards
DB_ROW_T        = 4
DB_ROW_B        = 16

        .segment "ZEROPAGE"

vp:             .res 2          ; a word or a name being walked

        .segment "CODE"

; --- the theme: its file, its name

; FirstLoad: the theme files listed (THEMES), the one SETTINGS.INI uses
; ([desktop] theme=; none: GeoUltra) chosen and read.
FirstLoad:
        jsr ListThemes
        jsr UsedName
@find:  ldx #0                  ; its place in the list (or added)
@try:   cpx themeCount
        bcs @add
        stx themeNo
        jsr SameName
        bcc @load
        ldx themeNo
        inx
        bne @try
@add:   jsr AddName
@load:  lda #1
        sta themeLoaded
        lda #0
        sta themePart
        sta iType               ; (BSS: not cleared at the start)
        jmp LoadTheme

; UsedName: name = the theme in use (SETTINGS.INI [desktop] theme=;
; none, or too long: GeoUltra). Leaves SETTINGS.INI's text in use.
UsedName:
        jsr UseSettings
        lda #<SDesktop
        sta r0L
        lda #>SDesktop
        sta r0H
        lda #<KTheme
        sta r1L
        lda #>KTheme
        sta r1H
        jsr IniFind
        bcs @default
        cmp #THEME_NAME
        bcs @default
        tay
        lda #0
        sta name,y
@ch:    dey
        bmi @end
        lda (r2),y
        sta name,y
        jmp @ch
@default:
        ldx #0
@def:   lda DefaultName,x
        sta name,x
        beq @end
        inx
        bne @def
@end:   rts

; InUse: C clear when themeNames[themeNo] is the theme in use. Leaves
; the theme's text in use; name the theme in use.
InUse:  jsr UsedName
        jsr UseTheme
        jmp SameName

; DeleteTheme: THEMES/<themeNames[themeNo]>.ini deleted (themePath and
; themeTmp set to it). X = 0 or the error (no home folder: FE_ULTIMATE).
DeleteTheme:
        jsr ThemePaths
        lda #<themePath
        sta r0L
        lda #>themePath
        sta r0H
        lda #<themeTmp
        sta r1L
        lda #>themeTmp
        sta r1H
        jsr IniPaths
        ldx #FE_ULTIMATE
        bcs @end
        lda #<iniPath
        sta r0L
        lda #>iniPath
        sta r0H
        lda #FE_DELETE
        jmp FileEngine
@end:   rts

; ListThemes: themeNames = the THEMES folder's files ("<name>.ini", up
; to THEMES_MAX), themeCount their number; none without an Ultimate.
ListThemes:
        lda #0
        sta themeCount
        lda #<buf               ; the home folder
        sta r1L
        lda #>buf
        sta r1H
        lda #0
        sta buf
        lda #FE_HOME
        jsr FileEngine
        txa
        bne @end
        ldy #$FF                ; + "THEMES"
@home:  iny
        lda buf,y
        bne @home
        ldx #0
@dir:   lda ThemesDir,x
        sta buf,y
        beq @open
        iny
        inx
        bne @dir
@open:  lda #<buf
        sta r0L
        lda #>buf
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        bne @end
@read:  lda themeCount
        cmp #THEMES_MAX
        bcs @close
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<name
        sta r2L
        lda #>name
        sta r2H
        lda #0
        sta r3L
        sta r3H
        lda #FE_READDIR
        ldy handle
        jsr FileEngine
        txa
        bne @close
        jsr IniName             ; "x.ini": its name to the list
        bcs @read
        jsr AddName
        jmp @read
@close: lda #FE_CLOSE
        ldy handle
        jsr FileEngine
@end:   rts

; IniName: C clear when name ends in ".ini" (any case): that cut off.
IniName:
        ldy #$FF
@end:   iny
        lda name,y
        bne @end
        cpy #5
        bcc @no
        ldx #2                  ; ("ini" backwards)
@ext:   dey
        lda name,y
        ora #$20
        cmp IniExt,x
        bne @no
        dex
        bpl @ext
        dey                     ; (the ".")
        lda name,y
        cmp #'.'
        bne @no
        lda #0
        sta name,y
        clc
        rts
@no:    sec
        rts

; AddName: name (zero-ended, THEME_NAME at most) as the list's next one
; (when there is room); themeNo = it.
AddName:
        lda themeCount
        cmp #THEMES_MAX
        bcs @end
        sta themeNo
        jsr NameAt
        ldy #0
@ch:    lda name,y
        sta (vp),y
        beq @done
        iny
        cpy #THEME_NAME - 1
        bcc @ch
        lda #0
        sta (vp),y
@done:  inc themeCount
@end:   rts

; SameName: C clear when themeNames[themeNo] is name (any case).
SameName:
        jsr NameAt
        ldy #$FF
@ch:    iny
        lda (vp),y
        beq @end                ; (the list's name ends: name's too?)
        ora #$20
        sta tmp
        lda name,y
        beq @no
        ora #$20
        cmp tmp
        beq @ch
@no:    sec
        rts
@end:   lda name,y
        bne @no
        clc
        rts

; NameAt: vp = themeNames[themeNo].
NameAt: lda themeNo
        asl a
        asl a
        asl a
        asl a                   ; (THEME_NAME 16)
        clc
        adc #<themeNames
        sta vp
        lda #>themeNames
        adc #0
        sta vp+1
        rts
        .assert THEME_NAME = 16, error, "NameAt: * 16"

; LoadTheme: themePath/themeTmp for themeNames[themeNo], its file read
; into the theme's text (not there, no Ultimate: an empty text);
; themeDirty cleared.
LoadTheme:
        jsr ThemePaths
        jmp ReadTheme

; ThemePaths: themePath, themeTmp for themeNames[themeNo].
ThemePaths:
        jsr NameAt
        ldx #0                  ; "THEMES/" name ".ini" and ".tmp"
@dir:   lda ThemesDir,x
        beq :+
        sta themePath,x
        sta themeTmp,x
        inx
        bne @dir
:       lda #'/'
        sta themePath,x
        sta themeTmp,x
        inx
        ldy #0
@name:  lda (vp),y
        beq @ext
        sta themePath,x
        sta themeTmp,x
        inx
        iny
        bne @name
@ext:   ldy #0
@e:     lda IniDot,y
        sta themePath,x
        lda TmpDot,y
        sta themeTmp,x
        beq @end
        inx
        iny
        bne @e
@end:   rts

; ReadTheme: the theme's file (themePath) into its text (not there, no
; Ultimate: an empty text); themeDirty cleared.
ReadTheme:
        jsr UseTheme
        lda #0
        sta themeDirty
        sta iniLen
        sta iniLen+1
        jsr IniEmpty
        lda noFile
        bne @end
        lda #<themePath
        sta r0L
        lda #>themePath
        sta r0H
        lda #<themeTmp
        sta r1L
        lda #>themeTmp
        sta r1H
        jsr IniPaths
        bcs @end
        jsr IniLoad
@end:   rts

; ReadLine: style, ink, paper of line A from the current text (a line
; missing: its first style, dark grey on light grey).
ReadLine:
        sta line
        lda #0
        sta style
        lda #DEF_INK
        sta ink
        lda #DEF_PAPER
        sta paper
        jsr LineKey
        jsr IniFind             ; (r2 its value, A its length)
        bcs @end
        cmp #VAL_MAX
        bcc :+
        lda #VAL_MAX
:       tay                     ; the value, lower case, to val
        lda #0
        sta val,y
@ch:    dey
        bmi @parse
        lda (r2),y
        cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       sta val,y
        jmp @ch
@parse: ldy #0
        jsr HasWords
        beq @colours
        jsr Word                ; the style: its word's index
        bcs :+
        sta style
:       jsr Past                ; (to after ", ")
@colours:
        ldx line
        lda LColKind,x
        cmp #CK_NONE
        beq @end
        jsr Colour              ; the first colour (Y: the place in val)
        bcs @end
        pha
        ldx line
        lda LColKind,x
        cmp #CK_PAPER
        bne :+
        pla
        sta paper
        rts
:       pla
        sta ink
        jsr OnWord              ; " on " and the second
        bcs @end
        jsr Colour
        bcs @end
        sta paper
@end:   rts

; LineKey: r0 = "theme", r1 = line's key.
LineKey:
        lda #<STheme
        sta r0L
        lda #>STheme
        sta r0H
        ldx line
        lda KeyLo,x
        sta r1L
        lda KeyHi,x
        sta r1H
        rts

; HasWords: Z clear when line has style words (themedef.inc).
HasWords:
        ldx line
        lda WordsLo,x
        sta vp
        lda WordsHi,x
        sta vp+1
        sty tmp
        ldy #0
        lda (vp),y
        ldy tmp
        cmp #0
        rts

; Word: A = the index of the word of line's list (vp) at val + Y (to
; its "," or end), Y past it; C set when none matches.
Word:   sty start
        lda #0
        sta idx
@word:  ldy #0
        lda (vp),y
        beq @none               ; (the list's end)
        ldx start
@ch:    lda (vp),y
        beq @end
        cmp val,x
        bne @skip
        inx
        iny
        bne @ch
@end:   lda val,x               ; (the text's word ends here too)
        beq @yes
        cmp #','
        beq @yes
@skip:  jsr NextWord
        inc idx
        jmp @word
@yes:   txa
        tay
        lda idx
        clc
        rts
@none:  ldy start
        sec
        rts

; NextWord: vp past its word and the word's zero.
NextWord:
        ldy #0
@ch:    lda (vp),y
        iny
        cmp #0
        bne @ch
        tya
        clc
        adc vp
        sta vp
        bcc :+
        inc vp+1
:       rts

; Past: Y past "," and the spaces after it.
Past:   lda val,y
        beq @end
        iny
        cmp #','
        bne Past
@sp:    lda val,y
        cmp #' '
        bne @end
        iny
        bne @sp
@end:   rts

; Colour: A = the colour named at val + Y (to " on " or the end), Y
; past it; C set when no name matches.
Colour: sty start
        lda #0
        sta idx
        lda #<ColourNames
        sta vp
        lda #>ColourNames
        sta vp+1
@name:  ldy #0
        lda (vp),y
        beq @none
        ldx start
@ch:    lda (vp),y
        beq @end
        cmp val,x
        bne @skip
        inx
        iny
        bne @ch
@end:   lda val,x               ; (the text's name ends here too)
        beq @yes
        cmp #' '
        beq @yes
@skip:  jsr NextWord
        inc idx
        jmp @name
@yes:   txa
        tay
        lda idx
        clc
        rts
@none:  ldy start
        sec
        rts

; OnWord: Y past " on "; C set when it is not there.
OnWord: ldx #0
@ch:    lda OnText,x
        beq @yes
        cmp val,y
        bne @no
        inx
        iny
        bne @ch
@yes:   clc
        rts
@no:    sec
        rts


; --- Settings in the theme

; ReadChrome: the chrome's styles and colours from the theme's text (the
; theme in use: FirstLoad at the start, the Theme page's "use"); a line
; missing: its first style, dark grey on light grey. Leaves the theme's
; text in use. Destroys A, X, Y, r0-r2.
ReadChrome:
        jsr UseTheme
        ldx #CHROME_N - 1
@line:  stx cAt
        lda ChromeLine,x
        jsr ReadLine
        ldx cAt
        lda style
        sta cStyle,x
        lda ink                 ; ink << 4 | paper, as the colour matrix
        asl a
        asl a
        asl a
        asl a
        ora paper
        sta cColour,x
        dex
        bpl @line
        rts

; Colours: the border and every part's colour cells (title bar, side
; list with its mark, page, buttons' strip). Destroys A, X, Y, r0.
Colours:
        lda cColour + C_BORDER  ; the border: the line's paper
        and #$0F
        tax
        php
        sei
        lda CPU_PORT
        pha
        lda #$35                ; (I/O in)
        sta CPU_PORT
        stx $D020
        pla
        sta CPU_PORT
        plp
        lda cColour + C_TITLE   ; the title bar (rows 0-1); solid: swapped,
        ldx cStyle + C_TITLE    ; as it is drawn inverted
        cpx #T_SOLID
        bne :+
        jsr Swap
:       ldx #0
        ldy #39
        jsr Columns
        lda #0
        sta py0
        lda #1
        sta py1
        jsr Paint
        lda cColour + C_MENU    ; the buttons' strip (rows 22-24)
        ldx #0
        ldy #39
        jsr Columns
        lda #22
        sta py0
        lda #24
        sta py1
        jsr Paint
        jsr SideColours
        ; (falls into PageColours)

; PageColours: the page area's colour cells (rows 2-21, cards 11-39) in
; the desk's colours (the Theme page colours its own). Destroys A, X, Y,
; r0.
PageColours:
        lda cColour + C_DESK
        ldx #PAGE_CARD
        ldy #39
        bne Rows2to21

; SideColours: the side list's cells (rows 2-21, cards 0-10) in the side
; bar's colours, the current page's row in the selection's. Destroys
; A, X, Y, r0.
SideColours:
        lda cColour + C_SIDE
        ldx #0
        ldy #PAGE_CARD - 1
        jsr Rows2to21
        lda page
        jmp MarkCells

; Rows2to21: cards X-Y of rows 2-21 in colour A.
Rows2to21:
        jsr Columns
        lda #2
        sta py0
        lda #21
        sta py1
        jmp Paint

; Columns: pcol = A, px0 = X, px1 = Y.
Columns:
        sta pcol
        stx px0
        sty px1
        rts

; Paint: the colour cells of cards px0-px1, rows py0-py1, in pcol.
; Destroys A, X, Y, r0.
Paint:  lda #<COLOR_MATRIX
        sta r0L
        lda #>COLOR_MATRIX
        sta r0H
        ldx py0
        beq @rows
@down:  lda r0L                 ; (row py0's start)
        clc
        adc #40
        sta r0L
        bcc :+
        inc r0H
:       dex
        bne @down
@rows:  ldx py0
@row:   ldy px0
        lda pcol
@cell:  sta (r0),y
        cpy px1
        iny
        bcc @cell
        lda r0L
        clc
        adc #40
        sta r0L
        bcc :+
        inc r0H
:       cpx py1
        inx
        bcc @row
        rts

; Swap: A's ink and paper swapped (a part drawn inverted shows its
; colours the way round the theme says). Destroys nothing else.
Swap:   asl a                   ; (the known six-instruction nibble swap)
        adc #$80
        rol a
        asl a
        adc #$80
        rol a
        rts

; TitleBar: the title bar (y 0-15) with "GeoUltra Settings", by the
; theme's title bar style: stripes (every other line, a gap for the
; title, as GEOS windows), solid (inverted), line or none (the title in
; bold at the left; the line under the bar is DrawAll's). Destroys A,
; X, Y, r0-r4, r11.
TitleBar:
        lda cStyle + C_TITLE
        cmp #T_LINE
        bcc @mid
        lda #TITLE_LEFT
        sta r11L
        lda #0
        sta r11H
        jmp TitleText
@mid:   lda #<TitleW            ; its width (bold: a pixel more a
        sta r0L                 ; character)
        lda #>TitleW
        sta r0H
        jsr TextWidth
        clc
        adc #BOLD_EXTRA
        sta cTmp
        lda cStyle + C_TITLE
        bne @solid
        ldx #2                  ; stripes: lines 2, 4, ... 12
@stripe:
        stx r11L
        stx cAt
        jsr BarSpan
        lda #$FF
        jsr HorizontalLine
        ldx cAt
        inx
        inx
        cpx #TITLE_LINE - 1
        bcc @stripe
        lda #0                  ; a gap for the title
        jsr SetPattern
        jsr BarRows
        jsr TitleX
        lda r11L
        sec
        sbc #6
        sta r3L
        lda #0
        sta r3H
        sta r4H
        lda r11L
        clc
        adc cTmp
        adc #4
        sta r4L
        jsr Rectangle
        jsr TitleX
        jmp TitleText
@solid: jsr TitleX              ; solid: the title, then the bar inverted
        jsr TitleText
        jsr BarRows
        jsr BarSpan
        jmp InvertRectangle

; BarRows: r2L-r2H = the title bar inside the frame (y 1-13).
BarRows:
        lda #1
        sta r2L
        lda #TITLE_LINE - 2
        sta r2H
        rts

; BarSpan: r3-r4 = the screen inside the frame (x 1-318).
BarSpan:
        lda #1
        sta r3L
        lda #0
        sta r3H
        lda #<(SCREEN_RIGHT - 1)
        sta r4L
        lda #>(SCREEN_RIGHT - 1)
        sta r4H
        rts

; TitleX: r11 = the centred title's x (from cTmp, its width).
TitleX: lda cTmp
        lsr a
        sta r11L
        lda #160
        sec
        sbc r11L
        sta r11L
        lda #0
        sta r11H
        rts

; TitleText: the title in bold at r11, baseline TITLE_Y.
TitleText:
        lda #<Title
        sta r0L
        lda #>Title
        sta r0H
        lda #TITLE_Y
        sta r1H
        jmp PutString

; MarkOn, MarkOff: page A's name in the side list marked as the
; theme's selection (invert: inverted; bar: its colours only; frame: a
; frame round it), or back to normal. Destroys A, X, Y, r0, r2-r4.
MarkOn: sta cAt
        lda #$FF
        bne Mark
MarkOff:
        sta cAt
        lda #0
Mark:   sta cOn
        lda cAt
        jsr RowTop
        sta r2L
        clc
        adc #SIDE_ROW - 1
        sta r2H
        lda #1
        sta r3L
        lda #0
        sta r3H
        sta r4H
        lda #SIDE_W - 1
        sta r4L
        lda cStyle + C_SEL
        cmp #S_BAR
        beq @cells
        cmp #S_FRAME
        beq @frame
        jsr InvertRectangle     ; invert (both ways)
        jmp @cells
@frame: inc r2L                 ; (inside the row)
        dec r2H
        inc r3L
        dec r4L
        lda cOn
        jsr FrameRectangle
@cells: lda cOn
        beq @off
        lda cAt
        jmp MarkCells
@off:   lda cColour + C_SIDE
        ldx cAt
        jmp RowCells

; MarkCells: page A's row in the selection's colours (invert: swapped,
; unless they are the side list's own: no line, or the same colours,
; would hide the inverted mark).
MarkCells:
        tax
        lda cColour + C_SEL
        ldy cStyle + C_SEL
        bne RowCells            ; (S_INVERT 0)
        cmp cColour + C_SIDE
        beq RowCells
        jsr Swap
        ; (falls into RowCells)

; RowCells: page X's row (cards 0-9, its two card rows) in colour A.
RowCells:
        sta pcol
        txa
        jsr RowTop
        lsr a
        lsr a
        lsr a
        sta py0
        sta py1
        inc py1
        lda #0
        sta px0
        lda #SIDE_W / 8 - 1
        sta px1
        jmp Paint

; RowTop: A = page A's row top (SIDE_TOP + A * SIDE_ROW).
RowTop: tax
        lda #SIDE_TOP
@add:   dex
        bmi @end
        clc
        adc #SIDE_ROW
        bne @add
@end:   rts

; Dialog: DoDlgBox (r0 the dialog, at DEF_DB_POS) over the desk's
; colours (a dialog draws no colours: the side list's showed through
; it), the side list's colours back after; r0L and A its answer.
Dialog: lda cColour + C_DESK
        ldx #DB_CARD_L
        ldy #DB_CARD_R
        jsr Columns
        lda #DB_ROW_T
        sta py0
        lda #DB_ROW_B
        sta py1
        lda r0L
        pha
        lda r0H
        pha
        jsr Paint
        pla
        sta r0H
        pla
        sta r0L
        jsr DoDlgBox
        lda r0L
        pha
        jsr SideColours
        pla
        sta r0L
        rts


; --- data

SDesktop:       .byte "desktop", 0
KTheme:         .byte "theme", 0
STheme:         .byte "theme", 0
DefaultName:    .byte "GeoUltra", 0
ThemesDir:      .byte "THEMES", 0
IniDot:         .byte ".ini", 0
TmpDot:         .byte ".tmp", 0
IniExt:         .byte "ini"
                .byte 0
OnText:         .byte " on ", 0
ChromeLine:     .byte 0, 1, 2, 3, 5, 9 ; (C_* order: their lines)
Title:          .byte BOLDON
TitleW:         .byte "GeoUltra Settings", PLAINTEXT, 0

        .segment "BSS"

iType:          .res 1          ; the Theme page's icon colour by type shown
                                ; (0-5: its line LINE_ITYPES + iType; kept
                                ; here: the page's overlay is fetched anew)
cStyle:         .res CHROME_N   ; the chrome's styles (their words' index)
cColour:        .res CHROME_N   ; and colours (ink << 4 | paper)
cAt:            .res 1
cOn:            .res 1
cTmp:           .res 1
px0:            .res 1          ; Paint: cards px0-px1, rows py0-py1, pcol
px1:            .res 1
py0:            .res 1
py1:            .res 1
pcol:           .res 1
tmp:            .res 1          ; (the parser's and the loader's; the Theme
idx:            .res 1          ; page's too)
start:          .res 1
line:           .res 1          ; the line being read or written
style:          .res 1          ; its style (its word's index)
ink:            .res 1          ; its colours
paper:          .res 1
handle:         .res 1
info:           .res 16
name:           .res 64         ; a file's name (FE_READDIR), a theme's
val:            .res VAL_MAX + 1 ; a line's value
pbuf = name                     ; (the Theme page: palette='s value, 111
        .assert VAL_MAX + 1 + 64 >= 112, error, "pbuf: name and val"
                                ; and its zero, over name and val)
buf:            .res 48         ; the THEMES folder's path
