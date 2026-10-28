; Menus and mouse mode: DoMenu, ReDoMenu, DoPreviousMenu, GotoFirstMenu,
; RecoverMenu, RecoverAllMenus, StartMouseMode, ClearMouseMode, MouseUp,
; MouseOff, IsMseInRegion; the interrupt-level pointer check (limits,
; faults) and the MainLoop side (presses, faults, the selection flash).
;
; Written from HG2G2022 chapter 3 ("Icons, Menus, and Other Mouse
; Presses"). Behaviour details (item limits and inversion rectangles,
; mouse off during a selection, the flash sequence, redraw of the parent
; on DoPreviousMenu, fault handling) follow the reassembled GEOS 2.0
; kernal, mist64/geos kernal/menu/menu1.s, menu3.s and mouse/mouse2.s,
; read as behaviour reference only; checked with the conformance harness
; (tests/conformance/menu.py). Own code and data layout.

        .include "geos.inc"
        .include "hw.inc"

        .export DoMenu, ReDoMenu, DoPreviousMenu, GotoFirstMenu
        .export RecoverMenu, RecoverAllMenus
        .export StartMouseMode, ClearMouseMode, MouseUp, MouseOff
        .export IsMseInRegion, MenuTick, CheckMousePos
        .export DefFaultVector, DefMouseVector
        .import Rectangle, FrameRectangle, InvertRectangle
        .import HorizontalLine, VerticalLine, SetPattern
        .import UseSystemFont, PutString, frameCount

OFF_M_ATTRIBUTE = 6
NO_ITEM         = 0
SET_OFFTOP      = $80
SET_OFFBOTTOM   = $40
SET_OFFLEFT     = $20
SET_OFFRIGHT    = $10
SET_OFFMENU     = $08

        .segment "DATA"

mPtrLo:         .res MAX_M_NESTING      ; menu structure per level
mPtrHi:         .res MAX_M_NESTING
mSel:           .res MAX_M_NESTING      ; selected (or pointer) item per level
; The current level, copied from its structure
menuTop:        .byte 0
menuBottom:     .byte 0
menuLeft:       .word 0
menuRight:      .word 0
menuAttr:       .byte 0
count:          .byte 0
limitLo:        .res MAX_M_ITEMS + 1    ; item limits of the current level
limitHi:        .res MAX_M_ITEMS + 1

item:           .byte 0
saveText:       .res 9                  ; $26-$2E font variables, currentMode
saveMargins:    .res 6                  ; windowTop..rightMargin
saveDisp:       .byte 0
saveFault:      .res 2
savePattern:    .res 2
sprMask:        .byte 0
sprPort:        .byte 0
flashState:     .byte 0                 ; 0 idle, 1 and 2 waiting
flashTime:      .byte 0

        .segment "CODE"

; --- Mouse mode -------------------------------------------------------

; MouseUp: pointer and tracking on. Destroys A.
MouseUp:
        lda mouseOn
        ora #MOUSEON_BIT
        sta mouseOn
        lda #$01
        jmp SpriteOn

; MouseOff: pointer and tracking off. Destroys A.
MouseOff:
        lda mouseOn
        and #<~MOUSEON_BIT
        sta mouseOn
        lda #$01
        jmp SpriteOff

; ClearMouseMode: all mouse tracking off. Destroys A, X, Y, r3L.
ClearMouseMode:
        lda #0
        sta mouseOn
        lda #$01
        jmp SpriteOff

; Sprite enable bits in A on/off, I/O banked in around the write;
; X and Y are preserved.
SpriteOn:
        php
        sei
        sta sprMask
        lda CPU_PORT
        sta sprPort
        lda #RAM_IO
        sta CPU_PORT
        lda sprMask
        ora vicSprEnable
        jmp SpriteSet
SpriteOff:
        php
        sei
        eor #$FF
        sta sprMask
        lda CPU_PORT
        sta sprPort
        lda #RAM_IO
        sta CPU_PORT
        lda sprMask
        and vicSprEnable
SpriteSet:
        sta vicSprEnable
        lda sprPort
        sta CPU_PORT
        plp
        rts

; StartMouseMode: carry set and r11 non-zero: pointer to r11/Y. Installs
; the system mouse and fault services, clears faults, MouseUp.
; Destroys A, X, Y, r0-r15.
StartMouseMode:
        bcc @vectors
        lda r11L
        ora r11H
        beq @vectors
        lda r11L
        sta mouseXPos
        lda r11H
        sta mouseXPos+1
        sty mouseYPos
        jsr SlowMouse
