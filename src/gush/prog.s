; gush: starting programs (docs/design/GUSH.md, "Starting programs"). A word
; that is no command names a GEOS application or desk accessory: by its
; path, or by name in the current directory and then in the root of each
; drive A-D (drive E, "/e/bin" in the design, when the file engine knows
; drive E). FE_SELECT makes its drive and folder current, GetFile starts
; it: an application replaces gush; a desk accessory comes back, and gush
; redraws its screen. A document after an application's name is passed
; as the deskTop passes one (ST_LD_DATA, r2 its disk's name, r3 its
; name): its drive and folder are made current first, then the
; program's; on one drive both must be in one folder (an application
; finds its document by the disk's name: geoWrite 2.1's findDocDevice,
; mist64/geowrite, read for this behaviour only). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, Status, ConRedraw, argc, argLo, argHi
        .export StartProgram, prog, RunPrg
        .import Ask
        .import VarFind, varName, HistSave

GetFile         = $C208         ; GEOS jump table
StashRAM        = $C2C8
FetchRAM        = $C2CB
HIGH_BANK       = 3             ; (1: history, 2: cp -r, tree.s)
FindFile        = $C20B
ST_LD_DATA      = $80
NO_DOC          = $FC           ; gush's own errors (cmds.s ErrCodes)
ONE_DOC         = $FD
OTHER_FOLDER    = $FE
PATH_DIR_MAX    = 80            ; a PATH folder's characters at most
PATH_BUF        = 128           ; a folder, "/", the word

        .segment "ZEROPAGE"

pathAt:         .res 2          ; Path: the PATH folder looked at
argLo0:         .res 2          ; Path: word 0

        .segment "CODE"

; StartProgram: word 0 as a program, word 1 (if any) its document. X = 0
; (a desk accessory ran), or FILE_NOT_FOUND (none), STRUCT_MISMAT (found,
; but no program), or GetFile's error, with Y = $FF; or the document's
; error with Y = 1. An application does not come back.
StartProgram:
        lda argLo               ; a "/" in it: that path only
        sta r0L
        lda argHi
        sta r0H
        ldy #$FF
@slash: iny
        lda (r0),y
        beq @name
        cmp #'/'
        bne @slash
        jsr Try                 ; (r0: the word)
        bcs :+
        jmp Found
:        rts
@name:  sty wordLen             ; (its length)
        jsr Try                 ; the current directory
        bcs :+
        jmp Found
:        cpx #FILE_NOT_FOUND
        bne @end
        lda wordLen             ; longer than a name: on no drive's root
        cmp #FE_NAME_MAX_LONG + 1
        bcs @end
        lda #'a'                ; then "/a/NAME" .. "/d/NAME"
        sta drive
@drive: jsr Build
        jsr Try
        bcs :+
        jmp Found
:        cpx #FILE_NOT_FOUND
        bne @end
        inc drive
        lda drive
        cmp #'d' + 1
        bcc @drive
        jsr Path                ; then along PATH
        bcs :+
        jmp Found
:@end:   ldy #$FF                ; (about the program)
        rts

; Try: the path at r0 a program? C clear (r0 kept in prog); else C set,
; X = FILE_NOT_FOUND, STRUCT_MISMAT (there, but no program), IS_SCRIPT
; (a plain file) or IS_MODULE (an external command: a GEOS file of class
; "gush cmd", or the name with ".cvt" added: on the Ultimate a module is
; its CVT; module.s). prog: the path found.
Try:    jsr Try1
        bcc @end
        cpx #FILE_NOT_FOUND
        bne @end
        ldy #$FF                ; NAME.cvt (a module on the Ultimate)
@cp:    iny
        cpy #PATH_BUF - 5
        bcs @no
        lda (r0),y
        sta cvtBuf,y
        bne @cp
        ldx #0                  ; (y: at the zero)
