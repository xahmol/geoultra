; Processes: InitProcesses, RestartProcess, EnableProcess, BlockProcess,
; UnblockProcess, FreezeProcess, UnfreezeProcess, plus the interrupt
; level countdown and the MainLoop dispatch. Written from the HG2G2022
; descriptions.

        .include "geos.inc"

        .export InitProcesses, RestartProcess, EnableProcess
        .export BlockProcess, UnblockProcess, FreezeProcess, UnfreezeProcess
        .export ProcessTimers, RunProcesses

P_RUNNABLE      = $80
P_BLOCKED       = $40
P_FROZEN        = $20

        .segment "KSTATE"               ; saved and restored by dialog boxes

numProcesses:   .byte 0
pEventLo:       .res MAX_PROCESSES
pEventHi:       .res MAX_PROCESSES
pReloadLo:      .res MAX_PROCESSES
pReloadHi:      .res MAX_PROCESSES
pTimerLo:       .res MAX_PROCESSES
pTimerHi:       .res MAX_PROCESSES
pFlags:         .res MAX_PROCESSES
runIndex:       .byte 0

        .segment "CODE"

; InitProcesses: A = number of processes, r0 = table of 4-byte entries
; (.word event, .word timer). All start frozen. Destroys A, X, Y, r1.
InitProcesses:
        php
        sei
        sta numProcesses
        lda r0L
        sta r1L
        lda r0H
        sta r1H
        ldx #0
@next:  cpx numProcesses
        beq @done
        ldy #0
        lda (r1),y
        sta pEventLo,x
        iny
        lda (r1),y
        sta pEventHi,x
        iny
        lda (r1),y
        sta pReloadLo,x
        sta pTimerLo,x
        iny
        lda (r1),y
        sta pReloadHi,x
        sta pTimerHi,x
        lda #P_FROZEN
        sta pFlags,x
        clc
        lda r1L
        adc #4
        sta r1L
        bcc @inc
        inc r1H
@inc:   inx
        bne @next
@done:  plp
        rts

; RestartProcess: X = process. Reloads the timer, clears all flags.
; Destroys A.
RestartProcess:
        php
        sei
        lda pReloadLo,x
        sta pTimerLo,x
        lda pReloadHi,x
        sta pTimerHi,x
        lda #0
        sta pFlags,x
        plp
        rts

; EnableProcess: X = process, runnable on the next MainLoop pass.
EnableProcess:
        lda #P_RUNNABLE
        bne SetFlag

; BlockProcess: X = process; MainLoop ignores its events.
BlockProcess:
        lda #P_BLOCKED
        bne SetFlag

; FreezeProcess: X = process; its timer stops.
FreezeProcess:
        lda #P_FROZEN
SetFlag:
        php
        sei
        ora pFlags,x
        sta pFlags,x
        plp
        rts

; UnblockProcess: X = process.
UnblockProcess:
        lda #<~P_BLOCKED
        bne ClearFlag

; UnfreezeProcess: X = process.
UnfreezeProcess:
        lda #<~P_FROZEN
ClearFlag:
        php
        sei
        and pFlags,x
        sta pFlags,x
        plp
        rts

; Interrupt level: count down every timer that is not frozen; at zero
; the process becomes runnable and its timer restarts.
ProcessTimers:
        ldx numProcesses
        beq @end
@loop:  dex
        lda pFlags,x
        and #P_FROZEN
        bne @skip
        lda pTimerLo,x
        bne @low
        dec pTimerHi,x
@low:   dec pTimerLo,x
        lda pTimerLo,x
        ora pTimerHi,x
        bne @skip
        lda pFlags,x
        ora #P_RUNNABLE
        sta pFlags,x
        lda pReloadLo,x
        sta pTimerLo,x
        lda pReloadHi,x
        sta pTimerHi,x
@skip:  txa
        bne @loop
@end:   rts

; MainLoop level: call the event routine of every runnable process that
; is not blocked, clearing its runnable flag first.
RunProcesses:
        lda #0
        sta runIndex
@loop:  ldx runIndex
        cpx numProcesses
        bcs @end
        sei
        lda pFlags,x
        and #P_RUNNABLE | P_BLOCKED
        cmp #P_RUNNABLE
        bne @next
        lda pFlags,x
        and #<~P_RUNNABLE
        sta pFlags,x
        cli
        lda pEventLo,x
        sta @call+1
        lda pEventHi,x
        sta @call+2
@call:  jsr $FFFF                       ; patched with the event routine
@next:  cli
        inc runIndex
        bne @loop
@end:   rts
