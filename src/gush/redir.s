; gush: redirection (docs/GUSH.md, "Step 3", sub-step 2). Parse turns an
; unquoted ">", ">>" or "<" into a word of one marker byte (REDIR_OUT,
; REDIR_ADD, REDIR_IN); Redirect takes each with the word after it (the
; file) off the line and opens the file through the file engine. While
; output goes to a file (sinkOn), ConPut and ConNewLine put their bytes
; into sinkBuf (a new line: CR, as GEOS text files have it), written out
; when it is full and at the line's end (EndRedirect). Error messages and
; questions start with "gush: " (cmds.s, Gush): sinkPause keeps that
; line on the screen. "<" gives commands that read their input
; (cat, more without a path) the file's handle in inHandle. A
; redirection belongs to the script level that made it (sinkDepth,
; inDepth): a script run with "> file" writes there to its end; its own
; lines cannot open a second one (ERR_ONE_REDIR). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Fail, argc, argLo, argHi, depth
        .export Redirect, EndRedirect, SinkPut, sinkOn, sinkPause, inHandle

FO_READ         = 0
FO_WRITE        = 1
FO_APPEND       = 2

        .segment "CODE"

; Redirect: the marker words and their files taken off the words, the
; files opened (output: sinkOn; input: inHandle). C set when a marker
; has no file after it, or a file does not open (said).
Redirect:
        ldx #0
@scan:  cpx argc
        bcc :+
        clc                     ; (all looked at)
        rts
:       lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        ldy #0
        lda (r0),y
        cmp #REDIR_IN + 1
        bcc :+
        jmp @next               ; (a word: no marker byte)
:       sta kind
        stx at
        inx                     ; the file: the next word
        cpx argc
        bcc :+
        ldx #ERR_WORDS
        ldy #$FF
        jsr Fail
        sec
        rts
:       lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        lda kind
        cmp #REDIR_IN
        beq @in
        bit sinkOn              ; one at a time
        bpl :+
        ldx #ERR_ONE_REDIR
        bne @fail
:       sec                     ; FO_WRITE (>) or FO_APPEND (>>)
        sbc #REDIR_OUT - FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        txa
        bne @fail
        sta outHandle
        lda depth
        sta sinkDepth
        lda #0
        sta sinkLen
        lda #$80
        sta sinkOn
        bne @drop
@in:    lda inHandle
        bmi :+
        ldx #ERR_ONE_REDIR
        bne @fail
:       lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        txa
        bne @fail
        sta inHandle
        lda depth
        sta inDepth
@drop:  ldx at                  ; the two words off: the rest down
@move:  cpx argc
        bcs @less
        lda argLo+2,x
        sta argLo,x
        lda argHi+2,x
        sta argHi,x
        inx
        bne @move
@less:  dec argc
        dec argc
        ldx at
        jmp @scan
@next:  inx
        jmp @scan
@fail:  ldy at                  ; (about the file's word)
        iny
        jsr Fail
        sec
        rts
        .assert REDIR_OUT - FO_WRITE = REDIR_ADD - FO_APPEND, error, "Redirect: the markers' order"

; EndRedirect (after the line): the output written and closed, the input
; closed; back to the screen.
EndRedirect:
        bit sinkOn
        bpl @in
        lda sinkDepth           ; (a script's lines: its caller's stays)
        cmp depth
        bne @in
        jsr Flush
        ldy outHandle
        lda #FE_CLOSE
        jsr FileEngine
        lda #0
        sta sinkOn
        sta sinkPause
@in:    lda inHandle
        bmi @end
        lda inDepth
        cmp depth
        bne @end
        lda inHandle
        tay
        lda #FE_CLOSE
        jsr FileEngine
        lda #$FF
        sta inHandle
@end:   rts

; SinkPut: A into the output file's buffer (written when full). Destroys
; A, X, Y.
SinkPut:
        ldx sinkLen
        sta sinkBuf,x
        inc sinkLen
        bne @end
        lda #1                  ; (256 bytes)
        sta full
        jsr Flush
@end:   rts

; Flush: sinkBuf's bytes (sinkLen; 256 when full) written to the output
; file. The caller's r0-r4 kept (a command may be printing from them).
Flush:  ldx #9
@save:  lda r0L,x
        sta saveR,x
        dex
        bpl @save
        lda #<sinkBuf
        sta r1L
        lda #>sinkBuf
        sta r1H
        lda sinkLen
        sta r2L
        lda full
        sta r2H
        ora r2L
        beq @back
        ldy outHandle
        lda #FE_WRITE
        jsr FileEngine
@back:  lda #0
        sta sinkLen
        sta full
        ldx #9
@rest:  lda saveR,x
        sta r0L,x
        dex
        bpl @rest
        rts

        .segment "DATA"

sinkOn:         .byte 0         ; bit 7: output to the file
sinkPause:      .byte 0         ; nonzero: this line to the screen
inHandle:       .byte $FF       ; the input file's handle ($FF: none)
outHandle:      .byte 0
sinkDepth:      .byte 0         ; the script level that opened them
inDepth:        .byte 0
sinkLen:        .byte 0
full:           .byte 0
kind:           .byte 0
at:             .byte 0

        .segment "BSS"

saveR:          .res 10
sinkBuf:        .res 256
