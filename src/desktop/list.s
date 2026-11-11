; GeoUltra Desktop: the list (docs/DESKTOP.md, step D2). A folder's
; entries are read once (FE_OPENDIR, FE_READDIR) into an entry table in
; the application's REU, ENTRY_SIZE bytes each from bank ENTRY_BANK on
; (up to ENTRY_MAX), in directory order; the list area shows `rows`
; of them from `top`, with a scroll strip at the right edge, drawn in
; the theme's look (theme.s, step D7a: title bar, icons, selection and
; cursor styles, the status line). The selection
; is a bit per entry (`sel`), the cursor (`cur`) the entry the keys move.
; Mouse: a click selects the entry under it alone, SHIFT+click the range
; from the cursor, C=+click toggles it; in the strip, its arrows a line,
; above or below its thumb a page. Keys: cursor up and down move the cursor (the
; selection follows), with C= held they extend the selection (on the
; C64 cursor up is SHIFT + CRSR DOWN, so SHIFT cannot extend), HOME to
; the first entry. Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine, Open, Up, Into
        .import IconUp, IconFor, TextWidth, Paint, PaintList, px0, px1, py0, py1, pcol
        .import tTitle, tIcons, tSel, tCur, tScroll, tStatus, cSel, cAccentP
        .import listL, iconCard, nameX, pathY, listTop, rowH, rows, bottom
        .import stY0, stY1, trackTop, trackBot, trackH, viewMode, MonthName
        .export ListRead, ListDraw, ListPress, ListKey, path, count
        .export entryInfo, entryName, cur, top, sel, IsSelected, Fetch
        .export Modifiers, mods, IsDotDot, ListEnd, SelAll, row, RowEntry
        .import IconsForget, DrawCell, CellAt, step, tbMode
        .export Frame
        .import topY, titleEnd
        .export ProgressStart, ProgressBlock, progN, progTotal, SelCount
        .import Busy, Idle
        .import text            ; (side.s's INI text, PathPress's path: not
                                ; in use while a folder is entered)
cutPath = text

; The list's right edge (the strip from STRIP_LEFT), the status line
LIST_RIGHT      = STRIP_LEFT - 3
STATUS_Y        = 192
FREE_PRE_MAX    = 5             ; "USB0" and ":"
PROG_NAME_END   = 34            ; the progress line: the name cut here
ST_BUF_LEN      = PROG_NAME_END + 2 + 5 + 7 + 1 ; stBuf: the progress
                                ; line's name, ", 65535 blocks" and the zero
R_LEN           = 32            ; r0-r15
RAM_ALL         = $30
COL_SIZE        = 246           ; the detailed view: sizes end here,
COL_DATE        = 254           ; dates start here,
COL_NAME_END    = 202           ; names are clipped here

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
; IsDotDot). Then its free space for the status line (FreeRead).
ListRead:
        jsr Busy                ; (icons.s: the hourglass meanwhile)
        jsr IconsForget         ; (iconview.s: a new folder, new icons)
        jsr ReadList
        jsr FreeRead
        jmp Idle