@ext:   lda Cvt,x
        sta cvtBuf,y
        iny
        inx
        cpx #5
        bne @ext
        lda #<cvtBuf
        sta r0L
        lda #>cvtBuf
        sta r0H
        jsr Try1
        bcc @no                 ; (a program named so: none)
        cpx #IS_SCRIPT          ; a plain file: a module's CVT
        bne @no
        ldx #IS_MODULE
        sec
@end:   rts
@no:    ldx #FILE_NOT_FOUND
        sec
        rts

Cvt:    .byte ".cvt", 0
GushCmd:        .byte "gush cmd"        ; (a module's class, 8 of its 12)

Try1:   lda r0L
        sta prog
        lda r0H
        sta prog+1
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        bne @none
        ldx #IS_SCRIPT          ; a plain file: a script (script.s)
        lda info + FI_KIND
        cmp #K_CBM
        bne :+
        lda info + FI_CBM       ; a PRG on a GEOS drive: run in BASIC
        and #$07                ; (RunPrg; the user, 2026-11-26)
        cmp #2
        bne @no
        ldx #IS_PRG
        bne @no                 ; (always)
:
        cmp #K_UFILE
        beq @no
        ldx #STRUCT_MISMAT
        cmp #K_GEOS
        bne @no
        lda info + FI_GTYPE
        cmp #APPL_DATA          ; class "gush cmd": an external command
        bne @prog
        ldy #7
@class: lda fileHeader + O_GHFNAME,y
        cmp GushCmd,y
        bne @no
        dey
        bpl @class
        ldx #IS_MODULE
        sec
        rts
@prog:  cmp #APPLICATION
        beq @yes
        cmp #DESK_ACC
        bne @no
@yes:   clc
        rts
@none:  ldx #FILE_NOT_FOUND     ; (any error: not there)
@no:    sec
        rts

; Found: the document's folder current (Doc), then the program's
; (FE_SELECT); GetFile by its short name. A program on drive E: no slot
; can stay E's for GetFile (the engine shows E only during a call), so an
; application starts through FE_RUNSYS by its name (FE_RUNDOC with a
; document, since 2026-11-19: GU PostScript), a desk accessory through
; GetFile by its name (GetFile falls back to drive E; it takes no
; document).
Found:  jsr Doc
        bcc :+
        ldy #1                  ; (about the document)
        rts
:       jsr OnE
        bcc @sel
        lda info + FI_GTYPE
        cmp #APPLICATION
        bne :+
        jsr HistSave            ; (its history first: gush ends)
        lda #<short
        sta r0L
        lda #>short
        sta r0H
        lda #<docShort          ; (FE_RUNDOC: r1 the document, r2 its
        sta r1L                 ; disk's name)
        lda #>docShort
        sta r1H
        ldx docDrive
        lda DiskLo-8,x
        sta r2L
        lda DiskHi-8,x
        sta r2H
        lda #FE_RUNSYS
        ldx loadOpt             ; (a document: FE_RUNDOC)
        beq @run
        lda #FE_RUNDOC
@run:   jsr FileEngine          ; (back only with an error)
        jmp @end
:       ldy #0
        jsr High
        jmp @start
@sel:   lda prog
        sta r0L
        lda prog+1
        sta r0H
        lda #<short
        sta r1L
        lda #>short
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        bne @end
        ldy #0                  ; gush's variables ($6000-$7F3F, which a
        jsr High                ; desk accessory may draw over) kept
        lda info + FI_GTYPE     ; an application ends gush: its history
        cmp #APPLICATION        ; saved (hist.s)
        bne :+
        jsr HistSave
:
        lda loadOpt             ; (before GetFile's registers: High uses
        beq @start              ; r0-r3)
        lda curDrive            ; one drive: the document in this folder?
        cmp docDrive            ; (the same file: its first block)
        bne @pass
        jsr FindDoc
        ldx #OTHER_FOLDER
        bcs @other
        lda dirEntryBuf + 1
        cmp docTS
        bne @other
        lda dirEntryBuf + 2
        cmp docTS + 1
        beq @pass
