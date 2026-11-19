; GU PostScript: a run in one of the LaserWriter fonts (font IDs 27-37:
; the LW fonts, GeoUltra's GU fonts) as the printer's own font, real
; text (tools/gwps.py real_text): each word placed where geoWrite has it
; and fitted to geoWrite's width for it (W, OW); reverse as a black box
; with white text, underline as a line under the run, outline stroked.
; Own code.

        .include "psw.inc"

        .export RealFam, RealRun
        .import runAt, runEnd, lineY, Width, fHeight, fBase
        .import PutC, PutI, PutZ, PutDec, PutSp

FAM_FIRST       = 27
FAM_LAST        = 37

        .segment "CODE"

; RealFam: C set when the font ID A/X (lo/hi) is a LaserWriter family
; (27-37); then fam = its family. Keeps Y.
RealFam:
        sta tmp
        stx tmp + 1
        ldx #6                  ; family = fid >> 6
:       lsr tmp + 1
        ror tmp
        dex
        bne :-
        lda tmp + 1
        bne @no
        lda tmp
        cmp #FAM_FIRST
        bcc @no
        cmp #FAM_LAST + 1
        bcs @no
        sta fam
        sec
        rts
@no:    clc
        rts

; RealRun: the pieces runAt..runEnd-1 (font ID family fam, size `size`,
; style `style`; their font's slot in use) as real text: [reverse: "x
; y-base w height BOX", "1 setgray"], "/<name> size SF", per word "x y M
; (word) ww W" (OW when outline), [underline: "x y+1 w 1 BOX"],
; [reverse: "0 setgray"].
RealRun:
        ldx runAt               ; the run's x and end
        lda CHX_LO,x
        sta x0
        lda CHX_HI,x
        sta x0 + 1
        ldx runEnd
        lda CHX_LO - 1,x
        clc
        adc CHW - 1,x
        sta xEnd
        lda CHX_HI - 1,x
        adc #0
        sta xEnd + 1
        lda style
        and #REVERSE
        beq @font
        lda x0                  ; the box: x, y - base, w, height
        ldx x0 + 1
        jsr PutDec
        jsr PutSp
        lda lineY
        sec
        sbc fBase
        pha
        lda lineY + 1
        sbc #0
        tax
        pla
        jsr PutDec
        jsr PutSp
        jsr RunW
        jsr PutSp
        lda fHeight
        ldx #0
        jsr PutDec
        jsr PutI
        .byte " BOX", 10, "1 setgray", 10, 0
@font:  lda #'/'                ; the font: its PostScript name, the size
        jsr PutC
        jsr Name
        jsr PutSp
        lda size
        ldx #0
        jsr PutDec
        jsr PutI
        .byte " SF", 10, 0
        ldx runAt               ; the words
@word:  cpx runEnd
        bcs @under
        lda CHC,x
        cmp #' '
        bne :+
        inx                     ; (a space: no output)
        bne @word
:       stx wAt
        lda #0
        sta ww
        sta ww + 1
@w:     lda CHC,x               ; to the word's end
        cmp #' '
        beq :+
        lda CHW,x
        clc
        adc ww
        sta ww
        bcc @n
        inc ww + 1
@n:     inx
        cpx runEnd
        bcc @w
:       stx wEnd
        jsr Word
        ldx wEnd
        jmp @word
@under: lda style
        and #UNDERLINE
        beq @rev
        lda x0                  ; x y+1 w 1 BOX
        ldx x0 + 1
        jsr PutDec
        jsr PutSp
        lda lineY
        clc
        adc #1
        pha
        lda lineY + 1
        adc #0
        tax
        pla
        jsr PutDec
        jsr PutSp
        jsr RunW
        jsr PutI
        .byte " 1 BOX", 10, 0
@rev:   lda style
        and #REVERSE
        beq @end
        jsr PutI
        .byte "0 setgray", 10, 0
@end:   rts

; RunW: the run's width (xEnd - x0) written.
RunW:   lda xEnd
        sec
        sbc x0
        pha
        lda xEnd + 1
        sbc x0 + 1
        tax
        pla
        jmp PutDec

; Word: the word wAt..wEnd-1 (width ww): "x y M (word) ww W" (OW when
; outline), x its first piece's (gwps: the word's end less its width).
Word:   ldx wAt
        lda CHX_LO,x
        pha
        lda CHX_HI,x
        tax
        pla
        jsr PutDec
        jsr PutSp
        lda lineY
        ldx lineY + 1
        jsr PutDec
        jsr PutI
        .byte " M (", 0
        ldx wAt
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
        cpx wEnd
        bcc @ch
        jsr PutI
        .byte ") ", 0
        lda ww
        ldx ww + 1
        jsr PutDec
        lda style
        and #OUTLINE
        beq :+
        jsr PutI
        .byte " OW", 10, 0
        rts
:       jsr PutI
        .byte " W", 10, 0
        rts

; Name: the PostScript name of family fam in the style: plain, bold,
; italic, bold italic (Symbol, Zapf Chancery, Zapf Dingbats have one).
Name:   lda fam
        sec
        sbc #FAM_FIRST
        asl a
        asl a                   ; (4 names a family)
        sta tmp
        lda style
        and #BOLD
        beq :+
        inc tmp
:       lda style
        and #ITALIC
        beq :+
        inc tmp
        inc tmp
:       lda tmp
        asl a
        tax
        lda Names,x
        pha
        lda Names + 1,x
        tax
        pla
        jmp PutZ

Names:  .word NTimes, NTimesB, NTimesI, NTimesBI
        .word NHelv, NHelvB, NHelvO, NHelvBO
        .word NSymbol, NSymbol, NSymbol, NSymbol
        .word NCour, NCourB, NCourO, NCourBO
        .word NAvant, NAvantD, NAvantO, NAvantDO
        .word NBook, NBookD, NBookI, NBookDI
        .word NNarrow, NNarrowB, NNarrowO, NNarrowBO
        .word NSchl, NSchlB, NSchlI, NSchlBI
        .word NPal, NPalB, NPalI, NPalBI
        .word NZapf, NZapf, NZapf, NZapf
        .word NDing, NDing, NDing, NDing
NTimes:   .byte "Times-Roman", 0
NTimesB:  .byte "Times-Bold", 0
NTimesI:  .byte "Times-Italic", 0
NTimesBI: .byte "Times-BoldItalic", 0
NHelv:    .byte "Helvetica", 0
NHelvB:   .byte "Helvetica-Bold", 0
NHelvO:   .byte "Helvetica-Oblique", 0
NHelvBO:  .byte "Helvetica-BoldOblique", 0
NSymbol:  .byte "Symbol", 0
NCour:    .byte "Courier", 0
NCourB:   .byte "Courier-Bold", 0
NCourO:   .byte "Courier-Oblique", 0
NCourBO:  .byte "Courier-BoldOblique", 0
NAvant:   .byte "AvantGarde-Book", 0
NAvantD:  .byte "AvantGarde-Demi", 0
NAvantO:  .byte "AvantGarde-BookOblique", 0
NAvantDO: .byte "AvantGarde-DemiOblique", 0
NBook:    .byte "Bookman-Light", 0
NBookD:   .byte "Bookman-Demi", 0
NBookI:   .byte "Bookman-LightItalic", 0
NBookDI:  .byte "Bookman-DemiItalic", 0
NNarrow:  .byte "Helvetica-Narrow", 0
NNarrowB: .byte "Helvetica-Narrow-Bold", 0
NNarrowO: .byte "Helvetica-Narrow-Oblique", 0
NNarrowBO: .byte "Helvetica-Narrow-BoldOblique", 0
NSchl:    .byte "NewCenturySchlbk-Roman", 0
NSchlB:   .byte "NewCenturySchlbk-Bold", 0
NSchlI:   .byte "NewCenturySchlbk-Italic", 0
NSchlBI:  .byte "NewCenturySchlbk-BoldItalic", 0
NPal:     .byte "Palatino-Roman", 0
NPalB:    .byte "Palatino-Bold", 0
NPalI:    .byte "Palatino-Italic", 0
NPalBI:   .byte "Palatino-BoldItalic", 0
NZapf:    .byte "ZapfChancery-MediumItalic", 0
NDing:    .byte "ZapfDingbats", 0

        .segment "BSS"

fam:    .res 1
size:   .res 1                  ; (set by the caller)
style:  .res 1                  ; (set by the caller)
x0:     .res 2
xEnd:   .res 2
wAt:    .res 1
wEnd:   .res 1
ww:     .res 2

        .export size, style
