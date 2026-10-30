; Write-back: the changed blocks of the REU drives into their image files
; on the Ultimate (docs/DESIGN.md, "Write-back", "Image protection").
; Overlay module 1 (src/kernal/overlay.s). Called from MainLoop a few
; seconds after the last write (WbCheck in the disk driver), never inside
; a disk call.
;
; Per changed drive: its path (stored at boot in REU $01:0200 + 64 *
; drive), the folder; before the first write-back after a mount the image
; is copied into GEOULTRA/BACKUP/ under its own name (the firmware's copy
; command takes a destination folder and keeps the name; the home path is
; at REU $01:0300); then the image is opened (read/write, existing),
; and for every run of non-zero bytes in the dirty map (one bit per block,
; $01:2000 + $2000 * drive) the blocks are written with a seek and one
; SAVE_REU straight from the REU. Then the map is cleared and the drive's
; changed flag too. The UCI handshake is the one of src/kernal/mount.s.

        .include "geos.inc"
        .include "hw.inc"

        .export WriteBackNow, Begin, Put, Simple, cmdLen, dmaCmd, DmaGo, status
        .import OvlCall, uciPresent, wbPending, wbDelay, drvTracks, drvFlags, hibState, HibSuspend
        .export FreeNativeOvl, NativeOvl, NatBamOvl, NatSureOvl, Ovl1571, natLoaded

path            = $9F70         ; the slot's scratch area (overlay.s)
cmdBuf          = $9FB0
uciCtrl         = $DF1C
uciCmd          = $DF1D
uciResp         = $DF1E
uciStat         = $DF1F
TARGET_DOS      = $01
DOS_OPEN        = $02
DOS_CLOSE       = $03
DOS_SEEK        = $06
DOS_DELETE      = $09
DOS_COPY        = $0B
DOS_CD          = $11
DOS_MKDIR       = $16
DOS_SAVE_REU    = $22
SYS_BANK        = 1
F_DIRTY         = $01
F_BACKUP        = $04

        .segment "CODE"

WriteBackNow:
        jsr OvlCall
        .byte 1, 0
WriteDrive:
        jsr OvlCall
        .byte 2, 0
FreeNativeOvl:                  ; CalcBlksFree on native images (reudrv.s)
        jsr OvlCall
        .byte 6, 0
NativeOvl:                      ; native BAM work (reudrv.s, BamType)
        jsr OvlCall
        .byte 3, 0
NatBamOvl:                      ; native BAM working copy (reudrv.s, DirHead)
        jsr OvlCall
        .byte 6, 3
NatSureOvl:                     ; the working copy is the current drive's
        jsr OvlCall
        .byte 6, 6
Ovl1571:                        ; 1571 BAM work (reudrv.s, BamType)
        jsr OvlCall
        .byte 7, 0

        .segment "DATA"

natLoaded:      .byte 0         ; drive whose native BAM is in the working copy


        .segment "OVL1"

        jmp WriteBack           ; entry 0

; WriteBack: every changed drive. A, X, Y destroyed.
WriteBack:
        lda uciPresent
        beq @end
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        ldx #0
@drive: stx slot
        lda driveType,x
        and #$0F
        beq @next
        lda drvFlags,x
        and #F_DIRTY
        beq @next
        jsr Drive
@next:  ldx slot
        inx
        cpx #4
        bne @drive
        ldx #3                  ; a drive still changed (its write failed):
        lda #0                  ; tried again after RETRY_DELAY frames
@still: ora drvFlags,x
        dex
        bpl @still
        and #F_DIRTY
        sta wbPending
        beq @saved
        lda #RETRY_DELAY
        sta wbDelay
@saved:
        pla
        sta CPU_PORT
        bit hibState            ; a quiet moment after changes: the
        bvc @end                ; session saved too (HibTick)
        lda #0
        sta hibState
        jmp HibSuspend
@end:   rts

