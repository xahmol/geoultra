; GeoUltra Settings: the Theme page (overlay 5, ovl.s; docs/design/SETTINGS.md):
; the theme editor, in compact rows: Theme [-] name [+]
; with "use" (SETTINGS.INI [desktop] theme=) and "copy" (a new theme
; file from this one); Part [-] name [+] (the theme file's lines,
; src/inc/themedef.inc); the part's style; its ink and paper as 16
; swatches; a preview strip across the page (a mini desktop in the
; theme's colours), drawn again at each change. The theme file is the
; core's second text (UseTheme); a change rewrites its line in the
; file's own words ("clock, dark grey on light grey"); OK and Save write
; it as THEMES/<name>.ini (settings.s Write). Without an Ultimate (VICE)
; there are no theme files: the page edits an empty text. Own design
; and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ButtonDraw, OnButton, TextWidth, FileEngine
        .import IniFind, IniSet, NoRoom, dirty, Write
        .import UseSettings, UseTheme, themeDirty, themeLoaded, themeNo
        .import themeCount, themePart, themeNames
        .import noFile
        .import KeyLo, KeyHi, LColKind, ColourNames
        .importzp LINES_N, CK_NONE, CK_PAIR, CK_INK, CK_PAPER, LINE_ITYPES, ITYPES_N, LINE_BYTYPE
        .import PalKey, IniDel
        .export Ov_ThemeDraw, Ov_ThemePress, Ov_ThemeAsk, row, SWATCH_X
        .import BarOn, BarOff, ThemesFull, Ask2, repaint, ReadChrome
        .import FirstLoad, AddName, NameAt, LoadTheme
        .import ReadLine, LineKey, HasWords, NextWord, Colour
        .import STheme, OnText, SDesktop, KTheme, ThemePaths, tmp, idx, line, style, ink, paper, name, val, pbuf
        .import cColour, InUse, DeleteTheme, buf, iType
        .importzp vp

        .segment "ZEROPAGE"

askText:        .res 2          ; the copy's question (DBVARSTR)

        .segment "OV5"

; Ov_ThemeDraw: the theme read (once), the rows, the swatches, the
; preview.
Ov_ThemeDraw:
        lda themeLoaded
        bne :+
        jsr FirstLoad
:       jsr UseTheme
        ldx #0                  ; the labels
@label: stx at
        lda LabelLo,x
        sta r0L
        lda LabelHi,x
        sta r0H
        lda #<LABEL_X
        sta r11L
        lda #>LABEL_X
        sta r11H
        lda LabelY,x
        sta r1H
        jsr PutString
        ldx at
        inx
        cpx #LABELS
        bcc @label
        ldx #0                  ; the buttons
@btn:   stx at
        lda BtnLo,x
        pha
        lda BtnHi,x
        tax
        pla
        jsr ButtonDraw
        ldx at
        inx
        cpx #BUTTONS
        bcc @btn
        jsr NameDraw
        jmp PartDraw

; Ov_ThemePress: a click on a button, the style row or a swatch.
Ov_ThemePress:
        jsr UseTheme
        ldx #0
@btn:   stx at
        lda BtnLo,x
        pha
        lda BtnHi,x
        tax
        pla
        jsr OnButton
        bcs @next
        ldx at
        lda ActLo,x
        sta vp
        lda ActHi,x
        sta vp+1
        jmp (vp)
@next:  ldx at
        inx
        cpx #BUTTONS
        bcc @btn
        lda themePart
        cmp #PALETTE
        bne :+
        jmp PalPress
:       cmp #ITYPE_PART
        bne :+
        jsr TypePress           ; (the type picker, none)
        bcc @end
        lda #LINE_BYTYPE        ; its style row: icons-bytype on, off
        jsr ReadLine
        jsr StylePress
        bcc @end
        jsr ReadPart            ; its ink row: the type's line
        jmp SwatchPress
:       jsr StylePress
        bcc @end
        jmp SwatchPress
@end:   rts

; --- the theme: its file, its name

; NameDraw: the theme's name between its buttons; "*" before it when it
; is the theme in use (as the desktop's theme menu marks it).
NameDraw:
        lda #THEME_Y
        ldx #NAME_X
        jsr Clear
        lda themeCount          ; (none listed: no mark)
        cmp #1
        bcc :+
        jsr InUse               ; (chrome.s: C clear for the one in use)
:       php
        jsr NameAt
        lda vp
        sta r0L
        lda vp+1
        sta r0H
        lda themeCount          ; (none listed: the name in name)
        bne :+
        lda #<name
        sta r0L
        lda #>name
        sta r0H
:       lda #NAME_X
        sta r11L
        lda #0
        sta r11H
        lda #THEME_Y
        sta r1H
        plp
        bcs @name
        lda r0L
        pha
        lda r0H
        pha
        lda #'*'
        jsr PutChar
        pla
        sta r0H
        pla
        sta r0L
@name:  jmp PutString

; Ov_ThemeAsk (OK and Save, settings.s): when the Theme page was shown
; and the theme on it is not the one in use, "Use the theme <name> for
; the desktop?"; Yes as "use" (the user's decision of 2026-11-20: - and
; + only showing a theme was easy to mistake for choosing it).
Ov_ThemeAsk:
        lda themeLoaded         ; (the page not shown: nothing to ask)
        beq @end
        lda themeCount
        beq @end
        jsr InUse
        bcc @end                ; (it is the one in use)
        ldx #0
@txt:   lda UseAsk,x
        beq :+
        sta buf,x
        inx
        bne @txt
:       jsr NameAt
        ldy #0
@nm:    lda (vp),y
        beq :+
        sta buf,x
        inx
        iny
        bne @nm
:       lda #PLAINTEXT
        sta buf,x
        lda #0
        sta buf + 1,x
        lda #<buf
        sta askText
        lda #>buf
        sta askText+1
        lda #<UseDlg
        ldx #>UseDlg
        jsr Ask2
        cmp #YES
        bne @end
        jmp UseIt
@end:   rts

; Clear: the text's place at baseline A from x X to NEXT_X - 2 (a
; name's room, before its [+]); ClearRow: to the frame round the screen.
Clear:  ldy #<(NEXT_X - 2)
        sty r4L
        ldy #>(NEXT_X - 2)
        jmp ClearAt
ClearRow:
        ldy #<(SCREEN_RIGHT - 1) ; (inside settings.s's frame)
        sty r4L
        ldy #>(SCREEN_RIGHT - 1)
ClearAt:
        sty r4H
        sta tmp
        stx r3L
        lda #0
        sta r3H
        lda tmp
        sec
        sbc #9
        sta r2L
        lda tmp
        clc
        adc #2
        sta r2H
        lda #0
        jsr SetPattern
        jmp Rectangle

; --- the buttons

; ThemeDown, ThemeUp: the previous or next theme file (the changes to
; this one written first when asked: Yes saves, No drops them).
ThemeDown:
        lda themeNo
        bne :+
        lda themeCount
:       sec
        sbc #1
        jmp NewTheme
ThemeUp:
        ldx themeNo
        inx
        txa
        cmp themeCount
        bcc NewTheme
        lda #0
NewTheme:
        sta new
        lda themeCount
        cmp #2
        bcc @end                ; (one or none: nothing to go to)
        lda themeDirty
        beq @go
        lda #<SaveDlg
        ldx #>SaveDlg
        jsr Ask2
        cmp #YES
        bne @go
        jsr Write               ; (settings.s: both texts)
        bcs @back
@go:    lda new
        sta themeNo
        jsr LoadTheme
@back:  jsr NameDraw
        jmp PartDraw
@end:   rts

; PartDown, PartUp: the previous or next part.
PartDown:
        ldx themePart
        bne :+
        ldx #PARTS
:       dex
        stx themePart
        jmp PartDraw
; PalPart: straight to the palette part.
PalPart:
        ldx #PALETTE
        stx themePart
        jmp PartDraw
PartUp: ldx themePart
        inx
        cpx #PARTS
        bcc :+
        ldx #0
:       stx themePart
        jmp PartDraw

; UseIt: SETTINGS.INI [desktop] theme= this theme (the desktop's from
; its next start).
UseIt:  jsr UseSettings
        jsr NameAt
        lda #<SDesktop
        sta r0L
        lda #>SDesktop
        sta r0H
        lda #<KTheme
        sta r1L
        lda #>KTheme
        sta r1H
        lda vp
        sta r2L
        lda vp+1
        sta r2H
        jsr IniSet
        php
        jsr UseTheme
        plp
        bcc :+
        jmp NoRoom
:       lda #1
        sta dirty
        sta repaint             ; (settings.s: Settings drawn again in it)
        jmp ReadChrome          ; (chrome.s: its colours and styles)

; DeleteIt: the theme shown deleted (its file, at once), when it is not
; the one in use and not the last; asked first. The next one shown.
DeleteIt:
        lda noFile              ; (no Ultimate: no files)
        bne @no
        lda themeCount
        cmp #2
        bcc @no
        jsr InUse               ; (chrome.s)
        bcs @ask
        lda #<UsedDlg
        ldx #>UsedDlg
        jsr Ask2
        jmp @back
@no:    rts
@ask:   ldx #0                  ; "Delete the theme <name>?"
@txt:   lda DelText,x
        beq :+
        sta buf,x
        inx
        bne @txt
:       jsr NameAt
        ldy #0
@nm:    lda (vp),y
        beq :+
        sta buf,x
        inx
        iny
        bne @nm
:       lda #'?'
        sta buf,x
        lda #PLAINTEXT
        sta buf + 1,x
        lda #0
        sta buf + 2,x
        lda #<buf
        sta askText
        lda #>buf
        sta askText+1
        lda #<DelDlg
        ldx #>DelDlg
        jsr Ask2
        cmp #YES
        bne @back
        jsr DeleteTheme         ; (chrome.s)
        txa
        beq @gone
        cpx #FILE_NOT_FOUND     ; (a copy not saved yet has no file: out
        bne @back               ; of the list too; else the list as it was)
