; GeoUltra Settings: the Printing page (overlay 1 with the Desktop page,
; ovl.s; docs/SETTINGS.md, "Pages"; docs/DESIGN.md "Printing", the
; user's decisions of 2026-11-16): the printer, one of GeoUltra's
; drivers on drive E (GU Epson FX-80, GU Commodore MPS, GU PDF A4, GU PDF
; Letter), as SETTINGS.INI's [desktop] printer= (the name the desktop
; puts into PrntFilename at its start; src/desktop/inifile.s); a note
; that for the first two the desktop switches on the Ultimate's SoftIEC
; drive and printer and sets the emulation (src/desktop/prnult.s), and
; where PDF files go; the printer in use now (PrntFilename: also a
; driver of the user's own, chosen in the desktop). Since 2026-11-16/19
; also: the serial timing ([print] fastbus=), the disks' fonts ([system]
; diskfonts=), GU PostScript's paper and look ([print] paper=,
; pslook=: its options box's defaults). Own design and code.

        .include "geos.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress
        .export Ov_PrintDraw, Ov_PrintPress

COL1            = 132           ; the options (the system font's widths:
COL2            = 173           ; "Epson" 24, "MPS" 18, "PDF A4" 30, "PDF
COL3            = 208           ; Letter" 42, 11 for the box, 6 between;
COL4            = 255           ; to x 308; from 132: the label "PS look")
Y0              = PAGE_TOP + 20 ; the row's baseline (as the Desktop page)
NOTE_X          = PAGE_LEFT + 2
DY              = 14            ; the rows' distance (as the Desktop page)
NOTE_Y          = Y0 + 4 * DY + 18 ; the note's first baseline, 12 apart
NOTE_DY         = 12
USE_Y           = NOTE_Y + 5 * NOTE_DY  ; (right after the notes: above the
                                        ; buttons with five rows, 2026-11-19)

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

Rows:   .byte 5
        .byte Y0
        .word LPrinter, SDesktop, KPrinter
        .byte 4, 0
        .word COL1, TEpson, VEpson
        .word COL2, TMps, VMps
        .word COL3, TPdfA4, VPdfA4
        .word COL4, TPdfLet, VPdfLet
        .byte Y0 + DY                   ; the serial bus's timing (the GU
        .word LTiming, SPrint, KFast    ; Epson and MPS drivers, from the
        .byte 2, 0                      ; next start: prnserial.inc, the
        .word COL1, TStandard, 0        ; info block's guPrnFast)
        .word COL3, TFast, VOn
        .byte Y0 + 2 * DY               ; the disks' fonts in the programs'
        .word LFonts, SSystem, KDiskFonts ; lists (from the next start:
        .byte 2, 0                      ; docs/GEOULTRA_MANUAL.md "System
        .word COL1, TAll, 0             ; fonts")
        .word COL3, TSysOnly, VHide
        .byte Y0 + 3 * DY               ; GU PostScript's paper (src/psw
        .word LPaper, SPrint, KPaper    ; options.s: its box's default)
        .byte 2, 0
        .word COL1, TA4, 0
        .word COL3, TLetter, VLetter
        .byte Y0 + 4 * DY               ; and its look: the LW and GU fonts
        .word LLook, SPrint, KLook      ; as real text, or every font from
        .byte 2, 0                      ; its bitmaps
        .word COL1, TRealText, 0
        .word COL3, TC64Look, VC64

NoteLo: .byte <N1, <N2, <N3, <N4, <N5
NoteHi: .byte >N1, >N2, >N3, >N4, >N5
NoteY:  .byte NOTE_Y, NOTE_Y + NOTE_DY, NOTE_Y + 2 * NOTE_DY, NOTE_Y + 3 * NOTE_DY
        .byte NOTE_Y + 4 * NOTE_DY
NOTES   = * - NoteY
N1:     .byte "Epson, MPS: GeoUltra switches on the", 0
N2:     .byte "Ultimate's SoftIEC drive and printer and", 0
N3:     .byte "sets its emulation (not saved there).", 0
N4:     .byte "PDF, PostScript: files in GEOULTRA/print.", 0
N5:     .byte "Timing and fonts: from the next start.", 0
LInUse: .byte "In use: ", 0
LPaper:         .byte "Paper", 0
LLook:          .byte "PS look", 0
KPaper:         .byte "paper", 0
KLook:          .byte "pslook", 0
TA4:            .byte "A4", 0
TLetter:        .byte "Letter", 0
TRealText:      .byte "real text", 0
TC64Look:       .byte "C64 look", 0
VLetter:        .byte "letter", 0
VC64:           .byte "c64", 0
LTiming:        .byte "Timing", 0
LFonts:         .byte "Fonts", 0
SPrint:         .byte "print", 0
SSystem:        .byte "system", 0
KFast:          .byte "fastbus", 0
KDiskFonts:     .byte "diskfonts", 0
TStandard:      .byte "standard", 0
TFast:          .byte "fast", 0
TAll:           .byte "all", 0
TSysOnly:       .byte "system only", 0
VOn:            .byte "on", 0
VHide:          .byte "hide", 0
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
