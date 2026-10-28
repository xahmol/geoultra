; Kernal data: the 32 system fill patterns, the mouse pointer and the
; hardware vectors. Patterns and pointer are GeoUltra's own designs.

        .export patterns, pointerPic
        .import IrqEntry, NmiEntry, ColdStart

        .segment "RODATA"

patterns:
        .byte $00, $00, $00, $00, $00, $00, $00, $00  ;  0 white
        .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF  ;  1 black
        .byte $AA, $55, $AA, $55, $AA, $55, $AA, $55  ;  2 50% grey (desktop)
        .byte $88, $00, $22, $00, $88, $00, $22, $00  ;  3 light dots
        .byte $77, $FF, $DD, $FF, $77, $FF, $DD, $FF  ;  4 dark dots
        .byte $FF, $00, $FF, $00, $FF, $00, $FF, $00  ;  5 horizontal lines
        .byte $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA  ;  6 vertical lines
        .byte $01, $02, $04, $08, $10, $20, $40, $80  ;  7 diagonal /
        .byte $80, $40, $20, $10, $08, $04, $02, $01  ;  8 diagonal \
        .byte $FF, $80, $80, $80, $FF, $08, $08, $08  ;  9 bricks
        .byte $FF, $80, $80, $80, $80, $80, $80, $80  ; 10 grid
        .byte $81, $42, $24, $18, $18, $24, $42, $81  ; 11 cross-hatch
        .byte $CC, $CC, $33, $33, $CC, $CC, $33, $33  ; 12 coarse checks
        .byte $F0, $F0, $F0, $F0, $0F, $0F, $0F, $0F  ; 13 big checks
        .byte $11, $00, $44, $00, $11, $00, $44, $00  ; 14 sparse dots
        .byte $EE, $FF, $BB, $FF, $EE, $FF, $BB, $FF  ; 15 dense
        .byte $FF, $FF, $00, $00, $FF, $FF, $00, $00  ; 16 wide horizontal
        .byte $CC, $CC, $CC, $CC, $CC, $CC, $CC, $CC  ; 17 wide vertical
        .byte $03, $06, $0C, $18, $30, $60, $C0, $81  ; 18 thick /
        .byte $C0, $60, $30, $18, $0C, $06, $03, $81  ; 19 thick \
        .byte $18, $3C, $7E, $FF, $7E, $3C, $18, $00  ; 20 diamonds
        .byte $00, $66, $66, $00, $00, $66, $66, $00  ; 21 squares
        .byte $10, $10, $10, $FF, $10, $10, $10, $10  ; 22 plus grid
        .byte $80, $00, $00, $00, $00, $00, $00, $00  ; 23 very light
        .byte $55, $FF, $55, $FF, $55, $FF, $55, $FF  ; 24 75% grey
        .byte $00, $55, $00, $55, $00, $55, $00, $55  ; 25 25% grey
        .byte $3C, $42, $81, $81, $81, $81, $42, $3C  ; 26 circles
        .byte $E0, $C1, $83, $07, $0E, $1C, $38, $70  ; 27 slant
        .byte $FF, $81, $BD, $A5, $A5, $BD, $81, $FF  ; 28 frames
        .byte $08, $1C, $3E, $7F, $00, $00, $00, $00  ; 29 waves
        .byte $AA, $00, $AA, $00, $AA, $00, $AA, $00  ; 30 fine dots
        .byte $FF, $AA, $FF, $AA, $FF, $AA, $FF, $AA  ; 31 dark lines

; Mouse pointer: an arrow, hot spot top left (sprite, 24 x 21).
pointerPic:
        .byte %11000000, 0, 0
        .byte %11100000, 0, 0
        .byte %11110000, 0, 0
        .byte %11111000, 0, 0
        .byte %11111100, 0, 0
        .byte %11111110, 0, 0
        .byte %11111000, 0, 0
        .byte %11011000, 0, 0
        .byte %10001100, 0, 0
        .byte %00001100, 0, 0
        .byte %00000110, 0, 0
        .byte %00000110, 0, 0
        .res 9 * 3, 0
        .byte 0

        .segment "VECTORS"

        .word NmiEntry, ColdStart, IrqEntry
