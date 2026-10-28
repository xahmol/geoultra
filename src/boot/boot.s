; GeoUltra C64 boot ROM: Megabyter bank 0 at $8000.
;
; Copies the system image (ROM banks 1..IMG_BANKS) into the REU at
; $020000, switches the cartridge off and fetches every image to its C64
; address (docs/ARCHITECTURE.md, "Boot"), then starts the kernal.

        .include "hw.inc"
        .include "image.inc"

        .import __LOADER_LOAD__, __LOADER_RUN__

IOINIT  = $FDA3
KERNAL  = $C000
IMG_ROW = 7                     ; table row: REU address, C64 address, length

        .segment "HEADER"
        .word Cold, Cold
        .byte $C3, $C2, $CD, $38, $30   ; "CBM80"

        .segment "STARTUP"
Cold:   sei
        ldx #$FF
        txs
        cld
        jsr IOINIT
        ldx #0
@copy:  lda __LOADER_LOAD__,x
        sta __LOADER_RUN__,x
        lda __LOADER_LOAD__+$100,x
        sta __LOADER_RUN__+$100,x
        inx
        bne @copy
        jmp Loader

        .segment "LOADER"

Loader: lda #$55                ; an REU must be present
        sta reuC64
        cmp reuC64
        bne @none
        lda #$AA
        sta reuC64
        cmp reuC64
        beq @reu
@none:  jmp NoReu
@reu:

        lda #1                  ; ROM bank n -> REU $020000 + (n-1) * $2000
        sta bank
@stash: lda bank
        sta mbBank
        sec
        sbc #1
        sta tmp
        asl
        asl
        asl
        asl
        asl
        sta reuAddr+1
        lda tmp
        lsr
        lsr
        lsr
        clc
        adc #2
        sta reuAddr+2
        lda #0
        sta reuAddr
        sta reuC64
        sta reuLen
        sta reuCtrl
        lda #$80
        sta reuC64+1
        lda #$20
        sta reuLen+1
        lda #REU_STASH
        sta reuCmd
        inc bank
        lda bank
        cmp #IMG_BANKS + 1
        bne @stash

        lda #MB_OFF             ; cartridge off: $8000-$9FFF is RAM again
        sta mbCtrl

        ldx #0                  ; fetch every image with all RAM visible
@load:  lda table,x
        sta reuAddr
        lda table+1,x
        sta reuAddr+1
        lda table+2,x
        sta reuAddr+2
        lda table+3,x
        sta reuC64
        lda table+4,x
        sta reuC64+1
        lda table+5,x
        sta reuLen
        lda table+6,x
        sta reuLen+1
        lda #0
        sta reuCtrl
        lda #REU_FETCH_FF00
        sta reuCmd
        lda #RAM_ALL
        sta CPU_PORT
        sta REU_TRIGGER         ; the write starts the DMA
        lda #RAM_IO
        sta CPU_PORT
        txa
        clc
        adc #IMG_ROW
        tax
        cpx #IMG_COUNT * IMG_ROW
        bne @load
        jmp KERNAL

NoReu:  lda #2                  ; red border: no REU
        sta vicBorder
@halt:  jmp @halt

bank:   .byte 0
tmp:    .byte 0
table:  IMG_TABLE
