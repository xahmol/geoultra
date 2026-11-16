; GeoUltra Settings: the Printing page (overlay 1 with the Desktop page,
; ovl.s; docs/SETTINGS.md, "Pages"; docs/DESIGN.md "Printing", the
; user's decisions of 2026-11-16): the printer, one of GeoUltra's
; drivers on drive E (GU Epson FX-80, GU Commodore MPS, GU PDF A4, GU PDF
; Letter), as SETTINGS.INI's [desktop] printer= (the name the desktop
; puts into PrntFilename at its start; src/desktop/inifile.s); a note
; that for the first two the desktop switches on the Ultimate's SoftIEC
; drive and printer and sets the emulation (src/desktop/prnult.s), and
; where PDF files go; the printer in use now (PrntFilename: also a
; driver of the user's own, chosen in the desktop). Own design and code.

        .include "geos.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress
        .export Ov_PrintDraw, Ov_PrintPress

COL1            = 124           ; the options (the system font's widths:
COL2            = 165           ; "Epson" 24, "MPS" 18, "PDF A4" 30, "PDF
COL3            = 200           ; Letter" 42, 11 for the box, 6 between;
COL4            = 247           ; to x 300)
Y0              = PAGE_TOP + 20 ; the row's baseline (as the Desktop page)
NOTE_X          = PAGE_LEFT + 2
NOTE_Y          = Y0 + 26       ; the note's first baseline, 12 apart
NOTE_DY         = 12
USE_Y           = NOTE_Y + 5 * NOTE_DY

        .segment "OV1"

; Ov_PrintDraw: the row, the note, the printer in use.
Ov_PrintDraw:
        lda #<Rows
        ldx #>Rows
        jsr ChoiceDraw
        ldx #0
@line:  stx at
        lda NoteLo,x
        sta r0L
        lda NoteHi,x
        sta r0H
        lda NoteY,x
        jsr Text
        ldx at
        inx
        cpx #NOTES
        bcc @line
        lda #<LInUse
        sta r0L
        lda #>LInUse
        sta r0H
        lda #USE_Y
        jsr Text
        lda PrntFilename        ; (none: nothing after it)
        beq @end
        lda #<PrntFilename
        sta r0L
        lda #>PrntFilename
        sta r0H
        jmp PutString           ; (after "In use: ")
@end:   rts

; Ov_PrintPress: a click on the row.
Ov_PrintPress:
        lda #<Rows
        ldx #>Rows
        jmp ChoicePress

; Text: the string at r0 at NOTE_X, baseline A.
Text:   sta r1H
        lda #<NOTE_X
        sta r11L
        lda #>NOTE_X
        sta r11H
        jmp PutString

Rows:   .byte 1
        .byte Y0
        .word LPrinter, SDesktop, KPrinter
        .byte 4, 0
        .word COL1, TEpson, VEpson
        .word COL2, TMps, VMps
        .word COL3, TPdfA4, VPdfA4
        .word COL4, TPdfLet, VPdfLet

NoteLo: .byte <N1, <N2, <N3, <N4
NoteHi: .byte >N1, >N2, >N3, >N4
NoteY:  .byte NOTE_Y, NOTE_Y + NOTE_DY, NOTE_Y + 2 * NOTE_DY, NOTE_Y + 3 * NOTE_DY
NOTES   = * - NoteY
N1:     .byte "Epson, MPS: GeoUltra switches on the", 0
N2:     .byte "Ultimate's SoftIEC drive and printer and", 0
N3:     .byte "sets its emulation (not saved there).", 0
N4:     .byte "PDF: a file in GEOULTRA/print on the Ultimate.", 0
LInUse: .byte "In use: ", 0
SDesktop:       .byte "desktop", 0
KPrinter:       .byte "printer", 0
LPrinter:       .byte "Printer", 0
TEpson:         .byte "Epson", 0
TMps:           .byte "MPS", 0
TPdfA4:         .byte "PDF A4", 0
TPdfLet:        .byte "PDF Letter", 0
VEpson:         .byte "GU Epson FX-80", 0
VMps:           .byte "GU Commodore MPS", 0
VPdfA4:         .byte "GU PDF A4", 0
VPdfLet:        .byte "GU PDF Letter", 0

at:     .byte 0
