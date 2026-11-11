; GeoUltra Desktop: the list (docs/DESKTOP.md, step D2). A folder's
; entries are read once (FE_OPENDIR, FE_READDIR) into an entry table in
; the application's REU, ENTRY_SIZE bytes each from bank ENTRY_BANK on
; (up to ENTRY_MAX), in directory order; the list area shows ROWS of
; them from `top`, with a scroll strip at the right edge. The selection
; is a bit per entry (`sel`), the cursor (`cur`) the entry the keys move.
; Mouse: a click selects the entry under it alone, SHIFT+click the range
; from the cursor, C=+click toggles it; in the strip, above or below its
; thumb a page up or down. Keys: cursor up and down move the cursor (the
; selection follows), with C= held they extend the selection (on the
; C64 cursor up is SHIFT + CRSR DOWN, so SHIFT cannot extend), HOME to
; the first entry. Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Open, Up, Into
        .export ListRead, ListDraw, ListPress, ListKey, path, count
        .export entryInfo, entryName, cur, top, sel, IsSelected, Fetch
        .export Modifiers, mods, IsDotDot

; The list's rows (desktop.inc has the rest of the layout)
ROWS            = 17
LIST_BOTTOM     = LIST_TOP + ROWS * ROW_H - 1

; The entry table
ENTRY_SIZE      = 128           ; info (16), long name (61), spare
ENTRY_BANK      = 1             ; banks 1-4 of the application's REU
ENTRY_MAX       = 2048
ENTRY_LEN       = INFO_LEN + NAME_LEN

; CIA 1 for SHIFT and C= at a click (the keyboard matrix, as gush reads
; CTRL)
CIA1_PA         = $DC00
CIA1_PB         = $DC01
CPU_PORT        = $01
RAM_IO          = $35

        .segment "CODE"

; ListRead: the current folder (FE_PWD to path) read into the entry
; table; count entries, top, cur 0, nothing selected. Below "/" the
; first entry is "..", a folder (Open goes up; the actions leave it out,
; IsDotDot).
ListRead:
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FE_PWD
        jsr FileEngine
        lda #0
        sta count
        sta count+1
        sta top
        sta top+1
        sta cur
        sta cur+1
        jsr ClearSel
        lda path + 1            ; below "/": ".." first
        beq @read
        ldx #INFO_LEN - 1
        lda #0
@info:  sta entryInfo,x
        dex
        bpl @info
        lda #K_FOLDER
        sta entryInfo + FI_KIND
        lda #'.'
        sta entryName
        sta entryName + 1
        lda #0
        sta entryName + 2
        tax
        jsr Place
        jsr StashRAM
        inc count
@read:  lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        bne @end
@entry: lda count+1             ; (the table full: the rest left out)
        cmp #>ENTRY_MAX
        bcs @close
        lda #<entryInfo
        sta r1L
        lda #>entryInfo
        sta r1H
        lda #<entryName
        sta r2L
        lda #>entryName
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        lda count
        ldx count+1
        jsr Place
        jsr StashRAM
        inc count
        bne @entry
        inc count+1
        bne @entry
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@end:   rts

; Fetch: entry A/X (low, high) into entryInfo and entryName.
Fetch:  jsr Place
        jmp FetchRAM

; Place: r0-r3 for entry A/X (low, high): entryInfo <-> its place in the
; REU (bank ENTRY_BANK + n / 512, (n mod 512) * 128).
Place:  sta r1H                 ; n * 128: low byte (n & 1) << 7, high
        txa                     ; byte (n >> 1) & $FF
        lsr a                   ; (n / 512 = high byte / 2)
        sta r3L
        lda r1H
        ror a
        sta r1H                 ; (bits 1-8 of n: the page)
        lda #0
        ror a
        sta r1L                 ; (bit 0 of n: $80 or 0)
        lda r3L                 ; bank: ENTRY_BANK + n / 512
        clc
        adc #ENTRY_BANK
        sta r3L
        lda #<entryInfo
        sta r0L
        lda #>entryInfo
        sta r0H
        lda #ENTRY_LEN
        sta r2L
        lda #0
        sta r2H
        rts

