; VLIR overlays for a GEOS application (gush, the desktop; docs/GUSH.md
; "Memory", docs/DESKTOP.md "Structure"). Shared code, own design: moved
; here from gush's ovl.s on 2026-11-11 when the desktop needed the same.
;
; The application is a VLIR file: record 0 the resident core; records 1
; to OVL_N overlays linked at TRANS (TRANS_SIZE bytes). OvlInit, the
; first thing at the start (dirEntryBuf still holds the application's
; own entry: GetFile and FE_RUNSYS leave it), reads each overlay record
; once into the application's REU bank OVL_BANK, TRANS_SIZE apart, so a
; later cd or another drive never matters. A stub (Stub macro: jsr OvlGo
; / .byte overlay / .addr routine) fetches the overlay its routine lives
; in when another one is in the area. Overlay code may call the core and
; its own overlay's stubs, never another overlay's (its return would
; land in other code); core code that an overlay calls must not call an
; overlay either. An overlay's DATA comes back as built with each fetch:
; scratch only; lasting variables belong in the core's BSS.
;
; The includer defines TRANS, TRANS_SIZE, OVL_BANK, OVL_N and OvlFail
; (what a stub does when the overlays could not be read: it returns to
; the stub's caller), includes geos.inc first, and puts this include in
; its CODE segment. Exports OvlInit, OvlDrop, OvlGo, ovlOk.

ReadFile        = $C1FF         ; GEOS jump table
GetBlock        = $C1E4

        .export OvlInit, OvlDrop, OvlGo, ovlOk

        .segment "ZEROPAGE"

ovlP:           .res 2          ; OvlGo: the stub's bytes

        .segment "CODE"

; OvlInit: the overlay records (the application's index block, from its
; directory entry) read and kept in the REU. ovlOk set when all were.
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
        jsr OvlReu
        jsr StashRAM
        ldy ovlAt
        iny
        iny
        cpy #OVL_N * 2
        bcc @rec
        inc ovlOk
@end:   rts

; OvlDrop: no overlay in the area any more (something else loaded
; there); the next stub fetches its own.
OvlDrop:
        lda #$FF
        sta curOvl
        rts

; OvlReu: r0-r3 for overlay (A / 2 + 1) between TRANS and its REU place
; (bank OVL_BANK, (n - 1) * TRANS_SIZE; TRANS_SIZE a multiple of $800).
OvlReu: sta r1H                 ; ((n - 1) * 2 * TRANS_SIZE / 2 / 256)
        lda #0
        sta r1L
        ldx #>TRANS_SIZE        ; (pages: shifts of r1H by log2(pages / 2))
@sh:    cpx #4                  ; (16 pages: 3 shifts, (n - 1) * 2 * 8)
        bcc @done
        asl r1H
        txa
        lsr a
        tax
        bne @sh
@done:  lda #<TRANS
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
; Y, the flags and r0-r3 as the stub got them (kept across the fetch,
; which uses them: the desktop's ThemeUse takes r0; found 2026-11-11).
; It returns to the stub's caller.
; Without the overlays: OvlFail (the includer's), back to the caller.
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
        ldx #7                  ; r0-r3 kept across the fetch
@keep:  lda r0L,x
        sta keepR,x
        dex
        bpl @keep
        lda curOvl
        sec                     ; (n - 1) * 2
        sbc #1
        asl
        jsr OvlReu
        jsr FetchRAM
        ldx #7
@back:  lda keepR,x
        sta r0L,x
        dex
        bpl @back
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
@fail:  jmp OvlFail

; Stub: a routine's name in the core, Ov_name in its overlay.
.macro Stub name, ovl
        .export name
        .import .ident(.concat("Ov_", .string(name)))
name:   jsr OvlGo
        .byte ovl
        .addr .ident(.concat("Ov_", .string(name)))
.endmacro

        .segment "DATA"

ovlOk:          .byte 0
curOvl:         .byte $FF
ovlAt:          .byte 0
keepA:          .byte 0
keepX:          .byte 0
keepY:          .byte 0
keepP:          .byte 0
ovlJmp:         .word 0
keepR:          .res 8          ; r0-r3 across a fetch
ovlTS:          .res OVL_N * 2

        .segment "CODE"
