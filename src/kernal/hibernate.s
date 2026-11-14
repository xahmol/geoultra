; Hibernation (docs/DESIGN.md, "Hibernation"; docs/ARCHITECTURE.md): the
; running session to GEOULTRA/HIBERNAT.BIN on the Ultimate and back.
;
; Suspend (overlay module 8, entry 0): the drives are written back first;
; the chip state goes into RAM variables, Snap copies all 64 KB of RAM to
; REU bank HIB_RAM; then the file gets bank 1 (system, with a header at
; $0400), bank HIB_RAM, bank 18 (desk accessory swap) and banks 192-199
; (the applications' REU). HibResume (entry 3, from the cold start after
; the mounts): with a valid file (signature, the same kernal, the same
; mount table) and C= not held, the banks are loaded back, the file is
; deleted (a later unplanned power-off must not bring back an old state)
; and Resume copies the RAM back in one DMA. The CPU then continues in
; Resume, whose bytes are the same in the snapshot (same kernal), takes
; the saved stack pointer and returns from Snap a second time, with A = 1:
; Suspend's resumed path restores the chips and returns to its caller.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"

        .export HibSuspend, HibResumeOvl, Resume, hibSP, hibResumed, HibTick
        .export hibState, RtcClockOvl, hibLimit, RtcCheck
        .import guClockFresh    ; (info.s, $C0FB)
        .import WbTick, wbPending
        .import OvlCall, uciPresent, WriteBackNow, TodMode, WbCheck, turboNow
        .import Begin, Put, Simple, cmdLen, dmaCmd, DmaGo
        .import imgFlags, TaskMany, TaskInit

WR_VER_ERR      = $25           ; (as the disk driver: write failed)

hour            = $8519         ; GEOS 2.0's time: hour, minutes, seconds
HIB_RAM         = 19            ; REU bank of the RAM snapshot (task slot 1)
HIB_SCRATCH     = 20            ; checks at resume
SYS_BANK        = 1
HEADER          = $0400         ; in bank 1: signature, fingerprint
cmdBuf          = $9FB0
TARGET_DOS      = $01
DOS_OPEN        = $02
DOS_CLOSE       = $03
DOS_SEEK        = $06
DOS_DELETE      = $09
DOS_CD          = $11
DOS_LOAD_REU    = $21
DOS_SAVE_REU    = $22
DOS_GET_TIME    = $26
REU_STASH_FF00  = $80           ; execute on a write to $FF00, C64 -> REU
BUF             = $4000         ; cold start: free (TEXT of mount.s)

        .segment "DATA"

hibSP:          .byte 0         ; stack pointer inside Snap
hibResumed:     .byte 0         ; 1 after Resume
hibState:       .byte 0         ; bit 7: changed since the last save,
                                ; bit 6: a save is due (module 1)
hibIdle:        .word 0         ; frames without input since a change

        .segment "CODE"

hibLimit:       .byte IDLE_HI       ; SETTINGS.INI [system] hibernate=

HibSuspend:                     ; X = 0 or an error
        jsr OvlCall
        .byte 8, 0
HibResumeOvl:                   ; returns only when nothing is resumed
        jsr OvlCall
        .byte 9, 0
RtcClockOvl:                    ; (module 10)
        jsr OvlCall
        .byte 10, 3

; RtcCheck (MainLoop, then WbCheck): while the Ultimate's clock was not
; set yet (RtcClock), it is asked again once a minute.
RtcCheck:
        bit rtcRetry
        bpl @end
        lda $851A               ; minutes
        cmp rtcMinute
        beq @end
        sta rtcMinute
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        jsr RtcClockOvl
        pla
        sta CPU_PORT
        plp
@end:   jmp WbCheck

        .segment "DATA"
rtcRetry:       .byte 0         ; $80: the Ultimate's clock not set yet
rtcMinute:      .byte $FF
        .segment "CODE"

        .segment "BFCODE"       ; $BF40 area (not after the RAM copy)

; Snap: RAM -> REU bank HIB_RAM. Returns A = 0; after a resume it returns
; once more, with A = 1. Interrupts off. Destroys X.
Snap:   tsx
        stx hibSP
        lda #0
        sta hibResumed
        ldy #REU_STASH_FF00
        jsr RamDma
        lda hibResumed
        rts

; RamDma: Y = REU command for all 64 KB; RamSetup only sets it up and
; leaves all RAM visible for the $FF00 write.
RamDma: jsr RamSetup
        lda REU_TRIGGER
        sta REU_TRIGGER
        lda #RAM_IO
        sta CPU_PORT
        rts
RamSetup:
        lda #RAM_IO
        sta CPU_PORT
        ldx #reuCtrl - reuC64   ; all 0 (length 0: 65536 bytes) but the bank
        lda #0
