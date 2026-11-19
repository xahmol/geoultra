; GeoUltra Settings: the Serials page (overlay 2 with the Pointer page,
; ovl.s; docs/DESIGN.md "Serial number", the user's decisions of
; 2026-11-19: the full design, a tenth page). The serial number GeoUltra
; gives (SETTINGS.INI [system] serial=: none the user's own GEOS boot
; disk, found on the drives at the start; four hex digits a fixed one;
; GeoUltra's own number, SERIAL, for "GeoUltra") and the one in use now
; (GetSerialNumber);
; the bypass ([system] protection=bypass; switching it on shows the
; disclaimer); the serials per application ([serials] class=hex: the
; class only, any case), Add (asked: the class, then the number) and
; Remove; the disclaimer under them. The [serials] list takes effect at
; once on Save (settings.s Write: FE_SERIALS), the rest at the next
; start. Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress, ButtonDraw, OnButton, DrawPage
        .import IniFind, IniSet, IniDel, iniSkip, dirty, NoRoom, Dialog, Plain
        .import iniBase, iniLen
        .export Ov_SerDraw, Ov_SerPress

GetSerialNumber = $C196         ; GEOS jump table

        .segment "ZEROPAGE"

tp:             .res 2          ; the INI text being read
askLine:        .res 2          ; (DBVARSTR)

        .segment "OV2"

; Ov_SerDraw: the rows, the number in use, the list, the buttons, the
; disclaimer.
Ov_SerDraw:
        jsr Fixed               ; fixedVal: [system] serial='s hex, if any
        lda #<Rows
        ldx #>Rows
        jsr ChoiceDraw
        jsr InUse
        lda #<ListT
        ldx #>ListT
        ldy #LIST_HEAD
        jsr Line
        jsr ListDraw
        lda #B_ADD
        jsr BtnDraw
        lda #B_REMOVE
        jsr BtnDraw
        ldx #0                  ; the disclaimer
:       stx at
        lda DiscLo,x
        pha
        lda DiscHi,x
        tax
        pla
        ldy at
        pha
        lda DiscY,y
        tay
        pla
        jsr Line
        ldx at
        inx
        cpx #DISC_N
        bcc :-
        rts

; Ov_SerPress: "fixed" asks for a number; the rows (the bypass switched
; on: the disclaimer once more); Add, Remove; a list row selected.
Ov_SerPress:
        jsr OnFixed
        bcs :+
        jmp AskFixed
:       lda #B_ADD
        jsr BtnOn
        bcs :+
        jmp Add
:       lda #B_REMOVE
        jsr BtnOn
        bcs :+
        jmp Remove
:       jsr OnList
        bcs :+
        rts
:       jsr Bypass              ; (A: $80 when it is on)
        sta wasOn
        lda #<Rows
        ldx #>Rows
        jsr ChoicePress
        jsr Bypass
        bit wasOn
        bmi @end
        tax
        bpl @end
        lda #<DiscDlg           ; switched on: the disclaimer
        ldx #>DiscDlg
        jmp Plain
@end:   rts

; --- The serial number GeoUltra gives ------------------------------------

; Fixed: fixedVal = [system] serial='s value when it is four hex digits,
; else "-" (no option matches it then: "fixed" is not marked).
Fixed:  lda #'-'
        sta fixedVal
        lda #0
        sta fixedVal + 1
        jsr KeySerial
        jsr IniFind
        bcs @end
        cmp #4
        bne @end
        ldy #3
:       lda (r2),y
        jsr IsHex
        bcs @end
        dey
        bpl :-
        ldy #3                  ; (GeoUltra's own number: "GeoUltra", not
:       lda (r2),y              ; "fixed")
        jsr Upper
        cmp VOwn,y
        bne @fixed
        dey
        bpl :-
        rts
@fixed: ldy #3
:       lda (r2),y
        sta fixedVal,y
        dey
        bpl :-
        lda #0
        sta fixedVal + 4
@end:   rts

