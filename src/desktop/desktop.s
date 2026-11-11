; GeoUltra Desktop (docs/DESKTOP.md): GeoUltra's own desktop, milestone
; 1. This file: the start, the menus (geos with the desk accessories,
; drive E's merged in by the kernal; file with the actions; view with
; the themes; disk), the sidebar (drives A-D that are there, drive E,
; the Ultimate's roots; favourites and recent documents from side.s),
; the mouse and key routines that hand on to the list (list.s), opening
; (open.s) and the actions (actions.s). Drawn in the theme's look
; (theme.s, step D7a) on both screens; RecoverVector = Recover (theme.s),
; so menus and dialogs give back the bitmap and the colours under them.
; Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .import ListRead, ListDraw, ListPress, ListKey, Drive, Open, Back
        .import OvlInit, clipCount
        .import Copy, Cut, Paste, Delete, Rename, NewFolder, path
        .import SideLoad, SideLists, SidePress, FavAdd, ThemeSave, ClockSave
        .import ViewSave, ToolbarSave, ToolDraw, ToolPress, tbMode, topY, Derive
        .import HistAdd
        .import Eject, HasImage, EjectIcon, IconUp
        .import ThemeSet, ThemeName, themeNo, Paint, px0, px1, py0, py1, pcol
        .import ThemeUse, themeNames, themeCount, curName, hasPal, PalReset
        .import PaintAll, PaintSide, Neutral, Dialog, MenuNeutral, Recover
        .import ClockDraw, ClockTick, TextWidth, boldOn, clockMode, viewMode
        .import tHead, tIcons, cHeadP, cSide, cSideIconP, cSideAccentP
        .import sideW, ejectCard, sideTx, rowH, bottom
        .export FileEngine, Redraw, SideRedraw, SideHeading, SideItem, SideGap
        .export SideArrows, View
        .export itemText, itemName, itemIcon, itemEject

FE_ENTRY        = 30            ; the file engine: guExtTable + 30
SIDE_MAX        = 16            ; sidebar lines a click can choose
HEAD_STEP       = 10            ; a heading's lines and the gap after it
SECTION_GAP     = 3             ; between the sidebar's sections
NAME_DX         = 10            ; a drive's disk name after its letter
DA_MAX          = 8             ; desk accessories in the geos menu
DA_NAME_LEN     = 17            ; a GEOS name and its zero
THEME_ITEM      = 16            ; a view menu theme item: "* " and a name
THEME_NAME      = 15            ; a theme's name (themefile.s NAME_MAX)
THEMES_MAX      = 8             ; theme files the menu lists
MENU_ITEMS      = 7             ; a menu table's first item (after its frame)

        .segment "CODE"

; Start: the theme (the built-in default, or SETTINGS.INI's, side.s),
; the screen drawn, the menu installed, the clock ticking (appMain);
; back to MainLoop.
Start:  jsr OvlInit             ; (ovl.s: the overlays into the REU, while
        lda #0                  ; dirEntryBuf still holds our entry)
        sta clipCount           ; (actions.s: an empty clipboard)
        sta clipCount+1
        lda guExtTable          ; FileEngine: the extension table + 30
        clc
        adc #FE_ENTRY
        sta feVec
        lda guExtTable+1
        adc #0
        sta feVec+1
        jsr UseSystemFont
        lda #ST_WR_FORE | ST_WR_BACK ; both screens: the background holds
        sta dispBufferOn        ; what menus and accessories give back
        lda #<Recover           ; menus and dialogs give back what was
        sta RecoverVector       ; under them, colours too (theme.s)
        lda #>Recover
        sta RecoverVector+1
        lda #0                  ; the default theme, then SETTINGS.INI's
        jsr ThemeSet
        jsr SideLoad            ; favourites, recent documents, the theme
        jsr Draw
        jsr HistAdd             ; (the first place in the history)
        lda #<mainMenu
        sta r0L
        lda #>mainMenu
        sta r0H
        lda #<Press             ; mouse presses outside menus and keys
        sta otherPressVec
        lda #>Press
        sta otherPressVec+1
        lda #<Key
        sta keyVector
        lda #>Key
        sta keyVector+1
        lda #<ClockTick
        sta appMain
        lda #>ClockTick
        sta appMain+1
        lda #0
        jmp DoMenu

; Press (otherPressVec): a press (not a release) in the list, else on a
; sidebar line (its drive's root; on a drive's eject icon its unmount).
Press:  lda mouseData
        bmi @end
        jsr ToolPress           ; (C clear: it was on the toolbar)
        bcc @end
        jsr ListPress
        bcc @end
        lda mouseXPos+1         ; the sidebar: x left of its line
        bne @end
        lda sideW
        sec
        sbc #1
        sta tmp
        lda mouseXPos
        cmp tmp
        bcs @end
        ldx #0                  ; the line whose rows hold the pointer
@line:  cpx sideCount
        bcs @end
        lda mouseYPos
        sec
        sbc sideTops,x
        bcc @next
        cmp rowH
        bcs @next
        lda sideLetters,x
        bmi @lists
        cmp #'e'                ; A-D: on the eject icon (mount.s; a
        bcs @drive              ; drive without an image: entered)
        cmp #'a'
        bcc @drive
        pha
        lda ejectCard
        asl a
        asl a
        asl a
        sta tmp
        pla
        ldy mouseXPos
        cpy tmp
        bcc @drive
        jmp Eject
@drive: jmp Drive
@lists: jmp SidePress           ; (a favourite or recent document)
@next:  inx
        bne @line
@end:   rts

; Key (keyVector): the actions' keys (C= + c, x, v, r, n, o, f; DEL),
; else the list's.
Key:    lda keyData
        ldx #KeyActs_n - 1
@k:     cmp KeyActs,x
        beq @act
        dex
        bpl @k
        jmp ListKey
@act:   txa
        asl a
        tax
        lda ActDo+1,x
        pha
        lda ActDo,x
        pha
        rts

KeyActs:
        .byte SHORTCUT | 'c', SHORTCUT | 'x', SHORTCUT | 'v'
        .byte SHORTCUT | 'r', SHORTCUT | 'n', KEY_DELETE, SHORTCUT | 'o'
        .byte SHORTCUT | 'f'
KeyActs_n = * - KeyActs
ActDo:  .word Copy-1, Cut-1, Paste-1, Rename-1, NewFolder-1, Delete-1, Open-1
        .word FavAdd-1

; The file menu's items: the menus closed, then the action.
MOpen:  jsr GotoFirstMenu
        jmp Open
MCopy:  jsr GotoFirstMenu
        jmp Copy
MCut:   jsr GotoFirstMenu
        jmp Cut
MPaste: jsr GotoFirstMenu
        jmp Paste
MDelete:
        jsr GotoFirstMenu
        jmp Delete
MRename:
        jsr GotoFirstMenu
        jmp Rename
MNew:   jsr GotoFirstMenu
        jmp NewFolder
MFav:   jsr GotoFirstMenu
        jmp FavAdd

; FileEngine: A = function, Y = handle, r0-r4 (FILE_ENGINE.md).
FileEngine:
        jmp (feVec)

; Draw, Redraw: the whole screen in the theme: its colours, the menu
; bar's row white across with a line under it, the clock, the list read
; again (first: the sidebar's arrow follows its path), the sidebar, the
; list drawn.
Redraw:
Draw:   jsr PaintAll
        lda #0
        jsr SetPattern
        lda #0
        sta r2L
        lda #199
        sta r2H
        jsr Across
        jsr Rectangle
        lda #MENU_BOTTOM
        sta r11L
        jsr Across
        lda #$FF
        jsr HorizontalLine
        jsr ClockDraw
        jsr ToolDraw            ; (toolbar.s; nothing when it is off)
        jsr ListRead
        jsr Sidebar
        jmp ListDraw

; Across: r3-r4 = x 0 to 319.
Across: lda #0
        sta r3L
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        rts

; Sidebar: its colours and its line (x sideW - 1), "DRIVES" with a line
; per drive (A-D that are there, then E, the system drive), the
; Ultimate's roots, favourites and recent documents.
Sidebar:
        jsr PaintSide
        ldx topY                ; (from the line above the content: under
        dex                     ; the menu bar's, or the toolbar's)
        stx r3L
        lda bottom
        sta r3H
        lda sideW
        sec
        sbc #1
        sta r4L
        lda #0
        sta r4H
        lda #$FF
        jsr VerticalLine
        jsr OpenCode
        lda topY
        sta sideY
        lda #0
        sta sideCount
        lda #<DrivesText
        ldx #>DrivesText
        jsr SideHeading
        lda curDrive            ; (DiskName opens each drive)
        sta homeDrive
        ldx #0
@drive: stx drv
        lda driveType,x
        beq @next
        jsr DiskName            ; its disk's name after the letter
        lda drv
        clc
        adc #'A'
        sta driveLine
        lda #<driveLine
        sta itemText
        lda #>driveLine
        sta itemText+1
        lda #<dname
        sta itemName
        lda #>dname
        sta itemName+1
        ldx drv                 ; a native drive: its own icon
        lda driveType,x
        and #$0F
        cmp #DRV_NATIVE
        lda #IC_DRIVE
        bcc :+
        lda #IC_RAM
:       sta itemIcon
        lda drv                 ; an image there: the eject icon
        jsr HasImage
        lda #0
        bcs :+
        lda #1
:       sta itemEject
        lda drv
        clc
        adc #'a'
        jsr SideItem
@next:  ldx drv
        inx
        cpx #4
        bcc @drive
        lda homeDrive           ; the current drive again
        jsr SetDevice
        jsr OpenDisk
        lda #<ELetter           ; drive E, as the others
        sta itemText
        lda #>ELetter
        sta itemText+1
        lda #<SystemText
        sta itemName
        lda #>SystemText
        sta itemName+1
        lda #IC_DRIVE
        sta itemIcon
        lda #0
        sta itemEject
        lda #'e'
        jsr SideItem
        jmp Ultimate

; OpenCode: openCode = the sidebar code of the drive or Ultimate root
; the list is in ('a'-'e', '0', '1', 's'; 0 at "/"), for its arrow.
OpenCode:
        lda #0
        sta openCode
        lda path + 1
        beq @end
        ldx path + 2
        beq @set                ; "/b" or "/b/...": the letter
        cpx #'/'
        beq @set
        cmp #'u'                ; "/usb0", "/usb1": the digit
        bne :+
        lda path + 4
        bne @set
:       cmp #'s'                ; "/sd"
        bne @end
@set:   sta openCode
@end:   rts

; Ultimate: "ULTIMATE" and a line for each of the Ultimate's roots that
; is there (the root listing's Ultimate folders: none without a Command
; Interface); its sidebar code '0' (usb0), '1' (usb1), 's' (sd), for
; Drive (open.s).
Ultimate:
        lda #<rootPath
        sta r0L
        lda #>rootPath
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        bne @end
        lda #0
        sta any
@entry: lda #<uInfo
        sta r1L
        lda #>uInfo
        sta r1H
        lda #<dname
        sta r2L
        lda #>dname
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        lda uInfo               ; (FI_KIND)
        cmp #K_UDIR
        bne @entry
        lda any                 ; the heading before the first
        bne @line
        inc any
        jsr SideGap
        lda #<UltText
        ldx #>UltText
        jsr SideHeading
@line:  lda #<dname
        sta itemText
        lda #>dname
        sta itemText+1
        lda #0
        sta itemName+1
        sta itemEject
        lda dname               ; its code: "usb0" '0', "usb1" '1', "sd" 's'
        ldx dname + 2           ; (a two-letter name: its first letter;
        beq :+                  ; dname + 3 still holds an earlier name's)
        lda dname + 3
:       ldx #IC_SD
        cmp #'s'
        beq :+
        ldx #IC_USB
:       stx itemIcon
        jsr SideItem
        jmp @entry
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
@end:   jmp SideLists           ; favourites, recent documents (side.s)

; SideRedraw: the sidebar cleared and drawn again (side.s, mount.s); the
; current drive put back.
SideRedraw:
        lda #0
        jsr SetPattern
        lda topY
        sta r2L
        lda bottom
        sta r2H
        lda #0
        sta r3L
        sta r3H
        sta r4H
        lda sideW
        sta r4L
        dec r4L
        jsr Rectangle
        jmp Sidebar

; SideArrows: the open drive's arrow moved to the line of the drive or
; root the list is in now (open.s, Into; side.s): column 0 of each
; sidebar line cleared, the arrow drawn on the one that matches.
SideArrows:
        jsr OpenCode
        ldx #0
@line:  cpx sideCount
        bcs @end
        stx at
        lda sideTops,x
        sta sideY
        lda #0
        jsr SetPattern
        lda sideY
        sta r2L
        clc
        adc #7
        sta r2H
        lda #0
        sta r3L
        sta r3H
        sta r4H
        lda #7
        sta r4L
        jsr Rectangle
        lda #0
        sta px0
        sta px1
        lda cSide
        jsr ItemCells
        ldx at
        lda sideLetters,x
        cmp openCode
        bne @next
        lda #0
        sta px0
        sta px1
        lda cSideAccentP
        jsr ItemCells
        lda #IC_ARROW
        ldx #0
        ldy sideY
        jsr IconUp
@next:  ldx at
        inx
        bne @line
@end:   rts

; SideGap: a few lines between the sidebar's sections.
SideGap:
        lda sideY
        clc
        adc #SECTION_GAP
        sta sideY
        rts

; SideHeading: the heading text at A/X (plain, no style codes) on the
; next cell row, in the theme's heading style: inverted (a box around
; the text), band (the sidebar's width), underlined, plain (bold). C
; set when there is no room left.
SideHeading:
        sta hText
        stx hText+1
        lda sideY               ; on a cell row
        clc
        adc #7
        and #$F8
        sta sideY
        clc
        adc #7
        cmp bottom
        bcc :+
        beq :+
        sec
        rts
:       lda tHead
        cmp #ST_PLAIN
        beq @text               ; (plain: no colours of its own)
        lda #0                  ; the heading colours on its cells
        sta px0
        lda sideW
        sec
        sbc #2
        lsr a
        lsr a
        lsr a
        sta px1
        lda sideY
        lsr a
        lsr a
        lsr a
        sta py0
        sta py1
        lda cHeadP
        sta pcol
        jsr Paint
@text:  lda tHead               ; bold when underlined or plain
        cmp #ST_UNDERLINED
        bcc :+
        lda #SET_BOLD
        sta currentMode
        lda #1
        sta boldOn
:       lda #4
        sta tx
        lda sideY
        clc
        adc #6
        tay
        lda sideW
        sec
        sbc #3
        sta clip
        lda hText
        ldx hText+1
        jsr SideText
        lda #0
        sta currentMode
        sta boldOn
        lda tHead
        cmp #ST_UNDERLINED
        beq @under
        bcs @done               ; (plain)
        lda sideY               ; inverted or band: the box inverted
        sta r2L
        clc
        adc #7
        sta r2H
        lda #0
        sta r3H
        sta r4H
        lda tHead
        bne @band
        lda #2                  ; inverted: x 2 to the text's end + 6
        sta r3L
        lda hText
        sta r0L
        lda hText+1
        sta r0H
        jsr TextWidth
        lda r2L
        clc
        adc #4 + 6
        sta r4L
        lda sideY               ; (TextWidth used r2)
        sta r2L
        clc
        adc #7
        sta r2H
        jmp @inv
@band:  lda #0
        sta r3L
        lda sideW
        sec
        sbc #2
        sta r4L
@inv:   jsr InvertRectangle
        jmp @done
@under: lda sideY               ; underlined: a line under it
        clc
        adc #7
        sta r11L
        lda #3
        sta r3L
        lda #0
        sta r3H
        sta r4H
        lda sideW
        sec
        sbc #5
        sta r4L
        lda #$FF
        jsr HorizontalLine
@done:  lda sideY
        clc
        adc #HEAD_STEP
        sta sideY
        clc
        rts

; SideItem: a sidebar line with code A at sideY: the open drive's arrow
; (openCode), its icon (itemIcon, when the theme has icons), itemText
; and, when itemName+1 is not 0, itemName after it (a drive's disk
; name), the eject icon when itemEject. C set when there is no room
; left (nothing drawn).
SideItem:
        sta code
        lda sideY
        clc
        adc #7
        cmp bottom
        bcc :+
        beq :+
        sec
        rts
:       lda code
        jsr SideLine
        lda code                ; the open drive or root: an arrow
        cmp openCode
        bne @icon
        lda #0
        sta px0
        sta px1
        lda cSideAccentP
        jsr ItemCells
        lda #IC_ARROW
        ldx #0
        ldy sideY
        jsr IconUp
@icon:  lda tIcons
        bne @text
        lda #1
        sta px0
        sta px1
        lda cSideIconP
        jsr ItemCells
        lda itemIcon
        ldx #1
        ldy sideY
        jsr IconUp
@text:  lda sideW               ; clipped at the edge, or before the eject
        sec                     ; icon
        sbc #3
        ldx itemEject
        beq :+
        lda ejectCard
        asl a
        asl a
        asl a
        sec
        sbc #2
:       sta clip
        lda sideTx
        sta tx
        lda sideY
        clc
        adc #BASELINE
        tay
        lda itemText
        ldx itemText+1
        jsr SideText
        lda itemName+1
        beq @eject
        lda sideTx
        clc
        adc #NAME_DX
        sta tx
        lda sideY
        clc
        adc #BASELINE
        tay
        lda itemName
        ldx itemName+1
        jsr SideText
@eject: lda itemEject
        beq @next
        jsr EjectUp
@next:  lda sideY
        clc
        adc rowH
        sta sideY
        clc
        rts

; ItemCells: cells px0-px1, the rows of the line at sideY, get colour A.
ItemCells:
        sta pcol
        lda sideY
        lsr a
        lsr a
        lsr a
        sta py0
        lda sideY
        clc
        adc #7
        lsr a
        lsr a
        lsr a
        sta py1
        jmp Paint

; SideLine: a sidebar line for a click: code A (a drive letter, or an
; Ultimate root's code, open.s, Drive; with bit 7 a favourite or recent
; document, side.s), its top row sideY.
SideLine:
        ldy sideCount
        cpy #SIDE_MAX
        bcs @end
        sta sideLetters,y
        lda sideY
        sta sideTops,y
        inc sideCount
@end:   rts

; EjectUp: the eject icon on the sidebar line at sideY.
EjectUp:
        lda #<EjectIcon
        sta r0L
        lda #>EjectIcon
        sta r0H
        lda ejectCard
        sta r1L
        lda sideY
        sta r1H
        lda #1
        sta r2L
        lda #8
        sta r2H
        jmp BitmapUp

; SideText: the text at A/X at x tx, baseline Y, clipped at clip.
SideText:
        sta r0L
        stx r0H
        sty r1H
        lda tx
        sta r11L
        lda #0
        sta r11H
        sta rightMargin+1
        lda clip
        sta rightMargin
        jsr PutString
        lda #<SCREEN_RIGHT      ; (the whole width again)
        sta rightMargin
        lda #>SCREEN_RIGHT
        sta rightMargin+1
        rts

; DiskName: dname = drive drv's disk name (OpenDisk gives r5 = it,
; padded with $A0); empty when the disk cannot be opened. Sidebar puts
; the current drive back.
DiskName:
        lda #0
        sta dname
        lda drv
        clc
        adc #8
        jsr SetDevice
        jsr OpenDisk
        txa
        bne @end
        ldy #0
@ch:    lda (r5),y
        cmp #$A0
        beq @zero
        sta dname,y
        iny
        cpy #DA_NAME_LEN - 1
        bcc @ch
@zero:  lda #0
        sta dname,y
@end:   rts

; --- Menus --------------------------------------------------------------
; Every submenu is a DYN_SUB_MENU: its routine paints GEOS's colours
; under it (MenuNeutral) before GEOS draws it.

; GeosMenu: "GeoUltra info" and the desk accessories (FindFTypes; drive
; E's added by the kernal) into geosMenu. r0 = it.
GeosMenu:
        lda #<daNames
        sta r6L
        lda #>daNames
        sta r6H
        lda #DESK_ACC
        sta r7L
        lda #DA_MAX
        sta r7H
        lda #0
        sta r10L
        sta r10H
        jsr FindFTypes
        lda #DA_MAX             ; found: DA_MAX - what was left
        sec
        sbc r7H
        sta daCount
        clc                     ; items: info and the accessories
        adc #1
        ora #VERTICAL | UN_CONSTRAINED
        sta geosMenu + 6
        lda daCount             ; its bottom: MENU_BOTTOM + 14 per item
        clc
        adc #1
        jsr MenuBottom
        sta geosMenu + 1
        ldx #0                  ; the accessories' items
        ldy #0
@item:  cpx daCount
        bcs @done
        lda DaLo,x
        sta geosItems + 5,y
        lda DaHi,x
        sta geosItems + 6,y
        lda #MENU_ACTION
        sta geosItems + 7,y
        lda #<RunDA
        sta geosItems + 8,y
        lda #>RunDA
        sta geosItems + 9,y
        tya
        clc
        adc #5
        tay
        inx
        bne @item
@done:  lda #<geosMenu
        ldx #>geosMenu
        jmp MenuR0

; MenuBottom: A = MENU_BOTTOM + 14 * A (a menu of A items).
MenuBottom:
        asl a
        sta tmp
        asl a
        asl a
        asl a
        sec
        sbc tmp                 ; (* 14)
        clc
        adc #MENU_BOTTOM
        rts

; FileMenu, ViewMenu, DiskMenu: r0 = their tables, GEOS's colours under
; them. ViewMenu marks the theme in use with "*".
FileMenu:
        lda #<fileMenu
        ldx #>fileMenu
        bne MenuR0
DiskMenu:
        lda #<diskMenu
        ldx #>diskMenu
        bne MenuR0
ViewMenu:
        lda #<viewMenu          ; theme, view, clock: submenus
        ldx #>viewMenu
MenuR0: sta r0L
        stx r0H
        jmp MenuNeutral

; ThemeMenu (view > theme): the theme files in THEMES (themefile.s), or
; the built-in themes without them; each item "* " (the one in use,
; curName) or "  " and its name.
ThemeMenu:
        lda themeCount
        bne :+
        lda #THEMES_N
:       sta nThemes
        jsr MenuBottom
        sta themeMenu + 1
        lda nThemes
        ora #VERTICAL | UN_CONSTRAINED
        sta themeMenu + 6
        ldx #0
@theme: stx at
        txa
        jsr ThemeAt             ; r1 = its name
        lda at
        asl a                   ; its item: themeItems + at * THEME_ITEM
        asl a
        asl a
        asl a
        tax
        jsr IsCurrent           ; (A: "*" or " "; keeps X)
        sta themeItems,x
        lda #' '
        sta themeItems + 1,x
        ldy #0
@ch:    lda (r1),y
        sta themeItems + 2,x
        beq :+
        inx
        iny
        cpy #THEME_ITEM - 3
        bcc @ch
        lda #0
        sta themeItems + 2,x
:       ldx at
        inx
        cpx nThemes
        bcc @theme
        lda #<themeMenu
        ldx #>themeMenu
        jmp MenuR0

; ViewsMenu (view > view), ClockMenu (view > clock): "*" before the
; choice in use.
ViewsMenu:
        ldy viewMode
        lda #<viewsMenu
        ldx #>viewsMenu
        bne Marks
ToolbarMenu:
        ldy tbMode
        lda #<toolbarMenu
        ldx #>toolbarMenu
        bne Marks
ClockMenu:
        ldy clockMode
        lda #<clockMenu
        ldx #>clockMenu
; Marks: the menu at A/X (three items): its items' first character "*"
; for item Y, " " for the others; then r0 = it, GEOS's colours under it.
Marks:  sta r0L
        stx r0H
        sty at
        ldy #MENU_ITEMS         ; each item's text: its first word
        ldx #0
@item:  lda (r0),y
        sta r1L
        iny
        lda (r0),y
        sta r1H
        iny
        iny                     ; (the type and the routine)
        iny
        iny
        tya
        pha
        lda #' '
        cpx at
        bne :+
        lda #'*'
:       ldy #0
        sta (r1),y
        pla
        tay
        inx
        cpx #3
        bcc @item
        jmp MenuNeutral         ; (r0: the menu)

; Info (geos > GeoUltra info): a dialog naming the desktop.
Info:   jsr GotoFirstMenu
        lda #<infoDlg
        sta r0L
        lda #>infoDlg
        sta r0H
        jmp Dialog

; RunDA (geos > an accessory; A = the item: 1 the first accessory): in
; GEOS's colours; the desktop drawn again when it ends.
RunDA:  sta tmp
        jsr GotoFirstMenu
        ldx tmp
        dex
        lda DaLo,x
        sta r6L
        lda DaHi,x
        sta r6H
        jsr Neutral
        lda #0
        sta r0L
        jsr GetFile
        jmp Back                ; (open.s: Redraw and the menu bar)

; Theme (view > theme > a theme; A = the item, 0 the first): in use
; (themefile.s: its file over the built-in theme) with its view, saved
; (side.s, SETTINGS.INI [desktop]), the screen drawn in it.
Theme:  sta tmp
        jsr GotoFirstMenu
        lda hasPal              ; (the theme left had a palette?)
        sta tmp2
        lda tmp
        jsr ThemeAt
        lda r1L
        sta r0L
        lda r1H
        sta r0H
        jsr ThemeUse
        lda tmp2                ; it had, the new one has none: the
        beq :+                  ; Ultimate's own palette back
        lda hasPal
        bne :+
        jsr PalReset
:       jsr ThemeSave
        jmp Back

; ThemeAt: r1 = the name of the theme menu's item A (a file's, or a
; built-in theme's without files). Keeps nothing.
ThemeAt:
        ldx themeCount
        beq @built
        tax                     ; themeNames + A * THEME_NAME
        lda #<themeNames
        sta r1L
        lda #>themeNames
        sta r1H
@add:   dex
        bmi @end
        lda r1L
        clc
        adc #THEME_NAME
        sta r1L
        bcc @add
        inc r1H
        bne @add
@end:   rts
@built: jmp ThemeName

; IsCurrent: A = "*" when the name at r1 is curName (any case), else
; " ". Keeps X.
IsCurrent:
        ldy #0
@ch:    lda (r1),y
        beq @end
        ora #$20
        sta tmp
        lda curName,y
        ora #$20
        cmp tmp
        bne @no
        iny
        bne @ch
@end:   lda curName,y           ; (both end here)
        bne @no
        lda #'*'
        rts
@no:    lda #' '
        rts

; View (view > view > list, icons, detailed; A = the item): the list
; drawn that way (icons: the list for now, a later step), saved.
View:   sta tmp
        jsr GotoFirstMenu
        lda tmp
        sta viewMode
        jsr ViewSave
        jmp ListDraw

; Toolbar (view > toolbar > two lines, one line, off; A = the item):
; the layout derived anew, saved, the screen and the menu drawn again
; (Back, as after a theme).
Toolbar:
        sta tmp
        jsr GotoFirstMenu
        lda tmp
        sta tbMode
        jsr Derive
        jsr ToolbarSave
        jmp Back                ; (open.s: drawn again, the menu too)

; Clock (view > clock > 24-hour, 12-hour, off; A = the item): saved,
; drawn again.
Clock:  sta tmp
        jsr GotoFirstMenu
        lda tmp
        sta clockMode
        jsr ClockSave
        jmp ClockDraw

; Gush (file > gush): GeoUltra's shell in the desktop's place.
Gush:   jsr GotoFirstMenu
        jsr Neutral
        lda #<GushName
        sta r0L
        lda #>GushName
        sta r0H
        lda #FE_RUNSYS
        jsr FileEngine          ; (back only when it cannot start)
        jmp Back

; Refresh (disk > refresh): the list read again.
Refresh:
        jsr GotoFirstMenu
        jsr ListRead
        jmp ListDraw

; The accessories' names in daNames, DA_NAME_LEN apart.
DaLo:   .repeat DA_MAX, i
        .byte <(daNames + i * DA_NAME_LEN)
        .endrepeat
DaHi:   .repeat DA_MAX, i
        .byte >(daNames + i * DA_NAME_LEN)
        .endrepeat

DrivesText:     .byte "Drives", 0     ; (sentence case: the user, 2026-11-11)
UltText:        .byte "Ultimate", 0
rootPath:       .byte "/", 0
ELetter:        .byte "E", 0
SystemText:     .byte "System", 0
GushName:       .byte "gush", 0

        .segment "DATA"

mainMenu:
        .byte 0, MENU_BOTTOM
        .word 0, 129
        .byte HORIZONTAL | UN_CONSTRAINED | 4
        .word GeosText
        .byte DYN_SUB_MENU
        .word GeosMenu
        .word FileText
        .byte DYN_SUB_MENU
        .word FileMenu
        .word ViewText
        .byte DYN_SUB_MENU
        .word ViewMenu
        .word DiskText
        .byte DYN_SUB_MENU
        .word DiskMenu

geosMenu:
        .byte MENU_BOTTOM, MENU_BOTTOM + 14
        .word 0, 99
        .byte VERTICAL | UN_CONSTRAINED | 1
geosItems:
        .word InfoText
        .byte MENU_ACTION
        .word Info
        .res DA_MAX * 5         ; (the accessories, GeosMenu)

fileMenu:
        .byte MENU_BOTTOM, MENU_BOTTOM + 9 * 14
        .word 30, 129
        .byte VERTICAL | UN_CONSTRAINED | 9
        .word OpenItem
        .byte MENU_ACTION
        .word MOpen
        .word CopyItem
        .byte MENU_ACTION
        .word MCopy
        .word CutItem
        .byte MENU_ACTION
        .word MCut
        .word PasteItem
        .byte MENU_ACTION
        .word MPaste
        .word DeleteItem
        .byte MENU_ACTION
        .word MDelete
        .word RenameItem
        .byte MENU_ACTION
        .word MRename
        .word NewItem
        .byte MENU_ACTION
        .word MNew
        .word FavItem
        .byte MENU_ACTION
        .word MFav
        .word GushItem
        .byte MENU_ACTION
        .word Gush

viewMenu:
        .byte MENU_BOTTOM, MENU_BOTTOM + 4 * 14
        .word 58, 109
        .byte VERTICAL | UN_CONSTRAINED | 4
        .word ThemeText
        .byte DYN_SUB_MENU
        .word ThemeMenu
        .word ViewsText
        .byte DYN_SUB_MENU
        .word ViewsMenu
        .word ClockText
        .byte DYN_SUB_MENU
        .word ClockMenu
        .word ToolbarText
        .byte DYN_SUB_MENU
        .word ToolbarMenu

themeMenu:                              ; (beside the view menu's items;
        .byte MENU_BOTTOM, MENU_BOTTOM + THEMES_N * 14  ; ThemeMenu sets the
        .word 110, 199                                  ; bottom and count)
        .byte VERTICAL | UN_CONSTRAINED | THEMES_N
        .repeat THEMES_MAX, i
        .word themeItems + i * THEME_ITEM
        .byte MENU_ACTION
        .word Theme
        .endrepeat

viewsMenu:
        .byte MENU_BOTTOM + 14, MENU_BOTTOM + 14 + 3 * 14
        .word 110, 179
        .byte VERTICAL | UN_CONSTRAINED | 3
        .word ListItem
        .byte MENU_ACTION
        .word View
        .word IconsItem
        .byte MENU_ACTION
        .word View
        .word DetailedItem
        .byte MENU_ACTION
        .word View

clockMenu:
        .byte MENU_BOTTOM + 28, MENU_BOTTOM + 28 + 3 * 14
        .word 110, 179
        .byte VERTICAL | UN_CONSTRAINED | 3
        .word Hour24Item
        .byte MENU_ACTION
        .word Clock
        .word Hour12Item
        .byte MENU_ACTION
        .word Clock
        .word OffItem
        .byte MENU_ACTION
        .word Clock

toolbarMenu:
        .byte MENU_BOTTOM + 42, MENU_BOTTOM + 42 + 3 * 14
        .word 110, 179
        .byte VERTICAL | UN_CONSTRAINED | 3
        .word TwoLineItem
        .byte MENU_ACTION
        .word Toolbar
        .word OneLineItem
        .byte MENU_ACTION
        .word Toolbar
        .word TbOffItem
        .byte MENU_ACTION
        .word Toolbar

diskMenu:
        .byte MENU_BOTTOM, MENU_BOTTOM + 14
        .word 90, 149
        .byte VERTICAL | UN_CONSTRAINED | 1
        .word RefreshItem
        .byte MENU_ACTION
        .word Refresh

infoDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word InfoLine1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word InfoLine2
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0

GeosText:       .byte "geos", 0
FileText:       .byte "file", 0
ViewText:       .byte "view", 0
DiskText:       .byte "disk", 0
InfoText:       .byte "GeoUltra info", 0
GushItem:       .byte "gush", 0
OpenItem:       .byte "open      C=O", 0
CopyItem:       .byte "copy      C=C", 0
CutItem:        .byte "cut       C=X", 0
PasteItem:      .byte "paste     C=V", 0
DeleteItem:     .byte "delete    DEL", 0
RenameItem:     .byte "rename    C=R", 0
NewItem:        .byte "new folder C=N", 0
FavItem:        .byte "favourite  C=F", 0
ThemeText:      .byte "theme", 0
ViewsText:      .byte "view", 0
ClockText:      .byte "clock", 0
ListItem:       .byte "  list", 0      ; (Marks: "*" at the first character)
IconsItem:      .byte "  icons", 0
DetailedItem:   .byte "  detailed", 0
Hour24Item:     .byte "  24-hour", 0
Hour12Item:     .byte "  12-hour", 0
OffItem:        .byte "  off", 0
ToolbarText:    .byte "toolbar", 0
TwoLineItem:    .byte "  two lines", 0
OneLineItem:    .byte "  one line", 0
TbOffItem:      .byte "  off", 0          ; (its own: Marks writes into it)
RefreshItem:    .byte "refresh", 0
InfoLine1:      .byte BOLDON, "GeoUltra Desktop", PLAINTEXT, 0
InfoLine2:      .byte "milestone 1 (in development)", 0
driveLine:      .byte "A", 0

feVec:          .word 0
sideY:          .byte 0         ; the next sidebar line's top
drv:            .byte 0
homeDrive:      .byte 0
sideCount:      .byte 0
sideLetters:    .res SIDE_MAX   ; each sidebar line's code (Drive)
sideTops:       .res SIDE_MAX   ; and its top pixel row
handle:         .byte 0
any:            .byte 0
tmp:            .byte 0
tmp2:           .byte 0
at:             .byte 0
daCount:        .byte 0
nThemes:        .byte 0         ; the theme menu's items
openCode:       .byte 0         ; the drive or root the list is in
code:           .byte 0
tx:             .byte 0         ; SideText's x
clip:           .byte 0         ; and right edge
hText:          .word 0
itemText:       .word 0         ; SideItem's line
itemName:       .word 0
itemIcon:       .byte 0
itemEject:      .byte 0

        .segment "BSS"

dname:          .res 64
uInfo:          .res 16
daNames:        .res DA_MAX * DA_NAME_LEN
themeItems:     .res THEMES_MAX * THEME_ITEM
