; File engine: the progress routine of a copy (FE_COPY's r3), for the
; modules that copy blocks (31, 44, 45). Assembled into each module that
; needs it. Uses cDone.

; Progress: one more block done; the caller's routine (r3, if not 0)
; with r4 = blocks done. C set: stop. X = 0 after it (the routine may
; change X; the callers go on with X as their result). Destroys A, Y.
Progress:
        inc cDone
        bne :+
        inc cDone+1
:       lda argR3+1
        beq @no
        lda cDone
        sta r4L
        lda cDone+1
        sta r4H
        jsr @call
        ldx #0                  ; (C as the routine returned it)
        rts
@call:  jmp (argR3)
@no:    ldx #0
        clc
        rts
