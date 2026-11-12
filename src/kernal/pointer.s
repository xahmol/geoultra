; The mouse pointer's designs (docs/SETTINGS.md, the Pointer page;
; module 86). Four own drawings (tools/mkpointers.py): a classic arrow,
; a large arrow, a hand, a crosshair, each with its hot spot (the pixel
; the mouse position points at). A design is copied into the kernal's
; pointer picture (pointerPic, what the cold start and a new pointer
; use) and into sprite 0's picture, and PosPointer (irq.s) places the
; sprite so the hot spot is at the mouse: its x and y offsets are the
; operands PtrDX, PtrDY (24 and 50, less the hot spot). An application
; that draws its own pointer (DrawSprite on sprite 0) gets the offsets
; back to 24 and 50 (sprites.s), as GEOS 2.0 places it. Used at boot
; ([system] pointer=, mount.s) and by FE_POINTER. Own design and code.

        .include "geos.inc"
        .include "engine.inc"

        .import pointerPic, PtrDX, PtrDY

POS_DX          = 24            ; PosPointer's offsets for a hot spot 0, 0
POS_DY          = 50

        .segment "OVL86"
        .scope Mod86

        jmp OvApply             ; entry 0: A = the design (mount.s)
        jmp OvFePointer         ; entry 3: FE_POINTER

; OvFePointer (FE_POINTER): r2L = the design (0-3): applied at once.
; FE_BAD_PATH for a design that does not exist.
OvFePointer:
        lda argR2
        cmp #POINTERS_N
        bcc :+
        ldx #FE_BAD_PATH
        rts
:       jsr OvApply
        ldx #0
        rts

; OvApply: design A (0-3; others: nothing) into pointerPic and sprite
; 0's picture, its hot spot into PosPointer's offsets. Destroys A, X, Y.
OvApply:
        cmp #POINTERS_N
        bcs @end
        tax
        asl a                   ; its hot spot: offsets less it
        tay
        lda #POS_DX
        sec
        sbc PointerHot,y
        sta PtrDX
        lda #POS_DY
        sec
        sbc PointerHot + 1,y
        sta PtrDY
        lda #<Pointers          ; its picture: Pointers + X * 63
        sta r0L                 ; (r0: the caller's are kept by the file
        lda #>Pointers          ; engine's dispatcher; at boot free)
        sta r0H
@add:   dex
        bmi @copy
        lda r0L
        clc
        adc #63
        sta r0L
        bcc @add
        inc r0H
        bne @add
@copy:  ldy #62
@b:     lda (r0),y
        sta pointerPic,y
        sta SPRITE_PICS,y
        dey
        bpl @b
@end:   rts

        .include "pointers.inc"

        .endscope
