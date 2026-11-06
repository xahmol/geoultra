; GeoUltra Desktop (docs/DESKTOP.md): GeoUltra's own desktop, milestone
; 1, step D1: the frame. The menu bar (geos with the desk accessories,
; drive E's merged in by the kernal; file; view; disk), the sidebar with
; the drives that are there and drive E, and the list area with the
; current folder's path and its first names (through the file engine).
; Drawn on both screens, so GEOS recovers menus and desk accessories from
; the background. Own design and code.

        .include "geos.inc"

        .import ListRead, ListDraw, ListPress, ListKey, Drive, Open
        .import Copy, Cut, Paste, Delete, Rename, NewFolder
        .export FileEngine, Redraw

; GEOS jump table
Rectangle       = $C124
FrameRectangle  = $C127
SetPattern      = $C139
PutString       = $C148
UseSystemFont   = $C14B
DoMenu          = $C151
GotoFirstMenu   = $C1BD
GetFile         = $C208
FindFTypes      = $C23B
DoDlgBox        = $C256
RecoverRectangle = $C12D
SetDevice       = $C2B0
OpenDisk        = $C2A1
guExtTable      = $C0E4         ; GeoUltra: the extension table
FE_ENTRY        = 30            ; (its file engine entry)

; The file engine (docs/FILE_ENGINE.md)
FE_STAT         = 1
FE_OPENDIR      = 2
FE_READDIR      = 3
FE_CLOSE        = 4
FE_PWD          = 12
FE_RUNSYS       = 22
FI_KIND         = 0
K_DRIVE         = 1
K_FOLDER        = 2
K_UDIR          = 6

; Layout (docs/DESKTOP.md, "Screen")
MENU_BOTTOM     = 14
SIDE_RIGHT      = 79            ; the sidebar: x 0-79
LIST_LEFT       = 82
PATH_Y          = 24            ; the path line's baseline
LIST_TOP        = 28            ; the list: rows of ROW_H pixels
ROW_H           = 9
ROWS            = 17
LIST_BOTTOM     = LIST_TOP + ROWS * ROW_H
SCREEN_RIGHT    = 319
BASELINE        = 7             ; a row's baseline below its top
SIDE_FIRST      = LIST_TOP      ; the sidebar's first drive line's top

DA_MAX          = 8             ; desk accessories in the geos menu
NAME_LEN        = 17            ; a GEOS name and its zero
LONG_LEN        = 61            ; FE_READDIR's name buffer

        .segment "CODE"

; Start: the screen drawn, the menu installed; back to MainLoop.
Start:  lda guExtTable          ; FileEngine: the extension table + 30
        clc
        adc #FE_ENTRY
        sta feVec
        lda guExtTable+1
        adc #0
        sta feVec+1
        jsr UseSystemFont
        lda #ST_WR_FORE | ST_WR_BACK ; both screens: the background holds
        sta dispBufferOn        ; what menus and accessories give back
        lda #<RecoverRectangle  ; menus and dialogs give back what was
        sta RecoverVector       ; under them (from the background screen;
        lda #>RecoverRectangle  ; GEOS's default 0 erases with white)
        sta RecoverVector+1
        jsr Draw
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
        lda #0
        jmp DoMenu

; Press (otherPressVec): a press (not a release) in the list, else on a
; sidebar line (its drive's root).
Press:  lda mouseData
        bmi @end
        jsr ListPress
        bcc @end
        lda mouseXPos+1         ; the sidebar: x below SIDE_RIGHT, a line
        bne @end
        lda mouseXPos
        cmp #SIDE_RIGHT
        bcs @end
        lda mouseYPos
        sec
        sbc #SIDE_FIRST
        bcc @end
        ldx #0
@line:  cmp #ROW_H
        bcc @got
        sbc #ROW_H
        inx
        bne @line
@got:   cpx sideCount
        bcs @end
        lda sideLetters,x
        jmp Drive
@end:   rts

; Key (keyVector): the actions' keys (C= + c, x, v, r, n; DEL), else
; the list's.
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
KeyActs_n = * - KeyActs
ActDo:  .word Copy-1, Cut-1, Paste-1, Rename-1, NewFolder-1, Delete-1, Open-1

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

; FileEngine: A = function, Y = handle, r0-r4 (FILE_ENGINE.md).
FileEngine:
        jmp (feVec)

; Draw, Redraw: the whole screen: background (the menu bar's row white
; across, a line under it), sidebar, path, list (read again).
Redraw:
Draw:   lda #0
        jsr SetPattern
        lda #0
        ldx #199
        ldy #0
        jsr Box
        lda #1                  ; (a line under the menu bar: pattern 1)
        jsr SetPattern
        lda #MENU_BOTTOM
        ldx #MENU_BOTTOM
        ldy #0
        jsr Box
        jsr Sidebar
        jsr ListRead
        jmp ListDraw

; Box: a rectangle from row A to row X, x 0 to 319 (Y = 0) or the list
; area (Y = 1), in the current pattern.
Box:    sta r2L
        stx r2H
        lda #0
        sta r3H
        sta r4H
        tya
        bne @list
        sta r3L
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        jmp Rectangle
@list:  lda #LIST_LEFT
        sta r3L
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        jmp Rectangle

; Sidebar: its frame, "DRIVES" and a line per drive (A-D that are
; there, then E, the system drive).
Sidebar:
        lda #MENU_BOTTOM + 1    ; the frame: x 0-79
        sta r2L
        lda #199
        sta r2H
        lda #0
        sta r3L
        sta r3H
        sta r4H
        lda #SIDE_RIGHT
        sta r4L
        lda #$FF
        jsr FrameRectangle
        lda #<DrivesText
        ldx #>DrivesText
        ldy #PATH_Y
        jsr SideText
        lda curDrive            ; (DiskName opens each drive)
        sta homeDrive
        lda #SIDE_FIRST + BASELINE
        sta rowY
        lda #0
        sta sideCount
        ldx #0
@drive: stx drv
        lda driveType,x
        beq @next
        txa                     ; (its letter kept for a click)
        clc
        adc #'a'
        ldy sideCount
        sta sideLetters,y
        inc sideCount
        txa
        clc
        adc #'A'
        sta driveLine + 1
        lda #<driveLine
        ldx #>driveLine
        ldy rowY
        jsr SideText
        jsr DiskName            ; its disk's name after the letter
        lda #<dname
        ldx #>dname
        ldy rowY
        jsr SideName
        lda rowY
        clc
        adc #ROW_H
        sta rowY
@next:  ldx drv
        inx
        cpx #4
        bcc @drive
        lda homeDrive           ; the current drive again
        jsr SetDevice
        jsr OpenDisk
        lda #'e'                ; drive E, as the others
        ldy sideCount
        sta sideLetters,y
        inc sideCount
        lda #<ELetter
        ldx #>ELetter
        ldy rowY
        jsr SideText
        lda #<SystemText
        ldx #>SystemText
        ldy rowY
        jmp SideName

; SideText: the text at A/X at x 4, baseline Y. SideName: at x 20,
; clipped at the sidebar's edge (rightMargin).
SideText:
        pha
        lda #4
        bne SideAt
SideName:
        pha
        lda #20
SideAt: sta r11L
        pla
        sta r0L
        stx r0H
        sty r1H
        lda #0
        sta r11H
        lda #SIDE_RIGHT - 2
        sta rightMargin
        lda #0
        sta rightMargin+1
        jsr PutString
        lda #<SCREEN_RIGHT      ; (the whole width again)
        sta rightMargin
        lda #>SCREEN_RIGHT
        sta rightMargin+1
        rts

; DiskName: name = drive drv's disk name (OpenDisk gives r5 = it,
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
        cpy #NAME_LEN - 1
        bcc @ch
@zero:  lda #0
        sta dname,y
@end:   rts

; --- Menus --------------------------------------------------------------

; GeosMenu (the geos menu's DYN_SUB_MENU routine): "GeoUltra info" and
; the desk accessories (FindFTypes; drive E's added by the kernal) into
; geosMenu. r0 = it.
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
        asl a
        sta tmp
        asl a
        asl a
        asl a
        sec
        sbc tmp                 ; (* 14)
        clc
        adc #MENU_BOTTOM
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
        sta r0L
        lda #>geosMenu
        sta r0H
        rts

; Info (geos > GeoUltra info): a dialog naming the desktop.
Info:   jsr GotoFirstMenu
        lda #<infoDlg
        sta r0L
        lda #>infoDlg
        sta r0H
        jmp DoDlgBox

; RunDA (geos > an accessory; A = the item: 1 the first accessory).
RunDA:  sta tmp
        jsr GotoFirstMenu
        ldx tmp
        dex
        lda DaLo,x
        sta r6L
        lda DaHi,x
        sta r6H
        lda #0
        sta r0L
        jmp GetFile             ; (it comes back; GEOS restores the screen)

; Gush (file > gush): GeoUltra's shell in the desktop's place.
Gush:   jsr GotoFirstMenu
        lda #<GushName
        sta r0L
        lda #>GushName
        sta r0H
        lda #FE_RUNSYS
        jmp FileEngine          ; (back only when it cannot start)

; Refresh (disk > refresh): the list read again.
Refresh:
        jsr GotoFirstMenu
        jsr ListRead
        jmp ListDraw

; Nothing (view > list: the only view yet).
Nothing:
        jmp GotoFirstMenu

; The accessories' names in daNames, NAME_LEN apart.
DaLo:   .repeat DA_MAX, i
        .byte <(daNames + i * NAME_LEN)
        .endrepeat
DaHi:   .repeat DA_MAX, i
        .byte >(daNames + i * NAME_LEN)
        .endrepeat

DrivesText:     .byte BOLDON, "DRIVES", PLAINTEXT, 0
ELetter:        .byte " E", 0
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
        .byte SUB_MENU
        .word fileMenu
        .word ViewText
        .byte SUB_MENU
        .word viewMenu
        .word DiskText
        .byte SUB_MENU
        .word diskMenu

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
        .byte MENU_BOTTOM, MENU_BOTTOM + 8 * 14
        .word 30, 129
        .byte VERTICAL | UN_CONSTRAINED | 8
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
        .word GushItem
        .byte MENU_ACTION
        .word Gush

viewMenu:
        .byte MENU_BOTTOM, MENU_BOTTOM + 14
        .word 58, 119
        .byte VERTICAL | UN_CONSTRAINED | 1
        .word ListItem
        .byte MENU_ACTION
        .word Nothing

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
ListItem:       .byte "* list", 0
RefreshItem:    .byte "refresh", 0
InfoLine1:      .byte BOLDON, "GeoUltra Desktop", PLAINTEXT, 0
InfoLine2:      .byte "milestone 1 (in development)", 0
driveLine:      .byte " A", 0
drivePath:      .byte "/a", 0

feVec:          .word 0
rowY:           .byte 0
drv:            .byte 0
homeDrive:      .byte 0
sideCount:      .byte 0
sideLetters:    .res 5
tmp:            .byte 0
daCount:        .byte 0

        .segment "BSS"

dname:          .res NAME_LEN
daNames:        .res DA_MAX * NAME_LEN