@gone:
        lda themeNo             ; out of the list: the ones after it up
        asl a
        asl a
        asl a
        asl a
        tax
@mv:    lda themeNames + THEME_NAME,x
        sta themeNames,x
        inx
        cpx #(THEMES_MAX - 1) * THEME_NAME
        bcc @mv
        dec themeCount
        lda themeNo             ; (it was the last: the one before)
        cmp themeCount
        bcc :+
        dec themeNo
:       lda #0
        sta themeDirty
        jsr LoadTheme
@back:  jsr NameDraw
        jmp PartDraw

; Copy: a new theme from this one: its name typed (the input dialog),
; added to the list and shown; its text this one's with name= changed;
; written as THEMES/<name>.ini at Save or OK.
Copy:   lda themeCount
        cmp #THEMES_MAX
        bcs @full
        lda #0
        sta name
        lda #<CopyAsk
        sta askText
        lda #>CopyAsk
        sta askText+1
        lda #<name
        sta r5L
        lda #>name
        sta r5H
        lda #<NameDlg
        ldx #>NameDlg
        jsr Ask2
        cmp #CANCEL
        beq @end
        lda name
        beq @end
        jsr AddName
        jsr ThemePaths          ; (its paths; the text stays: a copy)
        lda #<STheme            ; name= the new name
        sta r0L
        lda #>STheme
        sta r0H
        lda #<KName
        sta r1L
        lda #>KName
        sta r1H
        lda #<name
        sta r2L
        lda #>name
        sta r2H
        jsr IniSet
        bcc :+
        jmp NoRoom
:       lda #1
        sta themeDirty
@end:   jsr NameDraw
        jmp PartDraw
@full:  jmp ThemesFull            ; (settings.s: said; the user's test)


; --- the part: its style, its colours

; PartDraw: the part's name, its style row, its swatches (by its kind
; of colours), the preview.
PartDraw:
        lda #PART_Y
        ldx #NAME_X
        jsr Clear
        ldx themePart
        lda KeyLo,x
        sta r0L
        lda KeyHi,x
        sta r0H
        cpx #ITYPE_PART         ; (the icon colours by type: one part)
        bne :+
        lda #<TByType
        sta r0L
        lda #>TByType
        sta r0H
:       lda #NAME_X
        sta r11L
        lda #0
        sta r11H
        lda #PART_Y
        sta r1H
        jsr PutString
        jsr Labels
        lda themePart
        cmp #PALETTE
        bne :+
        jsr PalDraw
        jmp Preview
:       lda themePart
        cmp #ITYPE_PART
        bne :+
        lda #LINE_BYTYPE        ; icons by type: on, off as its style;
        jsr ReadLine            ; the type's ink; the type picker on the
        jsr StyleDraw           ; paper row
        jsr ReadPart
        jsr SwatchesDraw
        jsr TypeDraw
        jmp Preview
