; GU PostScript: the output file (GEOULTRA/print/<document>.ps) through
; GeoUltra's file engine (docs/FILE_ENGINE.md), written in blocks of
; OUT_MAX bytes, and the number formats the PostScript needs. Own code.

        .include "psw.inc"

        .export OutOpen, OutClose, PutC, PutI, PutZ, PutDec, PutDecN, PutHund, PutHex
        .export PutSp, PutNL, FileEngine, outErr
        .import docName

        .segment "CODE"

; OutOpen: the print folder made (there already: fine) and
; <home>print/<docName>.ps opened for writing. X = 0 or the error;
; outErr = X.
OutOpen:
        lda guExtTable          ; the engine's entry
        clc
        adc #FE_ENTRY
        sta feVec
        lda guExtTable+1
        adc #0
        sta feVec+1
        lda #<path
        sta r1L
        lda #>path
        sta r1H
        lda #FE_HOME
        jsr FileEngine          ; path = "/USB0/GEOULTRA/"
        txa
        bne @end
        ldy #0
:       lda path,y
        beq :+
        iny
        bne :-
:       ldx #0                  ; + "print"
:       lda Folder,x
        sta path,y
        beq :+
        iny
        inx
        bne :-
:       sty at
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #0
        sta r2L
        lda #FE_MKDIR           ; (there already: an error, not minded)
        jsr FileEngine
        ldy at                  ; + "/" + the document's name + ".ps"
        lda #'/'
        sta path,y
        iny
        ldx #0
:       lda docName,x
        beq :+
        jsr Fat                 ; (a character the Ultimate's FAT refuses: _)
        sta path,y
        iny
        inx
        cpx #16
        bcc :-
:       ldx #0
:       lda Ext,x
        sta path,y
        beq :+
        iny
        inx
        bne :-
:       lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        lda #0
        sta outLen
@end:   stx outErr
        rts

; Fat: A as a FAT file name allows it (\ / : * ? " < > | to "_").
; Destroys nothing else.
Fat:    stx tmp
        ldx #FAT_BAD - 1
:       cmp FatBad,x
        beq :+
        dex
        bpl :-
        ldx tmp
        rts
:       lda #'_'
        ldx tmp
        rts

; OutClose: the rest written, the file closed. X = outErr (the first
; error; a failed close counts: the file is not complete).
OutClose:
        jsr Flush
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        lda outErr
        bne :+
        stx outErr
:       ldx outErr
        rts

; PutC: A to the output. Keeps A, X, Y.
PutC:   stx keepX
        ldx outLen
        sta OUTBUF,x
        inx
        stx outLen
        bne :+
        pha                     ; (256 bytes: written)
        tya
        pha
        lda #1
        sta full
        jsr Flush
        pla
        tay
        pla
:       ldx keepX
        rts

; Flush: the buffer written (outLen bytes, 256 when full is set); the
; first error kept in outErr. Destroys A, X, Y.
Flush:  lda outLen
        ora full
        beq @end
        lda #<OUTBUF
        sta r1L
        lda #>OUTBUF
        sta r1H
        lda outLen
        sta r2L
        lda full
        sta r2H                 ; (full: 256 = $100)
        ldy handle
        lda #FE_WRITE
        jsr FileEngine
        lda outErr
        bne :+
        stx outErr
:       lda #0
        sta outLen
        sta full
@end:   rts

; PutI: the zero-ended text after the jsr to the output; back after it.
; Keeps X, Y.
PutI:   pla
        sta op
        pla
        sta op+1
        tya
        pha
@next:  inc op
        bne :+
        inc op+1
:       ldy #0
        lda (op),y
        beq @end
        jsr PutC
        jmp @next
@end:   pla
        tay
        lda op+1
        pha
        lda op
        pha
        rts

; PutZ: the zero-ended text at A/X to the output. Keeps Y.
PutZ:   sta op
        stx op+1
        tya
        pha
        ldy #0
:       lda (op),y
        beq :+
        jsr PutC
        iny
        bne :-
:       pla
        tay
        rts

; PutSp, PutNL: a space, a line end (LF, as gwps writes). Keep X, Y.
PutSp:  lda #' '
        jmp PutC
PutNL:  lda #10
        jmp PutC

; PutDec: A/X (lo/hi) as a signed decimal number. PutDecN: n24 (three
; bytes, unsigned). Keep Y.
PutDec: sta n24
        stx n24+1
        lda #0
        sta n24+2
        txa
        bpl PutDecN
        lda #'-'                ; (negative: the minus and the value)
        jsr PutC
        sec
        lda #0
        sbc n24
        sta n24
        lda #0
        sbc n24+1
        sta n24+1
PutDecN:
        tya
        pha
        lda #0
        sta lead                ; (no digit yet: zeros left out)
        ldy #0                  ; the power of ten (3 bytes each)
@pow:   ldx #'0'
@sub:   lda n24                 ; n24 - power, while it does not go below 0
        sec
        sbc Pow10,y
        sta tmp
        lda n24+1
        sbc Pow10+1,y
        sta tmp+1
        lda n24+2
        sbc Pow10+2,y
        bcc @digit
        sta n24+2
        lda tmp+1
        sta n24+1
        lda tmp
        sta n24
        inx
        bne @sub
@digit: cpx #'0'
        bne :+
        lda lead
        bne :+
        cpy #POW_LAST           ; (the last digit always)
        bne @skip
:       txa
        jsr PutC
        inc lead
@skip:  iny
        iny
        iny
        cpy #POW_LAST + 3
        bcc @pow
        pla
        tay
        rts

; PutHund: n24 (hundredths) as "w.ff" (the whole part, two decimals),
; as gwps's "%d.%02d". Keeps Y.
PutHund:
        lda #0
        sta quot
        sta quot+1
@div:   lda n24                 ; quot = n24 / 100, n24 = the rest
        sec
        sbc #100
        tax
        lda n24+1
        sbc #0
        sta tmp
        lda n24+2
        sbc #0
        bcc @done
        sta n24+2
        lda tmp
        sta n24+1
        stx n24
        inc quot
        bne @div
        inc quot+1
        bne @div
@done:  lda n24
        pha
        lda quot
        ldx quot+1
        jsr PutDec
        lda #'.'
        jsr PutC
        pla                     ; the rest: two digits
        ldx #'0'
:       cmp #10
        bcc :+
        sbc #10
        inx
        bne :-
:       pha
        txa
        jsr PutC
        pla
        ora #'0'
        jmp PutC

; PutHex: A as two lower-case hex digits. Keeps X, Y.
PutHex: pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @dig
        pla
        and #$0F
@dig:   cmp #10
        bcc :+
        adc #'a' - 10 - 1       ; (carry set)
        jmp PutC
:       ora #'0'
        jmp PutC

; FileEngine: A = the function (docs/FILE_ENGINE.md).
FileEngine:
        jmp (feVec)

Pow10:  .byte $A0, $86, $01     ; 100000
        .byte $10, $27, $00     ; 10000
        .byte $E8, $03, $00     ; 1000
        .byte $64, $00, $00     ; 100
        .byte $0A, $00, $00     ; 10
        .byte $01, $00, $00     ; 1
POW_LAST        = 15
Folder: .byte "print", 0
Ext:    .byte ".ps", 0
FatBad: .byte $5C, "/:*?", $22, "<>|"
FAT_BAD = * - FatBad

        .segment "BSS"

feVec:  .res 2
handle: .res 1
outLen: .res 1
full:   .res 1
outErr: .res 1
keepX:  .res 1
lead:   .res 1
quot:   .res 2
at:     .res 1
path:   .res 64
