; GeoUltra Desktop: the clipboard menu (overlay 3, with mounting: overlay
; 7, the context menu and Info, was full; docs/design/DESIGN.md "Clipboard"; the user's decisions of
; 2026-11-15: the menu that was "disk", show, save as file, clear). The
; kernal keeps every program's scrap files in one store (src/kernal/
; scrap.s) whose directory is block 0 of track 246 on every drive; the
; jump table's FindFile, ReadFile, DeleteFile work on it by the scraps'
; names. The scraps' data goes through the background screen (BUF): the
; core draws the desktop anew afterwards (desktop.s, MClip*). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import Dialog, FileEngine, path
        .export Ov_ClipShow, Ov_ClipSave, Ov_ClipClear
Ov_ClipShow = ClipShow
Ov_ClipSave = ClipSave
Ov_ClipClear = ClipClear

GetBlock        = $C1E4         ; GEOS jump table
ReadFile        = $C1FF
FindFile        = $C20B
GetFHdrInfo     = $C229
SaveFile        = $C1ED
DeleteFile      = $C238
BitmapClip      = $C2AA
SCRAP_TRACK     = 246           ; the store's directory: 246/0 (scrap.s)
BUF             = $6000         ; the background screen (drawn anew after)
BUF_LEN         = $1F40
ENTRIES         = 8
SNAME_LEN       = 17            ; a name and its zero
SHOWN           = 30            ; the text preview: characters
PIC_X           = 22            ; the picture in the box: card 22 on,
PIC_W           = 9             ; 9 cards wide, from y 80, 40 lines
PIC_Y           = 80
PIC_H           = 40
ESC_CARDSET     = $17           ; (geoWrite's escapes: ESC_RULER and
                                ; ESC_GRAPHICS from geos.inc)

        .segment "OV3"

; ClipShow: the clipboard in a dialog: the text scrap's size and first
; characters, the photo scrap's size and the picture (when it fits the
; buffer), the other scraps by number.
ClipShow:
        jsr Collect
        jsr Clear               ; (the lines: empty, filled below)
        lda #0
        sta showPic
        lda #<TextName
        ldx #>TextName
        jsr Find
        bcs @notext
        jsr First               ; its first block: the size, the text
        lda #<SizeWord
        ldx #>SizeWord
        ldy #0
        jsr Put2
        lda BUF + 2
        ldx BUF + 3
        jsr Dec2
        lda #<BytesWord
        ldx #>BytesWord
        jsr Put2
        jsr Preview
        jmp @pic
@notext:
        lda #<NoText
        ldx #>NoText
        ldy #0
        jsr Put2
@pic:   lda #<PhotoName
        ldx #>PhotoName
        jsr Find
        bcs @nopic
        jsr Whole               ; the whole picture (X = 0: it fits)
        stx picErr
        lda #<PicWord
        ldx #>PicWord
        ldy #0
        jsr Put4
        lda BUF                 ; width: cards * 8
        asl a
        asl a
        asl a
        pha
        lda BUF
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        pla
        jsr Dec4
        lda #<ByWord
        ldx #>ByWord
        jsr Put4
        lda BUF + 1
        ldx BUF + 2
        jsr Dec4
        lda picErr
        bne :+
        lda #$80
        sta showPic
:       jmp @others
@nopic: lda #<NoPic
        ldx #>NoPic
        ldy #0
        jsr Put4
@others:
        lda count               ; the others (not text, not photo)
        sec
        sbc found
        beq @show
        pha
        lda #<OtherWord
        ldx #>OtherWord
        ldy #0
        jsr Put5
        pla
        ldx #0
        jsr Dec5
@show:  lda #<showDlg
        sta r0L
        lda #>showDlg
        sta r0H
        jmp Dialog

