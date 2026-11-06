; wc: lines, words and bytes of files, or of the input (a pipe or a <
; file), as "lines words bytes name" (no name for the input); with more
; files a total. The example external gush command (docs/GUSH_COMMANDS.md).
; Own code, GeoUltra.

        .include "geos.inc"
        .include "gushapi.inc"

CHUNK           = 256

        .segment "ZEROPAGE"

text:           .res 2          ; a name to print

        .segment "CODE"

        .byte "GCMD", GU_API_VERSION
        jmp Main

; Main: each file named, else the input.
Main:   lda #0
        ldx #11
@tot:   sta total,x
        dex
        bpl @tot
        jsr GU_ARGC
        sta argc
        cmp #2
        bcs @files
        jsr Clear               ; the input
        jsr Input
        bcs @bad
        lda #0
        sta text+1
        jsr Show
        clc
        rts
@files: lda #1
        sta word
@file:  jsr Clear
        jsr File
        bcs @bad
        ldx word
        jsr GU_ARG
        lda r0L
        sta text
        lda r0H
        sta text+1
        jsr Show
        jsr AddUp
        inc word
        lda word
        cmp argc
        bcc @file
        lda argc                ; more than one: the total
        cmp #3
        bcc @done
        ldx #11
@t:     lda total,x
        sta count,x
        dex
        bpl @t
        lda #<Total
        sta text
        lda #>Total
        sta text+1
        jsr Show
@done:  clc
        rts
@bad:   sec
        rts

Total:  .byte "total", 0

; Clear: the counts to zero, outside a word.
Clear:  lda #0
        ldx #11
@c:     sta count,x
        dex
        bpl @c
        sta inWord
        rts

; Input: the input counted. C set: none given or an error (said).
Input:  jsr Chunk
        jsr GU_READIN
        bcs @none
        txa
        bne @err
        jsr Count
        bcc Input               ; (C clear: more to come)
        clc
        rts
@none:  lda #<NoInput
        ldy #>NoInput
        jsr GU_PRINT
        jsr GU_NEWLINE
        sec
        rts
@err:   ldy #$FF
        jsr GU_FAIL
        sec
        rts

NoInput:        .byte "gush: wc: files, or an input (| or <)", 0

; Chunk: r1/r2 for a read of CHUNK bytes into buf.
Chunk:  lda #<buf
        sta r1L
        lda #>buf
        sta r1H
        lda #<CHUNK
        sta r2L
        lda #>CHUNK
        sta r2H
        rts

; File: word `word` opened and counted. C set: an error (said).
File:   ldx word
        jsr GU_ARG              ; r0: the path
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr GU_FILEENGINE
        sta handle
        txa
        bne @err
@read:  jsr Chunk
        ldy handle
        lda #FE_READ
        jsr GU_FILEENGINE
        txa
        bne @close
        jsr Count
        bcc @read
        ldx #0
@close: stx error
        ldy handle
        lda #FE_CLOSE
        jsr GU_FILEENGINE
        ldx error
        bne @err
        clc
        rts
@err:   ldy word
        jsr GU_FAIL
        sec
        rts

; Count: r2 bytes of buf (1 to CHUNK) counted. C set when r2 was 0 (the
; end), else clear.
Count:  lda r2L
        ora r2H
        bne :+
        sec
        rts
:       ldx #8                  ; bytes += r2
        lda r2L
        jsr Add
        ldx #9
        lda r2H
        jsr Add
        ldy #0
@ch:    lda buf,y
        cmp #CR
        beq @line
        cmp #10
        beq @line
        cmp #' '
        beq @gap
        cmp #9
        beq @gap
        lda inWord              ; a word starts
        bne @next
        inc inWord
        ldx #4
        lda #1
        jsr Add
        jmp @next
@line:  ldx #0
        lda #1
        jsr Add
@gap:   lda #0
        sta inWord
@next:  iny                     ; (256: r2L is 0, Y comes round to it)
        cpy r2L
        bne @ch
        clc
        rts

; Add: A added to count's byte X (lines 0-3, words 4-7, bytes 8-11, low
; byte first), the carry taken up to its counter's last byte. Y kept.
Add:    clc
        adc count,x
        sta count,x
        bcc @end
@up:    inx
        txa
        and #3
        beq @end                ; (past the counter: a 32-bit wrap)
        inc count,x
        beq @up
@end:   rts

; AddUp: total += count, each counter.
AddUp:  ldx #0
@n:     clc
@b:     lda total,x
        adc count,x
        sta total,x
        inx
        txa                     ; (no cpx: it would take the carry)
        and #3
        bne @b
        cpx #12
        bcc @n
        rts

; Show: lines, words, bytes, then " " and the text at `text` (none when
; its high byte is 0), a new line.
Show:   ldx #0
        lda #7
        jsr Number
        ldx #4
        lda #8
        jsr Number
        ldx #8
        lda #9
        jsr Number
        lda text+1
        beq @nl
        lda #' '
        jsr GU_PUTC
        lda text
        ldy text+1
        jsr GU_PRINT
@nl:    jmp GU_NEWLINE

; Number: count's counter at X printed right-aligned in A columns.
Number: pha
        lda count,x
        sta r0L
        lda count+1,x
        sta r0H
        lda count+2,x
        sta r1L
        lda count+3,x
        sta r1H
        pla
        jmp GU_DECIMAL

        .segment "DATA"

argc:           .byte 0
word:           .byte 0
handle:         .byte 0
error:          .byte 0
inWord:         .byte 0

        .segment "BSS"

count:          .res 12         ; lines, words, bytes (32 bits each)
total:          .res 12
buf:            .res CHUNK
