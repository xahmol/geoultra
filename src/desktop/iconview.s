; GeoUltra Desktop: the icon view (docs/DESKTOP.md, "Decisions": the
; user, 2026-11-11). A grid of cells, CELL_W x CELL_H pixels, as many
; columns as fit beside the sidebar (5, or 6 with the narrow one) and as
; many rows as fit under the path line; each cell the entry's 24 x 21
; icon and its name centred under it (cut at the cell's edge). GEOS
; files show their header's own icon (FE_STAT; kept in the REU, so a
; folder's icons are read once), everything else the list's 8 x 8 icon
; three times as big. The list's code does the rest: in this view its
; `rows` is the cells on a page (Derive calls IconLayout), and `step`
; (a page's columns) makes scrolling move a whole row of cells. Core
; code: ListDraw, which draws the cells, is also called from overlays.
; Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import listL, listTop, bottom, rows, viewMode, cur, row, RowEntry
        .import IsSelected, entryInfo, entryName, IconFor, Icons, TextWidth
        .import FileEngine, text, IsDotDot, stripL
        .export IconLayout, DrawCell, CellAt, IconsForget, step, gridCols, bigOk

CELL_CARDS      = 5             ; a cell: 5 cards wide (the icon on 1-3)
CELL_W          = CELL_CARDS * 8
CELL_H          = 32            ; the icon (21 rows), the name, a gap
ICON_W          = 3             ; cards
ICON_ROWS       = 21
ICON_LEN        = 1 + ICON_W * ICON_ROWS ; a BitmapUp packet: $BF, 63
ICON_PACKET     = $80 + ICON_W * ICON_ROWS ; (unique bytes, compacted)
NAME_BASE       = 30            ; the name's baseline in a cell
CACHE_BANK      = 6             ; (ovl.s: overlays $0000-$6FFF, history
CACHE_PAGE      = $90           ; $8000-$8FFF; the icons from $9000)
CACHE_N         = (BIG_PAGE * 256 - CACHE_PAGE * 256) / 64 ; entries whose
                                ; icon is kept: 440 (to the big icons)
SMALL_BYTES     = 9             ; icons.s: a packet byte and 8 rows
H_ICON          = 4             ; its icon: a $BF packet and 63 bytes

        .segment "CODE"

; IconLayout (theme.s, Derive, in the icon view): the grid's columns and
; rows, its first card, rows = the cells on a page, step = the columns.
; Destroys A, X, Y.
IconLayout:
        lda listL               ; the cards beside the sidebar
        lsr a
        lsr a
        lsr a
        sta first
        lda stripL+1            ; (the strip's card: stripL / 8)
        lsr a
        lda stripL
        ror a
        lsr a
        lsr a
        sec
        sbc first
        ldx #0
@col:   cmp #CELL_CARDS
        bcc :+
        sbc #CELL_CARDS
        inx
        bne @col
:       stx gridCols
        stx step
        lsr a                   ; the cards left over: half on each side
        clc
        adc first
        sta gridCard
        lda bottom              ; the rows: (bottom + 1 - listTop) / CELL_H
        sec
        sbc listTop
        clc
        adc #1
        ldx #0
@row:   cmp #CELL_H
        bcc :+
        sbc #CELL_H
        inx
        bne @row
:       stx gridRows
        lda #0                  ; rows = the cells on a page
        ldy gridRows
@mul:   dey
        bmi :+
        clc
        adc gridCols
        jmp @mul
:       sta rows
        rts

; DrawCell (ListDraw, the icon view): cell `row` (its entry fetched):
; the icon, the name, the selection inverted, the cursor framed.
; Destroys A, X, Y, r0-r4, r11.
DrawCell:
        lda row                 ; its column and row
        ldx #0
@div:   cmp gridCols
        bcc :+
        sbc gridCols
        inx
        bne @div
:       sta col
        asl a                   ; its card: gridCard + col * 5
        asl a
        adc col
        adc gridCard
        sta card
        sta cellX
        lda #0
        sta cellX+1
        asl cellX
        rol cellX+1
        asl cellX
        rol cellX+1
        asl cellX
        rol cellX+1
        txa                     ; its top: listTop + row * 32
        asl a
        asl a
        asl a
        asl a
        asl a
        adc listTop
        sta cellY
        jsr GetIcon
        lda #<icon
        sta r0L
        lda #>icon
        sta r0H
        ldx card
        inx
        stx r1L
        ldx cellY
        inx
        stx r1H
        lda #ICON_W
        sta r2L
        lda #ICON_ROWS
        sta r2H
        jsr BitmapUp
        jsr Name
        lda row                 ; selected: the cell inverted
        jsr RowEntry
        jsr IsSelected
        beq :+
        jsr Box
        jsr InvertRectangle
:       lda row                 ; the cursor: a frame round the cell
        jsr RowEntry
        cmp cur
        bne @end
        cpx cur+1
        bne @end
        jsr Box
        lda #$FF
        jmp FrameRectangle
@end:   rts

; Name: entryName centred under the icon (from the cell's left edge when
; it is wider than the cell, cut at its right edge).
Name:   lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        jsr TextWidth           ; r2
        lda cellX
        clc
        adc #1
        sta r11L
        lda cellX+1
        adc #0
        sta r11H
        lda r2H
        bne @put
        lda r2L
        cmp #CELL_W - 2
        bcs @put
        lda #CELL_W - 2         ; (CELL_W - 2 - width) / 2 more
        sec
        sbc r2L
        lsr a
        clc
        adc r11L
        sta r11L
        bcc @put
        inc r11H
@put:   lda cellX               ; the cell's right edge
        clc
        adc #CELL_W - 2
        sta rightMargin
        lda cellX+1
        adc #0
        sta rightMargin+1
        lda cellY
        clc
        adc #NAME_BASE
        sta r1H
        lda #<entryName
        sta r0L
        lda #>entryName
        sta r0H
        jsr PutString
        lda #<SCREEN_RIGHT
        sta rightMargin
        lda #>SCREEN_RIGHT
        sta rightMargin+1
        rts

; Box: r2-r4 = the cell's rectangle.
Box:    lda cellY
        sta r2L
        clc
        adc #CELL_H - 1
        sta r2H
        lda cellX
        sta r3L
        clc
        adc #CELL_W - 1
        sta r4L
        lda cellX+1
        sta r3H
        adc #0
        sta r4H
        rts

; CellAt (ListPress, the icon view): X = the cell under the pointer
; (mouseXPos, mouseYPos), C clear; C set when there is none.
CellAt: lda gridCard            ; x from the grid's left edge
        asl a
        asl a
        asl a
        sta tmp
        lda mouseXPos
        sec
        sbc tmp
        tay
        lda mouseXPos+1
        sbc #0
        bne @no                 ; (left of the grid, or far right)
        tya
        ldx #0
@col:   cmp #CELL_W
        bcc :+
        sbc #CELL_W
        inx
        bne @col
:       cpx gridCols
        bcs @no
        stx col
        lda mouseYPos
        sec
        sbc listTop
        bcc @no
        ldx #0
@row:   cmp #CELL_H
        bcc :+
        sbc #CELL_H
        inx
        bne @row
:       cpx gridRows
        bcs @no
        lda col                 ; cell = row * columns + column
@mul:   dex
        bmi :+
        clc
        adc gridCols
        jmp @mul
:       tax
        clc
        rts
@no:    sec
        rts

; GetIcon: icon = the entry's 24 x 21 icon: a GEOS file's own (from the
; REU when read before; else its header, then kept), otherwise the
; list's 8 x 8 one three times as big.
GetIcon:
        lda entryInfo + FI_KIND
        cmp #K_GEOS
        bne @small
        jsr Slot                ; (C set: no place in the REU for it)
        bcs @read
        lda cached,x
        and mask
        beq @read
        jsr Regs
        jmp FetchRAM
@read:  lda #<entryName         ; its header (FE_STAT, by its name in the
        sta r0L                 ; current folder)
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
        bne @small
        lda fileHeader + H_ICON
        cmp #ICON_PACKET        ; (an icon as GEOS writes it)
        bne @small
        ldx #ICON_LEN - 1
@copy:  lda fileHeader + H_ICON,x
        sta icon,x
        dex
        bpl @copy
        jsr Slot
        bcs @end
        lda cached,x
        ora mask
        sta cached,x
        jsr Regs
        jmp StashRAM
@small: jsr Generic
        bcs :+
        rts
:       jsr IconFor             ; (icons.s: none drawn big; three times)
        jmp Big
@end:   rts

; Generic: icon = the entry's 24 x 21 generic icon (tooldraw.s put them
; into the REU at the start), C clear; C set when it has none (or they
; are not there): ".." the parent folder; usb0, usb1 and sd their own;
; else by its 8 x 8 icon's kind (BigFor).
Generic:
        lda bigOk
        beq @none
        jsr IsDotDot
        bne :+
        lda #BIG_PARENT
        bne @fetch
:       lda entryInfo + FI_KIND
        cmp #K_DRIVE            ; an Ultimate root: its name longer than a
        bne @kind               ; drive letter
        lda entryName + 1
        beq @kind
        lda #BIG_SD
        ldx entryName
        cpx #'s'
        beq @fetch
        lda #BIG_USB
        bne @fetch
@kind:  jsr IconFor
        tax
        lda BigFor,x
        bmi @none
@fetch: sta slotLo              ; r1 = BIG_PAGE * 256 + n * 64
        lda #0
        sta slotHi
        jsr Regs
        lda r1H                 ; (Regs: CACHE_PAGE + n * 64; the big
        clc                     ; icons: BIG_PAGE + n * 64)
        adc #BIG_PAGE - CACHE_PAGE
        sta r1H
        lda #BIG_BANK
        sta r3L
        jsr FetchRAM
        clc
        rts
@none:  sec
        rts

; BigFor: the big icon for each 8 x 8 icon (icons.s's order), $FF none.
BigFor: .byte BIG_FOLDER, $FF, BIG_FILE, $FF, $FF, BIG_IMAGE, BIG_FILE
        .byte BIG_DRIVE, BIG_DRIVE, BIG_USB, BIG_SD
BIG_FOLDER      = 0             ; (tools/mkbigicons.py's order)
BIG_PARENT      = 1
BIG_DRIVE       = 2
BIG_FILE        = 3
BIG_IMAGE       = 4
BIG_USB         = 5
BIG_SD          = 6

; Slot: for the entry in row `row`: X = its byte in cached, mask = its
; bit, slotLo/Hi = its number; C set when it is past CACHE_N.
Slot:   lda row
        jsr RowEntry            ; A/X = its number
        sta slotLo
        stx slotHi
        cpx #>CACHE_N
        bcc :+
        bne @no
        cmp #<CACHE_N
        bcs @no
:       and #7
        tay
        lda #1
@b:     dey
        bmi :+
        asl a
        bne @b
:       sta mask
        lda slotHi              ; X = number / 8
        lsr a
        lda slotLo
        ror a
        lsr a
        lsr a
        tax
        clc
        rts
@no:    sec
        rts

; Regs: r0-r3L for the entry's icon in the REU (CACHE_BANK, $9000 +
; number * 64) <-> icon.
Regs:   lda #<icon
        sta r0L
        lda #>icon
        sta r0H
        lda slotLo              ; number * 64: (number << 6)
        sta r1L
        lda slotHi
        sta r1H
        ldx #6
@sh:    asl r1L
        rol r1H
        dex
        bne @sh
        lda r1H
        clc
        adc #CACHE_PAGE
        sta r1H
        lda #ICON_LEN
        sta r2L
        lda #0
        sta r2H
        lda #CACHE_BANK
        sta r3L
        rts

; IconsForget (list.s, ListRead: a folder read): no icon kept.
IconsForget:
        lda #0
        ldx #CACHE_N / 8 - 1
@clr:   sta cached,x
        dex
        bpl @clr
        rts

; Big: icon = small icon A (icons.s) three times as big: each of its
; first 7 rows three times (21 rows), each pixel three wide (24).
Big:    sta tmp                 ; r4 = its rows: Icons + A * 9 + 1
        asl a
        asl a
        asl a
        adc tmp
        adc #<(Icons + 1)
        sta r4L
        lda #>(Icons + 1)
        adc #0
        sta r4H
        lda #ICON_PACKET
        sta icon
        ldx #1
        ldy #0
@row:   lda (r4),y
        jsr Triple
        lda #3
        sta tmp
@rep:   lda wide
        sta icon,x
        lda wide+1
        sta icon+1,x
        lda wide+2
        sta icon+2,x
        inx
        inx
        inx
        dec tmp
        bne @rep
        iny
        cpy #ICON_ROWS / 3
        bcc @row
        rts

; Triple: wide (3 bytes) = byte A with each bit three times. Keeps X, Y.
Triple: sta tmp2
        lda #8
        sta bits
@bit:   asl tmp2                ; (C: the bit)
        php
        rol wide+2
        rol wide+1
        rol wide
        plp
        php
        rol wide+2
        rol wide+1
        rol wide
        plp
        rol wide+2
        rol wide+1
        rol wide
        dec bits
        bne @bit
        rts

; Scratch in the end of side.s's text buffer: free while the list is
; drawn (its other users, the INI and theme files and the paths built
; for actions, are done by then; side.s lists them).
icon            = text + TEXT_MAX + 1 - ICON_LEN
info            = icon - 16

        .segment "DATA"

step:           .byte 1         ; scrolling: 1 (the list) or the columns
bigOk:          .byte 0         ; 1: the generic icons are in the REU

        .segment "BSS"

gridCols:       .res 1
gridRows:       .res 1
gridCard:       .res 1          ; the grid's first card
first:          .res 1
col:            .res 1
card:           .res 1
cellX:          .res 2
cellY:          .res 1
slotLo:         .res 1
slotHi:         .res 1
mask:           .res 1
tmp:            .res 1
tmp2:           .res 1
bits:           .res 1
wide:           .res 3
cached:         .res CACHE_N / 8
        .assert ICON_LEN <= 64, error, "a cache slot holds 64 bytes"
