; gush: running a command line and the commands (docs/GUSH.md,
; "Commands"): exit, clear, echo, pwd, cd, ls here; the file commands
; in files.s. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import ConPut, ConPuts, ConNewLine, ConClear, conCol
        .import FileEngine, Status, pwdBuf, startDrive
        .import Parse, argc, argLo, argHi
        .export Run, ArgR0, PutArg, Print, Say, Fail, Decimal, num
        .import CmdCp, CmdMv, CmdRm, CmdMkdir, CmdRmdir, CmdCat, CmdMore, CmdDf
        .import StartProgram

EnterDeskTop    = $C22C         ; GEOS jump table

; Info block (docs/FILE_ENGINE.md, "Functions")
FI_KIND         = 0
FI_CBM          = 1
FI_SIZE         = 4
FI_DATE         = 8
K_ROOT          = 0
K_DRIVE         = 1
K_FOLDER        = 2
K_GEOS          = 3
K_CBM           = 4
K_UFILE         = 5
K_UDIR          = 6
END_OF_DIR      = $48

        .segment "ZEROPAGE"

str:            .res 2          ; a text being printed
pathAt:         .res 2          ; ls: the path being looked at

        .segment "CODE"

; Run: the line in lineBuf: its words (Parse), the first a command.
Run:    jsr Parse
        bcc :+
        lda #<TooMany
        ldy #>TooMany
        jmp Say
:       lda argc
        beq @end
        ldy #0                  ; the commands, one by one
@cmd:   lda Commands,y
        beq @unknown
        sty cmdAt
        lda argLo               ; word 0
        sta str
        lda argHi
        sta str+1
        ldx #0
@ch:    lda Commands,y
        cmp (str,x)             ; (X = 0)
        bne @next
        cmp #0
        beq @found
        iny
        inc str
        bne @ch
        inc str+1
        bne @ch
@next:  ldy cmdAt               ; past its name and address
@skip:  iny
        lda Commands-1,y
        bne @skip
        iny
        iny
        bne @cmd
@found: lda Commands+1,y
        sta @go+1
        lda Commands+2,y
        sta @go+2
@go:    jmp $FFFF
@unknown:
        jsr StartProgram        ; a program's name?
        txa
        beq @end
        cpx #STRUCT_MISMAT
        bne @nf
        jsr Gush                ; there, but no program
        ldx #0
        jsr PutArg
        lda #<NoProgram
        ldy #>NoProgram
        jmp Say
@nf:    cpx #FILE_NOT_FOUND
        beq @none
        ldy #$FF
        jmp Fail
@none:  jsr Gush
        ldx #0
        jsr PutArg
        lda #<NotFound
        ldy #>NotFound
        jmp Say
@end:   rts

; The commands: name, zero, address.
Commands:
        .byte "exit", 0
        .word CmdExit
        .byte "clear", 0
        .word ConClear
        .byte "echo", 0
        .word CmdEcho
        .byte "pwd", 0
        .word CmdPwd
        .byte "cd", 0
        .word CmdCd
        .byte "ls", 0
        .word CmdLs
        .byte "cp", 0
        .word CmdCp
        .byte "mv", 0
        .word CmdMv
        .byte "rm", 0
        .word CmdRm
        .byte "mkdir", 0
        .word CmdMkdir
        .byte "rmdir", 0
        .word CmdRmdir
        .byte "cat", 0
        .word CmdCat
        .byte "more", 0
        .word CmdMore
        .byte "df", 0
        .word CmdDf
        .byte "help", 0
        .word CmdHelp
        .byte 0

CmdExit:
        jmp EnterDeskTop

; help [command]: the commands, or one command's use.
CmdHelp:
        lda argc
        cmp #2
        bcs @one
        lda #<HelpAll
        ldy #>HelpAll
        jmp Say
@one:   ldx #1
        jsr ArgStr
        ldx #0                  ; the usage lines: "name text", zero
@line:  lda Usage,x
        beq @none
        stx cmdAt
        ldy #0
@cmp:   lda Usage,x
        cmp #' '
        beq @end_name
        cmp (str),y
        bne @skip
        inx
        iny
        bne @cmp
@end_name:
        lda (str),y
        bne @skip
        lda cmdAt               ; this one: printed
        clc
        adc #<Usage
        tax
        lda #>Usage
        adc #0
        tay
        txa
        jmp Say
