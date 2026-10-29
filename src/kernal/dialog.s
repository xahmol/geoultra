; Dialog boxes: DoDlgBox and RstrFrmDialogue. Written from HG2G2022
; chapter 8 ("Dialog Box") and chapter 19 (dlgBoxRamBuf, the default
; environment); behaviour details (order of the steps, r5-r10 kept for the
; commands, the shadow box offset by one card, the dialog's icon table,
; RETURN for OK, the recovery on exit) follow the reassembled GEOS 2.0
; kernal, mist64/geos kernal/dlgbox/*.s, read as behaviour reference
; only. Own code and data layout; the system icons are GeoUltra's own
; (tools/mkicons.py). Checked with tests/conformance/dialog.py.
;
; DBGETFILES: the file list box; its layout (124 x 88 pixels, five rows
; of 14, up to 15 files, the arrows from six files on, a name already in
; the buffer selected) and the selection rules follow GEOS 2.0, mist64/geos
; kernal/dlgbox/dlgbox1h.s and dlgbox1j.s, read as behaviour reference
; only; own code and own arrow icon.

        .include "geos.inc"
        .include "hw.inc"

        .export DoDlgBox, RstrFrmDialogue, SaveState, RestoreState, InitGEOEnv
        .import OvlCall
        .import DoIcons, StartMouseMode, UseSystemFont, PutString
        .import SetPattern, Rectangle, FrameRectangle, RecoverRectangle
        .import InterruptMain, MainLoop, GraphicsString, GetString
        .import SysIconOK, SysIconCANCEL, SysIconYES, SysIconNO
        .import SysIconOPEN, SysIconDISK
        .import FindFTypes, IsMseInRegion, InvertRectangle, HorizontalLine
        .import CopyString, CmpString, folderT, folderS
        .import __KSTATE_RUN__, __KSTATE_SIZE__

; dlgBoxRamBuf: zero page $22-$38, globals $849B-$84C0, the active icon
; table, the kernal state block (KSTATE), the sprites.
SAVE_ZP         = dlgBoxRamBuf
SAVE_GL         = SAVE_ZP + 23
SAVE_IC         = SAVE_GL + 38
SAVE_KS         = SAVE_IC + 2
SAVE_SPR        = SAVE_KS + __KSTATE_SIZE__
SPR_PTRS        = COLOR_MATRIX + $3F8
SPR_SAVED       = 8 + 17 + 1 + 1 + 3 + 2 + 8
        .assert __KSTATE_SIZE__ < 256, lderror, "KSTATE larger than 255 bytes"
        .assert SAVE_SPR + SPR_SAVED <= dlgBoxRamBuf + TOT_SRAM_SAVED, lderror, "dlgBoxRamBuf overflow"

MAX_DB_ICONS    = 8

        .segment "DATA"

dlgParams:      .res 12         ; r5-r10, kept for every command
dlgCallerPC:    .res 2
dlgCallerSP:    .res 1
dbCmd:          .res 1
dbIndex:        .res 1
dbPort:         .res 1
dbIconCmd:      .res MAX_DB_ICONS
dbIconTab:      .res 4 + MAX_DB_ICONS * OFF_I_NEXT
gfLeft:         .word 0         ; DBGETFILES: the box's left edge
gfTop:          .byte 0         ; and top
gfName:         .word 0         ; the caller's name buffer (r5)
gfFound:        .byte 0         ; files in the list
gfFirst:        .byte 0         ; file in the first row
gfSel:          .byte 0         ; selected file

        .segment "RODATA"

sysIconLo:
        .byte <SysIconOK, <SysIconCANCEL, <SysIconYES, <SysIconNO
        .byte <SysIconOPEN, <SysIconDISK
sysIconHi:
        .byte >SysIconOK, >SysIconCANCEL, >SysIconYES, >SysIconNO
        .byte >SysIconOPEN, >SysIconDISK
cmdLo:  .byte <DbSysIcon, <DbSysIcon, <DbSysIcon, <DbSysIcon, <DbSysIcon, <DbSysIcon
        .byte <DbNone, <DbNone, <DbNone, <DbNone
        .byte <DbTxtStr, <DbVarStr, <DbGetString, <DbSysOpv, <DbGrphStr
        .byte <DbGetFiles, <DbOpVec, <DbUsrIcon, <DbUsrRout
cmdHi:  .byte >DbSysIcon, >DbSysIcon, >DbSysIcon, >DbSysIcon, >DbSysIcon, >DbSysIcon
        .byte >DbNone, >DbNone, >DbNone, >DbNone
        .byte >DbTxtStr, >DbVarStr, >DbGetString, >DbSysOpv, >DbGrphStr
        .byte >DbGetFiles, >DbOpVec, >DbUsrIcon, >DbUsrRout
LAST_CMD        = DB_USR_ROUT
defaultPos:
        .byte DEF_DB_TOP, DEF_DB_BOT
        .word DEF_DB_LEFT, DEF_DB_RIGHT

        .segment "CODE"

; DoDlgBox: r0 = dialog definition; r5-r10 parameters for its commands.
; Returns r0L = the icon or command that ended it (sysDBData).
DoDlgBox:
        lda r0L
        sta DBoxDesc
        lda r0H
        sta DBoxDesc+1
        jsr SaveParams
        jsr SaveState
        jsr InitGEOEnv
        lda #0
        sta sysDBData
        php                     ; only the pointer sprite
        sei
        ldx CPU_PORT
        lda #RAM_IO
        sta CPU_PORT
        lda #$01
        sta vicSprEnable
        stx CPU_PORT
        plp
        jsr DrawDlgBox
        lda #0
        sta r11L
        sta r11H
        clc
        jsr StartMouseMode
        jsr UseSystemFont
        ldy #0                  ; commands start after the position
        lda (DBoxDesc),y
        bmi @default
        ldy #7
        bne @next
@default:
        ldy #1
@next:  sty dbIndex
        lda (DBoxDesc),y
        beq @end
        cmp #LAST_CMD + 1
        bcs @end
        sta dbCmd
        inc dbIndex
        jsr LoadParams
        ldx dbCmd
        lda cmdLo-1,x
        sta @call+1
        lda cmdHi-1,x
        sta @call+2
@call:  jsr $FFFF
        ldy dbIndex
        jmp @next
@end:   lda dbIconTab           ; the dialog's icons
        beq @run
        lda #<dbIconTab
        sta r0L
        lda #>dbIconTab
        sta r0H
        jsr DoIcons
@run:   pla                     ; RstrFrmDialogue returns to our caller
        sta dlgCallerPC
        pla
        sta dlgCallerPC+1
        tsx
        stx dlgCallerSP
        jmp MainLoop

; RstrFrmDialogue: restore the system state, recover the dialog's area
; (shadow first) and return from DoDlgBox with r0L = sysDBData.
RstrFrmDialogue:
        jsr RestoreState
        ldy #0
        lda (DBoxDesc),y
        and #$1F
        beq @box
        lda #8
        jsr DlgRect
        jsr Recover
@box:   lda #0
        jsr DlgRect
        jsr Recover
        lda sysDBData
        sta r0L
        ldx dlgCallerSP
        txs
        lda dlgCallerPC+1
        pha
        lda dlgCallerPC
        pha
        rts

Recover:
        lda RecoverVector
        ora RecoverVector+1
        bne @vector
        lda #0
        jsr SetPattern
        jmp Rectangle
@vector:
        jmp (RecoverVector)

; r2-r4 = the dialog's rectangle, every coordinate + A.
DlgRect:
        sta dbPort
        ldy #0
        lda (DBoxDesc),y
        bmi @default
        ldx #0
        iny
@copy:  lda (DBoxDesc),y
        sta r2,x
        iny
        inx
        cpx #6
        bne @copy
        beq @add
@default:
        ldx #5
@def:   lda defaultPos,x
        sta r2,x
        dex
        bpl @def
@add:   clc
        lda r2L
        adc dbPort
        sta r2L
        clc
        lda r2H
        adc dbPort
        sta r2H
        clc
        lda r3L
        adc dbPort
        sta r3L
        bcc @r4
        inc r3H
@r4:    clc
        lda r4L
        adc dbPort
        sta r4L
        bcc @end
        inc r4H
@end:   rts

; The box on the foreground screen: shadow (one card right and down) in
; the pattern of the position byte, white area, frame.
DrawDlgBox:
        lda #ST_WR_FORE
        sta dispBufferOn
        ldy #0
        lda (DBoxDesc),y
        and #$1F
        beq @box
        jsr SetPattern
        lda #8
        jsr DlgRect
        jsr Rectangle
@box:   lda #0
        jsr SetPattern
        lda #0
        jsr DlgRect
        lda r4L
        sta rightMargin
        lda r4H
        sta rightMargin+1
        jsr Rectangle
        lda #0
        jsr DlgRect
        lda #$FF
        jsr FrameRectangle
        lda #0
        sta dbIconTab
        sta dbIconTab+1
        sta dbIconTab+2
        sta dbIconTab+3
        rts

; --- Commands: entered with Y = dbIndex at the command's first data byte

DbNone: rts

; OK..DISK: .byte x card, y offset. OK also makes RETURN press it.
DbSysIcon:
        lda dbCmd
        cmp #OK
        bne @icon
        lda keyVector
        ora keyVector+1
        bne @icon
        lda #<DbKey
        sta keyVector
        lda #>DbKey
        sta keyVector+1
@icon:  ldx dbCmd
        lda sysIconLo-1,x
        sta r5L
        lda sysIconHi-1,x
        sta r5H
        lda #SYSDBI_WIDTH
        sta r6L
        lda #SYSDBI_HEIGHT
        sta r6H
        lda #<DbSysIconPress
        sta r7L
        lda #>DbSysIconPress
        sta r7H
        jmp AddIcon

; DBUSRICON: .byte x card, y offset, .word table (.word picture, .word 0,
; .byte width, height, .word routine).
DbUsrIcon:
        ldy dbIndex
        iny
        iny
        lda (DBoxDesc),y
        sta r8L
        iny
        lda (DBoxDesc),y
        sta r8H
        ldy #0
        lda (r8),y
        sta r5L
        iny
        lda (r8),y
        sta r5H
        ldy #4
        lda (r8),y
        sta r6L
        iny
        lda (r8),y
        sta r6H
        iny
        lda (r8),y
        sta r7L
        iny
        lda (r8),y
        sta r7H
        jsr AddIcon
        inc dbIndex             ; past the table pointer
        inc dbIndex
        rts

; Add an icon at the command's x card and y offset: r5 = picture,
; r6L/r6H = width/height, r7 = routine. Advances dbIndex past x and y.
AddIcon:
        lda #0
        jsr DlgRect
        lda r3H                 ; x card = left / 8 + offset
        lsr
        lda r3L
        ror
        lsr
        lsr
        ldy dbIndex
        clc
        adc (DBoxDesc),y
        sta r8L
        iny
        lda r2L
        clc
        adc (DBoxDesc),y
        sta r8H
        inc dbIndex
        inc dbIndex

; IconAt: as AddIcon at x card r8L, y r8H.
IconAt: ldx dbIconTab
        cpx #MAX_DB_ICONS
        bcs @skip
        lda dbCmd               ; remember what the icon is
        sta dbIconCmd,x
        txa                     ; X = entry offset
        asl
        asl
        asl
        clc
        adc #4
        tax
        lda r5L
        sta dbIconTab+OFF_I_PIC,x
        lda r5H
        sta dbIconTab+OFF_I_PIC+1,x
        lda r8L
        sta dbIconTab+OFF_I_X,x
        lda r8H
        sta dbIconTab+OFF_I_Y,x
        lda r6L
        sta dbIconTab+OFF_I_WIDTH,x
        lda r6H
        sta dbIconTab+OFF_I_HEIGHT,x
        lda r7L
        sta dbIconTab+OFF_I_EVENT,x
        lda r7H
        sta dbIconTab+OFF_I_EVENT+1,x
        inc dbIconTab
@skip:  rts

; A system icon was clicked: its number ends the dialog.
DbSysIconPress:
        ldx r0L
        lda dbIconCmd,x
        cmp #OPEN               ; OPEN on a folder row: into the folder,
        bne @close              ; the dialog stays
        jsr GfOpen
        bcc @close
        rts
@close: sta sysDBData
        jmp RstrFrmDialogue

; RETURN presses OK.
DbKey:  lda keyData
        cmp #KEY_DELETE         ; file list: DEL to the folder above
        bne @cr
        jmp GfUpKey
@cr:    cmp #CR
        bne @end
        jsr GfOpen              ; file list: RETURN on a folder row enters it
        bcs @end
        lda #OK
        sta sysDBData
        jmp RstrFrmDialogue
@end:   rts

; DBTXTSTR: .byte x, y, .word text.
DbTxtStr:
        jsr TextPos
        lda (DBoxDesc),y
        sta r0L
        iny
        lda (DBoxDesc),y
        sta r0H
        iny
        sty dbIndex
        jmp PutString

; DBVARSTR: .byte x, y, zero page register holding the text pointer.
DbVarStr:
        jsr TextPos
        lda (DBoxDesc),y
        tax
        iny
        sty dbIndex
        lda $00,x
        sta r0L
        lda $01,x
        sta r0H
        jmp PutString

; r11 = left + x, r1H = top + y of the command; Y after them.
TextPos:
        lda #0
        jsr DlgRect
        ldy dbIndex
        lda (DBoxDesc),y
        clc
        adc r3L
        sta r11L
        lda r3H
        adc #0
        sta r11H
        iny
        lda (DBoxDesc),y
        clc
        adc r2L
        sta r1H
        iny
        rts

; DBGETSTRING: .byte x, y (top of the characters), register holding the
; buffer pointer, maxChars. RETURN ends the dialog with DBGETSTRING.
DbGetString:
        jsr TextPos
        lda (DBoxDesc),y
        tax
        lda $00,x
        sta r0L
        lda $01,x
        sta r0H
        iny
        lda (DBoxDesc),y
        sta r2L
        iny
        sty dbIndex
        lda #<DbStringDone
        sta keyVector
        lda #>DbStringDone
        sta keyVector+1
        lda #0
        sta r1L
        jmp GetString
DbStringDone:
        lda #DBGETSTRING
        sta sysDBData
        jmp RstrFrmDialogue

; DBGRPHSTR: .word graphics string, drawn now.
DbGrphStr:
        ldy dbIndex
        lda (DBoxDesc),y
        sta r0L
        iny
        lda (DBoxDesc),y
        sta r0H
        inc dbIndex
        inc dbIndex
        jmp GraphicsString
; DBGETFILES: .byte x, y; r7L = GEOS file type, r10 = permanent name
; prefix (0: any), r5 = name buffer (a name in it starts selected). The
; selected name is always in the buffer.
GF_ROW          = 14
GF_ROWS         = 5
GF_MAX          = 15
        .segment "IOCODE"               ; (needs $01 = $30 like GEOS 2.0's,
                                        ; which calls FindFTypes from there)
DbGetFiles:
        lda #0
        jsr DlgRect
        ldy dbIndex
        clc
        lda (DBoxDesc),y
        adc r3L
        sta gfLeft
        lda #0
        adc r3H
        sta gfLeft+1
        iny
        clc
        lda (DBoxDesc),y
        adc r2L
        sta gfTop
        inc dbIndex
        inc dbIndex
        lda r5L
        sta gfName
        lda r5H
        sta gfName+1
        lda r7L                 ; FindFTypes needs r7, r10: keep them
        pha
        lda r10L
        pha
        lda r10H
        pha
        jsr GfBox
        lda #$FF
        jsr FrameRectangle
        sec                     ; the line above the arrows
        lda r2H
        sbc #16
        sta r11L
        lda #$FF
        jsr HorizontalLine
        pla
        sta r10H
        sta gfCls+1
        pla
        sta r10L
        sta gfCls
        pla
        sta r7L
        sta gfType
        jsr GfFind
        lda gfFound
        bne :+
        rts
:       cmp #GF_ROWS + 1
        bcs @arrows
        lda gfDirs              ; with folders the list can grow: arrows
        beq @press
@arrows:
        jsr GfBox               ; arrows: x card left / 8 + 7, y bottom - 14
        lda r3H
        lsr
        lda r3L
        ror
        lsr
        lsr
        clc
        adc #7
        sta r8L
        sec
        lda r2H
        sbc #14
        sta r8H
        lda #<arrowPic
        sta r5L
        lda #>arrowPic
        sta r5H
        lda #3
        sta r6L
        lda #12
        sta r6H
        lda #<GfArrow
        sta r7L
        lda #>GfArrow
        sta r7H
        jsr IconAt
@press: lda #<GfPress
        sta otherPressVec
        lda #>GfPress
        sta otherPressVec+1
        lda gfDirs              ; folders listed and no key routine of the
        beq @keys               ; dialog's own: RETURN and DEL for them
        lda keyVector
        ora keyVector+1
        bne @keys
        lda #<GfKeys
        sta keyVector
        lda #>GfKeys
        sta keyVector+1
@keys:
        ldx gfFound             ; select the name in the buffer, else the first
@find:  dex
        beq @sel
        txa
        jsr GfEntry
        ldx #r0
        ldy #r1
        jsr CmpString
        php
        lda r0L                 ; X back: the entry number
        sec
        sbc #<fileTrScTab
        ldx #$FF
@div:   inx
        sec
        sbc #17
        bcs @div
        plp
        bne @find
@sel:   stx gfSel
        txa
        sec
        sbc #GF_ROWS - 1
        bcs @first
        lda #0
@first: sta gfFirst
        jsr GfCopy
        jmp GfDraw
@end:   rts

; GfEntry: A = file number -> r0 = its name, r1 = the caller's buffer.
GfEntry:
        tax
        lda #<fileTrScTab
        sta r0L
        lda #>fileTrScTab
        sta r0H
@add:   dex
        bmi @buf
        clc
        lda r0L
        adc #17
        sta r0L
        bcc @add
        inc r0H
        bne @add
@buf:   lda gfName
        sta r1L
        lda gfName+1
        sta r1H
        rts

; GfCopy: the selected name to the caller's buffer (a folder row: no name,
; so that an application never gets one back).
GfCopy: lda gfSel
        jsr GfEntry
        lda gfSel
        cmp gfDirs
        bcs @file
        lda #0
        tay
        sta (r1),y
        rts
@file:  ldx #r0
        ldy #r1
        jmp CopyString

; GfBox: r2L/r2H = top/bottom, r3/r4 = left/right of the box.
GfBox:  lda gfLeft
        sta r3L
        clc
        adc #124
        sta r4L
        lda gfLeft+1
        sta r3H
        adc #0
        sta r4H
        lda gfTop
        sta r2L
        clc
        adc #88
        sta r2H
        rts

; GfRow: A = row -> r2-r4 = the row inside the frame.
GfRow:  pha
        jsr GfBox
        pla
        tax
        lda r2L
@row:   dex
        bmi @set
        clc
        adc #GF_ROW
        bne @row
@set:   sta r2L
        clc
        adc #GF_ROW
        sta r2H
        inc r2L
        dec r2H
        inc r3L
        bne @r4
        inc r3H
@r4:    lda r4L
        bne @dec
        dec r4H
@dec:   dec r4L
        rts

; GfDraw: the five rows (bold names), the selection inverted.
GfDraw: lda rightMargin
        pha
        lda rightMargin+1
        pha
        lda #0
        jsr GfRow
        lda r4L
        sta rightMargin
        lda r4H
        sta rightMargin+1
        lda #0
        jsr SetPattern
        lda #SET_BOLD
        sta currentMode
        lda #0
        sta dbPort              ; row counter
@row:   lda dbPort
        jsr GfRow
        jsr Rectangle
        lda dbPort              ; r0 = the name (GfEntry also sets r1)
        clc
        adc gfFirst
        jsr GfEntry
        lda r3L
        sta r11L
        lda r3H
        sta r11H
        lda r2L                 ; baseline 9 below the row's top
        clc
        adc #9
        sta r1H
        jsr PutString
        inc dbPort
        lda dbPort
        cmp #GF_ROWS
        bne @row
        jsr GfInvert
        lda #0
        sta currentMode
        pla
        sta rightMargin+1
        pla
        sta rightMargin
        rts

; GfInvert: invert the selected row.
GfInvert:
        lda gfSel
        sec
        sbc gfFirst
        jsr GfRow
        jmp InvertRectangle

; --- Folders in the file list (native drives; docs/DESIGN.md "Directories")

GetDirHead      = $C247         ; jump table
OFF_FNAME       = 3             ; the name in a directory entry

; GfFind: FindFTypes (r7L, r10 as set) into fileTrScTab, up to 15 names
; of 17 bytes; gfFound = their number; then the folders (GfFolders).
GfFind: lda #<fileTrScTab
        sta r6L
        lda #>fileTrScTab
        sta r6H
        lda #GF_MAX
        sta r7H
        jsr FindFTypes
        lda #GF_MAX
        sec
        sbc r7H
        sta gfFound
        ; (falls into GfFolders)

; GfFolders (after FindFTypes, gfFound files in fileTrScTab): on a native
; drive ".." (not at the root) and the folders as "/name" are put before
; the files, within GF_MAX places. gfDirs = those rows, gfUp = 1 with "..".
GfFolders:
        lda #$FF
        sta gfTarget
        lda #0
        sta gfDirs
        sta gfUp
        ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_NATIVE
        bne @end
        lda folderT-8,x
        cmp #1
        bne @up
        lda folderS-8,x
        cmp #1
        beq @count
@up:    inc gfUp
@count: lda gfUp
        sta gfDirs
        lda #$FF                ; count only
        sta gfWrite
        jsr GfScan
        lda gfDirs
        beq @end
        lda #GF_MAX             ; files kept: GF_MAX - gfDirs at most
        sec
        sbc gfDirs
        cmp gfFound
        bcs @move
        sta gfFound
@move:  lda gfDirs              ; r0 = the files' new place
        jsr GfEntry
        ldx gfFound             ; bytes to move: gfFound * 17
        lda #0
@bytes: dex
        bmi @copy
        clc
        adc #17
        bne @bytes
@copy:  tay
@back:  dey
        cpy #$FF
        beq @names
        lda fileTrScTab,y
        sta (r0),y
        jmp @back
@names: lda gfFound
        clc
        adc gfDirs
        sta gfFound
        lda gfUp
        beq @dirs
        lda #'.'
        sta fileTrScTab
        sta fileTrScTab+1
        lda #0
        sta fileTrScTab+2
@dirs:  lda gfUp                ; write "/name" from row gfUp on
        sta gfWrite
        jsr GfScan
@end:   rts

; GfScan: the directory's folders. gfWrite = $FF: count them into gfDirs
; (at most GF_MAX); else write them as "/name" from row gfWrite on, as
; many as gfDirs allows. With gfTarget < $FF: stop at that folder (0 the
; first) with r5 at its entry, C clear; else C set.
GfScan: jsr Get1stDirEntry
        txa
        bne @none
@entry: ldy #0
        lda (r5),y
        beq @next
        and #$07
        cmp #6                  ; DIR
        bne @next
        lda gfTarget
        cmp #$FF
        beq @list
        dec gfTarget
        bpl @next
        clc                     ; (the folder sought: r5 at it)
        rts
@list:  lda gfWrite
        cmp #$FF
        bne @write
        lda gfDirs
        cmp #GF_MAX
        bcs @next
        inc gfDirs
        bne @next
@write: cmp gfDirs
        bcs @next
        jsr GfEntry             ; r0 = the row
        inc gfWrite
        ldy #0
        lda #'/'
        sta (r0),y
@char:  iny                     ; the name: entry bytes 3-17, up to $A0
        cpy #16
        beq @zero
        tya
        clc
        adc #OFF_FNAME - 1
        sty gfTmp
        tay
        lda (r5),y
        ldy gfTmp
        cmp #$A0
        beq @zero
        sta (r0),y
        bne @char
@zero:  lda #0
        sta (r0),y
@next:  jsr GetNxtDirEntry
        txa
        bne @none
        tya
        beq @entry
@none:  sec
        rts

; GfUpKey: DEL in a file list: to the folder above.
GfUpKey:
        lda gfUp
        beq GfRts
        lda #0
        sta gfSel
        beq GfOpen              ; (always)
GfRts:  rts

; GfKeys (keyVector of a file list without a key routine of its own):
; RETURN on a folder row enters it (into GfOpen), DEL goes up; other keys
; do nothing.
GfKeys: lda keyData
        cmp #KEY_DELETE
        beq GfUpKey
        cmp #CR
        bne GfRts

; GfOpen: with a file list on the screen and a folder row selected, into
; that folder (".." up) and the list built anew. C set when done, else C
; clear (A kept).
GfOpen: pha
        lda otherPressVec       ; a file list: its press routine is set
        cmp #<GfPress
        bne @not
        lda otherPressVec+1
        cmp #>GfPress
        bne @not
        lda gfSel
        cmp gfDirs
        bcc @row
@not:   pla
        clc
        rts
@row:
        ldx gfUp                ; ".."
        beq @into
        cmp #0
        bne @into
        lda curDirHead+$22      ; the parent header
        ldy curDirHead+$23
        jmp @set
@into:  sec
        sbc gfUp
        sta gfTarget
        jsr GfScan
        bcs @no
        ldy #1                  ; the folder's header
        lda (r5),y
        pha
        iny
        lda (r5),y
        tay
        pla
@set:   ldx curDrive
        sta folderT-8,x
        tya
        sta folderS-8,x
        jsr GetDirHead
        lda #$FF
        sta gfTarget
        lda gfType              ; the list anew
        sta r7L
        lda gfCls
        sta r10L
        lda gfCls+1
        sta r10H
        jsr GfFind
        lda #0
        sta gfSel
        sta gfFirst
        jsr GfCopy
        jsr GfDraw
        pla
        sec
        rts
@no:    pla
        clc
        rts

        .segment "IODATA"

gfDirs:         .byte 0         ; rows of ".." and folders at the top
gfUp:           .byte 0         ; 1: ".." is row 0
gfWrite:        .byte 0
gfTarget:       .byte $FF       ; GfScan: folder sought, $FF: none
gfTmp:          .byte 0
gfType:         .byte 0         ; the dialog's FindFTypes arguments
gfCls:          .word 0

        .segment "IOCODE"

        .segment "KEXT"                 ; space: see ARCHITECTURE.md

; GfPress (otherPressVec): a press on a row selects its file.
GfPress:
        lda mouseData
        bmi @end
        jsr GfBox
        clc
        lda r2L
        adc #GF_ROWS * GF_ROW - 1
        sta r2H
        jsr IsMseInRegion
        beq @end
        jsr GfInvert
        sec
        lda mouseYPos
        sbc gfTop
        ldx #$FF
@div:   inx
        sec
        sbc #GF_ROW
        bcs @div
        txa
        clc
        adc gfFirst
        cmp gfFound
        bcc @sel
        ldx gfFound
        dex
        txa
@sel:   sta gfSel
        jsr GfInvert
        jmp GfCopy
@end:   rts

; GfArrow (icon): the left half scrolls up, the right half down; the
; selection stays in view.
GfArrow:
        jsr GfInvert
        jsr GfBox
        lda r3H
        lsr
        lda r3L
        ror
        lsr
        lsr
        clc
        adc #7                  ; arrow x card
        sta r0L
        lda #0
        asl r0L
        rol
        asl r0L
        rol
        asl r0L
        rol
        sta r0H
        clc
        lda r0L
        adc #12                 ; the middle of the icon
        sta r0L
        bcc @cmp
        inc r0H
@cmp:   ldx gfFirst
        lda mouseXPos+1
        cmp r0H
        bne @half
        lda mouseXPos
        cmp r0L
@half:  bcs @down
        dex
        bmi @keep
        bpl @set
@down:  inx
        lda gfFound
        sec
        sbc gfFirst
        cmp #GF_ROWS + 1
        bcc @keep
@set:   stx gfFirst
@keep:  lda gfFirst
        cmp gfSel
        bcc @low
        sta gfSel
@low:   clc
        adc #GF_ROWS - 1
        cmp gfSel
        bcs @copy
        sta gfSel
@copy:  jsr GfCopy
        jmp GfDraw

        .segment "CODE"

; The arrows icon (own design): up and down, 24 x 12, compacted.
arrowPic:
        .byte $A4, $FF, $FF, $FF, $80, $18, $01, $86, $18, $61, $8F, $18, $61
        .byte $9F, $98, $61, $BF, $D8, $61, $86, $1B, $FD, $86, $19, $F9, $86
        .byte $18, $F1, $86, $18, $61, $80, $18, $01, $FF, $FF, $FF

        .segment "CODE"

; DBSYSOPV: a press outside the icons ends the dialog with DBSYSOPV.
DbSysOpv:
        lda #<DbOtherPress
        sta otherPressVec
        lda #>DbOtherPress
        sta otherPressVec+1
        rts
DbOtherPress:
        lda mouseData
        bmi @end
        lda #DBSYSOPV
        sta sysDBData
        jmp RstrFrmDialogue
@end:   rts

; DBOPVEC: .word routine for presses outside the icons.
DbOpVec:
        ldy dbIndex
        lda (DBoxDesc),y
        sta otherPressVec
        iny
        lda (DBoxDesc),y
        sta otherPressVec+1
        inc dbIndex
        inc dbIndex
        rts

; DB_USR_ROUT: .word routine, called now (before the icons are drawn).
DbUsrRout:
        ldy dbIndex
        lda (DBoxDesc),y
        sta @call+1
        iny
        lda (DBoxDesc),y
        sta @call+2
        inc dbIndex
        inc dbIndex
@call:  jmp $FFFF

; --- State --------------------------------------------------------------

SaveParams:
        ldx #11
@copy:  lda r5,x
        sta dlgParams,x
        dex
        bpl @copy
        rts
LoadParams:
        ldx #11
@copy:  lda dlgParams,x
        sta r5,x
        dex
        bpl @copy
        rts

; SaveState / RestoreState: the kernal state around a dialog box or a desk
; accessory (overlay module 11; they save and restore what DoDlgBox and
; LdDeskAcc must keep).
SaveState:
        jsr OvlCall
        .byte 11, 0
RestoreState:
        jsr OvlCall
        .byte 11, 3

; The default environment of a dialog box (HG2G2022 chapter 14, "Dialog
; Box and Auto Exec Configuration"): plain text, both buffers, mouse
; and icons on, full-screen window and limits, vectors empty
; except intTopVector and RecoverVector, no processes, menus or icons.
InitGEOEnv:
        php                     ; no IRQ while intTopVector is cleared
        sei                     ; (geoWrite 2.0 calls this with IRQs on)
        lda #SET_PLAINTEXT
        sta currentMode
        lda #ST_WR_FORE | ST_WR_BACK
        sta dispBufferOn
        lda #MOUSEON_BIT | ICONSON_BIT  ; menus off: measured on GEOS 2.0
        sta mouseOn                     ; (HG2G2022's table says %11100000)
        lda #0
        sta windowTop
        sta leftMargin
        sta leftMargin+1
        sta pressFlag
        sta IconDescVec
        sta IconDescVec+1
        lda #SC_PIX_HEIGHT - 1
        sta windowBottom
        lda #<(SC_PIX_WIDTH - 1)
        sta rightMargin
        lda #>(SC_PIX_WIDTH - 1)
        sta rightMargin+1
        ldx #37                 ; globals: all zero, then the defaults
        lda #0
@gl:    sta appMain,x
        dex
        bpl @gl
        ldx #0                  ; kernal state: no menus, processes, icons
@ks:    cpx #<__KSTATE_SIZE__
        beq @defs
        sta __KSTATE_RUN__,x
        inx
        bne @ks
@defs:  lda #<InterruptMain
        sta intTopVector
        lda #>InterruptMain
        sta intTopVector+1
        lda #<RecoverRectangle
        sta RecoverVector
        lda #>RecoverRectangle
        sta RecoverVector+1
        lda #SELECTION_DELAY
        sta selectionFlash
        lda #ST_FLASH
        sta iconSelFlag
        lda #SC_PIX_HEIGHT - 1
        sta mouseBottom
        lda #<(SC_PIX_WIDTH - 1)
        sta mouseRight
        lda #>(SC_PIX_WIDTH - 1)
        sta mouseRight+1
        plp
        rts

        .segment "OVL11"                ; overlay module 11: dialog state

        jmp OvSaveState         ; entry 0
        jmp OvRestoreState      ; entry 3

; Save zero page $22-$38, the globals $849B-$84C0, the icon table, the
; kernal state block and the sprites into dlgBoxRamBuf.
OvSaveState:
        ldx #22
@zp:    lda curPattern,x
        sta SAVE_ZP,x
        dex
        bpl @zp
        ldx #37
@gl:    lda appMain,x
        sta SAVE_GL,x
        dex
        bpl @gl
        lda IconDescVec
        sta SAVE_IC
        lda IconDescVec+1
        sta SAVE_IC+1
        ldx #0
@ks:    cpx #<__KSTATE_SIZE__
        beq @spr
        lda __KSTATE_RUN__,x
        sta SAVE_KS,x
        inx
        bne @ks
@spr:   ldx #7
@ptr:   lda SPR_PTRS,x
        sta SAVE_SPR,x
        dex
        bpl @ptr
        php
        sei
        lda CPU_PORT
        sta dbPort
        lda #RAM_IO
        sta CPU_PORT
        ldx #16
@pos:   lda vicSpr0X,x
        sta SAVE_SPR+8,x
        dex
        bpl @pos
        lda vicSprEnable
        sta SAVE_SPR+25
        lda $D017               ; double height
        sta SAVE_SPR+26
        ldx #2
@prio:  lda $D01B,x             ; priority, multicolour, double width
        sta SAVE_SPR+27,x
        dex
        bpl @prio
        ldx #9
@col:   lda $D025,x             ; multicolours and sprite colours
        sta SAVE_SPR+30,x
        dex
        bpl @col
        lda dbPort
        sta CPU_PORT
        plp
        rts

OvRestoreState:
        php
        sei
        ldx #22
@zp:    lda SAVE_ZP,x
        sta curPattern,x
        dex
        bpl @zp
        ldx #37
@gl:    lda SAVE_GL,x
        sta appMain,x
        dex
        bpl @gl
        lda SAVE_IC
        sta IconDescVec
        lda SAVE_IC+1
        sta IconDescVec+1
        ldx #0
@ks:    cpx #<__KSTATE_SIZE__
        beq @spr
        lda SAVE_KS,x
        sta __KSTATE_RUN__,x
        inx
        bne @ks
@spr:   ldx #7
@ptr:   lda SAVE_SPR,x
        sta SPR_PTRS,x
        dex
        bpl @ptr
        lda CPU_PORT
        sta dbPort
        lda #RAM_IO
        sta CPU_PORT
        ldx #16
@pos:   lda SAVE_SPR+8,x
        sta vicSpr0X,x
        dex
        bpl @pos
        lda SAVE_SPR+25
        sta vicSprEnable
        lda SAVE_SPR+26
        sta $D017
        ldx #2
@prio:  lda SAVE_SPR+27,x
        sta $D01B,x
        dex
        bpl @prio
        ldx #9
@col:   lda SAVE_SPR+30,x
        sta $D025,x
        dex
        bpl @col
        lda dbPort
        sta CPU_PORT
        plp
        rts

