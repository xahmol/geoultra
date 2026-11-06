; gush: turbo, date and ntp (docs/GUSH.md, "Step 2"), with turbo -s
; writing the step into SETTINGS.INI's [system] section. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, argc, argLo, argHi
        .import ArgR0, Print, Say, Fail, Decimal, num, ConPut
        .export Ov_CmdTurbo := CmdTurbo
        .export Ov_CmdDate := CmdDate
        .export Ov_CmdNtp := CmdNtp

FE_TURBO        = 25
FE_HOME         = 26
FE_SETTIME      = 27
FE_NTP          = 29
FE_BAD_PATH     = $49
FE_ULTIMATE     = $4F
TEXT_MAX        = 3072          ; SETTINGS.INI's bytes, at most
                                ; (geos.inc: year, then month, day, hour,
                                ; minutes, seconds)

        .segment "OV2"                 ; (overlay 2, ovl.s)

; turbo: the U64's speed step. turbo [-s] N: step N (0: 1 MHz, 15: the
; most); -s also in SETTINGS.INI ([system] turbo=N), for the next boot.
CmdTurbo:
        lda argc
        cmp #1
        beq Show
        ldx #1
        stx at
        jsr Arg
        ldy #0
        lda (r0),y
        cmp #'-'
        bne @step
        iny
        lda (r0),y
        cmp #'s'
        bne Words
        iny
        lda (r0),y
        bne Words
        sty save                ; (nonzero)
        inc at
@step:  lda at                  ; the last word: the step
        clc
        adc #1
        cmp argc
        bne Words
        ldx at
        jsr Arg
        jsr Number
        bcs Words
        cmp #16
        bcs Words
        sta r2L
        sta step
        lda #FE_TURBO
        jsr FileEngine
        txa
        bne Failed
        lda save
        beq Show
        jsr SaveStep
        txa
        bne Failed
; Show: the speed step and its MHz on both kinds of U64.
Show:   lda #$FF                ; "turbo: step N of 15", then "A MHz (U64,
        sta r2L                 ; Elite I), B MHz (Elite II, C64U)"
        lda #FE_TURBO
        jsr FileEngine
        txa
        bne Failed
        lda r1L
        pha
        lda #<StepText
        ldy #>StepText
        jsr Print
        pla
        pha
        jsr Num
        lda #<OfText
        ldy #>OfText
        jsr Say
        pla
        tax
        pha
        lda MhzU64,x
        jsr Num
        lda #<U64Text
        ldy #>U64Text
        jsr Print
        pla
        tax
        lda MhzE2,x
        jsr Num
        lda #<E2Text
        ldy #>E2Text
        jmp Say

; Words: the wrong words for the command (said). Failed: error X said
; (no turbo registers: as such).
Words:  ldx #ERR_WORDS
        ldy #$FF
        jmp Fail
Failed: cpx #DEV_NOT_FOUND
        bne :+
        ldx #ERR_NO_TURBO
:       ldy #$FF
        jmp Fail

; Arg: r0 = word X. Number: the word at r0 as a number 0-255 in A; C
; set when it is none.
Arg:    jmp ArgR0
Number: ldy #0
        sty num
@digit: lda (r0),y
        beq @end
        sec
        sbc #'0'
        cmp #10
        bcs @no
        pha
        lda num                 ; num * 10 + digit
        cmp #26
        bcs @big
        asl
        asl
        adc num
        asl
        sta num
        pla
        clc
        adc num
        bcs @no
        sta num
        iny
        bne @digit
@big:   pla
@no:    sec
        rts
@end:   cpy #1                  ; (at least one digit: C set, then flipped)
        lda num
        bcc @no
        clc
        rts

; Num: A in decimal.
Num:    sta num
        lda #0
        sta num+1
        sta num+2
        sta num+3
        lda #1
        jmp Decimal

; --- SETTINGS.INI ------------------------------------------------------------

