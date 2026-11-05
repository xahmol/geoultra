; gush: starting programs (docs/GUSH.md, "Starting programs"). A word
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
        .export StartProgram, prog
        .import VarFind, varName

GetFile         = $C208         ; GEOS jump table
StashRAM        = $C2C8
FetchRAM        = $C2CB
HIGH_BANK       = 3             ; (1: history, 2: cp -r, tree.s)
FindFile        = $C20B
ST_LD_DATA      = $80
NO_DOC          = $FC           ; gush's own errors (cmds.s ErrCodes)
ONE_DOC         = $FD
OTHER_FOLDER    = $FE
FI_KIND         = 0
FI_GTYPE        = 3
K_GEOS          = 3
K_CBM           = 4
K_UFILE         = 5
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
        bcc Found
        rts
@name:  sty wordLen             ; (its length)
        jsr Try                 ; the current directory
        bcc Found
        cpx #FILE_NOT_FOUND
        bne @end
        lda wordLen             ; longer than a name: on no drive's root
        cmp #FE_NAME_MAX_LONG + 1
        bcs @end
        lda #'a'                ; then "/a/NAME" .. "/d/NAME"
        sta drive
@drive: jsr Build
        jsr Try
        bcc Found
        cpx #FILE_NOT_FOUND
        bne @end
        inc drive
        lda drive
        cmp #'d' + 1
        bcc @drive
        jsr Path                ; then along PATH
        bcc Found
@end:   ldy #$FF                ; (about the program)
        rts

; Try: the path at r0 a program? C clear (r0 kept in prog); else C set,
; X = FILE_NOT_FOUND or STRUCT_MISMAT (there, but no program).
Try:    lda r0L
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
        beq @no
        cmp #K_UFILE
        beq @no
        ldx #STRUCT_MISMAT
        cmp #K_GEOS
        bne @no
        lda info + FI_GTYPE
        cmp #APPLICATION
        beq @yes
        cmp #DESK_ACC
        bne @no
@yes:   clc
        rts
@none:  ldx #FILE_NOT_FOUND     ; (any error: not there)
@no:    sec
        rts

; Found: the document's folder current (Doc), then the program's
; (FE_SELECT); GetFile by its short name.
Found:  jsr Doc
        bcc :+
        ldy #1                  ; (about the document)
        rts
:       lda prog
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

info:           .res 16
pathBuf:        .res PATH_BUF
short:          .res 17
docShort:       .res 17
path:           .res 3 + FE_NAME_MAX_LONG + 1