; ListDraw: the path line, ROWS entries from top (each inverted when
; selected), and the scroll strip.
ListDraw:
        lda #0
        jsr SetPattern
        lda #MENU_BOTTOM + 1
        sta r2L
        lda #LIST_BOTTOM
        sta r2H
        lda #LIST_LEFT
        sta r3L
        lda #0
        sta r3H
        lda #<(STRIP_LEFT - 1)
        sta r4L
        lda #>(STRIP_LEFT - 1)
        sta r4H
        jsr Rectangle
        lda #<path
        ldx #>path
        ldy #PATH_Y
        jsr Text
        lda #0
        sta row
@row:   jsr RowEntry            ; entry top + row (C set: past the end)
        bcs @strip
        jsr Fetch
        jsr Mark
        lda row
        jsr RowY
        clc
        adc #BASELINE
        tay
        lda #<entryName
        ldx #>entryName
        jsr Text
        lda row                 ; selected: inverted
        jsr RowEntry
        jsr IsSelected
        beq :+
        lda row
        jsr Invert
:       inc row
        lda row
        cmp #ROWS
        bcc @row
@strip: jmp Strip

; RowEntry: A/X = entry top + row; C set when it is past the last.
RowEntry:
        lda row
        clc
        adc top
        pha
        lda top+1
        adc #0
        tax
        pla
        cpx count+1             ; (A/X >= count: C set)
        bne :+
        cmp count
:       rts

; RowY: A = row A's top pixel row.
RowY:   sta tmp
        asl a
        asl a
        asl a
        clc
        adc tmp                 ; (* 9)
        adc #LIST_TOP
        rts

