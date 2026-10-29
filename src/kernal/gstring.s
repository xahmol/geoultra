; GraphicsString and i_GraphicsString. Written from the HG2G2022
; description of the commands; details (sorted rectangle corners with the
; new point as pen, LINETO drawing set, the y delta using only its low
; byte) follow the reassembled GEOS 2.0 kernal, mist64/geos
; kernal/graph/graphicsstring.s and graph2l1.s, read as behaviour
; reference only. Own code; checked with tests/conformance/gstring.py.

        .include "geos.inc"

        .export GraphicsString, i_GraphicsString
        .import DrawLine, Rectangle, FrameRectangle, SetPattern, PutString
        .import OvlCall

MOVEPENTO       = 1
LINETO          = 2
RECTANGLETO     = 3
NEWPATTERN      = 5
ESC_PUTSTRING   = 6
FRAME_RECTO     = 7
PEN_X_DELTA     = 8
PEN_Y_DELTA     = 9
PEN_XY_DELTA    = 10

        .segment "DATA"

penX:   .res 2
penY:   .res 1
newX:   .res 2
newY:   .res 1

        .segment "CODE"                 ; (not under I/O: GEOS 2.0 allows it with I/O on)

; GraphicsString: r0 = commands, ended by NULL. Destroys A, X, Y, r0-r13.
; The interpreter is overlay module 5.
GraphicsString:
        jsr OvlCall
        .byte 5, 0

; i_GraphicsString: the commands follow the jsr; returns after the NULL.
i_GraphicsString:
        pla
        sta r0L
        pla
        sta r0H
        inc r0L
        bne @run
        inc r0H
@run:   jsr GraphicsString
        lda r0L                 ; r0 is past the NULL: return there
        bne @dec
        dec r0H
@dec:   dec r0L
        lda r0H
        pha
        lda r0L
        pha
        rts

        .segment "OVL5"

        jmp Interpret           ; entry 0

cmdLo:  .byte <MovePenTo, <LineTo, <RectangleTo, <Nothing, <NewPattern
        .byte <EscPutString, <FrameRecTo, <PenXDelta, <PenYDelta, <PenXYDelta
cmdHi:  .byte >MovePenTo, >LineTo, >RectangleTo, >Nothing, >NewPattern
        .byte >EscPutString, >FrameRecTo, >PenXDelta, >PenYDelta, >PenXYDelta

Interpret:
@loop:  jsr NextByte
        beq @end
        cmp #PEN_XY_DELTA + 1
        bcs @end                ; unknown command: stop
        tax
        lda cmdLo-1,x
        sta @call+1
        lda cmdHi-1,x
        sta @call+2
@call:  jsr $FFFF
        jmp @loop
@end:   rts

; A = (r0), r0 += 1 (flags from A)
NextByte:
        ldy #0
        lda (r0),y
        inc r0L
        bne @end
        inc r0H
@end:   cmp #0
        rts

; newX/newY = the next .word x, .byte y
GetPoint:
        jsr NextByte
        sta newX
        jsr NextByte
        sta newX+1
        jsr NextByte
        sta newY
        rts

; The point becomes the pen.
SetPen: lda newX
        sta penX
        lda newX+1
        sta penX+1
        lda newY
        sta penY
Nothing:
        rts

MovePenTo:
        jsr GetPoint
        jmp SetPen

; LINETO: a solid line from the pen to the point.
LineTo: jsr GetPoint
        lda penX
        sta r3L
        lda penX+1
        sta r3H
        lda penY
        sta r11L
        lda newX
        sta r4L
        lda newX+1
        sta r4H
        lda newY
        sta r11H
        jsr SetPen
        lda r0L                 ; DrawLine destroys r3-r13 only
        pha
        lda r0H
        pha
        sec
        lda #0
        jsr DrawLine
        pla
        sta r0H
        pla
        sta r0L
        rts

; r2-r4 = the rectangle between the pen and the point, sorted; the point
; becomes the pen.
Corners:
        jsr GetPoint
        lda newY
        cmp penY
        bcs @down
        sta r2L
        lda penY
        sta r2H
        jmp @x
@down:  sta r2H
        lda penY
        sta r2L
@x:     lda newX+1
        cmp penX+1
        bne @cmp
        lda newX
        cmp penX
@cmp:   bcs @right
        lda newX
        sta r3L
        lda newX+1
        sta r3H
        lda penX
        sta r4L
        lda penX+1
        sta r4H
        jmp SetPen
@right: lda penX
        sta r3L
        lda penX+1
        sta r3H
        lda newX
        sta r4L
        lda newX+1
        sta r4H
        jmp SetPen

RectangleTo:
        jsr Corners
        jmp Rectangle

FrameRecTo:
        jsr Corners
        lda #$FF
        jmp FrameRectangle

NewPattern:
        jsr NextByte
        jmp SetPattern

; ESC_PUTSTRING: .word x, .byte y, then text up to the NULL that also ends
; the graphics string.
EscPutString:
        jsr NextByte
        sta r11L
        jsr NextByte
        sta r11H
        jsr NextByte
        sta r1H
        jsr PutString           ; r0 at the NULL: past it, as after a
        inc r0L                 ; NULL command
        bne @end
        inc r0H
@end:   pla                     ; the string's NULL ends GraphicsString
        pla
        rts

; Pen deltas: signed words; for y only the low byte counts.
PenXYDelta:
        jsr PenXDelta
PenYDelta:
        jsr NextByte
        clc
        adc penY
        sta penY
        jmp NextByte
PenXDelta:
        jsr NextByte            ; both bytes first: NextByte sets the carry
        pha
        jsr NextByte
        tax
        pla
        clc
        adc penX
        sta penX
        txa
        adc penX+1
        sta penX+1
        rts
