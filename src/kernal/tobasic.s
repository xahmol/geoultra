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
        .import EnterDeskTop

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

        .segment "KCODE"

; ToBASIC: r0 = command (NULL-terminated, at most 40 characters), r5 =
; directory entry of a PRG file to load at r7 ($0000: no file; r7 is then
; the end of the BASIC program in memory, $0803 for none). Does not return.
ToBASIC:
        jsr HibSuspend          ; drives written back, the session saved
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
