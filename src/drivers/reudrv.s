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

        .export DiskInit
        .import Trap, CopyFString, GetPtrCurDkNm

FRST_FILE_ENTRY = 2
WR_PR_ON        = $26           ; write protected
WR_VER_ERR      = $25           ; verify failed
BAD_SECTOR      = $20           ; sector beyond the track (header not found)
SYS_BANK        = 1
MOUNT_TAB       = $0100
MOUNT_ENTRY     = $0120
DIRTY_MAP       = $20           ; page of slot 0's dirty map in bank 1
F_DIRTY         = $01
F_READONLY      = $02
dir3Head        = $9C80         ; third BAM block (1581), end of the driver

        .segment "DRIVER"

; $9000: vectors the kernal's jump table entries go through
        .word InitForIO, DoneWithIO, NoTurbo, NoTurbo, NoTurbo
        .word ChangeDiskDevice, NewDisk, ReadBlock, WriteBlock, VerWriteBlock
        .word OpenDisk, ReadBlock, WriteBlock, GetDirHead, PutDirHead
        .word tGetFreeDirBlk, CalcBlksFree, tFreeBlock, tSetNextFree
        .word tFindBAMBit, tNxtBlkAlloc, tBlkAlloc, ChkDkGEOS, tSetGEOSDisk

; $9030: entries applications call directly
        jmp FirstDirEntry
        jmp NextDirEntry
        jmp GetBorder
        jsr Trap                ; AddDirBlock
        jmp ReadBuff
        jmp WriteBuff
        jsr Trap                ; SendTSBytes (serial drives only)
        jsr Trap                ; CheckErrors (serial drives only)
        jsr Trap                ; AllocateBlock
        jmp ReadBlock           ; ReadLink: the whole block

; Not yet implemented (BAM and allocation): halt in Trap with the address.
tGetFreeDirBlk: jsr Trap
tFreeBlock:     jsr Trap
tSetNextFree:   jsr Trap
tFindBAMBit:    jsr Trap
tNxtBlkAlloc:   jsr Trap
tBlkAlloc:      jsr Trap
tSetGEOSDisk:   jsr Trap

; Per drive (index curDrive - 8); driveType and ramBase are the GEOS ones.
drvTracks:      .res 4          ; native: track count
drvFlags:       .res 4          ; mount table flags (F_DIRTY, F_READONLY)

borderFlag:     .byte 0
blkLo:          .byte 0         ; block number within the image
blkHi:          .byte 0
track:          .byte 0
dmaC64:         .word 0         ; DMA parameters
dmaReu:         .res 3
dmaLen:         .word 0
dirtyByte:      .byte 0
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

; EnterTurbo, ExitTurbo, PurgeTurbo, NewDisk: nothing to do for an image.
NewDisk:
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

; --- Blocks ---------------------------------------------------------------

; ReadBlock / GetBlock / ReadLink: r1 = track/sector, r4 = buffer.
; Returns X = error. r1, r4 unchanged; destroys A, Y.
ReadBlock:
        jsr Locate
        bcc BlkEnd
        ldy #REU_FETCH
        jsr DmaBlock
        ldx #0
BlkEnd: ldy #0
        rts

; WriteBlock / PutBlock: as ReadBlock, the other way.
WriteBlock:
        jsr Locate
        bcc BlkEnd
        ldy curDrive
        ldx #WR_PR_ON
        lda drvFlags-8,y
        and #F_READONLY
        bne BlkEnd
        ldy #REU_STASH
        jsr DmaBlock
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

ReadBuff:
        jsr BufPtr
        jmp ReadBlock
WriteBuff:
        jsr BufPtr
        jmp WriteBlock
BufPtr: lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        rts

BadTrack:
        ldx #INV_TRACK
        clc
        rts
BadSector:
        ldx #BAD_SECTOR
        clc
        rts

; Locate: r1 of the current drive -> blkHi/blkLo and dmaReu. C set when
; valid; else C clear and X = error.
Locate: ldy curDrive
        lda driveType-8,y
        and #$0F
        bne @type
        ldx #DEV_NOT_FOUND
        clc
        rts
@type:  ldx #0
        stx blkLo
        stx blkHi
        ldx r1L                 ; track
        beq BadTrack
        cmp #DRV_1581
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
        adc ramBase-8,y
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
; r4 = curDirHead. Destroys A, Y, r1.
GetDirHead:
        lda #<ReadBlock
        ldy #>ReadBlock
        bne DirHead
PutDirHead:
        lda #<WriteBlock
        ldy #>WriteBlock
DirHead:
        sta @op+1
        sty @op+2
        ldy curDrive
        lda driveType-8,y
        and #$0F
        bne @type
        ldx #DEV_NOT_FOUND
        bne @ptr
@type:  tay
        lda headStart,y
        sta dirIndex
@next:  ldy dirIndex
        lda headTab,y
        beq @done
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
@op:    jsr ReadBlock
        txa
        beq @next
        bne @ptr
@done:  ldx #0
@ptr:   lda #<curDirHead
        sta r4L
        lda #>curDirHead
        sta r4H
        rts

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
        .byte 1, 1, <curDirHead, >curDirHead, 1, 2, <dir2Head, >dir2Head, 0

; OpenDisk: header in, isGEOS set, disk name to DrXCurDkNm. Returns X =
; error, r5 = the name. Destroys A, Y, r0-r4.
OpenDisk:
        jsr GetDirHead
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
        cmp #DRV_1581
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

; --- Directory entries ---------------------------------------------------

; Get1stDirEntry: the first directory block to diskBlkBuf, r5 = its first
; entry. Returns X = error. Destroys A, Y, r1, r4.
FirstDirEntry:
        ldy curDrive
        lda driveType-8,y
        and #$0F
        tay
        lda dirTrack,y
        sta r1L
        lda dirSector,y
        sta r1H
        cpy #DRV_NATIVE         ; native: the header's link
        bne @read
        lda curDirHead
        sta r1L
        lda curDirHead+1
        sta r1H
@read:  lda #0
        sta borderFlag
EntryBlock:
        jsr ReadBuff
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
        jsr GetDirHead
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
@none:  lda #8
        sta curDrive
        sta curDevice
        lda driveType
        sta curType
        beq @end
        jmp OpenDisk
@end:   rts

mountSig:       .byte "GUMT"
