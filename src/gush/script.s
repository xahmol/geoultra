; gush: scripts (docs/GUSH.md). A script is a text
; file, read whole into gush's REU (bank SCRIPT_BANK, SCRIPT_MAX bytes per
; level, DEPTH_MAX levels: scripts may run scripts), then its lines run
; statement by statement as typed lines are (Exec, flow.s). $0 is its path, $1-$9 its words,
; $# their number (ArgN, for parse.s); "exit N" ends it with status N.
; Variables are shared with the caller (no subshell). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Fail, argc, argLo, argHi
        .import failed, VarFind, varName, Exec, ScriptExec
        .export RunScript, CmdSource, ArgN, depth, exitReq, exitStatus
        .export RunRc

SCRIPT_BANK     = 4             ; (1: history, 2: cp -r, 3: HIGH)
SCRIPT_MAX      = $4000         ; a script's bytes at most
DEPTH_MAX       = 4
ARGS_SIZE       = 256           ; a level's $0-$9, zero-ended one after
                                ; the other
StashRAM        = $C2C8
FetchRAM        = $C2CB

        .segment "CODE"

; source file [words]: the file run as a script.
CmdSource:
        lda argc
        cmp #2
        bcs :+
        ldx #ERR_WORDS
        ldy #$FF
        jmp Fail
:       ldx #1
        lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        ldx #2                  ; its words: from word 2
; RunScript: the script at r0 (a path), its words from word X on. status
; ($?): its last line's, or exit's. Errors said.
RunScript:
        stx from
        lda depth
        cmp #DEPTH_MAX
        bcc :+
        ldx #ERR_DEEP           ; (scripts nested too deep)
        ldy #$FF
        jmp Fail
:       ldx #3                  ; the caller's script: kept
@push:  lda path,x              ; (path, len)
        pha
        dex
        bpl @push
        lda r0L
        sta path
        lda r0H
        sta path+1
        jsr Words               ; $0-$9 kept (argBuf is reused by its lines)
        jsr Load
        bcs @out                ; (said)
        lda len                 ; its text to Exec (flow.s)
        ldy len+1
        jsr ScriptExec
        inc depth
        ldx depth
        jsr Exec
        lda exitReq
        beq @done
        lda exitStatus          ; exit N: the status of the line that ran
        sta failed              ; the script (Run makes it status)
        lda #0
        sta exitReq
@done:  dec depth
@out:   ldx #0
@pop:   pla
        sta path,x
        inx
        cpx #4
        bne @pop
        rts
        .assert len = path + 2, error, "RunScript: path, len together"

; Words: this level's arguments: $0 the path, then words from..argc-1
; (nine at most), into Args + (depth * ARGS_SIZE); their number to
; argCount + depth. Longer than ARGS_SIZE: cut.
Words:  lda depth               ; (the level about to run: depth now)
        clc
        adc #>Args
        sta r1H
        lda #<Args
        sta r1L
        ldy #0
        lda path                ; $0
        sta r0L
        lda path+1
        sta r0H
        jsr Copy
        ldx from
        lda #0
        sta count
@word:  cpx argc
        bcs @end
        lda count
        cmp #9
        bcs @end
        lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        stx at
        jsr Copy
        ldx at
        inx
        inc count
        bne @word
@end:   ldx depth
        lda count
        sta argCount,x
        rts

