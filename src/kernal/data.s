; Kernal data: the 32 system fill patterns, the mouse pointer and the
; hardware vectors. Patterns and pointer are GeoUltra's own designs.

        .export patterns, pointerPic
        .import IrqEntry, NmiEntry, ColdStart

        .segment "IODATA"       ; under I/O, as GEOS 2.0's (at $D010)

patterns:
        ; GeoUltra's own designs; at each number the same kind of pattern
        ; as GEOS 2.0's (docs/design/DESIGN.md, "System patterns"), so that
        ; applications' title bars, scroll areas and fills look as meant.
        .byte $00, $00, $00, $00, $00, $00, $00, $00  ;  0 white
        .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF  ;  1 black
        .byte $AA, $55, $AA, $55, $AA, $55, $AA, $55  ;  2 50% grey (desktop)
        .byte $88, $00, $22, $00, $88, $00, $22, $00  ;  3 light dots
        .byte $77, $FF, $DD, $FF, $77, $FF, $DD, $FF  ;  4 dark, light dots
        .byte $44, $11, $44, $11, $44, $11, $44, $11  ;  5 dot grid
        .byte $BB, $EE, $BB, $EE, $BB, $EE, $BB, $EE  ;  6 dark dot grid
        .byte $80, $00, $08, $00, $80, $00, $08, $00  ;  7 sparse dots
        .byte $7F, $FF, $F7, $FF, $7F, $FF, $F7, $FF  ;  8 dark, sparse dots
        .byte $FF, $00, $FF, $00, $FF, $00, $FF, $00  ;  9 horizontal lines
        .byte $AA, $AA, $AA, $AA, $AA, $AA, $AA, $AA  ; 10 vertical lines
        .byte $02, $04, $08, $10, $20, $40, $80, $01  ; 11 diagonal /
        .byte $40, $20, $10, $08, $04, $02, $01, $80  ; 12 diagonal \
        .byte $FD, $FB, $F7, $EF, $DF, $BF, $7F, $FE  ; 13 dark, diagonal /
        .byte $BF, $DF, $EF, $F7, $FB, $FD, $FE, $7F  ; 14 dark, diagonal \
        .byte $22, $22, $22, $FF, $22, $22, $22, $FF  ; 15 small grid
        .byte $01, $01, $01, $01, $01, $01, $01, $FF  ; 16 large grid
        .byte $FF, $01, $01, $01, $FF, $10, $10, $10  ; 17 bricks
        .byte $3C, $42, $81, $81, $81, $81, $42, $3C  ; 18 circles (scales)
        .byte $C0, $60, $30, $18, $0C, $06, $03, $81  ; 19 thick diagonal
        .byte $E0, $C1, $83, $07, $0E, $1C, $38, $70  ; 20 slant
        .byte $00, $66, $66, $00, $00, $66, $66, $00  ; 21 small squares
        .byte $10, $10, $10, $FF, $10, $10, $10, $10  ; 22 plus grid
        .byte $08, $1C, $3E, $7F, $00, $00, $00, $00  ; 23 waves
        .byte $FF, $81, $BD, $A5, $A5, $BD, $81, $FF  ; 24 tiles
        .byte $00, $55, $00, $55, $00, $55, $00, $55  ; 25 25% grey
        .byte $03, $06, $0C, $18, $30, $60, $C0, $81  ; 26 thick diagonal /
        .byte $CC, $CC, $33, $33, $CC, $CC, $33, $33  ; 27 coarse checks
        .byte $81, $42, $24, $18, $18, $24, $42, $81  ; 28 crosses
        .byte $F0, $F0, $F0, $F0, $0F, $0F, $0F, $0F  ; 29 big checks
        .byte $FF, $AA, $FF, $AA, $FF, $AA, $FF, $AA  ; 30 bars
        .byte $18, $3C, $7E, $FF, $7E, $3C, $18, $00  ; 31 diamonds

        .segment "RODATA"

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
