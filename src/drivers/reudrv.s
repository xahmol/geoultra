; REU image disk driver at $9000: every drive A-D is a disk image held
; whole in the REU (docs/DESIGN.md, "Drives A-D"). One driver serves all
; types; a geometry step maps track/sector to a block number, and a block
; is one 256-byte REU DMA. Written from the HG2G2022 descriptions of the
; disk routines; behaviour details (the ChkDkGEOS compare length, the
; 18 bytes OpenDisk copies, NextDirEntry's border handling, which
; registers InitForIO switches) follow the reassembled GEOS 2.0 1541
; driver, mist64/geos drv/drv1541.s, read as behaviour reference only.
; Own code; checked with tests/conformance/disk.py.
;
; Mount table (REU bank 1, written by the mount code; the harness writes
; it into its REU image): $01:0100 "GUMT", version; $01:0120 + 32 * slot,
; slot = drive (0-3): +0 type (0 none, 1 1541, 2 1571, 3 1581, 4 native),
; +1 first REU bank, +2 tracks (native), +3 flags (bit 0 changed since
; the last write-back, bit 1 read-only). Dirty map: one bit per block at
; $01:2000 + $2000 * slot.

        .include "geos.inc"
        .include "hw.inc"
        .include "sysdrive.inc"

        .export DiskInit, saveFlag, WbCheck, WbTick, uciPresent, wbPending
        .export drvTracks, drvFlags
        .import WriteBackNow, FreeNativeOvl, NativeOvl, NatBamOvl, NatSureOvl, Ovl1571
        .import ProtExecute, ProtStatus, SetGEOSDiskOvl, folderT, folderS
        .export DrvGetDirHead, DrvPutDirHead, CalcBlksFree, SetNextFree, ClearAndWrite
        .export geosId, FindBAMBit, FreeBlock, AllocateBlock, DrvReadBuff, DrvWriteBuff
        .import natLoaded
        .import Trap, CopyFString, GetPtrCurDkNm, Ddiv

FRST_FILE_ENTRY = 2
DIR_TRACK       = 18            ; 1541
INSUFF_SPACE    = 3
FULL_DIRECTORY  = 4
BAD_BAM         = 6
WR_PR_ON        = $26           ; write protected
WR_VER_ERR      = $25           ; verify failed
BAD_SECTOR      = $20           ; sector beyond the track (header not found)
SYS_BANK        = 1
MOUNT_TAB       = $0100
MOUNT_ENTRY     = $0120
DIRTY_MAP       = $20           ; page of slot 0's dirty map in bank 1
F_DIRTY         = $01
F_READONLY      = $02
WB_DELAY        = 150           ; frames (3 s at 50 Hz) after the last write
dir3Head        = $9C80         ; third BAM block (1581), end of the driver

        .segment "DRIVER"

; $9000: vectors the kernal's jump table entries go through
        .word InitForIO, DoneWithIO, NoTurbo, NoTurbo, NoTurbo
        .word ChangeDiskDevice, NewDisk, ReadBlock, WriteBlock, VerWriteBlock
        .word OpenDisk, ReadBlock, WriteBlock, DrvGetDirHead, DrvPutDirHead
        .word GetFreeDirBlk, CalcBlksFree, FreeBlock, SetNextFree
        .word FindBAMBit, NxtBlkAlloc, BlkAlloc, ChkDkGEOS, SetGEOSDiskOvl

; $9030: entries applications call directly
        jmp FirstDirEntry
        jmp NextDirEntry
        jmp GetBorder
        jmp AddDirBlock
        jmp DrvReadBuff
        jmp DrvWriteBuff
        jsr Trap                ; SendTSBytes (serial drives only)
        jsr Trap                ; CheckErrors (serial drives only)
        jmp AllocateBlock
        jmp ReadBlock           ; ReadLink: the whole block

; Per drive (index curDrive - 8); driveType and ramBase are the GEOS ones.
drvTracks:      .res 4          ; native: track count
drvFlags:       .res 4          ; mount table flags (F_DIRTY, F_READONLY)

borderFlag:     .byte 0
locBase:        .byte 0         ; Locate: the image's first REU bank
locSys:         .byte 0         ; Locate: $80 for a block of drive E
blkLo:          .byte 0         ; block number within the image
blkHi:          .byte 0
track:          .byte 0
dmaC64:         .word 0         ; DMA parameters
dmaReu:         .res 3
dmaLen:         .word 0
dirtyByte:      .byte 0
count:          .byte 0
saveFlag:       .byte 0         ; bit 7: BlkAlloc called from SaveFile (1581)
nativeFrom:     .word 0         ; BamType's caller (native drives)
uciPresent:     .byte 0         ; the boot found a UCI: write-back possible
wbPending:      .byte 0         ; a drive has changes not written back
wbDelay:        .byte 0         ; frames until the write-back may run
firstTwo:       .byte 0         ; 1581 BlkAlloc: blocks before track 35
dirIndex:       .byte 0
ioP:            .byte 0         ; InitForIO saves
ioPort:         .byte 0
ioIrqMask:      .byte 0
ioClock:        .byte 0
ioSprites:      .byte 0

; --- I/O and turbo -------------------------------------------------------

; InitForIO: interrupts off, sprites off, C64 Kernal ROM and I/O in for
; serial routines (printer drivers). Code running until DoneWithIO must
; not lie at $E000-$FFFF. Destroys A, Y.
InitForIO:
        php
        pla
        sta ioP
        sei
        lda CPU_PORT
        sta ioPort
        lda #$36                ; Kernal ROM and I/O, BASIC out
        sta CPU_PORT
        lda vicIrqMask
        sta ioIrqMask
        lda $D030               ; C128 / U64 clock register: 1 MHz
        sta ioClock
        ldy #0
        sty $D030
        sty vicIrqMask
        lda #$7F
        sta vicIrq
        sta cia1Icr
        sta cia2Icr
        lda #<IoIrq             ; the ROM's vectors run while it is in
        sta $0314
        lda #>IoIrq
        sta $0315
        lda #<IoNmi
        sta $0318
        lda #>IoNmi
        sta $0319
        lda #$3F                ; serial lines and VIC bank: outputs
        sta cia2DdrA
        lda vicSprEnable
        sta ioSprites
        sty vicSprEnable
        rts

; DoneWithIO: everything InitForIO changed back. Destroys A.
DoneWithIO:
        sei
        lda ioClock
        sta $D030
        lda ioSprites
        sta vicSprEnable
        lda #$7F
        sta cia2Icr
        lda cia2Icr
        lda ioIrqMask
        sta vicIrqMask
        lda ioPort
        sta CPU_PORT
        lda ioP
        pha
        plp
        rts

IoIrq:  pla                     ; the ROM pushed A, X, Y
        tay
        pla
        tax
        pla
