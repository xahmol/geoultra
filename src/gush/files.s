; gush: the file commands (docs/GUSH.md, "Commands"): cp, mv, rm, mkdir,
; rmdir, cat, more, df. Questions (y, n, a: all) before an overwrite or
; a delete unless -f, read from GEOS's key queue (GetNextChar: a command
; runs inside keyVector, so it cannot wait for the next keyVector call);
; a progress line for copies from 20 blocks on; RUN/STOP stops them. Own
; code.

        .include "geos.inc"
        .include "gush.inc"

        .import ConPut, ConPuts, ConNewLine, conCol
        .import FileEngine, argc, argLo, argHi
        .import ArgR0, PutArg, Print, Say, Fail, FailPath, Decimal, num
        .import CopyTree, sinkOn, inHandle, ReadIn
        .export CmdCp, CmdMv, CmdRm, CmdMkdir, CmdRmdir, CmdCat, CmdMore, CmdDf
        .export Ask, AskPath, Copy1, func, Options, firstArg, tracks

GetNextChar     = $C2A7         ; GEOS jump table
FC_OVERWRITE    = 1
FC_RAW          = 2
FILE_EXISTS     = $40
FE_BAD_PATH     = $49
FE_IS_FOLDER    = $4B
FE_CANCELLED    = $47
FO_READ         = 0
PROGRESS_FROM   = 20            ; blocks: from here a progress line
MORE_ROWS       = ROWS_TEXT - 1 ; more: a page, then the question

        .segment "ZEROPAGE"

text:           .res 2          ; cat: the bytes being shown

        .segment "CODE"

; --- Options -----------------------------------------------------------------

; Options: the words after the command that start with "-": their letters
; set flagF (f), flagR (r), flagRaw (R: no CVT), flagT (t: the next
; word a number, tracks);
; X = the first other word. C set: an unknown option (said).
Options:
        lda #0
        sta flagF
        sta flagR
        sta flagRaw
        sta tracks
        ldx #1
@word:  cpx argc
        bcs @end
        jsr Str2
        ldy #0
        lda (str2),y
        cmp #'-'
        bne @end
@ch:    iny
        lda (str2),y
        beq @next
        cmp #'f'
        bne :+
        sta flagF
        jmp @ch
:       cmp #'r'
        bne :+
        sta flagR
        jmp @ch
:       cmp #'R'
        bne :+
        sta flagRaw
        jmp @ch
:       cmp #'t'
        bne @bad
        inx                     ; -t N
        cpx argc
        bcs @bad
        stx optAt
        jsr Number
        bcs @bad
        sta tracks
        ldx optAt
@next:  inx
        bne @word
@end:   stx firstArg
        clc
        rts
@bad:   ldx #FE_BAD_PATH
        ldy #$FF
        jsr Fail
        sec
        rts

; Number: word X as a number (0-255) in A. C set when it is none.
Number: jsr Str2
        ldy #0
        sty value
@d:     lda (str2),y
        beq @end
        sec
        sbc #'0'
        cmp #10
        bcs @bad
        sta digit
        lda value               ; value * 10 + digit
        asl a
        asl a
        clc
        adc value
        asl a
        clc
        adc digit
        sta value
        iny
        bne @d
@end:   tya                     ; (no digits: none)
        beq @bad
        lda value
        clc
        rts
@bad:   sec
        rts

; Str2: str2 = word X. Destroys A.
str2 = text
Str2:   lda argLo,x
        sta str2
        lda argHi,x
        sta str2+1
        rts

; --- Questions ---------------------------------------------------------------

; Ask: "gush: CMD: WHAT WORD? (y/n/a) " and a key: C clear for yes (a:
; yes, and all after it); C set for no. With -f or after "a": yes.
; X = the word, A/Y the question's text. AskPath: the same with the
; name at askName (a path gush made) instead of a word.
Ask:    pha
        lda argLo,x
        sta askName
        lda argHi,x
        sta askName+1
        pla