@vectors:
        lda #<DefMouseVector
        sta mouseVector
        lda #>DefMouseVector
        sta mouseVector+1
        lda #<DefFaultVector
        sta mouseFaultVec
        lda #>DefFaultVector
        sta mouseFaultVec+1
        lda #0
        sta faultData
        jmp MouseUp

; IsMseInRegion: r2L/r2H = y1/y2, r3/r4 = x1/x2. Returns A = TRUE or
; FALSE (flags set accordingly).
IsMseInRegion:
        lda mouseYPos
        cmp r2L
        bcc @no
        cmp r2H
        beq @y
        bcs @no
@y:     lda mouseXPos+1
        cmp r3H
        bcc @no
        bne @right
        lda mouseXPos
        cmp r3L
        bcc @no
@right: lda mouseXPos+1
        cmp r4H
        bcc @yes
        bne @no
        lda mouseXPos
        cmp r4L
        beq @yes
        bcs @no
@yes:   lda #TRUE
        rts
@no:    lda #FALSE
        rts

; Interrupt level, after the input driver: keep the pointer inside the
; mouse limits and note faults (off a limit, off the current menu).
CheckMousePos:
        lda mouseXPos+1         ; left (negative counts as left)
        bmi @left
        cmp mouseLeft+1
        bcc @left
        bne @right
        lda mouseXPos
        cmp mouseLeft
        bcs @right
@left:  lda #SET_OFFLEFT
        jsr Fault
        lda mouseLeft
        sta mouseXPos
        lda mouseLeft+1
        sta mouseXPos+1
@right: lda mouseRight+1
        cmp mouseXPos+1
        bcc @rFault
        bne @top
        lda mouseRight
        cmp mouseXPos
        bcs @top
@rFault:
        lda #SET_OFFRIGHT
        jsr Fault
        lda mouseRight
        sta mouseXPos
        lda mouseRight+1
        sta mouseXPos+1
@top:   lda mouseYPos           ; 228 and above: wrapped above line 0
        cmp #228
        bcs @tFault
        cmp mouseTop
        bcs @bottom
@tFault:
        lda #SET_OFFTOP
        jsr Fault
        lda mouseTop
        sta mouseYPos
@bottom:
        lda mouseBottom
        cmp mouseYPos
        bcs @menu
        lda #SET_OFFBOTTOM
        jsr Fault
        lda mouseBottom
        sta mouseYPos
@menu:  bit mouseOn
        bvc PosDone
        lda mouseYPos
        cmp menuTop
        bcc @mFault
        lda menuBottom
        cmp mouseYPos
        bcc @mFault
        lda mouseXPos+1
        cmp menuLeft+1
        bcc @mFault
        bne @mRight
        lda mouseXPos
        cmp menuLeft
        bcc @mFault
@mRight:
        lda menuRight+1
        cmp mouseXPos+1
        bcc @mFault
        bne PosDone
        lda menuRight
        cmp mouseXPos
        bcs PosDone
@mFault:
        lda #SET_OFFMENU
Fault:  ora faultData
        sta faultData
PosDone:
        rts

; Default mouseFaultVec: a fault while a sub-menu is active goes up one
; level, except for a constrained menu when the pointer did not leave it
; through the side of its parent.
DefFaultVector:
        lda mouseOn
        and #MOUSEON_BIT | MENUON_BIT
        cmp #MOUSEON_BIT | MENUON_BIT
        bne @end
        lda menuNumber
        beq @end
        lda faultData
        and #SET_OFFMENU
        bne @prev
        ldx #SET_OFFTOP
        bit menuAttr
        bmi @side
        ldx #SET_OFFLEFT
@side:  txa
        and faultData
        bne @prev
        bit menuAttr
        bvs @end
@prev:  jmp DoPreviousMenu
@end:   rts

; Default mouseVector: a press on the current menu selects; other
; presses (icons come later) and all releases go to otherPressVec.
DefMouseVector:
        lda mouseData
        bmi @other
        lda mouseOn
        and #MOUSEON_BIT
        beq @other
        bit mouseOn
        bvc @other
        jsr CopyMenuRect
        jsr IsMseInRegion
        beq @other
        jmp MenuPress
