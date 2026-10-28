; Icons: DoIcons and the press on an icon. Written from HG2G2022 chapter 3
; ("Icons"); behaviour details (menus off when the mouse was off, the
; hit test by cards, the busy flag during the flash, the double-click
; rule, the inverted rectangle) follow the reassembled GEOS 2.0 kernal,
; mist64/geos kernal/icon/icon1.s and icon2.s, read as behaviour
; reference only. Own code; checked with tests/conformance/icon.py.

        .include "geos.inc"

        .export DoIcons, IconPress, IconTick
        .import BitmapUp, InvertRectangle, StartMouseMode, frameCount

        .segment "KSTATE"               ; saved and restored by dialog boxes

iconNo:         .byte 0
iconBusy:       .byte 0         ; a selection is flashing: ignore presses
iconTime:       .byte 0
entry:          .byte 0         ; offset of the selected icon's entry

        .segment "CODE"

; DoIcons: r0 = icon table. Draws the enabled icons (dispBufferOn),
; full-screen mouse limits, icons on (menus off when the mouse was off),
; StartMouseMode with the table's pointer position. Destroys A, X, Y,
; r0-r15.
DoIcons:
        lda r0L
        sta IconDescVec
        lda r0H
        sta IconDescVec+1
        lda #0
        sta r10L
        sta iconBusy
@draw:  lda r10L                ; r0-r2 = picture, x, y, width, height
        jsr EntryOffset
        ldx #0
@copy:  lda (IconDescVec),y
        sta r0,x
        iny
        inx
        cpx #6
        bne @copy
        lda r0L
        ora r0H
        beq @skip
        jsr BitmapUp
@skip:  inc r10L
        lda r10L
        ldy #OFF_NM_ICNS
        cmp (IconDescVec),y
        bne @draw
        lda #0                  ; full-screen mouse limits
        sta mouseTop
        sta mouseLeft
        sta mouseLeft+1
        lda #SC_PIX_HEIGHT - 1
        sta mouseBottom
        lda #<(SC_PIX_WIDTH - 1)
        sta mouseRight
        lda #>(SC_PIX_WIDTH - 1)
        sta mouseRight+1
        lda mouseOn
        bmi @on
        and #<~MENUON_BIT
@on:    ora #ICONSON_BIT
        sta mouseOn
        ldy #OFF_IC_XMOUSE
        lda (IconDescVec),y
        sta r11L
        iny
        lda (IconDescVec),y
        sta r11H
        iny
        lda (IconDescVec),y
        tay
        sec
        jmp StartMouseMode

; Y = offset of icon A's entry in the table.
EntryOffset:
        asl
        asl
        asl
        clc
        adc #4
        tay
        rts

; A press that the menus did not take, with icons on. Returns carry set
; when it was handled (an icon, or a press during a flash), carry clear
; for otherPressVec.
IconPress:
        lda IconDescVec+1
        beq @none
        lda iconBusy
        bne @busy
        jsr FindIcon
        bcc @none
        sty entry
        sta iconNo
        bit iconSelFlag
        bmi @flash
        bvc @call
        jsr InvertIcon          ; ST_INVERT: inverted, stays so
        jmp @call
@flash: jsr InvertIcon          ; ST_FLASH: inverted for selectionFlash
        lda #1
        sta iconBusy
        lda frameCount
        clc
        adc selectionFlash
        sta iconTime
@busy:  sec
        rts
@call:  jsr CallIcon
        sec
        rts
@none:  clc
        rts

; Called on every MainLoop pass: ends the flash, then calls the icon.
IconTick:
        lda iconBusy
        beq @end
        lda frameCount
        sec
        sbc iconTime
        bmi @end
        jsr InvertIcon
        lda #0
        sta iconBusy
        jmp CallIcon
@end:   rts

; Call the selected icon's routine: r0L = icon, r0H = TRUE on a double
; click (a second press while dblClickCount still runs).
CallIcon:
        ldx #FALSE
        ldy #CLICK_COUNT
        lda dblClickCount
        beq @single
        ldx #TRUE
        ldy #0
@single:
        sty dblClickCount
        stx r0H
        lda iconNo
        sta r0L
        ldy entry
        iny
        iny
        iny
        iny
        iny
        iny
        lda (IconDescVec),y
        sta @call+1
        iny
        lda (IconDescVec),y
        sta @call+2
@call:  jmp $FFFF

; Find the enabled icon under the pointer (card of x within x..x+w-1,
; line within y..y+h-1). Returns carry set, A = icon, Y = entry offset.
FindIcon:
        lda mouseXPos+1         ; r1L = pointer card
        lsr
        lda mouseXPos
        ror
        lsr
        lsr
        sta r1L
        lda #0
        sta iconNo
@loop:  lda iconNo
        jsr EntryOffset
        lda (IconDescVec),y
        iny
        ora (IconDescVec),y
        beq @next
        iny                     ; OFF_I_X
        lda r1L
        sec
        sbc (IconDescVec),y
        bcc @next
        iny
        iny                     ; OFF_I_WIDTH
        cmp (IconDescVec),y
        bcs @next
        dey                     ; OFF_I_Y
        lda mouseYPos
        sec
        sbc (IconDescVec),y
        bcc @next
        iny
        iny                     ; OFF_I_HEIGHT
        cmp (IconDescVec),y
        bcs @next
        lda iconNo
        jsr EntryOffset
        lda iconNo
        sec
        rts
@next:  inc iconNo
        lda iconNo
        ldy #OFF_NM_ICNS
        cmp (IconDescVec),y
        bne @loop
        clc
        rts

; Invert the selected icon's rectangle on the foreground screen.
InvertIcon:
        ldy entry
        iny
        iny                     ; OFF_I_X
        lda (IconDescVec),y
        sta r3L
        iny
        lda (IconDescVec),y     ; OFF_I_Y
        sta r2L
        iny
        lda (IconDescVec),y     ; OFF_I_WIDTH
        clc
        adc r3L
        sta r4L
        iny
        lda (IconDescVec),y     ; OFF_I_HEIGHT
        clc
        adc r2L
        sec
        sbc #1
        sta r2H
        lda #0                  ; r3 = x * 8, r4 = (x + w) * 8 - 1
        sta r3H
        sta r4H
        ldx #3
@shift: asl r3L
        rol r3H
        asl r4L
        rol r4H
        dex
        bne @shift
        lda r4L
        bne @dec
        dec r4H
@dec:   dec r4L
        lda dispBufferOn
        pha
        lda #ST_WR_FORE
        sta dispBufferOn
        jsr InvertRectangle
        pla
        sta dispBufferOn
        rts