AskPath:
        sta askText
        sty askText+1
        lda flagF
        beq :+
        clc
        rts
:       lda #<Gush
        ldy #>Gush
        jsr Print
        ldx #0
        jsr PutArg
        lda #<Colon
        ldy #>Colon
        jsr Print
        lda askText
        ldy askText+1
        jsr Print
        lda askName
        ldy askName+1
        jsr Print
        lda #<YesNo
        ldy #>YesNo
        jsr Print
@key:   jsr GetNextChar         ; (the IRQ keeps reading the keyboard)
        cmp #'y'
        beq @yes
        cmp #'n'
        beq @no
        cmp #CR
        beq @no
        cmp #KEY_STOP
        beq @no
        cmp #'a'
        bne @key
        sta flagF               ; all: no more questions
@yes:   jsr ConPut
        jsr ConNewLine
        clc
        rts
@no:    lda #'n'
        jsr ConPut
        jsr ConNewLine
        sec
        rts

; --- cp, mv ------------------------------------------------------------------

; cp [-f] source... target; mv [-f] source... target.
CmdCp:  lda #FE_COPY
        bne CopyMove
CmdMv:  lda #FE_MOVE
CopyMove:
        sta func
        jsr Options
        bcc :+
        rts
:       lda argc                ; at least a source and the target
        sec
        sbc firstArg
        cmp #2
        bcs :+
        lda #<Usage2
        ldy #>Usage2
        jmp Say
:       ldx argc
        dex
        stx targetAt
        ldx firstArg
@each:  stx srcAt
        jsr ArgR0               ; one source: copied or moved
        ldx targetAt
        lda argLo,x
        sta r1L
        lda argHi,x
        sta r1H
        jsr Copy1
        cpx #FE_IS_FOLDER       ; a folder: with -r, cp copies it whole
        bne @next
        lda flagR
        beq @fail
        lda func
        cmp #FE_COPY
        bne @fail
        ldx srcAt
        jsr ArgR0
        ldx targetAt
        lda argLo,x
        sta r1L
        lda argHi,x
        sta r1H
        jsr CopyTree
        jmp @next
@fail:  ldx #FE_IS_FOLDER
        ldy srcAt
        jsr Fail
@next:  ldx srcAt
        inx
        cpx targetAt
        bcc @each
@end:   rts

; Copy1: func (FE_COPY, FE_MOVE) of the path at r0 to the one at r1,
; with the progress line; there already: asked (unless -f), then again
; with FC_OVERWRITE. Errors said, except FE_IS_FOLDER (X, for cp -r).
; X = the error (0: done, or answered no).
Copy1:  lda r0L
        sta src
        sta askName
        lda r0H
        sta src+1
        sta askName+1
        lda r1L
        sta dst
        lda r1H
        sta dst+1
        lda #0
        sta overwrite
@again: lda src
        sta r0L
        lda src+1
        sta r0H
        lda dst
        sta r1L
        lda dst+1
        sta r1H
        lda flagF               ; -f: overwrite without asking
        ora overwrite
        beq :+
        lda #FC_OVERWRITE
:       ldx flagRaw             ; -R: raw, no CVT
        beq :+
        ora #FC_RAW
:       sta r2L
        lda #<Progress
        sta r3L
        lda #>Progress
        sta r3H
        lda #0
        sta shown
        lda func
        jsr FileEngine
        jsr EndProgress
        txa
        beq @end
        cpx #FE_IS_FOLDER
        beq @end
        cpx #FILE_EXISTS        ; there already: asked
        bne @fail
        lda overwrite
        bne @fail
        lda #<Overwrite
        ldy #>Overwrite
        jsr AskPath
        ldx #0
        bcs @end
        lda #1
        sta overwrite
        bne @again
@fail:  lda src
        ldy src+1
        jsr FailPath
        ldx #0                  ; (said)
@end:   rts

