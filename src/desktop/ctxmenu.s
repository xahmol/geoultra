; GeoUltra Desktop: the context menu and Info (overlay 7, ovl.s;
; docs/DESKTOP.md, "Toolbar and right-click": the user's decisions of
; 2026-11-11). The right mouse button (guMouse2, the 1351 driver) opens
; a menu at the pointer: open, copy, cut, paste, rename, delete, info,
; favourite, new folder. Popup draws it (in the menu bar's colours, a
; frame round it), follows the pointer (the item under it inverted) and
; returns the item clicked; the core does it (most actions are overlay
; 2's: an overlay calls no other). Info shows an entry's name, kind,
; size, date and GEOS class in a dialog (FE_STAT, so an Ultimate file's
; real size too). Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import MenuNeutral, Recover, Dialog, FileEngine, entryInfo, entryName
        .import cur, count, Fetch, IsDotDot
        .export Ov_Popup, Ov_Info
Ov_Popup = Popup
Ov_Info = Info

GetNextChar     = $C2A7         ; GEOS jump table
ITEMS_N         = 11            ; (CTX_* in desktop.inc: their order)
ITEM_H          = 14            ; as GEOS's menus
BOX_W           = 92
BOX_H           = ITEMS_N * ITEM_H + 2
TEXT_DX         = 6             ; an item's text: from the box's left edge
TEXT_DY         = 10            ; its baseline below the item's top
KEY_ESC         = 27
NONE            = $FF
LINE_LEN        = 40            ; an Info line, at most
NAME_SHOWN      = 26            ; Info's name: its first characters (bold,
                                ; within the dialog's 176 pixels)

        .segment "OV7"

; Popup (list.s, RightPress): the context menu at the pointer; A = the
; item clicked (0 to ITEMS_N - 1), NONE when it was closed without one
; (a click outside it, RUN/STOP, ESC or the right button again). Runs
; its own loop (MainLoop waits meanwhile). Destroys A, X, Y, r0-r11.
Popup:  lda dispBufferOn         ; (drawn on the foreground only: the
        sta bufSave             ; background keeps the desktop, which
        lda #ST_WR_FORE         ; Recover gives back)
        sta dispBufferOn
        jsr Place
        lda #<hdr               ; the menu bar's colours under it
        sta r0L
        lda #>hdr
        sta r0H
        jsr MenuNeutral
        jsr BoxRegs             ; cleared, framed
        lda #0
        jsr SetPattern
        jsr Rectangle
        jsr BoxRegs
        lda #$FF
        jsr FrameRectangle
        lda #0
        sta at
@item:  jsr ItemText            ; each item's text
        inc at
        lda at
        cmp #ITEMS_N
        bcc @item
        lda #NONE
        sta hover
        php                     ; (a press before the menu: not ours)
        sei
        lda pressFlag
        and #$FF - MOUSE_BIT
        sta pressFlag
        plp
@loop:  jsr Under               ; the item under the pointer inverted
        cmp hover
        beq @input
        pha
        lda hover
        jsr Invert              ; (the old one back; NONE: nothing)
        pla
        sta hover
        jsr Invert
@input: lda guMouse2            ; the right button again: closed
        and #$40
        beq :+
        php
        sei
        lda guMouse2
        and #$FF - $40
        sta guMouse2
        plp
        lda #NONE
        bne @close
:       jsr GetNextChar         ; RUN/STOP or ESC: closed
        cmp #KEY_STOP
        beq @none
        cmp #KEY_ESC
        beq @none
        lda pressFlag           ; the left button: pressed?
        and #MOUSE_BIT
        beq @loop
        php
        sei
        lda pressFlag
        and #$FF - MOUSE_BIT
        sta pressFlag
        plp
        lda mouseData
        bmi @loop               ; (a release: on)
        lda hover               ; pressed: the item where the pointer is
        jsr Invert              ; now (NONE outside), not the one last
        jsr Under               ; shown under it
        jmp @close
@none:  lda #NONE
@close: sta hover
        jsr BoxRegs             ; the screen and its colours back
        jsr Recover
        lda bufSave
        sta dispBufferOn
        lda hover
        rts

; Place: the box's corners at the pointer, kept on the screen (x0-x1,
; y0-y1), and hdr (a menu table's first 6 bytes) for MenuNeutral.
Place:  lda mouseXPos+1         ; x0 = min(pointer x, 319 - BOX_W)
        bne @right
        lda mouseXPos
        cmp #<(SCREEN_RIGHT - BOX_W)
        bcc :+
@right: lda #<(SCREEN_RIGHT - BOX_W)
:       sta x0
        clc
        adc #BOX_W
        sta x1
        lda #0
        adc #0
        sta x1+1
        lda mouseYPos           ; y0 = min(pointer y, 199 - BOX_H)
        cmp #199 - BOX_H
        bcc :+
        lda #199 - BOX_H
:       sta y0
        clc
        adc #BOX_H
        sta y1
        sta hdr+1
        lda y0
        sta hdr
        lda x0
        sta hdr+2
        lda #0
        sta hdr+3
        lda x1
        sta hdr+4
        lda x1+1
        sta hdr+5
        rts

; BoxRegs: r2-r4 = the box.
BoxRegs:
        lda y0
        sta r2L
        lda y1
        sta r2H
        lda x0
        sta r3L
        lda #0
        sta r3H
        lda x1
        sta r4L
        lda x1+1
        sta r4H
        rts

; ItemText: item `at`'s text in its place.
ItemText:
        lda at
        jsr ItemTop
        clc
        adc #TEXT_DY
        sta r1H
        lda x0
        clc
        adc #TEXT_DX
        sta r11L
        lda #0
        sta r11H
        ldx at
        lda TextLo,x
        sta r0L
        lda TextHi,x
        sta r0H
        jmp PutString

; ItemTop: A = item A's top pixel row (y0 + 1 + A * ITEM_H).
ItemTop:
        tax
        lda y0
        clc
        adc #1
@add:   dex
        bmi @end
        clc
        adc #ITEM_H
        bne @add
@end:   rts

; Under: A = the item under the pointer, NONE when it is outside.
Under:  lda mouseXPos+1
        cmp x1+1                ; x0 <= x < x1 (x0 < 256)
        bcc :+
        bne @none
        lda mouseXPos
        cmp x1
        bcs @none
:       lda mouseXPos+1
        bne @y
        lda mouseXPos
        cmp x0
        bcc @none
@y:     lda mouseYPos           ; y0 < y < y1: (y - y0 - 1) / ITEM_H
        sec
        sbc y0
        beq @none
        bcc @none
        sbc #1
        ldx #0
@row:   cmp #ITEM_H
        bcc @got
        sbc #ITEM_H
        inx
        bne @row
@got:   txa
        cmp #ITEMS_N
        bcs @none
        rts
@none:  lda #NONE
        rts

; Invert: item A's row inverted (NONE: nothing).
Invert: cmp #NONE
        beq @end
        jsr ItemTop
        sta r2L
        clc
        adc #ITEM_H - 1
        sta r2H
        lda x0
        clc
        adc #1
        sta r3L
        lda #0
        sta r3H
        lda x1
        sec
        sbc #1
        sta r4L
        lda x1+1
        sbc #0
        sta r4H
        jmp InvertRectangle
@end:   rts

; --- Info ----------------------------------------------------------------

; Info (the context menu, the toolbar's info button): the entry under
; the cursor in a dialog: its name, kind, size, date and GEOS class
; (FE_STAT: the size an Ultimate listing leaves out too). Nothing for
; ".." or an empty folder.
Info:   lda count
        ora count+1
        beq @end
        lda cur
        ldx cur+1
        jsr Fetch
        jsr IsDotDot
        beq @end
        ldx #0                  ; line1: the name in bold (cut to fit)
        lda #BOLDON
        sta line1
@name:  lda entryName,x
        beq @named
        sta line1 + 1,x
        inx
        cpx #NAME_SHOWN
        bcc @name
@named: lda #PLAINTEXT
        sta line1 + 1,x
        lda #0
        sta line1 + 2,x
        lda #<entryName         ; FE_STAT by its name in the current folder
        sta r0L
        lda #>entryName
        sta r0H
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        beq :+
        ldx #INFO_LEN - 1       ; (it failed: what the listing said)
@copy:  lda entryInfo,x
        sta info,x
        dex
        bpl @copy
:       jsr KindLine
        jsr SizeLine
        jsr DateLine
        jsr ClassLine
        lda #<infoDlg
        sta r0L
        lda #>infoDlg
        sta r0H
        jmp Dialog
@end:   rts

; KindLine: line2 = "Kind: " and the entry's kind (GEOS files: by their
; GEOS type).
KindLine:
        lda #0                  ; (into line2)
        sta which
        ldy #0
        lda #<KindWord
        ldx #>KindWord
        jsr Cat
        ldx info + FI_KIND
        cpx #K_GEOS
        bne @kind
        lda info + FI_GTYPE     ; a GEOS file: its GEOS type's name
        cmp #GTYPES_N
        bcc :+
        lda #0
:       tax
        lda GLo,x
        pha
        lda GHi,x
        tax
        pla
        jmp CatEnd
@kind:  cpx #KINDS_N
        bcc :+
        ldx #KINDS_N - 1
:       lda KLo,x
        pha
        lda KHi,x
        tax
        pla
        jmp CatEnd

; SizeLine: line3 = "Size: " and the size: blocks on GEOS drives (and
; KB), bytes on the Ultimate (KB from 64 KB); empty for folders and
; drives.
SizeLine:
        lda #1                  ; (into line3)
        sta which
        ldy #0
        lda info + FI_KIND
        cmp #K_GEOS
        beq @blocks
        cmp #K_CBM
        beq @blocks
        cmp #K_UFILE
        beq @bytes
        jmp Empty
@blocks:
        jsr SizeWord
        lda info + FI_SIZE
        ldx info + FI_SIZE + 1
        jsr Decimal
        lda #<BlocksWord
        ldx #>BlocksWord
        jmp CatEnd
@bytes: jsr SizeWord
        lda info + FI_SIZE + 2  ; from 64 KB: in KB (bytes / 1024)
        ora info + FI_SIZE + 3
        bne @kb
        lda info + FI_SIZE
        ldx info + FI_SIZE + 1
        jsr Decimal
        lda #<BytesWord
        ldx #>BytesWord
        jmp CatEnd
@kb:    lda info + FI_SIZE + 1  ; bytes 1-3 >> 2
        sta numL
        lda info + FI_SIZE + 2
        sta numH
        lda info + FI_SIZE + 3
        lsr a
        ror numH
        ror numL
        lsr a
        ror numH
        ror numL
        lda numL
        ldx numH
        jsr Decimal
        lda #<KBWord
        ldx #>KBWord
        jmp CatEnd

; SizeWord: "Size: " into line3 (Y on).
SizeWord:
        lda #<SizeText
        ldx #>SizeText
        jmp Cat

; DateLine: line4 = "Date: 12 Nov 1986  21:42" for GEOS files (as their
; directory entry has it), else empty.
; Empty4: line4 empty (DateLine: no date).
Empty4: lda #0
        sta line4
        rts
DateLine:
        ldy #0
        lda info + FI_KIND
        cmp #K_GEOS
        bne Empty4
        lda info + FI_DATE + 1  ; (a month 1-12, else no date)
        beq Empty4
        cmp #13
        bcs Empty4
        lda #<DateWord
        ldx #>DateWord
        jsr Cat4
        lda info + FI_DATE + 2  ; day
        ldx #0
        jsr Dec4
        lda #' '
        jsr Put4
        lda info + FI_DATE + 1  ; month: its three letters ((m - 1) * 3)
        sec
        sbc #1
        sta tmpX
        asl a
        adc tmpX
        tax
        lda MonN,x
        jsr Put4
        lda MonN + 1,x
        jsr Put4
        lda MonN + 2,x
        jsr Put4
        lda #' '
        jsr Put4
        lda info + FI_DATE      ; year: 19yy from 80, else 20yy
        cmp #80
        lda #<1900
        ldx #>1900
        bcs :+
        lda #<2000
        ldx #>2000
:       clc
        adc info + FI_DATE
        bcc :+
        inx
:       jsr Dec4
        lda #' '
        jsr Put4
        jsr Put4
        lda info + FI_DATE + 3  ; hour, minute
        ldx #0
        jsr Dec4
        lda #':'
        jsr Put4
        lda info + FI_DATE + 4
        cmp #10
        bcs :+
        pha
        lda #'0'
        jsr Put4
        pla
:       ldx #0
        jsr Dec4
        lda #0
        sta line4,y
        rts

; ClassLine: line5 = "Class: " and a GEOS file's permanent name (its
; header's class, cut at its first zero or 20 characters), else empty.
ClassLine:
        lda #0
        sta line5
        lda info + FI_KIND
        cmp #K_GEOS
        bne @end
        ldy #0
        ldx #0
@w:     lda ClassWord,x
        beq @name
        sta line5,y
        inx
        iny
        bne @w
@name:  ldx #0
@ch:    lda fileHeader + O_GHFNAME,x
        beq @zero
        cmp #' '                ; (control characters: not shown)
        bcc @zero
        sta line5,y
        iny
        inx
        cpx #20
        bcc @ch
@zero:  lda #0
        sta line5,y
@end:   rts

; Empty: line3 empty.
Empty:  lda #0
        sta line3
        rts

; Cat: the text at A/X into line2 or line3 (which) from Y; CatEnd: the
; same, then its end. Y on.
Cat:    sta r0L
        stx r0H
        sty tmpY
        ldy #0
@ch:    lda (r0),y
        beq @end
        sty r1L
        ldy tmpY
        jsr PutL
        inc tmpY
        ldy r1L
        iny
        bne @ch
@end:   ldy tmpY
        rts
CatEnd: jsr Cat
        lda #0
        jmp PutL

; PutL: A into the line being built (line2 while which is 0, else
; line3) at Y. Keeps A, Y.
PutL:   ldx which
        beq :+
        sta line3,y
        rts
:       sta line2,y
        rts

; Cat4, Put4, Dec4: the same into line4.
Cat4:   sta r0L
        stx r0H
        sty tmpY
        ldy #0
@ch:    lda (r0),y
        beq @end
        sty r1L
        ldy tmpY
        sta line4,y
        inc tmpY
        ldy r1L
        iny
        bne @ch
@end:   ldy tmpY
        rts
Put4:   sta line4,y
        iny
        rts
Dec4:   jsr Digits
        ldx #0
@c:     lda digits,x
        beq @end
        jsr Put4
        inx
        bne @c
@end:   rts

; Decimal: A/X in decimal into the line being built (PutL) at Y; Y on.
Decimal:
        jsr Digits
        ldx #0
@c:     lda digits,x
        beq @end
        stx tmpX
        jsr PutL
        ldx tmpX
        iny
        inx
        bne @c
@end:   rts

; Digits: digits = A/X in decimal, zero-ended, no leading zeros.
; Keeps Y.
Digits: sta numL
        stx numH
        sty tmpY
        ldy #0                  ; each power of ten
        sty lead
        ldx #0
@pow:   lda #'0'
        sta digit
@sub:   lda numL
        sec
        sbc PowLo,x
        pha
        lda numH
        sbc PowHi,x
        bcc @next
        sta numH
        pla
        sta numL
        inc digit
        bne @sub
@next:  pla
        lda digit
        cmp #'0'
        bne @put
        ldy lead                ; (no leading zeros; the last one stays)
        beq @skip
@put:   ldy lead
        sta digits,y
        inc lead
@skip:  inx
        cpx #4
        bcc @pow
        lda numL                ; the ones
        ora #'0'
        ldy lead
        sta digits,y
        iny
        lda #0
        sta digits,y
        ldy tmpY
        rts
PowLo:  .byte <10000, <1000, <100, <10
PowHi:  .byte >10000, >1000, >100, >10

; The menu's items (sentence case, the desktop's menus' words) in
; CTX_* order (desktop.inc).
TextLo: .byte <T0, <T1, <T2, <T3, <T4, <T5, <T6, <T7, <T8, <T9, <T10
TextHi: .byte >T0, >T1, >T2, >T3, >T4, >T5, >T6, >T7, >T8, >T9, >T10
T0:     .byte "open", 0
T1:     .byte "copy", 0
T2:     .byte "cut", 0
T3:     .byte "paste", 0
T4:     .byte "rename", 0
T5:     .byte "delete", 0
T6:     .byte "info", 0
T7:     .byte "favourite", 0
T8:     .byte "new folder", 0
T9:     .byte "copy to other", 0
T10:    .byte "move to other", 0
        .assert ITEMS_N = CTX_N, error, "an item per CTX_ code"

KindWord:       .byte "Kind: ", 0
SizeText:       .byte "Size: ", 0
DateWord:       .byte "Date: ", 0
ClassWord:      .byte "Class: ", 0
BlocksWord:     .byte " blocks", 0
BytesWord:      .byte " bytes", 0
KBWord:         .byte " KB", 0
; the kinds (FE_STAT's info: 0 root, 1 drive, 2 folder, 3 GEOS file,
; 4 CBM file, 5 Ultimate file, 6 Ultimate folder)
K0:     .byte "all drives", 0
K1:     .byte "drive", 0
K2:     .byte "folder", 0
K3:     .byte "GEOS file", 0
K4:     .byte "CBM file", 0
K5:     .byte "file on the Ultimate", 0
K6:     .byte "folder on the Ultimate", 0
KINDS_N = 7
KLo:    .byte <K0, <K1, <K2, <K3, <K4, <K5, <K6
KHi:    .byte >K0, >K1, >K2, >K3, >K4, >K5, >K6
; the GEOS types' names (HG2G: 0 non-GEOS ... 15 INPUT_128)
GTYPES_N = 16
GLo:    .byte <G0, <G1, <G2, <G3, <G4, <G5, <G6, <G7, <G8, <G9, <G10, <G11, <G12, <G13, <G14, <G15
GHi:    .byte >G0, >G1, >G2, >G3, >G4, >G5, >G6, >G7, >G8, >G9, >G10, >G11, >G12, >G13, >G14, >G15
G0:     .byte "GEOS file", 0
G1:     .byte "BASIC program", 0
G2:     .byte "machine code program", 0
G3:     .byte "data file", 0
G4:     .byte "system file", 0
G5:     .byte "desk accessory", 0
G6:     .byte "GEOS application", 0
G7:     .byte "GEOS document", 0
G8:     .byte "font", 0
G9:     .byte "printer driver", 0
G10:    .byte "input driver", 0
G11:    .byte "disk driver", 0
G12:    .byte "boot file", 0
G13:    .byte "temporary file", 0
G14:    .byte "auto-exec program", 0
G15:    .byte "input driver (128)", 0
MonN:   .byte "JanFebMarAprMayJunJulAugSepOctNovDec"

; Info's dialog: the name in bold, then four lines (measured: a line
; holds LINE_LEN characters, the dialog's text 176 pixels).
infoDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, 14
        .word line1
        .byte DBTXTSTR, TXT_LN_X, 26
        .word line2
        .byte DBTXTSTR, TXT_LN_X, 38
        .word line3
        .byte DBTXTSTR, TXT_LN_X, 50
        .word line4
        .byte DBTXTSTR, TXT_LN_X, 62
        .word line5
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0

; Scratch (overlay data: fetched anew with the overlay; Info's dialog
; runs while it is in)
hdr:    .res 6
x0:     .res 1
x1:     .res 2
y0:     .res 1
y1:     .res 1
at:     .res 1
hover:  .res 1
which:  .res 1
bufSave:        .res 1
tmpX:   .res 1
tmpY:   .res 1
numL:   .res 1
numH:   .res 1
lead:   .res 1
digit:  .res 1
digits: .res 6
info:   .res INFO_LEN
line1:  .res NAME_SHOWN + 3
line2:  .res LINE_LEN
line3:  .res LINE_LEN
line4:  .res LINE_LEN
line5:  .res LINE_LEN