; OnFixed: C clear when the click is on the row's "fixed" option.
OnFixed:
        lda mouseYPos
        cmp #Y0 - 9
        bcc @no
        cmp #Y0 + 3
        bcs @no
        lda mouseXPos + 1
        bne @no
        lda mouseXPos
        cmp #COL2
        bcc @no
        cmp #COL3
        bcs @no
        clc
        rts
@no:    sec
        rts

; AskFixed: a number asked (four hex digits; the one set as the
; default), then [system] serial= it.
AskFixed:
        ldy #4
:       lda fixedVal,y
        sta input,y
        dey
        bpl :-
        lda input
        cmp #'-'
        bne :+
        lda #0
        sta input
:       lda #<AskSerT
        ldx #>AskSerT
        ldy #4
        jsr Ask
        bcs @end
        jsr Hex4                ; (not four hex digits: nothing)
        bcs @end
        jsr KeySerial
        lda #<input
        sta r2L
        lda #>input
        sta r2H
        jsr IniSet
        bcs @full
        jmp Changed
@full:  jmp NoRoom
@end:   jmp DrawPage

; InUse: "In use: XXXX" (GetSerialNumber: Settings is in no [serials]
; list, so it is the system's).
InUse:  jsr GetSerialNumber
        lda r0H
        jsr HexByte
        stx useT + 8
        sta useT + 9
        lda r0L
        jsr HexByte
        stx useT + 10
        sta useT + 11
        lda #<useT
        ldx #>useT
        ldy #Y0 + DY
        jmp Line

; Bypass: A = $80 when [system] protection=bypass, else 0.
Bypass: lda #<SSystem
        sta r0L
        lda #>SSystem
        sta r0H
        lda #<KProt
        sta r1L
        lda #>KProt
        sta r1H
        jsr IniFind
        bcs @off
        ldy #0
        lda (r2),y
        ora #$20
        cmp #'b'
        bne @off
        lda #$80
        rts
@off:   lda #0
        rts

; KeySerial: r0, r1 = [system] serial.
KeySerial:
        lda #<SSystem
        sta r0L
        lda #>SSystem
        sta r0H
        lda #<KSerial
        sta r1L
        lda #>KSerial
        sta r1H
        rts

; --- The serials per application ----------------------------------------

; ListDraw: the box and [serials]' lines ("class  hex"), the selected
; one inverted; count = the lines (LIST_ROWS shown at most).
ListDraw:
        jsr ListBox
        lda #$FF
        jsr FrameRectangle
        lda #0
        sta count
        jsr Section
        bcs @end
@line:  jsr NextLine        ; (C set: no more)
        bcs @end
        lda count
        cmp #LIST_ROWS
        bcs @end
        jsr RowBase
        sta r1H
        lda #<shown
        sta r0L
        lda #>shown
        sta r0H
        lda #<TEXT_X
        sta r11L
        lda #>TEXT_X
        sta r11H
        jsr PutString
        lda count
        cmp sel
        bne :+
        jsr RowInvert
:       inc count
        bne @line
@end:   rts

; Section: tp at the line after "[serials]" in the INI text. C set: none.
Section:
        lda iniBase
        sta tp
        lda iniBase + 1
        sta tp + 1
@line:  jsr AtEnd
        bcs @no
        ldy #0
        lda (tp),y
        cmp #'['
        bne @skip
        ldy #1
:       lda (tp),y
        ora #$20
        cmp SectT - 1,y
        bne @skip
        iny
        cpy #SECT_LEN + 1
        bcc :-
        lda (tp),y
        cmp #']'
        bne @skip
        jsr EndLine
        clc
        rts
@skip:  jsr EndLine
        jmp @line
@no:    sec
        rts

; NextLine: the next "class=hex" line of the section as shown (the class,
; spaces to SHOWN_COL, the value) and key (its class, zero-ended); tp
; after it. C set: the section's end ("[" or the text's end).
NextLine:
@line:  jsr AtEnd
        bcs @no
        ldy #0
        lda (tp),y
        cmp #'['
        beq @no
        cmp #CR
        beq @blank
        cmp #LF
        beq @blank
        ldx #0                  ; the class
