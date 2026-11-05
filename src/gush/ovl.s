; gush: overlays (docs/GUSH.md, "Memory"). gush is a VLIR file: record 0
; the resident core at $0400-$4FFF (console, editor, parser, executor,
; variables, scripts, redirection, starting programs); records 1-OVL_N
; overlays linked at TRANS ($5000-$5FFF, gush.cfg), the area external
; commands (step 3.8) use too. OvlInit, the first thing at gush's start
; (dirEntryBuf still holds gush's own entry, GetFile left it), reads each
; overlay record once into the application's REU bank OVL_BANK, 4 KB
; each, so a later cd or another drive never matters; the stubs at the
; end, through OvlGo, fetch the overlay a routine lives in when another
; one is there. Overlay code may call the core, and its own overlay's
; stubs; never another overlay's (its return would land in other code).
; An overlay's DATA comes back as built with each fetch: scratch only.
; Without the records (a failed read) overlay commands fail quietly, and
; the start says so. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import failed
        .export OvlInit, ovlOk

ReadFile        = $C1FF         ; GEOS jump table
GetBlock        = $C1E4
StashRAM        = $C2C8
FetchRAM        = $C2CB
OVL_BANK        = 7             ; (1-6: history, cp -r, HIGH, scripts,
                                ; lines, pipes; the last free bank)
TRANS           = $5000         ; the transient area (gush.cfg)
TRANS_SIZE      = $1000
OVL_N           = 2             ; overlay records

        .segment "ZEROPAGE"

ovlP:           .res 2          ; OvlGo: the stub's bytes

        .segment "CODE"

; OvlInit: the overlay records (gush's index block, from its directory
; entry) read and kept in the REU. ovlOk set when all were.
OvlInit:
        lda #0
        sta ovlOk
        lda #$FF
        sta curOvl
        lda dirEntryBuf + OFF_GSTRUC_TYPE
        cmp #VLIR
        bne @end
        lda dirEntryBuf + OFF_DE_TR_SC
        sta r1L
        lda dirEntryBuf + OFF_DE_TR_SC + 1
        sta r1H
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        bne @end
        ldx #OVL_N * 2 - 1      ; records 1.. (record 0 at bytes 2-3)
@ts:    lda diskBlkBuf + 4,x
        sta ovlTS,x
        dex
        bpl @ts
        ldy #0
@rec:   sty ovlAt               ; (record n: ovlAt = (n - 1) * 2)
        lda ovlTS,y
        beq @end                ; (no such record)
        sta r1L
        lda ovlTS + 1,y
        sta r1H
        lda #<TRANS
        sta r7L
        lda #>TRANS
        sta r7H
        lda #<TRANS_SIZE
        sta r2L
        lda #>TRANS_SIZE
        sta r2H
        jsr ReadFile
        txa
        bne @end
        lda ovlAt
        jsr Reu
        jsr StashRAM
        ldy ovlAt
        iny
        iny
        cpy #OVL_N * 2
        bcc @rec
        inc ovlOk
@end:   rts

; Reu: r0-r3 for overlay (A / 2 + 1) between TRANS and its REU place
; (bank OVL_BANK, (n - 1) * 4 KB).
Reu:    asl                     ; ((n - 1) * 2 * 8 = (n - 1) * $10 pages)
        asl
        asl
        sta r1H
        lda #0
        sta r1L
        lda #<TRANS
        sta r0L
        lda #>TRANS
        sta r0H
        lda #<TRANS_SIZE
        sta r2L
        lda #>TRANS_SIZE
        sta r2H
        lda #OVL_BANK
        sta r3L
        rts

; OvlGo (from a stub: jsr OvlGo / .byte overlay / .addr routine): the
; overlay fetched when another one is there, then the routine with A, X,
; Y and the flags as the stub got them (r0-r3 are not kept: the routines
; behind stubs take no r registers). It returns to the stub's caller.
; Without the overlays: failed = 1, back to the caller.
OvlGo:  sta keepA
        stx keepX
        sty keepY
        php
        pla
        sta keepP
        pla                     ; (the stub's bytes, after its jsr)
        sta ovlP
        pla
        sta ovlP + 1
        ldy #1
        lda (ovlP),y
        cmp curOvl
        beq @go
        ldx ovlOk
        beq @fail
        sta curOvl
        sec                     ; (n - 1) * 2
        sbc #1
        asl
        jsr Reu
        jsr FetchRAM
@go:    ldy #2
        lda (ovlP),y
        sta ovlJmp
        iny
        lda (ovlP),y
        sta ovlJmp + 1
        lda keepP
        pha
        lda keepA
        ldx keepX
        ldy keepY
        plp
        jmp (ovlJmp)
@fail:  lda #1
        sta failed
        rts

; The stubs: a routine's name in the core, Ov_name in its overlay.
.macro Stub name, ovl
        .export name
        .import .ident(.concat("Ov_", .string(name)))
name:   jsr OvlGo
        .byte ovl
        .addr .ident(.concat("Ov_", .string(name)))
.endmacro

        Stub CmdCp, 1           ; overlay 1: files.s, tree.s, sys.s, hist.s
        Stub CmdMv, 1
        Stub CmdRm, 1
        Stub CmdMkdir, 1
        Stub CmdRmdir, 1
        Stub CmdCat, 1
        Stub CmdMore, 1
        Stub CmdDf, 1
        Stub CmdMount, 1
        Stub CmdUmount, 1
        Stub CmdMkimg, 1
        Stub CmdFree, 1
        Stub CmdReboot, 1
        Stub HistSave, 1
        Stub HistLoad, 1
        Stub CmdTurbo, 2        ; overlay 2: sysset.s, test.s
        Stub CmdDate, 2
        Stub CmdNtp, 2
        Stub CmdTest, 2
        Stub CmdBracket, 2
        Stub CmdRead, 2
        Stub CmdTrue, 2
        Stub CmdFalse, 2

        .segment "DATA"

ovlOk:          .byte 0
curOvl:         .byte $FF
ovlAt:          .byte 0
keepA:          .byte 0
keepX:          .byte 0
keepY:          .byte 0
keepP:          .byte 0
ovlJmp:         .word 0
ovlTS:          .res OVL_N * 2
