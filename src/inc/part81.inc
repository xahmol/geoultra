; Shared by the 1581 partition modules 18 and 21 (src/kernal/folders.s),
; assembled into each, as an overlay module cannot call another's code.
; Format: docs/reference/GEOS_REFERENCE.md, "1581 partitions and sub-directories".

; Tracks: A/Y = a partition's size in blocks (lo/hi) -> r3L = its tracks;
; C set when it is a whole number of at least 3 (a sub-directory).
; Destroys A, r2.
Tracks: sta r2L
        sty r2H
        lda #0
        sta r3L
@sub:   lda r2L
        ora r2H
        beq @done
        sec
        lda r2L
        sbc #40
        sta r2L
        lda r2H
        sbc #0
        sta r2H
        bcc @bad                ; (not a multiple of 40)
        inc r3L
        bne @sub
@done:  lda r3L
        cmp #3
        rts
@bad:   clc
        rts

; Valid: dirEntryBuf a partition usable as a sub-directory (type CBM,
; sector 0, whole tracks, at least 3, track 40 outside): C clear, A =
; its first track, r3L its tracks; else C set. Destroys Y, r2.
Valid:  lda dirEntryBuf
        and #$07
        cmp #5                  ; CBM
        bne @no
        lda dirEntryBuf + 2
        bne @no
        lda dirEntryBuf + OFF_SIZE
        ldy dirEntryBuf + OFF_SIZE + 1
        jsr Tracks
        bcc @no
        clc                     ; last = first + tracks - 1 < 40, or
        lda dirEntryBuf + 1     ; first > 40
        cmp #41
        bcs @ok
        adc r3L
        cmp #41
        bcs @no
@ok:    lda dirEntryBuf + 1
        clc
        rts
@no:    sec
        rts

; Formatted: A = a partition's first track; its header t/0 is read into
; diskBlkBuf (r1 = t/0). C clear and X = 0 when it is formatted as a
; sub-directory ("D", linked to t/3); else C set and X = STRUCT_MISMAT or
; the disk error.
Formatted:
        sta r1L
        lda #0
        sta r1H
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        bne @no
        ldx #STRUCT_MISMAT
        lda diskBlkBuf + 2
        cmp #'D'
        bne @no
        lda diskBlkBuf
        cmp r1L
        bne @no
        lda diskBlkBuf + 1
        cmp #3
        bne @no
        ldx #0
        clc
        rts
@no:    sec
        rts
