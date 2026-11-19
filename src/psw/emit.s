; GU PostScript: the PostScript text, as tools/gwps.py writes it (the
; tests compare the two byte for byte): the first pass (Prescan: the
; bitmap fonts and their glyphs, in the order met), the prolog with the
; Type 3 fonts, then each page: the header, the footer, the body's lines
; (Measure, layout.s) as runs of text, and the pictures (picture.s).
; Own code.

        .include "psw.inc"

        .export Prescan, Prolog, Pages, ReadRec, Down, FindFonts
        .export docWidth, nPages, hdrFlags, headH, footH, pageH, docV20, top, dry
        .import Measure, Token, Next, StateInit, nch, lineH, lineB, ended, first, recEnd
        .import curFid, curStyle, comboFid, comboFidH, comboStyle
        .import PutC, PutI, PutZ, PutDec, PutHund, PutSp
        .import GlyphSetup, GlyphBits, glyphW, fHeight, fBase, docName, paperW, paperH
        .import FindFont, SlotAX, UseSlot, LoadImage
        .import Picture

KEY_MAX         = 32
FID_MAX         = 16            ; font IDs the first pass keeps

        .segment "CODE"

; ReadRec: record A of the open document into buffer X (0 PAGEBUF, 1
; HEADBUF, 2 FOOTBUF); tp at its start, recEnd at its end. C set when
; it is empty or cannot be read.
ReadRec:
        stx which
        jsr PointRecord
        txa
        bne @none
        ldx which
        lda BufLo,x
        sta r7L
        sta tp
        lda BufHi,x
        sta r7H
        sta tp + 1
        lda SizeLo,x
        sta r2L
        lda SizeHi,x
        sta r2H
        jsr ReadRecord
        txa
        bne @none
        lda r7L                 ; (empty: r7 unchanged)
        sta recEnd
        lda r7H
        sta recEnd + 1
        lda recEnd
        cmp tp
        bne :+
        lda recEnd + 1
        cmp tp + 1
        beq @none
:       clc
        rts
@none:  sec
        rts
BufLo:  .byte <PAGEBUF, <HEADBUF, <FOOTBUF
BufHi:  .byte >PAGEBUF, >HEADBUF, >FOOTBUF
SizeLo: .byte <PAGE_MAX, <HF_MAX, <HF_MAX
SizeHi: .byte >PAGE_MAX, >HF_MAX, >HF_MAX

; --- The first pass -----------------------------------------------------

; Prescan: the header and footer (hasHead, hasFoot), then every page
; record: nPages, the page width (640 when a page's ruler goes past 480
; dots and the document is not V2.0), the Type 3 fonts with their
; glyphs (MarkRec); then x0, y0 (Place). Destroys all.
Prescan:
        lda #0
        sta nKey
        sta nFid
        sta nPages
        sta hasHead
        sta hasFoot
        lda #<480
        sta docWidth
        lda #>480
        sta docWidth + 1
        lda #HEADER_REC
        ldx #1
        jsr ReadRec
        bcs :+
        dec hasHead
        jsr MarkRec
:       lda #FOOTER_REC
        ldx #2
        jsr ReadRec
        bcs :+
        dec hasFoot
        jsr MarkRec
:       lda #0
        sta recNo
@page:  lda recNo
        ldx #0
        jsr ReadRec
        bcs @next
        inc nPages
        jsr Wide
        jsr MarkRec
@next:  inc recNo
        lda recNo
        cmp #PAGES
        bcc @page
        jmp Place

; Wide: docWidth = 640 when the page in PAGEBUF starts with a ruler
; whose right margin passes 480 and the document is not V2.0.
Wide:   bit docV20
        bmi @end
        lda PAGEBUF
        cmp #ESC_RULER
        bne @end
        lda PAGEBUF + R_RIGHT   ; right - 481 >= 0
        cmp #<481
        lda PAGEBUF + R_RIGHT + 1
        sbc #>481
        bcc @end
        lda #<640
        sta docWidth
        lda #>640
        sta docWidth + 1
@end:   rts

; MarkRec: every character of the record at tp under its font and style
; marked in its Type 3 font (gwps prescan: the state starts plain, font
; 0, in each record).
MarkRec:
        lda #0
        sta curFid
        sta curFid + 1
        sta curStyle
