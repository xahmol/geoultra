; gush: running a command line and the commands (docs/GUSH.md,
; "Commands"): exit, clear, echo, pwd, cd, ls here; the file commands
; in files.s. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import ConPut, ConPuts, ConNewLine, ConClear, conCol
        .import FileEngine, Status, pwdBuf, startDrive
        .import Parse, argc, argLo, argHi
        .export Run, ArgR0, PutArg, Print, Say, Fail, FailPath, Decimal, num
        .import CmdCp, CmdMv, CmdRm, CmdMkdir, CmdRmdir, CmdCat, CmdMore, CmdDf
        .import StartProgram, CmdMount, CmdUmount, CmdMkimg, CmdFree
        .import CmdTurbo, CmdDate, CmdReboot, CmdNtp, CmdSet, CmdUnset
        .import VarSet, varName, IsNameChar, Redirect, EndRedirect, sinkPause
        .import sinkOn
        .export status, failed, Commands
        .import RunScript, CmdSource, depth, exitReq, exitStatus, prog
        .import CmdTest, CmdBracket, CmdRead, CmdTrue, CmdFalse, HistSave
        .import RunModule, CmdIfconfig, CmdWget, DriveSwitch, Remember

EnterDeskTop    = $C22C         ; GEOS jump table

; Info block (docs/FILE_ENGINE.md, "Functions")
END_OF_DIR      = $48

        .segment "ZEROPAGE"

str:            .res 2          ; a text being printed
pathAt:         .res 2          ; ls: the path being looked at

        .segment "CODE"

; Run: the line in lineBuf: its words (Parse); leading NAME=value words
; set those variables (Assign: they stay set, unlike sh's for one
; command); the first word left is a command. status ($?): 1 when the
; line failed (an error said), else 0.
Run:    lda #0
        sta failed
        sta sinkPause
        jsr Line
        jsr EndRedirect         ; (a file written: closed)
        lda failed
        sta status
        rts
Line:   jsr Parse
        bcc :+
        inc failed
        lda #<TooMany
        ldy #>TooMany
        jmp Say
:       jsr Assign
        jsr Redirect            ; > >> <: files opened, words taken off
        bcc :+
        rts
:       lda argc
        bne :+
        rts
:       jsr DriveSwitch         ; "b:": a drive (drives.s)
        bcs :+
        rts
:
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
        cpy #1                  ; (the document's error)
        beq @fail
        cpx #IS_MODULE          ; an external command (module.s)
        bne :+
        jmp RunModule
:       cpx #IS_SCRIPT          ; a plain file: run as a script
        bne :+
        lda prog
        sta r0L
        lda prog+1
        sta r0H
        ldx #1
        jmp RunScript
:       cpx #STRUCT_MISMAT
        bne @nf
        jsr Gush                ; there, but no program
        ldx #0
        jsr PutArg
        inc failed
        lda #<NoProgram
        ldy #>NoProgram
        jmp Say
@nf:    cpx #FILE_NOT_FOUND
        beq @none
@fail:  jmp Fail                ; (Y: the word it is about, or $FF)
@none:  inc failed
        jsr Gush
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
        .byte "mkimg", 0
        .word CmdMkimg
        .byte "mount", 0
        .word CmdMount
        .byte "umount", 0
        .word CmdUmount
        .byte "free", 0
        .word CmdFree
        .byte "turbo", 0
        .word CmdTurbo
        .byte "reboot", 0
        .word CmdReboot
        .byte "ntp", 0
        .word CmdNtp
        .byte "date", 0
        .word CmdDate
        .byte "ifconfig", 0
        .word CmdIfconfig
        .byte "wget", 0
        .word CmdWget
        .byte "help", 0
        .word CmdHelp
        .byte "set", 0
        .word CmdSet
        .byte "source", 0
        .word CmdSource
        .byte "test", 0
        .word CmdTest
        .byte "[", 0
        .word CmdBracket
        .byte "read", 0
        .word CmdRead
        .byte "true", 0
        .word CmdTrue
        .byte "false", 0
        .word CmdFalse
        .byte "unset", 0
        .word CmdUnset
        .byte 0

; exit [N]: in a script, the script ends (status N, else 0); else back
; to the desktop.
CmdExit:
        lda depth
        bne :+
        jsr HistSave            ; (hist.s)
        jmp EnterDeskTop
