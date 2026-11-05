; File engine: an Ultimate stream's path in the REU (enginestreamu.s),
; for modules 61 and 62. Assembled into each module that needs it, after
; fereu.inc.

; PathOp: Y = REU_STASH or REU_FETCH: fePath (a page) <-> handle
; feHandle's page at FE_UPATHS. Destroys A, X, r0-r3L.
PathOp: lda #<fePath
        sta r0L
        lda #>fePath
        sta r0H
        lda #<FE_UPATHS
        sta r1L
        lda feHandle
        clc
        adc #>FE_UPATHS
        sta r1H
        lda #0
        sta r2L
        lda #1
        sta r2H
        jmp ReuOp
        .assert <FE_UPATHS = 0 && <fePath = 0, error, "PathOp: whole pages"