; DrawPic (the dialog's DB_USR_ROUT): the photo scrap clipped to its
; place in the box (lower right; the OK icon at the left).
DrawPic:
        bit showPic
        bpl @end
        lda #<(BUF + 3)
        sta r0L
        lda #>(BUF + 3)
        sta r0H
        lda #PIC_X
        sta r1L
        lda #PIC_Y
        sta r1H
        lda BUF                 ; width: up to PIC_W cards, the rest skipped
        cmp #PIC_W
        bcc :+
        lda #PIC_W
:       sta r2L
        lda BUF
        sec
        sbc r2L
        sta r11H
        lda #0
        sta r11L
        sta r12L
        sta r12H
        lda BUF + 2             ; height: up to PIC_H lines
        bne @tall
        lda BUF + 1
        cmp #PIC_H
        bcc :+
@tall:  lda #PIC_H
:       sta r2H
        jmp BitmapClip
@end:   rts

; ClipClear: asked first; then every scrap in the store deleted.
ClipClear:
        lda #<ClearAsk
        ldx #>ClearAsk
        jsr Ask
        bne @end
        jsr Collect
        lda #0
        sta at
@del:   lda at
        cmp count
        bcs @end
        jsr NameAt
        jsr DeleteFile          ; (the jump table: the store)
        inc at
        bne @del
@end:   rts

; ClipSave: each scrap saved as a file in the folder shown (a GEOS drive
; A-D), its name asked (proposed: the scrap's name and " 1"). C set: not
; saved at all (no folder for it).
ClipSave:
        jsr Collect
        lda count
        bne :+
        lda #<NoneMsg
        ldx #>NoneMsg
        jmp Tell
:       jsr Folder              ; the folder shown made current
        txa
        beq :+
        lda #<FolderMsg
        ldx #>FolderMsg
        jmp Tell
:       lda #0
        sta at
@each:  lda at
        cmp count
        bcs @end
        jsr SaveOne
        inc at
        bne @each
@end:   rts

; SaveOne: scrap `at` saved under a name asked.
SaveOne:
        jsr NameAt              ; r0 = its name; input = it and " 1"
        ldy #0
@cp:    lda (r0),y
        beq :+
        sta input,y
        iny
        bne @cp
:       lda #' '
        sta input,y
        lda #'1'
        sta input+1,y
        lda #0
        sta input+2,y
        lda #<input
        sta r5L
        lda #>input
        sta r5H
        lda #<nameDlg
        sta r0L
        lda #>nameDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #CANCEL
        beq @out
        lda input
        bne :+
@out:   rts
:       lda #<input             ; a file of that name there: not saved
        sta r6L
        lda #>input
        sta r6H
        jsr FindFile
        txa
        bne :+
        lda #<ExistsMsg
        ldx #>ExistsMsg
        jmp Tell
:       lda at                  ; the scrap: its header and data
        jsr NameAt
        lda r0L
        sta r6L
        lda r0H
        sta r6H
        jsr FindFile
        txa
        bne @err
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr GetFHdrInfo
        txa
        bne @err
        lda #<BUF
        sta r7L
        lda #>BUF
        sta r7H
        lda #<BUF_LEN
        sta r2L
        lda #>BUF_LEN
        sta r2H
        jsr ReadFile            ; (r7: the data's end)
        cpx #BFR_OVERFLOW
        bne :+
        lda #<LargeMsg
        ldx #>LargeMsg
        jmp Tell
:       txa
        bne @err
        lda #<input             ; the header: the new name, the data's place
        sta fileHeader
        lda #>input
        sta fileHeader+1
        lda #<BUF
        sta fileHeader + O_GHST_ADDR
        lda #>BUF
        sta fileHeader + O_GHST_ADDR + 1
        lda r7L
        sta fileHeader + O_GHEND_ADDR
        lda r7H
        sta fileHeader + O_GHEND_ADDR + 1
        lda #<fileHeader
        sta r9L
        lda #>fileHeader
        sta r9H
        lda #0
        sta r10L
        jsr SaveFile
        txa
        bne @err
@end:   rts
@err:   lda #<FailMsg
        ldx #>FailMsg
        jmp Tell

; Folder: the folder shown (path, a GEOS drive A-D) the current one: a
; drive's root by SetDevice and DirRoot, a folder by FE_SELECT of its own
; entry (its drive and parent current, its short name) and SetCurDir.
; X = 0, else not possible here (drive E, the Ultimate).
Folder: ldx #1
        lda path
        cmp #'/'
        bne @end
        lda path + 1
        cmp #'a'
        bcc @end
        cmp #'e'
        bcs @end
        lda path + 2
        bne @sub
        lda path + 1            ; the root
        sec
        sbc #'a' - 8
        jsr SetDevice
        jsr OpenDisk
        txa
        bne @end
        lda #15                 ; DirRoot: the extension table + 15
        jmp Ext
@sub:   cmp #'/'
        bne @end
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #<short
        sta r1L
        lda #>short
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        bne @end
        lda #<short             ; SetCurDir: the extension table + 5
        sta r0L
        lda #>short
        sta r0H
        lda #5
        jmp Ext
@end:   rts

; Ext: the extension table's entry at offset A.
Ext:    clc
        adc guExtTable
        sta extVec
        lda guExtTable+1
        adc #0
        sta extVec+1
        jmp (extVec)

; Collect: the store's directory (246/0, through the current drive) and
; its scraps' names into names (count of them); found = 0.
Collect:
        lda #SCRAP_TRACK
        sta r1L
        lda #0
        sta r1H
        sta count
        sta found
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        bne @end
        ldx #2                  ; each entry's type byte
@entry: lda diskBlkBuf,x
        beq @next
        stx tmp
        lda count
        jsr NameAt              ; (r0 = its slot in names)
        ldx tmp
        ldy #0
@name:  lda diskBlkBuf + 3,x
        cmp #$A0
        beq @done
        sta (r0),y
        inx
        iny
        cpy #SNAME_LEN - 1
        bcc @name
@done:  lda #0
        sta (r0),y
        inc count
        ldx tmp
@next:  txa
        clc
        adc #32
        tax
        bcc @entry
@end:   rts

; NameAt: A = an index: r0 = its name in names.
NameAt: ldx #0
        stx r0H
        sta r0L
        asl a                   ; * 17: * 16 + 1
        asl a
        asl a
        asl a
        clc
        adc r0L
        adc #<names
        sta r0L
        lda #>names
        adc #0
        sta r0H
        rts

; Find: A/X = a scrap's name: C clear and its data's block (r1, from the
; store's entry through FindFile) when it is there; found counted.
Find:   sta r6L
        stx r6H
        jsr FindFile
        txa
        bne @no
        lda dirEntryBuf + 1
        sta r1L
        lda dirEntryBuf + 2
        sta r1H
        lda dirEntryBuf + 1     ; (a disk's own old scrap: not the store's)
        cmp #SCRAP_TRACK
        bcc @no
        inc found
        clc
        rts
@no:    sec
        rts

; First: the block at r1 into BUF. Whole: the file from r1 into BUF (X:
; ReadFile's error, BFR_OVERFLOW when larger).
First:  lda #<BUF
        sta r4L
        lda #>BUF
        sta r4H
        jmp GetBlock
Whole:  lda #<BUF
        sta r7L
        lda #>BUF
        sta r7H
        lda #<BUF_LEN
        sta r2L
        lda #>BUF_LEN
        sta r2H
        jmp ReadFile

; Preview: line3 = the text scrap's first characters (BUF + 4 on, the
; first block's data after the length, up to its end), escapes skipped,
; in quotes.
Preview:
        lda BUF + 3             ; the end: 4 + its length, within the block
        bne @full
        lda BUF + 2
        cmp #256 - 4
        bcs @full
        adc #4
        .byte $2C
@full:  lda #255
        sta tmp2
        ldy #0
        lda #'"'
        sta Line3
        iny
        ldx #4
@ch:    cpx tmp2
        bcs @end
        lda BUF,x
        cmp #ESC_CARDSET
        bne :+
        inx                     ; (font and style: 4 bytes)
        inx
        inx
        inx
        bne @ch
:       cmp #ESC_RULER
        bne :+
        txa                     ; (a ruler: 27 bytes)
        clc
        adc #27
        tax
        bcs @end
        bcc @ch
:       cmp #ESC_GRAPHICS
        bne :+
        txa                     ; (a picture: 5 bytes)
        clc
        adc #5
        tax
        bcs @end
        bcc @ch
:       inx
        cmp #' '
        bcc @sp                 ; (line breaks, tabs: a space)
        cmp #$80
        bcs @ch
        bcc @put
@sp:    lda #' '
@put:   sta Line3,y
        iny
        cpy #SHOWN
        bcc @ch
@end:   lda #'"'
        sta Line3,y
        lda #0
        sta Line3+1,y
        rts

; Clear: the four lines empty.
Clear:  lda #0
        sta Line2
        sta Line3
        sta Line4
        sta Line5
        rts

; Put2/Put4/Put5: the text at A/X into that line from Y (Y on, ended).
Put2:   sta r0L
        stx r0H
        lda #<Line2
        ldx #>Line2
        bne PutAt
Put4:   sta r0L
        stx r0H
        lda #<Line4
        ldx #>Line4
        bne PutAt
Put5:   sta r0L
        stx r0H
        lda #<Line5
        ldx #>Line5
PutAt:  sta r1L
        stx r1H
        sty tmp
        ldy #0
@c:     lda (r0),y
        beq @end
        sty r2L
        ldy tmp
        sta (r1),y
        inc tmp
        ldy r2L
        iny
        bne @c
@end:   ldy tmp
        lda #0
        sta (r1),y
        rts

; Dec2/Dec4/Dec5: A/X (low, high) in decimal into that line at Y (Y on,
; ended).
Dec2:   sta num
        stx num+1
        lda #<Line2
        ldx #>Line2
        bne Decimal
Dec4:   sta num
        stx num+1
        lda #<Line4
        ldx #>Line4
        bne Decimal
Dec5:   sta num
        stx num+1
        lda #<Line5
        ldx #>Line5

; Decimal: num in decimal at (A/X) + Y, without leading zeros.
Decimal:
        sta r1L
        stx r1H
        ldx #0                  ; the digits, high first
        stx any
@pow:   lda #'0'
        sta digit
@sub:   lda num
        sec
        sbc PowLo,x
        sta tmp2
        lda num+1
        sbc PowHi,x
        bcc @put
        sta num+1
        lda tmp2
        sta num
        inc digit
        bne @sub
@put:   lda digit
        cmp #'0'
        bne @show
        bit any
        bpl @next
@show:  sta (r1),y
        iny
        lda #$80
        sta any
@next:  inx
        cpx #4
        bcc @pow
        lda num
        ora #'0'
        sta (r1),y
        iny
        lda #0
        sta (r1),y
        rts
PowLo:  .byte <10000, <1000, <100, <10
PowHi:  .byte >10000, >1000, >100, >10

; Ask: the question at A/X with YES and NO: Z set for YES.
Ask:    sta askLine
        stx askLine+1
        lda #<askDlg
        sta r0L
        lda #>askDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #YES
        rts

; Tell: the message at A/X with OK; C set.
Tell:   sta msgLine
        stx msgLine+1
        lda #<msgDlg
        sta r0L
        lda #>msgDlg
        sta r0H
        jsr Dialog
        sec
        rts

TextName:       .byte "Text  Scrap", 0
PhotoName:      .byte "Photo Scrap", 0
Title:          .byte BOLDON, "Clipboard", PLAINTEXT, 0
SizeWord:       .byte "Text: ", 0
BytesWord:      .byte " bytes", 0
NoText:         .byte "Text: none", 0
PicWord:        .byte "Picture: ", 0
ByWord:         .byte " x ", 0
NoPic:          .byte "Picture: none", 0
OtherWord:      .byte "Other scraps: ", 0
ClearAsk:       .byte BOLDON, "Clear the clipboard?", PLAINTEXT, 0
NoneMsg:        .byte BOLDON, "The clipboard is empty.", PLAINTEXT, 0
FolderMsg:      .byte BOLDON, "Open a folder on drive A-D.", PLAINTEXT, 0
ExistsMsg:      .byte BOLDON, "A file of that name is there.", PLAINTEXT, 0
LargeMsg:       .byte BOLDON, "Too large to save here.", PLAINTEXT, 0
FailMsg:        .byte BOLDON, "It could not be saved.", PLAINTEXT, 0
SaveWord:       .byte BOLDON, "Save the scrap as:", PLAINTEXT, 0

showDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, 14
        .word Title
        .byte DBTXTSTR, TXT_LN_X, 28
        .word Line2
        .byte DBTXTSTR, TXT_LN_X, 40
        .word Line3
        .byte DBTXTSTR, TXT_LN_X, 54
        .word Line4
        .byte DBTXTSTR, TXT_LN_X, 66
        .word Line5
        .byte DB_USR_ROUT
        .word DrawPic
        .byte OK, DBI_X_0, DBI_Y_2
        .byte 0
askDlg: .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
askLine:
        .word 0
        .byte YES, DBI_X_0, DBI_Y_2
        .byte NO, DBI_X_2, DBI_Y_2
        .byte 0
msgDlg: .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
msgLine:
        .word 0
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0
nameDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word SaveWord
        .byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5, 16
        .byte OK, DBI_X_0, DBI_Y_2
        .byte CANCEL, DBI_X_2, DBI_Y_2
        .byte 0

; Scratch (overlay data: set anew in each call)
Line2:          .res 40
Line3:          .res SHOWN + 4
Line4:          .res 40
Line5:          .res 40
names:          .res ENTRIES * SNAME_LEN
input:          .res SNAME_LEN + 2
short:          .res SNAME_LEN
count:          .byte 0
found:          .byte 0
at:             .byte 0
tmp:            .byte 0
tmp2:           .byte 0
num:            .word 0
digit:          .byte 0
any:            .byte 0
showPic:        .byte 0
picErr:         .byte 0
extVec:         .word 0