@skip:  ldx cmdAt               ; the next line
@past:  inx
        lda Usage-1,x
        bne @past
        jmp @line
@none:  jsr Gush
        lda #<NoHelp
        ldy #>NoHelp
        jsr Print
        ldx #1
        jsr PutArg
        jmp ConNewLine

HelpAll:                        ; (lines within COLS)
        .byte "commands: cd clear cp df echo exit help ls mkdir", CR
        .byte "more mv pwd rm rmdir; a program's name starts it.", CR
        .byte "help NAME: a command's use.", 0
Usage:  .byte "cd [path]", 0
        .byte "clear", 0
        .byte "cp [-f] source... target", 0
        .byte "df [path]", 0
        .byte "echo words...", 0
        .byte "exit", 0
        .byte "help [command]", 0
        .byte "ls [-l] [path...]", 0
        .byte "mkdir [-t tracks] path...", 0
        .byte "more path...", 0
        .byte "mv [-f] source... target", 0
        .byte "pwd", 0
        .byte "rm [-f] path...", 0
        .byte "rmdir path...", 0
        .byte 0
NoHelp: .byte "no help for ", 0
        .assert * - Usage < 256, error, "help: the usage lines in one page"

; echo: the words, one space between.
CmdEcho:
        ldx #1
@word:  cpx argc
        bcs @nl
        cpx #1
        beq :+
        lda #' '
        stx wordAt
        jsr ConPut
        ldx wordAt
:       stx wordAt
        jsr PutArg
        ldx wordAt
        inx
        bne @word
@nl:    jmp ConNewLine

CmdPwd: jsr Status
        lda #<pwdBuf
        ldy #>pwdBuf
        jmp Say

