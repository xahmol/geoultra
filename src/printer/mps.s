; GU Commodore MPS: GeoUltra's printer driver for Commodore MPS-801/803
; compatible printers and for the Ultimate's virtual printer in its
; Commodore MPS emulation, the firmware's default (docs/design/DESIGN.md
; "Printing"). Loaded at PRINTBASE ($7900, up to $7F3F) with the GEOS
; 2.0 printer driver interface (HG2G chapter 11, entries 20-176 to
; 20-183). Own code, written from HG2G's description of 7-bit printers
; (rows carried over from one call to the next) and Commodore's bit image
; mode; the Ultimate's firmware (GideonZ/1541ultimate,
; software/io/printer/mps_printer_cbm.cc) read for what its emulation
; knows: CHR$(8) bit image (a column per byte with bit 7 set, bit 0 the
; top dot, 7 dots, 60 dpi across), CHR$(26) n b (b n times, 0 = 256),
; CR (with LF; in bit image 7/72"), CHR$(15) (bit image off), CHR$(31)
; and CHR$(159) (NLQ on, off), FF.
;
; Graphics: 60 cards across (480 dots in 8"), 7 rows a head pass (72 dpi
; down; as GEOS's Commodore drivers, so a GEOS page is a little wider
; than on an 80 dpi printer). PrintBuffer adds its 8 rows to the rows
; still waiting (W_PEND, per card), prints 7 at a time while 7 wait and
; keeps the rest (at most 6) for the next call; StopPrint prints what is
; left. 88 card rows: 704 rows of 1/72". The Ultimate's default page is
; 60 lines of 36 pixels (10", 720 rows), but its MPS emulation starts a
; new page once the head passes the height less the head's 27 pixels
; (1541ultimate mps_printer.h MPS_PRINTER_MAX_MARGIN_BOTTOM), so 90 rows
; put the last band on a second page (the U64, 2026-11-18).
; ASCII: channel 7 (the lower case set, which the firmware selects at
; each SECOND 7), ASCII as PETSCII; CR (the printer adds LF); SetNLQ
; as NLQ.
;
; Device 4 on channel 7 through prnserial.inc (our own serial bus
; routines, any KERNAL ROM). State between calls in
; the work buffer (r1), its count first: StopPrint's buffer may be only
; 640 bytes (ASCII printing).

        .include "geos.inc"

PRN_SA          = $67           ; SECOND: channel 7 (prnserial.inc)
BIM             = $08           ; bit image on
BIM_REP         = $1A           ; a byte n times
BIM_OFF         = $0F
NLQ_ON          = $1F
NLQ_OFF         = $9F
FF              = $0C
DOTS            = 7             ; dots a pass

CARDS           = 60            ; GetDimensions: 480 dots across
ROWS            = 88            ; card rows: 704 dots down (see above)
COLS            = CARDS * 8
REP_MIN         = 4             ; equal columns sent as CHR$(26) n b

; the work buffer (r1)
W_COUNT         = 0             ; rows waiting (0-6 between calls)
W_PEND          = 1             ; per card 16 bytes: its waiting rows
W_COLS          = W_PEND + CARDS * 16   ; a pass's columns (COLS bytes)
        .assert W_COLS + COLS <= 1920, error, "work buffer"

; zero page: r3-r15 (every entry may destroy them)
dat             = r3            ; the row's cards (r0), the ASCII string
wb              = r4            ; the work buffer (r1)
pend            = r5            ; a card's waiting rows
out             = r6            ; columns
len             = r7            ; a pass's columns up to the last dot
tmp             = r8            ; 7 bytes (r8-r11): a card's rows
run             = r12L          ; equal columns from here
pd              = r13           ; rows being moved to

        .segment "CODE"

        jmp InitForPrint
        jmp StartPrint
        jmp PrintBuffer
        jmp StopPrint
        jmp GetDimensions
        jmp PrintASCII
        jmp StartASCII
        jmp SetNLQ

; GetDimensions: X cards across, Y card rows, A 0 (graphics and text).
; Destroys nothing else.
GetDimensions:
        ldx #CARDS
        ldy #ROWS
        lda #0
Ret:    rts

; InitForPrint: bit image and NLQ off, once per document.
InitForPrint:
        jsr Open
        bcs Ret
        lda #BIM_OFF
        jsr Put
        lda #NLQ_OFF
        jsr Put
        jmp Close

; SetNLQ: NLQ for the ASCII pages that follow.
SetNLQ: jsr Open
        bcs Ret
        lda #NLQ_ON
        jsr Put
        jmp Close

; StartPrint, StartASCII (r1 the work buffer): no rows waiting; X 0, or
; DEV_NOT_FOUND with carry set when device 4 does not answer.
StartPrint:
StartASCII:
        jsr Work
        lda #0
        tay                     ; (W_COUNT)
        sta (wb),y
        jsr Open
        bcs Ret                 ; (no printer: the error, nothing open)
        lda #FF                 ; a clean page first: the Ultimate's
        jsr Put                 ; printer writes nothing for an empty
        jmp Close               ; page, and a page left over from a job
                                ; that never ended (a reset, a power-off)
                                ; comes out on its own instead of under
                                ; this one (1541ultimate mps_printer.cc
                                ; FormFeed; the user's U64, 2026-11-18)

; StopPrint (r1 the work buffer): the rows still waiting printed (paper
; under them), bit image off, FF; X as StartPrint.
StopPrint:
        jsr Work
        jsr Open
        bcs Ret
        ldy #W_COUNT
        lda (wb),y
        beq @ff
        sta count
        jsr Pass                ; (rows past the count are paper)
        lda #0
        ldy #W_COUNT
        sta (wb),y
@ff:    lda #BIM_OFF
        jsr Put
        lda #FF
        jsr Put
        jmp Close

; PrintASCII: the string at r0 up to its zero, as PETSCII (lower case
; set: a-z as $41-$5A, A-Z as $C1-$DA; a few signs PETSCII lacks as
; their nearest); CR as is (the printer adds LF).
PrintASCII:
        jsr Open
        bcs Ret
        lda r0L
        sta dat
        lda r0H
        sta dat+1
@next:  ldy #0
        lda (dat),y
        bne :+
        jmp Close
:       jsr Petscii
        jsr Put
        inc dat
        bne @next
        inc dat+1
        bne @next               ; (always)

; Petscii: A (ASCII) as the printer's lower case set.
Petscii:
        cmp #'a'
        bcc @upper
        cmp #'z' + 1
        bcs @sign
        and #$DF                ; a-z: $41-$5A
        rts
@upper: cmp #'A'
        bcc @rts
        cmp #'Z' + 1
        bcs @sign
        ora #$80                ; A-Z: $C1-$DA
@rts:   rts
@sign:  ldx #SIGNS_N - 1
:       cmp SignIn,x
        beq :+
        dex
        bpl :-
        rts
:       lda SignOut,x
        rts
; ASCII signs the lower case set has not, and what is printed instead
SignIn:  .byte '\', '^', '_', '`', '{', '|', '}', '~'
SignOut: .byte '/', $5E, $A4, $27, '(', '!', ')', '-'
SIGNS_N = * - SignOut

        .include "prnserial.inc"

; ----------------------------------------------------------------------
; PrintBuffer: the first 60 of the 80 cards at r0 (8 rows) after the
; rows waiting; a pass of 7 while 7 wait, the rest kept.
PrintBuffer:
        lda r0L
        sta dat
        lda r0H
        sta dat+1
        jsr Work
        jsr Open
        bcc :+
        rts
:       jsr Pend0               ; append: each card's 8 rows after its
        ldy #W_COUNT            ; waiting ones
        lda (wb),y
        sta count
        lda #CARDS
        sta card
@add:   clc                     ; pd: where its rows go
        lda pend
        adc count
        sta pd
        lda pend+1
        adc #0
        sta pd+1
        ldy #7
:       lda (dat),y
        sta (pd),y
        dey
        bpl :-
        jsr NextCard
        clc
        lda dat
        adc #8
        sta dat
        bcc :+
        inc dat+1
:       dec card
        bne @add
        lda count
        clc
        adc #8
        sta count
@pass:  lda count               ; a pass while 7 rows wait
        cmp #DOTS
        bcc @keep
        jsr Pass
        jsr Shift
        lda count
        sec
        sbc #DOTS
        sta count
        bcs @pass               ; (always)
@keep:  ldy #W_COUNT
        sta (wb),y
        jmp Hold                ; (the printer kept listening: prnserial.inc)

; Shift: each card's waiting rows from 7 on moved to 0 on (count - 7 of
; them, count 7-14).
Shift:  jsr Pend0
        lda #CARDS
        sta card
@card:  clc                     ; pd: the card's row 7
        lda pend
        adc #DOTS
        sta pd
        lda pend+1
        adc #0
        sta pd+1
        lda count
        sec
        sbc #DOTS + 1           ; the last one to move
        bcc @next
        tay
:       lda (pd),y
        sta (pend),y
        dey
        bpl :-
@next:  jsr NextCard
        dec card
        bne @card
        rts

; Pend0: pend at the first card's waiting rows.
Pend0:  clc
        lda wb
        adc #W_PEND
        sta pend
        lda wb+1
        adc #0
        sta pend+1
        rts

; NextCard: pend 16 bytes on.
NextCard:
        clc
        lda pend
        adc #16
        sta pend
        bcc :+
        inc pend+1
:       rts

; Pass: the waiting rows 0-6 of each card as a bit image line (rows at
; or past count are paper), sent up to its last dot: CHR$(8), the
; columns (runs as CHR$(26) n b), CR.
Pass:   jsr Pend0
        clc
        lda wb
        adc #<W_COLS
        sta out
        lda wb+1
        adc #>W_COLS
        sta out+1
        lda #0
        sta card
        sta len
        sta len+1
        sta at                  ; at: the card's first column
        sta at+1
@card:  ldy #DOTS - 1           ; tmp: the card's 7 rows
:       lda #0
        cpy count
        bcs :+
        lda (pend),y
:       sta tmp,y
        dey
        bpl :--
        ldy #0                  ; 8 columns, the leftmost dot first
@col:   ldx #DOTS - 1           ; the last row first: row 0 ends in bit 0
        lda #0
:       asl tmp,x
        rol a
        dex
        bpl :-
        ora #$80
        sta (out),y
        cmp #$80
        beq :+
        tya                     ; a dot: len = this column + 1
        sec
        adc at
        sta len
        lda at+1
        adc #0
        sta len+1
:       iny
        cpy #8
        bne @col
        jsr NextCard
        clc
        lda out
        adc #8
        sta out
        bcc :+
        inc out+1
:       inc card
        clc                     ; at: the next card's first column
        lda at
        adc #8
        sta at
        bcc :+
        inc at+1
:       lda card
        cmp #CARDS
        bne @card
        lda #BIM
        jsr Put
        jsr Send
        lda #CR
        jmp Put

; Send: the columns at W_COLS, len of them; runs of REP_MIN or more
; equal ones (at most 255) as CHR$(26) n b.
Send:   clc
        lda wb
        adc #<W_COLS
        sta out
        lda wb+1
        adc #>W_COLS
        sta out+1
@next:  lda len
        ora len+1
        bne :+
        rts
:       lda #255                ; max: the run's longest
        ldx len+1
        bne :+
        lda len
:       sta max
        ldy #0
        lda (out),y
        sta val
        ldy #1                  ; Y: the run's length
@run:   cpy max
        beq @end
        lda (out),y
        cmp val
        bne @end
        iny
        bne @run                ; (always: max 255)
@end:   sty run
        cpy #REP_MIN
        bcc @one
        lda #BIM_REP
        jsr Put
        lda run
        jsr Put
        lda val
        jsr Put
        jmp @past
@one:   lda val                 ; a column on its own
        jsr Put
        lda #1
        sta run
@past:  clc                     ; out and len past the run
        lda out
        adc run
        sta out
        bcc :+
        inc out+1
:       sec
        lda len
        sbc run
        sta len
        bcs @next
        dec len+1
        jmp @next

; Work: (prnserial.inc)

; ----------------------------------------------------------------------
        .segment "BSS"
count:  .res 1
card:   .res 1
at:     .res 2
max:    .res 1
val:    .res 1
