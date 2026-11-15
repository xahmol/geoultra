; Loading and starting: GetFile, LdFile, LdApplic, LdDeskAcc, RstrAppl,
; StartAppl, EnterDeskTop, FirstInit, Panic, Sleep, CRC. Written from
; the HG2G2022 descriptions; behaviour details (which file types GetFile
; starts, the load options kept across the warm start, record 0 of a
; VLIR file, the deskTop version test, the sleep queue woken from
; MainLoop, Panic's message, the CRC polynomial and start value) follow
; the reassembled GEOS 2.0 kernal, mist64/geos kernal/load/*.s,
; deskacc.s, init/*.s, panic.s, process3*.s, math/crc.s, read as
; behaviour reference only. Own code; checked with tests/conformance/load.py.
;
; Desk accessories swap through REU bank DA_BANK instead of a swap file:
; the memory the accessory loads over and the saved kernal state go to
; the same addresses in that bank.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"

        .export GetFile, LdFile, LdApplic, LdDeskAcc, RstrAppl, StartAppl
        .import ptrColour, progColours
        .export EnterDeskTop, FirstInit, Panic, Sleep, CRC
        .export SleepTick, WakeSleepers, InitMachine, ExtraColours, SaveJumpTab

JT_START        = $C100         ; the GEOS 2.0 jump table
JT_SIZE         = $01D7
JT_COPY         = $1000         ; its copy in REU bank 1
        .import FindFile, ReadFile, GetFHdrInfo, CopyFString
        .import Ddec, SysRAMOp, SaveState, RestoreState, InitGEOEnv
        .import UseSystemFont, MainLoopCall, KeyReset, DoDlgBox, SetDevice
        .import IrqEntry, NmiEntry, SetPattern, Rectangle, TodMode, OvlCall
        .import taskName
        .import ScrapFind, SpoolLd
        .import WriteBackNow, AppGate, RefusedMsg, ownDesk, FileEngine

DA_BANK         = 18
MAX_SLEEP       = 20
IRQ_LINE        = 250

        .segment "DATA"

loadOpt:        .byte 0         ; r0L, r10L, r7 of the last load call
loadR10:        .byte 0
loadAddr:       .word 0
daStart:        .word 0
daLength:       .word 0
daPC:           .word 0
daSP:           .byte 0
dtDrive:        .byte 0
numSleep:       .byte 0
sleepLo:        .res MAX_SLEEP
sleepHi:        .res MAX_SLEEP
sleepRtnLo:     .res MAX_SLEEP
sleepRtnHi:     .res MAX_SLEEP

        .segment "IOCODE"       ; (under I/O, as in GEOS 2.0)

; GetFile: r6 = name. Starts applications and auto-exec files (LdApplic),
; runs desk accessories (LdDeskAcc), loads anything else (LdFile).
; r0L, r7, r2, r3, r10L as for those. X = error.
GetFile:
        jsr SaveArgs
        jsr ScrapFind       ; (a scrap: the store, scrap.s; then SysFindFile,
                            ; drive E: desk accessories)
        txa
        bne @end
        jsr LoadArgs
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        lda dirEntryBuf + OFF_GFILE_TYPE
        cmp #DESK_ACC
        bne @app
        jmp LdDeskAcc
@app:   cmp #APPLICATION
        beq @start
        cmp #AUTO_EXEC
        bne LdFile
@start: jmp LdApplic
@end:   rts

; LdFile: r9 = directory entry. Loads the file (record 0 of a VLIR file)
; at its header's load address, or at r7 when bit 0 of the last load
; options was set. X = error; r7 = end of the data.
LdFile: jsr GetFHdrInfo
        txa
        bne @end
        lda fileHeader + O_GHSTR_TYPE
        cmp #VLIR
        bne @addr
        jsr ReadBuff            ; GetFHdrInfo left r1 = the index block
        txa
        bne @end
        ldx #INV_RECORD
        lda diskBlkBuf+2
        sta r1L
        beq @end
        lda diskBlkBuf+3
        sta r1H
@addr:  lda loadOpt
        lsr
        bcc @read
        lda loadAddr
        sta r7L
        lda loadAddr+1
        sta r7H
@read:  lda #$FF
        sta r2L
        sta r2H
        jmp SpoolLd             ; (ReadFile, then a printer driver's
@end:   rts                     ; entries caught: spool.s)

; LdApplic: r9 = entry, r0L / r7 / r2 / r3 as GetFile. Loads and starts
; the application; returns only with an error or an own load address.
LdApplic:
        jsr AppGate             ; (X <> 0: refused, sysdrive.s; the GEOS
        txa                     ; 2.0 deskTop calls LdApplic directly)
        bne @end
        jsr SaveArgs
        jsr LdFile
        txa
        bne @end
        lda loadOpt
        lsr
        bcs @end
        jsr LoadArgs
        lda fileHeader + O_GHST_VEC
        sta r7L
        lda fileHeader + O_GHST_VEC + 1
        sta r7H
        jmp StartAppl
@end:   rts

        .segment "KCODE"

; SaveArgs: keep r0L, r10L, r7; with bit 7 or 6 of r0L the data disk and
; file names (r2, r3) to dataDiskName and dataFileName.
SaveArgs:
        lda r7L
        sta loadAddr
        lda r7H
        sta loadAddr+1
        lda r10L
        sta loadR10
        lda r0L
        sta loadOpt
        and #$C0
        beq @end
        lda #<dataDiskName
        sta r4L
        lda #>dataDiskName
        sta r4H
        ldx #r2
        jsr @copy
        lda #<dataFileName
        sta r4L
        lda #>dataFileName
        sta r4H
        ldx #r3
@copy:  ldy #r4
        lda #16
        jmp CopyFString
@end:   rts

; LoadArgs: r10L, r0L (r7 with bit 0) back; r2 / r3 = the name buffers.
LoadArgs:
        lda loadR10
        sta r10L
        lda loadOpt
        sta r0L
        lsr
        bcc @names
        lda loadAddr
        sta r7L
        lda loadAddr+1
        sta r7H
@names: lda #<dataDiskName
        sta r2L
        lda #>dataDiskName
        sta r2H
        lda #<dataFileName
        sta r3L
        lda #>dataFileName
        sta r3H
        rts

; StartAppl: r7 = start address, r0L / r2 / r3 / r10L passed on. Warm
; start, then the application from MainLoop. Does not return.
StartAppl:
        sei
        cld
        ldx #$FF
        txs
        jsr SaveArgs
        jsr RepairJumpTab       ; (destroys r0-r3: LoadArgs sets them)
        jsr InitMachine
        jsr UseSystemFont
        jsr LoadArgs
        lda loadAddr
        ldx loadAddr+1
        jmp MainLoopCall

; Jump table repair: SaveJumpTab (cold start) keeps the jump table in REU
; bank 1; RepairJumpTab (StartAppl, EnterDeskTop) puts it back, so that a
; program that changed it (a buggy one, or one that sabotages the system
; when it finds a foreign serial number) cannot break the next ones.
; Destroy r0-r3, A, X, Y.
SaveJumpTab:
        ldy #REU_STASH
        .byte $2C               ; (skips the next ldy)
RepairJumpTab:
        ldy #REU_FETCH
        lda #<JT_START
        sta r0L
        lda #>JT_START
        sta r0H
        lda #<JT_COPY
        sta r1L
        lda #>JT_COPY
        sta r1H
        lda #<JT_SIZE
        sta r2L
        lda #>JT_SIZE
        sta r2H
        lda #1                  ; SYS_BANK
        sta r3L
        jmp SysRAMOp

        .segment "IOCODE"       ; (under I/O, as in GEOS 2.0)

; LdDeskAcc: r9 = entry, r10L passed on. Saves what the accessory loads
; over and the kernal state to REU bank DA_BANK, runs it; returns when it
; calls RstrAppl. X = error.
LdDeskAcc:
        lda r10L
        sta loadR10
        jsr GetFHdrInfo
        txa
        bne @end
        lda r1L                 ; data start
        pha
        lda r1H
        pha
        lda fileHeader + O_GHST_ADDR
        sta daStart
        lda fileHeader + O_GHST_ADDR + 1
        sta daStart+1
        sec
        lda fileHeader + O_GHEND_ADDR
        sbc daStart
        sta daLength
        lda fileHeader + O_GHEND_ADDR + 1
        sbc daStart+1
        sta daLength+1
        ldy #REU_STASH
        jsr SwapArea
        jsr SaveState
        ldy #REU_STASH
        jsr SwapState
        pla
        sta r1H
        pla
        sta r1L
        pla                     ; return address of the caller
        sta daPC
        pla
        sta daPC+1
        tsx
        stx daSP
        lda daStart
        sta r7L
        lda daStart+1
        sta r7H
        lda #$FF
        sta r2L
        sta r2H
        jsr ReadFile
        txa
        bne RstrAppl
        jsr UseSystemFont
        jsr InitEnv
        lda loadR10
        sta r10L
        lda fileHeader + O_GHST_VEC
        ldx fileHeader + O_GHST_VEC + 1
        jmp MainLoopCall
@end:   rts

; RstrAppl: back from a desk accessory to the application, as it was
; before LdDeskAcc (X = 0 to the caller). Does not return.
RstrAppl:
        ldy #REU_FETCH
        jsr SwapArea
        ldy #REU_FETCH
        jsr SwapState
        jsr RestoreState
        ldx daSP
        txs
        lda daPC+1
        pha
        lda daPC
        pha
        ldx #0
        rts

; SwapArea / SwapState: Y = REU command; the accessory's area / the
; saved kernal state between memory and the same addresses in DA_BANK.
SwapArea:
        lda daStart
        sta r0L
        lda daStart+1
        sta r0H
        lda daLength
        sta r2L
        lda daLength+1
        sta r2H
        jmp Swap
SwapState:
        lda #<dlgBoxRamBuf
        sta r0L
        lda #>dlgBoxRamBuf
        sta r0H
        lda #<TOT_SRAM_SAVED
        sta r2L
        lda #>TOT_SRAM_SAVED
        sta r2H
Swap:   lda r0L
        sta r1L
        lda r0H
        sta r1H
        lda #DA_BANK
        sta r3L
        jmp SysRAMOp

        .segment "KCODE"

; InitMachine: hardware and GEOS variables to the warm-start state (VIC,
; CIAs, keyboard, vectors, environment; mouse off until the application
; starts it). Destroys A, X, Y, r0-r2.
InitMachine:
        lda #RAM_IO
        sta CPU_PORT
        lda #$7F                ; no CIA interrupts
        sta cia1Icr
        sta cia2Icr
        lda cia1Icr
        lda cia2Icr
        lda cia2DdrA            ; VIC-II bank 2
        ora #$03
        sta cia2DdrA
        lda cia2PortA
        and #$FC
        ora #$01
        sta cia2PortA
        lda #$3B                ; bitmap mode, raster IRQ in the lower border
        sta vicCtrl1
        lda #$08
        sta vicCtrl2
        lda #$38
        sta vicMemPtr
        lda #IRQ_LINE
        sta vicRaster
        lda #$01
        sta vicIrqMask
        sta vicIrq
        lda #0
        sta vicSprMulti
        sta $D017
        sta $D01D
        sta $D01B               ; sprite priority
        ldx #$10                ; sprite positions and their x bit 8
@spr:   sta $D000,x
        dex
        bpl @spr
        lda #$01                ; only sprite 0 (the mouse pointer) on, as
        sta vicSprEnable        ; GEOS 2.0's VIC table (mist64/geos
                                ; kernal/hw1a.s, behaviour only): geoWrite
                                ; left its sprite 6 over the deskTop
        lda #<IrqEntry
        sta $FFFE
        lda #>IrqEntry
        sta $FFFF
        lda #<NmiEntry
        sta $FFFA
        lda #>NmiEntry
        sta $FFFB
        jsr TodMode
        lda #RAM_ALL
        sta CPU_PORT
        jsr KeyReset
        lda #0
        sta numSleep
InitEnv:
        jsr InitGEOEnv
        lda #0                  ; as GEOS 2.0: the application turns the
        sta mouseOn             ; mouse on (menus, icons)
        lda #<mousePicData
        sta msePicPtr
        lda #>mousePicData
        sta msePicPtr+1
        lda #<Panic
        sta BRKVector
        lda #>Panic
        sta BRKVector+1
        ldx #7                  ; sprite n picture at SPRITE_PICS + 64 n
@spr:   txa
        clc
        adc #(SPRITE_PICS - $8000) / 64
        sta COLOR_MATRIX + $3F8,x
        dex
        bpl @spr
        rts

        .segment "CODE"

; ExtraColours: the colour bytes after the colour matrix ($8FE8-$8FF0)
; that the deskTop and the pad colour manager read, with GEOS 2.0's
; start values (measured).
ExtraColours:
        ldx #7
        lda #$BB
@pad:   sta COLOR_MATRIX + $3E8,x
        dex
        bpl @pad
        lda #$BF
        sta COLOR_MATRIX + $3F0
        rts

        .segment "CODE"

        .segment "DATA"

panicText:
        .byte BOLDON, "System error near $"
panicAddr:
        .byte "xxxx", 0

        .segment "CODE"

; Sleep: r0 = frames. Returns to the caller's caller now; the caller
; continues after its jsr Sleep from MainLoop when the time is up (at most
; MAX_SLEEP at once). Destroys A, X, Y.
Sleep:  php
        pla
        tay
        sei
        ldx numSleep
        lda r0L
        sta sleepLo,x
        lda r0H
        sta sleepHi,x
        pla
        sta sleepRtnLo,x
        pla
        sta sleepRtnHi,x
        inc numSleep
        tya
        pha
        plp
        rts

; SleepTick (interrupt level): count the sleepers down.
SleepTick:
        ldx numSleep
        beq @end
@each:  dex
        bmi @end
        lda sleepLo,x
        ora sleepHi,x
        beq @each
        lda sleepLo,x
        bne @low
        dec sleepHi,x
@low:   dec sleepLo,x
        jmp @each
@end:   rts

; WakeSleepers (MainLoop): continue every sleeper whose time is up.
WakeSleepers:
        ldx numSleep
@each:  dex
        bmi @end
        lda sleepLo,x
        ora sleepHi,x
        bne @each
        lda sleepRtnLo,x        ; the jsr's return address + 1
        clc
        adc #1
        sta r0L
        lda sleepRtnHi,x
        adc #0
        sta r0H
        txa
        pha
        php                     ; remove the entry
        sei
@close: inx
        cpx numSleep
        beq @closed
        lda sleepLo,x
        sta sleepLo-1,x
        lda sleepHi,x
        sta sleepHi-1,x
        lda sleepRtnLo,x
        sta sleepRtnLo-1,x
        lda sleepRtnHi,x
        sta sleepRtnHi-1,x
        jmp @close
@closed:
        dec numSleep
        plp
        jsr @call
        pla
        tax
        jmp @each
@call:  jmp (r0)
@end:   rts

; --- Overlay module 0 stubs (src/kernal/overlay.s) -----------------------

        .segment "CODE"

EnterDeskTop:
        jsr OvlCall
        .byte 0, 0
FirstInit:
        jsr OvlCall
        .byte 0, 3
CRC:    jsr OvlCall
        .byte 0, 9

; Panic (BRKVector): the BRK address + 2 on the stack (taken here, before
; the overlay call adds its own frame); the message is in the overlay.
Panic:  pla
        sec
        sbc #2
        sta r0L
        pla
        sbc #0
        sta r0H
        jsr OvlCall
        .byte 0, 6

; --- Overlay module 0: run in the slot at $9D80 ---------------------------

        .segment "OVL0"

        jmp OvEnterDeskTop      ; entry 0
        jmp OvFirstInit         ; entry 3
        jmp PanicMsg            ; entry 6
        jmp OvCRC               ; entry 9

; FirstInit: InitMachine plus the cold-start colours. Destroys A, X, Y,
; r0-r2. (The 1351 driver does not use the mouse speed variables.)
OvFirstInit:
        sei
        cld
        jsr InitMachine
        lda #<EnterDeskTop
        sta EnterDeskTopVec+1
        lda #>EnterDeskTop
        sta EnterDeskTopVec+2
        lda progColours         ; the programs' colours (info.s: dark grey
        sta screencolors        ; on light grey unless the desktop's theme
                                ; says programs=)
        ldx #0
@col:   sta COLOR_MATRIX,x
        sta COLOR_MATRIX+$100,x
        sta COLOR_MATRIX+$200,x
        sta COLOR_MATRIX+$2E8,x
        inx
        bne @col
        jsr ExtraColours
        lda #RAM_IO
        sta CPU_PORT
        lda ptrColour           ; the pointer and the prompt in the user's
        sta vicSpr0Color        ; pointer colour (info.s; blue unless
                                ; [system] pointercolour=), border black
        sta vicSpr0Color+1
        lda #0
        sta vicBorder
        lda #RAM_ALL
        sta CPU_PORT
        rts

AutoNext:
        jsr OvlCall
        .byte 92, 3
EnterDeskTopVec = $C22C         ; the jump table entry (jmp EnterDeskTop)
FE_RUNSYS       = 22            ; (engine.inc: an application from drive E)
APP_RAM         = $0400

; EnterDeskTop: warm start and load the desktop ("DESK TOP", version 1.5
; or higher) from the current drive, else from the others; asks for it
; while none is found. Does not return.
OvEnterDeskTop:
        sei
        cld
        ldx #$FF
        txs
        jsr WriteBackNow        ; changed drives to their images first
        jsr RepairJumpTab
        jsr InitMachine
        jsr Background
        jsr RefusedMsg          ; an application refused: why (sysdrive.s)
        lda #0                  ; (the task's name: the desktop's, task.s)
        sta taskName
        jsr AutoNext            ; the cold start's auto-execs: the next one
                                ; (no return while one starts; module 92)
        bit ownDesk             ; GeoUltra's desktop (sysdrive.s ownDesk)
        bpl @old                ; from drive E (FE_RUNSYS); back only
        ldx #OWN_LEN            ; when it cannot start: then GEOS 2.0's
@name:  lda ownName,x           ; deskTop of the boot disk as a last
                                ; resort (no option any more). The name goes
        sta APP_RAM,x           ; to application memory first: this
        dex                     ; module's bytes are gone once the engine's
        bpl @name               ; modules use the slot (and the
        lda #<APP_RAM           ; application area is free here: a new
        sta r0L                 ; one is about to load)
        lda #>APP_RAM
        sta r0H
        lda #FE_RUNSYS
        jsr FileEngine
@old:   lda curDrive
        sta dtDrive
@try:   lda dtDrive             ; the current drive first, then 8-11
        jsr TryDesk
        ldy #8
@other: tya
        pha
        cmp dtDrive
        beq @next
        ldx driveType-8,y
        beq @next
        jsr TryDesk
@next:  pla
        tay
        iny
        cpy #12
        bne @other
        lda #<deskDlg
        sta r0L
        lda #>deskDlg
        sta r0H
        jsr DoDlgBox
        jmp @try

; TryDesk: A = drive. Starts the desktop on it if there is one; returns
; otherwise.
TryDesk:
        jsr SetDevice
        jsr OpenDisk
        txa
        bne @end
        sta r0L
        lda #<deskName
        sta r6L
        lda #>deskName
        sta r6H
        jsr FindFile
        txa
        bne @end
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr GetFHdrInfo
        txa
        bne @end
        lda fileHeader + O_GHFNAME + 13 ; "V1.5" or higher
        cmp #'1'
        bcc @end
        bne @load
        lda fileHeader + O_GHFNAME + 15
        cmp #'5'
        bcc @end
@load:  lda #0
        sta r0L
        jsr SaveArgs
        jmp LdApplic
@end:   rts

; Background: the screen in the desktop pattern.
Background:
        lda #2
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
        jmp Rectangle

deskName:
        .byte "DESK TOP", 0
ownName:
        .byte "GeoUltra Desktop", 0
OWN_LEN         = * - ownName - 1
deskDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word deskText1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word deskText2
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0
deskText1:
        .byte BOLDON, "Please mount a disk", 0
deskText2:
        .byte "with a desktop", 0

; PanicMsg: r0 = the address of the BRK. Shows "System error near
; $xxxx"; OK goes to the desktop.
PanicMsg:
        lda r0H
        ldx #0
        jsr Hex
        lda r0L
        jsr Hex
        lda #<panicDlg
        sta r0L
        lda #>panicDlg
        sta r0H
        jsr DoDlgBox
        jmp EnterDeskTop

Hex:    pha
        lsr
        lsr
        lsr
        lsr
        jsr @digit
        pla
        and #$0F
@digit: cmp #10
        bcc @num
        adc #'A' - '0' - 10 - 1
@num:   adc #'0'
        sta panicAddr,x
        inx
        rts

panicDlg:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word panicText
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0

; CRC: CRC-16 (polynomial $1021, start $FFFF, high bit first) of r1 bytes
; from r0 in r2. Destroys A, Y, r0, r1, r3L.
OvCRC:  ldy #$FF
        sty r2L
        sty r2H
        iny
@byte:  lda #$80
        sta r3L
@bit:   asl r2L                 ; feedback = old top bit xor data bit
        rol r2H
        lda (r0),y
        and r3L
        bcc @fb
        eor r3L
@fb:    beq @next
        lda r2L
        eor #$21
        sta r2L
        lda r2H
        eor #$10
        sta r2H
@next:  lsr r3L
        bcc @bit
        iny
        bne @count
        inc r0H
@count: ldx #r1
        jsr Ddec
        bne @byte
        rts