:       jsr ReadPart
        jsr StyleDraw
        jsr SwatchesDraw
        jmp Preview

; Labels: the three lower rows' labels for the part (the palette's: RGB,
; none, Colour; the others': Style, Ink, Paper).
Labels: ldx #2
@l:     stx at
        lda LowY,x              ; its place cleared
        sec
        sbc #9
        sta r2L
        clc
        adc #11
        sta r2H
        lda #LABEL_X
        sta r3L
        lda #STYLE_X - 2
        sta r4L
        lda #0
        sta r3H
        sta r4H
        jsr SetPattern
        jsr Rectangle
        ldx at
        ldy themePart
        cpy #PALETTE
        bne :+
        inx
        inx
        inx
:       cpy #ITYPE_PART         ; (icons by type: "Type" for "Paper")
        bne :+
        cpx #2
        bne :+
        ldx #6
:       lda LowLo,x
        sta r0L
        lda LowHi,x
        sta r0H
        beq @next               ; (none)
        lda #LABEL_X
        sta r11L
        lda #0
        sta r11H
        ldx at
        lda LowY,x
        sta r1H
        jsr PutString
@next:  ldx at
        dex
        bpl @l
        rts

; ReadPart: style, ink, paper of the part from its line (missing: the
; first style, dark grey on light grey).
ReadPart:
        jsr PartLine
        jsr ReadLine
        lda themePart           ; an icon colour by type not set: no ink
        cmp #ITYPE_PART         ; (none framed)
        bne @end
        jsr LineKey
        jsr IniFind
        bcc @end
        lda #NO_INK
        sta ink
@end:   rts

; PartLine: A = the theme line the part edits (icons by type: the line
; of the type shown, iType).
PartLine:
        lda themePart
        cmp #ITYPE_PART
        bne :+
        lda iType
        clc
        adc #LINE_ITYPES
:       rts

; StyleLine: A = the line of the part's style row (icons by type:
; icons-bytype's on, off).
StyleLine:
        lda themePart
        cmp #ITYPE_PART
        bne PartLine
        lda #LINE_BYTYPE
        rts

; TypeDraw: the type picker on the paper row, [-] the type's name [+],
; and "none" after the ink row's swatches (framed: the type not set).
TypeDraw:
        lda #<BNone             ; (its frame of before cleared)
        ldx #>BNone
        jsr OnBox
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda #<BNone
        ldx #>BNone
        jsr ButtonDraw
        lda ink
        cmp #NO_INK
        bne :+
        lda #<BNone
        ldx #>BNone
        jsr OnBox
        lda #$FF
        jsr FrameRectangle
:       lda #<BTypeDn
        ldx #>BTypeDn
        jsr ButtonDraw
        lda #<BTypeUp
        ldx #>BTypeUp
        jsr ButtonDraw
        ldx iType
        lda TypeLo,x
        sta r0L
        lda TypeHi,x
        sta r0H
        lda #<TYPE_NAME_X
        sta r11L
        lda #>TYPE_NAME_X
        sta r11H
        lda #TYPE_Y
        sta r1H
        jmp PutString

; OnBox: r2-r4 = button A/X's box, a pixel larger all round.
OnBox:  sta r0L
        stx r0H
        ldy #0
        lda (r0),y
        sec
        sbc #2
        sta r3L
        iny
        lda (r0),y
        sbc #0
        sta r3H
        iny
        lda (r0),y
        sec
        sbc #2
        sta r2L
        clc
        adc #BTN_H + 3
        sta r2H
        iny
        lda (r0),y              ; its width
        clc
        adc r3L
        adc #3
        sta r4L
        lda r3H
        adc #0
        sta r4H
        rts

; TypePress: C clear when the click was on the type picker's [-] or
; [+]: the previous or next type shown (its swatches, the preview).
TypePress:
        lda #<BNone             ; none: the type's line out of the theme
        ldx #>BNone
        jsr OnButton
        bcs @dnb
        jsr PartLine
        sta line
        jsr LineKey
        jsr IniDel
        lda #1
        sta themeDirty
        jsr PartDraw
        clc
        rts
@dnb:   lda #<BTypeDn
        ldx #>BTypeDn
        jsr OnButton
        bcs :+
        ldx iType
        bne @dn
        ldx #ITYPES_N
@dn:    dex
        jmp @set
:       lda #<BTypeUp
        ldx #>BTypeUp
        jsr OnButton
        bcs @no
        ldx iType
        inx
        cpx #ITYPES_N
        bcc @set
        ldx #0
@set:   stx iType
        jsr PartDraw
        clc
        rts
@no:    sec
        rts
; WriteLine: line's value in the file's words from style, ink, paper
; (by its kind), set in the theme's text; themeDirty; the preview.
WriteLine:
        ldy #0
        jsr HasWords
        beq @colours
        ldx style               ; the style's word
@find:  dex
        bmi @copy
        jsr NextWord
        jmp @find
@copy:  ldy #0                  ; (val from its start)
        jsr Put
        ldx line
        lda LColKind,x
        cmp #CK_NONE
        beq @done
        lda #','
        jsr PutCh
        lda #' '
        jsr PutCh
        jmp @kind
@colours:
        ldy #0                  ; (no style word: val from its start)
@kind:  ldx line
        lda LColKind,x
        cmp #CK_NONE
        beq @done
        cmp #CK_PAPER
        bne :+
        lda paper
        jsr PutColour
        jmp @done
:       lda ink
        jsr PutColour
        ldx line
        lda LColKind,x
        cmp #CK_INK
        beq @done
        ldx #0
@on:    lda OnText,x
        beq :+
        jsr PutCh
        inx
        bne @on
:       lda paper
        jsr PutColour
@done:  lda #0
        sta val,y
        jsr LineKey
        lda #<val
        sta r2L
        lda #>val
        sta r2H
        jsr IniSet
        bcc :+
        jmp NoRoom
:       lda #1
        sta themeDirty
        rts

; Put: the zero-ended word at vp to val + Y. PutCh: A. PutColour: the
; name of colour A.
Put:    sty tmp
        ldy #0
        lda (vp),y
        beq @end
        ldy tmp
        jsr PutCh
        inc vp
        bne Put
        inc vp+1
        bne Put
@end:   ldy tmp
        rts
