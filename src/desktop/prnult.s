; GeoUltra Desktop: the Ultimate's printer set up for the printer chosen
; (overlay 6, ovl.s; docs/DESIGN.md "Printing", the user's requests of
; 2026-11-16). When PrntFilename is GU Epson FX-80 or GU Commodore MPS,
; the Ultimate gets, in its memory only (its saved settings untouched):
; the SoftIEC drive on (firmware 3.15a writes printer pages only then),
; the IEC printer on at bus 4, the emulation that matches the driver,
; and the pages' file name in GeoUltra's print folder, next to GU PDF's
; files: home + "print/epson" or "print/mps" (the firmware adds -001.png
; and so on: its "Output file" is a name, not a folder). The output type
; stays as the user set it. The print folder is made when missing.
; As the kernal's ApplyCfg (mount.s): the lines written to
; /Temp/uci_config.cfg, then UCI control $50 loads that file; here
; through FE_UCI, five raw commands. Without an Ultimate (VICE) the calls
; fail and nothing changes. Called at the desktop's start (side.s,
; SideLoad) and after a printer driver was chosen (open.s). Own code.

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
@found: stx which
        lda #<home              ; the home folder ("/USB0/GEOULTRA/")
        sta r1L
        lda #>home
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        ldx #4                  ; the print folder made (there already:
        jsr AddFolder           ; an error, not minded)
        lda #0
        sta cmd2,x
        lda #<(cmd2 + 4)
        sta r0L
        lda #>(cmd2 + 4)
        sta r0H
        lda #0
        sta r2L
        lda #FE_MKDIR
        jsr FileEngine
        ldy which               ; the second write: the emulation's line,
        ldx #4                  ; "Output file=", the folder, the name
        lda EmuLo,y
        pha
        lda EmuHi,y
        tay
        pla
        jsr AddText
        lda #<OutText
        ldy #>OutText
        jsr AddText
        jsr AddFolder
        lda #'/'
        sta cmd2,x
        inx
        ldy which
        lda FileLo,y
        pha
        lda FileHi,y
        tay
        pla
        jsr AddText
        lda #10
        sta cmd2,x
        inx
        stx len
        lda #<OpenCmd           ; the file opened, both parts written
        ldy #>OpenCmd
        ldx #OPEN_LEN
        jsr Uci
        jsr WrHead
        lda #<cmd
        ldy #>cmd
        ldx #CFG_HEAD
        jsr Uci
        jsr WrHead
        lda #<cmd2
        ldy #>cmd2
        ldx len
        jsr Uci
        lda #<CloseCmd          ; closed, loaded
        ldy #>CloseCmd
        ldx #2
        jsr Uci
        lda #<LoadCmd
        ldy #>LoadCmd
        ldx #2
; Uci: the command at A/Y, X bytes long, through FE_UCI; no reply
; wanted, errors left (no Ultimate: nothing changes).
Uci:    sta r0L
        sty r0H
        stx r1L
        lda #0
        sta r2L
        sta r2H
        sta r3L
        sta r3H
        lda #FE_UCI
        jmp FileEngine

; WrHead: DOS_WRITE's four bytes in front of cmd and cmd2. Destroys A, Y.
WrHead: ldy #3
:       lda WriteCmd,y
        sta cmd,y
        sta cmd2,y
        dey
        bpl :-
        rts

; AddFolder: the home folder's path and "print" to cmd2 at X; X after
; them. Destroys A, Y, r4.
AddFolder:
        lda #<home
        ldy #>home
        jsr AddText
        lda #<Folder
        ldy #>Folder
; AddText: the zero-ended text at A/Y to cmd2 at X (not its zero); X
; after it. Destroys A, Y, r4.
AddText:
        sta r4L
        sty r4H
        ldy #0
:       lda (r4),y
        beq :+
        sta cmd2,x
        inx
        iny
        bne :-
:       rts

OpenCmd:        .byte T_DOS, DOS_OPEN, O_WRITE_NEW, "/Temp/uci_config.cfg"
OPEN_LEN        = * - OpenCmd
CloseCmd:       .byte T_DOS, DOS_CLOSE
LoadCmd:        .byte T_CTRL, CTRL_LOAD_CFG
WriteCmd:       .byte T_DOS, DOS_WRITE, 0, 0
NameLo:         .byte <NEpson, <NMps
NameHi:         .byte >NEpson, >NMps
EmuLo:          .byte <EEpson, <EMps
EmuHi:          .byte >EEpson, >EMps
FileLo:         .byte <FEpson, <FMps
FileHi:         .byte >FEpson, >FMps
NEpson:         .byte "GU Epson FX-80", 0
NMps:           .byte "GU Commodore MPS", 0
EEpson:         .byte "Emulation=Epson FX-80/JX-80", 10, 0
EMps:           .byte "Emulation=Commodore MPS", 10, 0
FEpson:         .byte "epson", 0
FMps:           .byte "mps", 0
Folder:         .byte "print", 0
OutText:        .byte "Output file=", 0
home:           .res 32                 ; FE_HOME's path
which:          .byte 0
len:            .byte 0
cmd:            .byte 0, 0, 0, 0        ; first write: the fixed lines
                .byte "[SoftIEC Drive Settings]", 10, "IEC Drive=Enabled", 10
                .byte "[Printer Settings]", 10, "IEC printer=Enabled", 10, "Bus ID=4", 10
CFG_HEAD        = * - cmd
cmd2:           .res 4 + 28 + 12 + 32 + 5 + 7 + 1 ; second: emulation, output
CMD2_LEN        = * - cmd2
        .assert CFG_HEAD <= 128 && CMD2_LEN <= 128, error, "prnult.s: FE_UCI takes 128 bytes"
