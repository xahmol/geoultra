; File engine: its work area kept in the REU while the write-back runs
; (it uses the same overlay scratch), for modules 66 (FE_UMOUNT) and 75
; (FE_REBOOT). Assembled into each module that needs it, after
; fereu.inc.

; WorkOp: Y = REU_STASH or REU_FETCH: the work area <-> FE_WSAVE.
WorkOp: lda #<FE_WORK
        sta r0L
        lda #>FE_WORK
        sta r0H
        lda #<FE_WSAVE
        sta r1L
        lda #>FE_WSAVE
        sta r1H
        lda #FE_WORK_LEN
        sta r2L
        lda #0
        sta r2H
        jmp ReuOp
