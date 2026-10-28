; REU and block moves: DoRAMOp, StashRAM, FetchRAM, SwapRAM, VerifyRAM,
; MoveData, i_MoveData. Written from the HG2G2022 descriptions; checked
; with tests/conformance/misc.py.
;
; Applications see ramExpSize banks (the legacy view, docs/DESIGN.md);
; their bank n is physical REU bank LEGACY_BASE + n, so they can never
; reach the system banks, drives or task slots. Their bank 0 is also
; MoveData's DMA scratch area, as in GEOS 2.0.

        .include "geos.inc"
        .include "hw.inc"

        .export DoRAMOp, StashRAM, FetchRAM, SwapRAM, VerifyRAM
        .export MoveData, i_MoveData
        .import DoInlineReturn

LEGACY_BASE     = 248           ; physical bank of the applications' bank 0
DEV_NOT_FOUND   = $0D
returnAddress   = $3D

        .segment "DATA"

port:   .byte 0
mdCount:.res 2

        .segment "CODE"

; StashRAM / FetchRAM / SwapRAM / VerifyRAM: r0 = C64 address, r1 = REU
; address, r2 = length, r3L = bank. Returns X = error, A = status & $60.
StashRAM:
        ldy #REU_STASH
        bne DoRAMOp
FetchRAM:
        ldy #REU_FETCH
        bne DoRAMOp
SwapRAM:
        ldy #REU_STASH | 2
        bne DoRAMOp
VerifyRAM:
        ldy #REU_STASH | 3

; DoRAMOp: as above, Y = REU command. r0-r3L unchanged. Destroys Y.
DoRAMOp:
        lda r3L
        cmp ramExpSize
        bcc @bank
        ldx #DEV_NOT_FOUND
        lda #0
        rts
@bank:  php
        sei
        lda CPU_PORT
        sta port
        lda #RAM_IO
        sta CPU_PORT
        lda r0L
        sta reuC64
        lda r0H
        sta reuC64+1
        lda r1L
        sta reuAddr
        lda r1H
        sta reuAddr+1
        lda r3L
        clc
        adc #LEGACY_BASE
        sta reuAddr+2
        lda r2L
        sta reuLen
        lda r2H
        sta reuLen+1
        lda #0
        sta reuCtrl
        sty reuCmd
        lda reuStatus
        and #$60
        ldx port
        stx CPU_PORT
        ldx #0
        plp
        rts

; MoveData: r0 = source, r1 = destination, r2 = count; overlapping areas
; in either direction. With sysRAMFlg bit 7 by REU DMA (through the
; applications' bank 0), else by the CPU. r0-r2 unchanged; destroys A, Y.
MoveData:
        lda r2L
        ora r2H
        beq @end
        bit sysRAMFlg
        bpl Cpu
        txa
        pha
        lda r3L
        pha
        lda #0
        sta r3L
        lda r1L                 ; stash the source to REU 0:0000 ...
        pha
        lda r1H
        pha
        lda #0
        sta r1L
        sta r1H
        jsr StashRAM
        pla                     ; ... and fetch it to the destination
        sta r1H
        pla
        sta r1L
        lda r0L
        pha
        lda r0H
        pha
        lda r1L
        sta r0L
        lda r1H
        sta r0H
        lda #0
        sta r1L
        sta r1H
        jsr FetchRAM
        lda r0L                 ; r0/r1 back
        sta r1L
        lda r0H
        sta r1H
        pla
        sta r0H
        pla
        sta r0L
        pla
        sta r3L
        pla
        tax
@end:   rts

; CPU copy: forwards when the destination is below the source, else
; backwards from the end.
Cpu:    lda r2L
        sta mdCount
        lda r2H
        sta mdCount+1
        lda r1H
        cmp r0H
        bne @cmp
        lda r1L
        cmp r0L
@cmp:   bcs Backward
        lda r0L                 ; forwards, self-modified addresses
        sta @src+1
        lda r0H
        sta @src+2
        lda r1L
        sta @dst+1
        lda r1H
        sta @dst+2
        ldy #0
@fwd:   lda $FFFF
@src    = * - 3
        sta $FFFF
@dst    = * - 3
        inc @src+1
        bne @s
        inc @src+2
@s:     inc @dst+1
        bne @d
        inc @dst+2
@d:     lda mdCount
        bne @dec
        dec mdCount+1
@dec:   dec mdCount
        lda mdCount
        ora mdCount+1
        bne @fwd
        rts

Backward:
        clc                     ; the last byte of each area
        lda r0L
        adc r2L
        sta @src+1
        lda r0H
        adc r2H
        sta @src+2
        clc
        lda r1L
        adc r2L
        sta @dst+1
        lda r1H
        adc r2H
        sta @dst+2
@back:  lda @src+1              ; step back first: the addresses are one past
        bne @s
        dec @src+2
@s:     dec @src+1
        lda @dst+1
        bne @d
        dec @dst+2
@d:     dec @dst+1
        lda $FFFF
@src    = * - 3
        sta $FFFF
@dst    = * - 3
        lda mdCount
        bne @dec
        dec mdCount+1
@dec:   dec mdCount
        lda mdCount
        ora mdCount+1
        bne @back
        rts

; i_MoveData: .word source, destination, count follow the jsr.
i_MoveData:
        pla
        sta returnAddress
        pla
        sta returnAddress+1
        ldy #6
@args:  lda (returnAddress),y
        sta r0-1,y
        dey
        bne @args
        jsr MoveData
        php
        lda #7
        jmp DoInlineReturn
