; GeoUltra Desktop: the Ultimate's printer set up for the printer chosen
; (overlay 6, ovl.s; docs/DESIGN.md "Printing", the user's request of
; 2026-11-16). When PrntFilename is GU Epson FX-80 or GU Commodore MPS,
; the Ultimate gets, in its memory only (its saved settings untouched):
; the SoftIEC drive on (firmware 3.15a writes printer pages only then),
; the IEC printer on at bus 4, and the emulation that matches the driver.
; As the kernal's ApplyCfg (mount.s): the lines written to
; /Temp/uci_config.cfg, then UCI control $50 loads that file; here
; through FE_UCI, four raw commands. Output type and file stay as the
; user set them. Without an Ultimate (VICE) the calls fail and nothing
; changes. Called at the desktop's start (side.s, SideLoad) and after a
; printer driver was chosen (open.s). Own code.

        .include "geos.inc"
        .include "desktop.inc"

        .import FileEngine
        .export Ov_PrnUlt

FE_UCI          = 30            ; (FILE_ENGINE.md: a raw Ultimate command)
T_DOS           = $01           ; UCI targets and commands (mount.s)
T_CTRL          = $04
DOS_OPEN        = $02
DOS_CLOSE       = $03
DOS_WRITE       = $05
O_WRITE_NEW     = $0A           ; write, create always
CTRL_LOAD_CFG   = $50           ; load /Temp/uci_config.cfg

        .segment "OV6"

Ov_PrnUlt = PrnUlt

; PrnUlt: see above. Destroys A, X, Y, r0-r4.
PrnUlt: ldx #0                  ; which: 0 Epson, 1 MPS, else none
@drv:   lda NameLo,x
        sta r0L
        lda NameHi,x
        sta r0H
        ldy #0
:       lda (r0),y
        cmp PrntFilename,y
        bne @other
        iny
        cmp #0
        bne :-
        beq @found              ; (always)
@other: inx
        cpx #2
        bcc @drv
        rts
@found: lda EmuLo,x             ; the emulation's line after the rest
        sta r0L
        lda EmuHi,x
        sta r0H
        ldy #0
        ldx #CFG_HEAD
:       lda (r0),y
        sta cmd,x
        beq :+
        inx
        iny
        bne :-
:       stx len                 ; (the text from cmd + 4: its length + 4)
        lda #<OpenCmd           ; the file opened
        ldx #OPEN_LEN
        jsr Uci
        lda #T_DOS              ; the lines written
        sta cmd
        lda #DOS_WRITE
        sta cmd+1
        lda #0
        sta cmd+2
        sta cmd+3
        lda #<cmd
        ldx len
        jsr Uci
        lda #<CloseCmd          ; closed, loaded
        ldx #2
        jsr Uci
        lda #<LoadCmd
        ldx #2
; Uci: the command at A (this overlay's page), X bytes long, through
; FE_UCI; no reply wanted, errors left (no Ultimate: nothing changes).
Uci:    sta r0L
        lda #>cmd               ; (all commands in one page: asserted)
        sta r0H
        stx r1L
        lda #0
        sta r2L
        sta r2H
        sta r3L
        sta r3H
        lda #FE_UCI
        jmp FileEngine

OpenCmd:        .byte T_DOS, DOS_OPEN, O_WRITE_NEW, "/Temp/uci_config.cfg"
OPEN_LEN        = * - OpenCmd
CloseCmd:       .byte T_DOS, DOS_CLOSE
LoadCmd:        .byte T_CTRL, CTRL_LOAD_CFG
NameLo:         .byte <NEpson, <NMps
NameHi:         .byte >NEpson, >NMps
EmuLo:          .byte <EEpson, <EMps
EmuHi:          .byte >EEpson, >EMps
NEpson:         .byte "GU Epson FX-80", 0
NMps:           .byte "GU Commodore MPS", 0
EEpson:         .byte "Emulation=Epson FX-80/JX-80", 10, 0
EMps:           .byte "Emulation=Commodore MPS", 10, 0
cmd:            .byte 0, 0, 0, 0
                .byte "[SoftIEC Drive Settings]", 10, "IEC Drive=Enabled", 10
                .byte "[Printer Settings]", 10, "IEC printer=Enabled", 10, "Bus ID=4", 10
CFG_HEAD        = * - cmd
                .res 32                 ; the emulation's line
len:            .byte 0
        .assert >OpenCmd = >cmd && >CloseCmd = >cmd && >LoadCmd = >cmd, error, "prnult.s: the commands in one page"
        .assert CFG_HEAD + 32 <= 128, error, "prnult.s: FE_UCI takes 128 bytes"
