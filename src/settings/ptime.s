; GeoUltra Settings: the Time page (overlay 4, ovl.s; docs/SETTINGS.md,
; "S3 decisions"): SETTINGS.INI's [time] as the kernal reads it
; (enginentp.s modules 77-79): ntp= the server, offset= seconds from UTC
; (signed), summer=eu or off (the EU's rule, module 79); "now" sets the
; clocks from the server (FE_NTP, with the settings written first: the
; kernal reads them from the file); the date and time by hand
; (FE_SETTIME). The zone in quarter hours from UTC-12:00 to UTC+14:00.
; Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress, ButtonDraw, OnButton
        .import IniFind, IniSet, IniDel, dirty, NoRoom, FileEngine, Write
        .export Ov_TimeDraw, Ov_TimePress

        .segment "ZEROPAGE"

askText:        .res 2          ; Ask: its question and a line under the
askHint:        .res 2          ; input (DBVARSTR: zero page)

        .segment "OV4"

; Ov_TimeDraw: the page: the server, "now", the zone, summer time, the
; date and time.
Ov_TimeDraw:
        jsr ReadZone
        lda #<Rows
        ldx #>Rows
        jsr ChoiceDraw
        ldx #0                  ; the labels
@label: stx at
        lda LabelLo,x
        sta r0L
        lda LabelHi,x
        sta r0H
        lda #<LABEL_X
        sta r11L
        lda #>LABEL_X
        sta r11H
        lda LabelY,x
        sta r1H
        jsr PutString
        ldx at
        inx
        cpx #LABELS
        bcc @label
        ldx #0                  ; the buttons
@btn:   stx at
        lda BtnLo,x
        pha
        lda BtnHi,x
        tax
        pla
        jsr ButtonDraw
        ldx at
        inx
        cpx #BUTTONS
        bcc @btn
        lda #<NowNote
        sta r0L
        lda #>NowNote
        sta r0H
        lda #<(NOW_X + NOW_W + 6)
        sta r11L
        lda #>(NOW_X + NOW_W + 6)
        sta r11H
        lda #NOW_Y + 9
        sta r1H
        jsr PutString
        jsr ServerDraw
        jsr ZoneDraw
        jmp DateDraw

; Ov_TimePress: a click: the summer row, the server's box, the buttons.
Ov_TimePress:
        lda #<Rows
        ldx #>Rows
        jsr ChoicePress
        jsr OnServer
        bcs :+
        jmp EditServer
:       lda #<Minus
        ldx #>Minus
        jsr OnButton
        bcs :+
        lda zone
        cmp #ZONE_MIN
        beq @end
        dec zone
        jmp NewZone
:       lda #<Plus
        ldx #>Plus
        jsr OnButton
        bcs :+
        lda zone
        cmp #ZONE_MAX
        beq @end
        inc zone
        jmp NewZone
:       lda #<Now
        ldx #>Now
        jsr OnButton
        bcs :+
        jmp NowNtp
:       lda #<SetBtn
        ldx #>SetBtn
        jsr OnButton
        bcs @end
        jmp EditDate
@end:   rts

; --- the server

; ServerDraw: the server's box cleared and framed, ntp='s value in it
; (or "none").
ServerDraw:
        jsr ServerBox
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda #$FF
        jsr FrameRectangle
        jsr ReadServer          ; (buf)
        lda #<buf
        sta r0L
        lda #>buf
        sta r0H
        lda buf
        bne :+
        lda #<NoneText
        sta r0L
        lda #>NoneText
        sta r0H
:       lda #<(BOX_X + 3)
        sta r11L
        lda #>(BOX_X + 3)
        sta r11H
        lda #SERVER_Y - 1       ; (its cells inside the frame)
        sta r1H
        lda #<(BOX_X + BOX_W - 3) ; (clipped at the box)
        sta rightMargin
        lda #>(BOX_X + BOX_W - 3)
        sta rightMargin+1
        jsr PutString
        lda #<SCREEN_RIGHT
        sta rightMargin
        lda #>SCREEN_RIGHT
        sta rightMargin+1
        rts

; ReadServer: buf = ntp='s value (empty: none), SERVER_MAX at most.
ReadServer:
        lda #0
        sta buf
        jsr NtpKey
        jsr IniFind
        bcs @end
        cmp #SERVER_MAX
        bcc :+
        lda #SERVER_MAX
:       tay
        lda #0
        sta buf,y
@ch:    dey
        bmi @end
        lda (r2),y
        sta buf,y
        jmp @ch
@end:   rts

; EditServer: the server typed (the input dialog, its text as it is);
; an empty one takes ntp= out.
EditServer:
        jsr ReadServer
        lda #<ServerAsk
        sta askText
        lda #>ServerAsk
        sta askText+1
        lda #<ServerHint
        sta askHint
        lda #>ServerHint
        sta askHint+1
        jsr Ask
        bcs @end
        jsr NtpKey
        lda buf
        bne :+
        jsr IniDel
        jmp @done
:       lda #<buf
        sta r2L
        lda #>buf
        sta r2H
        jsr IniSet
        bcc @done
        jmp NoRoom
@done:  lda #1
        sta dirty
        jmp ServerDraw
@end:   rts

; OnServer: C clear when the pointer is in the server's box.
OnServer:
        lda mouseYPos
        cmp #SERVER_Y - 9
        bcc @no
        cmp #SERVER_Y + 3
        bcs @no
        lda mouseXPos+1
        bne @hi
        lda mouseXPos
        cmp #BOX_X
        bcc @no
@yes:   clc
        rts
@hi:    lda mouseXPos           ; (x 256-319: up to the box's end)
        cmp #<(BOX_X + BOX_W)
        bcc @yes
@no:    sec
        rts

; ServerBox: r2-r4 = the server's box.
ServerBox:
        lda #SERVER_Y - 9
        sta r2L
        lda #SERVER_Y + 2
        sta r2H
        lda #<BOX_X
        sta r3L
        lda #>BOX_X
        sta r3H
        lda #<(BOX_X + BOX_W - 1)
        sta r4L
        lda #>(BOX_X + BOX_W - 1)
        sta r4H
        rts

; NowNtp: the settings written (the kernal reads the server, the zone
; and summer time from the file), then the clocks from the server; the
; date drawn again, or the failure said.
NowNtp: jsr Write
        bcs @end
        lda #0
        sta r0L
        sta r0H
        lda #FE_NTP
        jsr FileEngine
        txa
        beq :+
        lda #<NtpFail
        sta r0L
        lda #>NtpFail
        sta r0H
        jsr DoDlgBox
:       jmp DateDraw
@end:   rts

; --- the zone

; ReadZone: zone = offset='s seconds in quarter hours (rounded; none:
; 0), within ZONE_MIN to ZONE_MAX.
ReadZone:
        lda #0
        sta zone
        sta neg
        sta num
        sta num+1
        jsr OffKey
        jsr IniFind
        bcc :+
        rts                     ; (none: UTC)
:       sta len
        ldy #0
        lda (r2),y
        cmp #'-'
        bne :+
        inc neg
        iny
        bne @dig
:       cmp #'+'
        bne @dig
        iny
@dig:   cpy len
        bcs @quarters
        lda (r2),y
        sec
        sbc #'0'
        cmp #10
        bcs @quarters
        pha                     ; num = num * 10 + the digit (16 bits:
        lda num                 ; enough for 14 hours, 50400 s)
        asl a
        sta tmp
        lda num+1
        rol a
        sta tmp+1
        asl num
        rol num+1
        asl num
        rol num+1
        asl num
        rol num+1
        lda num
        clc
        adc tmp
        sta num
        lda num+1
        adc tmp+1
        sta num+1
        pla
        clc
        adc num
        sta num
        bcc :+
        inc num+1
:       iny
        bne @dig
@quarters:
        lda num                 ; quarters: num / 900, rounded
        sec
        sbc #<450
        tax
        lda num+1
        sbc #>450
        bcc @sign
@q:     stx num
        sta num+1
        inc zone
        lda num
        sec
        sbc #<900
        tax
        lda num+1
        sbc #>900
        bcs @q
@sign:  lda zone
        cmp #ZONE_MAX + 1
        bcc :+
        lda #ZONE_MAX
:       ldx neg
        beq :+
        cmp #ZONE_WEST + 1
        bcc @neg
        lda #ZONE_WEST
@neg:   eor #$FF
        clc
        adc #1
:       sta zone
@end:   rts

; NewZone: offset= the zone's seconds (zone * 900) in the text, the zone
; drawn again.
NewZone:
        ldx #0                  ; |zone| * 900 in num, the sign in buf
        lda zone
        bpl :+
        eor #$FF
        clc
        adc #1
        pha
        lda #'-'
        sta buf
        inx
        pla
:       sta tmp
        lda #0
        sta num
        sta num+1
        ldy tmp
@mul:   dey
        bmi @text
        lda num
        clc
        adc #<900
        sta num
        lda num+1
        adc #>900
        sta num+1
        jmp @mul
@text:  jsr Decimal             ; (num into buf from X)
        lda #0
        sta buf,x
        jsr OffKey
        lda #<buf
        sta r2L
        lda #>buf
        sta r2H
        jsr IniSet
        bcc :+
        jmp NoRoom
:       lda #1
        sta dirty
; ZoneDraw: "UTC+hh:mm" between the zone's buttons.
ZoneDraw:
        lda #0
        jsr SetPattern
        lda #ZONE_Y - 9
        sta r2L
        lda #ZONE_Y + 2
        sta r2H
        lda #<ZONE_X
        sta r3L
        lda #>ZONE_X
        sta r3H
        lda #<(PLUS_X - 2)
        sta r4L
        lda #>(PLUS_X - 2)
        sta r4H
        jsr Rectangle
        ldx #3                  ; "UTC" and the sign
@utc:   lda Utc,x
        sta buf,x
        dex
        bpl @utc
        lda zone
        bpl :+
        lda #'-'
        sta buf + 3
        lda zone
        eor #$FF
        clc
        adc #1
:       sta tmp                 ; hours: |zone| / 4, minutes (|zone| & 3) * 15
        lsr a
        lsr a
        ldx #4
        jsr Two
        lda #':'
        sta buf,x
        inx
        lda tmp
        and #3
        tay
        lda Quarter,y
        jsr Two
        lda #0
        sta buf,x
        lda #<buf
        sta r0L
        lda #>buf
        sta r0H
        lda #<ZONE_X
        sta r11L
        lda #>ZONE_X
        sta r11H
        lda #ZONE_Y
        sta r1H
        jmp PutString

; --- the date and time

; DateDraw: GEOS's date and time, "2026-11-12 19:05".
DateDraw:
        lda #0
        jsr SetPattern
        lda #DATE_Y - 9
        sta r2L
        lda #DATE_Y + 2
        sta r2H
        lda #<DATE_X
        sta r3L
        lda #>DATE_X
        sta r3H
        lda #<(SET_X - 2)
        sta r4L
        lda #>(SET_X - 2)
        sta r4H
        jsr Rectangle
        jsr DateText
        lda #<buf
        sta r0L
        lda #>buf
        sta r0H
        lda #<DATE_X
        sta r11L
        lda #>DATE_X
        sta r11H
        lda #DATE_Y
        sta r1H
        jmp PutString

; DateText: buf = GEOS's clock as "YYYY-MM-DD HH:MM" (years 80-99:
; 19xx, else 20xx).
DateText:
        ldx #0
        lda year
        ldy #20
        cmp #80
        bcc :+
        ldy #19
