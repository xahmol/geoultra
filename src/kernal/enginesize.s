; File engine: a native (DNP) image mounted at another size than its
; file (the user, 2026-11-14: Settings' Drives page changes a drive's
; tracks at once). FE_MOUNT's image path may end in ",tracks=N" as
; MOUNTS.INI's lines do (module 65 Comma); module 68 then loads the file
; into N banks (larger: the whole file, the new tracks set free in the
; BAM; smaller: only the first N tracks, refused when the BAM shows a
; used block after them), the BAM's last track (1/2 $08) set to N, the
; drive F_RESIZED (module 69 Enter takes mResz; its write-back writes the whole image anew, MOUNTS.INI
; keeps ",tracks=N"). The cold start does the same from MOUNTS.INI
; (mount.s ResizeFirst, ResizeThen); this is the running system's.
; Module 91. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"
        .include "drvflags.inc"

        .import SysRAMOp

SYS_BANK        = 1
MIN_TRACKS      = 2             ; native: track 1 and one more at least
BAM_PAGE        = $02           ; a native BAM: $0200 + track * 32 in the
                                ; drive's first bank (blocks 1/2 on)
LAST_TRACK      = $0208         ; its last track (1/2 $08)

        .segment "OVL91"
        .scope Mod91

        jmp Comma               ; entry 0 (module 65: the path's option)
        jmp Want                ; entry 3 (module 68: the banks to load)
        jmp Then                ; entry 6 (module 68: after the load)

        .include "fereu.inc"

; Comma: fePath's ",tracks=N" (any case) cut off, N to mWant (0: none;
; more than 255 or not a number: 0). mResz cleared.
Comma:  lda #0
        sta mWant
        sta mResz
        ldx #$FF
@find:  inx
        lda fePath,x
        beq @end
        cmp #','
        bne @find
        lda #0
        sta fePath,x
@eq:    inx
        lda fePath,x
        beq @end
        cmp #'='
        bne @eq
@digit: inx
        lda fePath,x
        sec
        sbc #'0'
        cmp #10
        bcs @end
        sta mTmp
        lda mWant               ; mWant * 10 + the digit
        cmp #26
        bcs @big
        asl
        asl
        adc mWant
        asl
        adc mTmp
        bcs @big
        sta mWant
        bcc @digit              ; (always)
@big:   lda #0
        sta mWant
@end:   rts

; Want (module 68, a native image: mTracks = mBanks = its file's tracks):
; mFile = them; with a wanted size (MIN_TRACKS up, another): mBanks =
; it, and a smaller one only those tracks loaded (mTracks = it).
Want:   lda mTracks
        sta mFile
        lda mWant
        cmp #MIN_TRACKS
        bcc @end
        cmp mTracks
        beq @end
        sta mBanks
        bcs @end                ; (larger: the whole file loaded)
        sta mTracks
@end:   rts

; Then (module 68, after the load at mBank): another size: smaller,
; X = FE_NOT_SUPPORTED when the BAM shows a used block after the last
; track; larger, the new tracks' blocks set free; then the BAM's last
; track = the size, mTracks = it, mResz = F_RESIZED | F_DIRTY. Else X = 0.
Then:   ldx #0
        lda mType               ; (native images only: mFile is theirs)
        cmp #DRV_NATIVE
        bne @end
        lda mWant
        cmp #MIN_TRACKS
        bcc @end
        cmp mFile
        beq @end
        bcs @grow
        tax                     ; smaller: tracks mWant+1 .. mFile free?
@check: inx
        stx mIdx
        txa
        ldy #REU_FETCH
        jsr BamOp
        ldy #31
@free:  lda diskBlkBuf,y
        cmp #$FF
        bne @used
        dey
        bpl @free
        ldx mIdx
        cpx mFile
        bne @check
        beq @size
@used:  ldx #FE_NOT_SUPPORTED   ; (files after the last track: refused)
@end:   rts
@grow:  ldy #31                 ; larger: tracks mFile+1 .. mWant free
        lda #$FF
@ff:    sta diskBlkBuf,y
        dey
        bpl @ff
        ldx mFile
@new:   inx
        stx mIdx
        txa
        ldy #REU_STASH
        jsr BamOp
        ldx mIdx
        cpx mWant
        bne @new
@size:  lda mWant               ; the BAM's last track
        sta mTracks
        sta diskBlkBuf
        lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #<LAST_TRACK
        sta r1L
        lda #>LAST_TRACK
        sta r1H
        lda #1
        sta r2L
        lda #0
        sta r2H
        jsr DriveOp
        lda #F_RESIZED | F_DIRTY ; (changed too: the file gets the new size at
        sta mResz               ; the next write-back or FE_UMOUNT)
        ldx #0
        rts

; BamOp: A = a track, Y = REU command: its 32 BAM bytes <-> diskBlkBuf.
BamOp:  pha
        asl
        asl
        asl
        asl
        asl
        sta r1L
        pla
        lsr
        lsr
        lsr
        clc
        adc #BAM_PAGE
        sta r1H
        lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #32
        sta r2L
        lda #0
        sta r2H
DriveOp:
        lda mBank               ; (the drive's first bank)
        sta r3L
        jmp SysRAMOp

        .endscope
