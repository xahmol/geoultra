; gush: the history across sessions (docs/GUSH.md, "Step 3", sub-step
; 6). HistSave writes the newest HIST_SAVE lines, the oldest first, a CR
; after each, to HOME/gush_history when gush ends (exit, an application
; started, reboot); HistLoad reads them back at gush's start into the
; history (edit.s), as if typed. The file goes through a page buffer
; (each engine write on the Ultimate costs several commands). Without
; HOME nothing happens. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, VarFind, varName, lineBuf, lineLen
        .import histTop, histCount, histSlot, histBuf, Fetch, Keep
        .export Ov_HistSave := HistSave
        .export Ov_HistLoad := HistLoad

HIST_SAVE       = 100
HIST_N          = 128           ; (edit.s: the slots, a power of 2)
PATH_MAX        = 48

        .segment "OV1"                 ; (overlay 1, ovl.s)

; HistSave: the newest lines to HOME/gush_history (errors left: the
; history is a convenience).
HistSave:
        jsr Path
        bcs @end
        lda histCount           ; (none: nothing to write)
        beq @end
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        txa
        bne @end
        sta handle
        lda #0
        sta bufLen
        lda histCount           ; n = min(count, HIST_SAVE), oldest first
        cmp #HIST_SAVE
        bcc :+
        lda #HIST_SAVE
:       sta left
@line:  lda left
        beq @close
        dec left
        lda histTop             ; slot = top - left
        sec
        sbc left
        and #HIST_N - 1
        sta histSlot
        jsr Fetch
        ldx #0
@ch:    lda histBuf,x
        beq @eol
        jsr Out
        inx
        bne @ch
@eol:   lda #CR
        jsr Out
        jmp @line
@close: jsr Flush
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@end:   rts

; Out: A into the page buffer (written when full). X kept.
Out:    stx keepX
        ldx bufLen
        sta buf,x
        inc bufLen
        bne :+
        lda #1                  ; (256)
        sta bufFull
        jsr Flush
:       ldx keepX
        rts

; Flush: the buffer's bytes (bufLen; 256 when full) written.
Flush:  lda #<buf
        sta r1L
        lda #>buf
        sta r1H
        lda bufLen
        sta r2L
        lda bufFull
        sta r2H
        ora r2L
        beq @end
        ldy handle
        lda #FE_WRITE
        jsr FileEngine
@end:   lda #0
        sta bufLen
        sta bufFull
        rts

; HistLoad: HOME/gush_history's lines into the history (none: nothing).
HistLoad:
        jsr Path
        bcc :+
        rts
:       lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        txa
        beq :+
        rts
:       sta handle
        lda #0
        sta lineLen
@chunk: lda #<buf               ; a page at a time
        sta r1L
        lda #>buf
        sta r1H
        lda #0
        sta r2L
        lda #1
        sta r2H
        ldy handle
        lda #FE_READ
        jsr FileEngine
        txa
        bne @close
        lda r2L
        sta got
        lda r2H
        sta gotHi
        ora got
        beq @close
        ldx #0
@ch:    stx at
        lda buf,x
        cmp #CR
        beq @eol
        cmp #10
        beq @eol
        ldy lineLen             ; (LINE_MAX at most)
        cpy #LINE_MAX
        bcs @next
        sta lineBuf,y
        inc lineLen
        jmp @next
@eol:   jsr Line
@next:  ldx at
        inx
        lda gotHi               ; (256: all of the page)
        bne :+
        cpx got
        beq @more
:       cpx #0
        bne @ch
@more:  lda gotHi
        bne @chunk
        jmp @close
@close: jsr Line                ; (a last line without its CR)
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        lda #0
        sta lineLen
@end:   rts

; Line: lineBuf (lineLen) kept as a history line, if any.
Line:   ldy lineLen
        beq @end
        lda #0
        sta lineBuf,y
        jsr Keep
        lda #0
        sta lineLen
@end:   rts

; Path: r0 = HOME "/gush_history" (in path). C set without HOME.
Path:   ldy #0
@n:     lda HomeName,y
        sta varName,y
        beq :+
        iny
        bne @n
:       jsr VarFind
        bcs @end
        ldy #0
@home:  lda (r1),y
        beq @tail
        sta path,y
        iny
        cpy #PATH_MAX - 14
        bcc @home
        sec
        rts
@tail:  cpy #0
        beq @none               ; (HOME empty)
        ldx #0
@t:     lda HistName,x
        sta path,y
        beq @done
        iny
        inx
        bne @t
@done:  lda #<path
        sta r0L
        lda #>path
        sta r0H
        clc
@end:   rts
@none:  sec
        rts

HomeName:       .byte "HOME", 0
HistName:       .byte "/gush_history", 0

        .segment "OV1"

handle:         .byte 0
bufLen:         .byte 0
bufFull:        .byte 0
left:           .byte 0
keepX:          .byte 0
got:            .byte 0
gotHi:          .byte 0
at:             .byte 0

        .segment "BSS"

path:           .res PATH_MAX

        .segment "HIGHBSS"

buf:            .res 256