PutCh:  cpy #VAL_MAX
        bcs :+
        sta val,y
        iny
:       rts
PutColour:
        tax
        lda #<ColourNames
        sta vp
        lda #>ColourNames
        sta vp+1
@skip:  dex
        bmi Put
        sty tmp
        jsr NextWord
        ldy tmp
        jmp @skip

; StyleDraw: the part's style words as boxes, laid out by their
; measured widths (none: the row empty); styleN of them, at styleXLo/Hi.
StyleDraw:
        lda #STYLE_Y
        ldx #STYLE_X - 2
        jsr ClearRow
        lda #0
        sta styleN
        lda #<STYLE_X
        sta posL
        lda #>STYLE_X
        sta posH
        ldy #0
        jsr HasWords
        beq @end
@word:  ldy #0
        lda (vp),y
        beq @end
        ldx styleN
        cpx #STYLES_MAX
        bcs @end
        lda posL
        sta styleXLo,x
        lda posH
        sta styleXHi,x
        stx idx
        jsr StyleBox
        lda vp                  ; its word after the box
        sta r0L
        lda vp+1
        sta r0H
        lda posL
        clc
        adc #BOX_TEXT
        sta r11L
        lda posH
        adc #0
        sta r11H
        lda #STYLE_Y
        sta r1H
        jsr PutString
        lda vp                  ; the next box: after its word and a gap
        sta r0L
        lda vp+1
        sta r0H
        jsr TextWidth
        clc
        adc #BOX_TEXT + STYLE_GAP
        adc posL
        sta posL
        bcc :+
        inc posH
:       jsr NextWord
        inc styleN
        jmp @word
@end:   rts

; StyleBox: style box idx framed, filled when it is the style.
StyleBox:
        ldx idx
        lda styleXLo,x
        sta r3L
        clc
        adc #BOX - 1
        sta r4L
        lda styleXHi,x
        sta r3H
        adc #0
        sta r4H
        lda #STYLE_Y - BOX + 1
        sta r2L
        lda #STYLE_Y
        sta r2H
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda #$FF
        jsr FrameRectangle
        lda idx
        cmp style
        bne @end
        inc r2L
        inc r2L
        dec r2H
        dec r2H
        lda r3L
        clc
        adc #2
        sta r3L
        bcc :+
        inc r3H
:       lda r4L
        sec
        sbc #2
        sta r4L
        bcs :+
        dec r4H
:       lda #1
        jsr SetPattern
        jsr Rectangle
@end:   rts

; StylePress: C clear when the click was on the style row: the last box
; left of the pointer becomes the style (written, drawn again).
StylePress:
        lda mouseYPos
        cmp #STYLE_Y - 9
        bcc @no
        cmp #STYLE_Y + 3
        bcs @no
        ldx styleN
        beq @no
@box:   dex
        bmi @no
        lda mouseXPos+1         ; its x <= the pointer's?
        cmp styleXHi,x
        bcc @box
        bne @hit
        lda mouseXPos
        cmp styleXLo,x
        bcc @box