; Invert: row A inverted (selected, or the cursor's frame).
Invert: jsr RowY
        sta r2L
        clc
        adc #ROW_H - 1
        sta r2H
        lda #LIST_LEFT
        sta r3L
        lda #0
        sta r3H
        lda #<(STRIP_LEFT - 2)
        sta r4L
        lda #>(STRIP_LEFT - 2)
        sta r4H
        jmp InvertRectangle

; Text: the text at A/X at the list's left edge + 2, baseline Y, clipped
; before the strip.
Text:   sta r0L
        stx r0H
        sty r1H
        lda #LIST_LEFT + 2
        sta r11L
        lda #0
        sta r11H
        lda #<(STRIP_LEFT - 2)
        sta rightMargin
        lda #>(STRIP_LEFT - 2)
        sta rightMargin+1
        jsr PutString
        lda #<SCREEN_RIGHT
        sta rightMargin
        lda #>SCREEN_RIGHT
        sta rightMargin+1
        rts

; Mark: "/" after entryName when entryInfo says folder or drive.
Mark:   lda entryInfo + FI_KIND
        cmp #K_FOLDER
        beq @slash
        cmp #K_UDIR
        beq @slash
        cmp #K_DRIVE
        bne @end
@slash: ldy #$FF
@len:   iny
        lda entryName,y
        bne @len
        cpy #NAME_LEN - 2
        bcs @end
        lda #'/'
        sta entryName,y
        lda #0
        sta entryName + 1,y
@end:   rts

; Strip: the scroll strip: a frame, its thumb at top / count of its
; height (the whole strip when everything fits).
Strip:  lda #0
        jsr SetPattern
        jsr StripRect
        jsr Rectangle
        jsr StripRect
        lda #$FF
        jsr FrameRectangle
        lda count+1             ; everything on one screen: no thumb
        bne @thumb
        lda count
        cmp #ROWS + 1
        bcs @thumb
        rts
@thumb: jsr ThumbRows           ; r2L-r2H the thumb's rows
        lda #1
        jsr SetPattern
        lda #<(STRIP_LEFT + 1)
        sta r3L
        lda #>(STRIP_LEFT + 1)
        sta r3H
        lda #<(SCREEN_RIGHT - 1)
        sta r4L
        lda #>(SCREEN_RIGHT - 1)
        sta r4H
        jmp Rectangle

; StripRect: r2-r4 = the strip.
StripRect:
        lda #LIST_TOP
        sta r2L
        lda #LIST_BOTTOM
        sta r2H
        lda #<STRIP_LEFT
        sta r3L
        lda #>STRIP_LEFT
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        rts

; ThumbRows: r2L/r2H = the thumb's first and last pixel row: the strip's
; height (H) times top / count and (top + ROWS) / count. Counts above 255
; are scaled down by 8 first (an approximate thumb is enough).
ThumbRows:
        lda top
        ldx top+1
        jsr Scale
        sta r2L
        lda top
        clc
        adc #ROWS
        tay
        lda top+1
        adc #0
        tax
        tya
        jsr Scale
        sta r2H
        lda r2L
        clc
        adc #LIST_TOP
        sta r2L
        lda r2H
        clc
        adc #LIST_TOP - 1
        cmp #LIST_BOTTOM
        bcc :+
        lda #LIST_BOTTOM
:       sta r2H
        rts

; Scale: A/X (an entry number) * H / count, H = the strip's height.
Scale:  sta numL
        stx numH
        lda count
        sta denL
        lda count+1
        sta denH
@fit:   lda denH                ; both under 256
        ora numH
        beq @mul
        lsr denH
        ror denL
        lsr numH
        ror numL
        jmp @fit
@mul:   lda numL                ; numL * H (16 bits) / denL
        sta mulL
        lda #0
        sta mulH
        ldx #LIST_BOTTOM - LIST_TOP     ; H - 1 additions
        lda numL
@add:   pha
        clc
        adc mulL
        sta mulL
        bcc :+
        inc mulH
:       pla
        dex
        bne @add
        lda denL                ; mulH:mulL / denL
        beq @zero
        ldx #0
@div:   lda mulL
        sec
        sbc denL
        tay
        lda mulH
        sbc #0
        bcc @done
        sta mulH
        sty mulL
        inx
        bne @div
@done:  txa
        rts
@zero:  lda #0
        rts

; --- The selection -----------------------------------------------------

; ClearSel: nothing selected.
ClearSel:
        lda #0
        tay
@clr:   sta sel,y
        iny
        bne @clr
        rts

; IsSelected: Z clear when entry A/X is selected.
IsSelected:
        jsr Locate
        and sel,x
        rts

; Select (A/X, Y: 0 off, 1 on, 2 toggle).
Select: sty mode
        jsr Locate
        ldy mode
        beq @off
        cpy #1
        beq @on
        eor sel,x
        sta sel,x
        rts
@on:    ora sel,x
        sta sel,x
        rts
@off:   eor #$FF
        and sel,x
        sta sel,x
        rts

; Locate: X = the byte of entry A/X in sel (n / 8), A = its bit.
Locate: sta tmp
        stx tmpH
        and #7
        tay
        lda #0
        sec
@bit:   rol a
        dey
        bpl @bit
        pha
        lsr tmpH                ; n / 8
        ror tmp
        lsr tmpH
        ror tmp
        lsr tmpH
        ror tmp
        ldx tmp
        pla
        rts

; --- Input -------------------------------------------------------------

; IsDotDot: Z set when entryName is "..".
IsDotDot:
        lda entryName
        cmp #'.'
        bne @end
        lda entryName + 1
        cmp #'.'
        bne @end
        lda entryName + 2
@end:   rts

; PathPress (ListPress: a press on the path line): the folder whose part
; of the path the pointer is on (the system font's widths from the
; line's start); the last part, the current folder, does nothing. C
; clear (the list's).
PathPress:
        lda #LIST_LEFT + 2      ; (Text's x)
        sta numL
        lda #0
        sta numH
        tay
@ch:    lda path,y
        beq @done               ; (past the end: nothing)
        sty tmp
        jsr GetCharWidth
        clc
        adc numL
        sta numL
        bcc :+
        inc numH
:       ldy tmp
        lda mouseXPos+1         ; the pointer before this character's end?
        cmp numH
        bcc @found
        bne @next
        lda mouseXPos
        cmp numL
        bcc @found
@next:  iny
        bne @ch
@found: cpy #0                  ; its part's end: the next "/" (the root's
        bne @end                ; "/" ends at 1)
        iny
        bne @cut
@end:   lda path,y
        beq @done               ; (the last part: the current folder)
        cmp #'/'
        beq @cut
        iny
        bne @end
@cut:   tya
        tax
        ldy #0
@copy:  lda path,y
        sta cutPath,y
        iny
        dex
        bne @copy
        lda #0
        sta cutPath,y
        lda #<cutPath
        ldx #>cutPath
        jsr Into
@done:  clc
        rts

; ListPress (a mouse press in the list area or the strip; desktop.s).
; C clear when it was the list's.
ListPress:
        lda mouseYPos
        cmp #LIST_TOP
        bcs :+
        cmp #MENU_BOTTOM + 2    ; the path line
        bcc @out
        lda mouseXPos+1
        bne PathPress
        lda mouseXPos
        cmp #LIST_LEFT
        bcs PathPress
        bcc @out
:
        cmp #LIST_BOTTOM + 1
        bcc :+
@out:   sec                     ; (not the list's)
        rts
@toStrip:
        jmp @strip
:       lda mouseXPos+1         ; the strip?
        cmp #>STRIP_LEFT
        bcc @list
        bne @toStrip
        lda mouseXPos
        cmp #<STRIP_LEFT
        bcs @toStrip
@list:  lda mouseXPos+1
        bne :+
        lda mouseXPos
        cmp #LIST_LEFT
        bcc @out
:       lda mouseYPos           ; the row
        sec
        sbc #LIST_TOP
        ldx #0
@r:     cmp #ROW_H
        bcc @got
        sbc #ROW_H
        inx
        bne @r
@got:   stx row
        jsr RowEntry
        bcs @done               ; (below the last entry)
        sta pick
        stx pick+1
        jsr Double              ; (the same entry clicked again in time)
        bcs @open
        jsr Modifiers
        lda mods
        and #MOD_CBM
        bne @toggle
        lda mods
        and #MOD_SHIFT
        bne @range
        jsr ClearSel            ; alone
        lda pick
        ldx pick+1
        ldy #1
        jsr Select
        jmp @cursor
@toggle:
        lda pick
        ldx pick+1
        ldy #2
        jsr Select
        jmp @cursor
@range: jsr Range               ; cursor .. pick selected
@cursor:
        lda pick
        sta cur
        lda pick+1
        sta cur+1
@done:  jsr ListDraw
        clc
        rts
@open:  lda pick                ; a double click: the entry opened
        sta cur
        lda pick+1
        sta cur+1
        jsr Open
        clc
        rts
@strip: lda mouseYPos           ; above or below the thumb: a page
        pha
        jsr ThumbRows
        pla
        cmp r2L
        bcc @up
        jsr PageDown
        jmp @redraw
@up:    jsr PageUp
@redraw:
        jsr ListDraw
        clc
        rts
@no:    sec
        rts

; Double: C set when pick is the entry clicked last and GEOS's double-
; click count still runs; else that count started for this click.
Double: lda dblClickCount
        beq @new
        lda pick
        cmp last
        bne @new
        lda pick+1
        cmp last+1
        bne @new
        lda #0
        sta dblClickCount
        sec
        rts
@new:   lda pick
        sta last
        lda pick+1
        sta last+1
        lda #CLICK_COUNT
        sta dblClickCount
        clc
        rts

; Range: entries cur to pick (either way round) selected.
Range:  lda cur
        sta lo
        lda cur+1
        sta lo+1
        lda pick
        sta hi
        lda pick+1
        sta hi+1
        lda hi+1                ; lo <= hi
        cmp lo+1
        bne :+
        lda hi
        cmp lo
:       bcs @loop
        ldx lo                  ; (swapped)
        lda hi
        sta lo
        stx hi
        ldx lo+1
        lda hi+1
        sta lo+1
        stx hi+1
@loop:  lda lo
        ldx lo+1
        ldy #1
        jsr Select
        lda lo
        cmp hi
        bne :+
        lda lo+1
        cmp hi+1
        beq @end
:       inc lo
        bne @loop
        inc lo+1
        bne @loop
@end:   rts

; PageUp, PageDown: top a screen up or down (within the table).
PageUp: lda top
        sec
        sbc #ROWS
        tax
        lda top+1
        sbc #0
        bcs :+
        lda #0
        tax
:       stx top
        sta top+1
        rts
PageDown:
        lda top
        clc
        adc #ROWS
        tax
        lda top+1
        adc #0
        cmp count+1             ; still within the table?
        bne :+
        cpx count
:       bcs @end
        stx top
        sta top+1
@end:   rts

; Modifiers: mods = SHIFT and C= as held now (the keyboard matrix:
; row 1 bit 7 left SHIFT, row 6 bit 4 right SHIFT, row 7 bit 5 C=).
; Control port 1 shares the matrix's columns: a 1351's left button
; pulls bit 4 low (right SHIFT's) while it is pressed. The lines held
; low with no row selected are therefore ignored (joyMask), so a click
; is not taken for SHIFT+click; right SHIFT then does not count during
; a click, left SHIFT does.
Modifiers:
        lda #0
        sta mods
        php
        sei
        lda CPU_PORT            ; (I/O in: applications run with RAM there,
        pha                     ; as gush's Ctrl knows)
        lda #RAM_IO
        sta CPU_PORT
        lda CIA1_PA
        pha
        lda #$FF                ; no row: what control port 1 holds low
        sta CIA1_PA
        lda CIA1_PB
        eor #$FF
        sta joyMask             ; (those lines: read as not pressed)
        lda #%11111101          ; row 1
        sta CIA1_PA
        lda CIA1_PB
        ora joyMask
        and #%10000000
        bne :+
        lda #MOD_SHIFT
        sta mods
:       lda #%10111111          ; row 6
        sta CIA1_PA
        lda CIA1_PB
        ora joyMask
        and #%00010000
        bne :+
        lda mods
        ora #MOD_SHIFT
        sta mods
:       lda #%01111111          ; row 7
        sta CIA1_PA
        lda CIA1_PB
        ora joyMask
        and #%00100000
        bne :+
        lda mods
        ora #MOD_CBM
        sta mods
:       pla
        sta CIA1_PA
        pla
        sta CPU_PORT
        plp
        rts

; ListKey: A = a key (keyVector, desktop.s). C clear when it was the
; list's.
ListKey:
        sta key
        and #$7F
        cmp #KEY_DOWN
        beq @down
        cmp #KEY_UP
        beq @up
        cmp #KEY_HOME
        beq @home
        cmp #CR
        beq @open
        cmp #KEY_LEFT
        beq @parent
        sec
        rts
@open:  jsr Open
        clc
        rts
@parent:
        jsr Up
        clc
        rts
@home:  lda #0
        sta cur
        sta cur+1
        sta top
        sta top+1
        jmp @moved
@down:  lda cur                 ; (not past the last)
        clc
        adc #1
        tax
        lda cur+1
        adc #0
        cmp count+1
        bne :+
        cpx count
:       bcs @show
        stx cur
        sta cur+1
        jmp @moved
@up:    lda cur
        ora cur+1
        beq @show
        lda cur
        bne :+
        dec cur+1
:       dec cur
@moved: bit key                 ; C= held: the selection extended, else
        bmi @extend             ; only the cursor's entry
        jsr ClearSel
@extend:
        lda cur
        ldx cur+1
        ldy #1
        jsr Select
        jsr Follow
@show:  jsr ListDraw
        clc
        rts

; Follow: top moved so the cursor is on the screen.
Follow: lda cur+1               ; cur < top: top = cur
        cmp top+1
        bne :+
        lda cur
        cmp top
:       bcs @below
        lda cur
        sta top
        lda cur+1
        sta top+1
        rts
@below: lda top                 ; cur >= top + ROWS: top = cur - ROWS + 1
        clc
        adc #ROWS
        tax
        lda top+1
        adc #0
        cmp cur+1
        bne :+
        cpx cur
:       beq @move
        bcs @end
@move:  lda cur
        sec
        sbc #ROWS - 1
        sta top
        lda cur+1
        sbc #0
        sta top+1
@end:   rts


        .segment "DATA"

count:          .word 0         ; entries in the table
top:            .word 0         ; the first shown
cur:            .word 0         ; the cursor
pick:           .word 0
last:           .word $FFFF         ; the entry clicked last
lo:             .word 0
hi:             .word 0
handle:         .byte 0
row:            .byte 0
tmp:            .byte 0
tmpH:           .byte 0
mode:           .byte 0
mods:           .byte 0
joyMask:        .byte 0         ; control port 1's low lines (Modifiers)
key:            .byte 0
numL:           .byte 0
numH:           .byte 0
denL:           .byte 0
denH:           .byte 0
mulL:           .byte 0
mulH:           .byte 0

        .segment "BSS"

path:           .res 256
entryInfo:      .res INFO_LEN
entryName:      .res NAME_LEN + 2
sel:            .res ENTRY_MAX / 8
cutPath:        .res 256        ; (PathPress)
