; Overlays: rarely used kernal routines live in modules of OVL_SIZE bytes
; in the REU (at the start of the system image, REU $020000) and run in
; the slot at OVL_SLOT ($9D80-$9F6F, the end of the disk driver area);
; $9F70-$9FFF is scratch for the running module that loads leave alone
; (users: write-back and hibernation from MainLoop; the file engine's
; work area during a call, engine.inc).
; A routine is reached through a resident stub:
;
;       jsr OvlCall
;       .byte module, entry         ; entry = offset in the module's table
;
; OvlCall fetches the module (one REU DMA) when another one is in the
; slot, calls the entry with A, X, Y and the flags as at the stub, then
; fetches the previous module back and returns to the stub's caller (the
; stub is entered like the routine itself), so overlay routines may call
; others. Rules: overlay code never installs a vector into the slot
; (a callback may find another module there), and a module's own bytes
; (variables included) are fetched anew from the REU after every nested
; overlay call, so values that must survive one live outside the module.
; docs/ARCHITECTURE.md.

        .include "geos.inc"
        .include "hw.inc"

        .export OvlCall

OVL_SLOT        = $9D80
OVL_SIZE        = $01F0         ; a module; $9F70-$9FFF: scratch for
                                ; the running module (kept across loads)
OVL_REU         = $020000
OVL_STRIDE      = $0200         ; a module's place in the REU (OVL_SIZE used)
        .assert <OVL_REU = 0 && >OVL_REU = 0, error, "OvlLoad: OVL_REU on a bank start"
NO_MODULE       = $FF

        .segment "DATA"

ovCur:  .byte NO_MODULE         ; the module in the slot
ovA:    .byte 0
ovX:    .byte 0
ovY:    .byte 0
ovP:    .byte 0
ovMod:  .byte 0
ovEntry:.byte 0

        .segment "KCODE"                ; low kernal area (space)

OvlCall:
        php
        sta ovA
        stx ovX
        sty ovY
        pla
        sta ovP
        pla                     ; the stub's return address (its jsr's last
        sta @mod+1              ; byte), only to read the two bytes after
        sta @entry+1            ; it: the return goes to the stub's caller
        pla
        sta @mod+2
        sta @entry+2
        ldy #1
@mod:   lda $FFFF,y
        sta ovMod
        iny
@entry: lda $FFFF,y
        sta ovEntry
        lda ovCur               ; the previous module, for the way back
        pha
        lda ovMod
        jsr OvlLoad
        clc
        lda #<OVL_SLOT
        adc ovEntry
        sta @call+1
        lda #>OVL_SLOT
        adc #0
        sta @call+2
        lda ovP
        pha
        lda ovA
        ldx ovX
        ldy ovY
        plp
@call:  jsr $FFFF
        php
        sta ovA
        stx ovX
        sty ovY
        pla
        sta ovP
        pla
        jsr OvlLoad
        lda ovP
        pha
        lda ovA
        ldx ovX
        ldy ovY
        plp
        rts

        .segment "CODE"

; OvlLoad: A = module into the slot (NO_MODULE: leave it).
OvlLoad:
        cmp ovCur
        beq @end
        cmp #NO_MODULE
        beq @end
        sta ovCur
        tax
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda #<OVL_SLOT
        sta reuC64
        lda #>OVL_SLOT
        sta reuC64+1
        lda #<OVL_REU           ; module X at OVL_REU + X * OVL_STRIDE
        sta reuAddr             ; (the Makefile spreads the linker's
        txa                     ; modules to that stride)
        asl
        sta reuAddr+1
        lda #^OVL_REU
        sta reuAddr+2
        lda #<OVL_SIZE
        sta reuLen
        lda #>OVL_SIZE
        sta reuLen+1
        lda #0
        sta reuCtrl
        lda #REU_FETCH
        sta reuCmd
        pla
        sta CPU_PORT
        plp
@end:   rts
