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
        .export PipeOut, PipeIn, ReadIn, PIPE
        .import Say

StashRAM        = $C2C8
FetchRAM        = $C2CB
PIPE            = $FE           ; the handle of a pipe (a stage's output in
PIPE_BANK       = 6             ; the REU: two areas of PIPE_MAX in this
PIPE_MAX        = $8000         ; bank, used in turn)

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
        cmp #REDIR_OUT          ; (an empty word: its zero, no marker)
        bcc @word
        cmp #REDIR_IN + 1
        bcc :+
@word:  jmp @next               ; (a word: no marker byte)
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
        cmp #$FF
        beq :+
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
        lda outHandle           ; a pipe: its bytes stay for the next stage
        cmp #PIPE
        bne @close
        ldx outArea
        lda pipeLen
        sta availLo,x
        lda pipeLen+1
        sta availHi,x
        lda pipeFull
        beq @off
        lda #0
        sta pipeFull
        lda #<FullText
        ldy #>FullText
        jsr Say
        jmp @off
@close: ldy outHandle
        lda #FE_CLOSE
        jsr FileEngine
@off:   lda #0
        sta sinkOn
        sta sinkPause
@in:    lda inHandle
        cmp #$FF
        beq @end
        lda inDepth
        cmp depth
        bne @end
        lda inHandle
        cmp #PIPE               ; (a pipe: nothing to close)
        beq @free
        tay
        lda #FE_CLOSE
        jsr FileEngine
@free:  lda #$FF
        sta inHandle
@end:   rts

; PipeOut: the output of this stage into pipe area A (its old bytes
; dropped). C set when the output goes elsewhere already (said).
PipeOut:
        bit sinkOn
        bpl :+
        ldx #ERR_ONE_REDIR
        ldy #$FF
        jsr Fail
        sec
        rts
:       sta outArea
        lda #PIPE
        sta outHandle
        lda #0
        sta pipeLen
        sta pipeLen+1
        sta sinkLen
        lda depth
        sta sinkDepth
        lda #$80
        sta sinkOn
        clc
        rts

; PipeIn: the input of this stage from pipe area A (what the stage before
; wrote).
PipeIn: tax
        stx inArea
        lda availLo,x
        sta inLenLo
        lda availHi,x
        sta inLenHi
        lda #0
        sta inPosLo
        sta inPosHi
        lda #PIPE
        sta inHandle
        lda depth
        sta inDepth
        rts

; ReadIn: Y = a handle (a file's, or PIPE): up to r2 bytes to (r1); r2 =
; the bytes read. X = 0 or the error.
ReadIn: cpy #PIPE
        beq :+
        lda #FE_READ
        jmp FileEngine
:       lda inLenLo             ; at most what is left (16 bits)
        sec
        sbc inPosLo
        sta leftLo
        lda inLenHi
        sbc inPosHi
        sta leftHi
        lda leftLo
        cmp r2L
        lda leftHi
        sbc r2H
        bcs :+                  ; (enough left)
        lda leftLo
        sta r2L
        lda leftHi
        sta r2H
:       lda r1L                 ; to (r1) from the area at inPos
        sta r0L
        lda r1H
        sta r0H
        lda inPosLo
        sta r1L
        lda inPosHi
        ldx inArea
        beq :+
        ora #>PIPE_MAX
:       sta r1H
        lda #PIPE_BANK
        sta r3L
        lda r2L
        ora r2H
        beq @none
        jsr FetchRAM
        lda inPosLo
        clc
        adc r2L
        sta inPosLo
        lda inPosHi
        adc r2H
        sta inPosHi
@none:  ldx #0
        rts

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
        cpy #PIPE
        beq @pipe
        lda #FE_WRITE
        jsr FileEngine
        jmp @back
@pipe:  lda pipeLen             ; room left in the area?
        clc
        adc r2L
        tax
        lda pipeLen+1
        adc r2H
        cmp #>PIPE_MAX
        bcc :+
        bne @over
        cpx #0
        beq :+
@over:  inc pipeFull            ; (more: left out, said at the end)
        jmp @back
:       lda r1L                 ; sinkBuf to the area at pipeLen
        sta r0L
        lda r1H
        sta r0H
        lda pipeLen
        sta r1L
        lda pipeLen+1
        ldx outArea
        beq :+
        ora #>PIPE_MAX
:       sta r1H
        lda #PIPE_BANK
        sta r3L
        jsr StashRAM
        lda pipeLen
        clc
        adc r2L
        sta pipeLen
        lda pipeLen+1
        adc r2H
        sta pipeLen+1
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
outArea:        .byte 0
inArea:         .byte 0
pipeFull:       .byte 0
pipeLen:        .word 0
inPosLo:        .byte 0
inPosHi:        .byte 0
inLenLo:        .byte 0
inLenHi:        .byte 0
leftLo:         .byte 0
leftHi:         .byte 0
availLo:        .byte 0, 0      ; per area: the bytes written
availHi:        .byte 0, 0

FullText:       .byte "gush: pipe full (32 KB): the rest left out", 0

        .segment "BSS"

saveR:          .res 10
sinkBuf:        .res 256