@hit:   stx style
        jsr WriteLine
        jsr StyleLine           ; (WriteLine kept line: the part's)
        jsr ReadLine
        jsr StyleDraw
        jsr Preview
        clc
        rts
@no:    sec
        rts

; SwatchesDraw: the ink row and the paper row (each only when the part
; has it), the one in use framed.
SwatchesDraw:
        lda #INK_ROW
        jsr RowClear
        lda #PAPER_ROW
        jsr RowClear
        ldx line
        lda LColKind,x
        cmp #CK_PAIR
        beq @both
        cmp #CK_INK
        beq @ink
        cmp #CK_PAPER
        beq @paper
        rts
@both:  jsr @ink
@paper: lda #PAPER_ROW
        ldx paper
        jmp Swatches
@ink:   lda #INK_ROW
        ldx ink
        jmp Swatches

; RowClear: card row A's swatches cleared to the screen's colours.
RowClear:
        sta row
        jsr RowBox
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda row
        jsr Cells
        ldy #SWATCHES - 1
        lda cColour + 1         ; (chrome.s: the desk's, as the page)
@c:     sta (vp),y
        dey
        bpl @c
        jmp BarOff              ; (settings.s: the frame round it away)

; Swatches: card row A: the 16 colours as cells (the colour as paper),
; colour X framed (in black or white, whichever shows).
Swatches:
        sta row
        stx chosen
        jsr Cells
        ldy #SWATCHES - 1
@c:     tya
        sta (vp),y
        dey
        bpl @c
        lda chosen              ; (none chosen, NO_INK: no frame)
        cmp #SWATCHES
        bcs @bar
        jsr RowBox              ; the chosen one framed
        lda chosen
        asl a
        asl a
        asl a
        clc
        adc #<SWATCH_X
        sta r3L
        lda #>SWATCH_X
        adc #0
        sta r3H
        lda r3L
        clc
        adc #7
        sta r4L
        lda r3H
        adc #0
        sta r4H
        lda #$FF
        jsr FrameRectangle
        lda row
        jsr Cells
        ldy chosen
        ldx chosen
        lda Contrast,x
        asl a
        asl a
        asl a
        asl a
        ora chosen
        sta (vp),y
@bar:   jmp BarOn               ; (settings.s: a frame round the row, so
                                ; the page's own colour shows too; the
                                ; user, 2026-11-13)

; RowBox: r2-r4 = card row row's swatches (8 pixels high).
RowBox: lda row
        asl a
        asl a
        asl a
        sta r2L
        clc
        adc #7
        sta r2H
        lda #<SWATCH_X
        sta r3L
        lda #>SWATCH_X
        sta r3H
        lda #<(SWATCH_X + 8 * SWATCHES - 1)
        sta r4L
        lda #>(SWATCH_X + 8 * SWATCHES - 1)
        sta r4H
        rts

; Cells: vp = the colour matrix at card row A, the swatches' first card.
Cells:  ldx #0
        stx vp+1
        sta vp                  ; A * 40 = A * 32 + A * 8
        asl vp
        asl vp
        asl vp                  ; (* 8; rows below 32: no carry yet)
        lda vp
        asl a
        rol vp+1
        asl a
        rol vp+1                ; (* 32)
        clc
        adc vp
        sta vp
        lda vp+1
        adc #>COLOR_MATRIX
        sta vp+1
        lda vp
        clc
        adc #<COLOR_MATRIX + SWATCH_CARD
        sta vp
        bcc :+
        inc vp+1
:       rts

; SwatchPress: a click on a swatch row: that colour as ink or paper.
SwatchPress:
        lda mouseXPos           ; (x - SWATCH_X: 0-127 on a swatch)
        sec
        sbc #<SWATCH_X
        tax
        lda mouseXPos+1
        sbc #>SWATCH_X
        bne @end
        txa
        lsr a
        lsr a
        lsr a
        cmp #SWATCHES
        bcs @end
        sta new
        lda mouseYPos
        lsr a
        lsr a
        lsr a
        ldx line
        cmp #INK_ROW
        bne :+
        ldy LColKind,x          ; (the ink row: shown for pairs and ink)
        cpy #CK_PAIR
        beq @ink
        cpy #CK_INK
        beq @ink
        rts
:       cmp #PAPER_ROW
        bne @end
        ldy LColKind,x
        cpy #CK_PAIR
        beq @paper
        cpy #CK_PAPER
        beq @paper
@end:   rts
@ink:   lda new
        sta ink
        jmp @set
@paper: lda new
        sta paper
@set:   jsr WriteLine
        jsr SwatchesDraw
        jmp Preview

; --- the palette (an Ultimate 64's 16 colours as RGB: the
; user's choice of 2026-11-13)

; PalDraw: the palette read (ReadPal), the colour to change chosen in
; the paper row, its R, G, B with - and + in the style row, "default".
PalDraw:
        jsr ReadPal
        lda #STYLE_Y
        ldx #STYLE_X - 2
        jsr ClearRow
        lda #INK_ROW
        jsr RowClear
        ldx #0                  ; R, G, B and their buttons
@lab:   stx at
        lda RgbLo,x
        sta r0L
        lda RgbHi,x
        sta r0H
        lda RgbX,x
        sta r11L
        lda #0
        sta r11H
        lda #STYLE_Y
        sta r1H
        jsr PutString
        ldx at
        inx
        cpx #3
        bcc @lab
        ldx #0
@btn:   stx at
        lda PalBtnLo,x
        pha
        lda PalBtnHi,x
        tax
        pla
        jsr ButtonDraw
        ldx at
        inx
        cpx #PAL_BUTTONS
        bcc @btn
        jsr ValuesDraw
; PalColours: the paper row as the palette's colours, the chosen framed
; (cleared first: an old frame goes).
PalColours:
        lda #PAPER_ROW
        jsr RowClear
        lda #PAPER_ROW
        ldx palSel
        jmp Swatches

; ValuesDraw: the chosen colour's R, G, B in hex between their buttons.
ValuesDraw:
        ldx #0
@v:     stx at
        lda #0                  ; its place cleared
        jsr SetPattern
        lda #STYLE_Y - 9
        sta r2L
        lda #STYLE_Y + 2
        sta r2H
        lda ValX,x
        sta r3L
        lda ValX + 3,x
        sta r3H
        lda r3L
        clc
        adc #13
        sta r4L
        lda r3H
        adc #0
        sta r4H
        jsr Rectangle
        lda palSel              ; its byte: pal[palSel * 3 + x]
        asl a
        adc palSel
        adc at
        tax
        lda pal,x
        jsr HexText             ; (hexText)
        lda #<hexText
        sta r0L
        lda #>hexText
        sta r0H
        ldx at
        lda ValX,x
        sta r11L
        lda ValX + 3,x
        sta r11H
        lda #STYLE_Y
        sta r1H
        jsr PutString
        ldx at
        inx
        cpx #3
        bcc @v
        rts

; HexText: A as two hex digits in hexText.
HexText:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @dig
        sta hexText
        pla
        and #$0F
        jsr @dig
        sta hexText + 1
        lda #0
        sta hexText + 2
        rts
@dig:   cmp #10
        bcc :+
        adc #'A' - 10 - 1
        rts
:       adc #'0'
        rts

; PalPress: a click on the palette part: a colour chosen (the paper
; row), an R, G or B step (- and +), or "default".
PalPress:
        ldx #0
@btn:   stx at
        lda PalBtnLo,x
        pha
        lda PalBtnHi,x
        tax
        pla
        jsr OnButton
        bcs @next
        ldx at
        cpx #PAL_BUTTONS - 1
        bne :+
        jmp PalDefault
:       txa                     ; buttons: R- R+ G- G+ B- B+
        lsr a
        sta comp                ; its component
        lda palSel
        asl a
        adc palSel
        adc comp
        tax
        lda at
        and #1
        bne @up
        lda pal,x
        sec
        sbc #PAL_STEP
        bcs @set
        lda #0
        beq @set
@up:    lda pal,x
        clc
        adc #PAL_STEP
        bcc @set
        lda #$FF
@set:   sta pal,x
        jsr PalSend             ; (the colour at once)
        jsr WritePal
        jmp ValuesDraw
@next:  ldx at
        inx
        cpx #PAL_BUTTONS
        bcc @btn
        lda mouseXPos           ; a swatch of the paper row: the colour
        sec                     ; to change
        sbc #<SWATCH_X
        tax
        lda mouseXPos+1
        sbc #>SWATCH_X
        bne @end
        txa
        lsr a
        lsr a
        lsr a
        cmp #SWATCHES
        bcs @end
        tax
        lda mouseYPos
        lsr a
        lsr a
        lsr a
        cmp #PAPER_ROW
        bne @end
        stx palSel
        jsr ValuesDraw
        jmp PalColours
@end:   rts

; ReadPal: pal = the theme's palette= (16 RRGGBB, spaces between); none
; or not 16: the Ultimate's palette now (GET_PALETTE); none there (no
; Ultimate 64): its default (DefaultPal).
ReadPal:
        lda #<STheme
        sta r0L
        lda #>STheme
        sta r0H
        lda #<PalKey
        sta r1L
        lda #>PalKey
        sta r1H
        jsr IniFind             ; (r2 its value, A its length)
        bcs @ask
        sta len
        ldy #0
        ldx #0
@byte:  jsr SkipSp
        jsr Nibble
        bcs @ask
        asl a
        asl a
        asl a
        asl a
        sta tmp
        jsr Nibble
        bcs @ask
        ora tmp
        sta pal,x
        inx
        cpx #PAL_LEN
        bcc @byte
        rts
@ask:   lda #CTRL_GET_PALETTE   ; the Ultimate's palette now
        sta uciCmd + 1
        lda #2
        jsr Uci
        txa
        beq @end
        ldx #PAL_LEN - 1        ; (no Ultimate 64: its default)
@def:   lda DefaultPal,x
        sta pal,x
        dex
        bpl @def
@end:   rts

; SkipSp: Y past spaces in the value at r2 (len its length).
SkipSp: cpy len
        bcs @end
        lda (r2),y
        cmp #' '
        bne @end
        iny
        bne SkipSp
@end:   rts

; Nibble: A = the hex digit at r2 + Y (Y on); C set when none.
Nibble: cpy len
        bcs @no
        lda (r2),y
        iny
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

; WritePal: palette= the 16 colours as RRGGBB, a space between, in the
; theme's text; themeDirty.
WritePal:
        ldx #0
        ldy #0
@c:     cpx #0                  ; (a space before each but the first)
        beq :+
        lda #' '
        sta pbuf,y
        iny
:       lda #3
        sta comp
@b:     lda pal,x
        sty tmp
        jsr HexText
        ldy tmp
        lda hexText
        sta pbuf,y
        lda hexText + 1
        sta pbuf + 1,y
        iny
        iny
        inx
        dec comp
        bne @b
        cpx #PAL_LEN
        bcc @c
        lda #0
        sta pbuf,y
        lda #<STheme
        sta r0L
        lda #>STheme
        sta r0H
        lda #<PalKey
        sta r1L
        lda #>PalKey
        sta r1H
        lda #<pbuf
        sta r2L
        lda #>pbuf
        sta r2H
        jsr IniSet
        bcc :+
        jmp NoRoom
:       lda #1
        sta themeDirty
        rts

; PalSend: the chosen colour to the Ultimate at once (SET_PALETTE_COLOR:
; its index, R, G, B; nothing without an Ultimate 64).
PalSend:
        lda #CTRL_SET_COLOUR
        sta uciCmd + 1
        lda palSel
        sta uciCmd + 2
        asl a
        adc palSel
        tax
        ldy #0
@c:     lda pal,x
        sta uciCmd + 3,y
        inx
        iny
        cpy #3
        bcc @c
        lda #6
; Uci: uciCmd (the control target, its command, A bytes in all) to the
; Ultimate (FE_UCI); a reply into pal (GET_PALETTE's 48 bytes). X = 0 or
; the error.
Uci:    sta r1L
        lda #CTRL_TARGET
        sta uciCmd
        lda #<uciCmd
        sta r0L
        lda #>uciCmd
        sta r0H
        lda #<pal
        sta r2L
        lda #>pal
        sta r2H
        lda #PAL_LEN
        sta r3L
        lda #0
        sta r3H
        lda #FE_UCI
        jmp FileEngine

; PalDefault: the theme without its own palette (palette= out): the
; Ultimate's own back (RESET_PALETTE), shown.
PalDefault:
        lda #<STheme
        sta r0L
        lda #>STheme
        sta r0H
        lda #<PalKey
        sta r1L
        lda #>PalKey
        sta r1H
        jsr IniDel
        lda #1
        sta themeDirty
        lda #CTRL_RESET_PALETTE
        sta uciCmd + 1
        lda #2
        jsr Uci
        jmp PalDraw

; --- the preview: a mini desktop in the theme's colours

; Preview: card rows PREV_ROW to PREV_ROW + 5, cards PREV_CARD to
; PREV_CARD + 19: the border at both ends, the menu bar, the toolbar,
; the sidebar with its heading, the list with a selected row, the
; status line; their words in their inks.
Preview:
        lda #0                  ; its bitmap cleared
        jsr SetPattern
        lda #PREV_ROW * 8
        sta r2L
        lda #PREV_ROW * 8 + 6 * 8 - 1
        sta r2H
        lda #<(PREV_CARD * 8)
        sta r3L
        lda #>(PREV_CARD * 8)
        sta r3H
        lda #<(PREV_CARD * 8 + 20 * 8 - 1)
        sta r4L
        lda #>(PREV_CARD * 8 + 20 * 8 - 1)
        sta r4H
        jsr Rectangle
        dec r2L                 ; a frame just outside it (the user, 2026-
        inc r2H                 ; 11-13: the preview stands out)
        lda #<(PREV_CARD * 8 - 1)
        sta r3L
        lda #>(PREV_CARD * 8 - 1)
        sta r3H
        lda #<(PREV_CARD * 8 + 20 * 8)
        sta r4L
        lda #>(PREV_CARD * 8 + 20 * 8)
        sta r4H
        lda #$FF
        jsr FrameRectangle
        lda line                ; (ReadLine below changes it)
        pha
        lda style
        pha
        lda ink
        pha
        lda paper
        pha
        ldx #0                  ; each area: its line's colours to its cells
@area:  stx at
        lda AreaLine,x
        jsr ReadLine
        ldx at
        lda line
        tay
        lda LColKind,y
        cmp #CK_PAPER
        bne :+
        lda paper               ; (the border: paper only)
        jmp @cell
:       lda ink
        asl a
        asl a
        asl a
        asl a
        ora paper
@cell:  sta colour
        lda AreaRow,x
        sta row
        lda AreaRows,x
        sta rows
@rows:  lda row
        jsr PrevCells
        ldx at
        ldy AreaCard,x
        lda AreaCards,x
        sta cards
        lda colour
@c:     sta (vp),y
        iny
        dec cards
        bne @c
        inc row
        dec rows
        bne @rows
        ldx at
        inx
        cpx #AREAS
        bcc @area
        pla
        sta paper
        pla
        sta ink
        pla
        sta style
        pla
        sta line
        ldx #0                  ; the words
@word:  stx at
        lda PrevLo,x
        sta r0L
        lda PrevHi,x
        sta r0H
        lda PrevX,x
        sta r11L
        lda #0
        sta r11H
        lda PrevY,x
        sta r1H
        jsr PutString
        ldx at
        inx
        cpx #PREV_WORDS
        bcc @word
        rts

; PrevCells: vp = the colour matrix at card row A, the preview's first
; card.
PrevCells:
        jsr Cells
        lda vp
        sec
        sbc #SWATCH_CARD - PREV_CARD
        sta vp
        bcs :+
        dec vp+1
:       rts

; --- layout and data

LABEL_X         = PAGE_LEFT + 2
THEME_Y         = PAGE_TOP + 20 ; the rows' baselines
PART_Y          = THEME_Y + 18
STYLE_Y         = PART_Y + 18
INK_ROW         = 10            ; the swatches' card rows (y 80, 96)
PAPER_ROW       = 12
SWATCH_CARD     = 19            ; their first card (x 152)
SWATCH_X        = SWATCH_CARD * 8
SWATCHES        = 16
PREV_ROW        = 15            ; the preview: card rows 15-20 (y 120-167),
PREV_CARD       = 19            ; cards 19-38 (x 152-311)
MINUS_X         = 150           ; the buttons: [-] name [+] use copy
NAME_X          = MINUS_X + 18
PLUS_X          = 236
NEXT_X          = PLUS_X        ; (a name's room ends at [+])
USE_X           = 254
COPY_X          = 286
STYLE_X         = 118           ; (after "Style")
BOX             = 7
BOX_TEXT        = 11
STYLE_GAP       = 8             ; between a word and the next box
STYLES_MAX      = 4
ITYPE_PART      = LINE_BYTYPE   ; the icon colours by type: one part (the
                                ; user, 2026-11-14): icons-bytype's on, off
                                ; and the type lines by iType
PALETTE         = LINE_BYTYPE + 1 ; then the palette
PARTS           = LINE_BYTYPE + 2
        .assert LINE_ITYPES + ITYPES_N = LINES_N, error, "parts: the type lines last"
TYPE_NAME_X     = STYLE_X + 18
TYPE_Y          = PAPER_ROW * 8 + 7 ; (the paper row's label's baseline)
NONE_X          = SWATCH_X + 16 * 8 + 4 ; after the ink row's swatches
NO_INK          = $FF           ; ink: the type's line not there
BTN_H           = 12            ; a button's height (widgets.s)
PAL_LEN         = 48            ; 16 RGB triplets
PAL_STEP        = 4             ; an R, G or B step
PAL_BUTTONS     = 7             ; R- R+ G- G+ B- B+ default
RGB_W           = 56            ; an R, G or B group: letter, -, value, +
CTRL_TARGET     = 4             ; the Ultimate's control target (ultimate-
CTRL_GET_PALETTE = $51          ; uci-oscar64 manual, firmware 3.15a on the
CTRL_SET_COLOUR = $53           ; Ultimate 64)
CTRL_RESET_PALETTE = $54
LABELS          = 2             ; (Theme, Part; the rest: Labels)
BUTTONS         = 8
DEL_Y           = (PREV_ROW + 5) * 8 - 6 ; the delete button's top (its row
                                ; ends with the preview's last)
AREAS           = 9
PREV_WORDS      = 6

LabelLo:        .byte <LTheme, <LPart
LabelHi:        .byte >LTheme, >LPart
LabelY:         .byte THEME_Y, PART_Y
LowLo:          .byte <LStyle, <LInk, <LPaper, <LRgb, 0, <LColour, <LType
LowHi:          .byte >LStyle, >LInk, >LPaper, >LRgb, 0, >LColour, >LType
LowY:           .byte STYLE_Y, INK_ROW * 8 + 7, PAPER_ROW * 8 + 7
BtnLo:          .byte <BThemeDn, <BThemeUp, <BUse, <BCopy, <BPartDn, <BPartUp, <BPal, <BDel
BtnHi:          .byte >BThemeDn, >BThemeUp, >BUse, >BCopy, >BPartDn, >BPartUp, >BPal, >BDel
ActLo:          .byte <ThemeDown, <ThemeUp, <UseIt, <Copy, <PartDown, <PartUp, <PalPart, <DeleteIt
ActHi:          .byte >ThemeDown, >ThemeUp, >UseIt, >Copy, >PartDown, >PartUp, >PalPart, >DeleteIt

BThemeDn:       .word MINUS_X
                .byte THEME_Y - 9, 14
                .word TMinus
BThemeUp:       .word PLUS_X
                .byte THEME_Y - 9, 14
                .word TPlus
BUse:           .word USE_X
                .byte THEME_Y - 9, 28
                .word TUse
BCopy:          .word COPY_X
                .byte THEME_Y - 9, 32
                .word TCopy
BPartDn:        .word MINUS_X
                .byte PART_Y - 9, 14
                .word TMinus
BPartUp:        .word PLUS_X
                .byte PART_Y - 9, 14
                .word TPlus
BPal:           .word USE_X             ; (the user, 2026-11-13: the palette
                .byte PART_Y - 9, 64    ; was hard to find)
                .word TPalette
BDel:           .word LABEL_X               ; (the user, 2026-11-13: delete on
                .byte DEL_Y, 36             ; the Theme page; left of the preview,
                .word TDelete               ; the Theme row is full)
TPalette:       .byte "palette", 0
TDelete:        .byte "delete", 0

; The preview's areas: the line whose colours they take (themedef.inc's
; order: 0 border, 1 desk, 2 menubar, 3 sidebar, 4 headings, 9
; selection, 12 status, 13 toolbar), their first card row, rows, first
; card (from PREV_CARD) and cards.
AreaLine:       .byte 0, 0, 2, 13, 3, 4, 1, 9, 12
AreaRow:        .byte 15, 15, 15, 16, 17, 17, 17, 18, 20
AreaRows:       .byte 6, 6, 1, 1, 3, 1, 3, 1, 1
AreaCard:       .byte 0, 19, 1, 1, 1, 1, 6, 7, 1
AreaCards:      .byte 1, 1, 18, 18, 5, 5, 13, 9, 18
PrevLo:         .byte <WMenu, <WSide, <WFile1, <WSel, <WFile2, <WStatus
PrevHi:         .byte >WMenu, >WSide, >WFile1, >WSel, >WFile2, >WStatus
PrevX:          .byte (PREV_CARD + 1) * 8 + 2, (PREV_CARD + 1) * 8 + 2, (PREV_CARD + 6) * 8 + 2
                .byte (PREV_CARD + 7) * 8 + 2, (PREV_CARD + 6) * 8 + 2, (PREV_CARD + 1) * 8 + 2
PrevY:          .byte 15 * 8 + 7, 17 * 8 + 7, 17 * 8 + 7, 18 * 8 + 7, 19 * 8 + 7, 20 * 8 + 7

; The palette part's row: R, G, B at RgbX, their values at ValX (low,
; high bytes), - and + around them, "default" after.
RgbLo:          .byte <TR, <TG, <TB
RgbHi:          .byte >TR, >TG, >TB
RgbX:           .byte STYLE_X, STYLE_X + RGB_W, <(STYLE_X + 2 * RGB_W)
ValX:           .byte <(STYLE_X + 24), <(STYLE_X + RGB_W + 24), <(STYLE_X + 2 * RGB_W + 24)
                .byte >(STYLE_X + 24), >(STYLE_X + RGB_W + 24), >(STYLE_X + 2 * RGB_W + 24)
PalBtnLo:       .byte <BRm, <BRp, <BGm, <BGp, <BBm, <BBp, <BDef
PalBtnHi:       .byte >BRm, >BRp, >BGm, >BGp, >BBm, >BBp, >BDef
BRm:    .word STYLE_X + 0 * RGB_W + 8
        .byte STYLE_Y - 9, 14
        .word TMinus
BRp:    .word STYLE_X + 0 * RGB_W + 38
        .byte STYLE_Y - 9, 14
        .word TPlus
BGm:    .word STYLE_X + 1 * RGB_W + 8
        .byte STYLE_Y - 9, 14
        .word TMinus
BGp:    .word STYLE_X + 1 * RGB_W + 38
        .byte STYLE_Y - 9, 14
        .word TPlus
BBm:    .word STYLE_X + 2 * RGB_W + 8
        .byte STYLE_Y - 9, 14
        .word TMinus
BBp:    .word STYLE_X + 2 * RGB_W + 38
        .byte STYLE_Y - 9, 14
        .word TPlus
BDef:   .word STYLE_X + 3 * RGB_W + 4
        .byte STYLE_Y - 9, 28
        .word TDefault
TR:             .byte "R", 0
TG:             .byte "G", 0
TB:             .byte "B", 0
TDefault:       .byte "none", 0

; The Ultimate 64's default palette (read with GET_PALETTE from a
; U64-II, firmware 3.15a, 2026-11-13): for a theme without its own
; where the Ultimate cannot be asked (VICE).
DefaultPal:
        .byte $00, $00, $00, $F7, $F7, $F7, $8D, $2F, $34, $6A, $D4, $CD
        .byte $98, $35, $A4, $4C, $B4, $42, $2C, $29, $B1, $EF, $EF, $5D
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $4A, $4A, $4A
        .byte $7B, $7B, $7B, $9F, $EF, $93, $6D, $6A, $EF, $B2, $B2, $B2

