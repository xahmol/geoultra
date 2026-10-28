; Interrupt handler, InterruptMain and MainLoop.

        .include "geos.inc"
        .include "hw.inc"

        .export IrqEntry, NmiEntry, InterruptMain, MainLoop, DefMouseVector
        .import KeyScan, GetNextChar, ProcessTimers, RunProcesses

        .segment "DATA"

irqSaveRegs:    .res 32         ; r0-r15 during the IRQ
irqSavePort:    .res 1

        .segment "CODE"

; Hardware IRQ (raster, once per frame). Saves A, X, Y, the CPU port and
; r0-r15, calls intTopVector (InterruptMain) and intBotVector.
IrqEntry:
        pha
        txa
        pha
        tya
        pha
        lda CPU_PORT
        sta irqSavePort
        lda #RAM_IO
        sta CPU_PORT
        lda vicIrq
        sta vicIrq
        ldx #31
@save:  lda r0,x
        sta irqSaveRegs,x
        dex
        bpl @save
        jsr CallTop
        lda intBotVector
        ora intBotVector+1
        beq @rest
        jsr CallBot
@rest:  ldx #31
@load:  lda irqSaveRegs,x
        sta r0,x
        dex
        bpl @load
        lda irqSavePort
        sta CPU_PORT
        pla
        tay
        pla
        tax
        pla
NmiEntry:
        rti

CallTop:
        jmp (intTopVector)
CallBot:
        jmp (intBotVector)

; Jump table InterruptMain: the kernal's own per-frame work. Runs with
; I/O banked in. The input driver reads the pots first, while port 1 is
; still selected from the previous frame; the keyboard scan selects it
; again at its end.
InterruptMain:
        bit mouseOn
        bpl @keys
        jsr UpdateMouse
        jsr PosPointer
@keys:  jsr KeyScan
        jmp ProcessTimers

; Position sprite 0 (the pointer) at mouseXPos/mouseYPos.
PosPointer:
        lda mouseXPos
        clc
        adc #24
        sta vicSpr0X
        lda mouseXPos+1
        adc #0
        and #$01
        sta r0L
        lda vicSprXMsb
        and #$FE
        ora r0L
        sta vicSprXMsb
        lda mouseYPos
        clc
        adc #50
        sta vicSpr0Y
        rts

; Jump table MainLoop: appMain, then input events, then processes.
MainLoop:
        lda appMain
        ora appMain+1
        beq @input
        jsr CallApp
@input: jsr HandleInput
        jsr RunProcesses
        jmp MainLoop

CallApp:
        jmp (appMain)

; Dispatch the events the interrupt level flagged in pressFlag.
HandleInput:
        lda pressFlag
        and #INPUT_BIT
        beq @mouse
        lda #<~INPUT_BIT
        jsr ClearPress
        lda inputVector
        ora inputVector+1
        beq @mouse
        jsr CallInput
@mouse: lda pressFlag
        and #MOUSE_BIT
        beq @key
        lda #<~MOUSE_BIT
        jsr ClearPress
        lda mouseVector
        ora mouseVector+1
        beq @key
        jsr CallMouse
@key:   lda pressFlag
        and #KEYPRESS_BIT
        beq @end
        jsr GetNextChar
        beq @end
        sta keyData
        lda keyVector
        ora keyVector+1
        beq @end
        jmp (keyVector)
@end:   rts

; pressFlag &= A, safe against the IRQ setting other bits meanwhile.
ClearPress:
        php
        sei
        and pressFlag
        sta pressFlag
        plp
        rts

CallInput:
        jmp (inputVector)
CallMouse:
        jmp (mouseVector)

; Default mouseVector: menus and icons come later; a press or release
; elsewhere goes to otherPressVec.
DefMouseVector:
        lda otherPressVec
        ora otherPressVec+1
        beq @end
        jmp (otherPressVec)
@end:   rts
