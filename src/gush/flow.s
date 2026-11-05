; gush: statements and control flow (docs/GUSH.md, "Step 3", sub-step 4).
; Exec runs a text in gush's REU (a script's area, or a typed line copied
; to LINE_BANK) statement by statement: statements end at a line's end or
; an unquoted ";"; "#" at a word's start comments to the line's end. The
; keywords are taken here: if/then/elif/else/fi, while/do/done,
; for NAME in words/do/done; any other statement goes to Run (cmds.s).
; Open blocks are frames on a stack (FR_MAX); a branch not taken is
; skipped, only its keywords looked at for nesting. "while" at "done":
; back to the while statement, which tests again; "for" at "done": its
; statement parsed again, the next word into NAME. A level's state (one
; per script depth, 0: a typed line) is kept in arrays, not on the 6502
; stack. RUN/STOP between statements stops everything (breakReq). A
; typed line must close its blocks: no continuation lines yet. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "gush.inc"

        .import Run, Parse, Fail, Say, lineBuf, lineLen, argc, argLo, argHi
        .import status, failed, VarSet, varName, depth, exitReq
        .import PipeOut, PipeIn
        .export Exec, ExecLine, breakReq, cachePage, ScriptExec

StashRAM        = $C2C8
FetchRAM        = $C2CB
LINE_BANK       = 5             ; a typed line's text (bank 4: scripts)
SCRIPT_BANK     = 4             ; (script.s)
FR_MAX          = 16            ; open blocks, all levels together
LEVELS          = 5             ; a typed line and four scripts
STMT_MAX        = LINE_MAX

FR_IF           = 1             ; frame kinds
FR_WHILE        = 2
FR_FOR          = 3

SK_BRANCH       = 1             ; skipping: to this if's elif/else/fi
SK_FI           = 2             ; to its fi
SK_DONE         = 3             ; to the loop's done

KW_IF           = 1             ; Keywords' order
KW_THEN         = 2
KW_ELIF         = 3
KW_ELSE         = 4
KW_FI           = 5
KW_WHILE        = 6
KW_DO           = 7
KW_DONE         = 8
KW_FOR          = 9

        .segment "ZEROPAGE"

restPtr:        .res 2          ; the statement after its keyword

        .segment "CODE"

; ExecLine: the typed line (lineBuf, lineLen) run: copied to LINE_BANK,
; then Exec. A RUN/STOP that stopped it is said here.
ExecLine:
        lda #<lineBuf
        sta r0L
        lda #>lineBuf
        sta r0H
        lda #0
        sta r1L
        sta r1H
        sta r2H
        lda lineLen
        sta r2L
        beq @end
        lda #LINE_BANK
        sta r3L
        jsr StashRAM
        lda #$FF                ; (the cache holds no line now)
        sta cachePage
        ldx #0                  ; level 0
        lda #LINE_BANK
        sta exBank,x
        lda #0
        sta exPage,x
        sta exLenHi,x
        lda lineLen
        sta exLenLo,x
        jsr Exec
        lda breakReq
        beq @end
        lda #0
        sta breakReq
        lda #<Stopped
        ldy #>Stopped
        jmp Say
@end:   rts

; ScriptExec (script.s, its text loaded at depth's area, A/Y its length;
; depth not yet counted up): level depth+1's text set; the cache emptied
; (the area was just written).
ScriptExec:
        ldx depth
        inx
        sta exLenLo,x
        tya
        sta exLenHi,x
        lda #$FF
        sta cachePage
        lda #SCRIPT_BANK
        sta exBank,x
        lda depth               ; its page: depth * $40 (script.s Area)
        asl
        asl
        asl
        asl
        asl
        asl
        sta exPage,x
        rts                     ; (script.s then counts depth up, Exec)

; Exec: level X's text (exBank, exPage, exLenLo/Hi) run statement by
; statement from its start. Ends at the text's end, exit (exitReq) or
; RUN/STOP (breakReq). Blocks left open: said; their frames dropped.
Exec:   stx level
        lda #0
        sta exPosLo,x
        sta exPosHi,x
        lda fsp
        sta exBase,x
        lda #0
        sta skip
@stmt:  ldx level
        lda breakReq
        bne @end
        lda exitReq
        bne @end
        jsr Stop                ; RUN/STOP held?
        bcs @end
        lda exPosLo,x           ; the text's end?
        cmp exLenLo,x
        lda exPosHi,x
        sbc exLenHi,x
        bcs @end
        jsr GetStmt
        lda stmtBuf
        beq @stmt               ; (empty)
        jsr Keyword
        jsr Do
        ldx depth               ; (a script run meanwhile: ours again; a
        stx level               ; level is its script depth)
        jmp @stmt