ReadList:
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FE_PWD
        jsr FileEngine          ; (an error left: path keeps the folder it
        lda #0                  ; held, which the listing below then reads)
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

; ListDraw: the list area in the theme's look: the title bar, the path
; line, the rows from top (icon, name, selection, cursor), the scroll
; strip and the status line.
ListDraw:
        jsr AlignTop            ; (the icon view: a whole row of cells)
        jsr PaintList
        lda #0
        jsr SetPattern
        lda topY                ; title, path and rows cleared
        sta r2L
        lda bottom
        sta r2H
        lda listL
        sta r3L
        lda #0
        sta r3H
        lda #<(STRIP_LEFT - 1)
        sta r4L
        lda #>(STRIP_LEFT - 1)
        sta r4H
        jsr Rectangle
        jsr Title
        jsr NameClip
        lda listL               ; the path line, a line under it
        clc
        adc #4
        sta textX
        lda #<path
        ldx #>path
        ldy pathY
        jsr Text
        jsr Header
        lda pathY               ; (to the frame's right edge: the scroll
        clc                     ; strip starts below it)
        adc #2
        sta r11L
        jsr ListSpan
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        lda #$FF
        jsr HorizontalLine
        lda #0
        sta row
@row:   lda row
        cmp rows
        bcs @strip
        jsr RowEntry            ; (C set: past the end)
        bcs @strip
        jsr Fetch
        jsr DrawEntry
        inc row
        bne @row
@strip: jsr Strip
        jsr Status
        jmp Frame

; Frame (ListDraw; desktop.s, SideRedraw): the lines that box the
; desktop's areas (the user, 2026-11-11): the screen's left and right
; edges from under the menu bar's line to the bottom, the line above the
; status line, and the line under the toolbar (none when it is off: the
; menu bar's line is the top then). With the sidebar's line they frame
; the toolbar, the sidebar and the list. Drawn again after each of them,
; as their clearing takes the lines away. Destroys A, X, Y, r3, r4, r11.
Frame:  lda #0
        jsr Edge
        lda #<SCREEN_RIGHT
        ldx #>SCREEN_RIGHT
        jsr Edge2
        lda bottom
        jsr Across
        lda tbMode
        cmp #TB_OFF
        beq @end
        ldx topY
        dex
        txa
        jmp Across
@end:   rts

; Edge, Edge2: a line at x A (Edge2: A/X) from under the menu bar's line
; to bottom.
Edge:   ldx #0
Edge2:  sta r4L
        stx r4H
        lda #MENU_BOTTOM + 1
        sta r3L
        lda bottom
        sta r3H
        lda #$FF
        jmp VerticalLine

; Across: a line across the screen at y A.
Across: sta r11L
        lda #0
        sta r3L
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        lda #$FF
        jmp HorizontalLine

; DrawEntry: row `row` drawn as a row of the list or a cell of the
; icon view (iconview.s).
DrawEntry:
        lda viewMode
        cmp #VIEW_ICONS
        bne DrawRow
        jmp DrawCell

; AlignTop: top a multiple of step (the icon view's columns; 1 in the
; list, nothing to do).
AlignTop:
        lda step
        cmp #2
        bcc @end
        lda top                 ; tmp/tmpH = top mod step
        sta tmp
        lda top+1
        sta tmpH
@sub:   lda tmp
        sec
        sbc step
        tax
        lda tmpH
        sbc #0
        bcc @mod
        sta tmpH
        stx tmp
        jmp @sub
@mod:   lda top                 ; top -= it
        sec
        sbc tmp
        sta top
        bcs @end
        dec top+1
@end:   rts

; ListSpan: r3 = listL, r4 = LIST_RIGHT (the list's width).
ListSpan:
        lda listL
        sta r3L
        lda #0
        sta r3H
        lda #<LIST_RIGHT
        sta r4L
        lda #>LIST_RIGHT
        sta r4H
        rts

; DrawRow: row `row`, its entry fetched: the selection's colour bar,
; the icon (or "/" after a folder without icons), the name, the
; selection inverted or framed, the cursor.
DrawRow:
        lda row
        jsr RowY
        sta ry
        lda row
        jsr RowEntry
        jsr IsSelected
        sta selNow
        beq @icon
        lda tSel
        cmp #ST_BAR
        bne @icon
        lda listL               ; the bar: the row's cells (8-pixel rows)
        lsr a
        lsr a
        lsr a
        sta px0
        lda #LIST_RIGHT / 8
        sta px1
        lda ry
        lsr a
        lsr a
        lsr a
        sta py0
        sta py1
        lda cSel
        sta pcol
        jsr Paint
@icon:  lda tIcons
        bne @mark
        jsr IconFor
        ldx iconCard
        ldy ry
        jsr IconUp
        jsr IsDotDot            ; ("..", two dots: "../" with the icon too)
        bne @name
@mark:  jsr Mark
@name:  lda nameX
        sta textX
        lda ry
        clc
        adc #BASELINE
        tay
        lda #<entryName
        ldx #>entryName
        jsr Text
        lda viewMode            ; the detailed view: size and date
        cmp #VIEW_DETAILED
        bne :+
        jsr Columns
:       lda selNow
        beq @cursor
        jsr RowBox
        lda tSel
        beq @inv
        cmp #ST_FRAME
        bne @cursor
        lda #$FF
        jsr FrameRectangle
        jmp @cursor
@inv:   jsr InvertRectangle
@cursor:
        lda row
        jsr RowEntry
        cmp cur
        bne @none
        cpx cur+1
        beq :+
@none:  rts
:       lda tCur
        beq @dotted
        cmp #ST_MARK
        beq @side
        lda #<entryName         ; underline: under the name
        sta r0L
        lda #>entryName
        sta r0H
        jsr TextWidth
        lda nameX
        sta r3L
        clc
        adc r2L
        sta r4L
        lda #0
        sta r3H
        adc r2H
        sta r4H
        cmp #>LIST_RIGHT        ; (clipped at the list's edge)
        bne :+
        lda r4L
        cmp #<LIST_RIGHT
:       bcc :+
        lda #<LIST_RIGHT
        sta r4L
        lda #>LIST_RIGHT
        sta r4H
:       lda ry
        clc
        adc #7
        ldx rowH
        cpx #9
        bne :+
        adc #1
:       sta r11L
        lda #$FF
        jmp HorizontalLine
@dotted:
        jsr RowBox
        lda #$AA
        jmp FrameRectangle
@side:  lda listL               ; a mark at the left edge, accent colour
        lsr a
        lsr a
        lsr a
        sta px0
        sta px1
        lda ry
        lsr a
        lsr a
        lsr a
        sta py0
        lda ry
        clc
        adc #7
        lsr a
        lsr a
        lsr a
        sta py1
        lda cAccentP
        sta pcol
        jsr Paint
        lda #1
        jsr SetPattern
        lda ry
        sta r2L
        clc
        adc #7
        sta r2H
        lda listL
        clc
        adc #1
        sta r3L
        adc #1
        sta r4L
        lda #0
        sta r3H
        sta r4H
        jsr Rectangle
        lda #0
        jmp SetPattern
@end:   rts

; NameClip: textClip = the list's right edge, or before the columns in
; the detailed view.
NameClip:
        lda #<LIST_RIGHT
        ldx #>LIST_RIGHT
        ldy viewMode
        cpy #VIEW_DETAILED
        bne :+
        lda #COL_NAME_END
        ldx #0
:       sta textClip
        stx textClip+1
        rts

; Header: "Size" and "Date" over the detailed view's columns, on the
; path line's right.
Header: lda viewMode
        cmp #VIEW_DETAILED
        bne @end
        ldy #0
        ldx #SizeWord
        jsr Words
        lda #0
        sta stBuf,y
        jsr RightAtSize
        ldy pathY
        jsr ColText
        ldy #0
        ldx #DateWord
        jsr Words
        lda #0
        sta stBuf,y
        lda #COL_DATE
        sta textX
        ldy pathY
        jmp ColText
@end:   rts

; Columns: the entry's size (KB or MB; not for folders and drives) right-
; aligned at COL_SIZE, its date (GEOS files) at COL_DATE, on row ry.
Columns:
        jsr SizeKB
        bcs @date
        ldy #0
        jsr Dec16
        lda #' '
        sta stBuf,y
        iny
        lda unit
        sta stBuf,y
        iny
        lda #'B'
        sta stBuf,y
        iny
        lda #0
        sta stBuf,y
        jsr RightAtSize
        jsr RowBase
        jsr ColText
@date:  lda entryInfo + FI_KIND
        cmp #K_GEOS
        bne @end
        ldx entryInfo + FI_DATE + 1     ; "12 Nov 26"
        beq @end
        cpx #13
        bcs @end
        ldy #0
        lda entryInfo + FI_DATE + 2
        ldx #0
        jsr Dec16
        lda #' '
        sta stBuf,y
        iny
        lda entryInfo + FI_DATE + 1
        jsr MonthName           ; r1 (theme.s)
        sty tmp
        ldx tmp
        ldy #0
@mon:   lda (r1),y
        sta stBuf,x
        inx
        iny
        cpy #3
        bcc @mon
        txa
        tay
        lda #' '
        sta stBuf,y
        iny
        lda entryInfo + FI_DATE         ; the year: two digits
        ldx #'0' - 1
@ten:   inx
        sec
        sbc #10
        bcs @ten
        adc #10 + '0'
        pha
        txa
        sta stBuf,y
        iny
        pla
        sta stBuf,y
        iny
        lda #0
        sta stBuf,y
        lda #COL_DATE
        sta textX
        jsr RowBase
        jmp ColText
@end:   rts

; RightAtSize: textX = COL_SIZE - the width of stBuf.
RightAtSize:
        lda #<stBuf
        sta r0L
        lda #>stBuf
        sta r0H
        jsr TextWidth
        lda #COL_SIZE
        sec
        sbc r2L
        sta textX
        rts

; RowBase: Y = row ry's baseline.
RowBase:
        lda ry
        clc
        adc #BASELINE
        tay
        rts

; ColText: stBuf at textX, baseline Y, clipped at the list's right edge.
ColText:
        lda #<LIST_RIGHT
        sta textClip
        lda #>LIST_RIGHT
        sta textClip+1
        lda #<stBuf
        ldx #>stBuf
        jsr Text
        jmp NameClip

; SizeKB: A/X = the entry's size in KB (unit 'K'), or in MB (unit 'M')
; from 10240 KB; C set for an entry without a size (folders, drives,
; Ultimate files: their listing gives none).
; GEOS and CBM files: blocks / 4, rounded up; Ultimate files: bytes /
; 1024, rounded up.
SizeKB: lda entryInfo + FI_KIND
        cmp #K_GEOS
        beq @blocks
        cmp #K_CBM
        beq @blocks
        cmp #K_UFILE
        bne @none
        lda entryInfo + FI_SIZE         ; (the Ultimate's listings give
        ora entryInfo + FI_SIZE + 1     ; no sizes, FILE_ENGINE.md: 0 is
        ora entryInfo + FI_SIZE + 2     ; unknown, so nothing shown)
        ora entryInfo + FI_SIZE + 3
        bne @bytes
@none:  sec
        rts
@blocks:
        lda entryInfo + FI_SIZE         ; (blocks + 3) / 4
        clc
        adc #3
        sta numL
        lda entryInfo + FI_SIZE + 1
        adc #0
        sta numH
        lsr numH
        ror numL
        lsr numH
        ror numL
        jmp @unit
@bytes: lda entryInfo + FI_SIZE         ; (bytes + 1023) / 1024: bits
        clc                             ; 10-25 of the sum
        adc #<1023
        lda entryInfo + FI_SIZE + 1
        adc #>1023
        sta numL
        lda entryInfo + FI_SIZE + 2
        adc #0
        sta numH
        lda entryInfo + FI_SIZE + 3
        adc #0
        lsr a
        ror numH
        ror numL
        lsr a
        ror numH
        ror numL
@unit:  lda #'K'
        sta unit
        lda numH                ; 10240 KB and more: MB (KB / 1024)
        cmp #>10240
        bcc @end
        lsr a
        lsr a
        sta numL
        lda #0
        sta numH
        lda #'M'
        sta unit
@end:   lda numL
        ldx numH
        clc
        rts

; RowBox: r2-r4 = row ry's box: from the gap above it on 9-pixel rows to
; its last line, x listL + 2 to LIST_RIGHT - 1.
RowBox: lda ry
        ldx rowH
        cpx #9
        bne :+
        sec
        sbc #1
:       sta r2L
        lda ry
        clc
        adc #7
        sta r2H
        lda listL
        clc
        adc #2
        sta r3L
        lda #0
        sta r3H
        lda #<(LIST_RIGHT - 1)
        sta r4L
        lda #>(LIST_RIGHT - 1)
        sta r4H
        rts

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

; RowY: A = row A's top pixel row (listTop + A * rowH).
RowY:   tax
        lda listTop
@add:   dex
        bmi @end
        clc
        adc rowH
        bne @add
@end:   rts

; Text: the text at A/X at x textX, baseline Y, clipped at textClip
; (the list's right edge, or before the detailed view's columns).
Text:   sta r0L
        stx r0H
        sty r1H
        lda textX
        sta r11L
        lda #0
        sta r11H
        lda textClip
        sta rightMargin
        lda textClip+1
        sta rightMargin+1
PutWhole:
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

; Title: the title bar (y 16-23) with the folder's name: the path's last
; part ("GeoUltra" at "/"), by the theme's style.
Title:  lda tTitle
        cmp #ST_NONE
        bne :+
        rts
:       jsr TitleName           ; r0
        lda tTitle
        cmp #ST_LINE
        bne :+
        jmp @line
:       jsr TextWidth           ; cx = the bar's middle - width / 2
        lda r2L
        sta tw
        lda listL
        clc
        adc #<SCREEN_RIGHT
        sta cx
        lda #>SCREEN_RIGHT
        adc #0
        lsr a
        ror cx                  ; (listL + 319) / 2
        lda tw
        lsr a
        sta tmp
        lda cx
        sec
        sbc tmp
        sta cx
        lda tTitle
        bne @solid
        ldx topY                ; stripes: every other line
@stripe:
        stx r11L
        stx tmp
        jsr TitleSpan
        lda #$FF
        jsr HorizontalLine
        ldx tmp
        inx
        inx
        cpx titleEnd
        bcc @stripe
        lda #0                  ; a gap for the name
        jsr SetPattern
        jsr TitleRows

        lda cx
        sec
        sbc #5
        sta r3L
        lda #0
        sta r3H
        lda cx
        clc
        adc tw
        sta r4L
        lda #0
        adc #0
        sta r4H
        lda r4L
        clc
        adc #4
        sta r4L
        bcc :+
        inc r4H
:       jsr Rectangle
        jmp TitleText
@solid: jsr TitleText           ; solid: the name, then the bar inverted
        jsr TitleRows
        jsr TitleSpan
        jmp InvertRectangle
@line:  lda listL               ; line: the name in bold at the left, a
        clc                     ; line under the bar
        adc #4
        sta cx
        lda #SET_BOLD
        sta currentMode
        jsr TitleText
        lda #0
        sta currentMode
        ldx titleEnd
        dex
        stx r11L
        jsr TitleSpan
        lda #$FF
        jmp HorizontalLine

; TitleRows: r2L-r2H = the title bar's rows (topY to titleEnd - 1).
TitleRows:
        lda topY
        sta r2L
        ldx titleEnd
        dex
        stx r2H
        rts

; TitleSpan: r3 = listL, r4 = the screen's right edge.
TitleSpan:
        lda listL
        sta r3L
        lda #0
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        rts

; TitleText: the title's name at x cx, baseline topY + 6.
TitleText:
        jsr TitleName
        lda cx
        sta r11L
        lda #0
        sta r11H
        ldx topY
        inx
        inx
        inx
        inx
        inx
        inx
        stx r1H
        jmp PutString

; TitleName: r0 = the path's last part, or "GeoUltra" at "/".
TitleName:
        lda path + 1
        bne :+
        lda #<RootTitle
        sta r0L
        lda #>RootTitle
        sta r0H
        rts
:       ldy #0
        ldx #1
@ch:    lda path,y
        beq @end
        iny
        cmp #'/'
        bne @ch
        tya
        tax
        bne @ch
@end:   txa
        clc
        adc #<path
        sta r0L
        lda #>path
        adc #0
        sta r0H
        rts

; Strip: the scroll strip (x STRIP_LEFT-319, stY0-stY1): arrows in boxes
; and a grey thumb, or a thin line with a black one.
Strip:  lda #0
        jsr SetPattern
        jsr StripRect
        jsr Rectangle
        lda tScroll
        bne @thin
        lda #IC_UP
        ldx #STRIP_LEFT / 8
        ldy stY0
        iny
        jsr IconUp
        lda stY1
        sec
        sbc #8
        tay
        lda #IC_DOWN
        ldx #STRIP_LEFT / 8
        jsr IconUp
        jsr StripRect           ; the frame, the arrows' boxes
        lda #$FF
        jsr FrameRectangle
        jsr StripRect
        lda stY0
        clc
        adc #8
        sta r2H
        lda #$FF
        jsr FrameRectangle
        jsr StripRect
        lda stY1
        sec
        sbc #8
        sta r2L
        lda #$FF
        jsr FrameRectangle
        lda #2                  ; the thumb: grey
        ldx #STRIP_LEFT + 1 - 256
        ldy #<(SCREEN_RIGHT - 1)
        bne @thumb
@thin:  lda stY0                ; a line in the middle
        sta r3L
        lda stY1
        sta r3H
        lda #<(STRIP_LEFT + 4)
        sta r4L
        lda #>(STRIP_LEFT + 4)
        sta r4H
        lda #$FF
        jsr VerticalLine
        lda #1                  ; the thumb: black, 3 pixels
        ldx #STRIP_LEFT + 3 - 256
        ldy #STRIP_LEFT + 5 - 256
@thumb: sta tmp                 ; (pattern), x1 and x2 low bytes (high 1)
        stx r3L
        sty r4L
        lda #1
        sta r3H
        sta r4H
        lda count
        ora count+1
        beq @end                ; (nothing listed: no thumb)
        lda r3L
        pha
        lda r4L
        pha
        jsr ThumbRows
        pla
        sta r4L
        pla
        sta r3L
        lda #1
        sta r3H
        sta r4H
        lda tmp
        jsr SetPattern
        jsr Rectangle
        lda #0
        jmp SetPattern
@end:   rts

; StripRect: r2-r4 = the strip.
StripRect:
        lda stY0
        sta r2L
        lda stY1
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

; ThumbRows: r2L/r2H = the thumb's first and last pixel row: the
; track's height times top / count and (top + rows) / count. Counts
; above 255 are scaled down first (an approximate thumb is enough).
ThumbRows:
        lda top
        ldx top+1
        jsr Scale
        clc
        adc trackTop
        sta r2L
        lda top
        clc
        adc rows
        tay
        lda top+1
        adc #0
        tax
        tya
        jsr Scale
        clc
        adc trackTop
        sec
        sbc #1
        cmp trackBot
        bcc :+
        lda trackBot
:       cmp r2L                 ; (at least a line)
        bcs :+
        lda r2L
:       sta r2H
        rts

; Scale: A/X (an entry number) * trackH / count; at most trackH.
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
@mul:   lda numL                ; numL > denL (past the end): the whole
        cmp denL
        bcc :+
        lda trackH
        rts
:       lda #0                  ; numL * trackH (16 bits) / denL
        sta mulL
        sta mulH
        ldx trackH
        beq @done0
@add:   lda numL
        clc
        adc mulL
        sta mulL
        bcc :+
        inc mulH
:       dex
        bne @add
        lda denL
        beq @done0
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
@done0: lda #0
        rts

; Status: the status line (y 192-199): entries and selected ones at the
; left, the free space of the current drive or Ultimate root at the
; right (FreeRead), inverted in the status colours.
Status: lda tStatus
        beq :+
        rts
:       lda #0
        jsr SetPattern
        lda #STATUS_Y
        sta r2L
        lda #199
        sta r2H
        jsr FullSpan
        jsr Rectangle
        lda count               ; "21 entries, 2 selected" (".." not
        ldx count+1             ; counted; "1 entry"; no selection: no
        ldy path + 1            ; second part)
        beq :+
        sec
        sbc #1
        bcs :+
        dex
:       ldy #EntryWord          ; (one: the singular)
        cpx #0
        bne :+
        cmp #1
        beq @one
:       ldy #EntriesWord
@one:   sty word
        ldy #0
        jsr Dec16
        ldx word
        jsr Words
        jsr SelCount
        cmp #0
        bne :+
        cpx #0
        beq @left
:       pha
        txa
        pha
        ldx #CommaWord
        jsr Words
        pla
        tax
        pla
        jsr Dec16
        ldx #SelectedWord
        jsr Words
@left:  lda #0
        sta stBuf,y
        lda #4
        sta textX
        lda #<stBuf
        ldx #>stBuf
        jsr StatusText
        lda freeOK              ; the free space, right-aligned
        beq @inv
        ldy #0
@pre:   lda freePre,y
        beq :+
        sta stBuf,y
        iny
        bne @pre
:       lda #' '
        sta stBuf,y
        iny
        lda freeVal
        ldx freeVal+1
        jsr Dec16
        lda #' '
        sta stBuf,y
        iny
        lda freeMB
        sta stBuf,y
        iny
        ldx #FreeWord
        jsr Words               ; "B free"
        lda #0
        sta stBuf,y
        lda #<stBuf
        sta r0L
        lda #>stBuf
        sta r0H
        jsr TextWidth
        lda #<316               ; x = 316 - the width
        sec
        sbc r2L
        sta r11L
        lda #>316
        sbc r2H
        sta r11H
        lda #198
        sta r1H
        jsr PutString
@inv:   lda #STATUS_Y
        sta r2L
        lda #199
        sta r2H
        jsr FullSpan
        jmp InvertRectangle

; ProgressStart: "Copying 3 of 12: name" on the status line (A = the
; verb: 0 copying, 1 moving, 2 deleting; progN of progTotal, "Copying
; 14: name" when progTotal is 0; the name in entryName), its length kept
; for ProgressBlock.
ProgressStart:
        tax
        ldy VerbAt,x
        ldx #0
@verb:  lda Verbs,y
        beq :+
        sta stBuf,x
        inx
        iny
        bne @verb
:       txa
        tay
        lda progN
        ldx progN+1
        jsr Dec16
        lda progTotal           ; (a total not known: "Copying 14: name")
        ora progTotal+1
        beq :+
        ldx #OfWord
        jsr Words
        lda progTotal
        ldx progTotal+1
        jsr Dec16
:       ldx #ColonWord
        jsr Words
        ldx #0
@name:  lda entryName,x
        beq :+
        sta stBuf,y
        iny
        inx
        cpy #PROG_NAME_END
        bcc @name
:       sty progLen
        lda #0
        sta stBuf,y
        jmp StatusShow

; ProgressBlock (FE_COPY's and FE_MOVE's progress routine, r3): ", 40
; blocks" after ProgressStart's text (r4 = the blocks done); C set when
; RUN/STOP is held (the engine stops: FE_CANCELLED). Keeps r0-r15 and the
; CPU port as the engine had them; the drawing with the font in view.
ProgressBlock:
        ldx #R_LEN - 1          ; the engine's registers kept
@keep:  lda r0L,x
        sta regSave,x
        dex
        bpl @keep
        lda CPU_PORT
        pha
        lda #RAM_ALL            ; (the system font lies under I/O)
        sta CPU_PORT
        ldy progLen
        ldx #CommaWord
        jsr Words
        lda r4L
        ldx r4H
        jsr Dec16
        ldx #BlocksWord
        jsr Words
        lda #0
        sta stBuf,y
        jsr StatusShow
        jsr Stopped             ; (C set: RUN/STOP held)
        pla
        sta CPU_PORT
        php
        ldx #R_LEN - 1
@back:  lda regSave,x
        sta r0L,x
        dex
        bpl @back
        plp
        rts

; StatusShow: stBuf on the status line, in its colours, inverted as the
; status line is.
StatusShow:
        lda #0
        jsr SetPattern
        lda #STATUS_Y
        sta r2L
        lda #199
        sta r2H
        jsr FullSpan
        jsr Rectangle
        lda #<316
        sta rightMargin
        lda #>316
        sta rightMargin+1
        lda #4
        sta textX
        lda #<stBuf
        ldx #>stBuf
        jsr StatusText
        lda #<SCREEN_RIGHT
        sta rightMargin
        lda #>SCREEN_RIGHT
        sta rightMargin+1
        lda #STATUS_Y
        sta r2L
        lda #199
        sta r2H
        jsr FullSpan
        jmp InvertRectangle

; Stopped: C set when RUN/STOP is held (the keyboard matrix's row 7,
; bit 7; I/O switched in for the read).
Stopped:
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda CIA1_PA
        pha
        lda #%01111111
        sta CIA1_PA
        lda CIA1_PB
        sta tmp
        pla
        sta CIA1_PA
        pla
        sta CPU_PORT
        plp
        lda tmp                 ; (bit 7 low: held)
        asl a
        bcc :+
        clc
        rts
:       sec
        rts

; StatusText: the text at A/X at x textX (< 256), baseline 198.
StatusText:
        sta r0L
        stx r0H
        lda textX
        sta r11L
        lda #0
        sta r11H
        lda #198
        sta r1H
        jmp PutString

; FullSpan: r3-r4 = x 0 to 319.
FullSpan:
        lda #0
        sta r3L
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        rts

; Words: the zero-ended text at StatusWords + X to stBuf + Y (Y on).
Words:  lda StatusWords,x
        beq @end
        sta stBuf,y
        iny
        inx
        bne Words
@end:   rts

; SelCount: A/X = the selected entries (the bits set in sel). Keeps Y.
SelCount:
        sty tmp
        lda #0
        sta numL
        sta numH
        ldy #0
@byte:  lda sel,y
        beq @next
@bit:   asl a
        bcc :+
        inc numL
        bne :+
        inc numH
:       cmp #0
        bne @bit
@next:  iny
        bne @byte
        ldy tmp
        lda numL
        ldx numH
        rts

; Dec16: A/X (low, high) in decimal to stBuf + Y, without leading
; zeros; Y on.
Dec16:  sta numL
        stx numH
        lda #0
        sta any
        ldx #0                  ; the powers of ten, 10000 down to 10
@pow:   lda #'0'
        sta digit
@sub:   lda numL
        sec
        sbc PowLo,x
        sta tmp
        lda numH
        sbc PowHi,x
        bcc @put
        sta numH
        lda tmp
        sta numL
        inc digit
        bne @sub
@put:   lda digit           ; (leading zeros left out)
        cmp #'0'
        bne @out
        lda any
        beq @skip
        lda digit
@out:   sta stBuf,y
        iny
        sta any
@skip:  inx
        cpx #4
        bcc @pow
        lda numL                ; the units, always
        ora #'0'
        sta stBuf,y
        iny
        rts

; FreeRead: the free space of the current folder's drive or Ultimate
; root for the status line (FE_DF; nothing at "/" or on an error):
; freePre its name ("B:", "USB0:"), freeVal and freeMB the amount in KB
; or MB ('K' or 'M').
FreeRead:
        lda #0
        sta freeOK
        lda path + 1
        beq @end
        ldy #1                  ; the name: the path's first part, upper case
        ldx #0
@pre:   lda path,y
        beq :+
        cmp #'/'
        beq :+
        cmp #'a'
        bcc @keep
        cmp #'z' + 1
        bcs @keep
        and #$DF
@keep:  sta freePre,x
        inx
        iny
        cpx #FREE_PRE_MAX
        bcc @pre
:       lda #':'
        sta freePre,x
        lda #0
        sta freePre + 1,x
        stx tmp                 ; (its length: 1 for a drive)
        lda #<path
        sta r0L
        lda #>path
        sta r0H
        lda #FE_DF
        jsr FileEngine
        txa
        bne @end
        lda r1L                 ; a drive's blocks: / 4 for KB
        sta freeVal
        lda r1H
        sta freeVal+1
        lda tmp
        cmp #1
        bne @kb
        lsr freeVal+1
        ror freeVal
        lsr freeVal+1
        ror freeVal
@kb:    lda #'K'
        sta freeMB
        lda freeVal+1           ; 10240 KB and more: MB
        cmp #>10240
        bcc @ok
        lda #'M'
        sta freeMB
        lda freeVal+1           ; KB / 1024 = the high byte / 4
        lsr a
        lsr a
        sta freeVal
        lda #0
        sta freeVal+1
@ok:    lda #1
        sta freeOK
@end:   rts

PowLo:  .byte <10000, <1000, <100, <10
PowHi:  .byte >10000, >1000, >100, >10
StatusWords:                    ; (sentence case: the user, 2026-11-11)
EntryWord = * - StatusWords
        .byte " entry", 0
EntriesWord = * - StatusWords
        .byte " entries", 0
CommaWord = * - StatusWords
        .byte ", ", 0
SelectedWord = * - StatusWords
        .byte " selected", 0
FreeWord = * - StatusWords
        .byte "B free", 0
OfWord = * - StatusWords
        .byte " of ", 0
ColonWord = * - StatusWords
        .byte ": ", 0
BlocksWord = * - StatusWords
        .byte " blocks", 0
SizeWord = * - StatusWords
        .byte "Size", 0
DateWord = * - StatusWords
        .byte "Date", 0
RootTitle:      .byte "GeoUltra", 0
Verbs:          .byte "Copying ", 0
VERB_MOVE = * - Verbs
                .byte "Moving ", 0
VERB_DELETE = * - Verbs
                .byte "Deleting ", 0
VerbAt:         .byte 0, VERB_MOVE, VERB_DELETE

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
        lda listL               ; (Text's x for the path)
        clc
        adc #4
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

; ListPress (a mouse press right of the sidebar; desktop.s). C clear
; when it was the list's: the path line, a row, the scroll strip (its
; arrows a line, above or below the thumb a page).
ListPress:
        lda mouseXPos+1
        bne :+
        lda mouseXPos
        cmp listL
        bcc @out                ; (the sidebar)
:       lda mouseYPos
        cmp topY
        bcc @out
        cmp listTop
        bcs @below
        lda pathY               ; above the rows: the path line, else the
        sec                     ; title bar (nothing)
        sbc #8
        cmp mouseYPos
        bcs @title
        jmp PathPress
@title: clc
        rts
@below: lda bottom              ; (below it: the status line, not ours)
        cmp mouseYPos
        bcs :+
@out:   sec
        rts
:       lda mouseXPos+1         ; the strip?
        cmp #>STRIP_LEFT
        bcc @list
        beq :+
        jmp @strip
:       lda mouseXPos
        cmp #<STRIP_LEFT
        bcc @list
        jmp @strip
@list:  lda viewMode              ; the icon view: the cell
        cmp #VIEW_ICONS
        bne @rows
        jsr CellAt
        bcs @none
        bcc @got
@rows:  lda mouseYPos           ; the row
        sec
        sbc listTop
        ldx #0
@r:     cmp rowH
        bcc @got
        sbc rowH
        inx
        bne @r
@got:   cpx rows
        bcs @none               ; (below the last whole row)
        stx row
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
@none:  clc
        rts
@open:  lda pick                ; a double click: the entry opened
        sta cur
        lda pick+1
        sta cur+1
        jsr Open
        clc
        rts
@strip: lda tScroll             ; the arrows (their boxes: 9 lines)
        bne @page
        lda mouseYPos
        sec
        sbc stY0
        cmp #9
        bcs :+
        jsr LineUp
        jmp @redraw
:       lda stY1
        sec
        sbc mouseYPos
        cmp #9
        bcs @page
        jsr LineDown
        jmp @redraw
@page:  lda count               ; above or below the thumb: a page
        ora count+1
        beq @none
        lda mouseYPos
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

; LineUp, LineDown: top a row up or down (within the table; step
; entries: one, or the icon view's row of cells).
LineUp: lda top
        sec
        sbc step
        tax
        lda top+1
        sbc #0
        bcs :+
        lda #0                  ; (above the first: the first)
        tax
:       stx top
        sta top+1
        rts
LineDown:
        lda top                 ; top + rows < count: a step on
        clc
        adc rows
        tax
        lda top+1
        adc #0
        cmp count+1
        bne :+
        cpx count
:       bcs @end
        lda top
        clc
        adc step
        sta top
        bcc @end
        inc top+1
@end:   rts

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
        sbc rows
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
        adc rows
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

; ListEnd (the toolbar's end button): the cursor on the last entry,
; only it selected, the list drawn.
ListEnd:
        lda count
        ora count+1
        beq @end
        lda count
        sec
        sbc #1
        sta cur
        lda count+1
        sbc #0
        sta cur+1
        jsr ClearSel
        lda cur
        ldx cur+1
        ldy #1
        jsr Select
        jsr Follow
        jmp ListDraw
@end:   rts

; SelAll (the toolbar's select all): every entry selected but ".." (the
; first, below "/"), the list drawn.
SelAll: jsr ClearSel
        lda count               ; whole bytes: count / 8
        sta tmp
        lda count+1
        sta tmpH
        ldx #3
@div:   lsr tmpH
        ror tmp
        dex
        bne @div
        ldx tmp                 ; (ENTRY_MAX entries: 256 bytes, X 0 and
        lda tmpH                ; tmpH 1: all 256 filled)
        bne :+
        txa
        beq @rest
:       lda #$FF
@all:   dex
        sta sel,x
        bne @all
@rest:  lda count               ; the last byte's bits: count & 7
        and #7
        tay
        lda #0
@bit:   dey
        bmi @last
        sec
        rol a
        bne @bit
@last:  ldx tmpH                 ; (all 256 bytes full: no rest)
        bne @dotdot
        ldx tmp
        ora sel,x
        sta sel,x
@dotdot:
        lda path + 1            ; below "/": ".." not
        beq @draw
        lda #0
        tax
        tay
        jsr Select
@draw:  jmp ListDraw
        .assert ENTRY_MAX <= 2048, error, "SelAll: sel at most 256 bytes"

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
@below: lda top                 ; cur >= top + rows: top = cur - rows + 1
        clc
        adc rows
        tax
        lda top+1
        adc #0
        cmp cur+1
        bne :+
        cpx cur
:       beq @move
        bcs @end
@move:  lda cur                 ; (+ step: the cursor's row of cells the
        sec                     ; last, once AlignTop rounds down)
        sbc rows
        sta top
        lda cur+1
        sbc #0
        sta top+1
        lda top
        clc
        adc step
        sta top
        bcc @end
        inc top+1
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
textX:          .byte 0         ; Text's x
textClip:       .word LIST_RIGHT ; and its right edge
unit:           .byte 'K'       ; SizeKB
word:           .byte 0         ; Status: the entries' word
progN:          .word 0         ; ProgressStart: the item,
progTotal:      .word 0         ; of so many
progLen:        .byte 0         ; its text's length
regSave:        .res R_LEN      ; ProgressBlock: the engine's r0-r15
ry:             .byte 0         ; DrawRow's top
selNow:         .byte 0
cx:             .byte 0         ; the title's x
tw:             .byte 0         ; its width
digit:          .byte 0
any:            .byte 0
freeOK:         .byte 0         ; FreeRead: 1 when freeVal holds the space
freeVal:        .word 0
freeMB:         .byte 'K'
freePre:        .res FREE_PRE_MAX + 2

        .segment "BSS"

path:           .res 256
entryInfo:      .res INFO_LEN
entryName:      .res NAME_LEN + 2
sel:            .res ENTRY_MAX / 8
stBuf:          .res ST_BUF_LEN ; the status line's text
