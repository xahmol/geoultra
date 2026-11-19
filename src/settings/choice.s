; GeoUltra Settings: choice rows (docs/design/SETTINGS.md), the widget most
; pages are made of. A row is a label and two or more options, each
; with a box in front; the box of the option in force is filled. The
; option in force comes from the INI text (a section's key; a value not
; known or missing: the row's default); a click on an option sets the
; key in the text (ini.inc IniSet) and marks the settings changed. A
; page's overlay holds its table and hands it over (ChoiceDraw,
; ChoicePress); the table is read while that overlay is in place. Own
; design and code.
;
; Table: .byte rows, then per row (ROW_* offsets):
;   .byte baseline y; .addr label (0: none), section, key; .byte options,
;   default
;   then per option: .word x; .addr text, value (zero-ended; 0: no
;   value, the key taken out: an option meaning "as without the key",
;   which is the row's default then)

        .include "geos.inc"
        .include "settings.inc"

        .import IniFind, IniSet, IniDel, dirty, NoRoom
        .export ChoiceDraw, ChoicePress, sel

ROW_Y           = 0
ROW_LABEL       = 1
ROW_SECT        = 3
ROW_KEY         = 5
ROW_N           = 7
ROW_DEF         = 8
ROW_OPTS        = 9             ; the options from here, OPT_LEN each
OPT_X           = 0
OPT_TEXT        = 2
OPT_VAL         = 4
OPT_LEN         = 6
ROWS_MAX        = 8             ; rows a page has, at most
LABEL_X         = PAGE_LEFT + 2
BOX             = 7             ; a box: 7 x 7 pixels, its bottom on the
TEXT_DX         = 11            ; baseline; the option's text after it

        .segment "ZEROPAGE"

tp:             .res 2          ; the row (RowAt)
op:             .res 2          ; an option (OptAt)

        .segment "CODE"

; ChoiceDraw: A/X = a table: each row's option in force found in the
; INI text, the rows drawn (labels, boxes, texts).
ChoiceDraw:
        jsr Table
        lda #0
        sta row
@row:   lda row
        cmp rows
        bcs @end
        jsr Current
        jsr RowAt
        ldy #ROW_LABEL          ; the label (0: none)
        lda (tp),y
        sta r0L
        iny
        lda (tp),y
        sta r0H
        beq @texts
        lda #<LABEL_X
        sta r11L
        lda #>LABEL_X
        sta r11H
        jsr Base
        jsr PutString
@texts: lda #0                  ; the options' texts
        sta opt
@text:  lda opt
        jsr OptAt
        bcs @boxes
        ldy #OPT_TEXT
        lda (op),y
        sta r0L
        iny
        lda (op),y
        sta r0H
        jsr OptX                ; r11 = its x + TEXT_DX
        lda r11L
        clc
        adc #TEXT_DX
        sta r11L
        bcc :+
        inc r11H
:       jsr Base
        jsr PutString
        inc opt
        bne @text
@boxes: jsr Boxes
        inc row
        bne @row
@end:   rts

; ChoicePress: A/X = the table; the click at the pointer: on an option
; of a row, that option set (the key in the INI text, the row's boxes
; drawn again). Nothing elsewhere.
ChoicePress:
        jsr Table
        lda #0
        sta row
@row:   lda row
        cmp rows
        bcs @end
        jsr RowAt
        ldy #ROW_Y              ; the row's band: baseline - 9 to + 2
        lda (tp),y
        clc
        adc #2
        cmp mouseYPos
        bcc @next
        sbc #11
        cmp mouseYPos
        bcs @next
        lda #0                  ; the option: the last whose x is left of
        sta opt                 ; the pointer
        lda #$FF
        sta hit
@opt:   lda opt
        jsr OptAt
        bcs @set
        ldy #OPT_X + 1          ; its x <= the pointer's?
        lda mouseXPos+1
        cmp (op),y
        bcc @set
        bne :+
        dey
        lda mouseXPos
        cmp (op),y
        bcc @set
:       lda opt
        sta hit
        inc opt
        bne @opt
@set:   lda hit
        bmi @end                ; (left of the first option)
        ldx row
        cmp sel,x
        beq @end                ; (in force already)
        jmp Choose
@next:  inc row
        bne @row
@end:   rts

; Choose: option A of row `row` set: the key in the INI text, the boxes
; drawn again, the settings marked changed. A text too long for its
; buffer: NoRoom (settings.s) says so, nothing changes.
Choose: sta opt
        jsr RowAt
        jsr Keys                ; r0 = the section, r1 = the key
        lda opt
        jsr OptAt
        ldy #OPT_VAL
        lda (op),y
        sta r2L
        iny
        lda (op),y
        sta r2H
        bne @set
        jsr IniDel              ; (no value: the key out; none there: fine)
        jmp @done
@set:   jsr IniSet
        bcc @done
        jmp NoRoom
@done:  ldx row
        lda opt
        sta sel,x
        lda #1
        sta dirty
        jsr RowAt
        jmp Boxes

; Table: A/X = the table: tbl, rows.
Table:  sta tbl
        stx tbl+1
        sta tp
        stx tp+1
        ldy #0
        lda (tp),y
        cmp #ROWS_MAX + 1
        bcc :+
        lda #ROWS_MAX
:       sta rows
        rts

; RowAt: tp = row `row` (past the ones before it: ROW_OPTS + options
; * OPT_LEN bytes each).
RowAt:  lda tbl
        clc
        adc #1
        sta tp
        lda tbl+1
        adc #0
        sta tp+1
        ldx row
@skip:  dex
        bmi @end
        ldy #ROW_N
        lda (tp),y
        asl a                   ; * OPT_LEN (6): * 2 + * 4
        sta tmp
        asl a
        clc
        adc tmp
        adc #ROW_OPTS
        clc
        adc tp
        sta tp
        bcc @skip
        inc tp+1
        bne @skip
@end:   rts

; OptAt: op = option A of the row at tp; C set when the row has no
; option A.
OptAt:  ldy #ROW_N
        cmp (tp),y
        bcs @end
        sta tmp                 ; op = tp + ROW_OPTS + A * 6
        asl a
        clc
        adc tmp
        asl a
        adc #ROW_OPTS
        clc
        adc tp
        sta op
        lda tp+1
        adc #0
        sta op+1
        clc
@end:   rts

; OptX: r11 = the option at op's x.
OptX:   ldy #OPT_X
        lda (op),y
        sta r11L
        iny
        lda (op),y
        sta r11H
        rts

; Base: r1H = the row at tp's baseline.
Base:   ldy #ROW_Y
        lda (tp),y
        sta r1H
        rts

; Keys: r0 = the row at tp's section, r1 = its key.
Keys:   ldy #ROW_SECT
        lda (tp),y
        sta r0L
        iny
        lda (tp),y
        sta r0H
        ldy #ROW_KEY
        lda (tp),y
        sta r1L
        iny
        lda (tp),y
        sta r1H
        rts

; Current: sel for row `row`: the option whose value the INI text holds
; for its key (any case, a "-" in front left out), else the row's
; default.
Current:
        jsr RowAt
        ldy #ROW_DEF
        lda (tp),y
        ldx row
        sta sel,x
        jsr Keys
        jsr IniFind             ; (r2 the value, A its length)
        bcs @end
        sta len
        ldy #0                  ; a "-" in front: the same option (the
        lda (r2),y              ; desktop's sort=-date, reversed; a click
        cmp #'-'                ; writes it plain again)
        bne :+
        dec len
        inc r2L
        bne :+
        inc r2H
:       lda #0
        sta opt
@opt:   jsr RowAt               ; (IniFind leaves tp alone; op moves)
        lda opt
        jsr OptAt
        bcs @end
        ldy #OPT_VAL
        lda (op),y
        sta r3L
        iny
        lda (op),y
        sta r3H
        beq @other              ; (no value: never the one in the text)
        jsr Equal
        bcc @found
@other: inc opt
        bne @opt
@found: lda opt
        ldx row
        sta sel,x
@end:   rts

; Equal: C clear when the value at r3 (zero-ended) is the len bytes at
; r2 (any case).
Equal:  ldy #0
@ch:    cpy len
        beq @last
        lda (r3),y
        beq @no                 ; (shorter)
        jsr Lower
        sta tmp
        lda (r2),y
        jsr Lower
        cmp tmp
        bne @no
        iny
        bne @ch
@last:  lda (r3),y              ; (the value must end here too)
        bne @no
        clc
        rts
@no:    sec
        rts

; Lower: A in lower case (ASCII A-Z).
Lower:  cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       rts

; Boxes: the row at tp's boxes: each framed, the one in force filled.
Boxes:  lda #0
        sta opt
@opt:   lda opt
        jsr OptAt
        bcs @end
        jsr OptX                ; r3 = x, r4 = x + BOX - 1
        lda r11L
        sta r3L
        clc
        adc #BOX - 1
        sta r4L
        lda r11H
        sta r3H
        adc #0
        sta r4H
        jsr Base                ; r2 = the baseline - BOX + 1 to it
        lda r1H
        sta r2H
        sec
        sbc #BOX - 1
        sta r2L
        lda #0                  ; cleared, framed
        jsr SetPattern
        jsr Rectangle
        lda #$FF
        jsr FrameRectangle
        ldx row                 ; the one in force: filled inside
        lda sel,x
        cmp opt
        bne @next
        inc r2L
        inc r2L
        dec r2H
        dec r2H
        lda r3L                 ; x: + 2 and - 2 (words)
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
@next:  jsr RowAt               ; (Rectangle leaves tp; op again)
        inc opt
        bne @opt
@end:   rts

        .segment "BSS"

tbl:            .res 2          ; the table
rows:           .res 1          ; its rows
row:            .res 1          ; the row at hand
opt:            .res 1          ; the option at hand
hit:            .res 1          ; ChoicePress: the option clicked
len:            .res 1          ; Current: the value's length
tmp:            .res 1
sel:            .res ROWS_MAX   ; each row's option in force