@other: lda otherPressVec
        ora otherPressVec+1
        beq @none
        jmp (otherPressVec)
@none:  rts

; --- Menus ------------------------------------------------------------

; DoMenu: r0 = menu structure, A = item to put the pointer on.
; Destroys A, X, Y, r0-r13.
DoMenu:
        sta mSel
        ldx #0
        stx menuNumber
        stx flashState
        beq Install

; Open the sub-menu r0 one level deeper, pointer on its item 0.
OpenSubMenu:
        inc menuNumber
        ldx menuNumber
        lda #NO_ITEM
        sta mSel,x
Install:
        lda r0L
        sta mPtrLo,x
        lda r0H
        sta mPtrHi,x
        jsr LoadMenu
        sec
        jmp ShowMenu

; ReDoMenu: redraw the current level, menus stay active.
ReDoMenu:
        jsr MouseOff
        jmp Reshow

; GotoFirstMenu: up to the main menu.
GotoFirstMenu:
        php
        sei
@loop:  lda menuNumber
        beq @end
        jsr DoPreviousMenu
        jmp @loop
@end:   plp
        rts

; DoPreviousMenu: close the current sub-menu; the parent is drawn again
; and becomes active.
DoPreviousMenu:
        jsr MouseOff
        jsr RecoverMenu
        dec menuNumber
Reshow: jsr LoadMenu
        clc

; Draw the current level. Carry set (DoMenu, a new sub-menu) or a
; constrained menu: pointer on the level's selected item. Then menus on
; (icons on as well when the mouse was on) and StartMouseMode.
ShowMenu:
        php
        jsr DrawMenu
        plp
        bit menuAttr
        bvs @point
        bcc @mode
@point: ldx menuNumber
        lda mSel,x
        jsr ItemLimits
        bit menuAttr
        bmi @vert
        clc                     ; horizontal: x = middle of the limits,
        lda r3L                 ; y = middle of the menu
        adc r4L
        sta r11L
        lda r3H
        adc r4H
        ror
        sta r11H
        ror r11L
        lda menuTop
        clc
        adc menuBottom
        ror
        tay
        sec
        bcs @mode
@vert:  lda r2L                 ; vertical: y = middle of the limits,
        clc                     ; x = middle of the menu
        adc r2H
        ror
        tay
        clc
        lda menuLeft
        adc menuRight
        sta r11L
        lda menuLeft+1
        adc menuRight+1
        ror
        sta r11H
        ror r11L
        sec
@mode:  php
        bit mouseOn
        bpl @menus
        lda mouseOn
        ora #ICONSON_BIT
        sta mouseOn
@menus: lda mouseOn
        ora #MENUON_BIT
        sta mouseOn
        plp
        jmp StartMouseMode

; RecoverMenu: recover the area of the current level.
RecoverMenu:
        jsr CopyMenuRect
        lda RecoverVector
        ora RecoverVector+1
        bne @vector
        lda #0
        jsr SetPattern
        jmp Rectangle
@vector:
        jmp (RecoverVector)

; RecoverAllMenus: recover every open level; menuNumber ends at 0.
RecoverAllMenus:
@loop:  jsr LoadMenu
        jsr RecoverMenu
        dec menuNumber
        bpl @loop
        lda #0
        sta menuNumber
        rts

; Copy the header of the current level (menuNumber) into menuTop..
; menuAttr and the mouse limits (full screen unless constrained).
LoadMenu:
        ldx menuNumber
        lda mPtrLo,x
        sta r0L
        lda mPtrHi,x
        sta r0H
        ldy #OFF_M_ATTRIBUTE
        lda (r0),y
        sta menuAttr
        and #$1F
        sta count
        dey
@copy:  lda (r0),y
        sta mouseTop,y
        sta menuTop,y
        dey
        bpl @copy
        bit menuAttr
        bvs @end
        lda #0
        sta mouseTop
        sta mouseLeft
        sta mouseLeft+1
        lda #SC_PIX_HEIGHT - 1
        sta mouseBottom
        lda #<(SC_PIX_WIDTH - 1)
        sta mouseRight
        lda #>(SC_PIX_WIDTH - 1)
        sta mouseRight+1
@end:   rts

; r2-r4 = rectangle of the current level.
CopyMenuRect:
        ldx #5
@copy:  lda menuTop,x
        sta r2,x
        dex
        bpl @copy
        rts

