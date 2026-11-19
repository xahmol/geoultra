; GU PostScript: geoWrite's line measure (tools/gwps.py measure, tab_to;
; Michael Steil, "Inside geoWrite - 7", behaviour only; the rules
; geoWrite's printout taught, tests/print/psref.py). Measure lays out one
; line from the token pointer tp: its characters' x, width, code and
; combination (font ID and style: Combo) in the CH* arrays, aligned,
; without tabs and trailing spaces; its height and baseline. Own code.

        .include "psw.inc"

        .export Measure, Combo, Token, Next, StateInit, nch, lineH, lineB, ended, first, recEnd
        .export curFid, curStyle, comboFid, comboFidH, comboStyle, nCombo, COMBO_MAX
        .import Width, Height, Base

COMBO_MAX       = 64

        .segment "CODE"

; Token: A = the kind of the token at tp (T_* below), tp unchanged; at
; the record's end (recEnd, or a zero byte) T_END. Keeps X, Y.
; (T_* in psw.inc; a character's code in tokC)
Token:  sty keepY
        lda tp + 1
        cmp recEnd + 1
        bcc :+
        bne @end
        lda tp
        cmp recEnd
        bcs @end
:       ldy #0
        lda (tp),y
        beq @end
        sta tokC
        ldy #T_RULER
        cmp #ESC_RULER
        beq @kind
        ldy #T_FONT
        cmp #ESC_NEWCARDSET
        beq @kind
        ldy #T_PIC
        cmp #ESC_GRAPHICS
        beq @kind
        ldy #T_TAB
        cmp #TAB
        beq @kind
        ldy #T_CR
        cmp #CR
        beq @kind
        cmp #PAGE_BREAK
        beq @kind
        ldy #T_SKIP
        cmp #$20
        bcc @kind
        cmp #$80
        bcs @kind
        ldy #T_CHAR
@kind:  tya
        ldy keepY
        rts
@end:   lda #T_END
        ldy keepY
        rts

; Next: tp past the token of kind A (T_*). Keeps A, X, Y.
Next:   stx nextX
        pha
        tax
        lda TokLen,x
        clc
        adc tp
        sta tp
        bcc :+
        inc tp + 1
:       ldx nextX
        pla
        rts
TokLen: .byte 0, 1, 1, 1, RULER_LEN, 4, 5, 1

; StateInit: a record's state at its start: no ruler, font 0 plain
; (gwps layout's initial state). Destroys A, X, Y.
StateInit:
        lda #0
        sta rp
        sta rp + 1
        sta curFid
        sta curFid + 1
        sta curStyle
        jsr Combo
        stx curCombo
        rts

; TakeFont: the NewCardSet at tp as curFid, curStyle, curCombo.
; Destroys A, X, Y.
TakeFont:
        ldy #1
        lda (tp),y
        sta curFid
        iny
        lda (tp),y
        sta curFid + 1
        iny
        lda (tp),y
        sta curStyle
        jsr Combo
        stx curCombo
        rts

; Combo: X = the combination of curFid and curStyle (added when new;
; COMBO_MAX at most: the last one is used again). Destroys A, Y.
Combo:  ldx #0
@find:  cpx nCombo
        beq @add
        lda comboFid,x
        cmp curFid
        bne :+
        lda comboFidH,x
        cmp curFid + 1
        bne :+
        lda comboStyle,x
        cmp curStyle
        beq @end
:       inx
        bne @find
@add:   cpx #COMBO_MAX
        bcc :+
        dex
        rts
:       lda curFid
        sta comboFid,x
        lda curFid + 1
        sta comboFidH,x
        lda curStyle
        sta comboStyle,x
        inc nCombo
@end:   rts

; Measure: one line from tp (first: $80 when it is a paragraph's first
; line). Returns nch pieces in the CH* arrays (x aligned), lineH, lineB,
; ended ($80: the paragraph ended); tp at the next line. The ruler in
; force is rp (0: none: margins 0 and 480). Destroys A, X, Y, r-regs.
Measure:
@rul:   jsr Token               ; (the paragraph's own ruler first)
        cmp #T_RULER
        bne :+
        jsr TakeRuler
        lda #T_RULER
        jsr Next
        jmp @rul
:       jsr Margins             ; left (the paragraph margin on a first
        lda left                ; line), right
        sta curX
        lda left + 1
        sta curX + 1
        lda #0
        sta nch
        sta ended
        sta spaceAt             ; ($80: a space seen on the line)
@loop:  jsr Token
        cmp #T_RULER
        bne :+
        jsr TakeRuler
        jsr Margins2            ; (only the right margin changes)
        lda #T_RULER
        jsr Next
        jmp @loop
:       cmp #T_FONT
        bne :+
        jsr TakeFont
        lda #T_FONT
        jsr Next
        jmp @loop
:       cmp #T_SKIP
        bne :+
        jsr Next
        jmp @loop
:       cmp #T_CR
        bne :+
        jsr Next
        jmp @ends
:       cmp #T_PIC
        beq @ends
        cmp #T_END              ; (the record's end: the paragraph goes on
        bne :+                  ; on the next page, so not ended)
        jmp Finish
:
        cmp #T_TAB
        bne @char
        jsr Next
        jsr TabTo
        lda #0                  ; a tab mark: code 0, width 0
        jsr Add
        jmp @loop
@ends:  lda #$80
        sta ended
        jmp Finish
@char:  lda tokC                ; its width in the style
        ldx curStyle
        jsr Width
        sta w
        lda curX                   ; x + w > right, with characters: the end
        clc
        adc w
        sta tmp
        lda curX + 1
        adc #0
        sta tmp + 1
        lda right
        cmp tmp
        lda right + 1
        sbc tmp + 1
        bcs @fits
        lda nch
        beq @fits
        lda tokC                ; a space that overflows: the line ends
        cmp #' '                ; there, its word kept
        bne :+
        lda #T_CHAR
        jsr Next
        jmp Finish
:       bit spaceAt             ; else back to after the last space
        bpl :+
        jsr Restore
:       jmp Finish
@fits:  lda tokC
        jsr Add
        lda curX
        clc
        adc w
        sta curX
        bcc :+
        inc curX + 1
:       lda #T_CHAR
        jsr Next
        lda tokC
        cmp #' '
        bne :+
        jsr Save
:       jmp @loop

; Add: a character (code A; 0 a tab mark) at x, width w (0 for a tab),
; in curCombo, to the CH* arrays (LINE_MAX at most: more are dropped).
Add:    ldx nch
        cpx #LINE_MAX
        bcs @end
        sta CHC,x
        lda curX
        sta CHX_LO,x
        lda curX + 1
        sta CHX_HI,x
        lda CHC,x
        beq :+
        lda w
:       sta CHW,x
        lda curCombo
        sta CHK,x
        inc nch
@end:   rts

; Save, Restore: the state after a space (the place, the characters
; kept, the font, style and ruler) and back to it.
Save:   lda tp
        sta sTp
        lda tp + 1
        sta sTp + 1
        lda nch
        sta sNch
        lda curFid
        sta sFid
        lda curFid + 1
        sta sFid + 1
        lda curStyle
        sta sStyle
        lda curCombo
        sta sCombo
        lda rp
        sta sRp
        lda rp + 1
        sta sRp + 1
        lda #$80
        sta spaceAt
        rts
Restore:
        lda sTp
        sta tp
        lda sTp + 1
        sta tp + 1
        lda sNch
        sta nch
        lda sFid
        sta curFid
        lda sFid + 1
        sta curFid + 1
        lda sStyle
        sta curStyle
        lda sCombo
        sta curCombo
        lda sRp
        sta rp
        lda sRp + 1
        sta rp + 1
        rts

; TakeRuler: rp = the ruler at tp.
TakeRuler:
        lda tp
        sta rp
        lda tp + 1
        sta rp + 1
        rts

; Margins: left (the paragraph margin when first is set) and right from
; rp (none: 0 and 480). Margins2: the right margin only.
Margins:
        lda #0
        sta left
        sta left + 1
        lda rp + 1
        beq Margins2
        ldy #R_LEFT
        bit first
        bpl :+
        ldy #R_PARA
:       lda (rp),y
        sta left
        iny
        lda (rp),y
        sta left + 1
Margins2:
        lda #<480
        sta right
        lda #>480
        sta right + 1
        lda rp + 1
        beq :+
        ldy #R_RIGHT
        lda (rp),y
        sta right
        iny
        lda (rp),y
        sta right + 1
:       rts

; TabTo: x = where a TAB at x goes (gwps tab_to): the first tab stop
; past x and before the right margin; a decimal stop (bit 15) less the
; width of the text after the TAB up to its next full stop (not below
; x). No stop: x stays. tp is after the TAB.
TabTo:  lda rp + 1
        beq @end
        ldy #R_TABS
@stop:  lda (rp),y              ; pos = the stop & $7FFF
        sta pos
        iny
        lda (rp),y
        sta decStop
        and #$7F
        sta pos + 1
        iny
        lda pos                 ; pos >= right: unused
        cmp right
        lda pos + 1
        sbc right + 1
        bcs @no
        lda curX                   ; pos <= x: passed
        cmp pos
        lda curX + 1
        sbc pos + 1
        bcs @no
        bit decStop
        bmi @dec
        lda pos
        sta curX
        lda pos + 1
        sta curX + 1
        rts
@no:    cpy #R_TABS + 16
        bcc @stop
@end:   rts
@dec:   jsr DecWidth            ; x = max(x, pos - width)
        lda pos
        sec
        sbc tmp
        sta tmp
        lda pos + 1
        sbc tmp + 1
        sta tmp + 1
        bcc @end                ; (below 0: x stays)
        lda tmp
        cmp curX
        lda tmp + 1
        sbc curX + 1
        bcc @end
        lda tmp
        sta curX
        lda tmp + 1
        sta curX + 1
        rts

; DecWidth: tmp = the width of the characters from tp to the next full
; stop or the first other token (fonts followed). tp, the font and the
; style are left as they were.
DecWidth:
        lda tp
        pha
        lda tp + 1
        pha
        lda curStyle
        pha
        lda #0
        sta tmp
        sta tmp + 1
@loop:  jsr Token
        cmp #T_FONT
        bne :+
        ldy #3
        lda (tp),y
        sta curStyle
        lda #T_FONT
        jsr Next
        jmp @loop
:       cmp #T_CHAR
        bne @end
        lda tokC
        cmp #'.'
        beq @end
        ldx curStyle
        jsr Width
        clc
        adc tmp
        sta tmp
        bcc :+
        inc tmp + 1
:       lda #T_CHAR
        jsr Next
        jmp @loop
@end:   pla
        sta curStyle
        pla
        sta tp + 1
        pla
        sta tp
        rts

; Finish: the line's height and baseline (the largest of its
; characters' combinations, or the one in force when it has none; with
; its leading and spacing), then the alignment.
Finish: lda #0
        sta hi
        sta base
        ldx nch
        beq @none
@each:  dex
        ldy CHK,x
        jsr Metrics
        txa
        bne @each
        beq @spc
@none:  ldy curCombo
        jsr Metrics
@spc:   lda hi                  ; h = hi + LEADING
        clc
        adc #LEADING
        sta h
        sta lineH
        ldx #0                  ; the ruler's spacing: 1, 1.5, 2
        lda rp + 1
        beq @set
        ldy #R_FLAGS
        lda (rp),y
        lsr a
        lsr a
        and #3
        tax
@set:   cpx #1
        bne :+
        lda h                   ; 1.5: h * 3 / 2
        lsr a
        clc
        adc h
        sta lineH               ; (h + h / 2 = h * 3 // 2)
        jmp @base
:       cpx #2
        bne @base
        lda h
        asl a
        sta lineH
@base:  lda lineH               ; the baseline: the room above the text
        sec
        sbc h
        clc
        adc base
        sta lineB
        jmp Align

; Metrics: hi, base = the larger of them and combination Y's height and
; baseline. Keeps X.
Metrics:
        stx keepX
        ldx comboStyle,y
        jsr Height
        cmp hi
        bcc :+
        sta hi
:       jsr Base
        cmp base
        bcc :+
        sta base
:       ldx keepX
        rts

; Align: the text (the characters but tabs and the trailing spaces)
; moved by the alignment (centred, right; justified: the spaces widened
; but on a paragraph's last line) and kept in the CH* arrays alone.
Align:  lda #0
        sta nGaps
        ldx nch                 ; last = the last text character
@back:  dex
        cpx #$FF
        beq @empty
        lda CHC,x
        beq @back               ; (a tab)
        cmp #' '
        beq @back
        stx last
        lda CHX_LO,x            ; end = its x + w
        clc
        adc CHW,x
        sta tmp
        lda CHX_HI,x
        adc #0
        sta tmp + 1
        jmp @shift
@empty: lda #$FF
        sta last
        lda left
        sta tmp
        lda left + 1
        sta tmp + 1
@shift: lda right               ; room = right - end
        sec
        sbc tmp
        sta room
        lda right + 1
        sbc tmp + 1
        sta room + 1
        lda #0
        sta shift
        sta shift + 1
        sta per
        sta more
        ldx #0
        lda rp + 1
        beq @move
        ldy #R_FLAGS
        lda (rp),y
        and #3
        tax
        cpx #1
        bne :+
        lda room + 1            ; centred: room / 2 (rounded down)
        cmp #$80
        ror a
        sta shift + 1
        lda room
        ror a
        sta shift
        jmp @move
:       cpx #2
        bne :+
        lda room
        sta shift
        lda room + 1
        sta shift + 1
        jmp @move
:       cpx #3
        bne @move
        bit ended
        bmi @move
        jsr Gaps                ; justified: per gap and the first `more`
@move:  ldy #0                  ; the pieces, in place
        ldx #0
        lda #0
        sta acc
        sta acc + 1
        sta gapNo
@each:  cpx nch
        beq @done
        lda CHC,x
        beq @skip               ; (a tab)
        lda last
        cmp #$FF
        beq @skip
        cpx last
        beq :+
        bcs @skip               ; (a trailing space)
:       lda CHX_LO,x            ; x + shift + acc
        clc
        adc shift
        sta tmp
        lda CHX_HI,x
        adc shift + 1
        sta tmp + 1
        lda tmp
        clc
        adc acc
        sta CHX_LO,y
        lda tmp + 1
        adc acc + 1
        sta CHX_HI,y
        lda CHW,x
        sta CHW,y
        lda CHC,x
        sta CHC,y
        lda CHK,x
        sta CHK,y
        iny
        jsr Share               ; (after a gap: its share)
@skip:  inx
        bne @each
@done:  sty nch
        rts

; Share: after character X, a gap (a space, when justifying): acc +=
; per, and 1 more for the first `more` gaps. Keeps X, Y.
Share:  lda CHC,x
        cmp #' '
        bne @end
        lda nGaps
        beq @end
        lda acc
        clc
        adc per
        sta acc
        lda acc + 1
        adc per + 1
        sta acc + 1
        lda gapNo
        cmp more
        bcs :+
        inc acc
        bne :+
        inc acc + 1
:       inc gapNo
@end:   rts

; Gaps: nGaps = the spaces before the last text character; when there
; are any and room > 0: per, more = room / nGaps (the first `more` gaps
; one dot more). Else nGaps = 0.
Gaps:   lda #0
        sta nGaps
        lda last
        cmp #$FF
        beq @end
        ldx #0
@count: cpx last
        bcs :+
        lda CHC,x
        cmp #' '
        bne @n
        inc nGaps
@n:     inx
        bne @count
:       lda nGaps
        beq @end
        lda room + 1            ; room <= 0: nothing
        bmi @none
        ora room
        beq @none
        lda #0                  ; room / nGaps (16 by 8 bits)
        sta per
        sta per + 1
        lda room
        sta tmp
        lda room + 1
        sta tmp + 1
        ldx #16
        lda #0
@div:   asl tmp
        rol tmp + 1
        rol a
        bcs @sub                ; (over 255: certainly at least nGaps)
        cmp nGaps
        bcc :+
@sub:   sbc nGaps               ; (carry set)
        inc tmp
:       dex
        bne @div
        sta more                ; the rest: the first `more` gaps + 1
        lda tmp
        sta per
        lda tmp + 1
        sta per + 1
@end:   rts
@none:  lda #0
        sta nGaps
        rts

        .segment "BSS"

recEnd: .res 2
first:  .res 1
ended:  .res 1
nch:    .res 1
lineH:  .res 1
lineB:  .res 1
curFid: .res 2
curStyle: .res 1
curCombo: .res 1
nCombo: .res 1
comboFid: .res COMBO_MAX
comboFidH: .res COMBO_MAX
comboStyle: .res COMBO_MAX
tokC:   .res 1
keepX:  .res 1
nextX:  .res 1
keepY:  .res 1
curX:   .res 2
w:      .res 1
left:   .res 2
right:  .res 2
pos:    .res 2
decStop: .res 1
spaceAt: .res 1
sTp:    .res 2
sNch:   .res 1
sFid:   .res 2
sStyle: .res 1
sCombo: .res 1
sRp:    .res 2
hi:     .res 1
base:   .res 1
h:      .res 1
last:   .res 1
room:   .res 2
shift:  .res 2
per:    .res 2
more:   .res 1
acc:    .res 2
nGaps:  .res 1
gapNo:  .res 1