IoNmi:  rti

; NewDisk: nothing to do for an image. The bytes after the jmp are never
; run: an application's first-run check for its original disk (1541 drive
; code) finds the drive-execute and status calls after the first STA $8B
; behind NewDisk and calls those. GeoUltra's answers (ProtExecute,
; ProtStatus) report "not an original disk", unless the optional module
; is switched on (src/kernal/bypass.s, docs/DESIGN.md "Serial number").
NewDisk:
        jmp NoTurbo
        sta $8B
        jsr ProtExecute
        jsr ProtStatus

; EnterTurbo, ExitTurbo, PurgeTurbo: nothing to do for an image.
NoTurbo:
        ldx #0
        rts

; ChangeDiskDevice: A = new device number (8-11) for the current drive.
ChangeDiskDevice:
        tay
        ldx curDrive
        lda driveType-8,x
        sta driveType-8,y
        lda ramBase-8,x
        sta ramBase-8,y
        lda drvTracks-8,x
        sta drvTracks-8,y
        lda drvFlags-8,x
        sta drvFlags-8,y
        lda #0
        sta driveType-8,x
        sty curDrive
        sty curDevice
        ldx #0
        rts

; --- Write-back trigger (the write-back itself: src/kernal/writeback.s) ---

; WbTick (interrupt level): count the delay down.
WbTick: lda wbDelay
        beq @end
        dec wbDelay
@end:   rts

; WbCheck (MainLoop): write changed drives back once the delay is over.
WbCheck:
        lda uciPresent
        beq @end
        lda wbPending
        beq @end
        lda wbDelay
        bne @end
        jmp WriteBackNow
@end:   rts

; --- Blocks ---------------------------------------------------------------

; ReadBlock / GetBlock / ReadLink: r1 = track/sector, r4 = buffer.
; Returns X = error. r1, r4 unchanged; destroys A, Y.
ReadBlock:
        jsr Locate
        bcc BlkEnd
        ldy #REU_FETCH
        jsr DmaBlock
        jsr HeaderSwap
        ldx #0
BlkEnd: ldy #0
        rts

; WriteBlock / PutBlock: as ReadBlock, the other way.
WriteBlock:
        jsr Locate
        bcc BlkEnd
        ldy curDrive
        ldx #WR_PR_ON
        bit locSys              ; drive E: read-only
        bmi BlkEnd
        lda drvFlags-8,y
        and #F_READONLY
        bne BlkEnd
        jsr HeaderSwap          ; the disk's own layout on the disk
        ldy #REU_STASH
        jsr DmaBlock
        jsr HeaderSwap          ; the caller's buffer as it was
        jsr MarkDirty
        ldx #0
        beq BlkEnd

; VerWriteBlock: WriteBlock, then an REU compare.
VerWriteBlock:
        jsr WriteBlock
        txa
        bne BlkEnd
        jsr Locate              ; MarkDirty used the DMA address
        ldy #REU_STASH | 3
        jsr DmaBlock
        and #$20                ; compare fault
        beq BlkEnd
        ldx #WR_VER_ERR
        bne BlkEnd

; HeaderSwap: block 40/0 of a 1581 image (1/1 of a native one) at r4:
; bytes $04-$1C swapped with $90-$A8, so GEOS finds the disk name where a
; 1541 keeps it (GEOS 2.0's 1581 driver does the same, mist64/geos
; drv/drv1581.s; native: the same layout, own choice). Destroys A, X, Y.
HeaderSwap:
        ldy curDrive
        lda driveType-8,y
        and #$0F
        cmp #DRV_NATIVE         ; native: the header is 1/1
        beq @native
        cmp #DRV_1581
        bne @end
        lda r1L
        cmp #40
        bne @end
        lda r1H
        bne @end
        beq @go
@native:                        ; the current folder's header
        ldx curDrive
        lda r1L
        cmp folderT-8,x
        bne @end
        lda r1H
        cmp folderS-8,x
        bne @end
@go:
        ldy #4
@swap:  lda (r4),y
        tax
        tya
        clc
        adc #$8C
        tay
        lda (r4),y
        pha
        txa
        sta (r4),y
        tya
        sec
        sbc #$8C
        tay
        pla
        sta (r4),y
        iny
        cpy #$1D
        bne @swap
@end:   rts

DrvReadBuff:
        jsr BufPtr
        jmp ReadBlock
DrvWriteBuff:
        jsr BufPtr
        jmp WriteBlock
BufPtr: lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        rts


; Locate: r1 of the current drive -> blkHi/blkLo and dmaReu. C set when
; valid; else C clear and X = error. Tracks SYSDRV_TRACK+1 and up are drive
; E's blocks (docs/ARCHITECTURE.md "System drive"): its 1541 image at
; SYSDRV_BANK, track - SYSDRV_TRACK, on every drive but a native one that
; large (locSys = $80 then).
Locate: ldy curDrive
        lda driveType-8,y
        and #$0F
        bne @type
        ldx #DEV_NOT_FOUND
        clc
        rts
@type:  ldx ramBase-8,y
        stx locBase
        ldx #0
        stx blkLo
        stx blkHi
        stx locSys
        ldx r1L                 ; track
        beq BadTrack
        cpx #SYSDRV_TRACK + 1
        bcc @own
        cmp #DRV_NATIVE
        bcc @sys
        ldx drvTracks-8,y
        cpx #SYSDRV_TRACK + 1
        ldx r1L
        bcs @own                ; real tracks of this native drive
@sys:   lda #SYSDRV_BANK
        sta locBase
        lda #$80
        sta locSys
        txa
        sec
        sbc #SYSDRV_TRACK
        tax
        lda #DRV_1541
@own:   cmp #DRV_1581
        beq Loc1581
        bcs LocNative
        cpx #36                 ; 1541 / 1571
        bcc @side
        cmp #DRV_1571
        bne BadTrack
        cpx #71
        bcs BadTrack
        lda #<683               ; second side: after the 683 blocks of the first
        sta blkLo
        lda #>683
        sta blkHi
        txa
        sec
        sbc #35
        tax
@side:  stx track
        ldx #1
@sum:   cpx track
        beq @last
        jsr Sectors
        jsr AddBlk
        inx
        bne @sum
@last:  jsr Sectors
        cmp r1H
        bcc BadSector
        beq BadSector
        lda r1H
        jsr AddBlk
        jmp Address

BadTrack:
        ldx #INV_TRACK
        clc
        rts
BadSector:
        ldx #BAD_SECTOR
        clc
        rts

; 1581: 80 tracks of 40 sectors.
Loc1581:
        cpx #81
        bcs BadTrack
        lda r1H
        cmp #40
        bcs BadSector
@sum:   dex
        beq @last
        lda #40
        jsr AddBlk
        jmp @sum
