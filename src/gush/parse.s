; gush: the command line into words (docs/GUSH.md, "Syntax"). Spaces
; separate words; "..." and '...' keep spaces; \ takes the next character
; as it is. $NAME, ${NAME} and $? are replaced by the value (not in
; '...'; a value is not split into words). An unquoted >, >> or < is a
; word of its own: a marker byte (gush.inc REDIR_*; redir.s). A word with an unquoted * or ? is replaced by the names that
; match (the file engine's FE_OPENDIR pattern in its last part), with the
; word's folder part in front; none: the word stays. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import lineBuf, FileEngine, VarFind, varName, IsNameChar, status
        .export Parse, argc, argLo, argHi

        .segment "ZEROPAGE"

argOut:         .res 2          ; the next byte of argBuf

        .segment "CODE"

; Parse: lineBuf into argc words, argLo/argHi pointing at each (zero-
; ended, in argBuf). C set when the words do not fit (ARGS_MAX words,
; ARGBUF_SIZE bytes). Destroys A, X, Y, r0-r4.
Parse:  lda #0
        sta argc
        sta inPos
        lda #<argBuf
        sta argOut
        lda #>argBuf
        sta argOut+1
@word:  ldx inPos               ; past the spaces
@sp:    lda lineBuf,x
        bne :+
        jmp @done
:       cmp #' '
        bne @start
        inx
        bne @sp
@start: stx inPos
        lda argc
        cmp #ARGS_MAX
        bcc :+
        jmp @full
:       tax
        lda argOut
        sta argLo,x
        lda argOut+1
        sta argHi,x
        lda #0
        sta quote
        sta glob
@char:  ldx inPos
        lda lineBuf,x
        beq @end
        inc inPos
        ldy quote
        bne @quoted
        cmp #' '
        beq @end
        cmp #'"'
        beq @open
        cmp #$27                ; '
        beq @open
        cmp #'\'
        beq @escape
        cmp #'$'
        beq @dollar
        cmp #'>'
        beq @mark
        cmp #'<'
        bne :+
@mark:  jsr Mark
        bcc @ended
        jmp @full
@ended: jmp @end
:
        cmp #'*'
        beq @wild
        cmp #'?'
        bne @put
@wild:  sta glob                ; (nonzero; sta keeps cmp's flags:
        jmp @put                ; jmp, not bne)
@open:  sta quote
        jmp @char
@quoted:
        cmp quote               ; the closing quote
        beq @close
        cmp #'$'                ; "...": $ too
        bne @put
        cpy #'"'
        bne @put
@dollar:
        jsr Dollar
        bcs @full
        jmp @char
@close:
        lda #0
        sta quote
        beq @char
@escape:
        ldx inPos
        lda lineBuf,x
        beq @end
        inc inPos
@put:   jsr Out
        bcs @full
        jmp @char
@end:   lda #0                  ; the word's end
        jsr Out
        bcs @full
        lda glob
        beq @next
        jsr Expand
        bcs @full
        jmp @word
@next:  inc argc
        jmp @word
@done:  clc
        rts
@full:  sec
        rts

; Mark (A: an unquoted ">" or "<" read): the word begun ends there (the
; character read again), else the marker byte REDIR_OUT, REDIR_ADD (">>")
; or REDIR_IN is this word. C set when argBuf is full.
Mark:   sta redirCh
        ldx argc                ; a word already begun: ended first (the
        lda argOut              ; ">" read again then)
        cmp argLo,x
        bne @before
        lda argOut+1
        cmp argHi,x
        bne @before
        lda redirCh
        cmp #'<'                ; the marker as a word of its own
        beq @in
        ldx inPos
        lda lineBuf,x
        cmp #'>'
        bne @out
        inc inPos
        lda #REDIR_ADD
        bne @mark
@out:   lda #REDIR_OUT
        bne @mark
@in:    lda #REDIR_IN
@mark:  jmp Out                 ; (C set: argBuf full)
@before:
        dec inPos
        clc
        rts

; Dollar (after a "$", inPos at the next character): a variable's
; value, $? the status of the last line, ${NAME}; $0-$9 and $# (a
; script's words: sub-step 3) empty for now; a "$" with no name after it
; stays. C set when argBuf is full.
Dollar: ldx inPos
        lda lineBuf,x
        cmp #'?'
        beq @status
        cmp #'#'
        beq @skip
        cmp #'{'
        beq @brace
        cmp #'0'
        bcc :+
        cmp #'9' + 1
        bcc @skip
:       jsr IsNameChar
        bcs @name
        lda #'$'                ; (no name: the "$" itself)
        jmp Out
@skip:  inc inPos
        clc
        rts
@brace: inx
        ldy #0
@bn:    lda lineBuf,x
        beq @got
        inx
        cmp #'}'
        beq @got
        sta varName,y
        iny
        cpy #VAR_NAME_MAX
        bcc @bn
        bcs @got
@name:  ldy #0
@nm:    lda lineBuf,x
        jsr IsNameChar
        bcc @got
        sta varName,y
        inx
        iny
        cpy #VAR_NAME_MAX
        bcc @nm
@got:   lda #0
        sta varName,y
        stx inPos
        jsr VarFind
        bcs @none
        ldy #0
@val:   lda (r1),y
        beq @none
        sty pos
        jsr Out
        bcs @end
        ldy pos
        iny
        bne @val
@none:  clc
@end:   rts
@status:
        inc inPos
        lda status              ; (0-255 in decimal)
        ldx #100
        stx pos
        ldy #0                  ; (Y: a digit written)
@pow:   ldx #'0'
@sub:   cmp pos
        bcc @digit
        sbc pos
        inx
        bne @sub
@digit: pha
        txa
        cpx #'0'
        bne @put
        cpy #0
        bne @put
        lda pos
        cmp #1
        bne @next
        lda #'0'
@put:   jsr Out
        ldy #1
@next:  pla
        ldx pos                 ; 100, 10, 1
        cpx #1
        beq @done
        cpx #100
        bne :+
        ldx #10
        .byte $2C               ; (bit abs: skips the next ldx)
:       ldx #1
        stx pos
        jmp @pow
@done:  clc
        rts

; Out: A to argBuf. C set when it is full. Destroys A, Y.
Out:    ldy #0
        sta (argOut),y
        inc argOut
        bne :+
        inc argOut+1
:       lda argOut
        cmp #<(argBuf + ARGBUF_SIZE)
        lda argOut+1
        sbc #>(argBuf + ARGBUF_SIZE)
        rts                     ; (C set: at the end)

; Expand: word argc (just stored) replaced by its matches, each a word;
; none: kept, one word. C set when they do not fit.
Expand: ldx argc                ; the pattern to patBuf
        lda argLo,x
        sta r1L
        lda argHi,x
        sta r1H
        ldy #0
        sty folder              ; the folder part: up to the last "/"
        dey
@copy:  iny
        lda (r1),y
        sta patBuf,y
        beq @copied
        cmp #'/'
        bne @copy
        iny                     ; (folder: its length, the "/" in it)
        sty folder
        dey
        jmp @copy
@copied:
        lda #<patBuf
        sta r0L
        lda #>patBuf
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        beq :+
        jmp @keep
:       sta found
@entry: lda #<info              ; the next match
        sta r1L
        lda #>info
        sta r1H
        lda #<nameBuf
        sta r2L
        lda #>nameBuf
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        beq :+
        jmp @close
:       ldx argc                ; a word: the folder part, the name
        cpx #ARGS_MAX
        bcs @overflow
        lda argOut
        sta argLo,x
        lda argOut+1
        sta argHi,x
        ldy #0
@dir:   cpy folder
        beq @name
        lda patBuf,y
        sty pos
        jsr Out
        bcs @overflow
        ldy pos
        iny
        bne @dir
@name:  ldy #0
@nm:    lda nameBuf,y
        sty pos
        jsr Out
        bcs @overflow
        ldy pos
        iny
        lda nameBuf-1,y
        bne @nm
        inc argc
        inc found
        jmp @entry
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        lda found
        beq @none
        clc
        rts
@none:  ldx argc                ; none: the word as it was
        lda argLo,x
        sta argOut
        lda argHi,x
        sta argOut+1
        ldy #$FF
@back:  iny
        lda patBuf,y
        sty pos
        jsr Out
        ldy pos
        lda patBuf,y
        bne @back
@keep:  inc argc
        clc
        rts
@overflow:
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        sec
        rts

        .segment "DATA"

argc:           .byte 0
redirCh:        .byte 0         ; the ">" or "<" read
VAR_NAME_MAX    = 16            ; (vars.s: NAME_MAX)
inPos:          .byte 0
quote:          .byte 0
glob:           .byte 0
folder:         .byte 0
found:          .byte 0
handle:         .byte 0
pos:            .byte 0

        .segment "BSS"

        .segment "HIGHBSS"
argLo:          .res ARGS_MAX
argHi:          .res ARGS_MAX
argBuf:         .res ARGBUF_SIZE
patBuf:         .res 256
        .segment "BSS"
nameBuf:        .res 64
info:           .res 16
