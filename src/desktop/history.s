; GeoUltra Desktop: the toolbar's history, back and forward (step T2;
; docs/DESKTOP.md "Toolbar and right-click": "back and forward keep a
; short history of the folders visited"). Each folder the list goes to
; (open.s, Into; the first one at the start) is recorded as the current
; place; back and forward go to the one before or after it without
; recording. Going somewhere new after going back drops the places after
; the current one, as a web browser does. The paths themselves live in
; the application's REU (HIST_BANK at HIST_ADDR: HIST_N slots of 256
; bytes, a ring: the oldest is dropped when it is full); here only the
; positions and a check value per slot (the path's length and the sum of
; its bytes, so the same folder twice in a row is recorded once). Core
; code: Into, which calls HistAdd, is also called from overlays. Own
; design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import path, text, Into
        .export HistAdd, HistBack, HistForward

HIST_BANK       = 6             ; (ovl.s: the overlays at $0000-$6FFF)
HIST_ADDR       = $80           ; the slots' first page in the bank
HIST_N          = 16            ; places kept
HIST_MASK       = HIST_N - 1
        .assert HIST_N & HIST_MASK = 0, error, "HIST_N: a power of two"

        .segment "CODE"

; HistAdd (open.s, Into; desktop.s at the start): path recorded as the
; place after the current one (those after it dropped), unless a back
; or forward move is under way or it is the current place already.
; Destroys A, X, Y, r0-r3.
HistAdd:
        lda histMove
        bne @end
        jsr Check               ; (sum, len: path's check value)
        ldx histLen
        beq @first
        lda histPos             ; the same as the current place: nothing
        jsr Phys
        lda sum
        cmp histSum,x
        bne @new
        lda len
        cmp histLenB,x
        beq @end
@new:   ldx histPos             ; after the current place; the rest dropped
        inx
        stx histPos
        inx
        stx histLen
        cpx #HIST_N + 1         ; full: the oldest dropped
        bcc @store
        lda histFirst
        clc
        adc #1
        and #HIST_MASK
        sta histFirst
        dec histPos
        dec histLen
        jmp @store
@first: lda #0
        sta histPos
        sta histFirst
        lda #1
        sta histLen
@store: lda histPos
        jsr Phys                ; X: its slot
        lda sum
        sta histSum,x
        lda len
        sta histLenB,x
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        jsr Regs
        jmp StashRAM
@end:   rts

; HistBack, HistForward (the toolbar's back and forward): the place
; before or after the current one, when there is one, gone to without
; being recorded.
HistBack:
        lda histPos
        beq Stay
        dec histPos
        jmp Go
HistForward:
        ldx histPos
        inx
        cpx histLen
        bcs Stay
        stx histPos
; Go: the current place's path fetched (into text: free between
; actions) and gone to.
Go:     lda histPos
        jsr Phys
        lda #<text
        sta r0L
        lda #>text
        sta r0H
        jsr Regs
        jsr FetchRAM
        inc histMove
        lda #<text
        ldx #>text
        jsr Into
        dec histMove
Stay:   rts

; Phys: X = the slot of place A (histFirst + A, in the ring).
Phys:   clc
        adc histFirst
        and #HIST_MASK
        tax
        rts

; Regs: r1-r3L for slot X (r0 set: the C64 side), 256 bytes.
Regs:   lda #0
        sta r1L
        sta r2L
        txa
        clc
        adc #HIST_ADDR
        sta r1H
        lda #1
        sta r2H
        lda #HIST_BANK
        sta r3L
        rts

; Check: sum = the sum of path's bytes, len = its length (to 255).
Check:  ldy #0
        tya
        clc
@ch:    ldx path,y
        beq @end
        adc path,y
        iny
        bne @ch
@end:   sta sum
        sty len
        rts

        .segment "DATA"         ; (loaded with the desktop: set at each start)

histFirst:      .byte 0         ; the oldest place's slot
histPos:        .byte 0         ; the current place (0 the oldest)
histLen:        .byte 0         ; places kept (0: none yet)
histMove:       .byte 0         ; 1 while back or forward goes somewhere

        .segment "BSS"

histSum:        .res HIST_N     ; per slot: its path's check value
histLenB:       .res HIST_N
sum:            .res 1
len:            .res 1