; SaveStep: SETTINGS.INI anew, with "turbo=step" as the first line of
; its [system] section (an older turbo= line there left out; the section
; added when there is none); every other line as it was. Written as
; SETTINGS.TMP, which then takes SETTINGS.INI's place. X = 0 or the
; error.
SaveStep:
        jsr Paths
        jsr ReadIni
        txa
        bne @end
        lda #<tmpPath
        sta r0L
        lda #>tmpPath
        sta r0H
        lda #FO_WRITE
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        txa
        bne @end
        jsr Lines
        lda #FE_CLOSE
        ldy handle
        jsr FileEngine
        lda #<iniPath           ; the old one away, the new one in its place
        sta r0L
        lda #>iniPath
        sta r0H
        lda #FE_DELETE
        jsr FileEngine
        lda #<tmpPath
        sta r0L
        lda #>tmpPath
        sta r0H
        lda #<IniName
        sta r1L
        lda #>IniName
        sta r1H
        lda #FE_RENAME
        jsr FileEngine
@end:   rts

; Paths: iniPath, tmpPath = the home folder and the two names.
Paths:  lda #<iniPath
        sta r1L
        lda #>iniPath
        sta r1H
        lda #FE_HOME
        jsr FileEngine
        ldx #0
@home:  lda iniPath,x
        sta tmpPath,x
        beq @end
        inx
        cpx #32
        bne @home
@end:   ldy #0
@name:  lda IniName,y
        sta iniPath,x
        lda TmpName,y
        sta tmpPath,x
        beq @done
        inx
        iny
        bne @name
@done:  rts

; ReadIni: SETTINGS.INI into text (none there: empty), textLen its
; bytes. X = 0 or the error (FE_ULTIMATE: larger than TEXT_MAX).
ReadIni:
        lda #0
        sta textLen
        sta textLen+1
        lda #<iniPath
        sta r0L
        lda #>iniPath
        sta r0H
        lda #FO_READ
        sta r2L
        lda #FE_OPEN
        jsr FileEngine
        sta handle              ; (A: the handle; txa would lose it)
        cpx #FILE_NOT_FOUND
        beq @none
        txa
        bne @end
        lda #<text
        sta r1L
        lda #>text
        sta r1H
        lda #<(TEXT_MAX + 1)
        sta r2L
        lda #>(TEXT_MAX + 1)
        sta r2H
        lda #FE_READ
        ldy handle
        jsr FileEngine
        lda r2L
        sta textLen
        lda r2H
        sta textLen+1
        txa
        pha
        lda #FE_CLOSE
        ldy handle
        jsr FileEngine
        pla
        tax
        bne @end
        ldx #FE_ULTIMATE        ; (too large to rewrite safely)
        lda textLen
        cmp #<(TEXT_MAX + 1)
        lda textLen+1
        sbc #>(TEXT_MAX + 1)
        bcs @end
@none:  ldx #0
@end:   rts

; Lines: the new text to the open file, a line at a time.
Lines:  lda #0
        sta inSystem
        sta written
        lda #<text
        sta r5L
        lda #>text
        sta r5H
        lda #<text              ; textEnd = text + textLen
        clc
        adc textLen
        sta textEnd
        lda #>text
        adc textLen+1
        sta textEnd+1
@line:  lda r5L
        cmp textEnd
        lda r5H
        sbc textEnd+1
        bcs @done
        jsr LineLen             ; Y: its bytes, with its end
        ldy #0
        lda (r5),y
        cmp #'['
        bne @inside
        jsr IsSystem
        sta inSystem
        jsr Put                 ; the section's line, then turbo= in [system]
        lda inSystem
        beq @next
        jsr Nl
        jsr Turbo
        jmp @next
@inside:
        lda inSystem
        beq @put
        jsr IsTurbo
        bcs @next               ; (the old one left out)
@put:   jsr Put
@next:  lda r5L
        clc
        adc lineLen
        sta r5L
        bcc @line
        inc r5H
        bne @line
