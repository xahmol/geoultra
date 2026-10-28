; Interrupt handler, InterruptMain and MainLoop.

        .include "geos.inc"
        .include "hw.inc"

        .export IrqEntry, NmiEntry, InterruptMain, MainLoop

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
; I/O banked in.
InterruptMain:
        bit mouseOn
        bpl @done
        jsr UpdateMouse
        jsr PosPointer
@done:  rts

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

; Jump table MainLoop: calls appMain on every pass.
MainLoop:
        lda appMain
        ora appMain+1
        beq MainLoop
        jsr CallApp
        jmp MainLoop

CallApp:
        jmp (appMain)
