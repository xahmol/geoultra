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
        .export hibState
        .import WbTick, wbPending
        .import OvlCall, uciPresent, WriteBackNow, TodMode
        .import Begin, Put, Simple, cmdLen, dmaCmd, DmaGo, status

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
REU_STASH_FF00  = $80           ; execute on a write to $FF00, C64 -> REU
BUF             = $4000         ; cold start: free (TEXT of mount.s)

        .segment "DATA"

hibSP:          .byte 0         ; stack pointer inside Snap
hibResumed:     .byte 0         ; 1 after Resume
hibState:       .byte 0         ; bit 7: changed since the last save,
                                ; bit 6: a save is due (module 1)
hibIdle:        .word 0         ; frames without input since a change

        .segment "CODE"

HibSuspend:                     ; X = 0 or an error
        jsr OvlCall
        .byte 8, 0
HibResumeOvl:                   ; returns only when nothing is resumed
        jsr OvlCall
        .byte 9, 0
TodSetOvl:                      ; (module 10)
        jsr OvlCall
        .byte 10, 0

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
; (about 10 s) without input a save is due: the write-back path runs it
; from MainLoop (WbCheck, module 1). Destroys A.
IDLE_HI         = 2
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
@quiet: bit hibState
        bpl @wb
        inc hibIdle
        bne @wb
        inc hibIdle+1
        lda hibIdle+1
        cmp #IDLE_HI
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
        bne @go
        rts
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
        jsr TodMode             ; the TOD on again, at the session's time
        jsr TodSetOvl
        plp
        pla
        sta CPU_PORT
        ldx #0
        rts


        .segment "OVL10"

        jmp TodSet              ; entry 0

; TodSet: the CIA 1 time-of-day clock from hour (0-23), minutes, seconds
; (12-hour BCD with the PM bit; the time of the session goes on from the
; suspend, the clock not yet being read from the Ultimate).
TodSet: lda #0                  ; writes set the clock, not the alarm
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