; --- Drawing ----------------------------------------------------------

; Draw the current level on the foreground screen in the system font:
; white area, frame, item texts, separators; computes the item limits.
DrawMenu:
        ldx #8
@saveT: lda baselineOffset,x
        sta saveText,x
        dex
        bpl @saveT
        ldx #5
@saveM: lda windowTop,x
        sta saveMargins,x
        dex
        bpl @saveM
        lda dispBufferOn
        sta saveDisp
        lda StringFaultVec
        sta saveFault
        lda StringFaultVec+1
        sta saveFault+1
        lda curPattern
        sta savePattern
        lda curPattern+1
        sta savePattern+1
        lda #ST_WR_FORE
        sta dispBufferOn
        jsr CopyMenuRect
        lda #0
        jsr SetPattern
        jsr Rectangle
        jsr CopyMenuRect
        lda #$FF
        jsr FrameRectangle
        jsr UseSystemFont
        lda #0
        sta currentMode
        sta StringFaultVec
        sta StringFaultVec+1
        sta windowTop
        sta leftMargin
        sta leftMargin+1
        lda #SC_PIX_HEIGHT - 1
        sta windowBottom
        sec                     ; text stops before the right frame
        lda menuRight
        sbc #1
        sta rightMargin
        lda menuRight+1
        sbc #0
        sta rightMargin+1

        lda menuLeft            ; r11/r1H: position of the first item
        sta r11L
        lda menuLeft+1
        sta r11H
        lda menuTop             ; horizontal text starts 2 lines down
        bit menuAttr
        bmi @top
        clc
        adc #2
@top:   sta r1H
        lda #0
        sta item
@item:  ldx item                ; limit of this item
        bit menuAttr
        bmi @vlim
        lda r11L
        sta limitLo,x
        lda r11H
        sta limitHi,x
        jmp @text
@vlim:  lda r1H                 ; vertical limits: item tops
        sta limitLo,x
        lda #0
        sta limitHi,x
@text:  cpx count
        beq @seps
        jsr ItemText
        inc item
        jmp @item

@seps:  lda count               ; separators at the inner limits
        sec
        sbc #1
        beq @done
        sta item
        bit menuAttr
        bmi @hsep
        lda menuTop
        clc
        adc #1
        sta r3L
        lda menuBottom
        sec
        sbc #1
        sta r3H
@vsep:  ldx item
        lda limitLo,x
        sta r4L
        lda limitHi,x
        sta r4H
        lda #$AA
        jsr VerticalLine
        dec item
        bne @vsep
        beq @done
@hsep:  clc
        lda menuLeft
        adc #1
        sta r3L
        lda menuLeft+1
        adc #0
        sta r3H
        sec
        lda menuRight
        sbc #1
        sta r4L
        lda menuRight+1
        sbc #0
        sta r4H
@hline: ldx item
        lda limitLo,x
        sta r11L
        lda #$55
        jsr HorizontalLine
        dec item
        bne @hline

@done:  ldx #8                  ; restore
@restT: lda saveText,x
        sta baselineOffset,x
        dex
        bpl @restT
        ldx #5
@restM: lda saveMargins,x
        sta windowTop,x
        dex
        bpl @restM
        lda saveDisp
        sta dispBufferOn
        lda saveFault
        sta StringFaultVec
        lda saveFault+1
        sta StringFaultVec+1
        lda savePattern
        sta curPattern
        lda savePattern+1
        sta curPattern+1
        rts

; Print the text of item `item` and advance r11/r1H to the next item:
; horizontal 4 + text + 4 pixels, vertical 2 + (height + 1) + 2 lines;
; text baseline 2 + baselineOffset + 1 below the item top.
ItemText:
        lda item                ; r0 = item text
        asl
        asl
        adc item
        adc #7
        tay
        ldx menuNumber
        lda mPtrLo,x
        sta r10L
        lda mPtrHi,x
        sta r10H
        lda (r10),y
        sta r0L
        iny
        lda (r10),y
        sta r0H
        lda r1H                 ; keep the item top
        pha
        jsr Advance
        lda r1H
        clc
        adc baselineOffset
        sta r1H
        inc r1H
        jsr PutString
        pla
        sta r1H
        bit menuAttr
        bmi @vert
        jmp Advance             ; horizontal: 4 more after the text