:       lda #0
        sta exitStatus
        lda argc
        cmp #2
        bcc @end
        ldx #1
        jsr ArgStr
        ldy #0
@digit: lda (str),y             ; (0-255; the digits there)
        sec
        sbc #'0'
        cmp #10
        bcs @end
        pha
        lda exitStatus
        asl
        asl
        adc exitStatus
        asl
        sta exitStatus
        pla
        adc exitStatus
        sta exitStatus
        iny
        bne @digit
@end:   inc exitReq
        rts

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
        lda #<Usage             ; the usage lines: "name text", zero
        sta r6L                 ; (r6: the line looked at)
        lda #>Usage
        sta r6H
@line:  ldy #0
        lda (r6),y
        beq @none
@cmp:   lda (r6),y              ; its name: up to a space or its end
        beq @named
        cmp #' '
        beq @named
        cmp (str),y
        bne @skip
        iny
        bne @cmp
@named: lda (str),y
        bne @skip
        lda r6L                 ; this one: printed
        ldy r6H
        jmp Say
@skip:  ldy #0                  ; the next line
@past:  lda (r6),y
        php
        inc r6L
        bne :+
        inc r6H
:       plp
        bne @past
        jmp @line
@none:  jsr Gush
        lda #<NoHelp
        ldy #>NoHelp
        jsr Print
        ldx #1
        jsr PutArg
        jmp ConNewLine

HelpAll:                        ; (lines of 52 at most: 53 wraps)
        .byte "commands: [ cd clear cp date df echo exit false free", CR
        .byte "help ifconfig ls mkdir mkimg more mount mv ntp pwd", CR
        .byte "read reboot rm rmdir set source test true turbo", CR
        .byte "umount unset wget; if/while/for; NAME=value, $NAME;", CR
        .byte "a program's or a script's name starts it.", CR
        .byte "help NAME: a command's use.", 0
Usage:  .byte "cd [path]", 0
        .byte "date [YYYY-MM-DD HH:MM[:SS]]", 0
        .byte "clear", 0
        .byte "cp [-frR] source... target", 0
        .byte "df [path]", 0
        .byte "echo words...", 0
        .byte "exit [N]", 0
        .byte "false", 0
        .byte "free", 0
        .byte "help [command]", 0
        .byte "ifconfig", 0
        .byte "ls [-l] [path...]", 0
        .byte "mkdir [-t tracks] path...", 0
        .byte "mkimg [-t tracks] type path [name]", 0
        .byte "more path...", 0
        .byte "mount [image /drive]", 0
        .byte "mv [-fR] source... target", 0
        .byte "ntp [server]", 0
        .byte "pwd", 0
        .byte "read name...", 0
        .byte "reboot", 0
        .byte "rm [-f] path...", 0
        .byte "rmdir path...", 0
        .byte "set", 0
        .byte "source file [words]", 0
        .byte "test expr (also [ expr ]: -e -f -d -z -n = != -eq...)", 0
        .byte "true", 0
        .byte "turbo [-s] [step]", 0
        .byte "unset name...", 0
        .byte "umount /drive", 0
        .byte "wget [-O name] http://host[:port]/path", 0
        .byte 0
NoHelp: .byte "no help for ", 0

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
@ok:    jmp Remember            ; (drives.s: kept for "b:"; the status line)

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
@paths:
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
        bit sinkOn              ; into a file: a name per line
        bpl @screen
        lda #<nameBuf
        ldy #>nameBuf
        jsr Print
        jmp ConNewLine
@screen:
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

; Assign: the leading words of the form NAME=value (NAME: letters,
; digits, "_", not a digit first) set those variables and are taken off
; the words.
Assign: lda #0
        sta done
@word:  ldx done
        cpx argc
        bcs @shift
        lda argLo,x
        sta r0L
        lda argHi,x
        sta r0H
        ldy #0
        lda (r0),y
        cmp #'0'                ; (no digit first)
        bcc :+
        cmp #'9' + 1
        bcc @shift
:       ldy #$FF
@name:  iny
        cpy #17
        bcs @shift
        lda (r0),y
        cmp #'='
        beq @eq
        jsr IsNameChar
        bcc @shift
        sta varName,y
        bcs @name
@eq:    cpy #0
        beq @shift
        lda #0
        sta varName,y
        iny                     ; the value: after the "="
        tya
        clc
        adc r0L
        sta r0L
        bcc :+
        inc r0H
:       jsr VarSet
        inc done
        bne @word
