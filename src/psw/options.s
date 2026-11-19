; GU PostScript: the options (docs/DESIGN.md "PostScript writer", the
; user's decisions of 2026-11-19): paper (A4, Letter) and look (real
; text: the LW and GU fonts as the printer's own; C64 look: every font
; from its bitmaps), their defaults from SETTINGS.INI ([print] paper=
; letter, pslook= c64; anything else: A4, real text), chosen in a short
; box before the document is written. Own code.

        .include "psw.inc"

        .export Defaults, Options, Paper
        .import docName, paperW, paperH, real, FileEngine, EngineInit

SetPattern      = $C139
Rectangle       = $C124
PutString       = $C148
r4L = $0A
r4H = $0B
r11L = $18
r11H = $19
FE_READ         = 14
FO_READ         = 0
DBUSRICON       = 18
INI_MAX         = $0800         ; SETTINGS.INI's bytes read, at most
BOX_X           = 64            ; DEF_DB_POS's box, its top left
BOX_Y           = 32
STATUS_Y        = TXT_LN_2_Y + 6        ; the status line's baseline in the box

        .segment "ZEROPAGE"

titleLine:  .res 2              ; (DBVARSTR: zero page pointers)
statusLine: .res 2

        .segment "CODE"

; Defaults: paper and real from SETTINGS.INI in the home folder ("PAPER=
; LETTER", "PSLOOK=C64", in any case; no file, no Ultimate: A4, real
; text). Destroys all.
Defaults:
        lda #0
        sta letter
        lda #$80
        sta real
        jsr EngineInit
        lda #<path
        sta r1L
        lda #>path
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        txa
        bne @end
        ldy #0                  ; + "SETTINGS.INI"
:       lda path,y
        beq :+
        iny
        bne :-
:       ldx #0
:       lda IniName,x
        sta path,y
        beq :+
        iny
        inx
        bne :-
:       lda #0                  ; the buffer cleared: the text ends at a 0
        ldx #>INI_MAX + 1
        jsr Clear
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        txa
        bne @end
        lda #<PAGEBUF
        sta r1L
        lda #>PAGEBUF
        sta r1H
        lda #<INI_MAX
        sta r2L
        lda #>INI_MAX
        sta r2H
        ldy handle
        lda #FE_READ
        jsr FileEngine
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        lda #<KeyLetter
        ldx #>KeyLetter
        jsr InText
        bcc :+
        lda #$80
        sta letter
:       lda #<KeyC64
        ldx #>KeyC64
        jsr InText
        bcc @end
        lda #0
        sta real
@end:   rts

; Clear: X pages of PAGEBUF set to A.
Clear:  ldy #<PAGEBUF
        sty op
        ldy #>PAGEBUF
        sty op + 1
        ldy #0
:       sta (op),y
        iny
        bne :-
        inc op + 1
        dex
        bne :-
        rts

; InText: C set when the zero-ended key at A/X (upper case) is in the
; text at PAGEBUF (letters in any case; the text ends at a 0, at most
; INI_MAX bytes).
InText: sta gp
        stx gp + 1
        lda #<PAGEBUF
        sta op
        lda #>PAGEBUF
        sta op + 1
@at:    ldy #0
        lda (op),y
        beq @no
@cmp:   lda (gp),y
        beq @yes
        lda (op),y
        cmp #'a'
        bcc :+
        cmp #'z' + 1
        bcs :+
        and #$DF
:       cmp (gp),y
        bne @next
        iny
        bne @cmp
@next:  inc op
        bne @at
        inc op + 1
        lda op + 1
        cmp #>(PAGEBUF + INI_MAX)
        bcc @at
@no:    clc
        rts
@yes:   sec
        rts

; Options: the box: "PostScript of <document>", the paper and the look
; shown and changed by their buttons, OK or Cancel. C set: cancelled.
Options:
        ldx #0                  ; the title: "PostScript of " + the name
:       lda TitleText,x
        sta title,x
        beq :+
        inx
        bne :-
:       ldy #0
:       lda docName,y
        sta title,x
        beq :+
        inx
        iny
        cpy #16
        bcc :-
        lda #0
        sta title,x