; Drive: write drive slot back.
Drive:  jsr FetchPath
        ldx slot
        lda drvFlags,x
        and #F_BACKUP
        bne @cd
        jsr BackupDir           ; GEOULTRA/BACKUP/ without an old copy
        bne @end                ; not there: no backup, no write
@cd:    lda #DOS_CD             ; the folder: the path up to its last "/"
        jsr Begin
        ldx #0
@dir:   cpx nameAt
        beq @go
        lda path,x
        jsr Put
        inx
        bne @dir
@go:    jsr Simple
        bne @end
        ldx slot
        lda drvFlags,x
        and #F_BACKUP
        bne @open
        lda #DOS_COPY           ; the image as mounted, into BACKUP/
        jsr Begin
        jsr PutName
        lda #0
        jsr Put
        jsr PutBackup
        jsr Simple
        bne @end                ; no backup, no write
        ldx slot
        lda drvFlags,x
        ora #F_BACKUP
        sta drvFlags,x
@open:  lda #DOS_OPEN
        jsr Begin
        lda #$03                ; read/write, existing
        jsr Put
        jsr PutName
        jsr Simple
        bne @end
        jsr Blocks
        jmp WriteDrive          ; module 2: the blocks, then close
@end:   rts

; BackupDir: into <home>BACKUP/ (made when missing), then an old copy of
; the image's name there deleted. Z set when in BACKUP/: only then is
; anything deleted (an absolute path, never the image's own folder).
BackupDir:
        lda #DOS_CD
        jsr Begin
        jsr PutBackup
        jsr Simple
        beq @delete
        lda #DOS_CD
        jsr Begin
        jsr PutHome
        jsr Simple
        bne @fail
        lda #DOS_MKDIR
        jsr Begin
        ldx #0
@name:  lda backupName,x
        jsr Put
        inx
        cpx #6
        bne @name
        jsr Simple
        lda #DOS_CD
        jsr Begin
        jsr PutBackup
        jsr Simple
        bne @fail
@delete:
        lda #DOS_DELETE         ; (missing is fine)
        jsr Begin
        jsr PutName
        jsr Simple
        lda #0                  ; Z set: in BACKUP/
@fail:  rts

; PutBackup: "<home>BACKUP/".
PutBackup:
        jsr PutHome
        ldx #0
@char:  lda backupName,x
        jsr Put
        inx
        cpx #7
        bne @char
        rts
backupName:
        .byte "BACKUP/"

; PutHome: the home path from REU $01:0300 (32 bytes, ending with "/").
PutHome:
        lda #$00
        sta reuAddr
        lda #$03
        sta reuAddr+1
        lda cmdLen
        clc
        adc #<cmdBuf
        ldx #>cmdBuf
        ldy #32
        jsr Dma1Fetch
        ldy cmdLen
@end:   lda cmdBuf,y
        beq @done
        iny
        bne @end
@done:  sty cmdLen
        rts

; Blocks: total = the image's blocks, mapLen = its dirty map's bytes.
Blocks: ldx slot
        lda driveType,x
        and #$0F
        tay
        lda blocksLo,y
        sta total
        lda blocksHi,y
        sta total+1
        cpy #DRV_NATIVE
        bne @map
        lda #0
        sta total
        lda drvTracks,x
        sta total+1
@map:   lda total               ; (total + 7) / 8
        clc
        adc #7
        sta mapLen
        lda total+1
        adc #0
        ldx #3
@div:   lsr
        ror mapLen
        dex
        bne @div
        sta mapLen+1
        rts

blocksLo:       .byte 0, <683, <1366, <3200, 0
blocksHi:       .byte 0, >683, >1366, >3200, 0

; FetchPath: path from the REU; nameAt = after its last "/".
FetchPath:
        lda slot                ; $01:0200 + 64 * slot
        asl
        asl
        asl
        asl
        asl
        asl
        sta reuAddr
        lda #$02
        sta reuAddr+1
        lda #<path
        ldx #>path
        ldy #64
        jsr Dma1Fetch
        ldx #0
        stx nameAt
@scan:  lda path,x
        beq @end
        inx
        cmp #'/'
        bne @scan
        stx nameAt
        beq @scan
        bne @scan
@end:   rts

        .segment "DRVEXT"               ; resident: after the disk driver

; Dma1 / Dma1Fetch: A/X = C64 address, Y = length, reuAddr/+1 set; bank
; 1, fetch.
Dma1:
Dma1Fetch:
        pha
        lda #REU_FETCH
        sta dmaCmd
        pla
DmaGo:  sta reuC64
        stx reuC64+1
        sty reuLen
        lda #0
        sta reuLen+1
        sta reuCtrl
        lda #SYS_BANK
        sta reuAddr+2
        lda dmaCmd
        sta reuCmd
        rts


; --- Commands ---------------------------------------------------------------

; Begin: a DOS command A; Put: one more byte. PutName: the file name.
Begin:  pha
        lda #TARGET_DOS
        sta cmdBuf
        pla
        sta cmdBuf+1
        lda #2
        sta cmdLen
        rts
Put:    ldy cmdLen
        sta cmdBuf,y
        inc cmdLen
        rts
PutName:
        ldx nameAt
@char:  lda path,x
        beq @end
        jsr Put
        inx
        bne @char
@end:   rts

; Simple: send, drop the data, status; Z set on "00".
Simple: ldx #0                  ; idle; an old reply is released
@idle:  lda uciCtrl
        and #$30
        beq @write
        and #$20
        beq @idle
        lda #$02
        sta uciCtrl
        bne @idle
@write: lda cmdBuf,x
        sta uciCmd
        inx
        cpx cmdLen
        bne @write
        lda #$01
        sta uciCtrl
        lda uciCtrl
        and #$08
        beq @taken
        lda #$08
        sta uciCtrl
        ldx #0
        beq @idle
@taken: lda uciCtrl
        and #$01
        bne @taken
        lda uciCtrl
        and #$30
        cmp #$10
        beq @taken
@data:  bit uciCtrl             ; the data is not needed
        bpl @stat
        lda uciResp
        jmp @data
@stat:  ldx #0                  ; the first two characters
        stx status
        stx status+1
@char:  bit uciCtrl
        bvc @acc
        lda uciStat
        cpx #2
        bcs @char
        sta status,x
        inx
        bne @char
@acc:   lda #$02
        sta uciCtrl
@wait:  lda uciCtrl
        and #$02
        bne @wait
        lda status
        cmp #'0'
        bne @rts
        lda status+1
        cmp #'0'
@rts:   rts

; --- State (resident: modules 1 and 2 share it) ----------------------------

slot:   .res 1
nameAt: .res 1
total:  .res 2
mapLen: .res 2
mapIdx: .res 2
runStart: .res 2
first:  .res 2
last:   .res 2
mapByte: .res 1
dmaCmd: .res 1
status: .res 2
cmdLen: .res 1

RETRY_DELAY     = 250           ; frames (5 s) before a failed write-back
                                ; is tried again

        .segment "OVL2"

        jmp WriteDrive2         ; entry 0

; WriteDrive (module 2, entry 0): the open image of drive slot: every run
; of changed blocks, then close, clear the map and the changed flag. When
; a SEEK or SAVE_REU failed (stick removed, file write-protected, stick
; full), the map and the flag stay set: the next write-back tries again
; (code sweep 2026-10-30: the changes counted as saved and were lost).
WriteDrive2:
        lda #0
        sta mapIdx
        sta mapIdx+1
        sta wrFailed
@scan:  jsr MapEnd
        bcs @done
        jsr MapByte
        bne @run
        jsr NextByte
        jmp @scan
@run:   lda mapIdx              ; a run of changed bytes
        sta runStart
        lda mapIdx+1
        sta runStart+1
@more:  jsr NextByte
        jsr MapEnd
        bcs @write
        jsr MapByte
        bne @more
@write: jsr WriteRun
        jmp @scan
@done:  lda #DOS_CLOSE
        jsr Begin
        jsr Simple
        lda wrFailed            ; not all written: keep map and flag
        bne @end
        jsr ClearMap
        ldx slot
        lda drvFlags,x
        and #<~F_DIRTY
        sta drvFlags,x
        jsr StoreFlags
@end:   rts

MapEnd: lda mapIdx+1            ; C set at the end of the map
        cmp mapLen+1
        bne @cmp
        lda mapIdx
        cmp mapLen
@cmp:   rts

NextByte:
        inc mapIdx
        bne @end
        inc mapIdx+1
@end:   rts

; MapByte: A = the map byte mapIdx (Z: unchanged blocks).
MapByte:
        lda mapIdx
        sta reuAddr
        lda slot
        asl
        asl
        asl
        asl
        asl
        clc
        adc #$20
        adc mapIdx+1
        sta reuAddr+1
        lda #<mapByte
        ldx #>mapByte
        ldy #1
        jsr Dma1
        lda mapByte
        rts

; WriteRun: blocks runStart * 8 .. min(mapIdx * 8, total): seek, SAVE_REU.
WriteRun:
        lda runStart            ; first block
        sta first
        lda runStart+1
        ldx #3
@s:     asl first
        rol
        dex
        bne @s
        sta first+1
        lda mapIdx              ; end block
        sta last
        lda mapIdx+1
        ldx #3
@e:     asl last
        rol
        dex
        bne @e
        sta last+1
        cmp total+1             ; clipped to the image
        bne @clip
        lda last
        cmp total
@clip:  bcc @len
        lda total
        sta last
        lda total+1
        sta last+1
@len:   sec                     ; blocks in the run
        lda last
        sbc first
        sta last
        lda last+1
        sbc first+1
        sta last+1
        lda #DOS_SEEK           ; position: first * 256
        jsr Begin
        lda #0
        jsr Put
        lda first
        jsr Put
        lda first+1
        jsr Put
        lda #0
        jsr Put
        jsr Simple
        beq :+
        lda #$FF
        sta wrFailed
:       lda #DOS_SAVE_REU       ; REU: drive bank + first * 256
        jsr Begin
        lda #0
        jsr Put
        lda first
        jsr Put
        ldx slot
        lda ramBase,x
        clc
        adc first+1
        jsr Put
        lda #0
        jsr Put
        jsr Put                 ; length: blocks * 256
        lda last
        jsr Put
        lda last+1
        jsr Put
        lda #0
        jsr Put
        jsr Simple
        beq @ok
        lda #$FF
        sta wrFailed
@ok:    rts

; ClearMap: the drive's dirty map ($2000 bytes) to zeros.
ClearMap:
        lda #0
        sta reuAddr
        sta mapByte
        lda slot
        asl
        asl
        asl
        asl
        asl
        clc
        adc #$20
        sta reuAddr+1
        lda #$80                ; the same C64 byte for all
        sta reuCtrl
        lda #<mapByte
        sta reuC64
        lda #>mapByte
        sta reuC64+1
        lda #0
        sta reuLen
        lda #$20
        sta reuLen+1
        lda #SYS_BANK
        sta reuAddr+2
        lda #REU_STASH
        sta reuCmd
        lda #0
        sta reuCtrl
        rts

; StoreFlags: the drive's flags to its mount table entry ($01:0123 + 32 *
; slot).
StoreFlags:
        ldx slot
        lda drvFlags,x
        sta mapByte
        txa
        asl
        asl
        asl
        asl
        asl
        clc
        adc #$23
        sta reuAddr
        lda #$01
        sta reuAddr+1
        lda #<mapByte
        ldx #>mapByte
        ldy #1
        lda #REU_STASH
        sta dmaCmd
        lda #<mapByte
        jmp DmaGo



wrFailed:       .byte 0         ; module 2: a SEEK or SAVE_REU failed (no
                                ; nested overlay calls while it is used)