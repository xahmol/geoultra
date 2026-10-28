; Temporary milestone demo, removed when the desktop arrives:
; - process 0 blinks a square in the top right corner every second,
; - a click (press) toggles the pattern inside the box,
; - every key press shows its code as 8 squares under the box (black = 1)
;   and is logged at KEY_LOG (32 codes, count at KEY_LOG + 32) for tests.

KEY_LOG = $0400

        .include "geos.inc"

        .export DemoInit
        .import InitProcesses, RestartProcess, SetPattern, Rectangle

        .segment "DATA"

blinkOn:        .byte 0
boxOn:          .byte 0
bitNo:          .byte 0

        .segment "RODATA"

procTable:
        .word DemoBlink, 50

        .segment "CODE"

DemoInit:
        lda #0
        ldx #32
@clr:   sta KEY_LOG,x
        dex
        bpl @clr
        lda #<procTable
        sta r0L
        lda #>procTable
        sta r0H
        lda #1
        jsr InitProcesses
        ldx #0
        jsr RestartProcess
        lda #<DemoClick
        sta otherPressVec
        lda #>DemoClick
        sta otherPressVec+1
        lda #<DemoKey
        sta keyVector
        lda #>DemoKey
        sta keyVector+1
        rts

; Fill r2L..r2H, r3..r4 (x below 256) with pattern A.
FillBox:
        jsr SetPattern
        lda #0
        sta r3H
        sta r4H
        jmp Rectangle

DemoBlink:
        lda blinkOn
        eor #1
        sta blinkOn
        ldx #8
        stx r2L
        ldx #15
        stx r2H
        ldx #<296
        stx r3L
        ldx #<303
        stx r4L
        jsr SetPattern
        lda #>296
        sta r3H
        sta r4H
        jmp Rectangle

DemoClick:
        lda mouseData
        bmi @end                ; release
        lda boxOn
        eor #1
        sta boxOn
        beq @fill
        lda #3                  ; light dots
@fill:  ldx #81
        stx r2L
        ldx #118
        stx r2H
        ldx #81
        stx r3L
        ldx #238
        stx r4L
        jmp FillBox
@end:   rts

DemoKey:
        lda KEY_LOG + 32
        and #31
        tax
        lda keyData
        sta KEY_LOG,x
        inc KEY_LOG + 32
        lda #0
        sta bitNo
@bit:   ldx bitNo               ; square for bit 7 - bitNo at x = 96 + 16 * bitNo
        lda keyData
@shift: cpx #0
        beq @test
        asl
        dex
        jmp @shift
@test:  and #$80
        beq @pat
        lda #1
@pat:   ldx #130
        stx r2L
        ldx #137
        stx r2H
        pha
        lda bitNo
        asl
        asl
        asl
        asl
        clc
        adc #96
        sta r3L
        adc #11
        sta r4L
        pla
        jsr FillBox
        inc bitNo
        lda bitNo
        cmp #8
        bne @bit
        rts
