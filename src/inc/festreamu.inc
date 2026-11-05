; File engine: streams on the Ultimate (enginestreamu.s), for FE_READ
; and FE_WRITE (modules 62, 63). Assembled into each module that needs
; it, after fereu.inc and feult.inc; the setup (UStream, OpenAt,
; Close) is module 64's.

; Moved: A bytes (at most 255) done: sPtr and sGot on, sLeft less, the
; stream's place on. A kept.
Moved:  pha
        clc
        adc sPtr
        sta sPtr
        bcc :+
        inc sPtr+1
:       pla
        pha
        clc
        adc sGot
        sta sGot
        bcc :+
        inc sGot+1
:       pla
        pha
        eor #$FF                ; sLeft - A
        sec
        adc sLeft
        sta sLeft
        bcs :+
        dec sLeft+1
:       pla
        pha
        clc
        adc feH + H_UPOS
        sta feH + H_UPOS
        bcc :+
        inc feH + H_UPOS+1
        bne :+
        inc feH + H_UPOS+2
:       pla
        rts

UStream:
        jsr OvlCall             ; (module 64: the handle, its path)
        .byte 64, 0
OpenAt: jsr OvlCall             ; (module 64: its file opened at its place)
        .byte 64, 3
Close:  jsr OvlCall             ; (module 64: its file closed)
        .byte 64, 6

; Keep: the handle back to the REU. X = 0.
Keep:   ldy #REU_STASH
        jsr HandleOp
        ldx #0
        rts

