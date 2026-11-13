; GeoUltra Desktop: the error dialog and the path join that both
; overlays use (actions and the recursion in overlay 2, mounting in
; overlay 3), so in the core. Moved from actions.s on 2026-11-11 when
; mounting got its own overlay. Own code.

        .include "geos.inc"
        .include "desktop.inc"

FULL_DIRECTORY  = 4             ; (GEOS: no free directory entry)

        .import entryName, Dialog, text
        .export Error, Append

full = text                     ; (actions.s, mount.s: the path built)

        .segment "CODE"

; Append: "/" (unless full ends in one, Y its end) and entryName to full,
; cut at its 255th character (a path that long fails in the engine, with
; an error shown, rather than running past full).
Append: lda full-1,y
        cmp #'/'
        beq @name
        lda #'/'
        sta full,y
        iny
@name:  ldx #0
@n:     cpy #255
        bcs @cut
        lda entryName,x
        sta full,y
        beq @end
        iny
        inx
        bne @n
@cut:   lda #0
        sta full,y
@end:   rts

; Error: X = the engine's error, shown (entryName on the first line):
; the common ones in words, the rest by number (the user's test
; 2026-11-13: "failed: error $03" for a full drive said too little).
Error:  txa
        ldx #ERRS - 1
@find:  cmp ErrCodes,x
        beq @word
        dex
        bpl @find
        jsr Hex                 ; (A: the code still)
        lda #<errText
        ldx #>errText
        bne @set                ; (always)
@word:  lda ErrLo,x
        pha
        lda ErrHi,x
        tax
        pla
@set:   sta errLine
        stx errLine+1
        lda #<errDlg
        sta r0L
        lda #>errDlg
        sta r0H
        jmp Dialog

; Hex: A as two hex digits into errCode.
Hex:    pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @d
        sta errCode
        pla
        and #$0F
        jsr @d
        sta errCode+1
        rts
@d:     cmp #10
        bcc :+
        adc #'A' - '0' - 10 - 1
:       adc #'0'
        rts

        .segment "DATA"

errDlg: .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word entryName
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
errLine:
        .word errText
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0
ErrCodes:       .byte INSUFF_SPACE, FULL_DIRECTORY, WR_PR_ON, FILE_EXISTS, DIR_NOT_EMPTY
                .byte FILE_NOT_FOUND, ERR_IMAGE
ERRS = * - ErrCodes
ErrLo:          .byte <ENoRoom, <EDirFull, <ELocked, <EExists, <ENotEmpty, <ENotFound, <EImage
ErrHi:          .byte >ENoRoom, >EDirFull, >ELocked, >EExists, >ENotEmpty, >ENotFound, >EImage
ENoRoom:        .byte "Not enough room on the drive.", 0
EDirFull:       .byte "The directory is full.", 0
ELocked:        .byte "The drive cannot be written to.", 0
EExists:        .byte "A file of that name is there.", 0
ENotEmpty:      .byte "The folder is not empty.", 0
ENotFound:      .byte "Not found.", 0
EImage:         .byte "Disk images stay on the Ultimate", 0
errText:        .byte "failed: error $"
errCode:        .byte "00", 0