@last:  lda r1H
        jsr AddBlk
        jmp Address

; Native: tracks of 256 blocks.
LocNative:
        txa
        cmp drvTracks-8,y
        beq @ok
        bcc @ok
        jmp BadTrack
@ok:    sec                     ; track - 1
        sbc #1
        sta blkHi
        lda r1H
        sta blkLo

; REU address: the drive's first bank, block number as bank and page.
Address:
        ldy curDrive
        lda #0
        sta dmaReu
        lda blkLo
        sta dmaReu+1
        lda blkHi
        clc
        adc locBase
        sta dmaReu+2
        sec
        rts

AddBlk: clc
        adc blkLo
        sta blkLo
        bcc @end
        inc blkHi
@end:   rts

; Sectors: X = track (1-35) -> A = sectors on it (1541 speed zones).
Sectors:
        lda #21
        cpx #18
        bcc @end
        lda #19
        cpx #25
        bcc @end
        lda #18
        cpx #31
        bcc @end
        lda #17
@end:   rts

; DmaBlock: Y = REU command, r4 <-> dmaReu, 256 bytes. Returns A = status.
DmaBlock:
        lda r4L
        sta dmaC64
        lda r4H
        sta dmaC64+1
        lda #0
        sta dmaLen
        lda #1
        sta dmaLen+1

; Dma: Y = REU command with dmaC64, dmaReu, dmaLen. Returns A = status.
Dma:    php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        ldx #6
@par:   lda dmaC64,x
        sta reuC64,x
        dex
        bpl @par
        lda #0
        sta reuCtrl
        sty reuCmd
        ldx reuStatus
        pla
        sta CPU_PORT
        plp
        txa
        rts

; MarkDirty: set the block's bit in the dirty map, and the drive's
; changed flag in the mount table the first time.
MarkDirty:
        lda #WB_DELAY           ; write back a while after the last write
        sta wbDelay
        lda #1
        sta wbPending
        lda blkHi               ; dmaReu = map + block / 8
        sta dmaReu+1
        lda blkLo
        ldx #3
@div:   lsr dmaReu+1
        ror
        dex
        bne @div
        sta dmaReu
        lda curDrive
        sec
        sbc #8
        asl
        asl
        asl
        asl
        asl
        adc #DIRTY_MAP
        adc dmaReu+1
        sta dmaReu+1
        lda #SYS_BANK
        sta dmaReu+2
        jsr Byte
        lda blkLo
        and #7
        tax
        lda #0
        sec
@bit:   rol
        dex
        bpl @bit
        ora dirtyByte
        sta dirtyByte
        jsr Stash
        ldy curDrive
        lda drvFlags-8,y
        and #F_DIRTY
        bne @end
        lda drvFlags-8,y
        ora #F_DIRTY
        sta drvFlags-8,y
        sta dirtyByte
        tya                     ; mount entry + 3
        sec
        sbc #8
        asl
        asl
        asl
        asl
        asl
        adc #<(MOUNT_ENTRY + 3)
        sta dmaReu
        lda #>MOUNT_ENTRY
        sta dmaReu+1
        jmp Stash
@end:   rts

; Byte / Stash: one byte between dirtyByte and dmaReu.
Byte:   ldy #REU_FETCH
        .byte $2C               ; bit abs: skips the next ldy
Stash:  ldy #REU_STASH
        lda #<dirtyByte
        sta dmaC64
        lda #>dirtyByte
        sta dmaC64+1
        lda #1
        sta dmaLen
        lda #0
        sta dmaLen+1
        jmp Dma

; --- Directory header and BAM blocks -------------------------------------

; GetDirHead / PutDirHead: the directory header to curDirHead and, per
; type, the further BAM blocks (dir2Head, dir3Head). Returns X = error,
; r4 = the last block's buffer. Destroys A, Y, r1.
DrvGetDirHead:
        lda #<ReadBlock
        ldy #>ReadBlock
        bne DirHead
DrvPutDirHead:
        lda #<WriteBlock
        ldy #>WriteBlock
DirHead:
        sta DirOp+1
        sty DirOp+2
        ldy curDrive
        lda driveType-8,y
        and #$0F
        bne @type
        ldx #DEV_NOT_FOUND
        bne @ptr
@type:  tay
        cpy #DRV_NATIVE         ; native: the current folder's header
        bne @start
        ldx curDrive
        lda folderT-8,x
        sta tNative
        lda folderS-8,x
        sta tNative+1
@start: lda headStart,y
        sta dirIndex
@next:  ldy dirIndex
        lda headTab,y
        beq @done
        bmi @bam
        sta r1L
        lda headTab+1,y
        sta r1H
        lda headTab+2,y
        sta r4L
        lda headTab+3,y
        sta r4H
        tya
        clc
        adc #4
        sta dirIndex
        jsr DirOp
        txa
        beq @next
        rts
@bam:   jmp NatBamOvl           ; native: the BAM's working copy (r4 kept)
@done:  ldx #0                  ; r4 = the last block read, as GEOS 2.0
        rts                     ; (curDirHead on a 1541, dir3Head on a 1581)
@ptr:   lda #<curDirHead
        sta r4L
        lda #>curDirHead
        sta r4H
        rts
DirOp:  jmp ReadBlock            ; ReadBlock or WriteBlock (set by DirHead)

; Per type: track, sector, buffer of each header block, 0 at the end.
headStart:
        .byte tNone - headTab, t1541 - headTab, t1571 - headTab
        .byte t1581 - headTab, tNative - headTab
headTab:
t1541:  .byte 18, 0, <curDirHead, >curDirHead
tNone:  .byte 0
t1571:  .byte 18, 0, <curDirHead, >curDirHead, 53, 0, <dir2Head, >dir2Head, 0
t1581:  .byte 40, 0, <curDirHead, >curDirHead, 40, 1, <dir2Head, >dir2Head
        .byte 40, 2, <dir3Head, >dir3Head, 0
tNative:
        .byte 1, 1, <curDirHead, >curDirHead, 1, 2, <dir2Head, >dir2Head, $FF

; OpenDisk: header in, isGEOS set, disk name to DrXCurDkNm. Returns X =
; error, r5 = the name. Destroys A, Y, r0-r4.
OpenDisk:
        jsr DrvGetDirHead
        txa
        bne @end
        lda #<curDirHead
        sta r5L
        lda #>curDirHead
        sta r5H
        jsr ChkDkGEOS
        lda #<(curDirHead + OFF_DISK_NAME)
        sta r4L
        lda #>(curDirHead + OFF_DISK_NAME)
        sta r4H
        ldx #r5
        jsr GetPtrCurDkNm
        ldx #r4
        ldy #r5
        lda #18                 ; name and the two bytes after it
        jsr CopyFString
        ldx #0
@end:   rts