; Progress (the engine's progress routine, r4 = blocks done): from
; PROGRESS_FROM blocks on, the count on its line; RUN/STOP stops (C set).
; It must not call the engine.
Progress:
        lda r4H
        bne @show
        lda r4L
        cmp #PROGRESS_FROM
        bcc @key
@show:  lda #0                  ; the line anew: "  N blocks"
        sta conCol
        lda #1
        sta shown
        lda r4L
        sta num
        lda r4H
        sta num+1
        lda #0
        sta num+2
        sta num+3
        lda #8
        jsr Decimal
        lda #<Blocks
        ldy #>Blocks
        jsr Print
@key:   jsr GetNextChar
        cmp #KEY_STOP
        beq @stop
        clc
        rts
@stop:  sec
        rts

; EndProgress: a progress line ended. X kept.
EndProgress:
        lda shown
        beq @end
        txa
        pha
        jsr ConNewLine
        pla
        tax
@end:   rts

; --- rm, mkdir, rmdir --------------------------------------------------------

; rm [-f] path...: each deleted, asked first.
CmdRm:  jsr Options
        bcs @end
        ldx firstArg
@each:  cpx argc
        bcs @end
        stx srcAt
        lda #<Remove
        ldy #>Remove
        jsr Ask
        bcs @next
        ldx srcAt
        jsr ArgR0
        lda #FE_DELETE
        jsr FileEngine
        txa
        beq @next
        ldy srcAt
        jsr Fail
@next:  ldx srcAt
        inx
        bne @each
@end:   rts

; mkdir [-t N] path...: folders (on a 1581: partitions of N tracks).
CmdMkdir:
        lda #FE_MKDIR
        bne Each
; rmdir path...: empty folders removed.
CmdRmdir:
        lda #FE_RMDIR
; Each: function A for every path word (r2L = tracks).
Each:   sta func
        jsr Options
        bcs @end
        ldx firstArg
@each:  cpx argc
        bcs @end
        stx srcAt
        jsr ArgR0
        lda tracks
        sta r2L
        lda func
        jsr FileEngine
        txa
        beq @next
        ldy srcAt
        jsr Fail
@next:  ldx srcAt
        inx
        bne @each
@end:   rts

; --- cat, more ---------------------------------------------------------------

; cat path...; more path... (a page at a time: SPACE a page, RETURN a
; line, q stops; not when the output goes to a file). Without a path:
; the input file (< file), if any.
CmdMore:
        lda #1
        bit sinkOn
        bpl Show
CmdCat: lda #0
Show:   sta paging
        lda #0
        sta pageRows
        lda argc
        cmp #2
        bcs @paths
        lda inHandle            ; no path: the input (none: nothing)
        cmp #$FF
        beq @end
        sta handle
        jsr ShowHandle
        jmp @end
@paths: ldx #1
@each:  cpx argc
        bcs @end
        stx srcAt
        jsr ArgR0
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        txa
        beq @read
        ldy srcAt
        jsr Fail
        jmp @next
@read:  jsr ShowHandle
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@next:  ldx srcAt
        inx
        bne @each
@end:   lda conCol
        beq :+
        jmp ConNewLine
:       rts

; ShowHandle: the open file `handle` shown to its end (or q).
ShowHandle:
@read:  lda #<readBuf
        sta r1L
        lda #>readBuf
        sta r1H
        lda #0
        sta r2L
        lda #1
        sta r2H
        ldy handle              ; (a file, or a pipe: redir.s)
        jsr ReadIn
        txa
        bne @close
        lda r2L                 ; (the bytes read: at most 256)
        sta count
        lda r2H
        beq :+
        lda #0                  ; (256: all of the buffer)
        sta count
        lda #1
:       ora count
        beq @close              ; nothing more
        jsr Bytes
        bcs @close              ; (q)
        lda r2H
        bne @read
        lda r2L
        bne @read
@close: rts

; Bytes: count bytes of readBuf (0: 256) shown: CR a new line, LF and
; other control characters left out, TAB a space, beyond ASCII a dot. C
; set: stop (more: q).
Bytes:  ldy #0
@byte:  sty pos
        lda readBuf,y
        cmp #CR
        beq @nl
        cmp #9
        bne :+
        lda #' '
:       cmp #' '
        bcc @skip
        cmp #127
        bcc @put
        lda #'.'
@put:   ldx conCol              ; (a full row: a new line, counted)
        cpx #COLS - 1
        bcc :+
        jsr ConPut
        jsr Page
        bcs @end
        jmp @skip
:       jsr ConPut
        jmp @skip
@nl:    jsr ConNewLine
        jsr Page
        bcs @end
@skip:  ldy pos
        iny
        cpy count
        bne @byte
        clc
@end:   rts

; Page: more: after MORE_ROWS lines the question; C set for q.
Page:   lda paging
        beq @go
        inc pageRows
        lda pageRows
        cmp #MORE_ROWS
        bcc @go
        lda #<MoreText
        ldy #>MoreText
        jsr Print
@key:   jsr GetNextChar
        cmp #' '
        beq @page
        cmp #CR
        beq @line
        cmp #'q'
        beq @quit
        cmp #KEY_STOP
        beq @quit
        bne @key
@page:  lda #0
        sta pageRows
        beq @clear
@line:  lda #MORE_ROWS - 1
        sta pageRows
@clear: lda #0                  ; the question off its line
        sta conCol
        ldx #MoreLen
@sp:    lda #' '
        stx pos2
        jsr ConPut
        ldx pos2
        dex
        bne @sp
        lda #0
        sta conCol
@go:    clc
        rts
@quit:  jsr ConNewLine
        sec
        rts

; --- df ----------------------------------------------------------------------

; df [path]: blocks free and in all (GEOS drives).
CmdDf:  lda argc
        cmp #2
        bcs @path
        lda #<Dot
        sta r0L
        lda #>Dot
        sta r0H
        jmp @go
@path:  ldx #1
        jsr ArgR0
@go:    lda #FE_DF
        jsr FileEngine
        txa
        beq @show
        ldy #1
        lda argc
        cmp #2
        bcs :+
        ldy #$FF
:       jmp Fail
@show:  lda r1L                 ; free
        ldx r1H
        jsr Num
        lda #<Free
        ldy #>Free
        jsr Print
        lda r2L                 ; in all
        ldx r2H
        jsr Num
        lda #<Total
        ldy #>Total
        jmp Say

; Num: A/X (low, high) in decimal.
Num:    sta num
        stx num+1
        lda #0
        sta num+2
        sta num+3
        lda #1
        jmp Decimal

Gush:           .byte "gush: ", 0
Colon:          .byte ": ", 0
YesNo:          .byte "? (y/n/a) ", 0
Overwrite:      .byte "overwrite ", 0
Remove:         .byte "remove ", 0
Usage2:         .byte "gush: a source and a target, please", 0
Blocks:         .byte " blocks", 0
MoreText:       .byte "-- more (space, return, q) --", 0
MoreLen         = * - MoreText - 1
Free:           .byte " blocks free of ", 0
Total:          .byte " blocks", 0
Dot:            .byte ".", 0

        .segment "DATA"

flagF:          .byte 0
flagR:          .byte 0
flagRaw:        .byte 0
tracks:         .byte 0
optAt:          .byte 0
firstArg:       .byte 0
value:          .byte 0
digit:          .byte 0
askName:        .word 0
askText:        .word 0
src:            .word 0
dst:            .word 0
func:           .byte 0
targetAt:       .byte 0
srcAt:          .byte 0
overwrite:      .byte 0
shown:          .byte 0
paging:         .byte 0
pageRows:       .byte 0
handle:         .byte 0
count:          .byte 0
pos:            .byte 0
pos2:           .byte 0

        .segment "BSS"

readBuf:        .res 256
