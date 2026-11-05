; gush: test, [ ], read, true, false (docs/GUSH.md, "Step 3", sub-step
; 4). Their answer is the line's status ($?, failed: 0 true, 1 false).
; test: no words false; one word: true when not empty; "! ..." the
; opposite; -e/-f/-d path (there, a file, a folder or drive), -z/-n word
; (empty, not empty); a = b, a != b; numbers (16 bits, signed) -eq -ne
; -lt -le -gt -ge. "[" is test with "]" as its last word. read NAME...:
; a line from the keyboard (or the < file), a word to each NAME, the
; rest of the line to the last. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, argc, argLo, argHi, failed, Fail
        .import VarSet, varName, ConPut, ConNewLine, conCol, inHandle, ReadIn
        .export CmdTest, CmdBracket, CmdRead, CmdTrue, CmdFalse

GetNextChar     = $C2A7
FO_READ         = 0
FI_KIND         = 0
K_DRIVE         = 1
K_FOLDER        = 2
K_UDIR          = 6
K_GEOS          = 3
K_UFILE         = 5
READ_MAX        = 250

        .segment "ZEROPAGE"

wp:             .res 2          ; a word

        .segment "CODE"

; true, false.
CmdTrue:
        lda #0
        sta failed
        rts
CmdFalse:
        lda #1
        sta failed
        rts

; [ ... ]: test with "]" as its last word.
CmdBracket:
        ldx argc
        dex
        beq @bad
        lda argLo,x
        sta wp
        lda argHi,x
        sta wp+1
        ldy #0
        lda (wp),y
        cmp #']'
        bne @bad
        iny
        lda (wp),y
        bne @bad
        dec argc                ; (the "]" off)
        jmp CmdTest
@bad:   ldx #ERR_WORDS
        ldy #$FF
        jmp Fail

; test ...: the expression of words 1..argc-1.
CmdTest:
        lda #1
        sta first
        lda #0
        sta negate
        jsr Expr
        lda #0                  ; true (C clear) -> 0
        rol
        eor negate
        sta failed
        rts

; Expr: the words from first: C clear when true.
Expr:   lda argc
        sec
        sbc first
        sta n
        beq @false
        ldx first               ; "!": the opposite of the rest
        jsr Word
        jsr IsBang
        bcc :+
        lda negate
        eor #1
        sta negate
        inc first
        jmp Expr
:       lda n
        cmp #1
        beq @one
        cmp #2
        beq @unary
        cmp #3
        beq @binary
@false: sec
        rts
@one:   ldy #0                  ; a word: true when not empty
        lda (wp),y
        cmp #1
        rts
@unary: ldy #0                  ; -X word
        lda (wp),y
        cmp #'-'
        bne @false
        iny
        lda (wp),y
        sta op
        iny
        lda (wp),y
        bne @false
        ldx first
        inx
        jsr Word
        lda op
        cmp #'z'
        beq @z
        cmp #'n'
        bne @file
        ldy #0                  ; -n: not empty
        lda (wp),y
        cmp #1
        rts
@z:     ldy #0                  ; -z: empty
        lda (wp),y
        beq :+
        sec
        rts
:       clc
        rts
@file:  jmp FileTest
@binary:
        ldx first               ; a OP b
        inx
        jsr Word
        jsr Op
        bcs @false
        jmp Compare

; Word: wp = word X.
Word:   lda argLo,x
        sta wp
        lda argHi,x
        sta wp+1
        rts

; IsBang: C set when wp is "!".
IsBang: ldy #0
        lda (wp),y
        cmp #'!'
        bne @no
        iny
        lda (wp),y
        bne @no
        sec
        rts
@no:    clc
        rts

; FileTest: op (e, f, d) on the path at wp: C clear when true.
FileTest:
        lda wp
        sta r0L
        lda wp+1
        sta r0H
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        bne @no                 ; (not there)
        lda op
        cmp #'e'
        beq @yes
        lda info + FI_KIND
        cmp #K_GEOS             ; files: K_GEOS, K_CBM, K_UFILE
        bcc @dir
        cmp #K_UFILE + 1
        bcs @dir
        lda op                  ; a file
        cmp #'f'
        beq @yes
        bne @no
@dir:   lda op                  ; a folder, drive, "/"
        cmp #'d'
        beq @yes
@no:    sec
        rts
@yes:   clc
        rts

; Op: the operator word at wp to op (0 "=", 1 "!=", 2-7 -eq -ne -lt -le
; -gt -ge). C set when it is none.
Op:     ldx #0
@try:   ldy #0
@ch:    lda Ops,x
        beq @end
        cmp (wp),y
        bne @next
        inx
        iny
        bne @ch
@end:   lda (wp),y
        bne @skip
        lda opNo
        sta op
        lda #0
        sta opNo
        clc
        rts
@next:  lda Ops,x
        beq @skip
        inx
        bne @next
@skip:  inx
        inc opNo
        lda Ops,x
        bne @try
        lda #0
        sta opNo
        sec
        rts

Ops:    .byte "=", 0, "!=", 0, "-eq", 0, "-ne", 0, "-lt", 0, "-le", 0
        .byte "-gt", 0, "-ge", 0, 0

; Compare: word first op word first+2: C clear when true.
Compare:
        lda op
        cmp #2
        bcs @num
        ldx first               ; strings
        jsr Word
        lda wp
        sta r1L
        lda wp+1
        sta r1H
        ldx first
        inx
        inx
        jsr Word
        ldy #$FF
@ch:    iny
        lda (r1),y
        cmp (wp),y
        bne @diff
        cmp #0
        bne @ch
        lda op                  ; the same: "=" true
        cmp #1
        rts
@diff:  lda op                  ; different: "!=" true
        eor #1
        cmp #1
        rts
