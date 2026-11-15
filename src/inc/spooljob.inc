; The print spooler's job table (spool.s), in the modules that read or
; write it: JOB_MAX entries of J_LEN bytes at JOBTAB in REU bank 1, job
; n's at entry n mod JOB_MAX.

; JobGet / JobPut: job A's entry <-> jbuf. Destroys A, Y, r0-r3L.
JobGet: ldy #REU_FETCH
        .byte $2C
JobPut: ldy #REU_STASH
        and #JOB_MAX - 1
        asl a
        asl a
        asl a
        asl a
        sta r1L
        lda #>JOBTAB
        sta r1H
        lda #<jbuf
        sta r0L
        lda #>jbuf
        sta r0H
        lda #J_LEN
        sta r2L
        lda #0
        sta r2H
        lda #SYS_BANK
        sta r3L
        jmp SysRAMOp
        .assert <JOBTAB = 0 && J_LEN * JOB_MAX = 256, error, "JobGet: a page, 16 of 16"
