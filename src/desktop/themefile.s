; GeoUltra Desktop: theme files (docs/DESKTOP.md, "Look and themes";
; the user, 2026-11-11: every theme a file, the built-in ones editable,
; and a custom one). A theme is GEOULTRA/THEMES/<name>.ini, in words as
; the approved mock-up wrote it:
;
;   [theme]
;   name=GeoUltra
;   border=light blue
;   desk=dark grey on light grey
;   menubar=clock, dark grey on light grey
;   ...
;   status=on, white on grey
;
; ThemeFiles (at the desktop's start) makes THEMES with the six built-in
; themes and Custom (a copy of GeoUltra) when it is not there, and lists
; the files for the view menu (themeNames); ThemeLoad reads one into the
; theme record (theme.s; unknown lines and words left as they were, so
; a file only needs the lines it changes). Without an Ultimate (VICE)
; nothing is there: the built-in themes stay. Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, ThemeSet, ThemeName, ThemeByName, Derive, tMenu
        .import tCols, viewMode
        .export ThemeFiles, ThemeUse, themeNames, themeCount, curName

FO_READ_        = FO_READ
LINES_N         = 13            ; the file's lines after name=
NAME_MAX        = 15            ; a theme's name (and its zero)
THEMES_MAX      = 8             ; files the view menu lists
FILE_MAX        = 600           ; a theme file's bytes, at most
NO_STYLE        = $FF
CK_NONE         = 0             ; a line's colours: none,
CK_PAIR         = 1             ; ink on paper,
CK_INK          = 2             ; ink (on the area's paper),
CK_PAPER        = 3             ; paper only (the border)
REC_ROWS        = 4             ; tRows: 9 or 8, the words' index 0 or 1

        .segment "ZEROPAGE"

tp:             .res 2          ; the text being read or written

        .segment "CODE"

; ThemeFiles: THEMES made with the built-in themes and Custom when it is
; not there; themeNames = the files' names (themeCount, at most
; THEMES_MAX); none without a home folder. Destroys the theme record
; while writing (ThemeSet afterwards).
ThemeFiles:
        lda #0
        sta themeCount
        jsr Home
        bcs @end
        jsr List                ; (a missing folder on the Ultimate opens
        lda themeCount          ; and lists nothing: FE_OPENDIR fails only
        bne @end                ; at the first read)
        jsr Make
        jsr List
@end:   rts

; Make: THEMES made, each built-in theme written, then Custom (GeoUltra's
; record under its own name).
Make:   jsr DirPath
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #0
        sta r2L
        lda #FE_MKDIR
        jsr FileEngine          ; (an error left: it may be there, empty;
        lda #0                  ; a write that fails then fails alone)
        sta at
@theme: lda at
        jsr ThemeSet
        lda at
        jsr ThemeName           ; r1
        jsr NameFrom
        jsr Write
        inc at
        lda at
        cmp #THEMES_N
        bcc @theme
        lda #0
        jsr ThemeSet
        lda #<CustomName
        sta r1L
        lda #>CustomName
        sta r1H
        jsr NameFrom
        jmp Write

; NameFrom: curName = the name at r1 (cut at NAME_MAX - 1).
NameFrom:
        ldy #0
@ch:    lda (r1),y
        sta curName,y
        beq @end
        iny
        cpy #NAME_MAX - 1
        bcc @ch
        lda #0
        sta curName,y
@end:   rts

; List: themeNames = the .ini files in THEMES (their names without
; ".ini"). X = 0, or the error.
List:   jsr DirPath
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        beq @entry
        rts
@entry: lda #<info
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
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        lda themeCount
        cmp #THEMES_MAX
        bcs @entry              ; (full: the rest not listed)
        jsr IniName             ; ".ini" cut off; C set: not one
        bcs @entry
        lda themeCount          ; to themeNames + count * NAME_MAX
        jsr NameSlot
        ldy #0
@ch:    lda name,y
        sta (tp),y
        beq @next
        iny
        cpy #NAME_MAX - 1
        bcc @ch
        lda #0
        sta (tp),y
@next:  inc themeCount
        jmp @entry
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        ldx #0
        rts

; NameSlot: tp = themeNames + A * NAME_MAX.
NameSlot:
        tax
        lda #<themeNames
        sta tp
        lda #>themeNames
        sta tp+1
@add:   dex
        bmi @end
        lda tp
        clc
        adc #NAME_MAX
        sta tp
        bcc @add
        inc tp+1
        bne @add
@end:   rts

; IniName: name ends in ".ini" (any case): cut there, C clear; else C
; set.
IniName:
        ldy #0
@len:   lda name,y
        beq @end
        iny
        bne @len
@end:   cpy #5
        bcc @no
        lda name-4,y
        cmp #'.'
        bne @no
        lda name-3,y
        ora #$20
        cmp #'i'
        bne @no
        lda name-2,y
        ora #$20
        cmp #'n'
        bne @no
        lda name-1,y
        ora #$20
        cmp #'i'
        bne @no
        lda #0
        sta name-4,y
        clc
        rts
@no:    sec
        rts

; --- Reading ---------------------------------------------------------------

; ThemeUse: the theme named at r0 in use: the built-in theme of that
; name (else GeoUltra) as the start, its file read on top when there is
; one (an edited built-in theme, or Custom), the view its columns say;
; curName = the name.
ThemeUse:
        lda r0L
        sta r1L
        lda r0H
        sta r1H
        jsr NameFrom
        lda #<curName
        sta r0L
        lda #>curName
        sta r0H
        jsr ThemeByName         ; (theme.s; C set: none of that name)
        bcc :+
        lda #0
        jsr ThemeSet
:       lda #<curName
        sta r0L
        lda #>curName
        sta r0H
        jsr ThemeLoad           ; (C set: no file; the built-in stays)
        lda #VIEW_LIST
        ldx tCols
        beq :+
        lda #VIEW_DETAILED
:       sta viewMode
        rts

; ThemeLoad: the theme file of the name at r0 read into the record (on
; top of what is there: start from a built-in theme), its layout
; derived; curName = the name. C set when it could not be read.
ThemeLoad:
        lda r0L
        sta r1L
        lda r0H
        sta r1H
        jsr NameFrom
        jsr Home
        bcs @fail
        jsr FilePath
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FO_READ_
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        txa
        bne @fail
        lda #<buf
        sta r1L
        lda #>buf
        sta r1H
        lda #<FILE_MAX
        sta r2L
        lda #>FILE_MAX
        sta r2H
        ldy handle
        lda #FE_READ
        jsr FileEngine
        lda r2L                 ; its end: a zero after it
        clc
        adc #<buf
        sta tp
        lda r2H
        adc #>buf
        sta tp+1
        ldy #0
        tya
        sta (tp),y
        txa
        pha
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        pla
        bne @fail
        lda #<buf
        sta tp
        lda #>buf
        sta tp+1
@line:  jsr Line
        jsr NextLine
        bcc @line
        jsr Derive
        clc
        rts
@fail:  sec
        rts

; NextLine: tp past the line's end (LF or CR); C set at the text's end.
NextLine:
        ldy #0
@ch:    lda (tp),y
        beq @end
        jsr Step
        cmp #10
        beq @next
        cmp #CR
        bne @ch
@next:  lda (tp),y              ; (CR LF: both)
        cmp #10
        bne :+
        jsr Step
:       clc
        rts
@end:   sec
        rts

; Step: tp one on. Keeps A.
Step:   inc tp
        bne :+
        inc tp+1
:       rts

; Line: the line at tp, when its key is one of Keys: its style word and
; colours into the record. tp stays at the line's start.
Line:   lda tp
        sta lineAt
        lda tp+1
        sta lineAt+1
        ldx #0                  ; each line kind
@kind:  stx kind
        jsr KeyMatch            ; tp after "key=" when it matches
        bcc @found
        lda lineAt
        sta tp
        lda lineAt+1
        sta tp+1
        ldx kind
        inx
        cpx #LINES_N
        bcc @kind
        rts
@found: ldx kind
        lda LStyle,x            ; a style word first?
        cmp #NO_STYLE
        beq @colour
        jsr StyleWord           ; A = its index, C set: none
        bcs @colour
        ldx kind
        ldy LStyle,x
        cpy #REC_ROWS           ; (rows: 9 or 8 as such)
        bne :+
        tax
        lda RowsVal,x
:       sta tMenu,y
        jsr Comma               ; ", " before the colours
@colour:
        ldx kind
        lda LColKind,x
        beq @back
        cmp #CK_PAIR
        bne @one
        jsr Colour              ; ink "on" paper
        bcs @back
        asl a
        asl a
        asl a
        asl a
        sta tmp
        jsr OnWord
        bcs @back
        jsr Colour
        bcs @back
        ora tmp
        jmp @store
@one:   jsr Colour              ; ink or paper alone: the number
        bcs @back
@store: ldx kind
        ldy LColour,x
        sta tMenu,y
@back:  lda lineAt
        sta tp
        lda lineAt+1
        sta tp+1
        rts

; KeyMatch: the line at tp starts with line kind X's key and "=": C
; clear, tp after them; else C set.
KeyMatch:
        lda KeyLo,x
        sta r1L
        lda KeyHi,x
        sta r1H
        ldy #0
@ch:    lda (r1),y
        beq @eq
        jsr LowAt
        cmp (r1),y
        bne @no
        iny
        bne @ch
@eq:    lda (tp),y
        cmp #'='
        bne @no
        iny
        jmp Skip
@no:    sec
        rts

; Skip: tp on by Y, then past spaces. C clear.
Skip:   tya
        clc
        adc tp
        sta tp
        bcc :+
        inc tp+1
:       ldy #0
@sp:    lda (tp),y
        cmp #' '
        bne @end
        jsr Step
        jmp @sp
@end:   clc
        rts

; LowAt: A = the character at tp + Y in lower case.
LowAt:  lda (tp),y
        cmp #'A'
        bcc @end
        cmp #'Z' + 1
        bcs @end
        ora #$20
@end:   rts

; StyleWord: A = the index of the word at tp among line kind `kind`'s
; style words; tp after it. C set when none matches.
StyleWord:
        ldx kind
        lda WordsLo,x
        sta r1L
        lda WordsHi,x
        sta r1H
        lda #0
        sta idx
        jmp Match

; Colour: A = the colour whose name is at tp (0-15); tp after it. C set
; when none matches.
Colour: lda #<ColourNames
        sta r1L
        lda #>ColourNames
        sta r1H
        lda #0
        sta idx
; Match: A = the index of the word at tp in the list at r1 (words
; zero-ended, a second zero after the last); the word at tp must end
; there (end, CR, LF, ",", " "). tp after it, C clear; C set when none.
Match:  ldy #0
@ch:    lda (r1),y
        beq @end
        jsr LowAt
        cmp (r1),y
        bne @next
        iny
        bne @ch
@end:   lda (tp),y              ; (the word ends here too)
        beq @yes
        cmp #CR
        beq @yes
        cmp #10
        beq @yes
        cmp #','
        beq @yes
        cmp #' '
        beq @yes
@next:  ldy #0                  ; past this word's zero
@skip:  lda (r1),y
        beq :+
        iny
        bne @skip
:       iny
        tya
        clc
        adc r1L
        sta r1L
        bcc :+
        inc r1H
:       inc idx
        ldy #0
        lda (r1),y
        bne Match
        sec
        rts
@yes:   jsr Skip
        lda idx
        rts

; Comma: tp past "," and spaces.
Comma:  ldy #0
        lda (tp),y
        cmp #','
        bne :+
        jsr Step
:       ldy #0
        jmp Skip

; OnWord: tp past "on" (and spaces); C set when it is not there.
OnWord: ldy #0
        jsr LowAt
        cmp #'o'
        bne @no
        iny
        jsr LowAt
        cmp #'n'
        bne @no
        iny
        jmp Skip
@no:    sec
        rts

; --- Writing ---------------------------------------------------------------

; Write: the theme record as THEMES/<curName>.ini (written anew). X = 0
; or the error.
Write:  lda #<buf
        sta tp
        lda #>buf
        sta tp+1
        lda #<HeadText          ; "[theme]", "name=" and the name
        ldx #>HeadText
        jsr Put
        lda #<curName
        ldx #>curName
        jsr Put
        jsr NewLine
        lda #0
        sta kind
@line:  ldx kind
        lda KeyLo,x
        pha
        lda KeyHi,x
        tax
        pla
        jsr Put
        lda #'='
        jsr PutCh
        ldx kind
        lda LStyle,x
        cmp #NO_STYLE
        beq @colour
        tay                     ; the style's word
        lda tMenu,y
        cpy #REC_ROWS           ; (rows: 9 or 8 to its index)
        bne :+
        lda #0
        ldx tRowsByte
        cpx #9
        beq :+
        lda #1
:       jsr StyleOut
        ldx kind
        lda LColKind,x
        beq @eol
        lda #','
        jsr PutCh
        lda #' '
        jsr PutCh
@colour:
        ldx kind
        lda LColKind,x
        beq @eol
        ldy LColour,x
        lda tMenu,y
        sta tmp
        lda LColKind,x
        cmp #CK_PAIR
        bne @one
        lda tmp                 ; ink "on" paper
        lsr a
        lsr a
        lsr a
        lsr a
        jsr ColourOut
        lda #<OnText
        ldx #>OnText
        jsr Put
        lda tmp
        and #$0F
        jsr ColourOut
        jmp @eol
@one:   lda tmp
        and #$0F
        jsr ColourOut
@eol:   jsr NewLine
        inc kind
        lda kind
        cmp #LINES_N
        bcs :+
        jmp @line
:       jsr FilePath            ; the file
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        txa
        bne @end
        lda #<buf
        sta r1L
        lda #>buf
        sta r1H
        lda tp
        sec
        sbc #<buf
        sta r2L
        lda tp+1
        sbc #>buf
        sta r2H
        ldy handle
        lda #FE_WRITE
        jsr FileEngine
        txa
        pha
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        pla
        tax
@end:   rts
tRowsByte = tMenu + REC_ROWS

; StyleOut: line kind `kind`'s style word A written.
StyleOut:
        sta idx
        ldx kind
        lda WordsLo,x
        sta r1L
        lda WordsHi,x
        sta r1H
        jmp WordOut

; ColourOut: colour A's name written.
ColourOut:
        sta idx
        lda #<ColourNames
        sta r1L
        lda #>ColourNames
        sta r1H
; WordOut: word idx of the list at r1 written.
WordOut:
        ldy #0
@find:  lda idx
        beq @put
@skip:  lda (r1),y
        iny
        cmp #0
        bne @skip
        dec idx
        jmp @find
@put:   lda (r1),y
        beq @end
        jsr PutCh
        iny
        bne @put
@end:   rts

; Put: the zero-ended text at A/X written; PutCh: A; NewLine: CR LF.
Put:    sta r2L
        stx r2H
        ldy #0
@ch:    lda (r2),y
        beq @end
        jsr PutCh
        iny
        bne @ch
@end:   rts
NewLine:
        lda #CR
        jsr PutCh
        lda #10
PutCh:  sty tmpY
        ldy #0
        sta (tp),y
        ldy tmpY
        jmp Step

; --- Paths -----------------------------------------------------------------

; Home: home = the home folder (FE_HOME, "/USB0/GEOULTRA/"); C set when
; there is none (no Ultimate).
Home:   lda #<home
        sta r1L
        lda #>home
        sta r1H
        lda #0
        sta home
        lda #FE_HOME
        jsr FileEngine
        txa
        bne @none
        lda home
        cmp #'/'
        bne @none
        clc
        rts
@none:  sec
        rts

; DirPath: path = home "THEMES". FilePath: home "THEMES/" curName ".ini".
DirPath:
        jsr HomeTo
        lda #<ThemesDir
        ldx #>ThemesDir
        jmp Append
FilePath:
        jsr DirPath
        lda #<Slash
        ldx #>Slash
        jsr Append
        lda #<curName
        ldx #>curName
        jsr Append
        lda #<IniExt
        ldx #>IniExt
        jmp Append

; HomeTo: path = home; X its end. Append: the text at A/X after path
; (X its end, kept current), cut at the buffer's end.
HomeTo: ldx #0
@ch:    lda home,x
        sta path,x
        beq @end
        inx
        cpx #HOME_LEN - 1
        bcc @ch
        lda #0
        sta path,x
@end:   stx pathEnd
        rts
Append: sta r2L
        stx r2H
        ldx pathEnd
        ldy #0
@ch:    lda (r2),y
        sta path,x
        beq @end
        inx
        iny
        cpx #PATH_BUF - 1
        bcc @ch
        lda #0
        sta path,x
@end:   stx pathEnd
        rts

; --- Tables ------------------------------------------------------------------

; The lines after name=, in the file's order: their keys, the record's
; style byte (NO_STYLE: none) with its words, the kind of colours and
; the record's colour byte (theme.s, Themes' order).
K_BORDER:       .byte "border", 0
K_DESK:         .byte "desk", 0
K_MENUBAR:      .byte "menubar", 0
K_SIDEBAR:      .byte "sidebar", 0
K_HEADINGS:     .byte "headings", 0
K_TITLEBAR:     .byte "titlebar", 0
K_ROWS:         .byte "rows", 0
K_COLUMNS:      .byte "columns", 0
K_ICONS:        .byte "icons", 0
K_SELECTION:    .byte "selection", 0
K_CURSOR:       .byte "cursor", 0
K_SCROLLBAR:    .byte "scrollbar", 0
K_STATUS:       .byte "status", 0
KeyLo:  .byte <K_BORDER, <K_DESK, <K_MENUBAR, <K_SIDEBAR, <K_HEADINGS
        .byte <K_TITLEBAR, <K_ROWS, <K_COLUMNS, <K_ICONS, <K_SELECTION
        .byte <K_CURSOR, <K_SCROLLBAR, <K_STATUS
KeyHi:  .byte >K_BORDER, >K_DESK, >K_MENUBAR, >K_SIDEBAR, >K_HEADINGS
        .byte >K_TITLEBAR, >K_ROWS, >K_COLUMNS, >K_ICONS, >K_SELECTION
        .byte >K_CURSOR, >K_SCROLLBAR, >K_STATUS
LStyle: .byte NO_STYLE, NO_STYLE, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
LColKind:
        .byte CK_PAPER, CK_PAIR, CK_PAIR, CK_PAIR, CK_PAIR, CK_PAIR
        .byte CK_NONE, CK_NONE, CK_INK, CK_PAIR, CK_INK, CK_NONE, CK_PAIR
LColour:                        ; (offsets from tMenu: 11 the border ...)
        .byte 11, 12, 13, 14, 15, 16, 0, 0, 17, 18, 19, 0, 20
W_NONE:         .byte 0
W_MENUBAR:      .byte "plain", 0, "clock", 0, 0
W_SIDEBAR:      .byte "wide", 0, "narrow", 0, 0
W_HEADINGS:     .byte "inverted", 0, "band", 0, "underlined", 0, "plain", 0, 0
W_TITLEBAR:     .byte "stripes", 0, "solid", 0, "line", 0, "none", 0, 0
W_ROWS:         .byte "9", 0, "8", 0, 0
W_COLUMNS:      .byte "name", 0, "detailed", 0, 0
W_ONOFF:        .byte "on", 0, "off", 0, 0
W_SELECTION:    .byte "invert", 0, "bar", 0, "frame", 0, 0
W_CURSOR:       .byte "dotted", 0, "mark", 0, "underline", 0, 0
W_SCROLLBAR:    .byte "arrows", 0, "thin", 0, 0
WordsLo:        .byte <W_NONE, <W_NONE, <W_MENUBAR, <W_SIDEBAR, <W_HEADINGS
                .byte <W_TITLEBAR, <W_ROWS, <W_COLUMNS, <W_ONOFF, <W_SELECTION
                .byte <W_CURSOR, <W_SCROLLBAR, <W_ONOFF
WordsHi:        .byte >W_NONE, >W_NONE, >W_MENUBAR, >W_SIDEBAR, >W_HEADINGS
                .byte >W_TITLEBAR, >W_ROWS, >W_COLUMNS, >W_ONOFF, >W_SELECTION
                .byte >W_CURSOR, >W_SCROLLBAR, >W_ONOFF
RowsVal:        .byte 9, 8
ColourNames:    .byte "black", 0, "white", 0, "red", 0, "cyan", 0, "purple", 0
                .byte "green", 0, "blue", 0, "yellow", 0, "orange", 0, "brown", 0
                .byte "light red", 0, "dark grey", 0, "grey", 0
                .byte "light green", 0, "light blue", 0, "light grey", 0, 0
HeadText:       .byte "[theme]", CR, 10, "name=", 0
OnText:         .byte " on ", 0
ThemesDir:      .byte "THEMES", 0
Slash:          .byte "/", 0
IniExt:         .byte ".ini", 0
CustomName:     .byte "Custom", 0

HOME_LEN        = 32
PATH_BUF        = 80

        .segment "DATA"

themeCount:     .byte 0         ; the theme files listed
handle:         .byte 0
at:             .byte 0
kind:           .byte 0         ; the line kind being read or written
idx:            .byte 0
tmp:            .byte 0
tmpY:           .byte 0
pathEnd:        .byte 0
lineAt:         .word 0

        .segment "BSS"

curName:        .res NAME_MAX   ; the theme in use (its file's name)
themeNames:     .res THEMES_MAX * NAME_MAX
home:           .res HOME_LEN
path:           .res PATH_BUF
info:           .res 16
name:           .res 64
buf:            .res FILE_MAX + 1
