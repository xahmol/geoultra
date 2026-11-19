; prnserial.inc: the serial part of GeoUltra's printer drivers
; (src/printer/epson.s, mps.s; docs/DESIGN.md "Printing"), included in
; their CODE: device 4 on the serial bus with routines of our own, not
; the C64 KERNAL's (the user, 2026-11-16: with the JiffyDOS KERNAL the
; Ultimate's printer does not work even from BASIC; our own routines
; print the same with any KERNAL ROM). Between InitForIO and DoneWithIO
; (I/O mapped, interrupts off, the U64 at 1 MHz).
;
; The standard serial protocol, written from Michael Steil's description
; ("Commodore Peripheral Bus: Part 4: Standard Serial", pagetable.com,
; 2019): no code taken. The controller pulls ATN and CLK, a device
; answers by pulling DATA (within 1 ms: else none is there), then each
; byte: the sender releases CLK (ready to send), waits until the
; receivers release DATA (ready for data), pulls CLK, then 8 bits, the
; first bit first: DATA set (1 = released), CLK released for at least 60
; us (data valid), CLK pulled and DATA released; the receiver pulls DATA
; within 1 ms (byte taken; we allow it about 30 s, see IecSend), at
; least 100 us between bytes. Commands under
; ATN: LISTEN $20 + device, SECOND $60 + channel, CLOSE $E0 + channel,
; UNLISTEN $3F; ATN released after the last. No EOI (a printer needs none). The C64's
; $DD00: bits 3-5 pull ATN, CLK, DATA (1 = pulled, through inverters),
; bits 6-7 read CLK and DATA (1 = released); bits 0-2 (the VIC bank,
; RS-232) are kept.
;
; The includer defines PRN_SA (SECOND's byte, $60 + channel) and wb (a
; zero-page word: Work sets it from r1). Own code, 2026-11-16.

InitForIO       = $C25C
DoneWithIO      = $C25F

IEC             = $DD00
O_ATN           = $08           ; (out: 1 pulls the line)
O_CLK           = $10
O_DATA          = $20
PRN_DEV         = 4
ACK_WAIT        = 43            ; x about 0.7 s: a byte's acknowledgement
SETUP_SPEC      = 3             ; IecDelay counts (5 cycles, about 5 us
SETUP_FAST      = 1             ; each at 1 MHz): see Timing
GAP_SPEC        = 20
GAP_FAST        = 6
LISTEN          = $20 + PRN_DEV
UNLISTEN        = $3F
PRN_CLOSE       = $E0 | (PRN_SA & $0F) ; CLOSE on PRN_SA's channel

; Timing: the bit set-up and the gap between bytes for this call: the
; IEC specification's minimums (set-up 20 us, data valid 20 us, 100 us
; between bytes; Michael Steil, "Commodore Peripheral Bus: Part 4"), or,
; with GeoUltra's guPrnFast ($C0FC bit 7, [print] fastbus=on; the "GU"
; signature at $C0E0 checked, so under GEOS 2.0 always the first), less:
; set-up 5 us, 30 us between bytes, which the Ultimate's printer takes
; (measured on the U64, 2026-11-19: a black page 261 s, fast 210 s; the
; first 302 s with 60 us data valid). Destroys A.
Timing: ldx #GAP_SPEC
        ldy #SETUP_SPEC
        lda $C0E0               ; (no "GU" signature: GEOS 2.0's bytes)
        cmp #'G'
        bne @set
        lda $C0E1
        cmp #'U'
        bne @set
        bit $C0FC
        bpl @set
        ldx #GAP_FAST
        ldy #SETUP_FAST
@set:   stx gapN
        sty setupN
        rts

; Open: device 4 listening on PRN_SA's channel (still, after Hold: no
; ATN). Carry set and X = DEV_NOT_FOUND when it does not answer (the bus
; released again), else carry clear, X 0.
Open:   jsr InitForIO
        jsr Timing
        lda #0
        sta iecErr
        bit listening           ; (kept listening by the last call)
        bmi @on
        lda #LISTEN
        jsr IecCmd
        bcs Fail
        lda #PRN_SA
        jsr IecSend
        lda iecErr
        bne Fail
        jsr IecAtnOff
        lda #$80
        sta listening
@on:    ldx #0
        clc
        rts
Fail:   lda #0
        sta listening
        jsr IecFree
        jsr DoneWithIO
        ldx #DEV_NOT_FOUND
        sec
        rts