:       lda #<title
        sta titleLine
        lda #>title
        sta titleLine + 1
        jsr Status
        lda #<box
        sta r0L
        lda #>box
        sta r0H
        jsr DoDlgBox
        lda r0L
        cmp #OK
        bne @no
        jsr Paper
        clc
        rts
@no:    sec
        rts

; Paper: paperW, paperH in hundredths of a point (A4: 595.28 x 841.89,
; Letter: 612 x 792).
Paper:  ldx #0
        bit letter
        bpl :+
        ldx #6
:       ldy #0
:       lda Sizes,x
        sta paperW,y
        inx
        iny
        cpy #3
        bcc :-
        ldy #0
:       lda Sizes,x
        sta paperH,y
        inx
        iny
        cpy #3
        bcc :-
        rts
Sizes:  .byte <59528, >59528, ^59528, <84189, >84189, ^84189
        .byte <61200, >61200, ^61200, <79200, >79200, ^79200

; Status: the status line's text: "A4" or "Letter", ", real text" or
; ", C64 look".
Status: lda #<status
        sta statusLine
        lda #>status
        sta statusLine + 1
        ldx #0
        lda #<TA4
        ldy #>TA4
        bit letter
        bpl :+
        lda #<TLetter
        ldy #>TLetter
:       jsr Append
        lda #<TReal
        ldy #>TReal
        bit real
        bmi :+
        lda #<TC64
        ldy #>TC64
:       jsr Append
        lda #0
        sta status,x
        rts

; Append: the zero-ended text at A/Y to status at X; X after it.
Append: sta op
        sty op + 1
        ldy #0
:       lda (op),y
        beq :+
        sta status,x
        inx
        iny
        bne :-
:       rts

; The buttons' routines (DBUSRICON): the choice changed, the status line
; drawn again (its place cleared, the text put).
SetA4:  lda #0
        sta letter
        jmp Redraw
SetLetter:
        lda #$80
        sta letter
        jmp Redraw
SetReal:
        lda #$80
        sta real
        jmp Redraw
SetC64: lda #0
        sta real
Redraw: jsr Status
        lda #0                  ; white
        jsr SetPattern
        lda #BOX_Y + STATUS_Y - 8
        sta r2L
        lda #BOX_Y + STATUS_Y + 2
        sta r2H
        lda #<(BOX_X + TXT_LN_X)
        sta r3L
        lda #>(BOX_X + TXT_LN_X)
        sta r3H
        lda #<(BOX_X + 184)
        sta r4L
        lda #>(BOX_X + 184)
        sta r4H
        jsr Rectangle
        lda #<status
        sta r0L
        lda #>status
        sta r0H
        lda #<(BOX_X + TXT_LN_X)
        sta r11L
        lda #>(BOX_X + TXT_LN_X)
        sta r11H
        lda #BOX_Y + STATUS_Y
        sta r1H
        jmp PutString

box:    .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, titleLine
        .byte DBVARSTR, TXT_LN_X, STATUS_Y, statusLine
        .byte DBUSRICON, 1, 44
        .word IconTabA4
        .byte DBUSRICON, 8, 44
        .word IconTabLetter
        .byte DBUSRICON, 1, 64
        .word IconTabReal
        .byte DBUSRICON, 8, 64
        .word IconTabC64
        .byte OK, DBI_X_2, 44
        .byte CANCEL, DBI_X_2, 64
        .byte 0
IconTabA4:      .word IconA4
                .byte 0, 0, 6, 16
                .word SetA4
IconTabLetter:  .word IconLetter
                .byte 0, 0, 6, 16
                .word SetLetter
IconTabReal:    .word IconReal
                .byte 0, 0, 6, 16
                .word SetReal
IconTabC64:     .word IconC64
                .byte 0, 0, 6, 16
                .word SetC64

TitleText:      .byte "PostScript of ", 0
TA4:            .byte "Paper A4", 0
TLetter:        .byte "Paper Letter", 0
TReal:          .byte ", real text", 0
TC64:           .byte ", C64 look", 0
IniName:        .byte "SETTINGS.INI", 0
KeyLetter:      .byte "PAPER=LETTER", 0
KeyC64:         .byte "PSLOOK=C64", 0

        .include "pswicons.inc"

        .segment "BSS"

letter: .res 1                  ; $80: US Letter
handle: .res 1
path:   .res 48
title:  .res 32
status: .res 32
