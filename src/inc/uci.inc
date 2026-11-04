; Ultimate Command Interface: the handshake, in one place for all of
; GeoUltra (the boot's mount.s, the resident write-back helpers of
; writeback.s, the clock of hibernate.s, the file engine). Assembled into
; each place that needs it: the boot code, a resident segment and the
; overlay modules cannot share one copy. The handshake follows the
; ultimate-uci-oscar64 library's corrected uii_sendcommand
; (~/git/ultimate-uci-oscar64, docs/UCILIB_MANUAL.md).
;
; The includer defines, before the include:
;   cmdBuf      the command: the target first, then the command byte
;   cmdLen      its length (1 byte)
;   statBuf     UCI_STAT_MAX + 1 bytes: the status text, zero-ended
;   UCI_STAT_MAX  characters of the status kept (at least 2)
;   dataEnd     UciData: the first address it may not write (a word);
;               0 drops all data
; and has r0 (UciData's buffer).

uciCtrl         = $DF1C         ; write: control; read: status
uciCmd          = $DF1D         ; write: command bytes; read: identity
uciResp         = $DF1E         ; the reply's data
uciStat         = $DF1F         ; the reply's status text

; UciSend: cmdBuf, cmdLen bytes, pushed; back when the Ultimate has taken
; it (and is no longer busy). Destroys A, X, Y.
UciSend:
        ldx #0                  ; a pending abort finishes first
        ldy #0
@abort: lda uciCtrl
        and #$04
        beq @idle
        dex
        bne @abort
        dey
        bne @abort
@idle:  lda uciCtrl             ; idle; an old reply is released
        and #$30
        beq @write
        and #$20
        beq @idle
        lda #$02
        sta uciCtrl
        bne @idle
@write: ldx #0
@byte:  lda cmdBuf,x
        sta uciCmd
        inx
        cpx cmdLen
        bne @byte
        lda #$01                ; push
        sta uciCtrl
        lda uciCtrl
        and #$08
        beq @taken
        lda #$08                ; error: clear it and push again
        sta uciCtrl
        bne @idle
@taken: lda uciCtrl             ; wait until taken and not busy
        and #$01
        bne @taken
        lda uciCtrl
        and #$30
        cmp #$10
        beq @taken
        rts

; UciData: the reply's data bytes to (r0), r0 advanced; bytes at or past
; dataEnd are dropped (the reply is read to its end either way).
; Destroys A, Y.
UciData:
@byte:  bit uciCtrl             ; N: data available
        bpl @end
        lda uciResp
        ldy r0H
        cpy dataEnd+1
        bcc @put
        bne @byte
        ldy r0L
        cpy dataEnd
        bcs @byte
@put:   ldy #0
        sta (r0),y
        inc r0L
        bne @byte
        inc r0H
        bne @byte
@end:   rts

; UciStatus: the status text to statBuf (UCI_STAT_MAX characters kept),
; zero-ended. Z set when it starts with "00". Destroys A, X.
UciStatus:
        ldx #0
@char:  bit uciCtrl             ; V: status available
        bvc @end
        lda uciStat
        cpx #UCI_STAT_MAX
        bcs @char
        sta statBuf,x
        inx
        bne @char
@end:   lda #0
        sta statBuf,x
        lda statBuf
        cmp #'0'
        bne @rts
        lda statBuf+1
        cmp #'0'
@rts:   rts

; UciAccept: the reply released; back when done. Destroys A.
UciAccept:
        lda #$02
        sta uciCtrl
@wait:  lda uciCtrl
        and #$02
        bne @wait
        rts

; UciCommand: the whole exchange: send, the data to (r0) as UciData,
; the status, accept. Z set when the status starts with "00". Destroys
; A, X, Y.
UciCommand:
        jsr UciSend
        jsr UciData
        jsr UciStatus
        php
        jsr UciAccept
        plp
        rts
        .assert UCI_STAT_MAX >= 2, error, "uci.inc: UCI_STAT_MAX below 2"
