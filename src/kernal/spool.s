; The print spooler (docs/DESIGN.md "Print spooler"; the user's decisions
; of 2026-11-15). Part 1: the queue's REU banks. Banks 27-28 always; with
; SETTINGS.INI [system] spool= (KB: 128, 256, 512, 1024, 2048; read by
; the auto-exec module 92 at the cold start) more, at the top of the
; drives' area (banks 31-187) as far as no mounted drive uses them there;
; FE_MOUNT and the disk images gone into stay below (driveLimit, the
; file engine's Banks0). The queue's logical bank n: 27 + n for n < 2,
; spoolBase + n - 2 after. Own code.

        .include "geos.inc"
        .include "engine.inc"

        .import OvlCall, drvTracks
        .export SpoolInit, spoolExtra, spoolBase, driveLimit

SPOOL_FIXED     = 2             ; banks 27-28
SPOOL_MAX       = 32            ; 2 MB

        .segment "KEXT"

; SpoolInit (module 92, the cold start): A, X = spool='s first and
; fourth character (0: no spool=).
SpoolInit:
        jsr OvlCall
        .byte 105, 0

spoolExtra:     .byte 0                 ; banks beyond 27-28
spoolBase:      .byte FE_LAST_BANK + 1  ; the first of them
driveLimit:     .byte FE_LAST_BANK + 2  ; a drive's banks end below this - 1

; ======================================================================

        .segment "OVL105"
        .scope Mod105

        jmp Init                ; entry 0

        .include "banksof.inc"

; Init: A, X = spool='s first and fourth character: the banks wanted
; (128, 256, 512: 2, 4, 8; 1024, 2048: 16, 32; else 2); up to that - 2
; at the top of the drives' area, from bank 187 down, while no REU drive
; uses them; spoolExtra, spoolBase, driveLimit set.
Init:   stx tmp
        ldx #2
@d:     cmp Digit,x
        beq @dig
        dex
        bpl @d
@none:  lda #2                  ; (none or another value: 128 KB)
        bne @want
@dig:   lda tmp                 ; a fourth digit: 1024, 2048
        cmp #'0'
        bcc :+
        cmp #'9' + 1
        bcs :+
        inx
        inx
        inx
:       lda Banks,x
        beq @none               ; (5xxx: as none)
@want:  sec
        sbc #SPOOL_FIXED
        bcs :+
        lda #0
:       cmp #SPOOL_MAX - SPOOL_FIXED + 1
        bcc :+
        lda #SPOOL_MAX - SPOOL_FIXED
:       sta want
        lda #0
        sta got
@bank:  lda got
        cmp want
        bcs @set
        lda #FE_LAST_BANK       ; the next bank down
        sec
        sbc got
        sta bank
        ldx #3                  ; any REU drive on it?
@drive: lda driveType,x
        bpl @next               ; (not an REU drive)
        and #$0F
        beq @next
        lda bank
        cmp ramBase,x
        bcc @next               ; (below its first bank)
        jsr BanksOf             ; its end: ramBase + banks
        clc
        adc ramBase,x
        cmp bank
        beq @next
        bcs @set                ; (on it: no further)
@next:  dex
        bpl @drive
        inc got
        bne @bank               ; (always)
@set:   lda got
        sta spoolExtra
        lda #FE_LAST_BANK + 1
        sec
        sbc got
        sta spoolBase
        clc
        adc #1
        sta driveLimit
        rts

Digit:          .byte "125"         ; 128, 256, 512; a fourth digit: x + 3
Banks:          .byte 2, 4, 8, 16, 32, 0
tmp:            .byte 0
want:           .byte 0
got:            .byte 0
bank:           .byte 0

        .endscope