@loop:  jsr Token
        cmp #T_END
        beq @end
        cmp #T_FONT
        bne :+
        ldy #1
        lda (tp),y
        sta curFid
        iny
        lda (tp),y
        sta curFid + 1
        iny
        lda (tp),y
        sta curStyle
        jsr KeepFid
        lda #T_FONT
        jsr Next
        jmp @loop
:       cmp #T_CHAR
        bne @other
        lda curFid
        ldx curFid + 1
        ldy curStyle
        jsr KeyOf
        ldy #0
        lda (tp),y
        jsr Mark
        lda #T_CHAR
@other: jsr Next
        jmp @loop
@end:   rts

; KeepFid: curFid in the list of font IDs the document uses (FindFonts
; then looks for their files), unless it is there or the list is full.
KeepFid:
        ldx #0
@each:  cpx nFid
        beq @add
        lda fidLo,x
        cmp curFid
        bne :+
        lda fidHi,x
        cmp curFid + 1
        beq @end
:       inx
        bne @each
@add:   cpx #FID_MAX
        bcs @end
        lda curFid
        sta fidLo,x
        lda curFid + 1
        sta fidHi,x
        inc nFid
@end:   rts

; FindFonts: a slot for each font ID the first pass found (font.s
; FindFont; the record file closed). Destroys all.
FindFonts:
        lda #0
        sta fidAt
@each:  ldx fidAt
        cpx nFid
        bcs @end
        lda fidLo,x
        pha
        lda fidHi,x
        tax
        pla
        jsr FindFont
        inc fidAt
        bne @each
@end:   rts

; KeyOf: X = the Type 3 font of the font ID A/X (lo/hi) in style Y (the
; system font's IDs 0 and 128 as one, BSW 9: "G0_9"; the style's
; CELL_STYLES), added when new (KEY_MAX at most: the last used again).
; Destroys A, Y.
KeyOf:  sta kFid
        stx kFid + 1
        tya
        and #CELL_STYLES
        sta kStyle
        lda kFid + 1            ; family (fid >> 6) 0 or 128: fid's high
        and #$DF                ; byte 0 or $20 and its bits 6-7 clear
        bne @find
        lda kFid
        and #$C0
        bne @find
        lda #9
        sta kFid
        lda #0
        sta kFid + 1
@find:  ldx #0
@each:  cpx nKey
        beq @add
        lda keyFid,x
        cmp kFid
        bne :+
        lda keyFidH,x
        cmp kFid + 1
        bne :+
        lda keyStyle,x
        cmp kStyle
        beq @end
:       inx
        bne @each
@add:   cpx #KEY_MAX
        bcc :+
        dex
        rts
:       lda kFid
        sta keyFid,x
        lda kFid + 1
        sta keyFidH,x
        lda kStyle
        sta keyStyle,x
        txa                     ; its glyphs: none yet
        jsr GlyphRow
        ldy #11
        lda #0
:       sta (gp),y
        dey
        bpl :-
        inc nKey
@end:   rts

; GlyphRow: gp = key A's 12-byte glyph bitmap (characters 32-127).
; Keeps X, Y.
GlyphRow:
        sta tmp                 ; A * 12 = (A * 4) * 3
        lda #0
        sta tmp + 1
        asl tmp
        rol tmp + 1
        asl tmp
        rol tmp + 1
        lda tmp
        asl a
        sta gp
        lda tmp + 1
        rol a
        sta gp + 1
        lda gp
        clc
        adc tmp
        sta gp
        lda gp + 1
        adc tmp + 1
        sta gp + 1
        lda gp
        clc
        adc #<glyphs
        sta gp
        lda gp + 1
        adc #>glyphs
        sta gp + 1
        rts

; Mark: character A (32-127) in key X's glyph bitmap. Keeps X.
Mark:   stx kSave
        sec
        sbc #32
        pha
        txa
        jsr GlyphRow
        pla
        pha
        lsr a
        lsr a
        lsr a
        tay
        pla
        and #7
        tax
        lda (gp),y
        ora BitOf,x
        sta (gp),y
        ldx kSave
        rts

