; Hibernation, resuming (overlay module 9): see hibernate.s.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"

        .import uciPresent, Resume, Begin, Put, Simple, cmdLen, dmaCmd, DmaGo, status

HIB_RAM         = 19
HIB_SCRATCH     = 20
SYS_BANK        = 1
HEADER          = $0400
cmdBuf          = $9FB0
TARGET_DOS      = $01
DOS_OPEN        = $02
DOS_CLOSE       = $03
DOS_SEEK        = $06
DOS_DELETE      = $09
DOS_CD          = $11
DOS_LOAD_REU    = $21
DOS_SAVE_REU    = $22
BUF             = $4000         ; cold start: free (TEXT of mount.s)

        .segment "OVL9"

        jmp HibResume           ; entry 0

        .include "hibshared.inc"

; HibResume: from the cold start ($01 = $35, after the mounts). Returns
; when nothing is resumed.
HibResume:
        lda uciPresent
        beq @end
        lda #$7F                ; C= held: start fresh
        sta $DC00
        lda $DC01
        and #$20
        beq @end
        jsr HomeCD
        bne @end
        lda #DOS_OPEN
        ldx #$01                ; read
        jsr NameCmd
        bne @end
        jsr CheckFile
        bne @close
        ldx #0
@part:  stx partIdx
        lda #DOS_LOAD_REU
        jsr PartCmd
        bne @close
        ldx partIdx
        inx
        cpx #PARTS
        bne @part
        lda #DOS_CLOSE
        jsr Begin
        jsr Simple
        lda #DOS_DELETE         ; used once: an old state never comes back
        ldx #0
        jsr NameCmd
        jmp Resume
@close: lda #DOS_CLOSE
        jsr Begin
        jsr Simple
@end:   rts

; CheckFile: Z set when the file's header has the signature and this
; kernal's fingerprint, and its mount table ($01:0100-$03FF: per drive
; type, bank and tracks, the image paths, the home path) is the one just
; mounted.
CheckFile:
        lda #DOS_SEEK           ; bank 1 of the file from $0100
        jsr Begin
        lda #0
        ldx #1
        jsr PutLong
        jsr Simple
        bne @end
        lda #DOS_LOAD_REU       ; $0400 bytes to the scratch bank at $0100
        jsr Begin
        lda #HIB_SCRATCH
        ldx #1
        jsr PutLong
        lda #0
        ldx #4
        jsr PutLong
        jsr Simple
        bne @end
        lda #HIB_SCRATCH        ; the file's $0100-$04FF -> BUF
        ldx #4
        ldy #0
        jsr PageDma
        lda #SYS_BANK           ; the current $0100-$03FF -> BUF+$400
        ldx #3
        ldy #4
        jsr PageDma
        jsr Fingerprint
        ldx #5
@sig:   lda BUF+$300,x
        cmp signature,x
        bne @end
        dex
        bpl @sig
        lda BUF+$306
        cmp r2L
        bne @end
        lda BUF+$307
        cmp r2H
        bne @end
        ldx #$20                ; per slot: type, bank, tracks (not the
@slot:  ldy #3                  ; flags, which change in a session)
@entry: lda BUF,x
        cmp BUF+$400,x
        bne @end
        inx
        dey
        bne @entry
        txa
        clc
        adc #29
        tax
        bpl @slot               ; ($20, $40, $60 and $80 done at $A0)
        ldx #0                  ; the image paths and the home path
@path:  lda BUF+$100,x
        cmp BUF+$500,x
        bne @end
        cpx #32
        bcs @next
        lda BUF+$200,x
        cmp BUF+$600,x
        bne @end
@next:  inx
        bne @path
@end:   rts

; PageDma: X pages from bank A at $0100 to BUF + Y pages.
PageDma:
        sta reuAddr+2
        stx reuLen+1
        tya
        clc
        adc #>BUF
        sta reuC64+1
        lda #0
        sta reuC64
        sta reuAddr
        sta reuLen
        sta reuCtrl
        lda #1
        sta reuAddr+1
        lda #REU_FETCH
        sta reuCmd
        rts

partIdx:        .byte 0
