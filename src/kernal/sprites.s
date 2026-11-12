; Sprites: DrawSprite, PosSprite, EnablSprite, DisablSprite. Written from
; the HG2G2022 descriptions; sprite pictures at SPRITE_PICS ($8A00, 64
; bytes per sprite, sprite 0 = mouse pointer).

        .include "geos.inc"
        .include "hw.inc"

        .export DrawSprite, PosSprite, EnablSprite, DisablSprite
        .import PtrDX, PtrDY

        .segment "DATA"

savePort:       .byte 0

        .segment "RODATA"

bit8:   .byte $01, $02, $04, $08, $10, $20, $40, $80

        .segment "CODE"

; DrawSprite: r3L = sprite, r4 = 64 bytes of picture. Destroys A, Y, r5.
; A picture for sprite 0, the pointer, is the caller's own: its hot spot
; top left, as GEOS 2.0 places it (PosPointer's offsets put back; a
; pointer design's hot spot, pointer.s, no longer applies).
DrawSprite:
        lda r3L
        bne :+
        lda #24
        sta PtrDX
        lda #50
        sta PtrDY
:       lda r3L                 ; r5 = SPRITE_PICS + sprite * 64
        lsr
        lsr
        sta r5H
        lda r3L
        asl
        asl
        asl
        asl
        asl
        asl
        sta r5L
        clc
        lda r5H
        adc #>SPRITE_PICS
        sta r5H
        ldy #63
@copy:  lda (r4),y
        sta (r5),y
        dey
        bpl @copy
        rts

; PosSprite: r3L = sprite, r4 = x, r5L = y (GEOS coordinates).
; Destroys A, X, Y, r6.
PosSprite:
        php
        sei
        jsr IoOn
        lda r3L
        asl
        tay                     ; Y = register offset
        clc
        lda r4L
        adc #24
        sta r6L
        lda r4H
        adc #0
        sta r6H
        lda r6L
        sta vicSpr0X,y
        lda r5L
        clc
        adc #50
        sta vicSpr0Y,y
        ldx r3L
        lda vicSprXMsb
        ora bit8,x
        ldy r6H
        bne @msb
        eor bit8,x
@msb:   sta vicSprXMsb
        jsr IoOff
        plp
        rts

; EnablSprite / DisablSprite: r3L = sprite. Destroy A, X.
EnablSprite:
        php
        sei
        jsr IoOn
        ldx r3L
        lda vicSprEnable
        ora bit8,x
        jmp SetEnable
DisablSprite:
        php
        sei
        jsr IoOn
        ldx r3L
        lda bit8,x
        eor #$FF
        and vicSprEnable
SetEnable:
        sta vicSprEnable
        jsr IoOff
        plp
        rts

IoOn:   lda CPU_PORT
        sta savePort
        lda #RAM_IO
        sta CPU_PORT
        rts
IoOff:  lda savePort
        sta CPU_PORT
        rts
