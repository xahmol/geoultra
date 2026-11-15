; Shared by the file engine's mount modules (femount.inc) and the
; spooler's banks (spool.s): drvTracks imported by the includer.

; BanksOf: A = the REU banks drive X uses (a native one: its tracks).
; Destroys Y.
BanksOf:
        lda driveType,x
        and #$0F
        cmp #DRV_NATIVE
        bne @fixed
        lda drvTracks,x
        rts
@fixed: tay
        lda TypeBanks,y
        rts
TypeBanks:      .byte 0, 3, 6, 13       ; none, 1541, 1571, 1581 (mount.s)