; ChkDkGEOS: r5 = directory header. isGEOS = A = $FF when it carries the
; GEOS signature ("GEOS format"), else 0. Destroys A, Y.
ChkDkGEOS:
        ldy #OFF_GS_ID + 10
@cmp:   lda (r5),y
        cmp geosId - OFF_GS_ID,y
        bne @no
        dey
        cpy #OFF_GS_ID
        bcs @cmp
        lda #$FF
        .byte $2C
@no:    lda #0
        sta isGEOS
        rts

geosId: .byte "GEOS format V1.0"

; CalcBlksFree: r4 = free blocks, r3 = blocks of an empty disk. r5 =
; directory header (1541 / 1571). Destroys A, Y.
CalcBlksFree:
        lda #0
        sta r4L
        sta r4H
        ldy curDrive
        lda driveType-8,y
        and #$0F
        cmp #DRV_NATIVE
        bne @cbm
        jmp FreeNativeOvl
@cbm:   cmp #DRV_1581
        beq @1581
        pha
        ldy #4                  ; side 1: one count per track, 4 bytes each
@side1: cpy #4 * 18             ; not the directory track
        beq @skip1
        lda (r5),y
        jsr AddFree
@skip1: iny
        iny
        iny
        iny
        cpy #4 + 4 * 35
        bne @side1
        pla
        ldy #<664
        ldx #>664
        cmp #DRV_1571
        bne @total
        ldy #$DD                ; side 2: counts at $DD-$FF
@side2: cpy #$DD + 17           ; not track 53
        beq @skip2
        lda (r5),y
        jsr AddFree
@skip2: iny
        bne @side2
        ldy #<1328
        ldx #>1328
        bne @total
@1581:  ldy #$10                ; 40 tracks per BAM block, 6 bytes each
@b2:    cpy #$10 + 6 * 39       ; not track 40
        beq @s2
        lda dir2Head,y
        jsr AddFree
@s2:    lda dir3Head,y
        jsr AddFree
        tya
        clc
        adc #6
        tay
        bcc @b2                 ; 40 entries end at $100
        ldy #<3160
        ldx #>3160
@total: sty r3L
        stx r3H
        ldx #0
        rts

AddFree:
        clc
        adc r4L
        sta r4L
        bcc @end
        inc r4H
@end:   rts

; --- BAM and allocation (1541 and 1581 images; 1571 and native trap) -----
;
; The 1581 rules follow GEOS 2.0's 1581 driver (mist64/geos drv/drv1581.s,
; behaviour reference only): the BAM in dir2Head (tracks 1-40) and
; dir3Head (41-80), six bytes per track from $10 (count, then the sector
; bits); sectors searched one after another, tracks from the start down
; to 1, then from 41 up to 80, once more from 39 if that fails.

; FindBAMBit: r6 = track/sector. A = the BAM byte masked with r8H, Z set
; when the block is in use; r7H = offset of the track's free count (in
; curDirHead; on a 1581 from $10 of the track's BAM block), X = offset of
; the BAM byte. Destroys Y.
FindBAMBit:
        jsr BamType
fbbBam: bne Find1541
        jsr Off81
        lda r6H
        and #7
        tay
        lda bamBit,y
        sta r8H
        lda r6H
        lsr
        lsr
        lsr
        sec
        adc r7H
        tax
        lda r6L
        cmp #41
        bcs @hi
        lda dir2Head+$10,x
        and r8H
        rts
@hi:    lda dir3Head+$10,x
        and r8H
        rts
Find1541:
        lda r6L
        asl
        asl
        sta r7H
        lda r6H
        and #7
        tay
        lda bamBit,y
        sta r8H
        lda r6H
        lsr
        lsr
        lsr
        sec                     ; the bitmap follows the count byte
        adc r7H
        tax
        lda curDirHead,x
        and r8H
        rts

bamBit: .byte $01, $02, $04, $08, $10, $20, $40, $80

; AllocateBlock: r6 = block to mark used. X = 0 or BAD_BAM (already
; used). Destroys A, Y, r7, r8H.
AllocateBlock:
        jsr FindBAMBit
        beq BadBam
        jsr BamType
abBam:  bne @c1541
        jsr Flip81
        ldx r7H
        lda r6L
        cmp #41
        bcs @hi
        dec dir2Head+$10,x
        bcc @done
@hi:    dec dir3Head+$10,x
@done:  ldx #0
        rts
@c1541: jsr FindBAMBit          ; A, X again (BamType used A)
        eor curDirHead,x        ; A = the set bit: clear it
        sta curDirHead,x
        ldx r7H
        dec curDirHead,x
        ldx #0
        rts
BadBam: ldx #BAD_BAM
        rts

; FreeBlock: r6 = block to mark free. X = 0 or BAD_BAM (already free).
FreeBlock:
        jsr FindBAMBit
        bne BadBam
        jsr BamType
fbBam:  bne @f1541
        jsr Flip81
        ldx r7H
        lda r6L
        cmp #41
        bcs @hi
        inc dir2Head+$10,x
        bcc @done
@hi:    inc dir3Head+$10,x
@done:  ldx #0
        rts
@f1541: jsr FindBAMBit
        lda r8H
        ora curDirHead,x
        sta curDirHead,x
        ldx r7H
        inc curDirHead,x
        ldx #0
        rts

; SetNextFree: allocate the next free block after r3 (track/sector), the
; GEOS 2.0 way: interleave sectors on (one less from track 25), then the
; following tracks, never back to lower ones; the directory track only
; when the search starts on it. r3 = the block, X = 0 or INSUFF_SPACE.
; Destroys A, Y, r6, r7, r8H.
SetNextFree:
        jsr BamType
snfBam: bne @s1541
        jmp Next1581
@s1541: lda r3L
        sta r6L
        lda r3H
        clc
        adc interleave
        sta r6H
        lda r3L
        cmp #25
        bcc @start
        dec r6H
@start: cmp #DIR_TRACK
        beq @try
@track: lda r6L
        cmp #DIR_TRACK
        beq @next
@try:   lda r6L
        asl
        asl
        tax
        lda curDirHead,x        ; free blocks on the track
        beq @next
        ldx r6L
        jsr Sectors
        sta r7L
        sta count
@sector:
        lda r6H                 ; r6H modulo sectors on the track
@mod:   cmp r7L
        bcc @in
        sbc r7L
        bcs @mod
@in:    sta r6H
        jsr AllocateBlock
        txa
        beq @found
        inc r6H
        dec count
        bne @sector
@next:  inc r6L
        lda r6L
        cmp #36
        bcs @full
        sec                     ; next track: 2 * distance + 4 + interleave
        sbc r3L
        asl
        adc #4
        adc interleave
        sta r6H
        jmp @track
@found: lda r6L
        sta r3L
        lda r6H
        sta r3H
        rts
