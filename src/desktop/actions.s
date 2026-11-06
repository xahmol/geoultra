; GeoUltra Desktop: actions on the selection (docs/DESKTOP.md, step D4).
; Copy and cut keep the source folder (srcPath) and the names of the
; selected entries (or the cursor's, when none is selected) in the
; application's REU (bank CLIP_BANK, CLIP_SIZE bytes each); paste copies
; (FE_COPY) or moves (FE_MOVE) them into the current folder, asking
; before an existing file is replaced; after a cut-and-paste the
; clipboard is empty. Delete asks once for the selection, then removes
; files (FE_DELETE) and empty folders (FE_RMDIR). Rename (the cursor's
; entry) and new folder ask for a name (a dialog with an input line).
; Errors are shown in a dialog and end the action. Through the file
; engine, so the Ultimate's file system is a peer of the drives (CVT on
; the way, as in gush). Own code.

        .include "geos.inc"

        .import FileEngine, ListRead, ListDraw, Fetch, IsSelected
        .import entryInfo, entryName, cur, count, path
        .export Copy, Cut, Paste, Delete, Rename, NewFolder

DoDlgBox        = $C256         ; GEOS jump table
StashRAM        = $C2C8
FetchRAM        = $C2CB

FE_COPY         = 5
FE_MOVE         = 6
FE_DELETE       = 7
FE_MKDIR        = 8
FE_RMDIR        = 9
FE_RENAME       = 10
FC_OVERWRITE    = $01
FILE_EXISTS     = $40
FI_KIND         = 0
K_DRIVE         = 1
K_FOLDER        = 2
K_UDIR          = 6

CLIP_BANK       = 5             ; (1-4: the entry table, list.s)
CLIP_SIZE       = 64            ; a name and its zero
CLIP_MAX        = 1024
NAME_MAX        = 40            ; an input line's characters
DBI_X_0         = 1             ; the left icon's place in a dialog

        .segment "ZEROPAGE"

askLine:        .res 2          ; (DBVARSTR: zero page pointers)
nameLine:       .res 2

        .segment "CODE"

; Copy, Cut: the selection to the clipboard (mode 0: copy, 1: move).
Copy:   lda #0
        beq Clip
Cut:    lda #1
Clip:   sta clipMode
        ldy #0                  ; the source folder
@path:  lda path,y
        sta srcPath,y
        beq :+
        iny
        bne @path
:       lda #0
        sta clipCount
        sta clipCount+1
        sta n
        sta n+1
        jsr AnySelected
        sta some
