; Turbo per application (overlay module 16; docs/DESIGN.md "Turbo"): at
; every application start (OvAppGate, sysdrive.s, with its file header in
; fileHeader) the U64's speed is set: 1 MHz when its permanent name is on
; the SETTINGS.INI list ([system] slow=NAME, up to SLOW_MAX names, kept by
; TurboInit at SLOW_BANK:SLOW_LIST), else full speed (turboWant). The list
; is in bank 3 (padding of the cartridge image, filled anew at each boot,
; not in a hibernated session): a resumed session follows the settings of
; this boot. The
; speed in use is kept in turboNow (a resumed session gets it back).
; Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "drvflags.inc"

        .import SysRAMOp, turboWant, turboNow

SLOW_LIST       = $FF00         ; SLOW_MAX names of SLOW_NAME
SLOW_MAX        = 6             ; bytes, 0-padded (an empty name ends it)
SLOW_NAME       = 12
SLOW_LEN        = SLOW_MAX * SLOW_NAME

        .segment "OVL16"

        jmp SpeedFor            ; entry 0

; SpeedFor: the speed for the application whose header is in fileHeader.
; r0-r3 destroyed (OvAppGate keeps r0-r15).
SpeedFor:
        lda turboWant
        cmp #$FF                ; no turbo registers, or turbo=off
        bne :+
        rts
:
        tsx                     ; the list into SLOW_LEN bytes of stack
        txa
        sec
        sbc #SLOW_LEN
        tax
        txs
        inx
        stx r0L
        lda #>$0100
        sta r0H
        lda #<SLOW_LIST
        sta r1L
        lda #>SLOW_LIST
        sta r1H
        lda #<SLOW_LEN
        sta r2L
        lda #0
        sta r2H
        lda #SLOW_BANK
        sta r3L
        ldy #REU_FETCH
        jsr SysRAMOp
        lda turboWant           ; full speed, unless listed
        sta speed
        lda #0
        sta entry
@name:  ldy entry               ; Y: the entry's first byte in the list
        lda (r0),y
        beq @set                ; (an empty name: the list ends)
        ldx #0
@char:  lda (r0),y
        beq @slow               ; the whole name matched
        cmp fileHeader + O_GHFNAME,x
        bne @next
        iny
        inx
        cpx #SLOW_NAME
        bne @char
@slow:  lda #0                  ; listed: 1 MHz
        sta speed
        beq @set
@next:  lda entry
        clc
        adc #SLOW_NAME
        sta entry
        cmp #SLOW_LEN
        bne @name
@set:   tsx                     ; the stack room given back
        txa
        clc
        adc #SLOW_LEN
        tax
        txs
        lda speed
        sta turboNow
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda $D030
        ora #$01
        sta $D030
        lda speed
        sta $D031
        pla
        sta CPU_PORT
        plp
@end:   rts

speed:          .byte 0         ; (module bytes: no nested overlay calls
entry:          .byte 0         ; while they are used)
