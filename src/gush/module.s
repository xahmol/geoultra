; gush: external commands (docs/GUSH.md, "Step 3", sub-step 8; writing
; one: docs/GUSH_COMMANDS.md). A module is a file whose data starts with
; MOD_MAGIC ("GCMD"), the API version it needs and a jmp to its code,
; built for the transient area TRANS ($5000, 4 KB at most, the overlays'
; area: ovl.s): on a GEOS drive a GEOS file of class "gush cmd", on the
; Ultimate its CVT (prog.s finds both). RunModule loads it there and
; calls it with the words in argc/argLo/argHi (word 0 its name); it
; returns with C clear (done) or set (failed). It reaches gush only
; through the API table at $0403 (gush.s): core routines, never an
; overlay's (the module is where an overlay would go). The wrappers the
; table needs are here too. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Fail, failed, prog, OvlDrop
        .import VarFind, VarSet, varName, ReadIn, inHandle, Decimal, num
        .import argc
        .export RunModule, ApiArgc, ApiGetVar, ApiSetVar, ApiReadIn
        .export ApiDecimal, ApiKey

GetNextChar     = $C2A7         ; GEOS jump table
NAME_MAX        = 16            ; (vars.s)
API_VERSION     = 1             ; (docs/GUSH_COMMANDS.md)
MOD_ENTRY       = 5             ; the module's jmp, after magic and version

        .segment "CODE"

; RunModule: the module at prog loaded and run (word 0 the command).
; failed set when it fails, or when it cannot be loaded (said).
RunModule:
        jsr OvlDrop             ; (the area is the module's now)
        lda prog
        sta r0L
        lda prog+1
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle
        txa
        beq :+
        jmp @fail
:
        lda #<TRANS             ; all of it, at most the area
        sta r1L
        lda #>TRANS
        sta r1H
        lda #<TRANS_SIZE
        sta r2L
        lda #>TRANS_SIZE
        sta r2H
        ldy handle
        lda #FE_READ
        jsr FileEngine
        stx error
        lda r2L                 ; (less than the area: the whole file)
        sta got
        lda r2H
        sta got+1
        lda #<extra             ; more than the area: too large
        sta r1L
        lda #>extra
        sta r1H
        lda #1
        sta r2L
        lda #0
        sta r2H
        ldy handle
        lda #FE_READ
        jsr FileEngine
        lda r2L
        sta more
        ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        ldx error
        bne @fail
        ldx #ERR_MODULE         ; (each check below: X this)
        lda more
        bne @fail
        lda got+1               ; at least magic, version and its jmp
        bne :+
        lda got
        cmp #MOD_ENTRY + 3
        bcc @fail
:       ldy #3
@magic: lda TRANS,y
        cmp Magic,y
        bne @fail
        dey
        bpl @magic
        lda TRANS + 4           ; a newer gush needed?
        cmp #API_VERSION + 1
        bcs @fail
        lda #0
        sta failed
        jsr TRANS + MOD_ENTRY
        bcc :+
        lda #1
        sta failed
:       rts
@fail:  ldy #$FF                ; ("gush: NAME: TEXT")
        jmp Fail

Magic:  .byte "GCMD"

; --- API wrappers (gush.s's table) ------------------------------------

; ApiArgc: A = the words (word 0 the command's name).
ApiArgc:
        lda argc
        rts

; ApiGetVar: the variable named at r0. C clear: r1 = its value
; (zero-ended); C set: none.
ApiGetVar:
        jsr Name
        bcs :+
        jmp VarFind
:       rts

; ApiSetVar: the variable named at r0 = the value at r1. C set: the
; table full or the name too long (said).
ApiSetVar:
        jsr Name
        bcs :+
        lda r1L
        sta r0L
        lda r1H
        sta r0H
        jmp VarSet
:       rts

; Name: the name at r0 to varName. C set when longer than NAME_MAX.
Name:   ldy #$FF
@ch:    iny
        cpy #NAME_MAX + 1
        bcs @end
        lda (r0),y
        sta varName,y
        bne @ch
        clc
@end:   rts

; ApiReadIn: up to r2 bytes of the command's input (< file or a pipe)
; to (r1); r2 = the bytes read (0: the end). C set: no input given.
; X = 0 or an error.
ApiReadIn:
        ldy inHandle
        cpy #$FF
        bne :+
        sec
        rts
:       jsr ReadIn
        clc
        rts

; ApiDecimal: r0-r1 (32 bits, r0L the lowest byte) printed in decimal,
; right-aligned in A columns (0: as long as it is).
ApiDecimal:
        pha
        ldx #3
@n:     ldy Regs,x
        lda 0,y
        sta num,x
        dex
        bpl @n
        pla
        jmp Decimal

Regs:   .byte r0L, r0H, r1L, r1H

; ApiKey: A = the next key, waited for.
ApiKey: jsr GetNextChar
        cmp #0
        beq ApiKey
        rts

        .segment "DATA"

handle:         .byte 0
error:          .byte 0
more:           .byte 0
extra:          .byte 0
got:            .word 0