@vert:  lda menuLeft            ; vertical: next item top
        sta r11L
        lda menuLeft+1
        sta r11H
        lda r1H
        sec
        adc curHeight
        clc
        adc #4
        sta r1H
        rts

; Horizontal: r11 += 4; vertical: r1H += 2, r11 += 4 (text inset).
Advance:
        bit menuAttr
        bpl @x
        inc r1H
        inc r1H
@x:     clc
        lda r11L
        adc #4
        sta r11L
        bcc @end
        inc r11H
@end:   rts

; r2-r4 = rectangle of item A of the current level: from its limit to
; the next one inclusive (item 0 one pixel in), across the inside.
ItemLimits:
        tax
        bit menuAttr
        bmi @vert
        lda limitLo,x
        sta r3L
        lda limitHi,x
        sta r3H
        lda limitLo+1,x
        sta r4L
        lda limitHi+1,x
        sta r4H
        cpx #0
        bne @hy
        inc r3L
        bne @hy
        inc r3H
@hy:    ldx menuTop
        inx
        stx r2L
        ldx menuBottom
        dex
        stx r2H
        rts
@vert:  lda limitLo,x
        sta r2L
        lda limitLo+1,x
        sta r2H
        cpx #0
        bne @vx
        inc r2L
@vx:    clc
        lda menuLeft
        adc #1
        sta r3L
        lda menuLeft+1
        adc #0
        sta r3H
        sec
        lda menuRight
        sbc #1
        sta r4L
        lda menuRight+1
        sbc #0
        sta r4H
        rts

; Item of the current level under the pointer.
FindItem:
        ldy count
        bit menuAttr
        bmi @vert
@hloop: dey
        beq @found
        lda mouseXPos+1
        cmp limitHi,y
        bne @hcmp
        lda mouseXPos
        cmp limitLo,y
@hcmp:  bcc @hloop
@found: tya
        rts
@vert:  lda mouseYPos
@vloop: dey
        beq @found
        cmp limitLo,y
        bcc @vloop
        tya
        rts

; Invert item A of the current level on the foreground screen.
InvertItem:
        jsr ItemLimits
        lda dispBufferOn
        pha
        lda #ST_WR_FORE
        sta dispBufferOn
        jsr InvertRectangle
        pla
        sta dispBufferOn
        rts

; --- MainLoop side -----------------------------------------------------

; A press on the current menu: mouse off, the item is inverted and
; becomes the level's selection, then its sub-menu opens, its dynamic
; sub-menu routine runs, or the selection flash starts for an action.
MenuPress:
        jsr MouseOff
        jsr FindItem
        ldx menuNumber
        sta mSel,x
        jsr InvertItem
        jsr ItemPointer
        ldy #2
        lda (r10),y
        bmi @sub
        asl
        bmi @dyn
        lda #1                  ; action: flash first
        sta flashState
        lda frameCount
        clc
        adc selectionFlash
        sta flashTime
        rts
@dyn:   jsr CallItem
        lda r0L
        ora r0H
        bne @sub
        rts
@sub:   jmp OpenSubMenu

; r10 = structure of the selected item of the current level, r0 = its
; pointer (sub-menu or routine).
ItemPointer:
        ldx menuNumber
        lda mSel,x
        asl
        asl
        adc mSel,x
        adc #7
        clc
        adc mPtrLo,x
        sta r10L
        lda mPtrHi,x
        adc #0
        sta r10H
        ldy #3
        lda (r10),y
        sta r0L
        iny
        lda (r10),y
        sta r0H
        rts

; Call the routine in r0 with A = the selected item of the current level.
CallItem:
        lda r0L
        sta @call+1
        lda r0H
        sta @call+2
        ldx menuNumber
        lda mSel,x
@call:  jmp $FFFF

; Called on every MainLoop pass: the selection flash of an action
; (selectionFlash frames inverted back, the same again inverted, then the
; item routine is called with the item number in A).
MenuTick:
        lda flashState
        beq @end
        lda frameCount
        sec
        sbc flashTime
        bmi @end
        ldx menuNumber
        lda mSel,x
        jsr InvertItem
        lda flashState
        cmp #2
        beq @call
        inc flashState
        lda frameCount
        clc
        adc selectionFlash
        sta flashTime
@end:   rts
@call:  lda #0
        sta flashState
        jsr ItemPointer
        jmp CallItem
