; File engine: into the home folder (GEOULTRA on /USB0, /USB1 or /SD; its
; path in REU bank 1 at HOME_PATH, from the boot), for modules 67, 75
; and 77. Assembled into each module that needs it, after fereu.inc and
; feult.inc. Destroys diskBlkBuf.

HOME_PATH       = $0300

; Home: into the home folder ("/" at its end left off). X = 0 or the
; error.
Home:   lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #<HOME_PATH
        sta r1L
        lda #>HOME_PATH
        sta r1H
        lda #32
        sta r2L
        lda #0
        sta r2H
        ldy #REU_FETCH
        jsr ReuOp
        lda #U_CD
        jsr UBegin
        ldx #0
@ch:    lda diskBlkBuf,x
        beq @cd
        cmp #'/'
        bne :+
        ldy diskBlkBuf+1,x
        beq @cd
:       jsr UPut
        inx
        cpx #32
        bne @ch
@cd:    jsr UNoData
        jmp UExec

