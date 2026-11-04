; File engine: its REU state (engine.inc, "REU bank 1"). Assembled into
; each engine module that needs it: an overlay module cannot call another's
; code. Needs SysRAMOp imported.

; ReuOp: Y = REU_STASH or REU_FETCH; r0 = C64 address, r1 = address in
; bank FE_BANK, r2 = length. Destroys A, X, r3L.
ReuOp:  lda #FE_BANK
        sta r3L
        jmp SysRAMOp

; HandleOp: Y = REU_STASH or REU_FETCH: handle feHandle <-> feH.
; Destroys A, X, r0-r3L.
HandleOp:
        jsr HandleRegs
        jmp ReuOp

; HandleRegs: r0-r2 for handle feHandle <-> feH. Destroys A, X.
HandleRegs:
        lda #<feH
        sta r0L
        lda #>feH
        sta r0H
        lda feHandle            ; FE_HANDLES + feHandle * FE_HSIZE (64;
        ldx #6                  ; four handles fit in one page)
@mul:   asl
        dex
        bne @mul
        sta r1L
        lda #>FE_HANDLES
        sta r1H
        lda #FE_HUSED
        sta r2L
        lda #0
        sta r2H
        rts
        .assert FE_HSIZE = 64 && FE_HANDLES_N <= 4 && <FE_HANDLES = 0, error, "HandleOp: handles of 64 bytes in one page"
