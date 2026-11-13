; GEOS's clock moved by minutes, over midnight, months and years: shared
; by Settings' Time page (ptime.s) and the desktop (inifile.s, [time]
; adjust= after a cold start). Own code. The includer includes geos.inc
; first (year: GEOS's clock), puts this in a code segment, defines delta
; (a word: the minutes, signed) and sets CLOCK_OV4 when its variables
; belong in overlay segment "OV4" (else BSS).

.ifndef month                   ; GEOS's clock (geos.inc: year; the
month           = year + 1      ; desktop's desktop.inc names them too)
day             = year + 2
hour            = year + 3
minutes         = year + 4
.endif

; ClockShift: GEOS's clock (year .. minutes) moved by delta minutes
; (signed), over midnight into the next day or the one before (months,
; leap years: right for 2000-2099). The caller sets the CIA's from it
; (FE_SETTIME). Destroys A, X.
ClockShift:
        php
        sei
        lda hour                ; t = hour * 60 + minutes + delta
        sta tL
        lda #0
        sta tH
        ldx #5                  ; hour * 60 = hour * 64 - hour * 4
@x64:   asl tL
        rol tH
        dex
        bpl @x64
        lda hour
        asl a
        asl a
        sta tmp4
        lda tL
        sec
        sbc tmp4
        sta tL
        lda tH
        sbc #0
        sta tH
        lda tL
        clc
        adc minutes
        sta tL
        lda tH
        adc #0
        sta tH
        lda tL
        clc
        adc delta
        sta tL
        lda tH
        adc delta+1
        sta tH
@neg:   lda tH                  ; below 0: the day before
        bpl @over
        lda tL
        clc
        adc #<1440
        sta tL
        lda tH
        adc #>1440
        sta tH
        jsr DayDown
        jmp @neg
@over:  lda tL                  ; 1440 or more: the next day
        cmp #<1440
        lda tH
        sbc #>1440
        bcc @split
        sta tH
        lda tL
        sec
        sbc #<1440
        sta tL
        jsr DayUp
        jmp @over
@split: ldx #$FF                ; hour = t / 60, minutes = t mod 60
@div:   inx
        lda tL
        sec
        sbc #60
        sta tL
        lda tH
        sbc #0
        sta tH
        bcs @div
        lda tL
        adc #60
        sta minutes
        stx hour
        plp
        rts

; DayUp, DayDown: the date a day on or back.
DayUp:  inc day
        jsr MonthDays
        cmp day
        bcs @end
        lda #1
        sta day
        inc month
        lda month
        cmp #13
        bcc @end
        lda #1
        sta month
        inc year
@end:   rts
DayDown:
        dec day
        bne @end
        dec month
        bne :+
        lda #12
        sta month
        dec year
:       jsr MonthDays
        sta day
@end:   rts

; MonthDays: A = the days of month (in year: February 29 when the year
; divides by 4, right for 2000-2099).
MonthDays:
        ldx month
        lda ClockDays - 1,x
        cpx #2
        bne @end
        lda year
        and #3
        bne :+
        lda #29
        rts
:       lda #28
@end:   rts

ClockDays:      .byte 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

        .pushseg
.ifdef CLOCK_OV4
        .segment "OV4"
.else
        .segment "BSS"
.endif
tL:             .res 1          ; ClockShift: the time of day in minutes
tH:             .res 1
tmp4:           .res 1          ; hour * 4
        .popseg
