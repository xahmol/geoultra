; File engine: a free handle, for the functions that open one (FE_OPENDIR,
; FE_OPEN). Assembled into each module that needs it, after fereu.inc.

; NewHandle: feHandle = a free handle (C clear), else C set and X =
; FE_NO_HANDLE.
NewHandle:
        lda #0
        sta feHandle
@try:   jsr HandleRegs
        lda #1                  ; (its type byte only)
        sta r2L
        ldy #REU_FETCH
        jsr ReuOp
        lda feH + H_TYPE
        beq @got
        inc feHandle
        lda feHandle
        cmp #FE_HANDLES_N
        bne @try
        ldx #FE_NO_HANDLE
        sec
        rts
@got:   clc
        rts

