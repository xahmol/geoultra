; Input driver for the Commodore 1351 mouse in proportional mode,
; control port 1, at MOUSE_BASE ($FE80). Moves the pointer freely; the
; kernal keeps it within the mouse limits (CheckMousePos).
;
; The movement calculation follows the algorithm published in the
; Commodore 1351 Mouse User's Manual (pot value difference over 7 bits,
; bit 0 noise discarded). Adapted: own code, GEOS variables and limits.
;
; The left button is GEOS's (mouseData, pressFlag). The right button
; (the 1351's "up" line, port bit 0) goes only to GeoUltra's guMouse2
; ($C0E6, info.s): GEOS applications see nothing new; GeoUltra's desktop
; reads it (its context menu).

        .include "geos.inc"
        .include "hw.inc"

guMouse2        = $C0E6         ; (info.s: GeoUltra's right button)

        .segment "INPUT"

        jmp DrvInit                     ; InitMouse
        jmp DrvSlow                     ; SlowMouse
        jmp DrvUpdate                   ; UpdateMouse

oldX:   .byte 0
oldY:   .byte 0
dOld:   .byte 0
dNew:   .byte 0
moved:  .byte 0
lastBtn:.byte $80                       ; last button state read from the port
lastBtn2:.byte $80                      ; the right button's (bit 7 clear: held)

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
@y:     lda sidPotY
        ldy oldY
        jsr Delta
        sty oldY
        cmp #0
        beq @button
        inc moved
        sta dNew                        ; mouseYPos -= delta (pot Y grows
        lda mouseYPos                   ; upwards); the kernal clamps
        sec
        sbc dNew
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
        pha
        jsr Right                       ; (bit 0: the right button)
        pla
        and #$10
        beq @same
        lda #$80
@same:  cmp lastBtn                     ; only a change of the port counts, so
        beq @end                        ; mouseData set by software stays
        sta lastBtn
        sta mouseData
        lda pressFlag
        ora #MOUSE_BIT
        sta pressFlag
@end:   rts

; Right: the port's bit 0 (A, low: the right button held) into
; guMouse2: bit 7 its state; at a press bit 6 set as well (cleared by
; the reader, so a click between two reads is not lost). Destroys A.
Right:  and #$01
        beq :+
        lda #$80
:       cmp lastBtn2
        beq @end
        sta lastBtn2
        cmp #0
        bne @up
        lda guMouse2                    ; pressed: held, and a press seen
        and #$7F
        ora #$40
        sta guMouse2
        rts
@up:    lda guMouse2                    ; released
        ora #$80
        sta guMouse2
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
