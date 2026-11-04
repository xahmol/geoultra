; File engine: a FAT date and time (FILE_INFO's reply in diskBlkBuf, +4)
; as GEOS keeps one (year with two digits, month, day, hour, minute), for
; FE_STAT on the Ultimate (module 37) and a copy from it (module 43). The
; includer defines FAT_OUT, where the five bytes go.

; FatDate: the date and time to FAT_OUT. Destroys A, X, feM.
FatDate:
        lda diskBlkBuf+5        ; date: yyyyyyym mmmddddd (year from 1980)
        lsr
        clc
        adc #80
        cmp #100
        bcc :+
        sbc #100
:       sta FAT_OUT
        lda diskBlkBuf+5        ; month: 1 bit here, 3 in the low byte
        and #$01
        ldx diskBlkBuf+4
        jsr Join
        sta FAT_OUT+1
        lda diskBlkBuf+4
        and #$1F
        sta FAT_OUT+2
        lda diskBlkBuf+7        ; time: hhhhhmmm mmmsssss
        lsr
        lsr
        lsr
        sta FAT_OUT+3
        lda diskBlkBuf+7        ; minute: 3 bits here, 3 in the low byte
        and #$07
        ldx diskBlkBuf+6
        jsr Join
        sta FAT_OUT+4
        rts

; Join: A * 8 + X's top three bits (a field across a FAT date or time's
; two bytes). Destroys X.
Join:   asl
        asl
        asl
        sta feM
        txa
        lsr
        lsr
        lsr
        lsr
        lsr
        ora feM
        rts
