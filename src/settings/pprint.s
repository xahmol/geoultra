; GeoUltra Settings: the Printing page (overlay 1 with the Desktop page,
; ovl.s; docs/SETTINGS.md, "Pages"; docs/DESIGN.md "Printing", the
; user's decisions of 2026-11-16): the printer, one of GeoUltra's two
; drivers on drive E, as SETTINGS.INI's [desktop] printer= (the name the
; desktop puts into PrntFilename at its start; src/desktop/inifile.s);
; a note that the Ultimate's printer emulation must match the driver;
; the printer in use now (PrntFilename: also a driver of the user's own,
; chosen in the desktop). Own design and code.

        .include "geos.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress
        .export Ov_PrintDraw, Ov_PrintPress

COL1            = 130           ; the options (the system font's widths:
COL2            = 205           ; "Epson FX-80" 54, "Commodore MPS" 75, 11
                                ; for the box)
Y0              = PAGE_TOP + 20 ; the row's baseline (as the Desktop page)
NOTE_X          = PAGE_LEFT + 2
NOTE_Y          = Y0 + 26       ; the note's first baseline, 12 apart
NOTE_DY         = 12
USE_Y           = NOTE_Y + 4 * NOTE_DY

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
        .byte 2, 0
        .word COL1, TEpson, VEpson
        .word COL2, TMps, VMps

NoteLo: .byte <N1, <N2, <N3
NoteHi: .byte >N1, >N2, >N3
NoteY:  .byte NOTE_Y, NOTE_Y + NOTE_DY, NOTE_Y + 2 * NOTE_DY
NOTES   = * - NoteY
N1:     .byte "The Ultimate's printer: set its emulation", 0
N2:     .byte "in its menu (Printer settings) to match:", 0
N3:     .byte "Epson FX-80/JX-80 or Commodore MPS.", 0
LInUse: .byte "In use: ", 0
SDesktop:       .byte "desktop", 0
KPrinter:       .byte "printer", 0
LPrinter:       .byte "Printer", 0
TEpson:         .byte "Epson FX-80", 0
TMps:           .byte "Commodore MPS", 0
VEpson:         .byte "GU Epson FX-80", 0
VMps:           .byte "GU Commodore MPS", 0

at:     .byte 0