@cls:   lda (tp),y
        cmp #'='
        beq @val
        cmp #CR
        beq @blank              ; (no "=": not a line of it)
        cpx #KEY_MAX
        bcs :+
        sta key,x
        sta shown,x
        inx
:       iny
        bne @cls
@val:   lda #0
        sta key,x
:       cpx #SHOWN_COL
        bcs :+
        lda #' '
        sta shown,x
        inx
        bne :-
:       iny                     ; the value
@v:     lda (tp),y
        cmp #CR
        beq @done
        cmp #LF
        beq @done
        cpx #SHOWN_MAX
        bcs :+
        sta shown,x
        inx
:       iny
        bne @v
@done:  lda #0
        sta shown,x
        jsr EndLine
        clc
        rts
@blank: jsr EndLine
        jmp @line
@no:    sec
        rts

; EndLine: tp after the line (its CR, LF or both).
EndLine:
        ldy #0
@to:    jsr AtEnd
        bcs @end
        lda (tp),y
        jsr Step
        cmp #CR
        beq @eol
        cmp #LF
        bne @to
        rts
@eol:   jsr AtEnd
        bcs @end
        lda (tp),y
        cmp #LF
        bne @end
        jsr Step
@end:   rts

; Step: tp + 1. Keeps A, Y.
Step:   inc tp
        bne :+
        inc tp + 1
:       rts

; AtEnd: C set when tp has reached the text's end (iniBase + iniLen).
AtEnd:  lda iniBase
        clc
        adc iniLen
        sta tmp
        lda iniBase + 1
        adc iniLen + 1
        sta tmp + 1
        lda tp
        cmp tmp
        lda tp + 1
        sbc tmp + 1
        rts

; Add: the class asked, then the number; [serials] class=hex.
Add:    lda #0
        sta input
        lda #<AskClsT
        ldx #>AskClsT
        ldy #12
        jsr Ask
        bcs @end
        lda input
        beq @end
        ldy #12
:       lda input,y
        sta key,y
        dey
        bpl :-
        lda #0
        sta input
        lda #<AskNumT
        ldx #>AskNumT
        ldy #4
        jsr Ask
        bcs @end
        jsr Hex4
        bcs @end
        jsr KeyApp
        lda #<input
        sta r2L
        lda #>input
        sta r2H
        jsr IniSet
        bcs @full
        jmp Changed
@full:  jmp NoRoom
@end:   jmp DrawPage

; Remove: the selected line taken out.
Remove: lda sel
        cmp count
        bcs @end
        jsr Section             ; key = its class
        bcs @end
        ldx #$FF
        stx at
:       inc at
        jsr NextLine
        bcs @end
        lda at
        cmp sel
        bne :-
        jsr KeyApp
        jsr IniDel
        lda #$FF
        sta sel
        jmp Changed
@end:   rts

; KeyApp: r0, r1 = [serials] key.
KeyApp: lda #<SSerials
        sta r0L
        lda #>SSerials
        sta r0H
        lda #<key
        sta r1L
        lda #>key
        sta r1H
        rts

; OnList: a click on a list row selects it (again: not); C set when the
; click was not in the list.
OnList: jsr ListBox
        lda mouseYPos
        cmp r2L
        bcc @no
        cmp r2H
        bcs @no
        lda mouseXPos + 1
        bne @no
        lda mouseXPos
        cmp #LIST_X
        bcc @no
        cmp #LIST_R
        bcs @no
        lda mouseYPos
        sec
        sbc #LIST_TOP + 1
        ldx #0
@div:   cmp #ROW_H
        bcc :+
        sbc #ROW_H
        inx
        bne @div
:       cpx count
        bcs @end
        cpx sel
        bne :+
        ldx #$FF
:       stx sel
        jsr DrawPage
@end:   clc
        rts
@no:    sec
        rts

; --- Shared --------------------------------------------------------------