@full:  ldx #INSUFF_SPACE
        rts

; BamType: Z set for a 1581 image, clear for a 1541. Native and 1571:
; the calling routine's work is done by an overlay module (3: NativeOp,
; 7: Op1571; both know the routine by the return address taken here) and
; the result goes to that routine's caller. Other types: the routine
; returns WR_PR_ON. Destroys A, X, Y.
BamType:
        ldy curDrive
        lda driveType-8,y
        and #$0F
        cmp #DRV_1581
        beq @end
        cmp #DRV_1541
        bne @none
        lda #1                  ; Z clear
@end:   rts
@none:  tax
        pla
        sta nativeFrom
        pla
        sta nativeFrom+1
        cpx #DRV_NATIVE
        bne @not
        jmp NativeOvl
@not:   cpx #DRV_1571
        bne @wp
        jmp Ovl1571
@wp:    ldx #WR_PR_ON
        lda #0
        rts

; Off81: X = r7H = 6 * (track - 1) within its BAM block (track r6L).
Off81:  lda r6L
        cmp #41
        bcc @low
        sbc #40
@low:   sec
        sbc #1
        asl
        sta r7H
        asl
        clc
        adc r7H
        sta r7H
        tax
        rts

; Flip81: flip bit r8H of BAM byte X of track r6L.
Flip81: lda r6L
        cmp #41
        bcs @hi
        lda r8H
        eor dir2Head+$10,x
        sta dir2Head+$10,x
        rts
@hi:    lda r8H
        eor dir3Head+$10,x
        sta dir3Head+$10,x
        rts

; Next1581: SetNextFree on a 1581 image.
Next1581:
        jsr @search
        txa
        beq @end
        lda #39                 ; not found: once more from track 39
        sta r3L
@search:
        lda r3H
        clc
        adc #1
        sta r6H
        lda r3L
        sta r6L
        cmp #40                 ; the directory track only as the start
        beq @try
@track: lda r6L
        cmp #40
        beq @next
@try:   jsr Off81
        lda r6L
        cmp #41
        bcs @upper
        lda dir2Head+$10,x
        jmp @count
@upper: lda dir3Head+$10,x
@count: beq @next
        lda #40
        sta r7L
        sta count
@sector:
        lda r6H
@mod:   cmp r7L
        bcc @in
        sbc r7L
        bcs @mod
@in:    sta r6H
        jsr AllocateBlock
        txa
        beq @found
        inc r6H
        dec count
        bne @sector
@next:  lda r6L                 ; down to track 1, then up from 41
        cmp #41
        bcs @up
        dec r6L
        bne @range
        lda #41
        sta r6L
        bne @range
@up:    inc r6L
@range: lda r6L
        cmp #81
        bcs @full
        lda #0
        sta r6H
        jmp @track
@found: lda r6L
        sta r3L
        lda r6H
        sta r3H
@end:   rts
@full:  ldx #INSUFF_SPACE
        rts

; BlkAlloc: r2 bytes from track 1; NxtBlkAlloc: from r3. Writes the
; blocks to the table at r6, then 0 and the bytes used in the last block
; + 1. Returns X = error, r2 = blocks, r3 = the last block. Destroys A,
; Y, r4-r8.
BlkAlloc:
        jsr BamType
baBam:  bne @b1541
        lda #35                 ; 1581: from track 35, from SaveFile 39
        bit saveFlag
        bpl @track
        lda #39
@track: sta r3L
        lda #0
        sta r3H
        sta saveFlag
        lda #2                  ; then back to track 35 after two blocks
        sta firstTwo
        bne Alloc
@b1541: lda #0
        sta saveFlag
        lda #1
        sta r3L
        lda #0
        sta r3H
NxtBlkAlloc:
        lda #0
        sta firstTwo
Alloc:  lda r9L                 ; Ddiv destroys r9
        pha
        lda r9H
        pha
        lda r3L
        pha
        lda r3H
        pha
        lda #254                ; data bytes per block
        sta r3L
        lda #0
        sta r3H
        ldx #r2
        ldy #r3
        jsr Ddiv
        lda r8L                 ; a part block counts
        beq @free
        inc r2L
        bne @free
        inc r2H
@free:  lda #<curDirHead
        sta r5L
        lda #>curDirHead
        sta r5H
        jsr CalcBlksFree
        pla
        sta r3H
        pla
        sta r3L
        ldx #INSUFF_SPACE
        lda r4H                 ; blocks > free: no space
        cmp r2H
        bne @cmp
        lda r4L
        cmp r2L
@cmp:   bcc @end
        lda r6L
        sta r4L
        lda r6H
        sta r4H
        lda r2L
        sta r5L
        lda r2H
        sta r5H
@block: jsr SetNextFree
        txa
        bne @end
        ldy #0
        lda r3L
        sta (r4),y
        iny
        lda r3H
        sta (r4),y
        clc
        lda r4L
        adc #2
        sta r4L
        bcc @first
        inc r4H
@first: lda firstTwo
        beq @count
        dec firstTwo
        bne @count
        lda #35
        sta r3L
@count: lda r5L
        bne @low
        dec r5H
@low:   dec r5L
        lda r5L
        ora r5H
        bne @block
        ldy #0
        tya
        sta (r4),y
        iny
        lda r8L
        bne @last
        lda #254
@last:  clc
        adc #1
        sta (r4),y
        ldx #0
@end:   pla
        sta r9H
        pla
        sta r9L
        rts

; GetFreeDirBlk: r10L = directory page (1-18) to start at. Finds the
; first empty entry from there, adding directory blocks as needed. The
; block is in diskBlkBuf, r1 its address, Y the entry's offset, r10L its
; page. X = 0 or FULL_DIRECTORY. Destroys A, r0, r3, r5, r7, r8.
GetFreeDirBlk:
        php
        sei
        lda r6L
        pha
        lda r2L
        pha
        lda r2H
        pha
        ldx r10L
        inx
        stx r6L
        jsr FirstDirBlock
@read:  jsr DrvReadBuff
@got:   txa
        bne @end
        dec r6L
        beq @page
@link:  lda diskBlkBuf
        bne @follow
        jsr AddDirBlock
        jmp @got
@follow:
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        jmp @read
@page:  ldy #FRST_FILE_ENTRY
@slot:  lda diskBlkBuf,y
        beq @end
        tya
        clc
        adc #32
        tay
        bcc @slot
        lda #1                  ; full: the next page
        sta r6L
        ldx #FULL_DIRECTORY
        ldy r10L
        iny
        sty r10L
        cpy #18
        bcc @link
@end:   pla
        sta r2H
        pla
        sta r2L
        pla
        sta r6L
        plp
        rts

