; Dialog boxes: DoDlgBox and RstrFrmDialogue. Written from HG2G2022
; chapter 8 ("Dialog Box") and chapter 19 (dlgBoxRamBuf, the default
; environment); behaviour details (order of the steps, r5-r10 kept for the
; commands, the shadow box offset by one card, the dialog's icon table,
; RETURN for OK, the recovery on exit) follow the reassembled GEOS 2.0
; kernal, mist64/geos kernal/dlgbox/*.s, read as behaviour reference
; only. Own code and data layout; the system icons are GeoUltra's own
; (tools/mkicons.py). Checked with tests/conformance/dialog.py.
;
; Not yet: DBGETFILES (the file system); its parameters are skipped.

        .include "geos.inc"
        .include "hw.inc"

        .export DoDlgBox, RstrFrmDialogue, SaveState, RestoreState, InitGEOEnv
        .import DoIcons, StartMouseMode, UseSystemFont, PutString
        .import SetPattern, Rectangle, FrameRectangle, RecoverRectangle
        .import InterruptMain, MainLoop, GraphicsString, GetString
        .import SysIconOK, SysIconCANCEL, SysIconYES, SysIconNO
        .import SysIconOPEN, SysIconDISK
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
        ldx dbIconTab
        cpx #MAX_DB_ICONS
        bcs @skip
        lda dbCmd               ; remember what the icon is
        sta dbIconCmd,x
        txa                     ; Y = entry offset
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
        lda r3H                 ; x card = left / 8 + offset
        lsr
        lda r3L
        ror
        lsr
        lsr
        ldy dbIndex
        clc
        adc (DBoxDesc),y
        sta dbIconTab+OFF_I_X,x
        iny
        lda r2L
        clc
        adc (DBoxDesc),y
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
@skip:  inc dbIndex
        inc dbIndex
        rts

; A system icon was clicked: its number ends the dialog.
DbSysIconPress:
        ldx r0L
        lda dbIconCmd,x
        sta sysDBData
        jmp RstrFrmDialogue

; RETURN presses OK.
DbKey:  lda keyData
        cmp #CR
        bne @end
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
; DBGETFILES: .byte x, y (file system: not yet).
DbGetFiles:
        lda #2
Skip:   clc
        adc dbIndex
        sta dbIndex
        rts

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

; Save zero page $22-$38, the globals $849B-$84C0, the icon table, the
; kernal state block and the sprites into dlgBoxRamBuf.
SaveState:
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

RestoreState:
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

; The default environment of a dialog box (HG2G2022 chapter 14, "Dialog
; Box and Auto Exec Configuration"): plain text, both buffers, mouse
; and icons on, full-screen window and limits, vectors empty
; except intTopVector and RecoverVector, no processes, menus or icons.
InitGEOEnv:
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
        rts