; Ask: the question at A/X, the answer in input (Y characters at most,
; its start already there). C clear: OK or RETURN with an answer.
Ask:    sta askLine
        stx askLine + 1
        sty askLen
        lda #<input
        sta r5L
        lda #>input
        sta r5H
        lda askLen
        sta AskMax
        lda #<AskDlg
        sta r0L
        lda #>AskDlg
        sta r0H
        jsr Dialog
        lda r0L
        cmp #DBGETSTRING        ; (RETURN ends it as OK)
        beq @ok
        cmp #OK
        bne @no
@ok:    lda input
        beq @no
        clc
        rts
@no:    sec
        rts

; Hex4: C clear when input is four hex digits (written in upper case).
Hex4:   ldy #0
:       lda input,y
        jsr IsHex
        bcs @no
        jsr Upper
        sta input,y
        iny
        cpy #4
        bcc :-
        lda input,y
        bne @no
        clc
        rts
@no:    sec
        rts

; IsHex: C clear when A is a hex digit (any case). Keeps A, Y.
IsHex:  pha
        jsr Upper
        cmp #'0'
        bcc @no
        cmp #'9' + 1
        bcc @yes
        cmp #'A'
        bcc @no
        cmp #'F' + 1
        bcs @no
@yes:   pla
        clc
        rts
@no:    pla
        sec
        rts

; Upper: A in upper case (ASCII letters).
Upper:  cmp #'a'
        bcc :+
        cmp #'z' + 1
        bcs :+
        and #$DF
:       rts

; HexByte: A as two hex digits: X the first, A the second.
HexByte:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr Digit
        tax
        pla
        and #$0F
Digit:  cmp #10
        bcc :+
        adc #'A' - 10 - 1
        rts
:       ora #'0'
        rts

; Changed: dirty, the page drawn again.
Changed:
        lda #$80
        sta dirty
        lda #0
        sta iniSkip
        jmp DrawPage

; ListBox: r2-r4 = the list's box.
ListBox:
        lda #LIST_TOP
        sta r2L
        lda #LIST_TOP + LIST_ROWS * ROW_H + 2
        sta r2H
        lda #<LIST_X
        sta r3L
        lda #>LIST_X
        sta r3H
        lda #<LIST_R
        sta r4L
        lda #>LIST_R
        sta r4H
        rts

; RowBase: A = row A's baseline.
RowBase:
        tax
        lda #LIST_TOP + ROW_H - 2
@m:     dex
        bmi @end
        clc
        adc #ROW_H
        bne @m
@end:   rts

; RowInvert: row A inverted.
RowInvert:
        jsr RowBase
        sec
        sbc #ROW_H - 3
        sta r2L
        clc
        adc #ROW_H - 1
        sta r2H
        lda #<(LIST_X + 1)
        sta r3L
        lda #>(LIST_X + 1)
        sta r3H
        lda #<(LIST_R - 1)
        sta r4L
        lda #>(LIST_R - 1)
        sta r4H
        jmp InvertRectangle

; BtnDraw, BtnOn: button A: drawn; C clear when the pointer is on it.
BtnDraw:
        jsr BtnAt
        jmp ButtonDraw
BtnOn:  jsr BtnAt
        jmp OnButton
BtnAt:  asl a                   ; (records of 6 bytes)
        sta tmp
        asl a
        adc tmp
        clc
        adc #<BtnDefs
        tay
        lda #>BtnDefs
        adc #0
        tax
        tya
        rts

; Line: the text at A/X at NOTE_X, baseline Y.
Line:   sty r1H
        sta r0L
        stx r0H
        lda #<NOTE_X
        sta r11L
        lda #>NOTE_X
        sta r11H
        jmp PutString

; --- data

Y0              = PAGE_TOP + 20 ; the rows' baselines (as the Printing page)
DY              = 14
COL1            = 132
COL2            = 196
COL3            = 240
NOTE_X          = PAGE_LEFT + 2
LIST_HEAD       = Y0 + 3 * DY + 4
LIST_X          = PAGE_LEFT + 2
LIST_R          = 252
LIST_TOP        = LIST_HEAD + 3
ROW_H           = 11
LIST_ROWS       = 5
TEXT_X          = LIST_X + 4
SHOWN_COL       = 14            ; the value's column in a row
SHOWN_MAX       = 24
KEY_MAX         = 16
BTN_X           = LIST_R + 6
B_ADD           = 0
B_REMOVE        = 1
DISC_Y          = LIST_TOP + LIST_ROWS * ROW_H + 12
DISC_N          = 2
        .assert DISC_Y + 10 <= PAGE_BOTTOM, error, "pser.s: the disclaimer below the page"

