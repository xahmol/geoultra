; GeoUltra smoke test cartridge (Megabyter, CRT type 86, 8 KB banks).
;
; Test A: REU DMA reads the cartridge ROM window. For banks 1-7 the RAM
;         under $8000-$9FFF is cleared, the bank is stashed from $8000 into
;         the REU by DMA, fetched back to $2000 and compared with what the
;         CPU reads from the ROM.
; Test B: the REU keeps its content across a reset. A signature and a
;         boot counter live at REU $FFFF00; every start reads them first.
;
; Results at $C000 (readable through c64bridge/REST memory reads):
;   $C000-$C003  "GUSM" when all tests ran
;   $C004        1 = REU present
;   $C005        test A: 0 = pass, else the failing bank, $FF = not run
;   $C006        test A: page of the first mismatch ($80-$9F; $00 = bank
;                tag wrong, i.e. the CPU did not see the ROM)
;   $C007        test B: 1 = signature found after start, 0 = not found
;   $C008        boot counter

        .setcpu "6502"
        .import __RAMCODE_LOAD__, __RAMCODE_RUN__

MB_BANK   = $DE00
MB_CTRL   = $DE02
MB_ON8K   = $00         ; EXROM active, GAME inactive: ROML at $8000
MB_OFF    = $02         ; EXROM and GAME inactive

REU_CMD   = $DF01
REU_C64   = $DF02
REU_ADDR  = $DF04
REU_LEN   = $DF07
REU_CTRL  = $DF0A
REU_STASH = $90         ; execute, $FF00 trigger off, C64 -> REU
REU_FETCH = $91         ; execute, $FF00 trigger off, REU -> C64

RES       = $C000
SIGBUF    = $C010
BUF       = $2000
NBANKS    = 8

CHROUT    = $FFD2

        .segment "ZEROPAGE"
ptr_a:  .res 2
ptr_b:  .res 2

        .segment "HEADER"
        .word cold, cold
        .byte $C3, $C2, $CD, $38, $30   ; "CBM80"

        .segment "STARTUP"
cold:   sei
        ldx #$FF
        txs
        cld
        jsr $FDA3               ; IOINIT
        jsr $FD50               ; RAMTAS
        jsr $FD15               ; RESTOR
        jsr $FF5B               ; CINT
        cli
        ldx #0                  ; copy the test code (4 pages) to $C100
copy:   lda __RAMCODE_LOAD__,x
        sta __RAMCODE_RUN__,x
        lda __RAMCODE_LOAD__+$100,x
        sta __RAMCODE_RUN__+$100,x
        lda __RAMCODE_LOAD__+$200,x
        sta __RAMCODE_RUN__+$200,x
        lda __RAMCODE_LOAD__+$300,x
        sta __RAMCODE_RUN__+$300,x
        inx
        bne copy
        jmp main

        .segment "RAMCODE"

; Set the REU registers: C64 address A/X (low/high), REU address $bb:mm00
; with Y = mm and reu_bank = bb, length $2000 unless changed afterwards.
.macro  reu_setup c64, reuaddr, len
        lda #<(c64)
        sta REU_C64
        lda #>(c64)
        sta REU_C64+1
        lda #<(reuaddr)
        sta REU_ADDR
        lda #>(reuaddr)
        sta REU_ADDR+1
        lda #^(reuaddr)
        sta REU_ADDR+2
        lda #<(len)
        sta REU_LEN
        lda #>(len)
        sta REU_LEN+1
        lda #0
        sta REU_CTRL
.endmacro

main:   lda #0
        ldx #15
@clr:   sta RES,x
        dex
        bpl @clr
        lda #$FF
        sta RES+5
        jsr print
        .byte $93, "GEOULTRA SMOKE TEST", 13, 13, 0
        jsr reu_detect
        sta RES+4
        bne @reu
        jsr print
        .byte "REU: NONE", 13, 0
        jmp done
@reu:   jsr print
        .byte "REU: PRESENT", 13, 0
        jsr test_b
        jsr test_a
done:   lda #'G'
        sta RES
        lda #'U'
        sta RES+1
        lda #'S'
        sta RES+2
        lda #'M'
        sta RES+3
        jsr print
        .byte 13, "DONE", 13, 0
@loop:  jmp @loop