@done:  lda written             ; no [system]: added at the end
        bne @end
        lda textLen
        ora textLen+1
        beq :+
        lda textEnd             ; (after the last line's end)
        sec
        sbc #1
        sta r5L
        lda textEnd+1
        sbc #0
        sta r5H
        lda #1
        sta lineLen
        jsr Nl
:       lda #<SystemLine
        ldy #>SystemLine
        jsr Write
        jsr Turbo
@end:   rts

; LineLen: lineLen = the line at r5's bytes, its CR/LF included (to the
; text's end at most).
LineLen:
        ldy #0
@ch:    tya
        clc
        adc r5L
        tax
        lda #0
        adc r5H
        cpx textEnd
        sbc textEnd+1
        bcs @end
        lda (r5),y
        iny
        cmp #10
        bne @ch
@end:   sty lineLen
        rts

; Nl: CR LF written when the line at r5 (lineLen bytes) does not end
; with LF (the file's last line).
Nl:     ldy lineLen
        beq @end
        dey
        lda (r5),y
        cmp #10
        beq @end
        lda #<CrLf
        ldy #>CrLf
        jmp Write
@end:   rts

; IsSystem: A = 1 when the line at r5 is "[system]" (letters in any
; case), else 0.
IsSystem:
        ldy #0
@ch:    lda (r5),y
        cmp SystemKey,y         ; (as it is, else the letter in lower case:
        beq :+                  ; ora alone would turn "[" into "{")
        ora #$20
        cmp SystemKey,y
        bne @no
:       iny
        cpy #SystemLen
        bne @ch
        lda #1
        rts
@no:    lda #0
        rts

; IsTurbo: C set when the line at r5 starts with "turbo=" (any case).
IsTurbo:
        ldy #0
@ch:    lda (r5),y
        cmp TurboKey,y          ; (as IsSystem)
        beq :+
        ora #$20
        cmp TurboKey,y
        bne @no
:       iny
        cpy #TurboLen
        bne @ch
        sec
        rts
@no:    clc
        rts

; Put: the line at r5 (lineLen bytes) written.
Put:    lda r5L
        sta r1L
        lda r5H
        sta r1H
        lda lineLen
        sta r2L
        lda #0
        sta r2H
        beq Out

; Turbo: "turbo=step", CR LF written.
Turbo:  lda #1
        sta written
        lda #<TurboLine
        ldy #>TurboLine
        jsr Write
        lda step                ; (one or two digits)
        ldx #'0'
@tens:  cmp #10
        bcc :+
        sbc #10
        inx
        bne @tens
:       ora #'0'
        sta digits+1
        stx digits
        lda #<digits
        ldy #>digits
        cpx #'0'
        bne :+
        lda #<(digits + 1)
:       jsr Write
        lda #<CrLf
        ldy #>CrLf
; Write: the zero-ended text at A/Y written.
Write:  sta r1L
        sty r1H
        ldy #$FF
@len:   iny
        lda (r1),y
        bne @len
        sty r2L
        lda #0
        sta r2H
Out:    lda #FE_WRITE
        ldy handle
        jmp FileEngine

; --- ntp ---------------------------------------------------------------------

; ntp [server]: the clocks from the server (else SETTINGS.INI's [time]
; ntp=), with [time] offset= seconds from UTC; then the date shown.
CmdNtp: lda #0
        sta r0L
        sta r0H
        lda argc
        cmp #3
        bcc :+
        jmp Words
:       cmp #2
        bcc @go
        ldx #1
        jsr ArgR0
@go:    lda #FE_NTP
        jsr FileEngine
        txa
        bne :+
        jmp ShowDate
:       cpx #FILE_NOT_FOUND
        bne :+
        ldx #ERR_NO_SERVER
:       ldy #$FF
        jmp Fail

; --- date --------------------------------------------------------------------

; date: GEOS's date and time. date YYYY-MM-DD HH:MM[:SS]: both set, and
; the Ultimate's clock.
CmdDate:
        lda argc
        cmp #1
        bne :+
        jmp ShowDate
:       cmp #3
        beq :+
        jmp Words
:       ldx #1                  ; YYYY-MM-DD
        jsr ArgR0
        ldy #0
        clc                     ; (Two: C set on entry passes an error on)
        jsr Two                 ; (the century: 19 or 20)
        bcs @bad
        sta century
        jsr Two
        bcs @bad
        sta new
        jsr Dash
        jsr Two
        sta new+1
        jsr Dash
        jsr Two
        sta new+2
        bcs @bad
        lda (r0),y
        bne @bad
        ldx #2                  ; HH:MM[:SS]
        jsr ArgR0
        ldy #0
        jsr Two
        sta new+3
        jsr Dash
        jsr Two
        sta new+4
        bcs @bad
        lda #0
        sta new+5
        lda (r0),y
        beq @check
        jsr Dash
        jsr Two
        sta new+5
        bcs @bad
        lda (r0),y
        bne @bad
@check: jsr Valid
        bcs @bad
        ldx #5
@set:   lda new,x
        sta year,x
        dex
        bpl @set
        lda #FE_SETTIME
        jsr FileEngine
        txa
        beq ShowDate
        cpx #FE_ULTIMATE
        bne :+
        ldx #ERR_CLOCK
:       ldy #$FF
        jmp Fail
@bad:   ldx #FE_BAD_PATH
        ldy #$FF
        jmp Fail
; ShowDate: GEOS's date and time, "yyyy-mm-dd hh:mm:ss".
ShowDate:
        lda year                ; "20yy-mm-dd hh:mm:ss"
        cmp #80
        lda #20
        bcc :+
        lda #19
:       jsr Out2
        ldx #0
@field: stx at
        lda year,x
        jsr Out2
        ldx at
        lda Seps,x
        beq @end
        jsr ConPut
        ldx at
        inx
        bne @field
@end:   jmp ConNewLine

; Two: two digits at (r0),y as a number (Y on by 2); C set when they are
; none (C stays set: a later Two keeps it).
Two:    bcs @end
        lda (r0),y
        sec
        sbc #'0'
        cmp #10
        bcs @end
        sta digits
        asl                     ; * 10
        asl
        adc digits
        asl
        sta digits
        iny
        lda (r0),y
        sec
        sbc #'0'
        cmp #10
        bcs @end
        adc digits              ; (C clear)
        iny
@end:   rts

; Dash: a separator (- or :) at (r0),y passed (C set when none).
Dash:   bcs @end
        lda (r0),y
        cmp #'-'
        beq @ok
        cmp #':'
        beq @ok
        sec
        rts
@ok:    iny
        clc
@end:   rts

; Valid: C clear when new is a date and time (century 19 or 20 with a
; year that GEOS keeps in two digits: 1980-2079; month 1-12, day 1-31,
; hour 0-23, minutes and seconds 0-59).
Valid:  lda century
        cmp #19
        bne @c20
        lda new
        cmp #80
        bcc @no
        bcs @rest
@c20:   cmp #20
        bne @no
        lda new
        cmp #80
        bcs @no
@rest:  ldx #4
@field: lda new+1,x
        cmp Low,x
        bcc @no
        cmp High,x
        bcs @no
        dex
        bpl @field
        clc
        rts
@no:    sec
        rts

; Out2: A (0-99) as two digits.
Out2:   ldx #'0'
@tens:  cmp #10
        bcc :+
        sbc #10
        inx
        bne @tens
:       pha
        txa
        jsr ConPut
        pla
        ora #'0'
        jmp ConPut

        .import ConNewLine

Low:    .byte 1, 1, 0, 0, 0     ; month, day, hour, minutes, seconds
High:   .byte 13, 32, 24, 60, 60
Seps:   .byte "-- ::", 0
MhzU64: .byte 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 24, 32, 40, 48
MhzE2:  .byte 1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32, 40, 48, 64
StepText:       .byte "turbo: step ", 0
OfText:         .byte " of 15", 0
U64Text:        .byte " MHz (U64, Elite I), ", 0
E2Text:         .byte " MHz (Elite II, C64U)", 0
IniName:        .byte "SETTINGS.INI", 0
TmpName:        .byte "SETTINGS.TMP", 0
SystemKey:      .byte "[system]"
SystemLen       = * - SystemKey
SystemLine:     .byte "[system]", CR, 10, 0
TurboKey:       .byte "turbo="
TurboLen        = * - TurboKey
TurboLine:      .byte "turbo=", 0
CrLf:           .byte CR, 10, 0

        .segment "OV2"

at:             .byte 0
save:           .byte 0
step:           .byte 0
handle:         .byte 0
inSystem:       .byte 0
written:        .byte 0
lineLen:        .byte 0
century:        .byte 0
digits:         .byte 0, 0, 0
textLen:        .word 0
textEnd:        .word 0

        .segment "BSS"

new:            .res 6
iniPath:        .res 48
tmpPath:        .res 48
        .segment "HIGHBSS"
text:           .res TEXT_MAX + 1
        .segment "BSS"
