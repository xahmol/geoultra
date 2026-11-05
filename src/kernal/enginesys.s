; File engine: system functions for gush (docs/FILE_ENGINE.md
; "Functions"; engine.s has the module list): module 75 FE_TURBO,
; FE_HOME, FE_SETTIME. An application cannot reach the turbo registers'
; owner (speed.s), the home folder (REU bank 1) or the Ultimate's clock
; command safely itself. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, turboWant, turboNow

HOME_PATH       = $0300         ; REU bank 1: the home folder (mount.s)
U_SET_TIME      = $27
                                ; (geos.inc: year, then month, day, hour,
                                ; minutes, seconds)

        .segment "OVL75"
        .scope Mod75

        jmp OvTurbo             ; entry 0
        jmp OvHome              ; entry 3
        jmp OvSetTime           ; entry 6

        .include "fereu.inc"
        .include "feult.inc"

TodSet: jsr OvlCall             ; (module 10: the CIA's clock from GEOS's)
        .byte 10, 0

; FE_TURBO: r2L = $FF: the U64's speed step; 0-15: that step set (also
; for the applications started later, speed.s: turboWant), with the
; badline stalls off above step 0. r1L = the step now. X = 0, or
; DEV_NOT_FOUND without turbo registers (an Ultimate II+; turbo off in
; SETTINGS.INI or the Ultimate's menu).
OvTurbo:
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        ldx #DEV_NOT_FOUND
        lda $D031
        cmp #$FF
        beq @out
        ldx #FE_BAD_PATH        ; (a step past 15)
        lda argR2
        cmp #$FF
        beq @get
        cmp #16
        bcs @out
        tay
        beq :+
        ora #$80                ; (badline stalls off)
:       sta turboWant
        sta turboNow
        sta $D031
        lda $D030
        ora #$01
        sta $D030
@get:   lda $D031
        and #$0F
        sta argR1
        lda #0
        sta argR1+1
        tax
@out:   pla
        sta CPU_PORT
        plp
        rts

; FE_HOME: r1 = a buffer of 32 bytes: the home folder's path ("/USB0/
; GEOULTRA/", "/" at its end; mount.s). X = 0.
OvHome: lda argR1
        sta r0L
        lda argR1+1
        sta r0H
        lda #<HOME_PATH
        sta r1L
        lda #>HOME_PATH
        sta r1H
        lda #32
        sta r2L
        lda #0
        sta r2H
        ldy #REU_FETCH
        jsr ReuOp
        ldx #0
        rts

; FE_SETTIME (after the caller set GEOS's date and time): the CIA's
; time-of-day clock, which GEOS's time follows, set from it (module 10's
; TodSet), then the Ultimate's clock (year 80-99: 19xx, else 20xx). X =
; 0, or FE_ULTIMATE ("98": setting the clock is off in the Ultimate's
; menu, UltiDOS: Allow SetDate).
OvSetTime:
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        jsr TodSet
        pla
        sta CPU_PORT
        plp
        lda #U_SET_TIME
        jsr UBegin
        lda year
        cmp #80
        bcs :+
        adc #100                ; (C clear)
:       jsr UPut                ; year - 1900
        ldx #1
@field: lda year,x
        stx feM
        jsr UPut
        ldx feM
        inx
        cpx #6
        bne @field
        jsr UNoData
        jmp UExec

        .endscope
