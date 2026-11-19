; GeoUltra's video autopilot (docs/design/DESIGN.md, Beta 1: the first-look
; video; the user, 2026-11-13). A small routine on GEOS's intBotVector
; that moves the mouse pointer smoothly and presses and releases its
; button, one command at a time, so that a recording needs no memory
; reads (which disturb the VIC stream) and only one short write per
; command. Loaded at $0334 (the cassette buffer: unused by GEOS and
; GeoUltra) by tools/dev/video/pilot.py, which also installs it. Own code.
;
; Command block (CMD): seq, op, x lo, x hi, y, speed. A new seq starts the
; command; op 1 glide to x/y (each frame 1/2^speed of the distance left,
; at least a pixel: quick at first, gentle at the end), 2 press, 3
; release. done = seq when the command has finished.

mouseXPos       = $3A
mouseYPos       = $3C
pressFlag       = $39
mouseData       = $8505
intBotVector    = $849F
MOUSE_BIT       = $20

CMD             = $03FA         ; the command block (pilot.py writes it)
seq             = CMD
op              = CMD + 1
tx              = CMD + 2
ty              = CMD + 4
speed           = CMD + 5

        .org $0334

; (pilot.py installs it: Chain's address the old intBotVector, then
; intBotVector = Tick; both written while GEOS runs, the vector last.)

Tick:   lda seq
        cmp done
        beq Chain
        lda op
        cmp #1
        beq Glide
        ldx #$80                ; 3: release
        cmp #2
        bne :+
        ldx #0                  ; 2: press
:       stx mouseData
        lda pressFlag
        ora #MOUSE_BIT
        sta pressFlag
Finish: lda seq
        sta done
Chain:  jmp $FFFF               ; (the vector before: pilot.py)

Glide:  lda tx                  ; dx = tx - x (16 bits)
        sec
        sbc mouseXPos
        sta dl
        lda tx + 1
        sbc mouseXPos + 1
        sta dh
        jsr Step                ; d = a part of it, at least 1 (0 stays)
        lda mouseXPos
        clc
        adc dl
        sta mouseXPos
        lda mouseXPos + 1
        adc dh
        sta mouseXPos + 1
        lda ty                  ; dy, the same
        sec
        sbc mouseYPos
        sta dl
        lda #0
        sbc #0
        sta dh
        jsr Step
        lda mouseYPos
        clc
        adc dl
        sta mouseYPos
        lda mouseXPos           ; there: done
        cmp tx
        bne Chain
        lda mouseXPos + 1
        cmp tx + 1
        bne Chain
        lda mouseYPos
        cmp ty
        bne Chain
        beq Finish

; Step: d (dl, dh signed) = d >> speed (arithmetic), at least +-1 while
; d is not 0.
Step:   lda dl
        ora dh
        beq @end
        lda dh
        sta sg
        ldx speed
@sh:    lda dh
        cmp #$80                ; (arithmetic: the sign in again)
        ror dh
        ror dl
        dex
        bne @sh
        lda dl
        ora dh
        bne @end
        lda #1                  ; (a part of 0: one pixel its way)
        sta dl
        lda sg
        bpl @end
        lda #$FF
        sta dl
        sta dh
@end:   rts

dl:     .byte 0
dh:     .byte 0
sg:     .byte 0
done:   .byte 0

End:
