; File engine: disk images mounted and unmounted while GEOS runs
; (docs/FILE_ENGINE.md "Mount"; engine.s has the module list): module 65
; FE_MOUNT (the image checked), module 68 its REU banks found and the
; image loaded, module 69 the new drive entered, module 66 FE_UMOUNT (a
; drive emptied, after the write-back), modules 67 and 70 MOUNTS.INI
; written anew. Shared: femount.inc, fedrive.inc.
; Own code; the boot mounts the same way (mount.s), from INIT code that
; is gone once GEOS runs.
;
; A drive is: the mount table entry in REU bank 1 ($0120 + 32 * drive:
; type, first bank, native tracks, flags), its image path ($0200 + 64 *
; drive) and dirty map ($2000 + $2000 * drive) for the write-back, and
; the driver's state (driveType, ramBase, drvTracks, drvFlags). Free
; banks are found from the other drives' (FE_FIRST_BANK-FE_LAST_BANK).

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"
        .include "drvflags.inc"

        .import OvlCall, SysRAMOp, folderT, folderS, drvTracks, drvFlags
        .import natLoaded, WriteBackNow, hibState

SYS_BANK        = 1
DIRTY_MAPS      = $2000         ; $2000 bytes per drive
PATH_MAX        = 63            ; an image path in its 64 bytes
U_LOAD_REU      = $21

        .segment "OVL65"
        .scope Mod65

        jmp OvMount             ; entry 0

        .include "feult.inc"
        .include "fecd.inc"
        .include "femount.inc"
        .include "fetype.inc"

Resolve:
        jsr OvlCall             ; (module 23: the path)
        .byte 23, 0
Unmount:
        jsr OvlCall             ; (module 66: the drive's image away)
        .byte 66, 3
Load:   jsr OvlCall             ; (module 68: the image loaded)
        .byte 68, 0
Enter:  jsr OvlCall             ; (module 69: the new drive entered; a
        .byte 69, 0             ; stub: back to the function's caller)
Comma:  jsr OvlCall             ; (module 91: a size after the path)
        .byte 91, 0

; FE_MOUNT: r0 = a drive ("/a"-"/d"), r1 = a disk image on the Ultimate
; (.d64, .d71, .d81, .dnp; its path at most PATH_MAX characters). The
; drive's old image is unmounted first (written back), the new one
; loaded into free REU banks; MOUNTS.INI written anew. X = 0 or the
; error (INSUFF_SPACE: no room in the REU).
OvMount:
        jsr ParseDrive
        bcs @end
        stx mSlot
        lda argR1
        sta r0L
        lda argR1+1
        sta r0H
        lda #1
        sta feUlt
        jsr Resolve
        txa
        bne @end
        ldx #FE_BAD_PATH
        lda feKind
        cmp #FE_P_ULTIMATE
        bne @end
        lda feName
        beq @end
        jsr Comma               ; (module 91: ",tracks=N" off the path)
        ldy #$FF                ; its length
@len:   iny
        lda fePath,y
        bne @len
        cpy #PATH_MAX + 1
        bcs @end
        jsr Type
        bcs @end
        ldx mSlot               ; the drive's old image first
        lda driveType,x
        and #$0F
        beq :+
        jsr Unmount
        txa
        bne @end
:       jsr Load
        txa
        bne @end
        jmp Enter
@end:   rts

        .endscope

        .segment "OVL66"
        .scope Mod66

        jmp OvUmount            ; entry 0
        jmp Unmount             ; entry 3

        .include "fereu.inc"
        .include "femount.inc"
        .include "fedrive.inc"
        .include "fework.inc"

Ini:    jsr OvlCall             ; (module 67: MOUNTS.INI anew; a stub)
        .byte 67, 0

; FE_UMOUNT: r0 = a drive ("/a"-"/d"): its image written back and the
; drive emptied; MOUNTS.INI written anew. X = 0 or the error
; (DEV_NOT_FOUND: nothing mounted; FE_ULTIMATE: the write-back failed,
; the drive stays).
OvUmount:
        jsr ParseDrive
        bcs @end
        stx mSlot
        lda driveType,x
        and #$0F
        bne :+
        ldx #DEV_NOT_FOUND
        rts
:       jsr Unmount
        txa
        bne @end
        jmp Ini
@end:   rts

; Unmount: drive mSlot's changes written back (every drive's: the
; write-back's own module), then the drive emptied; the caller's drive,
; if it was this one, becomes the first one left. X = 0, or FE_ULTIMATE
; when its changes could not be written (the drive stays).
;
; The write-back uses the overlay scratch $9F70-$9FFF (writeback.s:
; path, cmdBuf), the engine's work area: kept in the REU meanwhile
; (FE_WSAVE). A hibernation it would start at its end is held back
; (hibState bit 6 kept for MainLoop).
Unmount:
        lda hibState
        pha
        and #$BF
        sta hibState
        ldy #REU_STASH
        jsr WorkOp
        jsr WriteBackNow
        ldy #REU_FETCH
        jsr WorkOp
        pla
        ora hibState
        sta hibState
        ldx mSlot
        lda drvFlags,x
        and #F_DIRTY
        beq :+
        ldx #FE_ULTIMATE
        rts
:       lda #0
        sta driveType,x
        sta drvFlags,x
        sta drvTracks,x
        jsr TableOp             ; (its entry: type 0)
        jsr Common
        lda saveDrive           ; the caller's drive gone: another one
        sec
        sbc #8
        cmp mSlot
        bne @done
        ldx #0
@other: lda driveType,x
        and #$0F
        bne @found
        inx
        cpx #4
        bne @other
        beq @done               ; (none left)
@found: txa
        clc
        adc #8
        sta saveDrive
@done:  ldx #0
        rts

        .endscope

        .segment "OVL67"
        .scope Mod67

        jmp OvIni               ; entry 0

        .include "fereu.inc"
        .include "feult.inc"
        .include "fehome.inc"

Lines:  jsr OvlCall             ; (module 70: the text written)
        .byte 70, 0

; OvIni: MOUNTS.INI in the home folder written anew from the mounted
; drives: "[drives]", then "A=path" per drive (",tracks=N" for a native
; drive of another size than its file). Only the [drives] section is
; written: other lines in the file are lost. Written as MOUNTS.TMP
; first, which then takes MOUNTS.INI's place, so a failed write leaves
; the old list. X = 0 or the error.
OvIni:  jsr Home                ; (fehome.inc)
        txa
        bne @end
        lda #U_OPEN
        jsr UBegin
        lda #UO_ALWAYS
        jsr UPut
        ldx #TmpName - Names
        jsr Name
        jsr Send
        bne @end
        jsr Lines
        stx feM
        lda #U_CLOSE
        jsr UBegin
        jsr Send
        lda feM
        beq :+
        tax
:       txa
        bne @end
        lda #U_DELETE           ; the old list away (none: fine)
        jsr UBegin
        ldx #IniName - Names
        jsr Name
        jsr Send
        lda #U_RENAME           ; the new one in its place
        jsr UBegin
        ldx #TmpName - Names
        jsr Name
        lda #0
        jsr UPut
        ldx #IniName - Names
        jsr Name
        jmp Send
@end:   rts

; Name: the name at Names + X (zero-ended) to uCmd.
Name:   lda Names,x
        beq @end
        jsr UPut
        inx
        bne Name
@end:   rts

; Send: uCmd sent, no data back. Z set when it worked, else X = the error.
Send:   jsr UNoData
        jsr UExec
        txa
        rts

Names:
IniName:        .byte "MOUNTS.INI", 0
TmpName:        .byte "MOUNTS.TMP", 0

        .endscope

        .segment "OVL68"
        .scope Mod68

        jmp Load                ; entry 0
        jmp Banks0              ; entry 3 (FE_MKIMG, module 71)

Want:   jsr OvlCall             ; (module 91: the banks for a size)
        .byte 91, 3
Then:   jsr OvlCall             ; (module 91: after the load)
        .byte 91, 6

        .include "feult.inc"
        .include "fecd.inc"
        .include "femount.inc"

; Load: the image opened (read), a native one's tracks from its size,
; banks found, the whole image loaded there; closed. X = 0 or the error.
Load:   jsr UCd
        txa
        bne @end
        lda #U_OPEN
        jsr UBegin
        lda #UO_READ
        jsr UPut
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        bne @end
        lda #0
        sta mTracks
        lda mType
        cmp #DRV_NATIVE
        bne :+
        jsr Native
        bne @close
        jsr Want                ; (module 91: another size wanted)
:       jsr Banks0
        bcs @close
        lda #U_LOAD_REU         ; LOAD_REU: address, length (4 bytes each)
        jsr UBegin
        lda #0
        jsr UPut
        jsr UPut
        lda mBank
        jsr UPut
        lda #0
        jsr UPut
        lda #0                  ; the length: banks * 64 KB (a fixed image
        jsr UPut                ; is shorter: the file's end stops it)
        jsr UPut
        lda mBanks
        jsr UPut
        lda #0
        jsr UPut
        jsr UNoData
        jsr UExec
        txa
        bne @close
        jsr Then                ; (module 91: the BAM for another size)
@close: stx feM
        lda #U_CLOSE
        jsr UBegin
        jsr UNoData
        jsr UExec
        ldx feM
@end:   rts

; Native: a native image's tracks (and banks) from its size, 64 KB a
; track: 2 to 255. Z set when it worked, else X = FE_NOT_SUPPORTED or the
; error.
Native: lda #U_INFO
        jsr UBegin
        lda #<diskBlkBuf
        sta r0L
        sta uEnd
        lda #>diskBlkBuf
        sta r0H
        sta uEnd+1
        inc uEnd+1
        jsr UExec
        txa
        bne @end
        ldx #FE_NOT_SUPPORTED
        lda diskBlkBuf+3
        bne @end
        lda diskBlkBuf+2
        cmp #2
        bcc @end
        sta mTracks
        sta mBanks
        ldx #0
@end:   txa
        rts

; Banks0: mBank = the first of mBanks free banks, after the other
; drives' (first fit). C set: X = INSUFF_SPACE.
Banks0: lda #FE_FIRST_BANK
        sta mBank
@try:   lda mBank
        clc
        adc mBanks
        bcs @full
        cmp #FE_LAST_BANK + 2
        bcs @full
        ldx #3
@drive: cpx mSlot
        beq @next
        lda driveType,x
        and #$0F
        beq @next
        jsr BanksOf             ; overlap: its end after mBank, and
        clc                     ; mBank's end after its start?
        adc ramBase,x
        sta mTmp                ; (its end)
        cmp mBank
        bcc @next
        beq @next
        lda mBank
        clc
        adc mBanks
        cmp ramBase,x
        bcc @next
        beq @next
        lda mTmp                ; yes: after it, from the start again
        sta mBank
        jmp @try
@next:  dex
        bpl @drive
        clc
        rts
@full:  ldx #INSUFF_SPACE
        sec
        rts

        .endscope

        .segment "OVL69"
        .scope Mod69

        jmp Enter               ; entry 0
        jmp OvInfo              ; entry 3 (FE_MOUNTINFO; moved from module
                                ; 66 for room, 2026-11-14)

        .include "fereu.inc"
        .include "fedrive.inc"
        .include "femount.inc"

Ini:    jsr OvlCall             ; (module 67: MOUNTS.INI anew; a stub)
        .byte 67, 0

; FE_MOUNTINFO: r0 = a drive ("/a"-"/d"), r1 = a buffer of 64 bytes.
; r1 = 0 instead (no buffer: the old callers always pass one): long
; names set, r3L 1 off, 0 on (F_NOLONG; the mount table and MOUNTS.INI
; written anew; the user, 2026-11-14, Settings' Drives page). Out also:
; r3H the drive's flags (F_NOLONG: long names off).
; r2L = its DRV_* type (0: none), r3L = a native drive's tracks; the
; image's path in the buffer. X = 0, or DEV_NOT_FOUND when the drive
; holds no image.
OvInfo: jsr ParseDrive
        bcs @end
        stx mSlot
        lda argR1               ; r1 = 0: long names set (r3L 1: off)
        ora argR1+1
        bne @get
        lda drvFlags,x
        and #$FF ^ F_NOLONG
        lsr argR3
        bcc :+
        ora #F_NOLONG
:       sta drvFlags,x
        jsr TableOp             ; (its mount table entry; MOUNTS.INI anew:
        jmp Ini                 ; X its error; no info, no path copied)
@get:   lda drvFlags,x          ; r3H: its flags
        sta argR3+1
        lda driveType,x
        and #$0F
        sta argR2
        lda drvTracks,x
        sta argR3
        lda #0
        sta argR2+1
        lda argR2
        bne :+
        ldx #DEV_NOT_FOUND
@end:   rts
:       txa                     ; MOUNT_PATHS + 64 * drive
        asl
        asl
        asl
        asl
        asl
        asl
        sta r1L
        lda #>MOUNT_PATHS
        sta r1H
        lda argR1
        sta r0L
        lda argR1+1
        sta r0H
        lda #64
        sta r2L
        lda #0
        sta r2H
        ldy #REU_FETCH
        jsr ReuOp
        ldx #0
        rts

; Enter (from module 65, the image loaded): the drive's mount table
; entry, path (fePath) and an empty dirty map; the driver's state; the
; drive at its root; MOUNTS.INI written anew. X = 0 or the error.
Enter:  ldx mSlot
        lda mType
        ora #DRV_RAM
        sta driveType,x
        lda mBank
        sta ramBase,x
        lda mTracks
        sta drvTracks,x
        lda mResz               ; (F_RESIZED: mounted at another size,
        sta drvFlags,x          ; module 91; else 0)
        jsr TableOp
        lda #<fePath            ; the path, for the write-back
        sta r0L
        lda #>fePath
        sta r0H
        lda mSlot               ; MOUNT_PATHS + 64 * drive
        asl
        asl
        asl
        asl
        asl
        asl
        sta r1L
        lda #>MOUNT_PATHS
        sta r1H
        lda #64
        sta r2L
        lda #0
        sta r2H
        jsr SysOp
        lda #0                  ; the dirty map: zeros, a page at a time
        ldx #0
@zero:  sta diskBlkBuf,x
        inx
        bne @zero
        lda mSlot               ; DIRTY_MAPS + $2000 * drive
        asl
        asl
        asl
        asl
        asl
        clc
        adc #>DIRTY_MAPS
        sta mTmp
        lda #$20
        sta mBanks              ; (pages to go; mBanks no longer needed)
@page:  lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #0
        sta r1L
        sta r2L
        lda mTmp
        sta r1H
        lda #1
        sta r2H
        jsr SysOp
        inc mTmp
        dec mBanks
        bne @page
        jsr Common
        jmp Ini

        .endscope

        .segment "OVL70"
        .scope Mod70

        jmp Lines               ; entry 0

        .include "fereu.inc"
        .include "feult.inc"

U_PIECE         = 120

; Lines: the file's text. X = 0 or the error.
Lines:  jsr Begin
        ldx #0
@head:  lda Head,x
        jsr Out
        bne @end
        inx
        cpx #HeadLen
        bne @head
        lda #0
        sta mSlot
@drive: ldx mSlot
        lda driveType,x
        and #$0F
        beq @next
        jsr Line
        bne @end
@next:  inc mSlot
        lda mSlot
        cmp #4
        bne @drive
        lda uLen                ; the rest
        cmp #4 + 1
        bcc @done
        jmp Exec
@done:  ldx #0
@end:   rts

; Line: "X=path" for drive mSlot, ",tracks=N" when resized, CR LF. Z set
; when it worked, else X = the error.
Line:   lda #<diskBlkBuf        ; its path
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda mSlot
        asl
        asl
        asl
        asl
        asl
        asl
        sta r1L
        lda #>MOUNT_PATHS
        sta r1H
        lda #64
        sta r2L
        lda #0
        sta r2H
        ldy #REU_FETCH
        jsr ReuOp
        lda mSlot
        clc
        adc #'A'
        jsr Out
        bne @end
        lda #'='
        jsr Out
        bne @end
        ldx #0
@path:  stx mTmp
        lda diskBlkBuf,x
        beq @size
        jsr Out
        bne @end
        ldx mTmp
        inx
        cpx #64
        bne @path
@size:  ldx mSlot
        lda drvFlags,x
        and #F_RESIZED
        beq @long
        ldx #0
@tr:    stx mTmp
        lda Tracks,x
        beq @num
        jsr Out
        bne @end
        ldx mTmp
        inx
        bne @tr
@num:   ldx mSlot
        lda drvTracks,x
        jsr Decimal
        bne @end
@long:  ldx mSlot               ; ",longnames=off" (F_NOLONG)
        lda drvFlags,x
        and #F_NOLONG
        beq @eol
        ldx #0
@lo:    stx mTmp
        lda NoLong,x
        beq @eol
        jsr Out
        bne @end
        ldx mTmp
        inx
        bne @lo
@eol:   lda #13
        jsr Out
        bne @end
        lda #10
        jmp Out
@end:   rts

; Decimal: A (0-255) in decimal, without leading zeros. Z set when it
; worked, else X = the error.
Decimal:
        ldy #0                  ; hundreds, tens: subtracted
        sty mTmp                ; (mTmp: a digit was written)
        ldx #0
@pow:   ldy #'0'
@sub:   cmp Pows,x
        bcc @digit
        sbc Pows,x
        iny
        bne @sub
@digit: pha
        tya
        cpy #'0'
        bne @put
        ldy mTmp
        beq @skip
@put:   inc mTmp
        jsr Out
        beq :+
        pla                     ; (the error: X, Z clear)
        txa
        rts
:
@skip:  pla
        inx
        cpx #2
        bne @pow
        ora #'0'
        jmp Out

Pows:   .byte 100, 10

; Out: one byte of the text into the WRITE_DATA command, sent when it is
; full. Z set when it worked, else X = the error. Destroys A, Y; X kept
; when it worked.
Out:    pha
        lda uLen
        cmp #4 + U_PIECE
        bcc @put
        txa
        pha
        jsr Exec
        bne @fail
        jsr Begin
        pla
        tax
@put:   pla
        jsr UPut
        lda #0                  ; (Z set)
        rts
@fail:  pla
        pla
        txa
        rts

; Begin: uCmd = WRITE_DATA (its two zero bytes); Exec: sent. Z set when
; it worked, else X = the error.
Begin:  lda #U_WRITE
        jsr UBegin
        lda #0
        jsr UPut
        jmp UPut
Exec:   jsr UNoData
        jsr UExec
        txa
        rts


Head:           .byte "[drives]", 13, 10
HeadLen         = * - Head
Tracks:         .byte ",tracks=", 0
NoLong:         .byte ",longnames=off", 0

        .endscope
