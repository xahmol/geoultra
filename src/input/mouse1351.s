; Input driver for the Commodore 1351 mouse in proportional mode,
; control port 1, at MOUSE_BASE ($FE80).
;
; The movement calculation follows the algorithm published in the
; Commodore 1351 Mouse User's Manual (pot value difference over 7 bits,
; bit 0 noise discarded). Adapted: own code, GEOS variables and limits.

        .include "geos.inc"
        .include "hw.inc"

        .segment "INPUT"

        jmp DrvInit                     ; InitMouse
        jmp DrvSlow                     ; SlowMouse
        jmp DrvUpdate                   ; UpdateMouse

oldX:   .byte 0
oldY:   .byte 0
dOld:   .byte 0
dNew:   .byte 0
moved:  .byte 0

PORT1_POTS = $7F                        ; CIA1 port A bits 7/6 = 0/1

DrvInit:
        lda #8
        sta mouseXPos
        sta mouseYPos
        lda #0
        sta mouseXPos+1
        sta pressFlag
        lda #$80
        sta mouseData
        lda cia1DdrA
        ora #$C0
        sta cia1DdrA
        lda #PORT1_POTS
        sta cia1PortA
        lda sidPotX
        sta oldX
        lda sidPotY
        sta oldY
DrvSlow:
        rts

DrvUpdate:
        lda #PORT1_POTS
        sta cia1PortA
        lda #0
        sta moved
        lda sidPotX
        ldy oldX
        jsr Delta
        sty oldX
        cmp #0
        beq @y
        inc moved
        clc
        adc mouseXPos
        sta mouseXPos
        txa
        adc mouseXPos+1
        sta mouseXPos+1
        bmi @xMin                       ; left of 0
        lda mouseXPos+1                 ; clamp to mouseLeft..mouseRight
        cmp mouseLeft+1
        bcc @xMin
        bne @xMax
        lda mouseXPos
        cmp mouseLeft
        bcc @xMin
@xMax:  lda mouseRight+1
        cmp mouseXPos+1
        bcc @xHigh
        bne @y
        lda mouseRight
        cmp mouseXPos
        bcs @y
@xHigh: lda mouseRight
        sta mouseXPos
        lda mouseRight+1
        sta mouseXPos+1
        jmp @y
@xMin:  lda mouseLeft
        sta mouseXPos
        lda mouseLeft+1
        sta mouseXPos+1

@y:     lda sidPotY
        ldy oldY
        jsr Delta
        sty oldY
        cmp #0
        beq @button
        inc moved
        sta dNew                        ; mouseYPos -= delta (pot Y grows upwards)
        cpx #0
        bmi @down
        lda mouseYPos
        sec
        sbc dNew
        bcc @yMin
        cmp mouseTop
        bcc @yMin
        sta mouseYPos
        jmp @button
@down:  lda mouseYPos
        sec
        sbc dNew                        ; subtracting a negative delta
        bcs @yMax                       ; wrapped past 255
        cmp mouseBottom
        bcs @yMax
        sta mouseYPos
        jmp @button
@yMin:  lda mouseTop
        sta mouseYPos
        jmp @button
@yMax:  lda mouseBottom
        sta mouseYPos

@button:
        lda moved
        beq @fire
        lda pressFlag
        ora #INPUT_BIT
        sta pressFlag
@fire:  lda #$FF                        ; no keyboard column driven, or
        sta cia1PortA                   ; space (column 7, row 4) would
        lda cia1PortB                   ; read as the button (bit 4)
        ldx #PORT1_POTS
        stx cia1PortA
        and #$10
        beq @same
        lda #$80
@same:  cmp mouseData
        beq @end
        sta mouseData
        lda pressFlag
        ora #MOUSE_BIT
        sta pressFlag
@end:   rts

; A = new pot value, Y = previous value. Returns A/X = signed movement
; (low/high), Y = the new value.
Delta:  sty dOld
        sta dNew
        sec
        sbc dOld
        and #$7F
        cmp #$40
        bcs @neg
        lsr
        beq @zero
        ldx #0
        ldy dNew
        rts
@neg:   ora #$C0
        cmp #$FF
        beq @zero
        sec
        ror
        ldx #$FF
        ldy dNew
        rts
@zero:  lda #0
        tax
        ldy dNew
        rts
