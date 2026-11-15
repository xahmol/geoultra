; The print spooler's ring (spool.s), assembled into the modules that
; read or write it (an overlay module cannot call another's code). The
; ring: the spooler's logical banks, from page RING0 of bank 0 (pages
; 0 to RING0 - 1: the playback's state) to the last bank's end, then
; round again. Head and tail are 3-byte offsets in the header (hdr, the
; overlay scratch: spool.s).

; RING0 (spool.s): the ring's first page.

.ifndef RING_HEAD_ONLY          ; (module 107: only the header's routines)
; From: A/X = the C64 address the next Xfer (Put, Get) uses.
From:   sta src
        stx src+1
        rts

; Get: A/X bytes from the tail into src; the tail moves on.
Get:    sta len
        stx len+1
        ldx #Q_TAIL
        ldy #REU_FETCH

; Xfer: len bytes between src and the ring at the pointer hdr + X (the
; head or the tail), Y = the REU command; the pointer moves on (a bank's
; end: the next bank; the last bank's end: page RING0 of bank 0).
Xfer:   stx px
        sty cmd
@chunk: lda len
        ora len+1
        bne :+
        rts
:       ldx px
        sec                     ; this bank's room: 65536 - the offset
        lda #0
        sbc hdr,x
        sta n
        lda #0
        sbc hdr + 1,x
        sta n+1
        ora n                   ; (offset 0: a whole bank, more than any)
        beq @all
        lda n+1                 ; n = min(room, len)
        cmp len+1
        bcc @n
        bne @all
        lda n
        cmp len
        bcc @n
@all:   lda len
        sta n
        lda len+1
        sta n+1
@n:     lda src
        sta r0L
        lda src+1
        sta r0H
        lda hdr,x
        sta r1L
        lda hdr + 1,x
        sta r1H
        lda n
        sta r2L
        lda n+1
        sta r2H
        lda hdr + 2,x
        jsr Phys
        sta r3L
        ldy cmd
        jsr SysRAMOp
        clc
        lda src
        adc n
        sta src
        lda src+1
        adc n+1
        sta src+1
        ldx px
        clc
        lda hdr,x
        adc n
        sta hdr,x
        lda hdr + 1,x
        adc n+1
        sta hdr + 1,x
        bcc :+
        inc hdr + 2,x
        jsr Banks
        cmp hdr + 2,x
        bne :+
        lda #0                  ; (round again)
        sta hdr + 2,x
        lda #RING0
        sta hdr + 1,x
:       sec
        lda len
        sbc n
        sta len
        lda len+1
        sbc n+1
        sta len+1
        jmp @chunk

; Phys: A = a logical bank -> its REU bank.
Phys:   cmp #2
        bcs :+
        adc #SPOOL_BANK
        rts
:       sec
        sbc #2
        clc
        adc spoolBase
        rts
.endif

; Banks: A = the spooler's banks (2 + spoolExtra).
Banks:  lda spoolExtra
        clc
        adc #2
        rts

; HeadLoad / HeadSave: the header <-> hdr; HeadLoad (only where
; RING_LOAD is defined) makes an empty queue when its mark is missing
; (the REU after power-on, or no cold start's SpoolInit: VICE).
.ifdef RING_LOAD
HeadLoad:
        jsr HeadFetch
        ldx #3
@m:     lda hdr,x
        cmp Mark,x
        bne @new
        dex
        bpl @m
        clc
        rts
@new:
.ifdef RING_INIT                ; (else: C set, no queue)
        ldx #Q_LEN - 1
        lda #0
@z:     sta hdr,x
        dex
        bpl @z
        ldx #3
@k:     lda Mark,x
        sta hdr,x
        dex
        bpl @k
        lda #RING0
        sta hdr + Q_HEAD + 1
        sta hdr + Q_TAIL + 1
        clc
.else
        sec
.endif
        rts
Mark:   .byte "GUSP"
HeadFetch:
        ldy #REU_FETCH
        .byte $2C
.endif
HeadSave:
        ldy #REU_STASH
        lda #<hdr
        sta r0L
        lda #>hdr
        sta r0H
        lda #<QHEAD
        sta r1L
        lda #>QHEAD
        sta r1H
        lda #Q_LEN
        sta r2L
        lda #0
        sta r2H
        lda #SYS_BANK
        sta r3L
        jmp SysRAMOp
