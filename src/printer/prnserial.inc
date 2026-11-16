; prnserial.inc: the serial part of GeoUltra's printer drivers
; (src/printer/epson.s, mps.s; docs/DESIGN.md "Printing"), included in
; their CODE: device 4 through the C64 Kernal ROM's serial routines
; (LISTEN, SECOND, CIOUT, UNLSN) between InitForIO and DoneWithIO. The
; ROM's serial zero page ($90, $94, $95, $A3-$A5, in an application's
; part) and $02A1 (the ROM's RS-232 flags: its LISTEN waits until they
; are 0, and under GEOS they hold whatever was there) are put back after
; each call: the spooler plays a queue while any application runs.
; The includer defines PRN_SA (SECOND's channel, $60 + n) and wb (a
; zero-page word: Work sets it from r1). Own code, 2026-11-16.

InitForIO       = $C25C
DoneWithIO      = $C25F

; C64 Kernal ROM (mapped by InitForIO)
LISTEN          = $FFB1
SECOND          = $FF93
CIOUT           = $FFA8
UNLSN           = $FFAE
STATUS          = $90
C3PO            = $94           ; bit 7: a byte buffered for the bus ($95)
EOI             = $A3           ; the ROM's end-of-data flag
ENABL           = $02A1         ; RS-232 busy flags: LISTEN waits for 0

PRN_DEV         = 4

; Open: the serial routines and device 4 listening on PRN_SA's channel. Carry
; set and X = DEV_NOT_FOUND when it does not answer (closed again), else
; carry clear, X 0.
Open:   ldx #ZP_N - 1           ; the ROM's zero page kept
:       lda ZpAt,x
        tay
        lda 0,y
        sta zpSave,x
        dex
        bpl :-
        lda ENABL
        sta enabl
        jsr InitForIO
        lda #0
        sta ENABL               ; (no RS-232 under GEOS: else LISTEN hangs)
        sta STATUS
        sta C3PO                ; no byte buffered: the program's own value
        sta EOI                 ; there would be sent first (bit 7), and
                                ; with no printer the ROM's error path
                                ; then returned to nowhere
        lda #PRN_DEV
        jsr LISTEN
        lda #PRN_SA
        jsr SECOND
        lda STATUS
        bmi Fail
        ldx #0
        clc
        rts
Fail:   jsr UNLSN
        jsr Done
        ldx #DEV_NOT_FOUND
        sec
        rts

; Close: UNLSN, the serial routines left, the ROM's zero page back; X 0,
; carry clear.
Close:  jsr UNLSN
Done:   jsr DoneWithIO
        lda enabl
        sta ENABL
        ldx #ZP_N - 1
:       lda ZpAt,x
        tay
        lda zpSave,x
        sta 0,y
        dex
        bpl :-
        ldx #0
        clc
        rts

ZpAt:   .byte STATUS, C3PO, $95, EOI, $A4, $A5
ZP_N    = * - ZpAt

; Put: A to the printer (CIOUT). A, X and Y kept.
Put:    sty putY
        stx putX
        sta putA
        jsr CIOUT
        ldy putY
        ldx putX
        lda putA
        rts

; Work: wb from r1.
Work:   lda r1L
        sta wb
        lda r1H
        sta wb+1
        rts

        .pushseg
        .segment "BSS"
zpSave: .res ZP_N
enabl:  .res 1
putA:   .res 1
putX:   .res 1
putY:   .res 1
        .popseg