:       pha
        tya
        jsr Two
        pla
        jsr Two
        lda #'-'
        sta buf,x
        inx
        lda month
        jsr Two
        lda #'-'
        sta buf,x
        inx
        lda day
        jsr Two
        lda #' '
        sta buf,x
        inx
        lda hour
        jsr Two
        lda #':'
        sta buf,x
        inx
        lda minutes
        jsr Two
        lda #0
        sta buf,x
        rts

; EditDate: the date and time typed as "YYYY-MM-DD HH:MM" (shown as it
; is now); a valid one into GEOS's clock (seconds 0) and the Ultimate's
; and the CIA's (FE_SETTIME); else said.
EditDate:
        jsr DateText
        lda #<DateAsk
        sta askText
        lda #>DateAsk
        sta askText+1
        lda #<DateHint
        sta askHint
        lda #>DateHint
        sta askHint+1
        jsr Ask
        bcs @end
        ldx #0                  ; the fields: digits at fixed places
@field: lda FieldAt,x
        tay
        jsr Num2
        bcs @bad
        cmp FieldLow,x
        bcc @bad
        cmp FieldHigh,x
        bcs @bad
        sta new,x
        inx
        cpx #FIELDS
        bcc @field
        ldx #SEPS - 1           ; the separators
@sep:   ldy SepAt,x
        lda buf,y
        cmp SepChar,x
        bne @bad
        dex
        bpl @sep
        lda new                 ; the century: 19 with 80-99, 20 with 0-79
        ldy new + 1
        cmp #19
        bne :+
        cpy #80
        bcc @bad
        bcs @set
