; ToBASIC: leave GEOS for Commodore BASIC, optionally loading a PRG file
; and typing a command. Written from the HG2G2022 description; behaviour
; details (the command's letters as screen codes, the file loaded with
; its load address bytes kept, the C64 Kernal set-up, the command put on
; the screen and RETURN in the keyboard queue a few CIA 2 NMIs after
; BASIC's start, RESTORE returning to GEOS) follow the reassembled GEOS
; 2.0 kernal, mist64/geos kernal/tobasic/tobasic1.s and tobasic2.s, read
; as behaviour reference only. Own code. Runs from $C000-$CFFF (KCODE),
; which stays RAM while the BASIC and Kernal ROMs are in.

        .include "geos.inc"
        .include "hw.inc"

        .export ToBASIC
        .import ReadFile, BootGEOS, sysFlgCopy, basicBuf, HibSuspend, hibResumed
        .import EnterDeskTop, DoDlgBox, SysRAMOp, OvlCall, SetDevice, FindFile

IOINIT          = $FDA3         ; C64 Kernal: CIAs
RESTOR          = $FD15         ; Kernal vectors
CINT            = $FF5B         ; screen editor and VIC
basicStart      = $0800
nmiVector       = $0318
vartab          = $2D           ; BASIC: end of the program
pnt             = $D1           ; screen editor: current line
pntr            = $D3           ; cursor column
user            = $F3           ; colour line
ndx             = $C6           ; keys in the keyboard queue
keyd            = $0277         ; keyboard queue
NMI_WAIT        = 6

; In the information block ($C000), which BASIC programs leave alone
basicCmd        = basicBuf      ; 40 bytes
saveStart       = basicBuf + 40 ; $0800-$0802 (BASIC's start clears them)
saveVartab      = basicBuf + 43
nmiCount        = basicBuf + 45
                                ; +46-+51: module 55's (below)
basicAddr       = basicBuf + 52 ; a staged program: r0-r3L of the DMA
basicFrom       = basicBuf + 54 ; that fetches it (in this order: where,
basicLen        = basicBuf + 56 ; from, how many, the bank); basicLen 0:
basicBank       = basicBuf + 58 ; none (BASIC_BUF_LEN in info.s: 59)

        .segment "KCODE"

; ToBASIC: r0 = command (NULL-terminated, at most 40 characters), r5 =
; directory entry of a PRG file to load at r7 ($0000: no file; r7 is then
; the end of the BASIC program in memory, $0803 for none). Does not return.
ToBASIC:
        jsr BasicLoad           ; LOAD "name",8 from a GeoUltra drive; a
        bcc @go                 ; boot file refused (module 55, below)
        jsr DoDlgBox
        jmp EnterDeskTop
@go:    jsr HibSuspend          ; drives written back, the session saved
        lda hibResumed          ; that session resumed: back to the deskTop
        beq @toBasic            ; rather than into BASIC
        jmp EnterDeskTop
@toBasic:
        ldy #40                 ; the command, 40 characters (the last
@cmd:   dey                     ; first), letters as screen codes 1-26
        lda (r0),y              ; (and #$3F)
        cmp #'A'
        bcc @keep
        cmp #'Z' + 1
        bcs @keep
        and #$3F
@keep:  sta basicCmd,y
        tya
        bne @cmd
        lda r5H                 ; (Y = 0 from here)
        beq @basic
        lda #0                  ; an empty BASIC start page
@clear: sta basicStart,y
        iny
        bne @clear
        sec                     ; the file's load address lands 2 bytes
        lda r7L                 ; before r7; keep what was there
        sbc #2
        sta r7L
        sta r0L
        lda r7H
        sbc #0
        sta r7H
        sta r0H
        lda (r7),y
        pha
        iny
        lda (r7),y
        pha
        ldy #OFF_DE_TR_SC
        lda (r5),y
        sta r1L
        iny
        lda (r5),y
        sta r1H
        lda #$FF
        sta r2L
        sta r2H
        jsr ReadFile
        ldy #1
        pla
        sta (r0),y
        dey
        pla
        sta (r0),y
@basic: lda sysRAMFlg           ; BootGEOS reboots from the cartridge and
        ora #$20                ; the REU: programs need no boot disk
        sta sysFlgCopy
        sei
        lda basicLen            ; a program staged in the REU: into place
        ora basicLen+1          ; now (GEOS's memory up to $9FFF no
        beq @nofile             ; longer needed; interrupts off)
        ldx #6
@par:   lda basicAddr,x
        sta r0L,x
        dex
        bpl @par
        ldy #REU_FETCH
        jsr SysRAMOp
        lda #0                  ; BASIC's 0 before the program ($0800 is
        sta basicStart          ; kept over its start, below)
@nofile:
        ldy #2
@save:  lda basicStart,y
        sta saveStart,y
        dey
        bpl @save
        lda r7L
        sta saveVartab
        lda r7H
        sta saveVartab+1
        lda #ROM_ALL
        sta CPU_PORT
        ldx #$FF
        txs
        lda #0
        sta vicCtrl2
        jsr IOINIT
        ldx curDevice
        lda #0
        tay
@zp:    sta $0002,y             ; zero page, $0200-$03FF
        sta $0200,y
        sta $0300,y
        iny
        bne @zp
        stx curDevice
        lda #$A0                ; memory top, tape buffer, bottom, screen
        sta $0284
        lda #<$03C3
        sta $B2
        lda #>$03C3
        sta $B3
        lda #$08
        sta $0282
        lda #$04
        sta $0288
        jsr RESTOR
        jsr CINT
        lda #<BasicNmi
        sta nmiVector
        lda #>BasicNmi
        sta nmiVector+1
        lda #NMI_WAIT
        sta nmiCount
        lda cia2Icr             ; CIA 2 timer A: an NMI every 65536 cycles
        lda #$FF
        sta $DD04
        sta $DD05
        lda #$81
        sta cia2Icr
        lda #$01
        sta $DD0E
        jmp ($A000)             ; BASIC cold start

; BasicNmi: after NMI_WAIT NMIs (BASIC has started): NMIs off, RESTORE to
; GEOS, the program end back, the command on the screen and RETURN.
BasicNmi:
        pha
        tya
        pha
        lda cia2Icr
        dec nmiCount
        bne @end
        lda #$7F
        sta cia2Icr
        lda #<BootGEOS
        sta nmiVector
        lda #>BootGEOS
        sta nmiVector+1
        ldy #2
@start: lda saveStart,y
        sta basicStart,y
        dey
        bpl @start
        lda saveVartab
        sta vartab
        lda saveVartab+1
        sta vartab+1
        iny
@print: lda basicCmd,y
        beq @typed
        sta (pnt),y
        lda #14                 ; light blue
        sta (user),y
        iny
        bne @print
@typed: tya
        beq @end
        lda #40
        sta pntr
        lda #1
        sta ndx
        lda #CR
        sta keyd
@end:   pla
        tay
        pla
        rti

; --- A program from a GeoUltra drive (module 55, entry 6) ----------------
; GEOS 2.0's deskTop starts a BASIC file itself only when it loads at
; $0801 and has fewer than 121 blocks (r5 = its entry, ReadFile below);
; any other it starts with r5 = 0 and the command LOAD "name",8[,1]...,
; which BASIC would send to the IEC bus, where GeoUltra's drives are not
; (found in the deskTop's code, read for behaviour only, 2026-11-26).
; OvBasicLoad reads such a file from the GeoUltra drive into REU bank
; FE_UBANK (the file engine's listing bank, free while no listing is
; open); ToBASIC fetches it into place once GEOS is out of the way, so
; programs up to $9FFF fit. And the boot files of GEOS 2.0, Wheels,
; MegaPatch3 and GDOS64 are refused in both ways: they would start that
; system over GeoUltra (RBOOT from the REU, where GeoUltra's data is).
; The user's decision 2026-11-26 (docs/design/DESIGN.md, "Scope of 1.0").

        .segment "KCODE"

; Stubs, each reached by its own jsr (overlay.s): BasicLoad (module 128,
; ToBASIC's start), GuardBoot (module 129), StageFile (module 130).
BasicLoad:
        jsr OvlCall
        .byte 128, 0
GuardBoot:
        jsr OvlCall
        .byte 129, 0
StageFile:
        jsr OvlCall
        .byte 130, 0

; State in basicBuf (the information block: outside the modules, whose
; own bytes do not survive their calls to each other and FindFile's).
bName           = basicBuf      ; the file's name, 0 at its end (17)
bAbs            = basicBuf + 46 ; ",1": load at the file's own address
bRest           = basicBuf + 47 ; what follows ":" in the command (word)
bCount          = basicBuf + 49 ; a block's bytes
bDev            = basicBuf + 50 ; the command's device (not yet SetDevice)
NAME_MAX        = 16

        .segment "OVL128"               ; overlay module 128: ToBASIC's
                                        ; LOAD command read
        jmp OvBasicLoad         ; entry 0

; OvBasicLoad (ToBASIC's start): r0 = command, r5 = entry or 0, r7.
; Returns C set when refused: r0 = a dialog (in fileHeader) to show;
; C clear: r0, r5, r7 for ToBASIC, and basicLen non-zero when a file is
; staged for basicAddr. Destroys A, X, Y, r1-r4, r6.
OvBasicLoad:
        lda #0
        sta basicLen
        sta basicLen+1
        lda r5H
        beq @cmd
        ldy #3                  ; the entry's name, $A0 its padding
        ldx #0
@ename: lda (r5),y
        cmp #$A0
        beq @eend
        sta bName,x
        iny
        inx
        cpx #NAME_MAX
        bne @ename
@eend:  lda #0
        sta bName,x
        jmp GuardBoot
@cmd:   jsr Parse
        bcc @no
        jsr GuardBoot
        bcs @end                ; (refused: C set)
        lda bDev                ; a GeoUltra drive with the file?
        cmp #8
        bcc @no
        cmp #12
        bcs @no
        tax
        lda driveType-8,x
        beq @no
        txa
        jsr SetDevice
        txa
        bne @no
        lda #<bName
        sta r6L
        lda #>bName
        sta r6H
        jsr FindFile
        txa
        bne @no
        jmp StageFile           ; (module 130)
@no:    clc
@end:   rts

; Parse: r0 = LOAD "name",dev[,1][:rest]. C set when it is one: the name
; in bName, the device in bDev, bAbs, bRest
; (0: nothing after it). C clear otherwise (nothing changed but bName).
Parse:  ldy #0
        jsr Blanks
        ldx #0
@load:  lda (r0),y
        cmp LoadWord,x
        bne @no
        iny
        inx
        cpx #4
        bne @load
        jsr Blanks
        cmp #'"'
        bne @no
        iny
        ldx #0
@name:  lda (r0),y
        beq @no
        iny
        cmp #'"'
        beq @named
        sta bName,x
        inx
        cpx #NAME_MAX + 1
        bne @name
@no:    clc
        rts
@named: lda #0
        sta bName,x
        sta bAbs
        sta bRest+1
        jsr Comma
        bne @no
        jsr Digit               ; 8, 9, or 10, 11
        bcs @no
        cmp #1
        bne @dev
        lda (r0),y
        sec
        sbc #'0'
        cmp #2
        bcs @no
        iny
        adc #10
@dev:   sta bDev
        jsr Comma
        bne @rest
        jsr Digit
        bcs @no
        sta bAbs                ; (",0": as without)
@rest:  jsr Blanks
        beq @done
        cmp #':'
        bne @no
        iny
        tya
        clc
        adc r0L
        sta bRest
        lda r0H
        adc #0
        sta bRest+1
@done:  sec
        rts

; Blanks: Y past spaces; A the character there, Z set at the end.
Blanks: lda (r0),y
        cmp #' '
        bne @end
        iny
        bne Blanks
@end:   cmp #0
        rts

; Comma: Z set (and Y past it) when a comma follows (spaces allowed).
Comma:  jsr Blanks
        cmp #','
        bne @end
        iny
        jsr Blanks
        lda #','
        cmp #','
@end:   rts

; Digit: A = the digit at Y (Y past it), C clear; C set when none.
Digit:  lda (r0),y
        sec
        sbc #'0'
        cmp #10
        bcs @end
        iny
@end:   rts

LoadWord:       .byte "LOAD"

        .segment "OVL129"               ; overlay module 129: the boot
                                        ; files of other GEOS systems
        jmp OvGuardBoot         ; entry 0

; Guard: C set and r0 = the refusal dialog when bName is a boot file of
; GEOS 2.0, Wheels, MegaPatch3 or GDOS64 (the names on their disks;
; GeoUltra's own); C clear otherwise. The list: names, 0 after each; a
; name ending in "." matches all names starting with it.
OvGuardBoot:
        ldx #0
@next:  ldy #0
@char:  lda BootNames,x
        beq @whole
        cmp bName,y
        bne @skip
        inx
        iny
        cmp #'.'                ; ("GD." and the like: a prefix)
        bne @char
        lda BootNames,x
        beq @hit
        bne @char
@whole: lda bName,y
        beq @hit
@skip:  lda BootNames,x         ; to the next name
        inx
        tay
        bne @skip
        lda BootNames,x
        bne @next
        clc
        rts
@hit:   ldy #DlgEnd - Dlg - 1   ; the dialog into fileHeader
@copy:  lda Dlg,y
        sta fileHeader,y
        dey
        bpl @copy
        lda #<fileHeader
        sta r0L
        lda #>fileHeader
        sta r0H
        sec
        rts

BootNames:
        .byte "GEOS", 0, "GEOBOOT", 0, "RBOOT", 0, "GEOS BOOT", 0
        .byte "TURBOBOOT", 0, "GEOS128", 0, "GEOBOOT128", 0
        .byte "128 RBOOT", 0, "STARTER", 0, "SYSTEM1", 0
        .byte "STARTER 128", 0, "128SYSTEM1", 0, "TURBO41", 0
        .byte "GEOS64", 0, "GEOS64.", 0, "RBOOT64", 0, "RBOOT64.", 0
        .byte "GD", 0, "GD.", 0
        .byte 0

Dlg:    .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word fileHeader + (Txt1 - Dlg)
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word fileHeader + (Txt2 - Dlg)
        .byte OK, DBI_X_0, DBI_Y_2
        .byte 0
Txt1:   .byte "This starts another GEOS system,", 0
Txt2:   .byte "so GeoUltra does not run it.", 0
DlgEnd:

        .segment "OVL130"               ; overlay module 130: a program
                                        ; staged in the REU for ToBASIC
        .scope Mod130
        .include "engine.inc"   ; (FE_UBANK)

GetBlock        = $C1E4         ; GEOS jump table
TOP             = $A000         ; BASIC's RAM ends below it
LOW             = $0801         ; and starts here

        jmp OvStageFile         ; entry 0

; OvStageFile (module 130, entry 0): dirEntryBuf's file staged (Stage)
; and ToBASIC's registers set: r5H 0 (no ReadFile), r7 the program's
; end, r0 the command (Command). C clear either way (not staged: as
; before, the command goes to BASIC unchanged).
OvStageFile:
        jsr Stage
        bcc @no
        lda #0
        sta r5H
        clc
        lda basicAddr
        adc basicLen
        sta r7L
        lda basicAddr+1
        adc basicLen+1
        sta r7H
        jsr Command
@no:    clc
        rts

; Stage: dirEntryBuf's file into bank FE_UBANK from 0 (its load address
; first). C set when it fits: basicAddr (bAbs: its own, else $0801) and
; basicLen (the bytes after the address) set; C clear otherwise.
Stage:  lda dirEntryBuf + OFF_DE_TR_SC
        sta r1L
        lda dirEntryBuf + OFF_DE_TR_SC + 1
        sta r1H
@block: lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        beq :+
        jmp @no
:       ldx #254                ; the bytes in this block
        lda diskBlkBuf
        bne @full
        ldx diskBlkBuf+1
        dex
@full:  stx bCount
        txa                     ; (none: nothing to stash; a length of 0
        beq @next               ; would be 64 KB to the DMA)
        lda basicLen            ; the first block: the load address
        ora basicLen+1
        bne @room
        lda #<LOW
        ldx #>LOW
        ldy bAbs
        beq :+
        lda diskBlkBuf+2
        ldx diskBlkBuf+3
:       sta basicAddr
        stx basicAddr+1
@room:  lda #<(diskBlkBuf + 2)  ; the block to the REU
        sta r0L
        lda #>(diskBlkBuf + 2)
        sta r0H
        lda basicLen
        sta r1L
        lda basicLen+1
        sta r1H
        lda bCount
        sta r2L
        lda #0
        sta r2H
        lda #FE_UBANK
        sta r3L
        ldy #REU_STASH
        jsr SysRAMOp
        clc
        lda basicLen
        adc bCount
        sta basicLen
        bcc :+
        inc basicLen+1
        beq @no                 ; (64 KB: never a program)
:
@next:  lda diskBlkBuf          ; the next block
        beq @last
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        jmp @block
@last:  sec                     ; the bytes after the address
        lda basicLen
        sbc #2
        sta basicLen
        lda basicLen+1
        sbc #0
        sta basicLen+1
        bcc @no
        lda basicAddr+1         ; from $0801 up to $A000
        cmp #>LOW
        bcc @no
        bne :+
        lda basicAddr
        cmp #<LOW
        bcc @no
:       clc
        lda basicAddr
        adc basicLen
        tax
        lda basicAddr+1
        adc basicLen+1
        bcs @no
        cmp #>TOP
        bcc @fits
        bne @no
        cpx #1                  ; (exactly $A000: the end, fits)
        bcs @no
@fits:  lda #2                  ; ToBASIC's DMA: from offset 2 of the bank
        sta basicFrom
        lda #0
        sta basicFrom+1
        lda #FE_UBANK
        sta basicBank
        sec
        rts
@no:    lda #0
        sta basicLen
        sta basicLen+1
        clc
        rts

; Command: what ToBASIC types, into basicBuf (r0 = it): what followed ":"
; in the command, else RUN after a BASIC load (without ",1").
Command:
        ldy #0
        lda bRest+1
        beq @run
        lda bRest
        sta r1L
        lda bRest+1
        sta r1H
@copy:  lda (r1),y
        sta basicBuf,y
        beq @set
        iny
        cpy #39
        bne @copy
        lda #0
        sta basicBuf,y
        beq @set
@run:   lda bAbs
        bne @none
@rcopy: lda RunWord,y
        sta basicBuf,y
        beq @set
        iny
        bne @rcopy
@none:  lda #0
        sta basicBuf
@set:   lda #<basicBuf
        sta r0L
        lda #>basicBuf
        sta r0H
        rts

RunWord:        .byte "RUN", 0

        .endscope