; Returns A = 1 when the REU's C64 address register holds written values.
reu_detect:
        lda #$55
        sta REU_C64
        cmp REU_C64
        bne @none
        lda #$AA
        sta REU_C64
        cmp REU_C64
        bne @none
        lda #1
        rts
@none:  lda #0
        rts

; Test B: read the signature from REU $FFFF00, report, rewrite it.
test_b: reu_setup SIGBUF, $FFFF00, 8
        lda #REU_FETCH
        sta REU_CMD
        ldx #4
@cmp:   lda SIGBUF,x
        cmp sig,x
        bne @new
        dex
        bpl @cmp
        lda #1
        sta RES+7
        ldx SIGBUF+5
        inx
        bne @store
@new:   lda #0
        sta RES+7
        ldx #1
@store: stx RES+8
        stx SIGBUF+5
        ldx #4
@cpy:   lda sig,x
        sta SIGBUF,x
        dex
        bpl @cpy
        reu_setup SIGBUF, $FFFF00, 8
        lda #REU_STASH
        sta REU_CMD
        jsr print
        .byte "B REU AFTER RESET: ", 0
        lda RES+7
        beq @nf
        jsr print
        .byte "KEPT", 0
        jmp @cnt
@nf:    jsr print
        .byte "EMPTY (FIRST RUN?)", 0
@cnt:   jsr print
        .byte 13, "  BOOT COUNT ", 0
        lda RES+8
        jsr hex
        lda #13
        jmp CHROUT

sig:    .byte "GUREU"

; Test A: ROM banks 1..7 via REU DMA, compared with the CPU's view.
test_a: sei
        lda #1
        sta bank
@bank:  lda #MB_OFF             ; clear the RAM under the ROM window
        sta MB_CTRL
        lda #0
        sta ptr_a
        lda #$80
        sta ptr_a+1
        ldx #$20
        ldy #0
        tya
@fill:  sta (ptr_a),y
        iny
        bne @fill
        inc ptr_a+1
        dex
        bne @fill
        lda #MB_ON8K
        sta MB_CTRL
        lda bank
        sta MB_BANK
        cmp $8000               ; the CPU must see the bank tag
        beq @tagok
        lda #0
        sta RES+6
        jmp @fail
@tagok: reu_setup $8000, $010000, $2000
        lda bank                ; REU address $01:bank*$20:00
        asl
        asl
        asl
        asl
        asl
        sta REU_ADDR+1
        lda #REU_STASH
        sta REU_CMD
        reu_setup BUF, $010000, $2000
        lda bank
        asl
        asl
        asl
        asl
        asl
        sta REU_ADDR+1
        lda #REU_FETCH
        sta REU_CMD
        lda #<BUF               ; compare BUF with the ROM
        sta ptr_a
        lda #>BUF
        sta ptr_a+1
        lda #0
        sta ptr_b
        lda #$80
        sta ptr_b+1
        ldx #$20
        ldy #0
@cmp:   lda (ptr_a),y
        cmp (ptr_b),y
        bne @diff
        iny
        bne @cmp
        inc ptr_a+1
        inc ptr_b+1
        dex
        bne @cmp
        inc bank
        lda bank
        cmp #NBANKS
        beq @pass
        jmp @bank
@pass:
        lda #0
        sta RES+5
        lda #0
        sta MB_BANK
        cli
        jsr print
        .byte "A ROM TO REU DMA: PASS", 13, 0
        rts
@diff:  lda ptr_b+1
        sta RES+6
@fail:  lda bank
        sta RES+5
        lda #0
        sta MB_BANK
        cli
        jsr print
        .byte "A ROM TO REU DMA: FAIL BANK ", 0
        lda RES+5
        jsr hex
        jsr print
        .byte " PAGE ", 0
        lda RES+6
        jsr hex
        lda #13
        jmp CHROUT

bank:   .byte 0

; Print the zero-terminated string that follows the jsr.
print:  pla
        sta ptr_b
        pla
        sta ptr_b+1
@next:  inc ptr_b
        bne @get
        inc ptr_b+1
@get:   ldy #0
        lda (ptr_b),y
        beq @end
        jsr CHROUT
        jmp @next
@end:   lda ptr_b+1
        pha
        lda ptr_b
        pha
        rts

; Print A as two hex digits.
hex:    pha
        lsr
        lsr
        lsr
        lsr
        jsr @dig
        pla
        and #$0F
@dig:   cmp #10
        bcc @num
        adc #6
@num:   adc #'0'
        jmp CHROUT
