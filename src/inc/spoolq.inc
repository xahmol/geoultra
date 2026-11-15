; The print spooler's queue routines (spool.s), assembled into modules
; 107 and 108 (an overlay module cannot call another's code). Their
; state in the overlay scratch (spool.s: SQ_*), which nested module
; calls leave alone.

; From: A/X = where Put takes its bytes from (C64 memory).
From:   sta src
        stx src+1
        rts

; PutType: A = a record's type into the queue.
PutType:
        sta type
        lda #<type
        ldx #>type
        jsr From
        lda #1
        ldx #0
        jmp Put

; Put: A/X bytes from src into the queue at its head (across banks; the
; ring wraps at the spooler's size). No room: nothing (lost).
Put:    sta len
        stx len+1
        jsr Room
        bcs @out
@chunk: lda len
        ora len+1
        bne :+
@out:   rts
:       sec                     ; this bank's room: 65536 - the offset
        lda #0
        sbc hdr + Q_HEAD
        sta n
        lda #0
        sbc hdr + Q_HEAD + 1
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
        lda hdr + Q_HEAD
        sta r1L
        lda hdr + Q_HEAD + 1
        sta r1H
        lda n
        sta r2L
        lda n+1
        sta r2H
        lda hdr + Q_HEAD + 2
        jsr Phys
        sta r3L
        ldy #REU_STASH
        jsr SysRAMOp
        clc                     ; on: src, head (a bank's end: the next
        lda src                 ; bank, the ring's end: bank 0), len
        adc n
        sta src
        lda src+1
        adc n+1
        sta src+1
        clc
        lda hdr + Q_HEAD
        adc n
        sta hdr + Q_HEAD
        lda hdr + Q_HEAD + 1
        adc n+1
        sta hdr + Q_HEAD + 1
        bcc :+
        inc hdr + Q_HEAD + 2
        jsr Banks
        cmp hdr + Q_HEAD + 2
        bne :+
        lda #0
        sta hdr + Q_HEAD + 2
:       sec
        lda len
        sbc n
        sta len
        lda len+1
        sbc n+1
        sta len+1
        jmp @chunk

; Room: C clear when len bytes fit: free = size - used - 1, used = head
; - tail (mod size; sizes in banks, so compared in pages: len rounded up).
Room:   jsr Banks
        sta n                   ; (size in banks)
        sec                     ; used pages: (head - tail) in pages
        lda hdr + Q_HEAD + 1
        sbc hdr + Q_TAIL + 1
        sta m
        lda hdr + Q_HEAD + 2
        sbc hdr + Q_TAIL + 2
        bcs :+
        adc n                   ; (wrapped)
:       sta m+1                 ; m = used pages (bank, page)
        lda len+1               ; needed pages: len / 256 + 2 (a margin)
        clc
        adc #2
        clc
        adc m
        sta m
        lda m+1
        adc #0
        cmp n                   ; within the size (in banks)?
        rts                     ; (C set: no room)

; Banks: A = the spooler's banks (2 + spoolExtra).
Banks:  lda spoolExtra
        clc
        adc #2
        rts

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

; HeadLoad / HeadSave: the header <-> hdr; HeadLoad makes an empty
; queue when its mark is missing (the REU after power-on, or no cold
; start's SpoolInit: VICE).
HeadLoad:
        jsr HeadFetch
        ldx #3
@m:     lda hdr,x
        cmp Mark,x
        bne @new
        dex
        bpl @m
        rts
@new:   ldx #Q_LEN - 1
        lda #0
@z:     sta hdr,x
        dex
        bpl @z
        ldx #3
@k:     lda Mark,x
        sta hdr,x
        dex
        bpl @k
        rts
Mark:   .byte "GUSP"
HeadFetch:
        ldy #REU_FETCH
        .byte $2C
HeadSave:
        ldy #REU_STASH
        lda r0L                 ; (r0 kept)
        pha
        lda r0H
        pha
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
        jsr SysRAMOp
        pla
        sta r0H
        pla
        sta r0L
        rts