; Marked: Z clear when character A is marked in key `key`.
Marked: sec
        sbc #32
        pha
        lda key
        jsr GlyphRow
        pla
        pha
        lsr a
        lsr a
        lsr a
        tay
        pla
        and #7
        tax
        lda (gp),y
        and BitOf,x
        rts
BitOf:  .byte $01, $02, $04, $08, $10, $20, $40, $80

; Place: x0 = (paper width - width * 90 + 1) / 2 and y0 = (paper height
; + page height * 90 + 1) / 2, in hundredths of a point, rounded half
; up (gwps write).
Place:  lda docWidth
        ldx docWidth + 1
        jsr Times90             ; n24 = width * 90
        lda paperW              ; n24 = paperW - n24
        sec
        sbc n24
        sta n24
        lda paperW + 1
        sbc n24 + 1
        sta n24 + 1
        lda paperW + 2
        sbc n24 + 2
        sta n24 + 2
        jsr Half
        lda n24
        sta x0
        lda n24 + 1
        sta x0 + 1
        lda n24 + 2
        sta x0 + 2
        lda pageH
        ldx pageH + 1
        jsr Times90             ; n24 = paperH + page height * 90
        lda paperH
        clc
        adc n24
        sta n24
        lda paperH + 1
        adc n24 + 1
        sta n24 + 1
        lda paperH + 2
        adc n24 + 2
        sta n24 + 2
        jsr Half
        lda n24
        sta y0
        lda n24 + 1
        sta y0 + 1
        lda n24 + 2
        sta y0 + 2
        rts

