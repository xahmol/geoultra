; Clock: date and time from the CIA 1 time-of-day clock, updated from
; MainLoop, with the TOD alarm. Written from the HG2G2022 descriptions of
; year .. seconds, alarmSetFlag and alarmTmtVector; behaviour details (the
; date advanced when the clock passes midnight, the 12-hour TOD read as
; 0-23, alarmSetFlag = $4A when the alarm goes off, then the vector or
; the beeps counted in its low six bits) follow the reassembled GEOS 2.0
; kernal, mist64/geos kernal/time/time1.s, read as behaviour reference
; only. Own code, own beep. The date starts at the build date until the
; Ultimate's real-time clock is read (docs/DESIGN.md, "Clock").

        .include "geos.inc"
        .include "hw.inc"

        .export ClockInit, TodMode, TimeUpdate, AlarmTick

month           = year + 1
day             = year + 2
hour            = year + 3
minutes         = year + 4
seconds         = year + 5
alarmSetFlag    = year + 6
todTenths       = $DC08
todSeconds      = $DC09
todMinutes      = $DC0A
todHours        = $DC0B
cia1CtrlA       = $DC0E
cia1CtrlB       = $DC0F
ALARM_BIT       = $04           ; CIA 1 interrupt control: TOD alarm
sid             = $D400

        .segment "KEXT"                 ; $9A80: see ARCHITECTURE.md

todFreq:        .byte 0         ; $80: 50 Hz (PAL), 0: 60 Hz
hours:          .byte 0
alarmWarn:      .byte 0         ; frames until the next beep

; ClockInit (cold start, I/O on): 50 or 60 Hz for the TOD by the number of
; raster lines (PAL has lines past 287), the TOD started at midnight, the
; build date.
ClockInit:
@low:   bit vicCtrl1            ; a line below 256 ...
        bmi @low
@high:  bit vicCtrl1            ; ... then line 256
        bpl @high
@scan:  lda vicRaster
        cmp #$20                ; line 288 or later: PAL
        bcs @pal
        bit vicCtrl1
        bmi @scan
        lda #0
        beq @freq
@pal:   lda #$80
@freq:  sta todFreq
        jsr TodMode
        lda #0                  ; writes set the clock, not the alarm
        sta cia1CtrlB
        lda #$92                ; 12 AM. Writing the hours stops the clock,
        sta todHours            ; the tenths start it. A 6526 flips AM/PM
        bit todHours            ; when 12 is written (VICE does too): $92
        bpl @am                 ; becomes 12 AM; a CIA without the quirk
        lda #$12                ; keeps PM, then $12 is written
        sta todHours
@am:
        lda #0
        sta todMinutes
        sta todSeconds
        sta todTenths
        lda #BUILD_YEAR
        sta year
        lda #BUILD_MONTH
        sta month
        lda #BUILD_DAY
        sta day
        rts

; TodMode (I/O on): the TOD input frequency in CIA 1 control register A.
TodMode:
        lda cia1CtrlA
        and #$7F
        ora todFreq
        sta cia1CtrlA
        rts

; TimeUpdate (MainLoop): hour, minutes, seconds from the TOD; the next day
; after midnight; the alarm. Destroys A, X, Y.
TimeUpdate:
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda cia1CtrlB
        and #$7F
        sta cia1CtrlB
        lda hour                ; was afternoon, TOD now morning: next day
        cmp #12
        bcc @read
        bit todHours
        bmi @read
        jsr NextDay
@read:  lda todHours            ; latches the TOD until the tenths are read
        sta hours
        and #$1F
        jsr FromBCD
        cmp #12
        bne @pm
        lda #0
@pm:    bit hours
        bpl @am
        clc
        adc #12
@am:    sta hour
        lda todMinutes
        jsr FromBCD
        sta minutes
        lda todSeconds
        jsr FromBCD
        sta seconds
        lda todTenths
        ldx cia1Icr             ; X = interrupt flags (reading clears them)
        pla
        sta CPU_PORT
        bit alarmSetFlag
        bpl @beep
        txa
        and #ALARM_BIT
        beq @end
        lda #$4A                ; alarm: the vector, else ten beeps
        sta alarmSetFlag
        lda alarmTmtVector
        ora alarmTmtVector+1
        beq @beep
        plp
        jmp (alarmTmtVector)
@beep:  bit alarmSetFlag
        bvc @end
        jsr Beep
@end:   plp
        rts

; NextDay: day + 1, then month and year (leap years every fourth year).
NextDay:
        ldy month
        lda daysInMonth-1,y
        cpy #2
        bne @last
        tax
        lda year
        and #3
        bne @feb
        inx
@feb:   txa
@last:  cmp day
        beq @month
        inc day
        rts
@month: ldy #1
        sty day
        inc month
        lda month
        cmp #13
        bne @end
        sty month
        inc year
        lda year
        cmp #100
        bne @end
        dey
        sty year
@end:   rts

daysInMonth:
        .byte 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

; FromBCD: A (BCD) -> binary. Destroys X.
FromBCD:
        pha
        lsr
        lsr
        lsr
        lsr
        tax
        pla
        and #$0F
@tens:  dex
        bmi @end
        clc
        adc #10
        bne @tens
@end:   rts

; Beep: one alarm beep every BEEP_GAP frames while the low six bits of
; alarmSetFlag count down; the last one releases the note.
BEEP_GAP        = 30
Beep:   lda alarmWarn
        bne @end
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda #$0F                ; volume
        sta sid + $18
        lda #$00
        sta sid + 0             ; voice 1: about 1.5 kHz
        lda #$60
        sta sid + 1
        lda #$0A                ; quick attack, short decay
        sta sid + 5
        lda #$00
        sta sid + 6
        ldx #$10                ; triangle, gate off: restart the note
        stx sid + 4
        lda alarmSetFlag
        and #$3F
        beq @off
        ldx #$11                ; triangle, gate on
@off:   stx sid + 4
        pla
        sta CPU_PORT
        lda #BEEP_GAP
        sta alarmWarn
        dec alarmSetFlag
@end:   rts

; AlarmTick (interrupt level): count down to the next beep.
AlarmTick:
        lda alarmWarn
        beq @end
        dec alarmWarn
@end:   rts