; AddDirBlock: r1 = the last directory block (in diskBlkBuf). Allocates
; a block on the directory track, links it, writes both; the new, empty
; block is then in diskBlkBuf and r1. X = 0 or FULL_DIRECTORY. The BAM
; change stays in curDirHead (the caller writes it).
AddDirBlock:
        lda r6L
        pha
        lda r6H
        pha
        jsr DirTrackFree
        ldx #FULL_DIRECTORY
        and #$FF
        beq @end
        lda r1L
        sta r3L
        lda r1H
        sta r3H
        jsr SetNextFree
        lda r3L
        sta diskBlkBuf
        lda r3H
        sta diskBlkBuf+1
        jsr DrvWriteBuff
        txa
        bne @end
        lda r3L
        sta r1L
        lda r3H
        sta r1H
        jsr ClearAndWrite
@end:   pla
        sta r6H
        pla
        sta r6L
        rts

; DirTrackFree: A = free blocks on the directory track.
DirTrackFree:
        jsr BamType
dtfBam: bne @t1541
        lda dir2Head + $10 + 6 * 39
        rts
@t1541: lda curDirHead + 4 * DIR_TRACK
        rts

; FirstDirBlock: r1 = the first directory block of the drive's type.
FirstDirBlock:
        ldy curDrive
        lda driveType-8,y
        and #$0F
        cmp #DRV_NATIVE         ; native: the current folder's first block
        bne @table              ; (its header's link, in curDirHead)
        lda curDirHead
        sta r1L
        lda curDirHead+1
        sta r1H
        rts
@table: tay
        lda dirTrack,y
        sta r1L
        lda dirSector,y
        sta r1H
        rts

; ClearAndWrite: an empty block (link 0, $FF) to r1.
ClearAndWrite:
        lda #0
        tay
@clear: sta diskBlkBuf,y
        iny
        bne @clear
        dey
        sty diskBlkBuf+1
        jmp DrvWriteBuff

; --- Directory entries ---------------------------------------------------

; Get1stDirEntry: the first directory block to diskBlkBuf, r5 = its first
; entry. Returns X = error. Destroys A, Y, r1, r4.
FirstDirEntry:
        jsr FirstDirBlock       ; (native: the current folder's header link)
        lda #0
        sta borderFlag
EntryBlock:
        jsr DrvReadBuff
        lda #<(diskBlkBuf + FRST_FILE_ENTRY)
        sta r5L
        lda #>(diskBlkBuf + FRST_FILE_ENTRY)
        sta r5H
        ldy #0
        rts

dirTrack:       .byte 0, 18, 18, 40, 1
dirSector:      .byte 0, 1, 1, 3, 34

; GetNxtDirEntry: r5 = the next entry. At the end of the directory the
; GEOS border block follows (once). Returns X = error, Y = $FF at the
; end. Destroys A, r1, r4.
NextDirEntry:
        ldx #0
        ldy #0
        lda r5L
        clc
        adc #32
        sta r5L
        bcc @cmp
        inc r5H
@cmp:   lda r5H                 ; past the block (also after the end):
        cmp #>diskBlkBuf        ; r5 >= diskBlkBuf + $FF
        bne @past
        lda r5L
        cmp #$FF
        bcc @end
@past:  ldy #$FF
        lda diskBlkBuf          ; link to the next block
        beq @last
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        jmp EntryBlock
@last:  lda borderFlag
        bne @end
        dec borderFlag
        jsr GetBorder
        txa
        bne @end
        tya
        beq EntryBlock
@end:   rts

; GetBorder: r1 = the GEOS border block; Y = $FF on a non-GEOS disk.
; Returns X = error. Destroys A, r4, r5.
GetBorder:
        jsr DrvGetDirHead
        txa
        bne @end
        lda #<curDirHead
        sta r5L
        lda #>curDirHead
        sta r5H
        jsr ChkDkGEOS
        ldy #$FF
        and #$FF
        beq @ok
        lda curDirHead + OFF_OP_TR_SC
        sta r1L
        lda curDirHead + OFF_OP_TR_SC + 1
        sta r1H
        ldy #0
@ok:    ldx #0
@end:   rts

; --- Start-up -------------------------------------------------------------

        .segment "INIT"                 ; cold start only ($5000)

; DiskInit (cold start): drives from the mount table in the REU, then
; drive A (8) current and opened. Destroys A, X, Y, r0-r5.
DiskInit:
        lda #<diskBlkBuf
        sta dmaC64
        lda #>diskBlkBuf
        sta dmaC64+1
        lda #<MOUNT_TAB
        sta dmaReu
        lda #>MOUNT_TAB
        sta dmaReu+1
        lda #SYS_BANK
        sta dmaReu+2
        lda #$A0
        sta dmaLen
        lda #0
        sta dmaLen+1
        sta NUMDRV
        ldx #3
@clear: sta driveType,x
        dex
        bpl @clear
        ldy #REU_FETCH
        jsr Dma
        ldx #3
@sig:   lda diskBlkBuf,x
        cmp mountSig,x
        bne @none
        dex
        bpl @sig
        ldx #0                  ; entries at diskBlkBuf + $20 + 32 * slot
        ldy #$20
@slot:  lda diskBlkBuf,y
        beq @next
        cmp #DRV_NATIVE + 1
        bcs @next
        ora #DRV_RAM
        sta driveType,x
        lda diskBlkBuf+1,y
        sta ramBase,x
        lda diskBlkBuf+2,y
        sta drvTracks,x
        lda diskBlkBuf+3,y
        sta drvFlags,x
        inc NUMDRV
@next:  tya
        clc
        adc #32
        tay
        inx
        cpx #4
        bne @slot
@none:  lda #8                  ; GEOS 2.0's sector interleave
        sta interleave
        sta curDrive
        sta curDevice
        lda driveType
        sta curType
        beq @end
        jmp OpenDisk
@end:   rts

mountSig:       .byte "GUMT"

        .segment "OVL3"                 ; overlay module 3: native allocation

        jmp NativeOp            ; entry 0

; NativeOp: the BAM work of the driver routine that called BamType
; (nativeFrom) on a native image; returns to that routine's caller. The
; BAM lies in the image (in the REU) from 1/2 offset $20, 32 bytes a
; track, sector 0 in bit 7 (CMD native format, checked on a DNP made
; by CMD-compatible software); a bit set means free. Behaviour of the
; allocation follows GEOS 2.0's 1541/1581 routines where they apply;
; SetNextFree searches on from r3, then from track 1.
NativeOp:
        ldx #0
@find:  lda nativeFrom
        cmp natLo,x
        bne @next
        lda nativeFrom+1
        cmp natHi,x
        beq @found
@next:  inx
        cpx #6
        bne @find
        ldx #WR_PR_ON           ; (not reached)
        rts
@found: lda natJmpLo,x
        sta @jmp+1
        lda natJmpHi,x
        sta @jmp+2
@jmp:   jmp $FFFF

natLo:  .byte <(fbbBam-1), <(abBam-1), <(fbBam-1), <(snfBam-1), <(baBam-1), <(dtfBam-1)
natHi:  .byte >(fbbBam-1), >(abBam-1), >(fbBam-1), >(snfBam-1), >(baBam-1), >(dtfBam-1)
natJmpLo:
        .byte <NatFind, <NatAlloc, <NatFree, <NatNext, <NatBlkAlloc, <NatDirFree
natJmpHi:
        .byte >NatFind, >NatAlloc, >NatFree, >NatNext, >NatBlkAlloc, >NatDirFree

; NatFind (FindBAMBit): r6 = block. A = the BAM byte AND r8H (Z set:
; used), r8H = the sector's bit, dirtyByte = the byte, dmaReu its REU
; address, blkLo = the BAM block (1/blkLo) holding it.
NatFind:
        jsr NatSureOvl
        lda r6L                 ; offset = $0220 + 32 * (track - 1) + sector / 8
        sec
        sbc #1
        sta dmaReu+1            ; (track - 1) * 32 = (track - 1) * 256 / 8
        lda #0
        ldx #3
@div:   lsr dmaReu+1
        ror
        dex
        bne @div
        sta dmaReu
        lda r6H
        lsr
        lsr
        lsr
        clc
        adc #$20
        adc dmaReu
        sta dmaReu
        lda dmaReu+1            ; in the working copy: page NAT_WORK for 1/2
        adc #NAT_WORK
        sta dmaReu+1
        lda #SYS_BANK
        sta dmaReu+2
        lda r6H
        and #7
        tax
        lda #$80
@bit:   dex
        bmi @mask
        lsr
        bne @bit
@mask:  sta r8H
        jsr Byte
        lda dirtyByte
        and r8H
        rts

; NatAlloc / NatFree (AllocateBlock / FreeBlock after FindBAMBit): flip
; the bit, store the byte, mark the BAM block for the write-back. X = 0.
NatAlloc:
NatFree:
        jsr NatFind
        lda dirtyByte
        eor r8H
        sta dirtyByte
        jsr Stash
        ldx #0
        rts

; NatNext (SetNextFree): the next free block after r3, allocated. r3 =
; the block, X = 0 or INSUFF_SPACE.
NatNext:
        lda r3L
        sta r6L
        lda #0
        sta r7L                 ; 0: first round (from r3), 1: from track 1
        ldx r3H
        inx
        stx r6H
        bne @track
@nextTrack:
        lda #0
        sta r6H
        inc r6L
@track: ldx curDrive
        lda r6L
        beq @wrap
        cmp drvTracks-8,x
        beq @try
        bcc @try
@wrap:  lda r7L
        bne @full
        inc r7L
        lda #1
        sta r6L
        lda #0
        sta r6H
@try:   jsr NatFind
        bne @take
        lda dirtyByte           ; all 8 used: on to the next byte
        bne @one
        lda r6H
        ora #7
        sta r6H
@one:   inc r6H
        bne @try
        beq @nextTrack
@take:  jsr NatAlloc
        lda r6L
        sta r3L
        lda r6H
        sta r3H
        rts
@full:  ldx #INSUFF_SPACE
        rts

; NatBlkAlloc (BlkAlloc): from block 1/0, then as on a 1541.
NatBlkAlloc:
        lda #0
        sta saveFlag
        sta r3H
        lda #1
        sta r3L
        jmp NxtBlkAlloc

; NatDirFree (DirTrackFree): the directory may grow on any track.
NatDirFree:
        lda #$FF
        rts

        .segment "OVL6"                 ; overlay module 6: native BAM copy

        jmp FreeNative          ; entry 0
        jmp NatBam              ; entry 3
        jmp NatSure             ; entry 6

natDir: .byte 0                 ; NatBam: $FF load, 0 save

; The BAM of a native drive is used through a working copy in REU bank 1
; at NAT_WORK (blocks 1/2 on, a page each), as GEOS 2.0 keeps a 1541's
; BAM in curDirHead: GetDirHead loads it (discarding changes not written),
; PutDirHead writes it to the image and marks those blocks for the
; write-back; a failed SaveFile therefore leaves the image's BAM as it
; was. One copy, for the drive in natLoaded (GEOS 2.0 also has one
; curDirHead).
NAT_WORK        = $A0           ; page in bank 1 ($A000-$BFFF)

; NatBam (GetDirHead / PutDirHead, after the header blocks; direction from
; the block routine in DirOp): copy all BAM pages. X = 0.
NatBam: lda DirOp+1
        cmp #<ReadBlock
        bne NatSave
        lda DirOp+2
        cmp #>ReadBlock
        bne NatSave
NatLoad:
        lda #$FF
        .byte $2C
NatSave:
        lda #0
        sta natDir              ; $FF: image -> working copy
        ldx curDrive
        lda drvTracks-8,x       ; pages = (tracks + 8) / 8
        clc
        adc #8
        ror
        lsr
        lsr
        sta count
        lda #2
        sta blkLo
@page:  lda #<dir3Head          ; buffer: dir3Head (not used by native)
        sta dmaC64
        lda #>dir3Head
        sta dmaC64+1
        lda #0
        sta dmaLen
        sta dmaReu
        sta blkHi
        lda #1
        sta dmaLen+1
        bit natDir
        bpl @fromWork
        jsr ImagePage
        ldy #REU_FETCH
        jsr Dma
        jsr WorkPage
        ldy #REU_STASH
        jsr Dma
        jmp @on
@fromWork:
        jsr WorkPage
        ldy #REU_FETCH
        jsr Dma
        jsr ImagePage
        ldy #REU_STASH
        jsr Dma
        jsr MarkDirty           ; block 1/blkLo of the image
@on:    inc blkLo
        dec count
        bne @page
        lda curDrive
        sta natLoaded
        ldx #0
        rts

ImagePage:
        ldx curDrive
        lda ramBase-8,x
        sta dmaReu+2
        lda blkLo
        sta dmaReu+1
        rts
WorkPage:
        lda #SYS_BANK
        sta dmaReu+2
        lda blkLo
        clc
        adc #NAT_WORK - 2
        sta dmaReu+1
        rts

; NatSure: the working copy belongs to the current drive.
NatSure:
        lda natLoaded
        cmp curDrive
        beq @end
        lda DirOp+1             ; (keeps GetDirHead's direction)
        pha
        lda DirOp+2
        pha
        jsr NatLoad
        pla
        sta DirOp+2
        pla
        sta DirOp+1
@end:   rts

; FreeNative: CalcBlksFree on a native image: r4 = the free bits of tracks
; 1 .. drvTracks in the BAM (from 1/2 offset $20, 32 bytes a track), read
; byte by byte from the REU; r3 = all blocks (tracks * 256).
FreeNative:
        jsr NatSure
        ldx curDrive
        lda #0
        sta r3L
        lda drvTracks-8,x
        sta r3H
        lda #$20                ; the working copy of 1/2, from offset $20
        sta dmaReu
        lda #NAT_WORK
        sta dmaReu+1
        lda #SYS_BANK
        sta dmaReu+2
        lda r3H                 ; bytes: tracks * 32
        sta blkLo
        lda #0
        sta blkHi
        ldy #5
@mul:   asl blkLo
        rol blkHi
        dey
        bne @mul
@byte:  lda blkLo
        ora blkHi
        beq @end
        jsr Byte
        lda dirtyByte
@bit:   lsr
        bcc @next
        inc r4L
        bne @next
        inc r4H
@next:  tax
        bne @bit
        inc dmaReu
        bne @count
        inc dmaReu+1
        bne @count
        inc dmaReu+2
@count: lda blkLo
        bne @low
        dec blkHi
@low:   dec blkLo
        jmp @byte
@end:   ldx #0
        rts

        .segment "OVL7"                 ; overlay module 7: 1571 allocation

        jmp Op1571              ; entry 0

; Op1571: the BAM work of the driver routine that called BamType
; (nativeFrom) on a 1571 image; returns to that routine's caller. Rules
; as GEOS 2.0's 1571 driver (mist64/geos drv/drv1571.s, behaviour
; reference only): tracks 1-35 as on a 1541 (curDirHead); 36-70: the
; sector bits in dir2Head (block 53/0, 3 bytes a track), the free counts
; in curDirHead from $DD. SetNextFree: interleave on (no correction from
; track 25), tracks 18 and 53 only when the search starts there; on a
; double-sided disk the sides alternate (1, 36, 2, 37, ...).
Op1571:
        ldx #0
@find:  lda nativeFrom
        cmp d71FromLo,x
        bne @next
        lda nativeFrom+1
        cmp d71FromHi,x
        beq @found
@next:  inx
        cpx #6
        bne @find
        ldx #WR_PR_ON           ; (not reached)
        rts
@found: lda d71Lo,x
        sta @jmp+1
        lda d71Hi,x
        sta @jmp+2
@jmp:   jmp $FFFF

d71FromLo:                      ; (module 3's natLo/natHi are not loaded)
        .byte <(fbbBam-1), <(abBam-1), <(fbBam-1), <(snfBam-1), <(baBam-1), <(dtfBam-1)
d71FromHi:
        .byte >(fbbBam-1), >(abBam-1), >(fbBam-1), >(snfBam-1), >(baBam-1), >(dtfBam-1)
d71Lo:  .byte <D71Find, <D71Alloc, <D71Free, <D71Next, <D71BlkAlloc, <D71DirFree
d71Hi:  .byte >D71Find, >D71Alloc, >D71Free, >D71Next, >D71BlkAlloc, >D71DirFree

; D71Find (FindBAMBit): r6 = block. A = the BAM byte AND r8H (Z set:
; used), r8H = the sector's bit, X = the byte's offset (curDirHead for
; tracks 1-35, dir2Head above), r7H = the track's free count in curDirHead.
D71Find:
        lda r6H
        and #7
        tax
        lda bamBit,x
        sta r8H
        lda r6L
        cmp #36
        bcc @side1
        sbc #36                 ; (carry set)
        sta r7H
        lda r6H
        lsr
        lsr
        lsr
        clc
        adc r7H
        asl r7H                 ; X = 3 * (track - 36) + sector / 8
        clc
        adc r7H
        tax
        lda r6L
        clc
        adc #$DD - 36
        sta r7H
        lda dir2Head,x
        and r8H
        rts
@side1: asl
        asl
        sta r7H
        lda r6H
        lsr
        lsr
        lsr
        sec
        adc r7H
        tax
        lda curDirHead,x
        and r8H
        rts

; D71Alloc / D71Free (AllocateBlock / FreeBlock after FindBAMBit): flip the
; bit, count down / up. X = 0.
D71Alloc:
        lda #$FF
        .byte $2C
D71Free:
        lda #1
        sta r7L
        jsr D71Find
        lda r6L
        cmp #36
        lda r8H
        bcs @side2
        eor curDirHead,x
        sta curDirHead,x
        bcc @count
@side2: eor dir2Head,x
        sta dir2Head,x
@count: ldx r7H
        lda curDirHead,x
        clc
        adc r7L
        sta curDirHead,x
        ldx #0
        rts

; D71Next (SetNextFree): the next free block after r3, allocated. r3 =
; the block, X = 0 or INSUFF_SPACE. Destroys A, Y, r6, r7, r8H.
D71Next:
        lda r3H
        clc
        adc interleave
        sta r6H
        lda r3L
        sta r6L
        cmp #DIR_TRACK
        beq @count
        cmp #53
        beq @count
@track: lda r6L
        cmp #DIR_TRACK
        beq @advance
        cmp #53
        beq @advance
@count: cmp #36                 ; free blocks on the track
        bcc @c1
        adc #$DD - 36 - 1       ; (carry set)
        tax
        bne @c2
@c1:    asl
        asl
        tax
@c2:    lda curDirHead,x
        beq @advance
        lda r6L
        cmp #36
        bcc @zone
        sbc #35
@zone:  tax
        jsr Sectors
        sta r7L
        sta count
@sector:
        lda r6H                 ; r6H modulo the sectors
@mod:   cmp r7L
        bcc @in
        sbc r7L
        bcs @mod
@in:    sta r6H
        jsr D71Find
        beq @used
        lda r7L
        pha
        jsr D71Alloc
        pla
        sta r7L
        lda r6L
        sta r3L
        lda r6H
        sta r3H
        ldx #0
        rts
@used:  inc r6H
        dec count
        bne @sector
@advance:
        bit curDirHead+3        ; double-sided: the other side
        bpl @single
        lda r6L
        cmp #36
        bcs @back
        adc #35
        sta r6L
        bne @calc
@back:  sbc #34
        sta r6L
        bne @check
@single:
        inc r6L
        lda r6L
@check: cmp #36
        bcs @full
@calc:  lda r6L                 ; r6H = 2 * (track - start) + 4 + interleave
        sec
        sbc r3L
        asl
        adc #4
        adc interleave
        sta r6H
        jmp @track
@full:  ldx #INSUFF_SPACE
        rts

; D71BlkAlloc (BlkAlloc): from block 1/0, as on a 1541.
D71BlkAlloc:
        lda #0
        sta saveFlag
        sta r3H
        lda #1
        sta r3L
        jmp NxtBlkAlloc

; D71DirFree (DirTrackFree): the free blocks on track 18.
D71DirFree:
        lda curDirHead + 4 * DIR_TRACK
        rts
