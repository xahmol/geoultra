; A GEOS printer driver for the spooler's tests (tests/spool/sp3.py): it
; prints nothing; each call is logged at LOG (a count, then a type per
; call: 1 InitForPrint, 2 StartPrint, 3 PrintBuffer, 4 StopPrint, 5
; PrintASCII, 6 StartASCII, 7 SetNLQ) and each row's 16-bit sum at SUM.
; $0280-$02EF: memory the spooler does not lend the driver (the
; harness's trampoline is at $0340, its results at $02F0). Own code.

r0              = $02
LOG             = $0280
SUM             = $02C0         ; per row: low, high
ROWS            = $02BF
p               = $FB           ; (zero page the driver may use)

        .segment "CODE"

        jmp Init                ; InitForPrint
        jmp Start               ; StartPrint
        jmp Buffer              ; PrintBuffer
        jmp Stop                ; StopPrint
        jmp Dims                ; GetDimensions
        jmp Ascii               ; PrintASCII
        jmp SAscii              ; StartASCII
        jmp Nlq                 ; SetNLQ

Init:   lda #1
        jmp Log
Start:  lda #2
        jsr Log
        ldx #0
        rts
Stop:   lda #4
        jsr Log
        ldx #0
        rts
Dims:   ldx #80
        ldy #94
        lda #0
        rts
Ascii:  lda #5
        jmp Log
SAscii: lda #6
        jmp Log
Nlq:    lda #7
        jmp Log

; Buffer: logged; the 640 bytes at r0 summed into SUM + 2 * rows.
Buffer: lda #3
        jsr Log
        lda #0
        sta lo
        sta hi
        lda r0
        sta p
        lda r0+1
        sta p+1
        ldx #2                  ; two whole pages
        ldy #0
@b:     lda (p),y
        jsr Add
        iny
        bne @b
        inc p+1
        dex
        bne @b
@c:     lda (p),y               ; and 128 bytes: 640
        jsr Add
        iny
        bpl @c
        lda ROWS
        asl a
        tax
        lda lo
        sta SUM,x
        lda hi
        sta SUM+1,x
        inc ROWS
        rts

Add:    clc
        adc lo
        sta lo
        bcc :+
        inc hi
:       rts

Log:    ldx LOG
        sta LOG+1,x
        inc LOG
        rts

lo:     .byte 0
hi:     .byte 0
