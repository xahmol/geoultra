; Cold start: hardware, screen, mouse pointer, IRQ, then EnterDeskTop
; (GeoUltra's desktop, or GEOS 2.0's with SETTINGS.INI desktop=geos;
; gush with start=gush). Runs
; once from $4F00 (segment INIT, loaded by the boot ROM; applications
; overwrite it later), so cold-start-only code costs no kernal space.

        .include "geos.inc"
        .include "hw.inc"

        .import IrqEntry, InterruptMain, MainLoop, DefMouseVector, DefFaultVector
        .import Rectangle, FrameRectangle, SetPattern
        .import pointerPic, UseSystemFont, PutString, RecoverRectangle
        .import StringWidth, sysFlgCopy, DiskInit, ExtraColours, ClockInit
        .import MountAll, SerialFromDisk, TurboInit, SaveJumpTab, HibResumeOvl, RtcClockOvl
        .export ColdStart
        .import startGush, FileEngine

DEFAULT_COLORS  = $BF             ; dark grey pixels on light grey
DEFAULT_BORDER  = $0F             ; light grey
POINTER_COLOR   = $06             ; blue
IRQ_LINE        = 250             ; lower border
EnterDeskTop    = $C22C           ; GEOS jump table

        .segment "INIT"

ColdStart:                      ; $4F00: the boot ROM jumps here
        .assert ColdStart = $4F00, lderror, "ColdStart must start INIT"
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
        jsr ExtraColours

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
        lda #RAM_ALL            ; the patterns are under I/O
        sta CPU_PORT
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
        lda #RAM_IO
        sta CPU_PORT

        lda #IRQ_LINE           ; raster IRQ once per frame
        sta vicRaster
        lda vicCtrl1
        and #$7F
        sta vicCtrl1
        lda #$01
        sta vicIrqMask
        sta vicIrq
        jsr ClockInit
        jsr MountAll            ; images from MOUNTS.INI (Ultimate only)
        jsr TurboInit           ; the U64 at full speed
        jsr HibResumeOvl        ; a hibernated session: resumed (no return)
        jsr RtcClockOvl         ; the date and time from the Ultimate
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
        jsr DiskInit            ; drives from the REU mount table
        jsr SerialFromDisk      ; the user's GEOS serial, when a boot disk is in
        jsr SaveJumpTab         ; the copy that StartAppl/EnterDeskTop restore
        cli
        lda #0                  ; SETTINGS.INI [time] ntp=: the clocks from
        sta r0L                 ; that server (FE_NTP; nothing without one,
        sta r0H                 ; errors left: the Ultimate's clock stays)
        lda #FE_NTP
        jsr FileEngine
        bit startGush           ; SETTINGS.INI start=gush: gush from drive
        bpl @loop               ; E (FE_RUNSYS); back only when it failed
        lda #<gushName
        sta r0L
        lda #>gushName
        sta r0H
        lda #FE_RUNSYS
        jsr FileEngine
@loop:  jmp EnterDeskTop          ; (no return)

gushName:
        .byte "gush", 0
FE_RUNSYS       = 22            ; (engine.inc)
FE_NTP          = 29
