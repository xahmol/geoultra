; GeoUltra C64 boot ROM: Megabyter bank 0 at $8000.
;
; Shows the boot splash (copied by the CPU from the cartridge ROM, so it
; also works without an REU), checks the REU, copies the system image
; (ROM banks 1..IMG_BANKS) into the REU at $020000, switches the
; cartridge off and fetches every remaining image to its C64 address
; (docs/reference/ARCHITECTURE.md, "Boot"), then starts the kernal. Status
; messages are pre-drawn strips of the splash's status line
; (tools/dev/splash/mksplash.py --boot).

        .include "hw.inc"
        .include "image.inc"
        .include "splash.inc"

        .import __LOADER_LOAD__, __LOADER_RUN__

IOINIT  = $FDA3
KERNAL  = $4F00                 ; ColdStart, loaded with the system (segment
                                ; INIT; BootGEOS / ResetHandle reboot from ROM)
IMG_ROW = 7                     ; table row: REU address, C64 address, length
SCREEN  = $A000
COLOURS = $8C00
STATUS_ADDR  = SCREEN + STATUS_ROW * 320 + STATUS_COL * 8
STATUS_LINE  = STATUS_CELLS * 8             ; bytes per cell row of a strip
STATUS_COLRS = COLOURS + STATUS_ROW * 40 + STATUS_COL

src     = $FB                   ; zero page pointers (before GEOS runs)
dst     = $FD

        .segment "HEADER"
        .word Cold, Cold
        .byte $C3, $C2, $CD, $38, $30   ; "CBM80"

        .segment "STARTUP"
Cold:   sei
        ldx #$FF
        txs
        cld
        jsr IOINIT
        lda #$0B                ; screen off while the splash is copied
        sta vicCtrl1
        ldx #0
@copy:  lda __LOADER_LOAD__,x
        sta __LOADER_RUN__,x
        lda __LOADER_LOAD__+$100,x
        sta __LOADER_RUN__+$100,x
        inx
        bne @copy
        jmp Loader

        .segment "MESSAGES"
Messages:
        .incbin "splash_msg.bin"

        .segment "LOADER"

Loader: ldx #0                  ; the splash: CPU copies from the ROM
@splash:
        cpx #IMG_CPU * IMG_ROW
        beq @show
        stx row
        jsr CpuCopy
        lda row
        clc
        adc #IMG_ROW
        tax
        bne @splash
@show:  jsr ShowSplash

        lda #$55                ; an REU must be present
        sta reuC64
        cmp reuC64
        bne @none
        lda #$AA
        sta reuC64
        cmp reuC64
        beq @reu
@none:  lda #MSG_NO_REU
        jsr Status
        jsr StatusError
@halt:  jmp @halt
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

        lda #MSG_STARTING
        jsr Status
        lda #MB_OFF             ; cartridge off: $8000-$9FFF is RAM again
        sta mbCtrl

        ldx #IMG_CPU * IMG_ROW  ; fetch the other images with all RAM visible
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
        lda REU_TRIGGER         ; the write starts the DMA: the byte that
        sta REU_TRIGGER         ; is there written back (it is the input
                                ; driver's, $FE80-: storing A put $30 into
                                ; it once an earlier image had loaded it)
        lda #RAM_IO
        sta CPU_PORT
        txa
        clc
        adc #IMG_ROW
        tax
        cpx #IMG_COUNT * IMG_ROW
        bne @load
        jmp KERNAL

; Copy image table row X from the cartridge ROM with the CPU. Its REU
; address gives the place in the ROM: offset = address - $020000, bank =
; 1 + offset / $2000.
CpuCopy:
        lda table+1,x           ; bank = 1 + ((hi - 2) << 3 | mid >> 5)
        lsr
        lsr
        lsr
        lsr
        lsr
        sta tmp
        lda table+2,x
        sec
        sbc #2
        asl
        asl
        asl
        ora tmp
        clc
        adc #1
        sta bank
        sta mbBank
        lda table,x             ; src = $8000 + offset & $1FFF
        sta src
        lda table+1,x
        and #$1F
        ora #$80
        sta src+1
        lda table+3,x
        sta dst
        lda table+4,x
        sta dst+1
        lda table+5,x
        sta count
        lda table+6,x
        sta count+1
        ldy #0
@byte:  lda (src),y
        sta (dst),y
        inc dst
        bne @src
        inc dst+1
@src:   inc src
        bne @count
        inc src+1
        lda src+1
        cmp #$A0                ; end of the window: next bank
        bne @count
        lda #$80
        sta src+1
        inc bank
        lda bank
        sta mbBank
@count: lda count
        bne @dec
        dec count+1
@dec:   dec count
        lda count
        ora count+1
        bne @byte
        rts

; VIC-II bank 2, bitmap at $A000, colours at $8C00, display on.
ShowSplash:
        lda cia2DdrA
        ora #$03
        sta cia2DdrA
        lda cia2PortA
        and #$FC
        ora #$01
        sta cia2PortA
        lda #$08
        sta vicCtrl2
        lda #$38
        sta vicMemPtr
        lda #0
        sta vicSprEnable
        lda #BORDER_COLOUR
        sta vicBorder
        lda #$3B
        sta vicCtrl1
        rts

; Show status message A: copy its strip (in ROM bank 0) into the status
; line. The cartridge must still be on.
Status: tax
        lda #0
        sta mbBank
        lda msgLo,x
        sta src
        lda msgHi,x
        sta src+1
        ldy #0
@row1:  lda (src),y
        sta STATUS_ADDR,y
        iny
        cpy #STATUS_LINE
        bne @row1
        lda src                 ; the strip's second cell row
        clc
        adc #STATUS_LINE
        sta src
        bcc @row2y
        inc src+1
@row2y: ldy #0
@row2:  lda (src),y
        sta STATUS_ADDR + 320,y
        iny
        cpy #STATUS_LINE
        bne @row2
        rts

; Colour the status line light red: an error.
StatusError:
        ldx #STATUS_CELLS - 1
        lda #STATUS_ERROR_COLOURS
@col:   sta STATUS_COLRS,x
        sta STATUS_COLRS + 40,x
        dex
        bpl @col
        rts

msgLo:
        .repeat MSG_COUNT, i
        .byte <(Messages + i * STATUS_SIZE)
        .endrepeat
msgHi:
        .repeat MSG_COUNT, i
        .byte >(Messages + i * STATUS_SIZE)
        .endrepeat

bank:   .byte 0
tmp:    .byte 0
row:    .byte 0
count:  .word 0
table:  IMG_TABLE