; Copy: the zero-ended text at r0 to (r1),y on (Y on past its zero;
; stops at the area's end).
Copy:   sty dst
        ldy #$FF
@ch:    iny
        lda (r0),y
        sty src
        ldy dst
        sta (r1),y
        inc dst
        beq @full
        ldy src
        cmp #0
        bne @ch
        ldy dst
        rts
@full:  ldy #$FF                ; (cut: the area's last byte its zero)
        lda #0
        sta (r1),y
        rts

; ArgN: A = 0-9: the current script's word A ($0: its path); C set:
; none (not in a script, or fewer words). r1 = the word. A = $FF: $#,
; its words' number in decimal at r1.
ArgN:   ldx depth
        beq @none
        cmp #$FF
        beq @count
        cmp #0
        beq :+
        cmp argCount-1,x
        beq :+
        bcs @none
:       sta at
        dex                     ; (the running level: depth - 1)
        txa
        clc
        adc #>Args
        sta r1H
        lda #<Args
        sta r1L
        ldy #0
@skip:  lda at                  ; past at words
        beq @here
@past:  lda (r1),y
        iny
        cmp #0
        bne @past
        dec at
        jmp @skip
@here:  tya
        clc
        adc r1L
        sta r1L
        bcc :+
        inc r1H
:       clc
        rts
@count: lda argCount-1,x        ; (0-9: one digit)
        ora #'0'
        sta digit
        lda #<digit
        sta r1L
        lda #>digit
        sta r1H
        clc
        rts
@none:  sec
        rts

; Load: the file at path read into this level's REU area: len its
; bytes. C set: it does not open, or is longer than SCRIPT_MAX (said).
Load:   lda path
        sta r0L
        lda path+1
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        txa
        beq :+
        ldy #$FF
        jsr Fail
        sec
        rts
:       lda #0
        sta len
        sta len+1
@chunk: lda #<chunk             ; 256 bytes at a time
        sta r1L
        lda #>chunk
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
        ora r2H
        beq @close              ; (the end)
        lda len+1               ; room for it?
        cmp #>SCRIPT_MAX
        bcs @long
        lda r2L                 ; this level's area + len
        sta count
        lda r2H
        sta count+1
        jsr Area
        lda len
        sta r1L
        lda r1H
        clc
        adc len+1
        sta r1H
        lda #<chunk
        sta r0L
        lda #>chunk
        sta r0H
        lda count
        sta r2L
        lda count+1
        sta r2H
        jsr StashRAM
        lda len
        clc
        adc count
        sta len
        lda len+1
        adc count+1
        sta len+1
        lda count+1             ; a full 256: more may come
        bne @chunk
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        clc
        rts
@long:  ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        ldx #ERR_LONG           ; (longer than SCRIPT_MAX)
        ldy #$FF
        jsr Fail
        sec
        rts

; Area: r1H = this level's REU page base (depth * SCRIPT_MAX / 256),
; r3L = SCRIPT_BANK.
Area:   lda depth
        asl                     ; (SCRIPT_MAX = $4000: depth * $40 pages)
        asl
        asl
        asl
        asl
        asl
        sta r1H
        lda #SCRIPT_BANK
        sta r3L
        rts
        .assert SCRIPT_MAX = $4000 && DEPTH_MAX <= 4, error, "Area: four levels of $4000"

; RunRc: HOME/gushrc run as a script when it is there (gush's start).
RunRc:  lda #<HomeName
        sta r0L
        lda #>HomeName
        sta r0H
        ldy #0
@name:  lda HomeName,y
        sta varName,y
        beq :+
        iny
        bne @name
:       jsr VarFind
        bcs @end
        ldy #0                  ; HOME "/gushrc"
@home:  lda (r1),y
        beq @rc
        sta rcPath,y
        iny
        cpy #RC_MAX
        bcc @home
        rts
@rc:    ldx #0
@tail:  lda RcName,x
        sta rcPath,y
        beq @stat
        iny
        inx
        bne @tail
@stat:  lda #<rcPath
        sta r0L
        lda #>rcPath
        sta r0H
        lda #<chunk
        sta r1L
        lda #>chunk
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        bne @end                ; (none: nothing)
        lda #<rcPath
        sta r0L
        lda #>rcPath
        sta r0H
        ldx #$FF                ; (no words: argc is 0 here)
        jmp RunScript
@end:   rts

RC_MAX          = 32
HomeName:       .byte "HOME", 0
RcName:         .byte "/gushrc", 0

        .segment "DATA"

depth:          .byte 0         ; scripts running
exitReq:        .byte 0         ; exit in a script: end it
exitStatus:     .byte 0
from:           .byte 0
at:             .byte 0
count:          .word 0
src:            .byte 0
dst:            .byte 0
handle:         .byte 0
ender:          .byte 0
digit:          .byte 0, 0
path:           .word 0
len:            .word 0

        .segment "BSS"

argCount:       .res DEPTH_MAX
rcPath:         .res RC_MAX + 8
chunk:          .res 256
Args:           .res DEPTH_MAX * ARGS_SIZE   ; (level n: Args + n * 256)
