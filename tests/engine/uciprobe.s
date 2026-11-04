; UCI probe for the U64 tests of tests/engine (feu64.py, U64.uci): one
; command from cmdBuf (cmdLen bytes) through uci.inc; its data (all
; packets, "data more" acknowledged) to DATA, at most up to DATA_END;
; the status to statBuf; then the done flag. Run by MainLoop through
; appMain (switched off first). Own code.

        .include "geos.inc"

APP_MAIN        = $849B
DATA            = $5600
DATA_END        = $5E00
UCI_STAT_MAX    = 63

        .segment "CODE"

Probe:  lda #0
        sta APP_MAIN
        sta APP_MAIN+1
        php                     ; I/O on (MainLoop runs appMain with $01 =
        sei                     ; $30)
        lda $01
        pha
        lda #$35
        sta $01
        lda #<DATA
        sta r0L
        lda #>DATA
        sta r0H
        lda #<DATA_END
        sta dataEnd
        lda #>DATA_END
        sta dataEnd+1
        jsr UciSend
@packet:
        jsr UciData
        inc packets
        lda uciCtrl             ; "data more": the next packet after an ack
        and #$30
        cmp #$30
        bne @last
        jsr UciAccept
        jmp @packet
@last:  jsr UciStatus
        jsr UciAccept
        lda r0L
        sta dataLen
        lda r0H
        sta dataLen+1
        pla
        sta $01
        plp
        lda #1
        sta done
        rts

        .include "uci.inc"
        .assert * - Probe <= $0200, error, "uciprobe: the code reaches cmdBuf"

; Fixed places for feu64.py (the code is at $5300, below $5500)
cmdBuf          = $5500         ; $80 bytes
cmdLen          = $5580
dataEnd         = $5581         ; (a word)
dataLen         = $5583         ; r0 after the data (a word)
packets         = $5585
done            = $5586
statBuf         = $55C0         ; UCI_STAT_MAX + 1 bytes
