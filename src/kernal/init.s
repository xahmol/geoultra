; Cold start: hardware, screen, mouse pointer, IRQ, then MainLoop.

        .include "geos.inc"
        .include "hw.inc"

        .import IrqEntry, InterruptMain, MainLoop, DefMouseVector, DefFaultVector
        .import Rectangle, FrameRectangle, SetPattern
        .import pointerPic, UseSystemFont, PutString, RecoverRectangle
        .import StringWidth, sysFlgCopy, DiskInit
        .export ColdStart

DEFAULT_COLORS  = $BF             ; dark grey pixels on light grey
DEFAULT_BORDER  = $0F             ; light grey
POINTER_COLOR   = $06             ; blue
IRQ_LINE        = 250             ; lower border

        .segment "CODE"

ColdStart:
        sei
        cld
        ldx #$FF
        txs
        lda #RAM_IO
        sta CPU_PORT
        lda #$7F                ; no CIA interrupts
        sta cia1Icr
        sta cia2Icr
        lda cia1Icr
        lda cia2Icr

        lda #0                  ; clear r0-r15, kernal zero page, a2-a9
        ldx #$7D
@zp:    sta $02,x
        dex
        bpl @zp
        tax                     ; clear the variables $8400-$88FF
@vars:  sta $8400,x
        sta $8500,x
        sta $8600,x
        sta $8700,x
        sta $8800,x
        inx
        bne @vars

        lda cia2DdrA            ; VIC-II bank 2 ($8000-$BFFF)
        ora #$03
        sta cia2DdrA
        lda cia2PortA
        and #$FC
        ora #$01
        sta cia2PortA
        lda #$3B                ; bitmap mode, 25 rows, display on
        sta vicCtrl1
        lda #$08                ; hires, 40 columns
        sta vicCtrl2
        lda #$38                ; colour matrix $8C00, bitmap $A000
        sta vicMemPtr
        lda #DEFAULT_BORDER
        sta vicBorder
        lda #DEFAULT_COLORS
        sta screencolors
        ldx #0                  ; colour matrix $8C00-$8FE7
@col:   sta COLOR_MATRIX,x
        sta COLOR_MATRIX+$100,x
        sta COLOR_MATRIX+$200,x
        sta COLOR_MATRIX+$2E8,x
        inx
        bne @col

        ldx #63                 ; mouse pointer: sprite 0 from $8A00
@spr:   lda pointerPic,x
        sta SPRITE_PICS,x
        dex
        bpl @spr
        lda #(SPRITE_PICS - $8000) / 64
        sta COLOR_MATRIX + $3F8
        lda #POINTER_COLOR
        sta vicSpr0Color
        lda #0
        sta vicSprMulti
        ldx #7                  ; sprite n picture at SPRITE_PICS + n * 64
@sprp:  txa
        clc
        adc #(SPRITE_PICS - $8000) / 64
        sta COLOR_MATRIX + $3F8,x
        dex
        bpl @sprp
        lda #$01
        sta vicSprEnable

        lda #0                  ; mouse limits: the whole screen
        sta mouseTop
        sta mouseLeft
        sta mouseLeft+1
        lda #SC_PIX_HEIGHT - 1
        sta mouseBottom
        lda #<(SC_PIX_WIDTH - 1)
        sta mouseRight
        lda #>(SC_PIX_WIDTH - 1)
        sta mouseRight+1
        jsr InitMouse
        lda #MOUSEON_BIT
        sta mouseOn

        lda #<InterruptMain
        sta intTopVector
        lda #>InterruptMain
        sta intTopVector+1
        lda #<DefMouseVector
        sta mouseVector
        lda #>DefMouseVector
        sta mouseVector+1
        lda #<DefFaultVector
        sta mouseFaultVec
        lda #>DefFaultVector
        sta mouseFaultVec+1
        lda #<RecoverRectangle  ; defaults from HG2G2022 chapter 14
        sta RecoverVector
        lda #>RecoverRectangle
        sta RecoverVector+1
        lda #8                  ; applications see 512 KB of REU (legacy view)
        sta ramExpSize
        lda #$80                ; MoveData by REU DMA
        sta sysRAMFlg
        sta sysFlgCopy
        lda #SELECTION_DELAY
        sta selectionFlash
        lda #ST_FLASH
        sta iconSelFlag

        lda #ST_WR_FORE | ST_WR_BACK
        sta dispBufferOn
        lda #2                  ; desktop background
        jsr SetPattern
        lda #0
        sta r2L
        sta r3L
        sta r3H
        lda #SC_PIX_HEIGHT - 1
        sta r2H
        lda #<(SC_PIX_WIDTH - 1)
        sta r4L
        lda #>(SC_PIX_WIDTH - 1)
        sta r4H
        jsr Rectangle

        lda #IRQ_LINE           ; raster IRQ once per frame
        sta vicRaster
        lda vicCtrl1
        and #$7F
        sta vicCtrl1
        lda #$01
        sta vicIrqMask
        sta vicIrq
        lda #RAM_ALL            ; from here on the font under I/O is visible
        sta CPU_PORT
        lda #0                  ; text: whole screen, plain style
        sta windowTop
        sta leftMargin
        sta leftMargin+1
        sta currentMode
        lda #SC_PIX_HEIGHT - 1
        sta windowBottom
        lda #<(SC_PIX_WIDTH - 1)
        sta rightMargin
        lda #>(SC_PIX_WIDTH - 1)
        sta rightMargin+1
        jsr UseSystemFont
        jsr DrawBanner
        jsr DiskInit            ; drives from the REU mount table
        cli
        jmp MainLoop

bannerText:
        .byte "GeoUltra ", BOLDON, "kernal", PLAINTEXT, " - ", ULINEON, "own font", ULINEOFF, ", 1.0", 0

; Boot screen: the banner text centred in a white framed box that is
; sized by the measured text (BANNER_PAD pixels left and right).
BANNER_PAD      = 10
BANNER_TOP      = 88
BANNER_HEIGHT   = 24
DrawBanner:
        lda #<bannerText
        sta r0L
        lda #>bannerText
        sta r0H
        jsr StringWidth         ; r2 = text width
        lda r2L                 ; r11 = text x = 160 - width / 2
        sta r5L
        lda r2H
        lsr
        sta r5H
        ror r5L
        sec
        lda #<(SC_PIX_WIDTH / 2)
        sbc r5L
        sta r11L
        lda #>(SC_PIX_WIDTH / 2)
        sbc r5H
        sta r11H
        sec                     ; box: text +- BANNER_PAD
        lda r11L
        sbc #BANNER_PAD
        sta r3L
        lda r11H
        sbc #0
        sta r3H
        clc
        lda r11L
        adc r2L
        sta r4L
        lda r11H
        adc r2H
        sta r4H
        clc
        lda r4L
        adc #BANNER_PAD - 1
        sta r4L
        bcc @box
        inc r4H
@box:   lda r11L                ; keep the text x over the drawing
        pha
        lda r11H
        pha
        lda #BANNER_TOP
        sta r2L
        lda #BANNER_TOP + BANNER_HEIGHT - 1
        sta r2H
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda #$FF
        jsr FrameRectangle
        pla
        sta r11H
        pla
        sta r11L
        lda #<bannerText        ; baseline: the font's 9 lines centred
        sta r0L
        lda #>bannerText
        sta r0H
        lda #BANNER_TOP + (BANNER_HEIGHT - 9) / 2 + 6
        sta r1H
        jmp PutString