@num:   ldx first
        jsr Word
        jsr Number
        bcs @no
        lda num
        sta left
        lda num+1
        sta left+1
        ldx first
        inx
        inx
        jsr Word
        jsr Number
        bcs @no
        lda left                ; left - right, signed: sign and zero
        cmp num
        bne :+
        lda left+1
        cmp num+1
        bne :+
        lda #0                  ; equal
        beq @rel
:       lda left
        sec
        sbc num
        lda left+1
        sbc num+1
        bvc :+
        eor #$80
:       ora #1                  ; (not zero; bit 7: less)
@rel:   sta cmpRes
        ldx op
        lda Want-2,x            ; the answers true for: bit 0 equal, 1 less,
        ldy cmpRes              ; 2 greater
        beq @eq
        bmi @lt
        and #4
        bne @yes
        beq @no
@eq:    and #1
        bne @yes
        beq @no
@lt:    and #2
        bne @yes
@no:    sec
        rts
@yes:   clc
        rts

Want:   .byte 1, 6, 2, 3, 4, 5  ; -eq -ne -lt -le -gt -ge

; Number: the word at wp as a signed 16-bit number to num; C set when it
; is none.
Number: ldy #0
        sty num
        sty num+1
        sty minus
        lda (wp),y
        cmp #'-'
        bne @digit
        inc minus
        iny
@digit: lda (wp),y
        beq @end
        sec
        sbc #'0'
        cmp #10
        bcs @bad
        pha                     ; num * 10 + digit
        lda num
        asl
        sta t
        lda num+1
        rol
        sta t+1
        asl num
        rol num+1
        asl num
        rol num+1
        asl num
        rol num+1
        lda num
        clc
        adc t
        sta num
        lda num+1
        adc t+1
        sta num+1
        pla
        clc
        adc num
        sta num
        bcc :+
        inc num+1
:       iny
        bne @digit
@end:   cpy minus               ; (a "-" alone: none)
        beq @bad
        lda minus
        beq :+
        lda #0
        sec
        sbc num
        sta num
        lda #0
        sbc num+1
        sta num+1
:       clc
        rts
@bad:   sec
        rts

; read NAME...: a line in (the < file, else the keyboard, shown), a word
; to each NAME, the rest of the line to the last. Nothing more in the
; file: false.
CmdRead:
        lda argc
        cmp #2
        bcs :+
        ldx #ERR_WORDS
        ldy #$FF
        jmp Fail
:       jsr Line
        bcc :+
        lda #1                  ; (the file's end)
        sta failed
        rts
:       ldx #1                  ; the words to the names
        lda #0
        sta at
@name:  stx word
        jsr Word                ; NAME
        ldy #$FF
@nm:    iny
        lda (wp),y
        sta varName,y
        bne @nm
        ldx at                  ; past spaces
@sp:    lda readBuf,x
        cmp #' '
        bne :+
        inx
        bne @sp
:       stx from
        ldx word                ; the last name: the rest
        inx
        cpx argc
        bcs @rest
        ldx from                ; else one word
@w:     lda readBuf,x
        beq @cut
        cmp #' '
        beq @cut
        inx
        bne @w
@cut:   stx at
        lda readBuf,x           ; (its end, for a moment)
        pha
        lda #0
        sta readBuf,x
        jsr Set
        ldx at
        pla
        sta readBuf,x
        ldx word
        inx
        jmp @name
@rest:  jsr Set
        lda #0
        sta failed
        rts

; Set: varName = readBuf from `from`.
Set:    lda from
        clc
        adc #<readBuf
        sta r0L
        lda #>readBuf
        adc #0
        sta r0H
        jmp VarSet

; Line: a line to readBuf (zero-ended): from the < file (to CR or LF),
; else the keyboard (DEL takes back, RETURN ends). C set at the file's
; end with nothing read.
Line:   ldx #0
        stx at
        lda inHandle
        cmp #$FF
        beq @key
@file:  lda #<chr               ; a byte at a time
        sta r1L
        lda #>chr
        sta r1H
        lda #1
        sta r2L
        lda #0
        sta r2H
        ldy inHandle            ; (a file, or a pipe)
        jsr ReadIn
        txa
        bne @eof
        lda r2L
        beq @eof
        lda chr
        cmp #CR
        beq @done
        cmp #10
        beq @done
        jsr Keep
        jmp @file
@eof:   lda at                  ; nothing read: the end
        beq @end
@done:  ldx at
        lda #0
        sta readBuf,x
        clc
        rts
@end:   sec
        rts
@key:   jsr GetNextChar
        cmp #0
        beq @key
        cmp #CR
        beq @enter
        cmp #KEY_DELETE
        beq @del
        cmp #' '
        bcc @key
        cmp #127
        bcs @key
        ldx at
        cpx #READ_MAX
        bcs @key
        pha
        jsr ConPut
        pla
        jsr Keep
        jmp @key
@del:   ldx at
        beq @key
        dec at
        dec conCol              ; (the character off the screen)
        lda #' '
        jsr ConPut
        dec conCol
        jmp @key
@enter: jsr ConNewLine
        jmp @done

; Keep: A to readBuf at `at` (READ_MAX at most).
Keep:   ldx at
        cpx #READ_MAX
        bcs :+
        sta readBuf,x
        inc at
:       rts

        .segment "DATA"

first:          .byte 0
negate:         .byte 0
n:              .byte 0
op:             .byte 0
opNo:           .byte 0
cmpRes:         .byte 0
minus:          .byte 0
at:             .byte 0
word:           .byte 0
from:           .byte 0
chr:            .byte 0
num:            .word 0
left:           .word 0
t:              .word 0

        .segment "BSS"

info:           .res 16
readBuf:        .res READ_MAX + 1
