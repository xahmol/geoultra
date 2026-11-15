; Shared by the hibernation modules 8 (src/kernal/hibernate.s) and 9
; (src/kernal/hibresume.s): assembled into each, as an overlay module
; cannot call the other's code.

hibName:        .byte "HIBERNAT.BIN", 0
signature:      .byte "GUHIB3"
; The file's parts (REU banks: bank 1, the scrap store, the task banks,
; the desk accessory swap, the legacy REU, the print queue): module 115
; (hibernate.s), from the header bytes at HP (scratch, kept across the
; nested calls): HP + 0 the current task, + 1 the task slots saved, + 2
; the legacy banks saved, + 3 the print queue's extra banks saved, + 4
; the first of them (spoolBase: at the resume the cold start has not set
; it yet) (header + 8 to + 12 in the file).
HP              = $9FA0
HP_LEN          = 5

; PutLong: the 32-bit value 0, X, A, 0 (low byte first).
PutLong:
        pha
        lda #0
        jsr Put
        txa
        jsr Put
        pla
        jsr Put
        lda #0
        jmp Put

; HomeCD: CD to the home folder (REU $01:0300). Z set on "00".
HomeCD: lda #DOS_CD
        jsr Begin
        lda #$00
        sta reuAddr
        lda #$03
        sta reuAddr+1
        lda #REU_FETCH
        sta dmaCmd
        lda #<(cmdBuf + 2)
        ldx #>(cmdBuf + 2)
        ldy #32
        jsr DmaGo
        ldy #2
@end:   lda cmdBuf,y
        beq @done
        iny
        bne @end
@done:  sty cmdLen
        jmp Simple

; NameCmd: DOS command A (with attribute X when not 0) on HIBERNAT.BIN.
; Z set on "00".
NameCmd:
        jsr Begin
        txa
        beq @name
        jsr Put
@name:  ldx #0
@char:  lda hibName,x
        beq @send
        jsr Put
        inx
        bne @char
@send:  jmp Simple

; Fingerprint: r2 = the kernal's build ID (BUILD_ID, set by the Makefile
; at every build; a CRC of the running code would change with its
; self-modifying parts).
Fingerprint:
        lda #<BUILD_ID
        sta r2L
        lda #>BUILD_ID
        sta r2H
        rts

.ifdef HIB_SUSPEND
; ChipDma: dmaCmd = REU_STASH / REU_FETCH: the VIC-II registers and CIA
; 2's port A, port B and direction, to or from bank 1 at $0500 / $0530
; (I/O banked in).
ChipDma:
        lda #$00
        sta reuAddr
        lda #$05
        sta reuAddr+1
        lda #<$D000
        ldx #>$D000
        ldy #47
        jsr DmaGo
        lda #$30
        sta reuAddr
        lda #$05
        sta reuAddr+1
        lda #<$DD00
        ldx #>$DD00
        ldy #3
        jmp DmaGo
.endif