@end:   ldx level
        lda fsp                 ; blocks still open: said, dropped
        cmp exBase,x
        beq :+
        lda exBase,x
        sta fsp
        lda breakReq
        ora exitReq
        bne :+
        lda #<Open
        ldy #>Open
        jsr Said
:       lda #0
        sta skip
        rts

; Said: an error text (A/Y) said, the line failed.
Said:   inc failed
        jmp Say

; Do: the statement (stmtBuf; kw its keyword, restPtr after it).
Do:     lda skip
        beq @run
        jmp Skipping
@run:   lda kw
        bne :+
        jmp Plain
:       asl
        tax
        lda KwDo-1,x
        pha
        lda KwDo-2,x
        pha
        rts

KwDo:   .word DoIf-1, DoRest-1, DoElif-1, DoElse-1, DoFi-1
        .word DoWhile-1, DoRest-1, DoDone-1, DoFor-1

; Plain: a statement without a keyword: RunPiped.
Plain:  lda #<stmtBuf
        sta restPtr
        lda #>stmtBuf
        sta restPtr+1
        jmp RunPiped

; RunPiped: the statement at (restPtr) run (Run), its stages (split at
; an unquoted "|") one after the other, each one's output (redir.s,
; PipeOut) the next one's input (PipeIn). status: the last stage's. The
; statement is kept in LINE_BANK at page 1 + depth meanwhile: a stage may
; run a script, whose own statements use the buffers.
RunPiped:
        ldy #0                  ; to pipeSrc, then to its REU page
@copy:  lda (restPtr),y
        sta pipeSrc,y
        beq :+
        iny
        bne @copy
:       ldy #0                  ; (Y: Keep's direction: stash)
        jsr Keep
        lda #0
        sta stage
        sta srcAt
@stage: ldy #1                  ; (fetch: a script may have used it)
        jsr Keep
        jsr Segment             ; the next stage to lineBuf; more: C set
        lda #0
        rol
        sta more
        beq @in                 ; (the last: its output as it is)
        lda stage
        and #1
        jsr PipeOut
        bcs @end                ; (said)
@in:    lda stage               ; the stage before: its output as input
        beq @run
        sec
        sbc #1
        and #1
        jsr PipeIn
@run:   jsr Run
        inc stage
        lda breakReq
        bne @end
        lda more
        bne @stage
@end:   rts

; Keep: Y = 0: pipeSrc to LINE_BANK, page 1 + depth; 1: back from there.
Keep:   lda #<pipeSrc
        sta r0L
        lda #>pipeSrc
        sta r0H
        lda #0
        sta r1L
        sta r2L
        lda depth
        clc
        adc #1
        sta r1H
        lda #1
        sta r2H
        lda #LINE_BANK
        sta r3L
        tya
        bne :+
        jmp StashRAM
:       jmp FetchRAM

; Segment: pipeSrc from srcAt to an unquoted "|" (or its end) to lineBuf;
; srcAt past it. C set when a "|" ended it (more stages follow).
Segment:
        ldy srcAt
        ldx #0
        lda #0
        sta quote
@ch:    lda pipeSrc,y
        beq @end
        iny
        sta lineBuf,x
        inx
        lda quote
        bne @inq
        lda pipeSrc-1,y
        cmp #'|'
        beq @pipe
        cmp #'"'
        beq @open
        cmp #$27
        beq @open
        cmp #'\'
        bne @ch
        lda pipeSrc,y           ; (\: the next as it is)
        beq @end
        sta lineBuf,x
        inx
        iny
        bne @ch
