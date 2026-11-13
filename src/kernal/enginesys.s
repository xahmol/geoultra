; File engine: system functions for gush (docs/FILE_ENGINE.md
; "Functions"; engine.s has the module list): module 75 FE_TURBO,
; FE_HOME, FE_SETTIME, FE_REBOOT. An application cannot reach the turbo
; registers' owner (speed.s), the home folder (REU bank 1), the
; Ultimate's clock command or the write-back safely itself. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import guClockFresh    ; (info.s, $C0FB)
        .import OvlCall, SysRAMOp, turboWant, turboNow
        .import WriteBackNow, hibState, drvFlags
        .include "drvflags.inc"

U_SET_TIME      = $27           ; (no longer sent: OvSetTime)
U_TARGET_CTRL   = 4             ; the control target: REBOOT (the C64,
CTRL_REBOOT     = $06           ; cartridge and all)
                                ; (geos.inc: year, then month, day, hour,
                                ; minutes, seconds)

        .segment "OVL75"
        .scope Mod75

        jmp OvTurbo             ; entry 0
        jmp OvHome              ; entry 3
        jmp OvSetTime           ; entry 6
        jmp OvReboot            ; entry 9

        .include "fereu.inc"
        .include "feult.inc"
        .include "fework.inc"
        .include "fehome.inc"

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
; TodSet). X = 0. The Ultimate's own clock is no longer written (the
; user, 2026-11-13): its firmware keeps it right with SNTP in its own
; zone, and its SET_TIME (DOS $27) stored an hour less than it was given
; (measured on the U64, 3.15a, zones Western Europe and UK), so every
; write set it back an hour. The cold start takes the Ultimate's time as
; local time (module 10, RtcClock).
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
        ldx #0                  ; (set now: no adjust= to add any more)
        stx guClockFresh
        rts

; FE_REBOOT: every drive written back, the hibernated session dropped
; (HIBERNAT.BIN in the home folder deleted: the boot would resume it),
; then the C64 restarted through the Ultimate (GeoUltra boots afresh).
; Back only when a drive could not be written back (FE_ULTIMATE), or
; without an Ultimate (DEV_NOT_FOUND). The write-back uses the overlay
; scratch, the engine's work area, as in FE_UMOUNT (enginemount.s): kept
; at FE_WSAVE meanwhile, a hibernation it would start held back.
OvReboot:
        lda hibState
        pha
        and #$BF
        sta hibState
        ldy #REU_STASH
        jsr WorkOp
        jsr WriteBackNow
        ldy #REU_FETCH
        jsr WorkOp
        pla
        sta hibState
        ldx #3                  ; a drive still changed: no reboot
        lda #0
@dirty: ora drvFlags,x
        dex
        bpl @dirty
        and #F_DIRTY
        beq :+
        ldx #FE_ULTIMATE
        rts
:       jsr Home                ; the session file away (none: fine)
        txa
        bne @end
        lda #U_DELETE
        jsr UBegin
        ldx #0
@name:  lda HibName,x
        beq :+
        jsr UPut
        inx
        bne @name
:       jsr UNoData
        jsr UExec
        lda #CTRL_REBOOT        ; (does not come back)
        jsr UBegin
        lda #U_TARGET_CTRL
        sta uCmd
        jsr UNoData
        jsr UExec
@end:   rts

HibName:        .byte "HIBERNAT.BIN", 0

        .endscope
