; File engine: the Ultimate's Command Interface for gush's network
; commands (docs/design/FILE_ENGINE.md "Functions"; engine.s has the module
; list): module 80 FE_UCI, a command sent as given and its reply's data
; taken, through the exchange every Ultimate call uses (module 36,
; engineult.s), so the protocol lives in one place. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall

        .segment "OVL80"
        .scope Mod80

        jmp OvUci               ; entry 0

        .include "feult.inc"

; FE_UCI: r0 = a command (its target, command and bytes), r1L = its
; length (2 to U_CMD_MAX), r2 = a buffer for the reply's data, r3 = its
; size (0: none wanted). r3 = the data's length, r4 = the status's first
; two characters; X = 0, or the error (FE_ULTIMATE: the Ultimate said
; no; DEV_NOT_FOUND: no Command Interface; FE_BAD_PATH: a length out of
; range).
OvUci:  ldx #FE_BAD_PATH
        lda argR1
        cmp #2
        bcc @end
        cmp #U_CMD_MAX + 1
        bcs @end
        sta uLen
        lda argR0               ; the command to uCmd
        sta r5L
        lda argR0+1
        sta r5H
        ldy uLen
@cmd:   dey
        lda (r5),y
        sta uCmd,y
        tya
        bne @cmd
        lda argR2               ; the reply to r2 .. r2 + r3
        sta r0L
        clc
        adc argR3
        sta uEnd
        lda argR2+1
        sta r0H
        adc argR3+1
        sta uEnd+1
        lda argR3
        ora argR3+1
        bne :+
        jsr UNoData
:       jsr UExec
        lda r0L                 ; its length: where it ended
        sec
        sbc argR2
        sta argR3
        lda r0H
        sbc argR2+1
        sta argR3+1
        lda uStat
        sta argR4
        lda uStat+1
        sta argR4+1
@end:   rts

        .endscope
