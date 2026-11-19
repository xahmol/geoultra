; GU Epson FX-80: GeoUltra's printer driver for Epson FX-80/JX-80
; printers and for the Ultimate's virtual printer in its Epson emulation
; (docs/DESIGN.md "Printing"). Loaded at PRINTBASE ($7900, up to $7F3F)
; with the GEOS 2.0 printer driver interface (HG2G chapter 11 and the
; entries 20-176 to 20-183: InitForPrint, StartPrint, PrintBuffer,
; StopPrint, GetDimensions, PrintASCII, StartASCII, SetNLQ). Own code,
; written from HG2G's description of the interface and Epson's command
; set; the Ultimate's firmware (GideonZ/1541ultimate,
; software/io/printer/mps_printer_epson.cc) read for which commands its
; emulation knows: ESC * 4 (80 dpi), ESC J n (n/216" paper feed), ESC r n
; (ink), ESC E (emphasised), ESC @ (reset), CR, LF (with CR), FF.
;
; Graphics: 80 dpi across (ESC * 4, 640 dots in 8"), exactly 80 dpi down.
; The pins are 1/72" apart and a GEOS row is 1/80", so an 8-row band goes
; out in three head passes (PassA/PassN/PassAdv): row R of the page lands
; at round(R x 2.7)/216", each pass a run of the band's rows on the top
; pins; the cycle repeats every five bands (40 rows = 108/216").
; Colour: PrintBuffer's r2, when not 0, points at 80 colour bytes (a
; card's ink in the high nibble, its paper in the low, the C64's 16
; colours), printed as the inks K, C, M and Y (ESC r; the firmware mixes
; them), some colours dithered (InkLevel); each pass once per ink in use.
; r2 = 0: black only, without colour commands (any FX-80).
; ASCII: the printer's own font; CR as CR LF; SetNLQ as emphasised (the
; FX-80 has no NLQ).
;
; Each call talks to device 4 on channel 0 through prnserial.inc (our
; own serial bus routines, any KERNAL ROM; Open, Put, Close). State between calls
; lives in the work buffer (r1, which HG2G says the application keeps
; intact), at its start: StopPrint's buffer may be only 640 bytes (ASCII
; printing).

        .include "geos.inc"

PRN_SA          = $60           ; SECOND: channel 0 (prnserial.inc)
ESC             = $1B
FF              = $0C