; Black or white on each colour (1 white on the dark ones).
Contrast:       .byte 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0

DelDlg:         .byte DEF_DB_POS | 1
                .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askText
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
                .word DelText2
                .byte YES, 1, DBI_Y_2
                .byte NO, DBI_X_2, DBI_Y_2
                .byte 0
UseDlg:         .byte DEF_DB_POS | 1
                .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askText
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
                .word UseText2
                .byte YES, 1, DBI_Y_2
                .byte NO, DBI_X_2, DBI_Y_2
                .byte 0
UsedDlg:        .byte DEF_DB_POS | 1
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
                .word UsedText
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
                .word UsedText2
                .byte OK, 1, DBI_Y_2
                .byte 0
SaveDlg:        .byte DEF_DB_POS | 1
                .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
                .word SaveText
                .byte YES, 1, DBI_Y_2
                .byte NO, DBI_X_2, DBI_Y_2
                .byte 0
NameDlg:        .byte DEF_DB_POS | 1
                .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askText
                .byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5, THEME_NAME - 1
                .byte OK, 1, DBI_Y_2
                .byte CANCEL, DBI_X_2, DBI_Y_2
                .byte 0

KName:          .byte "name", 0
LTheme:         .byte "Theme", 0
LPart:          .byte "Part", 0
LStyle:         .byte "Style", 0
LInk:           .byte "Ink", 0
LPaper:         .byte "Paper", 0
LRgb:           .byte "RGB", 0
LColour:        .byte "Colour", 0
LType:          .byte "Type", 0
TByType:        .byte "icons by type", 0
TypeLo:         .byte <TyApps, <TyDocs, <TyDas, <TySys, <TyFolders, <TyUlt
TypeHi:         .byte >TyApps, >TyDocs, >TyDas, >TySys, >TyFolders, >TyUlt
TyApps:         .byte "applications", 0
TyDocs:         .byte "documents", 0
TyDas:          .byte "desk accessories", 0
TySys:          .byte "system files", 0
TyFolders:      .byte "folders, drives", 0
TyUlt:          .byte "Ultimate files", 0
BTypeDn:        .word STYLE_X
                .byte TYPE_Y - 9, 14
                .word TMinus