@shift: ldx done                ; the words left, to the front
        beq @end
        ldy #0
@move:  cpx argc
        bcs @count
        lda argLo,x
        sta argLo,y
        lda argHi,x
        sta argHi,y
        inx
        iny
        bne @move
@count: sty argc
@end:   rts

; Gush: "gush: " (an error or a question: its line on the screen even
; when the output goes to a file: sinkPause, redir.s).
Gush:   lda #1
        sta sinkPause
        lda #<GushColon
        ldy #>GushColon
        jmp Print

; Fail: "gush: CMD: WORD: TEXT" for error X; Y = the word (its number,
; $FF: none) the error is about. FailPath: the same about the text at
; A/Y (a path gush made). Destroys A, X, Y.
Fail:   inc failed              ; ($?: the line failed)
        stx error
        sty errWord
        jsr Gush
        ldx #0                  ; the command
        jsr PutArg
        lda #<Colon
        ldy #>Colon
        jsr Print
        ldx errWord
        bmi ErrText
        jsr PutArg
        jmp ErrColon
FailPath:
        inc failed
        stx error
        sta errPath
        sty errPath+1
        jsr Gush
        ldx #0
        jsr PutArg
        lda #<Colon
        ldy #>Colon
        jsr Print
        lda errPath
        ldy errPath+1
        jsr Print
ErrColon:
        lda #<Colon
        ldy #>Colon
        jsr Print
; ErrText: error's text and a new line.
ErrText:
        ldx #0                  ; the error's text
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
        .byte 3, 5, 13, $26, $40, $41, $47, $49, $4A, $4B, $4E, $4F, $50, $F3, $F4
        .byte $F5, $F6, $F7
        .byte $F8
        .byte $F9, $FA
        .byte $FB, $FC, $FD, $FE, $FF, ERR_MODULE, ERR_URL, ERR_HTTP
        .byte ERR_TIMEOUT, 0
ErrTexts:
        .word ErrSpace, ErrNotFound, ErrDrive, ErrProtect, ErrExists
        .word ErrNotEmpty, ErrCancelled, ErrBadPath, ErrNotFolder
        .word ErrIsFolder, ErrNotSupp, ErrUltimate, ErrNoSlot, ErrDeep, ErrOneRedir
        .word ErrLong, ErrNoServer, ErrClock
        .word ErrNoTurbo
        .word ErrWords, ErrOwnDrive
        .word ErrNoRoom, ErrNoDoc, ErrOneDoc
        .word ErrOtherFolder, ErrTooMany, ErrModule, ErrUrl, ErrHttp
        .word ErrTimeout
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
ErrNoSlot:      .byte "no free drive letter for E", 0
ErrDeep:        .byte "scripts nested too deep (4 at most)", 0
ErrOneRedir:    .byte "one output redirection at a time", 0
ErrLong:        .byte "script too long (16 KB at most)", 0
ErrNoServer:    .byte "no server (SETTINGS.INI [time] ntp=)", 0
ErrClock:       .byte "clock setting off (Ultimate menu, Allow SetDate)", 0
ErrNoTurbo:     .byte "no turbo (an Ultimate 64 has it)", 0   ; (gush's
ErrWords:       .byte "wrong words (see help)", 0      ; own, $F3-$FF)
ErrOwnDrive:    .byte "gush runs from there", 0
ErrNoRoom:      .byte "no room in the REU", 0
ErrNoDoc:       .byte "a desk accessory takes no document", 0
ErrOneDoc:      .byte "one document at a time", 0
ErrOtherFolder: .byte "not in the program's folder", 0
ErrTooMany:     .byte "too many entries", 0
ErrModule:      .byte "not a gush command, or for a newer gush", 0
ErrUrl:         .byte "bad URL (http:// only)", 0
ErrHttp:        .byte "the answer ended early", 0
ErrTimeout:     .byte "no answer in time", 0
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
failed:         .byte 0         ; Run: the line failed
status:         .byte 0         ; $?: the last line's
done:           .byte 0         ; Assign: words taken
wordAt:         .byte 0
argAt:          .byte 0
long:           .byte 0
handle:         .byte 0
width:          .byte 0
count:          .byte 0
error:          .byte 0
errWord:        .byte 0
errPath:        .word 0
num:            .res 4
digits:         .res 10

        .segment "BSS"

info:           .res 16
nameBuf:        .res 64
shortBuf:       .res 17