CARDS           = 80            ; GetDimensions: 640 dots across
ROWS            = 94            ; card rows: as GEOS's Epson drivers, so
                                ; documents paginate the same (9.4")
COLS            = CARDS * 8
FEED_MAX        = 200           ; paper feed held back at most (ESC J n)

; the work buffer (r1)
W_PHASE         = 0             ; the band in the five-band cycle (0-4)
W_FEED          = 1             ; paper feed held back (/216")
W_COLS          = 2             ; a pass's columns (COLS bytes)

; zero page: r3-r15 (every entry may destroy them)
dat             = r3            ; the row's 640 bytes (r0)
wb              = r4            ; the work buffer (r1)
colp            = r5            ; the colour bytes (r2), 0: none
out             = r6            ; columns being written
src             = r7            ; the card being read
len             = r8            ; a pass's columns up to the last ink
tmp             = r9            ; 8 bytes (r9-r12): a card's rows

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

; InitForPrint: the printer reset (ESC @), once per document.
InitForPrint:
        jsr Open
        bcs Ret
        lda #ESC
        jsr Put
        lda #'@'
        jsr Put
        jmp Close

; SetNLQ: emphasised printing (ESC E) for the ASCII pages that follow.
SetNLQ: jsr Open
        bcs Ret
        lda #ESC
        jsr Put
        lda #'E'
        jsr Put
        jmp Close

; StartPrint, StartASCII (r1 the work buffer): the band cycle from its
; start; X 0, or DEV_NOT_FOUND with carry set when device 4 does not
; answer.
StartPrint:
StartASCII:
        jsr Work
        lda #0
        ldy #W_PHASE
        sta (wb),y
        ldy #W_FEED
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

; StopPrint (r1 the work buffer): the page ends (FF; the feed held back
; is dropped, FF goes to the next page's top); X as StartPrint.
StopPrint:
        jsr Work
        lda #0
        ldy #W_PHASE
        sta (wb),y
        ldy #W_FEED
        sta (wb),y
        jsr Open
        bcs Ret
        lda #FF
        jsr Put
        jmp Close

; PrintASCII: the string at r0 up to its zero; CR as CR LF.
PrintASCII:
        jsr Open
        bcs Ret
        lda r0L
        sta dat
        lda r0H
        sta dat+1
@next:  ldy #0
        lda (dat),y
        beq Close
        jsr Put
        cmp #CR
        bne :+
        lda #LF
        jsr Put
:       inc dat
        bne @next
        inc dat+1
        bne @next               ; (always)

        .include "prnserial.inc"

; ----------------------------------------------------------------------
; PrintBuffer: the 80 cards at r0 (8 rows), r2 their colours or 0, r1 the
; work buffer. Three passes (the band's phase); in each, every ink in use
; once: its columns built (Build), cut after the last with ink, sent.
PrintBuffer:
        lda r0L
        sta dat
        lda r0H
        sta dat+1
        lda r2L
        sta colp
        lda r2H
        sta colp+1
        jsr Work
        jsr Open
        bcc :+
        rts
:       jsr Inks                ; inkSet: the inks in use
        ldy #W_PHASE
        lda (wb),y
        sta phase
        asl a                   ; the phase's first pass in the tables
        adc phase
        sta pass
        lda #3
        sta passes
@pass:  ldx pass
        lda PassA,x
        sta rowA
        lda PassN,x
        sta rowN
        lda #0
        sta ink
@ink:   ldx ink
        lda InkBit,x
        and inkSet
        beq @noInk
        jsr Build
        jsr Send
@noInk: inc ink
        lda ink
        cmp #4
        bcc @ink
        ldx pass                ; the paper to the next pass (held back)
        ldy #W_FEED
        lda (wb),y
        clc
        adc PassAdv,x
        sta (wb),y
        cmp #FEED_MAX
        bcc :+
        jsr Feed
:       inc pass
        dec passes
        bne @pass
        ldx phase               ; the next band's phase
        inx
        cpx #5
        bcc :+
        ldx #0
:       txa
        ldy #W_PHASE
        sta (wb),y
        lda colp+1              ; colour: black ink again
        beq :+
        lda #ESC
        jsr Put
        lda #'r'
        jsr Put
        lda #0
        jsr Put
:       jmp Hold                ; (the printer kept listening: prnserial.inc)

; Inks: inkSet, the inks (InkBit) any card's ink or paper uses; black
; alone without colours (r2's high byte 0: no colour bytes).
Inks:   lda #1
        ldx colp+1
        beq @set
        lda #0
        ldy #CARDS - 1
@card:  pha
        lda (colp),y
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        pla
        ora InkUse,x
        pha
        lda (colp),y
        and #$0F
        tax
        pla
        ora InkUse,x
        dey
        bpl @card
@set:   sta inkSet
        rts

; Feed: the paper feed held back sent (ESC J n), then none.
Feed:   ldy #W_FEED
        lda (wb),y
        beq @none
        pha
        lda #ESC
        jsr Put
        lda #'J'
        jsr Put
        pla
        jsr Put
        lda #0
        ldy #W_FEED
        sta (wb),y
@none:  rts

; Send: the pass's columns (W_COLS, len of them) to the printer: the feed
; held back, the ink (with colours), ESC * 4 and the columns, CR. Nothing
; when no column has ink.
Send:   lda len
        ora len+1
        beq @none
        jsr Feed
        lda colp+1
        beq @black
        lda #ESC
        jsr Put
        lda #'r'
        jsr Put
        ldx ink
        lda InkCode,x
        jsr Put
@black: lda #ESC
        jsr Put
        lda #'*'
        jsr Put
        lda #4                  ; 80 dpi
        jsr Put
        lda len
        jsr Put
        lda len+1
        jsr Put
        clc                     ; out: the columns
        lda wb
        adc #W_COLS
        sta out
        lda wb+1
        adc #0
        sta out+1
        ldy #0
@col:   lda (out),y
        jsr Put
        iny
        bne :+
        inc out+1
:       lda len
        bne :+
        dec len+1
:       dec len
        lda len
        ora len+1
        bne @col
        lda #CR
        jsr Put
@none:  rts

; Build: the pass's columns for ink at W_COLS: of each card the rows
; rowA..rowA+rowN-1, each as this ink prints it (Row), turned on their
; side (a column per dot across, the first row on the top pin, bit 7);
; len the columns up to the last with ink.
Build:  lda dat
        sta src
        lda dat+1
        sta src+1
        clc
        lda wb
        adc #W_COLS
        sta out
        lda wb+1
        adc #0
        sta out+1
        lda #0
        sta card
        sta len
        sta len+1
        lda #4                  ; the turn's chain entered at row rowN - 1
        sec                     ; (Rows: 3 bytes a row, row 3 first)
        sbc rowN
        sta at
        asl a
        adc at
        adc #<Rows
        sta @tj+1
        lda #>Rows
        adc #0
        sta @tj+2
@card:  lda #0                  ; at: the card's first column (card x 8)
        sta at+1
        lda card
        asl a
        rol at+1
        asl a
        rol at+1
        asl a
        rol at+1
        sta at
        jsr Levels
        ldx #0                  ; tmp: the pass's rows as this ink prints
        stx any                 ; them (any: a dot at all)
@row:   txa
        clc
        adc rowA
        tay
        jsr Row
        sta tmp,x
        ora any
        sta any
        inx
        cpx rowN
        bcc @row
        lda any                 ; no dot: 8 empty columns at once (most
        bne @turn               ; cards of a text page; the user's U64,
        ldy #7                  ; 2026-11-18: the turn of all 8 rows of
:       sta (out),y             ; every card took 0.3 s a band at 1 MHz)
        dey
        bpl :-
        bmi @nextc
@turn:  ldy #0                  ; 8 columns, the leftmost dot first
@colm:  lda #0
@tj:    jsr Rows                ; (entered at row rowN - 1: patched above)
        sta (out),y
        cmp #0
        beq :+
        tya                     ; ink: len = this column + 1
        sec
        adc at
        sta len
        lda at+1
        adc #0
        sta len+1
:       iny
        cpy #8
        bne @colm
@nextc: clc                     ; the next card
        lda out
        adc #8
        sta out
        bcc :+
        inc out+1
:       clc
        lda src
        adc #8
        sta src
        bcc :+
        inc src+1
:       inc card
        lda card
        cmp #CARDS
        beq :+
        jmp @card
:       rts

; Rows: A's bits from the pass's rows, each row's leftmost dot taken
; (asl), row 0 into bit 7 down to row rowN - 1 (ror from the last row
; up); entered at row rowN - 1 (Build patches the jsr), A = 0 there.
Rows:   asl tmp+3
        ror a
        asl tmp+2
        ror a
        asl tmp+1
        ror a
        asl tmp
        ror a
        rts
        .assert tmp < $100, error, "epson.s: Rows needs tmp in the zero page"

; Levels: this card's patterns for ink: patIE/patIO (where the card has
; ink, even and odd rows) and patPE/patPO (its paper). Black alone: ink
; solid, paper none.
Levels: lda colp+1
        bne @colour
        lda #$FF
        sta patIE
        sta patIO
        lda #0
        sta patPE
        sta patPO
        rts
@colour:
        ldy card
        lda (colp),y
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr Level
        lda PatE,x
        sta patIE
        lda PatO,x
        sta patIO
        pla
        and #$0F
        jsr Level
        lda PatE,x
        sta patPE
        lda PatO,x
        sta patPO
        rts

; Level: X = the level (0-3) of ink in colour A.
Level:  sta lvl
        lda ink
        asl a
        asl a
        asl a
        asl a
        ora lvl
        tax
        lda InkLevel,x
        tax
        rts

; Row: A = row Y of the card at src as this ink prints it: (pixels and
; the ink pattern) or (no pixels and the paper pattern); the patterns
; alternate by the row's parity. X kept.
Row:    lda (src),y
        sta pix
        tya
        lsr a
        bcs @odd
        lda pix
        and patIE
        sta pr
        lda pix
        eor #$FF
        and patPE
        ora pr
        rts
@odd:   lda pix
        and patIO
        sta pr
        lda pix
        eor #$FF
        and patPO
        ora pr
        rts

; ----------------------------------------------------------------------
; The band cycle: per phase three passes (first row, rows, paper feed to
; the next pass's offset after it, /216"): row R at round(R x 2.7)/216",
; the rows of a pass a run on the top pins (worked out by hand from
; that rule; the sums 22, 21, 22, 21, 22 make 108 = 40 rows).
PassA:  .byte 0, 2, 6,   0, 1, 4,   0, 3, 6,   0, 2, 5,   0, 4, 7
PassN:  .byte 2, 4, 2,   1, 3, 4,   3, 3, 2,   2, 3, 3,   4, 3, 1
PassAdv:.byte 5, 11, 6,  2, 8, 11,  8, 8, 6,   5, 8, 8,   11, 8, 3

; Inks: K, C, M, Y; their bits in InkUse, their ESC r codes (Epson
; JX-80: 0 black, 1 magenta, 2 cyan, 4 yellow).
InkBit: .byte 1, 2, 4, 8
InkCode:.byte 0, 2, 1, 4

; The C64's colours as inks, per ink a level: 0 none, 1 a quarter, 2
; half, 3 solid (dithered by PatE/PatO). Our own choice, by eye from the
; colours' look: dark grey solid black (text), light grey a quarter.
;                0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15
;               bk wh rd cy pu gr bl ye or br lr dg gy lg lb lg
InkLevel:
        .byte    3, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 3, 2, 0, 0, 1   ; K
        .byte    0, 0, 0, 3, 2, 3, 3, 0, 0, 0, 0, 0, 0, 2, 2, 0   ; C
        .byte    0, 0, 3, 0, 3, 0, 3, 0, 2, 2, 2, 0, 0, 0, 1, 0   ; M
        .byte    0, 0, 3, 0, 0, 3, 0, 3, 3, 3, 1, 0, 0, 2, 0, 0   ; Y
; InkUse: per colour the inks with a level above 0 (from InkLevel)
InkUse: .byte    1, 0,12, 2, 6,10, 6, 8,12,13,12, 1, 1,10, 6, 1
PatE:   .byte    $00, $88, $AA, $FF     ; even rows
PatO:   .byte    $00, $22, $55, $FF     ; odd rows

; ----------------------------------------------------------------------
        .segment "BSS"
phase:  .res 1
pass:   .res 1
passes: .res 1
rowA:   .res 1
rowN:   .res 1
ink:    .res 1
inkSet: .res 1
card:   .res 1
at:     .res 2
lvl:    .res 1
pix:    .res 1
any:    .res 1                  ; Build: any row of the card with a dot
pr:     .res 1
patIE:  .res 1
patIO:  .res 1
patPE:  .res 1
patPO:  .res 1