@open:  sta quote               ; (sta keeps cmp's flags: jmp, not bne)
        jmp @ch
@inq:   lda pipeSrc-1,y
        cmp quote
        bne @ch
        lda #0
        sta quote
        beq @ch
@pipe:  dex                     ; (the "|" off)
        lda #0
        sta lineBuf,x
        sty srcAt
        sec
        rts
@end:   lda #0
        sta lineBuf,x
        sty srcAt
        clc
        rts

; DoRest: "then", "do": the rest of the statement, if any, run.
DoRest: ldy #0
        lda (restPtr),y
        bne :+
        rts
:       jsr Shift               ; to stmtBuf's start, then as a statement
        jmp Do

; Cond: the rest of the statement run (RunPiped): C clear when its
; status is 0 (true). (Empty: false.)
Cond:   ldy #0
        lda (restPtr),y
        beq @false
        jsr RunPiped
        lda status
        cmp #1                  ; (0: C clear)
        rts
@false: sec
        rts

; DoIf: a frame; the condition; not true: to its elif, else or fi.
DoIf:   lda #FR_IF
        jsr Push
        bcs @end
        jsr Cond
        ldx fsp
        lda #0
        bcs :+
        lda #1
:       sta frDone-1,x          ; (a branch taken)
        bcc @end
        lda #SK_BRANCH
        jsr Skip
@end:   rts

; DoElif: after a branch taken: to fi; else the condition.
DoElif: jsr TopIf
        bcs @end
        lda frDone-1,x
        beq :+
        lda #SK_FI
        jmp Skip
:       jsr Cond
        bcs :+
        ldx fsp
        lda #1
        sta frDone-1,x
        rts
:       lda #SK_BRANCH
        jmp Skip
@end:   rts

; DoElse: after a branch taken: to fi; else this branch.
DoElse: jsr TopIf
        bcs @end
        lda frDone-1,x
        beq :+
        lda #SK_FI
        jmp Skip
:       lda #1
        sta frDone-1,x
        jmp DoRest
@end:   rts

; DoFi: the if's frame off.
DoFi:   jsr TopIf
        bcs @end
        dec fsp
@end:   rts

; DoWhile: a frame (its statement's place, to come back to); the
; condition; not true: the frame off, to done.
DoWhile:
        lda #FR_WHILE
        jsr Push
        bcs @end
        jsr Cond
        bcc @end
        dec fsp
        lda #SK_DONE
        jmp Skip
@end:   rts

; DoFor: "for NAME in words": none: to done; else NAME = the first, a
; frame (index 0).
DoFor:  jsr ForWords
        bcs @bad
        lda count
        bne :+
        lda #SK_DONE
        jmp Skip
:       lda #FR_FOR
        jsr Push
        bcs @end
        ldx fsp
        lda #0
        sta frDone-1,x          ; (the index)
        ldy level               ; its body: after the for statement
        lda exPosLo,y
        sta frBodyLo-1,x
        lda exPosHi,y
        sta frBodyHi-1,x
        jmp ForSet
@bad:   lda #<BadFor
        ldy #>BadFor
        jmp Said
@end:   rts

; DoDone: the loop's end: a while: back to its statement; a for: the
; next word, or the frame off.
DoDone: ldx fsp
        ldy level
        txa
        cmp exBase,y
        beq @lone
        lda frKind-1,x
        cmp #FR_WHILE
        beq @while
        cmp #FR_FOR
        beq @for
@lone:  lda #<NoLoop
        ldy #>NoLoop
        jmp Said
@while: ldy level               ; back to the while statement (it pushes
        lda frPosLo-1,x         ; its frame again)
        sta exPosLo,y
        lda frPosHi-1,x
        sta exPosHi,y
        dec fsp
        rts
@for:   inc frDone-1,x          ; the next word, if any
        lda frPosLo-1,x         ; (the for statement read again)
        ldy level
        pha
        lda exPosLo,y
        sta saveLo
        lda exPosHi,y
        sta saveHi
        pla
        sta exPosLo,y
        lda frPosHi-1,x
        sta exPosHi,y
        jsr GetStmt
        jsr Keyword
        lda kw                  ; ("do for ...": the for after the do)
        cmp #KW_DO
        bne :+
        jsr Shift
:       jsr ForWords
        ldx fsp
        lda frDone-1,x
        cmp count
        bcs @end_for
        ldy level               ; its body again: after the for statement
        lda exPosLo,y           ; (GetStmt left the place there)
        sta frBodyLo-1,x
        lda exPosHi,y
        sta frBodyHi-1,x
        jmp ForSet
@end_for:
        ldy level               ; past the done
        lda saveLo
        sta exPosLo,y
        lda saveHi
        sta exPosHi,y
        dec fsp
        rts

; Shift: the rest (restPtr) to stmtBuf's start, its keyword found.
Shift:  ldy #0
        ldx #0
@copy:  lda (restPtr),y
        sta stmtBuf,x
        beq @kw
        iny
        inx
        bne @copy
@kw:    jmp Keyword

; ForWords: the for statement's rest parsed (Parse): "NAME in words";
; count = the words' number. C set when it is not of that form.
ForWords:
        ldy #0
        ldx #0
@copy:  lda (restPtr),y
        sta lineBuf,x
        beq @parse
        iny
        inx
        bne @copy
@parse: jsr Parse
        bcs @bad
        lda argc
        cmp #2
        bcc @bad
        lda argLo+1             ; word 1: "in"
        sta r0L
        lda argHi+1
        sta r0H
        ldy #0
        lda (r0),y
        cmp #'i'
        bne @bad
        iny
        lda (r0),y
        cmp #'n'
        bne @bad
        iny
        lda (r0),y
        bne @bad
        lda argc
        sec
        sbc #2
        sta count
        clc
        rts
@bad:   sec
        rts

; ForSet: NAME = word (2 + the frame's index) of the parsed for
; statement.
ForSet: ldx fsp
        lda frDone-1,x
        clc
        adc #2
        tax
        lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        lda argLo               ; NAME: word 0
        sta r1L
        lda argHi
        sta r1H
        ldy #$FF
@name:  iny
        lda (r1),y
        sta varName,y
        bne @name
        jmp VarSet

; TopIf: X = fsp when the top frame (of this level) is an if; else C set,
; said.
TopIf:  ldx fsp
        ldy level
        txa
        cmp exBase,y
        beq @no
        lda frKind-1,x
        cmp #FR_IF
        bne @no
        clc
        rts
@no:    lda #<NoIf
        ldy #>NoIf
        jsr Said
        sec
        rts

; Push: a frame of kind A for the statement just read (its place:
; stmtLo/Hi). C set when the stack is full (said).
Push:   ldx fsp
        cpx #FR_MAX
        bcs @full
        sta frKind,x
        lda stmtLo
        sta frPosLo,x
        lda stmtHi
        sta frPosHi,x
        lda #0
        sta frDone,x
        inc fsp
        clc
        rts
@full:  lda #<Deep
        ldy #>Deep
        jsr Said
        sec
        rts

; Skip: skipping in mode A (SK_*) from here.
Skip:   sta skip
        lda #0
        sta nest
        rts

; Skipping: a statement while skipping: only nesting and the keyword
; that ends the skip count.
Skipping:
        lda kw
        cmp #KW_IF
        beq @in
        cmp #KW_WHILE
        beq @in
        cmp #KW_FOR
        beq @in
        cmp #KW_FI
        beq @fi
        cmp #KW_DONE
        beq @done
        cmp #KW_ELIF
        beq @branch
        cmp #KW_ELSE
        beq @branch
        rts
@in:    inc nest
        rts
@fi:    lda nest
        beq :+
        dec nest
        rts
:       lda skip                ; this if's fi
        cmp #SK_DONE
        beq @end
        lda #0
        sta skip
        jmp DoFi
@done:  lda nest
        beq :+
        dec nest
        rts
:       lda skip
        cmp #SK_DONE
        bne @end
        lda #0                  ; the loop's done: past it (no frame)
        sta skip
@end:   rts
@branch:
        lda nest
        bne @end
        lda skip
        cmp #SK_BRANCH
        bne @end
        lda #0                  ; this if's elif or else: taken as such
        sta skip
        lda kw
        cmp #KW_ELSE
        bne :+
        jmp DoElse
:       jmp DoElif

; GetStmt: the statement at this level's place into stmtBuf (zero-
; ended, its spaces in front left out), its place to stmtLo/Hi; the
; place past it and its ";" or line end. Quotes and \ keep ";" and "#";
; "#" at a word's start ends it (to the line's end).
GetStmt:
        ldx level
        lda exPosLo,x
        sta stmtLo
        lda exPosHi,x
        sta stmtHi
        lda #0
        sta quote
        sta out
        lda #' '
        sta prev
@ch:    jsr GetCh
        bcs @end                ; (the text's end)
        ldx quote
        bne @quoted
        cmp #CR
        beq @end
        cmp #10
        beq @end
        cmp #';'
        beq @end
        cmp #'#'
        bne :+
        ldx prev
        cpx #' '
        beq @comment
:       cmp #'"'
        beq @open
        cmp #$27
        beq @open
        cmp #'\'
        bne @put
        jsr @store
        jsr GetCh               ; (\: the next as it is)
        bcs @end
        bcc @put
@open:  sta quote               ; (sta keeps cmp's flags: jmp, not bne)
        jmp @put
@quoted:
        cmp quote
        bne @put
        ldx #0
        stx quote
@put:   jsr @store
        jmp @ch
@comment:
        jsr GetCh               ; to the line's end
        bcs @end
        cmp #CR
        beq @end
        cmp #10
        bne @comment
@end:   ldx out
        lda #0
        sta stmtBuf,x
        rts
@store: sta prev
        ldx out
        cpx #STMT_MAX
        bcs :+
        cmp #' '                ; (spaces in front left out)
        bne @keep
        cpx #0
        beq :+
@keep:  sta stmtBuf,x
        inc out
:       rts

; GetCh: the character at this level's place, the place on; C set at
; the text's end. A page of the text is kept in cache (cachePage: its
; REU page; cacheBank).
GetCh:  ldx level
        lda exPosLo,x
        cmp exLenLo,x
        lda exPosHi,x
        sbc exLenHi,x
        bcc :+
        rts                     ; (C set)
:       lda exPage,x            ; the place's page
        clc
        adc exPosHi,x
        cmp cachePage
        bne @fetch
        lda exBank,x
        cmp cacheBank
        beq @have
@fetch: lda exPage,x
        clc
        adc exPosHi,x
        sta cachePage
        sta r1H
        lda exBank,x
        sta cacheBank
        sta r3L
        lda #0
        sta r1L
        sta r2L
        lda #1
        sta r2H
        lda #<cache
        sta r0L
        lda #>cache
        sta r0H
        jsr FetchRAM
        ldx level
@have:  ldy exPosLo,x
        lda cache,y
        inc exPosLo,x
        bne :+
        inc exPosHi,x
:       clc
        rts

; Keyword: kw = stmtBuf's first word as a keyword (0: none); restPtr at
; the rest after it (its spaces left out).
Keyword:
        lda #0
        sta kw
        lda #<stmtBuf
        sta restPtr
        lda #>stmtBuf
        sta restPtr+1
        ldx #0                  ; Words: each keyword, zero-ended
        lda #1
        sta try
@word:  ldy #0
@ch:    lda Words,x
        beq @end_kw
        cmp stmtBuf,y
        bne @next
        inx
        iny
        bne @ch
@end_kw:
        lda stmtBuf,y           ; the word ends there too?
        beq @found
        cmp #' '
        beq @found
@next:  lda Words,x             ; to the next keyword
        beq :+
        inx
        bne @next
:       inx
        inc try
        lda Words,x
        bne @word
        rts
@found: lda try
        sta kw
@sp:    lda stmtBuf,y           ; the rest
        cmp #' '
        bne :+
        iny
        bne @sp
:       tya
        clc
        adc #<stmtBuf
        sta restPtr
        lda #>stmtBuf
        adc #0
        sta restPtr+1
        rts

Words:  .byte "if", 0, "then", 0, "elif", 0, "else", 0, "fi", 0
        .byte "while", 0, "do", 0, "done", 0, "for", 0, 0

; Stop: C set when RUN/STOP is held (the keyboard matrix: row 7, bit 7):
; breakReq set, the key's release waited for.
Stop:   php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda $DC00
        pha
        lda #$7F
        sta $DC00
        lda $DC01
        and #$80
        bne @no
@wait:  lda $DC01               ; (until it is let go)
        and #$80
        beq @wait
        lda #1
        sta breakReq
@no:    pla
        sta $DC00
        pla
        sta CPU_PORT
        plp
        lda breakReq
        cmp #1                  ; (C set: held)
        ldx level
        rts

Open:           .byte "gush: a block left open (if/while/for)", 0
NoIf:           .byte "gush: elif, else or fi without if", 0
NoLoop:         .byte "gush: done without while or for", 0
BadFor:         .byte "gush: for NAME in words", 0
Deep:           .byte "gush: blocks nested too deep", 0
Stopped:        .byte "^C (stopped)", 0

        .segment "DATA"

level:          .byte 0         ; the level being run
fsp:            .byte 0         ; frames in use
skip:           .byte 0         ; SK_*, 0: running
nest:           .byte 0         ; blocks opened while skipping
kw:             .byte 0
try:            .byte 0
count:          .byte 0
quote:          .byte 0
prev:           .byte 0
out:            .byte 0
stmtLo:         .byte 0
stmtHi:         .byte 0
saveLo:         .byte 0
saveHi:         .byte 0
breakReq:       .byte 0
stage:          .byte 0         ; RunPiped: the stage, more after it,
more:           .byte 0         ; its place in pipeSrc
srcAt:          .byte 0
cachePage:      .byte $FF
cacheBank:      .byte $FF

        .segment "BSS"

exBank:         .res LEVELS     ; per level: its text
exPage:         .res LEVELS
exLenLo:        .res LEVELS
exLenHi:        .res LEVELS
exPosLo:        .res LEVELS     ; its place
exPosHi:        .res LEVELS
exBase:         .res LEVELS     ; frames below its own
frKind:         .res FR_MAX
frPosLo:        .res FR_MAX     ; the statement that opened it
frPosHi:        .res FR_MAX
frBodyLo:       .res FR_MAX
frBodyHi:       .res FR_MAX
frDone:         .res FR_MAX     ; if: a branch taken; for: its index
        .segment "HIGHBSS"
stmtBuf:        .res STMT_MAX + 1
pipeSrc:        .res 256
cache:          .res 256
        .segment "BSS"