Rows:   .byte 2
        .byte Y0                        ; the serial GeoUltra gives
        .word LSerial, SSystem, KSerial
        .byte 3, 0
        .word COL1, TBoot, 0
        .word COL2, TFixed, fixedVal
        .word COL3, TOwn, VOwn
        .byte Y0 + 2 * DY               ; the bypass (bypass.s)
        .word LBypass, SSystem, KProt
        .byte 2, 0
        .word COL1, TOff, 0
        .word COL2, TOn, VBypass
BtnDefs:
        .word BTN_X
        .byte LIST_TOP + 1, 46
        .word AddB
        .word BTN_X
        .byte LIST_TOP + 17, 46
        .word RemoveB

DiscLo: .byte <Disc1, <Disc2
DiscHi: .byte >Disc1, >Disc2
DiscY:  .byte DISC_Y, DISC_Y + 10
Disc1:  .byte "For applications you own a licensed copy of.", 0
Disc2:  .byte "GEOS is under copyright: your responsibility.", 0
DiscDlg:                        ; (DESIGN.md's wording, the user's of
        .byte DEF_DB_POS | 1    ; 2026-10-29; four lines that fit the box)
        .byte DBTXTSTR, TXT_LN_X, 16
        .word DiscA
        .byte DBTXTSTR, TXT_LN_X, 28
        .word DiscB
        .byte DBTXTSTR, TXT_LN_X, 40
        .word DiscC
        .byte DBTXTSTR, TXT_LN_X, 52
        .word DiscD
        .byte OK, DBI_X_2, DBI_Y_2
        .byte 0
DiscA:  .byte "For applications you own a", 0
DiscB:  .byte "licensed copy of. GEOS software", 0
DiscC:  .byte "is still under copyright; use is", 0
DiscD:  .byte "your own responsibility.", 0
AskDlg: .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askLine
        .byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5
AskMax: .byte 12
        .byte OK, 1, DBI_Y_2
        .byte CANCEL, DBI_X_2, DBI_Y_2
        .byte 0

ListT:          .byte BOLDON, "Per application", PLAINTEXT, 0
LSerial:        .byte "Serial", 0
LBypass:        .byte "Bypass", 0
TBoot:          .byte "boot disk", 0
TFixed:         .byte "fixed", 0
TOwn:           .byte "GeoUltra", 0
TOff:           .byte "off", 0
TOn:            .byte "on", 0
VOwn:           .byte .sprintf("%04X", SERIAL), 0      ; (GeoUltra's own, written
                                ; as a fixed number: the kernal needs no key)
VBypass:        .byte "bypass", 0
SSystem:        .byte "system", 0
SSerials:       .byte "serials", 0
SectT:          .byte "serials"
SECT_LEN        = * - SectT
KSerial:        .byte "serial", 0
KProt:          .byte "protection", 0
AddB:           .byte "add", 0
RemoveB:        .byte "remove", 0
AskSerT:        .byte BOLDON, "Serial number (4 hex digits):", PLAINTEXT, 0
AskClsT:        .byte BOLDON, "The application's class:", PLAINTEXT, 0
AskNumT:        .byte BOLDON, "Its serial (4 hex digits):", PLAINTEXT, 0
useT:           .byte "In use: XXXX (the rows: at the next start)", 0

sel:            .byte $FF
count:          .byte 0
at:             .byte 0
tmp:            .res 2
wasOn:          .byte 0
askLen:         .byte 0
fixedVal:       .res 6
input:          .res 18
key:            .res KEY_MAX + 1
shown:          .res SHOWN_MAX + 2
