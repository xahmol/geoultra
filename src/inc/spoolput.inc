; The print spooler's writing (spool.s, module 108): with spoolring.inc.

; PutType: A = a record's type into the queue.
PutType:
        sta type
        lda #<type
        ldx #>type
        jsr From
        lda #1
        ldx #0

; Put: A/X bytes from src into the queue at its head. No room: nothing.
Put:    sta len
        stx len+1
        jsr Room
        bcs @no
        ldx #Q_HEAD
        ldy #REU_STASH
        jmp Xfer
@no:    rts

; Room: C clear when len bytes (and a page to spare) fit: the ring's
; pages R = banks * 256 - RING0, the used ones (head - tail) mod R.
Room:   jsr Banks
        sta rsize+1
        lda #0
        sec
        sbc #RING0
        sta rsize
        bcs :+
        dec rsize+1
:       sec                     ; used = head - tail (in pages)
        lda hdr + Q_HEAD + 1
        sbc hdr + Q_TAIL + 1
        sta m
        lda hdr + Q_HEAD + 2
        sbc hdr + Q_TAIL + 2
        sta m+1
        bcs :+
        clc                     ; (round again: + R)
        lda m
        adc rsize
        sta m
        lda m+1
        adc rsize+1
        sta m+1
:       clc                     ; + len's pages + 2
        lda m
        adc len+1
        sta m
        bcc :+
        inc m+1
:       clc
        lda m
        adc #2
        sta m
        bcc :+
        inc m+1
:       lda m                   ; C set: not below R
        cmp rsize
        lda m+1
        sbc rsize+1
        rts
