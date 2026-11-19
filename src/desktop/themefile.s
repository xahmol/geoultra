; GeoUltra Desktop: theme files (docs/design/DESKTOP.md, "Look and themes";
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
;   toolbar=dark grey on light grey
;
; ThemeFiles (at the desktop's start) makes THEMES with the six built-in
; themes and Custom (a copy of GeoUltra) when it is not there, and lists
; the files for the view menu (themeNames); ThemeLoad reads one into the
; theme record (theme.s; unknown lines and words left as they were, so
; a file only needs the lines it changes). Without an Ultimate (VICE)
; nothing is there: the built-in themes stay. A theme may carry a
; palette (user, 2026-11-11): "palette=" and 16 RRGGBB values in the C64
; colours' order, sent to the Ultimate 64 (firmware 3.15a; not yet on
; the C64 Ultimate, nothing on an Ultimate II+ or in VICE) when the theme
; is used; it then shows for every program, as the Ultimate's own
; palette setting does. Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, ThemeName, Derive, tMenu, themeNo
        .import tCols, viewMode, cProgs, cIconT, tByType
        .import text            ; (side.s's INI text: never in use at the same time)
        .export Ov_ThemeFiles, Ov_ThemeUse, Ov_PalReset   ; (overlay 1: ovl.s)
        .export themeNames, themeCount, curName, hasPal
Ov_ThemeFiles = ThemeFiles
Ov_ThemeUse = ThemeUse
Ov_PalReset = PalReset

FO_READ_        = FO_READ
NAME_MAX        = 15            ; a theme's name (and its zero)
THEMES_MAX      = 10            ; files the view menu lists (desktop.s's)
FILE_MAX        = 1024          ; a theme file's bytes, at most (Write's
                                ; longest, all words long and a palette: ~900)
NO_STYLE        = $FF
FE_UCI          = 30            ; (FILE_ENGINE.md: a raw Ultimate command)
PROG_COLOURS    = $C0F4         ; the kernal's programs' colours (info.s)
UCI_CONTROL     = 4             ; the control target,
SET_PALETTE     = $52           ; its palette commands (ultimate-uci-oscar64
RESET_PALETTE   = $54           ; manual: firmware 3.15a on the U64)
PAL_LEN         = 48            ; 16 RGB triplets
REC_ROWS        = 4             ; tRows: 9 or 8, the words' index 0 or 1

        .segment "ZEROPAGE"

tp:             .res 2          ; the text being read or written

        .segment "OV1"

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
Make:   lda #0                  ; (not Custom until its turn)
        sta custom
        jsr DirPath
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
        lda #0                  ; its palette, when it has one (theme.s)
        sta hasPal
        lda at
        jsr ThemePal
        bcs :+
        ldy #PAL_LEN - 1
@pal:   lda (r1),y
        sta palCmd + 2,y
        dey
        bpl @pal
        inc hasPal
:       lda at
        jsr ThemeName           ; r1
        jsr NameFrom
        jsr Write
        inc at
        lda at
        cmp #THEMES_N
        bcc @theme
        lda #0                  ; (GeoUltra: no palette)
        sta hasPal
        jsr ThemeSet
        lda #<CustomName
        sta r1L
        lda #>CustomName
        sta r1H
        jsr NameFrom
        inc custom              ; (its note on the palette)
        jsr Write
        dec custom
        rts

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
        lda #0                  ; (a palette only from the file)
        sta hasPal
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
        lda hasPal              ; its palette to the Ultimate 64; none:
        bne @pal                ; the Ultimate's own (after a palette
        jsr PalReset            ; tried in Settings and Cancel, or a
        jmp :+                  ; program's own; the user, 2026-11-13)
@pal:   jsr PalSend
:       lda cProgs              ; its programs' colours (programs=): GEOS's
        sta screencolors        ; screen colours now, and the kernal's for
        sta PROG_COLOURS        ; FirstInit (info.s)
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
        ldx #KIND_PALETTE       ; "palette=" and its 16 values
        jsr KeyMatch
        bcs :+
        jsr PalRead
:       lda lineAt
        sta tp
        lda lineAt+1
        sta tp+1
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

; PalRead: the 16 RRGGBB values at tp (spaces between them) into
; palCmd's data; hasPal = 1 when all 48 bytes were there.
PalRead:
        ldx #0
@rgb:   ldy #0
        jsr Skip                ; (spaces before a value)
        ldy #3                  ; its three bytes
@byte:  sty tmpY
        jsr Hex
        bcs @bad
        asl a
        asl a
        asl a
        asl a
        sta tmp
        jsr Hex
        bcs @bad
        ora tmp
        sta palCmd + 2,x
        inx
        ldy tmpY
        dey
        bne @byte
        cpx #PAL_LEN
        bcc @rgb
        lda #1
        sta hasPal
        rts
@bad:   lda #0
        sta hasPal
        rts

; Hex: A = the hex digit at tp (0-15), tp one on; C set when it is none.
Hex:    ldy #0
        lda (tp),y
        jsr Step
        cmp #'0'
        bcc @no
        cmp #'9' + 1
        bcc @dig
        ora #$20
        cmp #'a'
        bcc @no
        cmp #'f' + 1
        bcs @no
        sbc #'a' - 10 - 1       ; (C clear: one less)
        clc
        rts
@dig:   sbc #'0' - 1            ; (C clear)
        clc
        rts
@no:    sec
        rts

; PalSend: palCmd (SET_PALETTE and the 48 bytes) to the Ultimate
; (FE_UCI); PalReset: the Ultimate's own palette back (RESET_PALETTE).
; Errors left: no palette control (an Ultimate II+, a C64 Ultimate
; without it, VICE) changes nothing.
PalSend:
        lda #UCI_CONTROL
        sta palCmd
        lda #SET_PALETTE
        sta palCmd + 1
        lda #2 + PAL_LEN
        bne Uci
PalReset:
        lda #UCI_CONTROL
        sta palCmd
        lda #RESET_PALETTE
        sta palCmd + 1
        lda #2
Uci:    sta r1L
        lda #<palCmd
        sta r0L
        lda #>palCmd
        sta r0H
        lda #0
        sta r2L
        sta r2H
        sta r3L
        sta r3H
        lda #FE_UCI
        jmp FileEngine

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
        ldy LColour,x           ; an icon colour by type not set ($FF):
        lda tMenu,y             ; no line (the desk's colours stay)
        cmp #ITYPE_NONE
        bne :+
        jmp @next
:       lda KeyLo,x
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
@next:  inc kind
        lda kind
        cmp #LINES_N
        bcs :+
        jmp @line
:       lda hasPal              ; its palette
        beq @note
        lda #<PalKey
        ldx #>PalKey
        jsr Put
        lda #'='
        jsr PutCh
        ldx #0
@pal:   stx tmpX                ; a space before each value but the first
        txa
        beq :+
@third: cmp #3                  ; (X a multiple of 3: a value's start)
        bcc :+
        sbc #3
        bne @third
        lda #' '
        jsr PutCh
:       ldx tmpX
        lda palCmd + 2,x
        lsr a
        lsr a
        lsr a
        lsr a
        jsr HexOut
        ldx tmpX
        lda palCmd + 2,x
        and #$0F
        jsr HexOut
        ldx tmpX
        inx
        cpx #PAL_LEN
        bcc @pal
        jsr NewLine
@note:  lda custom              ; Custom: how a palette is written
        beq @file
        lda #<PalNote
        ldx #>PalNote
        jsr Put
        jsr NewLine
@file:  jsr FilePath            ; the file
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

; HexOut: the hex digit A (0-15) written.
HexOut: cmp #10
        bcc :+
        adc #'A' - 10 - 1       ; (C set)
        jmp PutCh
:       ora #'0'
        jmp PutCh

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


; --- The built-in themes (moved from theme.s on 2026-11-11: room in the
; core; ThemeName and the names stay there for the menu's texts) ------

; ThemeSet: built-in theme A (0 to THEMES_N - 1) into the record, its
; layout derived, the border set. Destroys A, X, Y.
ThemeSet:
        sta themeNo
        tax                     ; its bytes: A * THM_LEN
        lda #0
@mul:   dex
        bmi @copy
        clc
        adc #THM_LEN
        bne @mul
@copy:  tax
        ldy #0
@b:     lda Themes,x
        sta tMenu,y
        inx
        iny
        cpy #THM_LEN
        bcc @b
        lda #ITYPE_NONE         ; (the built-in themes: no icon colours by
        ldx #ITYPES_N - 1       ; type; a file's lines set them after)
@t:     sta cIconT,x
        dex
        bpl @t
        inx                     ; (X 0: icons-bytype on)
        stx tByType
        lda #VIEW_LIST          ; the theme's view (its columns style)
        ldx tCols
        beq :+
        lda #VIEW_DETAILED
:       sta viewMode
        jmp Derive

; ThemeByName: the built-in theme whose name is at r0 (any case, ended
; by 0, CR or LF) set; C set when there is none.
ThemeByName:
        lda #0
        sta at
@theme: lda at
        cmp #THEMES_N
        bcs @none
        jsr ThemeName           ; r1 = its name
        ldy #0
@ch:    lda (r1),y
        beq @end
        jsr Lower
        sta tmp
        lda (r0),y
        jsr Lower
        cmp tmp
        bne @next
        iny
        bne @ch
@end:   lda (r0),y              ; (the given name must end here too)
        beq @yes
        cmp #CR
        beq @yes
        cmp #10
        beq @yes
@next:  inc at
        bne @theme
@none:  sec
        rts
@yes:   lda at
        jsr ThemeSet
        clc
        rts

; Lower: A in lower case (letters only).
Lower:  cmp #'A'
        bcc @end
        cmp #'Z' + 1
        bcs @end
        ora #$20
@end:   rts

; ThemePal: r1 = built-in theme A's palette (48 bytes), C clear; C set
; when it has none (GeoUltra: the C64's own). Destroys X.
ThemePal:
        tax
        lda PalHi,x
        beq @none
        sta r1H
        lda PalLo,x
        sta r1L
        clc
        rts
@none:  sec
        rts

; The built-in themes (the mock-up, approved 2026-11-06). Styles:
; menubar (plain, clock), sidebar (wide, narrow), headings (inverted,
; band, underlined, plain), titlebar (stripes, solid, line, none), rows
; (9, 8), columns (name, detailed), icons (on, off), selection (invert,
; bar, frame), cursor (dotted, mark, underline), scrollbar (arrows,
; thin), status (on, off). Colours: border, desk, menu, side, heading,
; title (ink << 4 | paper), icon (ink), select (pair), accent (ink),
; status (pair), toolbar (pair; the menu bar's, as the mock-up has it).
; The border: the menu bar's paper (the user, 2026-11-11: the bar with
; the date, not the list's background). C64 colours: 0 black, 1 white, 3 cyan, 4 purple, 6
; blue, 7 yellow, 8 orange, 11 dark grey, 12 grey, 14 light blue, 15
; light grey.
Themes:
        ; GeoUltra (the default)
        .byte 1, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0
        .byte 15, $BF, $BF, $BF, $1E, $BF, 6, $14, 6, $1C, $BF, $BF
        ; GEOS classic
        .byte 0, 0, 2, 0, 9, 0, 1, 0, 0, 0, 1
        .byte 1, $61, $61, $61, $61, $61, 6, $16, 6, $63, $61, $BF
        ; Flat
        .byte 1, 0, 1, 1, 8, 0, 0, 1, 1, 1, 0
        .byte 15, $BF, $0F, $BF, $16, $1B, 11, $1E, 8, $1B, $0F, $BF
        ; Detailed
        .byte 1, 1, 0, 1, 9, 1, 0, 0, 2, 0, 0
        .byte 15, $0F, $0F, $BF, $1B, $1B, 11, $16, 6, $1C, $0F, $BF
        ; Night
        .byte 1, 0, 1, 2, 8, 0, 0, 1, 1, 1, 0
        .byte 0, $FB, $10, $F0, $03, $3B, 3, $07, 7, $30, $10, $BF
        ; Mono
        .byte 0, 0, 3, 2, 9, 0, 1, 2, 2, 1, 1
        .byte 1, $01, $01, $01, $01, $01, 0, $01, 0, $01, $01, $BF

; The built-in themes' palettes (user, 2026-11-11: GeoUltra keeps the
; C64's own, the others tuned freely in RGB): 16 RRGGBB triplets in
; the C64 colours' order; each colour keeps its character, as programs
; started from the desktop see the palette too.
PalLo:  .byte 0, <Pal1, <Pal2, <Pal3, <Pal4, <Pal5
PalHi:  .byte 0, >Pal1, >Pal2, >Pal3, >Pal4, >Pal5
Pal1:   ; GEOS classic
        .byte $00, $00, $00, $FF, $FF, $FF, $8D, $2F, $34, $A6, $DC, $E8
        .byte $98, $35, $A4, $4C, $B4, $42, $2A, $3A, $9E, $EF, $EF, $5D
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $4A, $4A, $4A
        .byte $7B, $7B, $7B, $9F, $EF, $93, $7A, $86, $E0, $B2, $B2, $B2
Pal2:   ; Flat
        .byte $1A, $1C, $20, $FF, $FF, $FF, $8D, $2F, $34, $6A, $D4, $CD
        .byte $98, $35, $A4, $4C, $B4, $42, $2F, $6F, $D6, $EF, $EF, $5D
        .byte $F0, $8A, $24, $5B, $38, $00, $D1, $67, $6D, $3C, $40, $48
        .byte $9A, $A0, $A8, $9F, $EF, $93, $5B, $9B, $F0, $E6, $E8, $EB
Pal3:   ; Detailed
        .byte $20, $22, $26, $FF, $FF, $FF, $8D, $2F, $34, $6A, $D4, $CD
        .byte $98, $35, $A4, $4C, $B4, $42, $33, $66, $CC, $EF, $EF, $5D
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $50, $55, $5C
        .byte $8A, $90, $98, $9F, $EF, $93, $6F, $95, $E0, $DC, $DF, $E3
Pal4:   ; Night
        .byte $12, $15, $1A, $E8, $EC, $F2, $8D, $2F, $34, $4F, $C7, $C2
        .byte $98, $35, $A4, $4C, $B4, $42, $2C, $29, $B1, $F2, $C9, $4C
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $23, $28, $30
        .byte $6B, $72, $80, $9F, $EF, $93, $6D, $6A, $EF, $C5, $CA, $D3
Pal5:   ; Mono
        .byte $10, $10, $10, $FA, $FA, $F5, $8D, $2F, $34, $6A, $D4, $CD
        .byte $98, $35, $A4, $4C, $B4, $42, $2C, $29, $B1, $EF, $EF, $5D
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $3A, $3A, $3A
        .byte $8C, $8C, $8C, $9F, $EF, $93, $6D, $6A, $EF, $D0, $D0, $D0


; --- Tables ------------------------------------------------------------------

; The lines after name=, in the file's order: their keys, the record's
; style byte (NO_STYLE: none) with its words, the kind of colours and
; the record's colour byte (theme.s, Themes' order).
LStyle: .byte NO_STYLE, NO_STYLE, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, NO_STYLE
        .byte NO_STYLE          ; programs
        .byte 29                ; icons-bytype (tByType, after cIconT)
        .res ITYPES_N, NO_STYLE ; icons by type
        .assert * - LStyle = LINES_N, error, "LStyle: a byte per line"
LColour:                        ; (offsets from tMenu: 11 the border ...)
        .byte 11, 12, 13, 14, 15, 16, 0, 0, 17, 18, 19, 0, 20, 21
        .byte 22                ; programs (cProgs)
        .byte 0                 ; icons-bytype (no colours)
        .byte 23, 24, 25, 26, 27, 28 ; icons by type (cIconT, after the record)
        .assert * - LColour = LINES_N, error, "LColour: a byte per line"
RowsVal:        .byte 9, 8
        .include "themedef.inc"  ; (the format's tables, shared with GeoUltra
                                ; Settings' theme editor)
HeadText:       .byte "[theme]", CR, 10, "name=", 0
OnText:         .byte " on ", 0
ThemesDir:      .byte "THEMES", 0
Slash:          .byte "/", 0
IniExt:         .byte ".ini", 0
CustomName:     .byte "Custom", 0
PalNote:        .byte "; palette=RRGGBB x 16 (black ... light grey): the colours"
                .byte " on an Ultimate 64", 0

HOME_LEN        = 32
PATH_BUF        = 80

        .segment "BSS"          ; (kept: the core reads them)

curName:        .res NAME_MAX   ; the theme in use (its file's name)
themeNames:     .res THEMES_MAX * NAME_MAX
themeCount:     .res 1         ; the theme files listed
hasPal:         .res 1         ; 1: the theme in use carries a palette

        .segment "OV1"          ; scratch: set anew in each call that uses it

palCmd:         .res 2 + PAL_LEN ; SET_PALETTE and the theme's palette
home:           .res HOME_LEN
path:           .res PATH_BUF
info:           .res 16
name:           .res 64
buf = text                      ; (side.s's INI text, TEXT_MAX + 1 bytes)
        .assert FILE_MAX <= TEXT_MAX, error, "a theme file must fit side.s's text"
handle:         .res 1
at:             .res 1
kind:           .res 1         ; the line kind being read or written
idx:            .res 1
tmp:            .res 1
tmpY:           .res 1
pathEnd:        .res 1
lineAt:         .res 2
tmpX:           .res 1
custom:         .res 1         ; 1: writing Custom (its palette note)