@other: ldy #1
        rts
@pass:  ldx docDrive            ; r2: its disk's name, r3: its name
        lda DiskLo-8,x
        sta r2L
        lda DiskHi-8,x
        sta r2H
        lda #<docShort
        sta r3L
        lda #>docShort
        sta r3H
@start: lda #<short
        sta r6L
        lda #>short
        sta r6H
        lda loadOpt             ; (ST_LD_DATA, or 0: no data file)
        sta r0L
        jsr GetFile             ; (an application: no return)
        txa
        pha
        ldy #1                  ; a desk accessory back: gush's variables
        jsr High
        jsr ConRedraw           ; a desk accessory back: the screen anew
        jsr Status
        pla
        tax
@end:   ldy #$FF
        rts

; OnE: C set when prog is on drive E ("/e/..."); then short = its last
; part (E's names are short names).
OnE:    lda prog                ; (r0: free here, Found sets it after)
        sta r0L
        lda prog+1
        sta r0H
        ldy #0
@pre:   lda (r0),y
        cmp EPrefix,y
        bne @no
        iny
        cpy #3
        bne @pre
        ldx #0                  ; the part after the last "/"
@ch:    lda (r0),y
        sta short,x
        beq @yes
        iny
        inx
        cmp #'/'
        bne :+
        ldx #0
:       cpx #17                 ; (short's size)
        bcc @ch
@no:    clc
        rts
@yes:   sec
        rts

EPrefix:        .byte "/e/"

; Doc: word 1, if there is one, the document: loadOpt ST_LD_DATA, its
; drive and folder current (FE_SELECT), its short name in docShort, its
; drive in docDrive, its first block in docTS. C set: X = the error
; (more than one word; a desk accessory, which takes none; FE_SELECT's;
; FindFile's).
Doc:    lda #0
        sta loadOpt
        lda argc
        cmp #2
        bcc @none
        ldx #ONE_DOC
        cmp #3
        bcs @no
        ldx #NO_DOC
        lda info + FI_GTYPE     ; (Try left the program's info)
        cmp #APPLICATION
        bne @no
        lda argLo+1
        sta r0L
        lda argHi+1
        sta r0H
        lda #<docShort
        sta r1L
        lda #>docShort
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        bne @no
        lda curDrive
        sta docDrive
        jsr FindDoc             ; (its first block, to know it again)
        bcs @no
        lda dirEntryBuf + 1
        sta docTS
        lda dirEntryBuf + 2
        sta docTS + 1
        lda #ST_LD_DATA
        sta loadOpt
@none:  clc
        rts
@no:    sec
        rts

; FindDoc: FindFile docShort in the current folder; C set: X its error.
FindDoc:
        lda #<docShort
        sta r6L
        lda #>docShort
        sta r6H
        jsr FindFile
        cpx #1                  ; (C set when X is not 0)
        rts

; The drives' disk names (GetFile copies r2's to dataDiskName).
DiskLo: .byte <DrACurDkNm, <DrBCurDkNm, <DrCCurDkNm, <DrDCurDkNm
DiskHi: .byte >DrACurDkNm, >DrBCurDkNm, >DrCCurDkNm, >DrDCurDkNm

; High: Y = 0: $6000-$7F3F to the application's REU (bank HIGH_BANK);
; 1: back from there. (StashRAM, FetchRAM.) Destroys A, Y, r0-r3L.
High:   lda #<$6000
        sta r0L
        sta r1L
        lda #>$6000
        sta r0H
        sta r1H
        lda #<$1F40
        sta r2L
        lda #>$1F40
        sta r2H
        lda #HIGH_BANK
        sta r3L
        tya
        bne :+
        jmp StashRAM
:       jmp FetchRAM

; Path: word 0 looked for in each folder of PATH (":" between them): C
; clear for a program (Found goes on); else C set, X = FILE_NOT_FOUND,
; IS_SCRIPT (prog: the file) or another error. Destroys A, Y.
Path:   ldy #0
@name:  lda PathName,y
        sta varName,y
        beq :+
        iny
        bne @name
:       jsr VarFind
        bcs @none
        lda r1L
        sta pathAt
        lda r1H
        sta pathAt+1
        lda argLo
        sta argLo0
        lda argHi
        sta argLo0+1
@dir:   ldy #0                  ; a folder: up to ":" or the end
        ldx #0
@ch:    lda (pathAt),y
        beq @copy
        cmp #':'
        beq @copy
        sta pathBuf,x
        inx
        iny
        cpx #PATH_DIR_MAX
        bcc @ch
@copy:  sty dirLen
        lda #'/'
        sta pathBuf,x
        inx
        ldy #0                  ; then the word
@word:  lda (argLo0),y
        sta pathBuf,x
        beq @try
        inx
        iny
        cpx #PATH_BUF - 1
        bcc @word
        lda #0
        sta pathBuf,x
@try:   lda #<pathBuf
        sta r0L
        lda #>pathBuf
        sta r0H
        jsr Try
        bcc @end
        cpx #FILE_NOT_FOUND
        bne @end
        ldy dirLen              ; the next folder, if a ":" ended this
        lda (pathAt),y
        beq @none
        iny
        tya
        clc
        adc pathAt
        sta pathAt
        bcc @dir
        inc pathAt+1
        bne @dir
@none:  ldx #FILE_NOT_FOUND
        sec
@end:   rts

PathName:       .byte "PATH", 0

; Build: path = "/" drive "/" word 0, at r0.
Build:  lda #'/'
        sta path
        sta path+2
        lda drive
        sta path+1
        lda argLo
        sta r1L
        lda argHi
        sta r1H
        ldy #0
@copy:  lda (r1),y              ; (at most FE_NAME_MAX_LONG: StartProgram
        sta path+3,y            ; checked it)
        beq @done
        iny
        bne @copy
@done:  lda #<path
        sta r0L
        lda #>path
        sta r0H
        rts

FE_NAME_MAX_LONG = 60

        .segment "DATA"

drive:          .byte 0
dirLen:         .byte 0
wordLen:        .byte 0
prog:           .word 0
loadOpt:        .byte 0
docDrive:       .byte 0
docTS:          .word 0

        .segment "BSS"

prgShort:       .res 17             ; RunPrg: the PRG's short name
prgCmd:         .res 32             ; and its LOAD command (prgrun.inc)
info:           .res 16
pathBuf:        .res PATH_BUF
cvtBuf:         .res PATH_BUF
short:          .res 17
docShort:       .res 17
path:           .res 3 + FE_NAME_MAX_LONG + 1

        .segment "CODE"

; RunPrg (StartProgram found a PRG on a GEOS drive, prog its path): run
; in BASIC, asked first ("leave GeoUltra and run NAME? (y/n/a)"; -f
; does not ask): its drive and folder current (FE_SELECT), then ToBASIC
; with LOAD "name",dev,1, which the kernal loads from the drive and
; starts (prgrun.inc). No: X = 0, back to the prompt; else X = error.
RunPrg: ldx #0
        lda #<RunQ
        ldy #>RunQ
        jsr Ask
        bcs @no
        lda prog
        sta r0L
        lda prog+1
        sta r0H
        lda #<prgShort
        sta r1L
        lda #>prgShort
        sta r1H
        lda #FE_SELECT
        jsr FileEngine
        txa
        bne @end
        lda #<prgShort
        sta r6L
        lda #>prgShort
        sta r6H
        jsr PrgCommand
        jmp ToBasic
@no:    ldx #0
@end:   rts

RunQ:   .byte "leave GeoUltra and run ", 0
ToBasic         = $C241         ; GEOS jump table

        .include "prgrun.inc"