@zero:  sta reuC64,x
        dex
        bpl @zero
        lda #HIB_RAM
        sta reuAddr+2
        sty reuCmd
        lda #RAM_ALL
        sta CPU_PORT
        rts

        .segment "KCODE"

; HibTick (interrupt, then WbTick): input (a key or a mouse button) marks
; the session changed and restarts the count; after IDLE_HI * 256 frames
; (30 s; SETTINGS.INI [system] hibernate=, 0 off) without input a save is
; due: the write-back path runs it
; from MainLoop (WbCheck, module 1). Destroys A.
IDLE_HI         = 6             ; 6 * 256 frames: about 30 s (PAL)
HibTick:
        lda pressFlag           ; keys and buttons (pointer moves alone
        and #KEYPRESS_BIT | MOUSE_BIT   ; change nothing; the 1351 jitters)
        beq @quiet
        lda #0
        sta hibIdle
        sta hibIdle+1
        lda #$80
        sta hibState
        bne @wb
@quiet: lda hibLimit            ; 0: automatic saves off
        beq @wb
        bit hibState
        bpl @wb
        inc hibIdle
        bne @wb
        inc hibIdle+1
        lda hibIdle+1
        cmp hibLimit
        bne @wb
        lda #$40                ; due (no longer counting)
        sta hibState
        sta wbPending
@wb:    jmp WbTick

        .segment "KEXT"         ; (these bytes run on after the RAM copy:
                                ; the same build, checked by BUILD_ID)

; Resume: REU bank HIB_RAM -> RAM, then on as after Snap (never returns).
Resume: sei
        ldy #REU_FETCH_FF00
        jsr RamSetup
        lda REU_TRIGGER         ; (all RAM: keep the byte at $FF00)
        sta REU_TRIGGER         ; the whole RAM, this code included
        lda #RAM_IO             ; (same bytes as before: same kernal)
        sta CPU_PORT
        ldx hibSP
        txs
        lda #1
        sta hibResumed
        rts                     ; from Snap, in the restored session

        .segment "OVL8"

        jmp Suspend             ; entry 0

HIB_SUSPEND     = 1
        .include "hibshared.inc"

partIdx:        .byte 0
hibErr:         .byte 0

; Suspend: X = 0, or DEV_NOT_FOUND (no Ultimate) / an error of the file.
Suspend:
        ldx #DEV_NOT_FOUND
        lda uciPresent
        beq @end
        jsr TaskMany            ; (several tasks: not yet; task.s)
        bcc @go
@end:   rts
@go:    jsr WriteBackNow        ; the drives' changes go to their images
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda #REU_STASH          ; chip state to bank 1
        sta dmaCmd
        jsr ChipDma
        php
        sei
        jsr Snap
        bne Resumed
        plp
        lda #WR_VER_ERR         ; until the file is complete
        sta hibErr
        jsr Fingerprint         ; header: signature and fingerprint to
        lda #<HEADER            ; bank 1 at HEADER (in the file's part 0)
        sta reuAddr
        lda #>HEADER
        sta reuAddr+1
        lda #<signature
        ldx #>signature
        ldy #6
        jsr DmaGo
        lda #<(HEADER + 6)
        sta reuAddr
        lda #<r2
        ldx #>r2
        ldy #2
        jsr DmaGo
        jsr HomeCD
        bne @fail
        lda #DOS_OPEN
        ldx #$0A                ; write, created or overwritten
        jsr NameCmd
        bne @fail
        ldx #0
@part:  stx partIdx
        lda #DOS_SAVE_REU
        jsr PartCmd
        bne @close
        ldx partIdx
        inx
        cpx #PARTS
        bne @part
        lda #0
        sta hibErr
@close: lda #DOS_CLOSE
        jsr Begin
        jsr Simple
@fail:  pla
        sta CPU_PORT
        ldx hibErr
        rts

; The session continues here after a resume (interrupts off, the P pushed
; before Snap on the stack): chips back, clock read anew, back to the
; caller of Suspend with X = 0.
Resumed:
        lda #$7F
        sta $DC0D
        sta $DD0D
        lda $DC0D
        lda $DD0D
        lda #$FF
        sta $DC02
        lda #0
        sta $DC03
        lda #REU_FETCH
        sta dmaCmd
        jsr ChipDma
        lda #$0F
        sta $D019               ; no pending VIC interrupt
        jsr TodMode             ; the TOD on again: the Ultimate's time
        lda turboNow            ; the session's turbo speed
        cmp #$FF
        beq @speed
        sta $D031
@speed: jsr RtcClockOvl         ; (else the session's)
        plp
        pla
        sta CPU_PORT
        ldx #0
        stx imgFlags            ; (a disk image's copy in the REU: not
        jsr TaskInit            ; in the file, gone; the other tasks too)
        ldx #0
        rts


        .segment "OVL10"
        .scope Mod10            ; (its own cmdBuf, cmdLen for uci.inc)

        jmp TodSet              ; entry 0
        jmp RtcClock            ; entry 3

; RtcClock (I/O on): date and time from the Ultimate's real-time clock
; (DOS command $26: "yyyy/mm/dd hh:mm:ss"), then the TOD from it; without
; an answer the TOD from the time already in the variables. r0 kept (a
; resumed session goes on after it).
RtcClock:
        lda uciPresent
        bne @ask
@none:  jmp TodSet
@ask:   lda r0L
        pha
        lda r0H
        pha
        lda #TARGET_DOS
        sta cmdBuf
        lda #DOS_GET_TIME
        sta cmdBuf+1
        lda #2
        sta cmdLen
        lda #<rtcText           ; the answer, at most 32 characters (the
        sta r0L                 ; status is not needed: the text is
        lda #>rtcText           ; checked instead)
        sta r0H
        lda #<(rtcText + 32)
        sta dataEnd
        lda #>(rtcText + 32)
        sta dataEnd+1
        jsr UciCommand
        lda r0L                 ; its length
        sec
        sbc #<rtcText
        tax
        pla
        sta r0H
        pla
        sta r0L
        cpx #19
        bcc @none
        lda rtcText+4
        cmp #'/'
        bne @none
        lda rtcText+2           ; before 2026: the clock is not set yet
        cmp #'2'                ; (the U64 at power-on, until it has the
        bcc @unset              ; network time: 2025/01/11 seen); the time
        bne @set                ; already there goes on, asked again later
        lda rtcText+3           ; (RtcCheck)
        cmp #'6'
        bcs @set
@unset: lda #$80
        sta rtcRetry
        bne @none
@set:   lda #0
        sta rtcRetry
        lda #1                  ; (the desktop adds [time] adjust=)
        sta guClockFresh
        ldx #5                  ; yy mm dd hh mm ss -> year .. seconds
@field: ldy rtcAt,x
        lda rtcText,y
        sec
        sbc #'0'
        sta @ten+1
        asl                     ; tens * 10
        asl
        clc
        adc @ten+1
        asl
        sta @ten+1
        lda rtcText+1,y
        sec
        sbc #'0'
        clc
@ten:   adc #0
        sta $8516,x             ; year, month, day, hour, minutes, seconds
        dex
        bpl @field
        ; (falls into TodSet)


; TodSet: the CIA 1 time-of-day clock from hour (0-23), minutes, seconds
; (12-hour BCD with the PM bit; the time of the session goes on from the
; suspend, the clock not yet being read from the Ultimate).
TodSet: lda $DC08               ; the tenths: releases a latch left by an
                                ; earlier read of the hours (ClockInit), or
                                ; TimeUpdate would see the old AM/PM
        lda #0                  ; writes set the clock, not the alarm
        sta $DC0F
        lda hour
        ldx #0                  ; X = PM bit
        cmp #12
        bcc @am
        ldx #$80
        sbc #12
@am:    cmp #0
        bne @bcd
        lda #12                 ; 0 and 12 are 12 on the TOD
@bcd:   jsr ToBCD
        stx @pm+1
@pm:    ora #0
        cmp #$12                ; 12 (AM or PM): a 6526 flips AM/PM when 12
        beq @twelve             ; is written, so the other half first, as
        cmp #$92                ; ClockInit does
        bne @write
@twelve:
        eor #$80
        sta $DC0B               ; (stops the clock until the tenths)
        eor #$80
        cmp $DC0B               ; not flipped: a CIA without the quirk
        beq @min
@write: sta $DC0B
@min:   lda $851A               ; minutes
        jsr ToBCD
        sta $DC0A
        lda $851B               ; seconds
        jsr ToBCD
        sta $DC09
        lda #0
        sta $DC08               ; tenths: the clock runs
        rts

rtcAt:  .byte 2, 5, 8, 11, 14, 17
rtcText:        .res 32

UCI_STAT_MAX    = 2             ; (module variables: no nested overlay call)
cmdBuf:         .res 2
cmdLen:         .res 1
statBuf:        .res UCI_STAT_MAX + 1
dataEnd:        .res 2
        .include "uci.inc"

; ToBCD: A (0-59) -> BCD. Destroys Y.
ToBCD:  ldy #$FF
@ten:   iny
        sec
        sbc #10
        bcs @ten
        adc #10
        sta @one+1
        tya
        asl
        asl
        asl
        asl
@one:   ora #0
        rts

        .endscope