; Close: UNLISTEN, then CLOSE on the channel (LISTEN, $E0 + channel,
; UNLISTEN: what BASIC's CLOSE sends), the bus released, the I/O left;
; X 0, carry clear. The CLOSE makes the Ultimate's printer take the
; job's last bytes: in PNG mode its firmware interprets its 256-byte
; buffer only when it is full or at an ATN addressed to the printer
; (1541ultimate software/io/printer/iec_printer.cc: push_ctrl, ATN as
; $FE, _push_command), not at UNLISTEN, so a page's last bytes (its FF)
; waited for the next job, which then printed the previous page (the
; user's U64, 2026-11-16).
Close:  lda #0
        sta listening
        lda #UNLISTEN
        jsr IecCmd
        jsr IecFree
        lda #LISTEN
        jsr IecCmd
        bcs @free               ; (gone meanwhile: nothing more)
        lda #PRN_CLOSE
        jsr IecSend
        lda #UNLISTEN
        jsr IecCmd
@free:  jsr IecFree
        jsr DoneWithIO
        ldx #0
        clc
        rts

; Hold (PrintBuffer's end): the printer kept listening for the next
; call, the I/O left; X 0, carry clear. No ATN between a page's bands:
; the Ultimate's firmware takes about 0.4 s for each Open and Close
; (measured on the U64, 2026-11-18: an empty page 39 s, straight through
; the driver), and it draws its 256-byte buffer whenever it is full;
; StopPrint's Close ends the page (and makes it take the rest). After a
; byte not taken: Close instead (the session ended).
Hold:   lda iecErr
        bne Close
        jsr DoneWithIO
        ldx #0
        clc
        rts

; Put: A to the printer. A, X and Y kept.
Put:    sty putY
        stx putX
        sta putA
        jsr IecSend
        ldy putY
        ldx putX
        lda putA
        rts

; IecCmd: ATN and CLK pulled, DATA released; a device must pull DATA
; within about 1 ms (carry set: none), then byte A sent under ATN.
IecCmd:
        pha
        lda IEC
        and #$FF - O_DATA
        ora #O_ATN | O_CLK
        sta IEC
        ldx #200                ; (11 cycles a pass: about 2 ms)
:       lda IEC
        bpl @there              ; (bit 7 0: DATA pulled)
        dex
        bne :-
        pla
        sec
        rts
@there: ldx #200                ; (about 1 ms: every device sees ATN
        jsr IecDelay            ; before CLK moves, as the KERNAL waits)
        pla
        jsr IecSend
        lda iecErr
        cmp #1                  ; (carry set: the byte was not taken)
        rts

; IecAtnOff: ATN released (CLK stays pulled: we go on sending).
IecAtnOff:
        lda IEC
        and #$FF - O_ATN
        sta IEC
        ldx #4
        jmp IecDelay

; IecFree: ATN, CLK and DATA released.
IecFree:
        lda IEC
        and #$FF - O_ATN - O_CLK - O_DATA
        sta IEC
        rts

; IecSend: byte A (nothing after an error: iecErr). Destroys A, X, Y.
IecSend:
        sta iecByte
        lda iecErr
        bne SendEnd
        lda IEC                 ; ready to send: CLK released
        and #$FF - O_CLK
        sta IEC
:       lda IEC                 ; wait until every listener released DATA
        cmp IEC                 ; (read twice: the line settled)
        bne :-
        asl a
        bcc :-
        lda IEC                 ; CLK pulled: the bits follow
        ora #O_CLK
        sta IEC
        ldy #8
@bit:   lsr iecByte
        lda IEC
        and #$FF - O_DATA       ; 1: DATA released
        bcs :+
        ora #O_DATA             ; 0: DATA pulled
:       sta IEC
        ldx setupN              ; (set up: Timing)
        jsr IecDelay
        lda IEC                 ; CLK released: the bit is valid
        and #$FF - O_CLK
        sta IEC
        ldx #4                  ; (at least 20 us)
        jsr IecDelay
        lda IEC                 ; CLK pulled, DATA released
        ora #O_CLK
        and #$FF - O_DATA
        sta IEC
        dey
        bne @bit
        lda #ACK_WAIT           ; the listener takes it: DATA pulled
        sta iecWait             ; (the protocol: within 1 ms; we wait
        ldy #0                  ; about 30 s: the Ultimate's printer,
        ldx #0                  ; firmware 3.15a, takes a byte only when
:       lda IEC                 ; its emulation has drawn the last 256,
        bpl @took               ; seconds for dense graphics; lost bytes
        dex                     ; would end the page nowhere)
        bne :-
        dey
        bne :-
        dec iecWait
        bne :-
        inc iecErr              ; not taken: nothing more is sent
        rts
@took:  ldx gapN                ; (between bytes: Timing)
IecDelay:                       ; (X x 5 cycles)
        dex
        bne IecDelay
SendEnd:
        rts

listening:      .byte 0         ; $80: the printer listening (Open, Hold;
                                ; in CODE: BSS is not in the file)
setupN:         .byte SETUP_SPEC ; the bit set-up, IecDelay counts (Timing)
gapN:           .byte GAP_SPEC  ; the gap between bytes (Timing)

; Work: wb from r1.
Work:   lda r1L
        sta wb
        lda r1H
        sta wb+1
        rts

        .pushseg
        .segment "BSS"
iecErr: .res 1                  ; nonzero: a byte was not taken
iecByte:.res 1
iecWait:.res 1
putA:   .res 1
putX:   .res 1
putY:   .res 1
        .popseg