; cd [path]: the current directory (none: the start drive's root).
CmdCd:  lda argc
        cmp #2
        bcs @path
        lda startDrive          ; "/a" .. "/d"
        clc
        adc #'a' - 8
        sta home+1
        lda #<home
        sta r0L
        lda #>home
        sta r0H
        jmp @go
@path:  ldx #1
        jsr ArgR0
@go:    lda #FE_CD
        jsr FileEngine
        txa
        beq @ok
        ldy #1
        jmp Fail
@ok:    jmp Status

; ls [-l] [path...]: each folder listed (its names, or with -l one line
; each: kind, type, size, date, name); a file: its own line.
CmdLs:  lda #0
        sta long
        ldx #1                  ; options first
@opt:   cpx argc
        bcs @paths
        jsr ArgStr
        ldy #0
        lda (str),y
        cmp #'-'
        bne @paths
@flag:  iny
        lda (str),y
        beq @nextopt
        cmp #'l'
        bne @flag
        sta long                ; (sta keeps cmp's flags: jmp)
        jmp @flag
@nextopt:
        inx
        bne @opt
@paths: stx firstPath
        cpx argc
        bcc @each
        lda #<Dot               ; none: "."
        sta r0L
        lda #>Dot
        sta r0H
        lda #$FF
        sta argAt
        jmp One
@each:  stx argAt
        jsr ArgR0
        jsr One
        ldx argAt
        inx
        cpx argc
        bcc @each
        rts

; One: path r0 (word argAt, or $FF for "."): a folder listed, a file
; shown.
One:    lda r0L
        sta pathAt
        lda r0H
        sta pathAt+1
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
        beq @stat
        ldy argAt
        jmp Fail
@stat:  lda info + FI_KIND
        cmp #K_GEOS
        beq @file
        cmp #K_CBM
        beq @file
        cmp #K_UFILE
        beq @file
        jmp List
@file:  ldy #$FF                ; its own name: the path as given
@nm:    iny
        lda (pathAt),y
        sta nameBuf,y
        bne @nm
        lda #0
        sta shortBuf
        jsr Entry
        jmp EndList

; List: the folder at pathAt, entry by entry.
List:   lda pathAt
        sta r0L
        lda pathAt+1
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        beq @entry
        ldy argAt
        jmp Fail
@entry: lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<nameBuf
        sta r2L
        lda #>nameBuf
        sta r2H
        lda #<shortBuf
        sta r3L
        lda #>shortBuf
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @end
        jsr Entry
        jmp @entry
@end:   ldy handle
        lda #FE_CLOSE
        jsr FileEngine
; EndList: a line ended after the names.
EndList:
        lda conCol
        beq :+
        jmp ConNewLine
:       rts

; Entry: one name (nameBuf; shortBuf its short name, 0: none), with
; its info (info) for ls -l.
Entry:  lda long
        bne Long
        ldy #$FF                ; the name's length; on the next line when
@len:   iny                     ; it does not fit after the others
        lda nameBuf,y
        bne @len
        tya
        clc
        adc conCol
        cmp #COLS
        bcc @put
        lda conCol
        beq @put
        jsr ConNewLine
@put:   lda #<nameBuf
        ldy #>nameBuf
        jsr Print
        lda conCol              ; two spaces after it (not at a line's end)
        beq @end
        cmp #COLS - 2
        bcs @nl
        lda #' '
        jsr ConPut
        lda #' '
        jmp ConPut
@nl:    jmp ConNewLine
@end:   rts

; Long: "d/- type size  yy-mm-dd hh:mm  name [short]".
Long:   ldx info + FI_KIND
        lda KindChar,x
        jsr ConPut
        lda #' '
        jsr ConPut
        jsr Type
        lda #' '
        jsr ConPut
        jsr Size
        lda #' '
        jsr ConPut
        jsr Date
        lda #' '
        jsr ConPut
        lda #<nameBuf
        ldy #>nameBuf
        jsr Print
        lda shortBuf            ; the short name, when it differs
        beq @nl
        ldx #$FF
@cmp:   inx
        lda shortBuf,x
        cmp nameBuf,x
        bne @short
        cmp #0
        bne @cmp
        beq @nl
@short: lda #' '
        jsr ConPut
        lda #'('
        jsr ConPut
        lda #<shortBuf
        ldy #>shortBuf
        jsr Print
        lda #')'
        jsr ConPut
@nl:    jmp ConNewLine

KindChar:
        .byte "/dd--fd"         ; root, drive, folder, GEOS, CBM, file, dir

; Type: three characters for the kind and CBM type.
Type:   ldx info + FI_KIND
        cpx #K_GEOS
        beq @geos
        cpx #K_CBM
        beq @cbm
        lda #<Blank3
        ldy #>Blank3
        cpx #K_UFILE
        bne :+
        lda #<UltFile
        ldy #>UltFile
:       jmp Print
@geos:  lda #<Geos
        ldy #>Geos
        jmp Print
@cbm:   lda info + FI_CBM
        and #$07
        asl a
        asl a
        clc
        adc #<CbmTypes
        tax
        lda #>CbmTypes
        adc #0
        tay
        txa
        jmp Print

Geos:   .byte "geo", 0
UltFile:
        .byte "   ", 0
Blank3: .byte "   ", 0
CbmTypes:
        .byte "del", 0, "seq", 0, "prg", 0, "usr", 0, "rel", 0, "cbm", 0, "dir", 0, "???", 0

; Size: the size (4 bytes) in 8 columns, right-aligned.
Size:   ldx #3
@copy:  lda info + FI_SIZE,x
        sta num,x
        dex
        bpl @copy
        lda #8
        jmp Decimal

; Date: "yy-mm-dd hh:mm" (blanks for no date).
Date:   lda info + FI_DATE + 1  ; (a month: a date)
        bne @date
        lda #<NoDate
        ldy #>NoDate
        jmp Print
@date:  lda info + FI_DATE
        jsr Two
        lda #'-'
        jsr ConPut
        lda info + FI_DATE + 1
        jsr Two
        lda #'-'
        jsr ConPut
        lda info + FI_DATE + 2
        jsr Two
        lda #' '
        jsr ConPut
        lda info + FI_DATE + 3
        jsr Two
        lda #':'
        jsr ConPut
        lda info + FI_DATE + 4
; Two: A (0-99) as two digits.
Two:    ldy #'0' - 1
        sec
@ten:   iny
        sbc #10
        bcs @ten
        adc #10 + '0'
        pha
        tya
        jsr ConPut
        pla
        jmp ConPut

NoDate: .byte "              ", 0

; Decimal: num (4 bytes) in decimal, right-aligned in A columns.
Decimal:
        sta width
        ldx #0                  ; digits, last first, to digits
@digit: lda #0                  ; num /= 10, the remainder in A
        ldy #32
@bit:   asl num
        rol num+1
        rol num+2
        rol num+3
        rol a
        cmp #10
        bcc :+
        sbc #10
        inc num
:       dey
        bne @bit
        ora #'0'
        sta digits,x
        inx
        lda num
        ora num+1
        ora num+2
        ora num+3
        bne @digit
        stx count
@pad:   lda width               ; spaces first
        cmp count
        beq @out
        bcc @out
        dec width
        lda #' '
        jsr ConPut
        jmp @pad
@out:   ldx count
@put:   dex
        bmi @end
        stx count
        lda digits,x
        jsr ConPut
        ldx count
        jmp @put
@end:   rts

; --- Words, texts, errors ----------------------------------------------------

; ArgStr: str = word X. ArgR0: r0 = word X.
ArgStr: lda argLo,x
        sta str
        lda argHi,x
        sta str+1
        rts
ArgR0:  lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        rts

; PutArg: word X printed. Destroys A, X, Y.
PutArg: lda argLo,x
        ldy argHi,x
; Print: the zero-ended text at A/Y (low, high). Destroys A, X, Y.
Print:  sta r0L
        sty r0H
        jmp ConPuts

; Say: Print and a new line.
Say:    jsr Print
        jmp ConNewLine

; Gush: "gush: ".
Gush:   lda #<GushColon
        ldy #>GushColon
        jmp Print

; Fail: "gush: CMD: WORD: TEXT" for error X; Y = the word (its number,
; $FF: none) the error is about. Destroys A, X, Y.
Fail:   stx error
        sty errWord
        jsr Gush
        ldx #0                  ; the command
        jsr PutArg
        lda #<Colon
        ldy #>Colon
        jsr Print
        ldx errWord
        bmi @text
        jsr PutArg
        lda #<Colon
        ldy #>Colon
        jsr Print
@text:  ldx #0                  ; the error's text
@find:  lda ErrCodes,x
        beq @other
        cmp error
        beq @found
        inx
        bne @find
@found: txa
        asl a
        tax
        lda ErrTexts,x
        ldy ErrTexts+1,x
        jmp Say
@other: lda #<ErrOther
        ldy #>ErrOther
        jsr Print
        lda error
        sta num
        lda #0
        sta num+1
        sta num+2
        sta num+3
        lda #1
        jsr Decimal
        jmp ConNewLine

ErrCodes:
        .byte 3, 5, 13, $26, $40, $41, $47, $49, $4A, $4B, $4E, $4F, 0
ErrTexts:
        .word ErrSpace, ErrNotFound, ErrDrive, ErrProtect, ErrExists
        .word ErrNotEmpty, ErrCancelled, ErrBadPath, ErrNotFolder
        .word ErrIsFolder, ErrNotSupp, ErrUltimate
ErrSpace:       .byte "disk full", 0
ErrNotFound:    .byte "no such file or folder", 0
ErrDrive:       .byte "no such drive", 0
ErrProtect:     .byte "write protected", 0
ErrExists:      .byte "exists already", 0
ErrNotEmpty:    .byte "folder not empty", 0
ErrCancelled:   .byte "cancelled", 0
ErrBadPath:     .byte "bad path", 0
ErrNotFolder:   .byte "not a folder", 0
ErrIsFolder:    .byte "is a folder", 0
ErrNotSupp:     .byte "not supported", 0
ErrUltimate:    .byte "the Ultimate refused", 0
ErrOther:       .byte "error ", 0

GushColon:      .byte "gush: ", 0
Colon:          .byte ": ", 0
NotFound:       .byte ": not found", 0
TooMany:        .byte "gush: too many words", 0
NoProgram:      .byte ": no program", 0
Dot:            .byte ".", 0

        .segment "DATA"

home:           .byte "/a", 0
cmdAt:          .byte 0
wordAt:         .byte 0
argAt:          .byte 0
firstPath:      .byte 0
long:           .byte 0
handle:         .byte 0
width:          .byte 0
count:          .byte 0
error:          .byte 0
errWord:        .byte 0
num:            .res 4
digits:         .res 10

        .segment "BSS"

info:           .res 16
nameBuf:        .res 64
shortBuf:       .res 17
