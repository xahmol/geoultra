; fontblk.inc: block helpers of the system fonts' relocation at the cold
; start (mount.s overlay modules 121 and 122, each its own copy: a module
; cannot call the other's without being fetched again). FONTS.DNP lies in
; REU banks FONT_BANK on, block t/s at bank FONT_BANK + t - 1, page s.
; Own code, 2026-11-18.

; FCheck: C set when block A/X lies outside the loaded image (track 0 or
; above fTracks). Destroys nothing.
FCheck: cmp #1
        bcc @no
        cmp fTracks
        beq @ok
        bcs @no
@ok:    clc
        rts
@no:    sec
        rts

; FMove: the track byte at page A, offset Y moved up by FONT_TRACK when
; it is not 0. Destroys A; X and Y kept.
FMove:  sta fmGet+2
        sta fmSet+2
fmGet:  lda $FF00,y
        beq fmEnd
        clc
        adc #FONT_TRACK
fmSet:  sta $FF00,y
fmEnd:  rts

; FGet / FPut: block A/X (track, sector) of the image <-> page Y.
; Destroys A.
FGet:   pha
        lda #REU_FETCH
        bne FDma
FPut:   pha
        lda #REU_STASH
FDma:   sta fdCmd
        pla
        clc
        adc #FONT_BANK - 1
        sta reuAddr+2
        stx reuAddr+1
        lda #0
        sta reuAddr
        sta reuC64
        sta reuLen
        sta reuCtrl
        sty reuC64+1
        lda #1
        sta reuLen+1
        lda fdCmd
        sta reuCmd
        rts