; Times90: n24 = A/X * 90 (shift and add over 90's bits).
Times90:
        sta tmp
        stx tmp + 1
        lda #0
        sta n24
        sta n24 + 1
        sta n24 + 2
        sta tmp2
        lda #90
        sta mul
@bit:   lsr mul
        bcc :+
        lda n24
        clc
        adc tmp
        sta n24
        lda n24 + 1
        adc tmp + 1
        sta n24 + 1
        lda n24 + 2
        adc tmp2
        sta n24 + 2
:       asl tmp
        rol tmp + 1
        rol tmp2
        lda mul
        bne @bit
        rts

; Half: n24 = (n24 + 1) / 2.
Half:   inc n24
        bne :+
        inc n24 + 1
        bne :+
        inc n24 + 2
:       lsr n24 + 2
        ror n24 + 1
        ror n24
        rts

; --- The prolog ---------------------------------------------------------

; Prolog: the file's head, the procedures and the Type 3 fonts, up to
; the page setup (gwps Writer.write).
Prolog: jsr PutI
        .byte "%!PS-Adobe-3.0", 10, "%%Title: ", 0
        lda #<docName
        ldx #>docName
        jsr PutZ
        jsr PutI
        .byte 10, "%%Creator: GeoUltra gwtool ps", 10, "%%Pages: ", 0
        lda nPages
        ldx #0
        jsr PutDec
        jsr PutI
        .byte 10, "%%BoundingBox: 0 0 ", 0
        lda #<paperW
        ldx #>paperW
        jsr Points
        jsr PutSp
        lda #<paperH
        ldx #>paperH
        jsr Points
        jsr PutI
        .byte 10, "%%EndComments", 10, "%%BeginProlog", 10
        .byte "/M {moveto} bind def /S {show} bind def", 10
        .byte "/W {/ww exch def /st exch def gsave currentpoint translate st stringwidth pop dup 0 gt", 10
        .byte " {ww exch div} {pop 1} ifelse 1 scale 0 0 moveto st show grestore} bind def", 10
        .byte "/OW {/ww exch def /st exch def gsave currentpoint translate st stringwidth pop dup 0 gt", 10
        .byte " {ww exch div} {pop 1} ifelse 1 scale 0 0 moveto st true charpath 0.5 setlinewidth stroke", 10
        .byte " grestore} bind def", 10
        .byte "/SF {/sz exch def findfont [sz 0 0 sz neg 0 0] makefont setfont} bind def", 10
        .byte "/BOX {4 2 roll moveto dup 0 exch rlineto exch 0 rlineto neg 0 exch rlineto closepath fill} bind def", 10
        .byte "/PIC {/h exch def /w exch def /y exch def /x exch def /d exch def gsave x y translate w h scale "
        .byte "w h true [w 0 0 h 0 0] {d} imagemask grestore} bind def", 10, 0
        lda #0
        sta key
@font:  lda key
        cmp nKey
        bcs @setup
        jsr Type3
        inc key
        bne @font
@setup: jsr PutI
        .byte "%%EndProlog", 10, "%%BeginSetup", 10, "<< /PageSize [", 0
        lda #<paperW
        ldx #>paperW
        jsr Hund
        jsr PutSp
        lda #<paperH
        ldx #>paperH
        jsr Hund
        jsr PutI
        .byte "] >> setpagedevice", 10, "%%EndSetup", 10, 0
        rts

; Load3: n24 = the 3 bytes at A/X. Hund: them as "w.ff". Points: as
; whole points, rounded ((v + 50) / 100).
Load3:  sta op
        stx op + 1
        ldy #0
        lda (op),y
        sta n24
        iny
        lda (op),y
        sta n24 + 1
        iny
        lda (op),y
        sta n24 + 2
        rts
Hund:   jsr Load3
        jmp PutHund
Points: jsr Load3
        lda n24
        clc
        adc #50
        sta n24
        bcc :+
        inc n24 + 1
        bne :+
        inc n24 + 2
:       lda #0                  ; n24 / 100
        sta quot
        sta quot + 1
@div:   lda n24
        sec
        sbc #100
        tax
        lda n24 + 1
        sbc #0
        sta tmp
        lda n24 + 2
        sbc #0
        bcc @done
        sta n24 + 2
        lda tmp
        sta n24 + 1
        stx n24
        inc quot
        bne @div
        inc quot + 1
        bne @div
@done:  lda quot
        ldx quot + 1
        jmp PutDec

; Type3: key `key`'s Type 3 font (gwps type3_def): its name, then each
; marked glyph ("Encoding c /gc put", "Glyphs /gc [w b h <hex>] put").
Type3:  ldx key                 ; its font's image in FONTBUF
        lda keyFid,x
        pha
        lda keyFidH,x
        tax
        pla
        jsr SlotAX
        pha
        jsr LoadImage
        pla
        jsr UseSlot
        lda #'/'
        jsr PutC
        jsr Name
        jsr PutI
        .byte " 9 dict dup begin", 10
        .byte "/FontType 3 def /FontMatrix [1 0 0 -1 0 0] def /FontBBox [0 -64 640 64] def", 10
        .byte "/Encoding 256 array def 0 1 255 {Encoding exch /.notdef put} for", 10
        .byte "/Glyphs ", 0
        jsr Count               ; its glyphs + 1
        clc
        adc #1
        ldx #0
        jsr PutDec
        jsr PutI
        .byte " dict def", 10, "Glyphs /.notdef [0 0 0 <>] put", 10, 0
        lda #32
        sta ch
@ch:    lda ch
        jsr Marked
        beq @next
        jsr PutI
        .byte "Encoding ", 0
        jsr PutCh
        jsr PutI
        .byte " /g", 0
        jsr PutCh
        jsr PutI
        .byte " put", 10, "Glyphs /g", 0
        jsr PutCh
        jsr PutI
        .byte " [", 0
        ldx key
        lda keyStyle,x
        tax
        lda ch
        jsr GlyphSetup
        lda glyphW
        jsr PutNum
        jsr PutSp
        lda fBase
        jsr PutNum
        jsr PutSp
        lda fHeight
        jsr PutNum
        jsr PutI
        .byte " <", 0
        jsr GlyphBits
        jsr PutI
        .byte ">] put", 10, 0
@next:  inc ch
        lda ch
        cmp #128
        bcc @ch
        jsr PutI
        .byte "/BuildGlyph {exch /Glyphs get exch get aload pop /d exch def /h exch def /b exch def /w exch def", 10
        .byte " w 0 0 b neg w h b sub setcachedevice", 10
        .byte " w 0 gt h 0 gt and {gsave 0 b neg translate w h scale", 10
        .byte " w h true [w 0 0 h 0 0] {d} imagemask grestore} if} bind def", 10
        .byte "/BuildChar {1 index /Encoding get exch get 1 index /BuildGlyph get exec} bind def", 10
        .byte "end definefont pop", 10, 0
        rts

; PutCh: ch as a number. PutNum: A as a number.
PutCh:  lda ch
PutNum: ldx #0
        jmp PutDec

; Count: A = the glyphs marked in key `key`.
Count:  lda key
        jsr GlyphRow
        lda #0
        sta tmp
        ldy #11
@byte:  lda (gp),y
@bit:   beq @next
        lsr a
        bcc @bit
        inc tmp
        bne @bit                ; (always: tmp < 96)
@next:  dey
        bpl @byte
        lda tmp
        rts

; Name: key `key`'s name: G<family>_<size>_<style>.
Name:   lda #'G'
        jsr PutC
        ldx key
        lda keyFid,x            ; family: fid >> 6
        sta tmp
        lda keyFidH,x
        sta tmp + 1
        ldy #6
:       lsr tmp + 1
        ror tmp
        dey
        bne :-
        lda tmp
        ldx tmp + 1
        jsr PutDec
        lda #'_'
        jsr PutC
        ldx key
        lda keyFid,x
        and #63
        jsr PutNum
        lda #'_'
        jsr PutC
        ldx key
        lda keyStyle,x
        jmp PutNum

; --- The pages ------------------------------------------------------------

; Pages: every page record: "%%Page: n n", the page's placement, the
; header and footer (not on a title page's first page), the body; then
; the file's end.
Pages:  lda #0
        sta recNo
        sta pageNo
@page:  lda recNo
        ldx #0
        jsr ReadRec
        bcc :+
        jmp @next
:       inc pageNo
        jsr PutI
        .byte "%%Page: ", 0
        lda pageNo
        jsr PutNum
        jsr PutSp
        lda pageNo
        jsr PutNum
        jsr PutI
        .byte 10, "gsave ", 0
        lda #<x0
        ldx #>x0
        jsr Hund
        jsr PutSp
        lda #<y0
        ldx #>y0
        jsr Hund
        jsr PutI
        .byte " translate 0.9 -0.9 scale", 10, 0
        lda #0
        sta bodyTop
        sta bodyTop + 1
        lda hdrFlags            ; a title page: no header or footer on it
        bpl :+
        lda pageNo
        cmp #1
        beq @body
:       jsr HeadFoot
        lda recNo               ; (the page again: recEnd is the footer's)
        ldx #0
        jsr ReadRec
@body:  lda bodyTop
        sta top
        lda bodyTop + 1
        sta top + 1
        jsr Record
        jsr PutI
        .byte "grestore showpage", 10, 0
@next:  inc recNo
        lda recNo
        cmp #PAGES
        bcs :+
        jmp @page
:       jsr PutI
        .byte "%%EOF", 10, 0
        rts

; HeadFoot: the header from the top (bodyTop then its height: the file
; header's, or its lines' when that is 0), the footer up to the page's
; end (its height the file header's, or its lines').
HeadFoot:
        bit hasHead
        bpl @foot
        lda #HEADER_REC
        ldx #1
        jsr ReadRec
        lda #0
        sta top
        sta top + 1
        jsr Record
        lda headH
        ldx headH + 1
        bne :+
        cmp #0
        bne :+
        lda sum
        ldx sum + 1
:       sta bodyTop
        stx bodyTop + 1
@foot:  bit hasFoot
        bpl @end
        lda footH
        sta fh
        lda footH + 1
        sta fh + 1
        ora fh
        bne :+
        lda #FOOTER_REC         ; (none kept: its lines' height, from a
        ldx #2                  ; run that writes nothing)
        jsr ReadRec
        lda #$80
        sta dry
        jsr Record
        lda #0
        sta dry
        lda sum
        sta fh
        lda sum + 1
        sta fh + 1
:       lda #FOOTER_REC
        ldx #2
        jsr ReadRec
        lda pageH
        sec
        sbc fh
        sta top
        lda pageH + 1
        sbc fh + 1
        sta top + 1
        jsr Record
@end:   rts

; Record: the record at tp laid out from y = top (gwps layout): rulers
; taken, pictures as lines of their own (picture.s), the rest by
; Measure; sum = the lines' height. dry ($80): measured only.
Record: jsr StateInit
        lda #0
        sta sum
        sta sum + 1
        lda #$80
        sta first
@loop:  jsr Token
        cmp #T_END
        beq @end
        cmp #T_RULER            ; (taken here: before a picture it makes
        bne :+                  ; no empty line)
        lda tp
        sta rp
        lda tp + 1
        sta rp + 1
        lda #T_RULER
        jsr Next
        jmp @loop
:       cmp #T_PIC
        bne @text
        jsr Picture             ; (its line: Down)
        lda #T_PIC
        jsr Next
        lda #$80
        sta first
        jmp @loop
@text:  jsr Measure
        bit dry
        bmi :+
        jsr Line
:       lda lineH
        ldx #0
        jsr Down
        lda ended
        sta first
        jmp @loop
@end:   rts

; Down: top and sum += A/X (lo/hi).
Down:   stx tmp
        pha
        clc
        adc top
        sta top
        lda top + 1
        adc tmp
        sta top + 1
        pla
        clc
        adc sum
        sta sum
        lda sum + 1
        adc tmp
        sta sum + 1
        rts

; Line: the line's pieces as runs (one combination, each piece where
; the one before ends), each "/<font> 1 SF x y M (text) S".
Line:   lda top                 ; y = top + the baseline
        clc
        adc lineB
        sta lineY
        lda top + 1
        adc #0
        sta lineY + 1
        ldx #0
@run:   cpx nch
        bcs @end
        stx runAt
@more:  lda CHX_LO,x            ; this piece's end: x + w
        clc
        adc CHW,x
        sta tmp
        lda CHX_HI,x
        adc #0
        sta tmp + 1
        inx
        cpx nch
        bcs @put
        lda CHK,x               ; the same combination, at that end?
        cmp CHK - 1,x
        bne @put
        lda CHX_LO,x
        cmp tmp
        bne @put
        lda CHX_HI,x
        cmp tmp + 1
        beq @more
@put:   stx runEnd
        jsr Run
        ldx runEnd
        jmp @run
@end:   rts

; Run: the pieces runAt..runEnd-1 as one show in their Type 3 font.
Run:    ldx runAt
        ldy CHK,x               ; the combination's font ID and style
        lda comboStyle,y
        sta rStyle
        lda comboFidH,y
        tax
        lda comboFid,y
        ldy rStyle
        jsr KeyOf
        stx key
        lda #'/'
        jsr PutC
        jsr Name
        jsr PutI
        .byte " 1 SF ", 0
        ldx runAt
        lda CHX_HI,x
        pha
        lda CHX_LO,x
        tay
        pla
        tax
        tya
        jsr PutDec
        jsr PutSp
        lda lineY
        ldx lineY + 1
        jsr PutDec
        jsr PutI
        .byte " M (", 0
        ldx runAt
@ch:    lda CHC,x
        cmp #'('
        beq @esc
        cmp #')'
        beq @esc
        cmp #$5C                ; (a backslash)
        bne @put
@esc:   pha
        lda #$5C
        jsr PutC
        pla
@put:   jsr PutC
        inx
        cpx runEnd
        bcc @ch
        jsr PutI
        .byte ") S", 10, 0
        rts

; --- Data -----------------------------------------------------------------

        .segment "BSS"

docWidth: .res 2
docV20: .res 1
nPages: .res 1
hdrFlags: .res 1
headH:  .res 2
footH:  .res 2
pageH:  .res 2
hasHead: .res 1
hasFoot: .res 1
which:  .res 1
recNo:  .res 1
pageNo: .res 1
nKey:   .res 1
nFid:   .res 1
fidAt:  .res 1
fidLo:  .res FID_MAX
fidHi:  .res FID_MAX
key:    .res 1
kFid:   .res 2
kStyle: .res 1
kSave:  .res 1
keyFid: .res KEY_MAX
keyFidH: .res KEY_MAX
keyStyle: .res KEY_MAX
glyphs: .res KEY_MAX * 12
ch:     .res 1
quot:   .res 2
top:    .res 2
bodyTop: .res 2
sum:    .res 2
fh:     .res 2
dry:    .res 1
lineY:  .res 2
runAt:  .res 1
runEnd: .res 1
tmp2:   .res 1
mul:    .res 1
rStyle: .res 1
x0:     .res 3
y0:     .res 3