@entry: lda n                   ; each entry selected (or the cursor's)
        cmp count
        bne :+
        lda n+1
        cmp count+1
        beq @end
:       lda n
        ldx n+1
        jsr Wanted
        bcs @next
        lda n
        ldx n+1
        jsr Fetch
        lda clipCount
        ldx clipCount+1
        jsr ClipPlace
        jsr StashRAM
        inc clipCount
        bne @next
        inc clipCount+1
@next:  inc n
        bne @entry
        inc n+1
        bne @entry
@end:   rts

; Wanted: C clear when entry A/X takes part: selected, or the cursor's
; when nothing is selected (some = 0).
Wanted: ldy some
        beq @cursor
        jsr IsSelected
        beq @no
        clc
        rts
@cursor:
        cmp cur
        bne @no
        cpx cur+1
        bne @no
        clc
        rts
@no:    sec
        rts

; AnySelected: A nonzero when any entry is selected.
AnySelected:
        lda #0
        sta n
        sta n+1
@entry: lda n
        cmp count
        bne :+
        lda n+1
        cmp count+1
        beq @none
:       lda n
        ldx n+1
        jsr IsSelected
        bne @some
        inc n
        bne @entry
        inc n+1
        bne @entry
@none:  lda #0
        sta n
        sta n+1
        rts
@some:  lda #0
        sta n
        sta n+1
        lda #1
        rts

; ClipPlace: r0-r3 for clipboard name A/X (entryName <-> the REU).
ClipPlace:
        sta r1L                 ; n * 64: (n << 6)
        stx r1H
        ldx #6
@shift: asl r1L
        rol r1H
        dex
        bne @shift
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        lda #CLIP_SIZE
        sta r2L
        lda #0
        sta r2H
        lda #CLIP_BANK
        sta r3L
        rts

; Paste: each clipboard name copied or moved into the current folder;
; a file there of the same name replaced after asking (NO: left out).
Paste:  lda #0
        sta n
        sta n+1
@name:  lda n
        cmp clipCount
        bne :+
        lda n+1
        cmp clipCount+1
        beq @done
:       lda n
        ldx n+1
        jsr ClipPlace
        jsr FetchRAM
        jsr Source              ; srcPath "/" entryName to full
        lda #0
        sta flags
@try:   lda #<full
        sta r0L
        lda #>full
        sta r0H
        lda #<path
        sta r1L
        lda #>path
        sta r1H
        lda flags
        sta r2L
        lda #0
        sta r3L                 ; (no progress routine)
        sta r3H
        lda clipMode
        clc
        adc #FE_COPY            ; (FE_MOVE = FE_COPY + 1)
        jsr FileEngine
        txa
        beq @next
        cpx #FILE_EXISTS
        bne @fail
        lda flags               ; (asked already: an error)
        bne @fail
        lda #<ReplaceText
        ldx #>ReplaceText
        jsr Ask
        bne @next               ; (NO: this one left out)
        lda #FC_OVERWRITE
        sta flags
        bne @try
@fail:  jsr Error
        jmp @reread
@next:  inc n
        bne @name
        inc n+1
        bne @name
@done:  lda clipMode            ; moved: the clipboard is empty
        beq @reread
        lda #0
        sta clipCount
        sta clipCount+1
@reread:
        jsr ListRead
        jmp ListDraw

; Source: full = srcPath, "/" (unless it ends in one), entryName.
Source: ldy #0
@p:     lda srcPath,y
        beq @end
        sta full,y
        iny
        bne @p
@end:   jmp Append

; Append: "/" (unless full ends in one, Y its end) and entryName to full.
Append: lda full-1,y
        cmp #'/'
        beq @name
        lda #'/'
        sta full,y
        iny
@name:  ldx #0
@n:     lda entryName,x
        sta full,y
        beq @end
        iny
        inx
        bne @n
@end:   rts

; Delete: after one question, each entry taking part removed (a folder
; must be empty).
Delete: jsr AnySelected
        sta some
        lda count
        ora count+1
        beq @end
        lda #<DeleteText
        ldx #>DeleteText
        jsr Ask
        bne @end                ; (NO)
        lda #0
        sta n
        sta n+1
@entry: lda n
        cmp count
        bne :+
        lda n+1
        cmp count+1
        beq @reread
:       lda n
        ldx n+1
        jsr Wanted
        bcs @next
        lda n
        ldx n+1
        jsr Fetch
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        ldy #FE_DELETE
        lda entryInfo + FI_KIND
        cmp #K_FOLDER
        beq @dir
        cmp #K_UDIR
        bne :+
@dir:   ldy #FE_RMDIR
:       tya
        jsr FileEngine
        txa
        beq @next
        jsr Error
        jmp @reread
@next:  inc n
        bne @entry
        inc n+1
        bne @entry
@reread:
        jsr ListRead
        jmp ListDraw
@end:   rts

; Rename: the cursor's entry gets the name asked for.
Rename: lda count
        ora count+1
        beq @end
        lda cur
        ldx cur+1
        jsr Fetch
        ldy #NAME_MAX           ; the old name as the start of the line
@old:   lda entryName,y
        sta input,y
        dey
        bpl @old
        lda #0
        sta input + NAME_MAX
        lda #<RenameText
        ldx #>RenameText
        jsr AskName
        bne @end
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        lda #<input
        sta r1L
        lda #>input
        sta r1H
        lda #FE_RENAME
        jsr FileEngine
        txa
        beq @reread
        jsr Error
@reread:
        jsr ListRead
        jmp ListDraw
@end:   rts

; NewFolder: a folder of the name asked for in the current folder.
NewFolder:
        lda #0
        sta input
        lda #<NewText
        ldx #>NewText
        jsr AskName
        bne @end
        lda #<input
        sta r0L
        lda #>input
        sta r0H
        lda #0
        sta r2L                 ; (tracks: the default)
        lda #FE_MKDIR
        jsr FileEngine
        txa
        beq @reread
        jsr Error
@reread:
        jsr ListRead
        jmp ListDraw
@end:   rts

; Ask: a question (the text at A/X, entryName on the second line):
; Z set for YES.
Ask:    sta askLine
        stx askLine+1
        lda #<askDlg
        sta r0L
        lda #>askDlg
        sta r0H
        jsr DoDlgBox
        lda r0L
        cmp #YES
        rts

; AskName: the text at A/X and an input line (input, its start already
; there): Z set for OK or RETURN, with a name.
AskName:
        sta nameLine
        stx nameLine+1
        lda #<input
        sta r5L
        lda #>input
        sta r5H
        lda #<nameDlg
        sta r0L
        lda #>nameDlg
        sta r0H
        jsr DoDlgBox
        lda r0L
        cmp #DBGETSTRING        ; (RETURN in the input line ends the
        beq :+                  ; dialog with DBGETSTRING)
        cmp #OK
        bne @end
:       lda input               ; (an empty name: as CANCEL)
        beq @cancel
        lda #0                  ; (Z set)
@end:   rts
@cancel:
        lda #1
        rts

; Error: X = the engine's error, shown (entryName on the first line).
Error:  txa
        jsr Hex
        lda #<errDlg
        sta r0L
        lda #>errDlg
        sta r0H
        jmp DoDlgBox

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

ReplaceText:    .byte BOLDON, "Replace it?", PLAINTEXT, 0
DeleteText:     .byte BOLDON, "Delete the selection?", PLAINTEXT, 0
RenameText:     .byte BOLDON, "Rename to:", PLAINTEXT, 0
NewText:        .byte BOLDON, "New folder:", PLAINTEXT, 0

        .segment "DATA"

askDlg: .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askLine
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word entryName
        .byte YES, DBI_X_0, DBI_Y_2
        .byte NO, DBI_X_2, DBI_Y_2
        .byte 0
nameDlg:
        .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, nameLine
        .byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5, NAME_MAX
        .byte OK, DBI_X_0, DBI_Y_2
        .byte CANCEL, DBI_X_2, DBI_Y_2
        .byte 0
errDlg: .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word entryName
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word errText
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0
errText:        .byte "failed: error $"
errCode:        .byte "00", 0

clipMode:       .byte 0
clipCount:      .word 0
n:              .word 0
some:           .byte 0
flags:          .byte 0

        .segment "BSS"

srcPath:        .res 256
full:           .res 256
input:          .res NAME_MAX + 1