:       cmp #20
        bne @bad
        cpy #80
        bcs @bad
@set:   php
        sei
        ldx #FIELDS - 2         ; year (its last two digits) .. minutes
@put:   lda new + 1,x
        sta year,x
        dex
        bpl @put
        lda #0
        sta seconds
        plp
        lda #FE_SETTIME
        jsr FileEngine          ; (the Ultimate refusing: GEOS's clock set)
        jmp DateDraw
@bad:   lda #<DateFail
        sta r0L
        lda #>DateFail
        sta r0H
        jmp DoDlgBox
@end:   rts

; Num2: A = the two digits at buf + Y; C set when they are not digits.
Num2:   lda buf,y
        jsr Digit
        bcs @end
        sta tmp
        asl a                   ; * 10
        asl a
        adc tmp
        asl a
        sta tmp
        lda buf + 1,y
        jsr Digit
        bcs @end
        adc tmp
        clc
@end:   rts

; Digit: A from "0"-"9" to 0-9, C clear; C set when not a digit.
Digit:  sec
        sbc #'0'
        cmp #10
        rts

; --- shared

; Ask: the input dialog with the text at askText, buf as its line
; (shown as it is, edited there). C set when cancelled.
Ask:    lda #<buf
        sta r5L
        lda #>buf
        sta r5H
        lda #<AskDlg
        sta r0L
        lda #>AskDlg
        sta r0H
        jsr DoDlgBox
        lda r0L
        cmp #DBGETSTRING        ; (RETURN ends it as OK)
        beq @ok
        cmp #OK
        beq @ok
        sec
        rts
@ok:    clc
        rts

; Two: A (0-99) as two digits into buf + X; X past them.
Two:    ldy #'0' - 1
@tens:  iny
        sec
        sbc #10
        bcs @tens
        adc #'0' + 10
        pha
        tya
        sta buf,x
        inx
        pla
        sta buf,x
        inx
        rts

; Decimal: num (16 bits) as decimal digits into buf + X, no leading
; zeros; X past them.
Decimal:
        lda #0
        sta lead
        ldy #3
@pow:   lda #'0'
        sta tmp
@sub:   lda num
        sec
        sbc PowLo,y
        sta tmp+1
        lda num+1
        sbc PowHi,y
        bcc @digit
        sta num+1
        lda tmp+1
        sta num
        inc tmp
        bne @sub
@digit: lda tmp
        cmp #'0'
        bne @out
        lda lead                ; (no leading zeros)
        beq @next
        lda tmp
@out:   sta buf,x
        inx
        sta lead
@next:  dey
        bpl @pow
        lda num                 ; the ones
        ora #'0'
        sta buf,x
        inx
        rts

; NtpKey, OffKey: r0 = "time", r1 = "ntp" or "offset".
NtpKey: lda #<KNtp
        ldx #>KNtp
        bne Keys
OffKey: lda #<KOff
        ldx #>KOff
Keys:   sta r1L
        stx r1H
        lda #<STime
        sta r0L
        lda #>STime
        sta r0H
        rts

; --- layout and data

month           = year + 1      ; GEOS's clock (geos.inc: year)
day             = year + 2
hour            = year + 3
minutes         = year + 4
seconds         = year + 5
LABEL_X         = PAGE_LEFT + 2
SERVER_Y        = PAGE_TOP + 20 ; the rows' baselines
NOW_Y           = SERVER_Y + 9  ; ("now": a button's top)
ZONE_Y          = SERVER_Y + 44
SUMMER_Y        = ZONE_Y + 20
DATE_Y          = SUMMER_Y + 24
BOX_X           = 150           ; the server's box
BOX_W           = 156
SERVER_MAX      = 40            ; a server's name, at most
NOW_X           = 150
NOW_W           = 36
MINUS_X         = 150
ZONE_X          = MINUS_X + 18
PLUS_X          = 230
DATE_X          = 150
SET_X           = 252
ZONE_WEST       = 48            ; UTC-12:00, in quarter hours
ZONE_MIN        = <-ZONE_WEST
ZONE_MAX        = 56            ; UTC+14:00
LABELS          = 4
BUTTONS         = 4
FIELDS          = 6             ; century, year, month, day, hour, minutes
SEPS            = 5             ; "-", "-", " ", ":" and the line's end

Rows:   .byte 1
        .byte SUMMER_Y                          ; summer time
        .word LSummer, STime, KSummer
        .byte 2, 1
        .word 150, TEu, VEu
        .word 216, TOff, VOff

LabelLo:        .byte <LServer, <LClock, <LZone, <LDate
LabelHi:        .byte >LServer, >LClock, >LZone, >LDate
LabelY:         .byte SERVER_Y, NOW_Y + 9, ZONE_Y, DATE_Y
BtnLo:          .byte <Now, <Minus, <Plus, <SetBtn
BtnHi:          .byte >Now, >Minus, >Plus, >SetBtn

Now:    .word NOW_X
        .byte NOW_Y, NOW_W
        .word TNow
Minus:  .word MINUS_X
        .byte ZONE_Y - 9, 14
        .word TMinus
Plus:   .word PLUS_X
        .byte ZONE_Y - 9, 14
        .word TPlus
SetBtn: .word SET_X
        .byte DATE_Y - 9, 50
        .word TSet

AskDlg: .byte DEF_DB_POS | 1
        .byte DBVARSTR, TXT_LN_X, TXT_LN_1_Y + 6, askText
        .byte DBGETSTRING, TXT_LN_X, TXT_LN_2_Y, r5, SERVER_MAX
        .byte DBVARSTR, TXT_LN_X, TXT_LN_4_Y, askHint
        .byte OK, 1, DBI_Y_2
        .byte CANCEL, DBI_X_2, DBI_Y_2
        .byte 0
NtpFail:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word NtpText
        .byte OK, 1, DBI_Y_2
        .byte 0
DateFail:
        .byte DEF_DB_POS | 1
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_1_Y + 6
        .word DateBad
        .byte DBTXTSTR, TXT_LN_X, TXT_LN_2_Y + 6
        .word DateHint
        .byte OK, 1, DBI_Y_2
        .byte 0

FieldAt:        .byte 0, 2, 5, 8, 11, 14 ; "YYYY-MM-DD HH:MM": each field's
FieldLow:       .byte 19, 0, 1, 1, 0, 0  ; place, lowest and one past its
FieldHigh:      .byte 21, 100, 13, 32, 24, 60 ; highest
SepAt:          .byte 4, 7, 10, 13, 16
SepChar:        .byte "-- :", 0          ; (and the line's end)
PowLo:          .byte <10, <100, <1000, <10000
PowHi:          .byte >10, >100, >1000, >10000
Quarter:        .byte 0, 15, 30, 45
Utc:            .byte "UTC+"

STime:          .byte "time", 0
KNtp:           .byte "ntp", 0
KOff:           .byte "offset", 0
KSummer:        .byte "summer", 0
LServer:        .byte "Server", 0
LClock:         .byte "Clock", 0
LZone:          .byte "Zone", 0
LSummer:        .byte "Summer", 0
LDate:          .byte "Date", 0
TEu:            .byte "EU rule", 0
TOff:           .byte "off", 0
VEu:            .byte "eu", 0
VOff:           .byte "off", 0
TNow:           .byte "now", 0
TMinus:         .byte "-", 0
TPlus:          .byte "+", 0
TSet:           .byte "set...", 0
NoneText:       .byte "none", 0
NowNote:        .byte "from the server", 0
ServerAsk:      .byte BOLDON, "Time server:", PLAINTEXT, 0
DateAsk:        .byte BOLDON, "Date and time:", PLAINTEXT, 0
DateHint:       .byte "as YYYY-MM-DD HH:MM", 0
ServerHint:     .byte "for example pool.ntp.org", 0
NtpText:        .byte BOLDON, "No time from the server.", PLAINTEXT, 0
DateBad:        .byte BOLDON, "Not a date.", PLAINTEXT, 0

; Scratch (overlay data: fetched anew with the overlay, when the page is
; drawn)
zone:           .byte 0         ; quarter hours from UTC (signed)
at:             .byte 0
neg:            .byte 0
len:            .byte 0
lead:           .byte 0
num:            .word 0
tmp:            .word 0
new:            .res FIELDS     ; EditDate's fields
buf:            .res SERVER_MAX + 1
