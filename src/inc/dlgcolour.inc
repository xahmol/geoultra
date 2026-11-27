; dlgcolour.inc: DlgColours, the colour cells under a DEF_DB_POS dialog
; box and its shadow (card rows 4-16, cards 8-32) set to the programs'
; colours (progColours, $C0F4), before the kernal shows a dialog over a
; program that colours its screen (GeoUltra's desktop: its headings and
; selection showed through the box; the user's hand test 2026-11-27).
; Included by tobasic.s (module 129, the boot-file refusal) and task.s
; (module 131, the close question, which gives the cells back after).
; The includer imports progColours. Destroys A, X, Y, r1.
DLGC_ROW        = 4
DLGC_ROWS       = 13
DLGC_CARD       = 8
DLGC_CARDS      = 25

DlgColours:
        lda #<(COLOR_MATRIX + DLGC_ROW * 40 + DLGC_CARD)
        sta r1L
        lda #>(COLOR_MATRIX + DLGC_ROW * 40 + DLGC_CARD)
        sta r1H
        ldx #DLGC_ROWS
@row:   ldy #DLGC_CARDS - 1
        lda progColours
@card:  sta (r1),y
        dey
        bpl @card
        clc
        lda r1L
        adc #40
        sta r1L
        bcc :+
        inc r1H
:       dex
        bne @row
        rts