BTypeUp:        .word PLUS_X
                .byte TYPE_Y - 9, 14
                .word TPlus
BNone:          .word NONE_X
                .byte INK_ROW * 8 - 2, 28
                .word TNone
TNone:          .byte "none", 0
TMinus:         .byte "-", 0
TPlus:          .byte "+", 0
TUse:           .byte "use", 0
TCopy:          .byte "copy", 0
SaveText:       .byte BOLDON, "Save this theme first?", PLAINTEXT, 0
DelText:        .byte BOLDON, "Delete the theme ", 0
UseAsk:         .byte BOLDON, "Use the theme ", 0
UseText2:       .byte "for the desktop?", 0
DelText2:       .byte "Its file goes at once.", 0
UsedText:       .byte BOLDON, "This theme is in use.", PLAINTEXT, 0
UsedText2:      .byte "Use another one first.", 0
CopyAsk:        .byte BOLDON, "The new theme's name:", PLAINTEXT, 0
WMenu:          .byte "geos  file  view", 0
WSide:          .byte "Drives", 0
WFile1:         .byte "letter", 0
WSel:           .byte "picture", 0
WFile2:         .byte "notes", 0
WStatus:        .byte "3 entries", 0

; Scratch (overlay data: fetched anew with the overlay)
at:             .byte 0
tmp2:           .byte 0
new:            .byte 0
row:            .byte 0
rows:           .byte 0
cards:          .byte 0
chosen:         .byte 0
styleN:         .byte 0         ; StyleDraw: the style row's boxes
styleXLo:       .res STYLES_MAX ; and their x
styleXHi:       .res STYLES_MAX
posL:           .byte 0
posH:           .byte 0
palSel:         .byte 6         ; the palette's colour being changed
comp:           .byte 0         ; R, G or B
len:            .byte 0
hexText:        .res 3
uciCmd:         .res 6          ; the control target's command, its bytes
pal:            .res PAL_LEN    ; the palette (16 RGB)
colour:         .byte 0
