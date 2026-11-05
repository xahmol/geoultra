; File engine: new disk images (docs/FILE_ENGINE.md "Mount"; engine.s has
; the module list): module 71 FE_MKIMG (free REU banks found, cleared,
; the image saved), module 72 the blocks of an empty D64, D71 or D81,
; module 73 those of an empty native image (DNP). Shared: fefmt.inc.
; Own code; the layouts are Commodore's (1541, 1571, 1581 DOS: header,
; BAM and the first directory block) and CMD's native one as
; tools/mkappsdnp.py writes it. The firmware has no command that makes
; an image, so it is made in the REU and saved with SAVE_REU.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp

U_SAVE_REU      = $22
DEF_TRACKS      = 16            ; a DNP without a size: 1 MB

        .segment "OVL71"
        .scope Mod71

        jmp OvMkImg             ; entry 0

        .include "feult.inc"
        .include "fecd.inc"
        .include "fetype.inc"

Resolve:
        jsr OvlCall             ; (module 23: the path)
        .byte 23, 0
Banks0: jsr OvlCall             ; (module 68: free banks)
        .byte 68, 3
Format: jsr OvlCall             ; (module 72: the empty image's blocks)
        .byte 72, 0
Clear:  jsr OvlCall             ; (module 73: its banks cleared)
        .byte 73, 3

; FE_MKIMG: r0 = a new image on the Ultimate (.d64, .d71, .d81, .dnp),
; r1 = its disk name (zero-ended, at most 16 characters used), r2L = a
; DNP's tracks (2-255; 0: DEF_TRACKS). Made empty (header, BAM, the
; first directory block; ID "GU") in free REU banks and saved; a file
; that is there already is kept (FILE_EXISTS). X = 0 or the error
; (INSUFF_SPACE: no room in the REU).
OvMkImg:
        lda argR0
        sta r0L
        lda argR0+1
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
        jsr Type
        bcs @end
        lda #0
        sta mTracks
        lda mType
        cmp #DRV_NATIVE
        bne @fixed
        lda argR2
        bne :+
        lda #DEF_TRACKS
:       ldx #FE_NOT_SUPPORTED
        cmp #2
        bcc @end
        sta mTracks
        sta mBanks
@fixed: lda #$FF                ; (no drive left out)
        sta mSlot
        jsr Banks0
        bcs @end
        jsr Clear
        jsr Format
        txa
        bne @end
        jmp Save
@end:   rts

; Save: a new file of the path's name (FILE_EXISTS when there is one),
; the image's bytes from the REU into it (SAVE_REU), closed; deleted
; again when the save failed. X = 0 or the error.
Save:   jsr UCd
        txa
        bne @end
        lda #U_OPEN
        jsr UBegin
        lda #UO_NEW
        jsr UPut
        jsr UPutName
        jsr Send
        bne @end
        lda #U_SAVE_REU         ; the address, the length (4 bytes each)
        jsr UBegin
        lda #0
        jsr UPut
        jsr UPut
        lda mBank
        jsr UPut
        lda #0
        jsr UPut
        ldx mType
        lda mTracks             ; (native: tracks * 64 KB)
        beq :+
        lda #0
        jsr UPut
        jsr UPut
        lda mTracks
        jsr UPut
        jmp @top
:       lda Len0-1,x
        jsr UPut
        lda Len1-1,x
        jsr UPut
        lda Len2-1,x
        jsr UPut
@top:   lda #0
        jsr UPut
        jsr Send
        stx feM
        lda #U_CLOSE
        jsr UBegin
        jsr Send
        lda feM
        beq @end
        lda #U_DELETE           ; (a failed save leaves no file)
        jsr UBegin
        jsr UPutName
        jsr Send
        ldx feM
@end:   rts

; The lengths of a D64, D71, D81 (683, 1366, 3200 blocks of 256 bytes).
Len0:   .byte <(683 * 256), <(1366 * 256), <(3200 * 256)
Len1:   .byte >(683 * 256), >(1366 * 256), >(3200 * 256)
Len2:   .byte ^(683 * 256), ^(1366 * 256), ^(3200 * 256)
        .assert DRV_1541 = 1 && DRV_1571 = 2 && DRV_1581 = 3, error, "Len*: DRV_*"

; Send: uCmd sent, no data back. Z set when it worked, else X = the error.
Send:   jsr UNoData
        jsr UExec
        txa
        rts

        .endscope

        .segment "OVL72"
        .scope Mod72

        jmp OvCbm               ; entry 0

        .include "fefmt.inc"

Native: jsr OvlCall             ; (module 73: a native image; a stub)
        .byte 73, 0
D81:    jsr OvlCall             ; (module 74: a D81; a stub)
        .byte 74, 0

; OvCbm: the empty image's blocks (mType, in the banks from mBank). X =
; 0.
OvCbm:  lda mType
        cmp #DRV_1581
        bcc D64
        bne Native
        jmp D81

; D64 and D71: the BAM and header at 18/0 (block 357; a D71's second
; side's BAM at 53/0, block 1040), the directory at 18/1. Track 18's
; first two blocks are used, a D71's track 53 all.
D64:    jsr Wipe
        lda #18
        sta diskBlkBuf
        lda #1
        sta diskBlkBuf+1
        lda #'A'
        sta diskBlkBuf+2
        lda mType
        cmp #DRV_1571
        bne :+
        lda #$80                ; (double-sided)
        sta diskBlkBuf+3
:       ldx #1                  ; tracks 1-35: 4 bytes each
@trk:   stx mIdx
        jsr Zone
        txa
        asl
        asl
        tax
        lda ZFree,y
        sta diskBlkBuf,x
        lda #$FF
        sta diskBlkBuf+1,x
        sta diskBlkBuf+2,x
        lda ZLast,y
        sta diskBlkBuf+3,x
        ldx mIdx
        inx
        cpx #36
        bne @trk
        lda #17                 ; track 18: header and directory used
        sta diskBlkBuf+18*4
        lda #$FC
        sta diskBlkBuf+18*4+1
        ldy #$90
        jsr Name
        lda #$A0
        sta diskBlkBuf+$A0
        sta diskBlkBuf+$A1
        sta diskBlkBuf+$A4
        ldx #3
@pad:   sta diskBlkBuf+$A7,x
        dex
        bpl @pad
        lda #'G'                ; the ID, the DOS type "2A"
        sta diskBlkBuf+$A2
        lda #'U'
        sta diskBlkBuf+$A3
        lda #'2'
        sta diskBlkBuf+$A5
        lda #'A'
        sta diskBlkBuf+$A6
        lda mType
        cmp #DRV_1571
        bne @put
        ldx #1                  ; a D71: tracks 36-70's free blocks at $DD
@side:  stx mIdx
        jsr Zone
        lda ZFree,y
        cpx #18
        bne :+
        lda #0                  ; (track 53: the second BAM)
:       sta diskBlkBuf+$DD-1,x
        ldx mIdx
        inx
        cpx #36
        bne @side
@put:   lda #<357
        ldx #>357
        jsr Put
        jsr Dir
        lda #<358
        ldx #>358
        jsr Put
        lda mType
        cmp #DRV_1571
        bne @done
        jsr Wipe                ; 53/0: tracks 36-70, 3 bytes each
        ldx #1
@bam2:  stx mIdx
        jsr Zone
        txa
        sta mTmp
        asl
        adc mTmp
        tax                     ; (3 * track - 3: the offset + 3)
        lda mIdx
        cmp #18
        beq :+                  ; (track 53: used)
        lda #$FF
        sta diskBlkBuf-3,x
        sta diskBlkBuf-2,x
        lda ZLast,y
        sta diskBlkBuf-1,x
:       ldx mIdx
        inx
        cpx #36
        bne @bam2
        lda #<1040
        ldx #>1040
        jsr Put
@done:  ldx #0
        rts

; Zone: Y = the 1541 speed zone (0-3) of track X (1-35). X kept.
Zone:   ldy #0
        cpx #18
        bcc @end
        iny
        cpx #25
        bcc @end
        iny
        cpx #31
        bcc @end
        iny
@end:   rts

ZFree:  .byte 21, 19, 18, 17    ; blocks per track in each zone
ZLast:  .byte $1F, $07, $03, $01 ; their last BAM byte (bit set: free)

        .endscope

        .segment "OVL73"
        .scope Mod73

        jmp OvNative            ; entry 0
        jmp Clear               ; entry 3 (for module 71)

        .include "fefmt.inc"

; OvNative: an empty native image of mTracks tracks: the header at 1/1
; (block 1), the BAM at 1/2-1/33 (32 bytes per track from the first BAM
; block's byte $20, bit 7 first, set: free; its header bytes before),
; the directory at 1/34. Track 1's blocks 0-34 are used. X = 0.
OvNative:
        jsr Wipe
        lda #1
        sta diskBlkBuf
        lda #34
        sta diskBlkBuf+1
        lda #'H'
        sta diskBlkBuf+2
        ldy #4
        jsr Name
        ldx #8
@hdr:   lda HeadN,x
        sta diskBlkBuf+$14,x
        dex
        bpl @hdr
        lda #1
        sta diskBlkBuf+$20
        sta diskBlkBuf+$21
        lda #1
        ldx #0
        jsr Put
        lda #0                  ; the 32 BAM blocks, 8 tracks each
        sta mIdx
@blk:   jsr Wipe
        lda mIdx
        bne @tracks
        ldx #6                  ; the first: its header bytes
@bhd:   lda BamN,x
        sta diskBlkBuf+2,x
        dex
        bpl @bhd
        lda mTracks
        sta diskBlkBuf+8
@tracks:
        lda mIdx                ; mTmp: the first track here
        asl
        asl
        asl
        sta mTmp
        ldx #0
@trk:   lda mTmp
        beq @next               ; (track 0: the header bytes)
        cmp mTracks
        beq :+
        bcs @put                ; (past the last track)
:       lda #$FF
        ldy #32
@byte:  sta diskBlkBuf,x
        inx
        dey
        bne @byte
        txa
        sec
        sbc #32
        tax
@next:  txa
        clc
        adc #32
        tax
        inc mTmp
        cpx #0
        bne @trk
@put:   lda mIdx
        bne :+
        lda #0                  ; track 1: blocks 0-34 used (offset $20)
        sta diskBlkBuf+$20
        sta diskBlkBuf+$21
        sta diskBlkBuf+$22
        sta diskBlkBuf+$23
        lda #$1F
        sta diskBlkBuf+$24
:       lda mIdx
        clc
        adc #2
        ldx #0
        jsr Put
        inc mIdx
        lda mIdx
        cmp #32
        bne @blk
        jsr Dir
        lda #34
        ldx #0
        jsr Put
        ldx #0
        rts

HeadN:  .byte $A0, $A0, 'G', 'U', $A0, '1', 'H', $A0, $A0
BamN:   .byte 'H', 'H' ^ $FF, 'G', 'U', $C0, 0, 0

; Clear: the image's banks filled with zeros, one DMA per bank (the C64
; address fixed on a zero byte).
Clear:  lda #0
        sta mTmp
@bank:  php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda #<Zero
        sta reuC64
        lda #>Zero
        sta reuC64+1
        lda #0
        sta reuAddr
        sta reuAddr+1
        sta reuLen              ; (0: 64 KB)
        sta reuLen+1
        lda mBank
        clc
        adc mTmp
        sta reuAddr+2
        lda #$80                ; the C64 address fixed
        sta reuCtrl
        lda #REU_STASH
        sta reuCmd
        lda #0
        sta reuCtrl
        pla
        sta CPU_PORT
        plp
        inc mTmp
        lda mTmp
        cmp mBanks
        bne @bank
        rts

Zero:   .byte 0

        .endscope

        .segment "OVL74"
        .scope Mod74

        jmp OvD81               ; entry 0

        .include "fefmt.inc"

; D81: the header at 40/0 (block 1560), the BAM at 40/1 and 40/2 (tracks
; 1-40, 41-80), the directory at 40/3; track 40's first four blocks used.
OvD81:  jsr Wipe
        lda #40
        sta diskBlkBuf
        lda #3
        sta diskBlkBuf+1
        lda #'D'
        sta diskBlkBuf+2
        ldy #4
        jsr Name
        ldx #6
@hdr:   lda Head81,x
        sta diskBlkBuf+$14,x
        dex
        bpl @hdr
        lda #$A0
        sta diskBlkBuf+$1B
        sta diskBlkBuf+$1C
        lda #<1560
        ldx #>1560
        jsr Put
        lda #1                  ; the two BAM blocks
        sta mIdx
@side:  jsr Wipe
        ldx #7
@bhd:   lda Bam81,x
        sta diskBlkBuf,x
        dex
        bpl @bhd
        ldx #$10                ; 40 tracks: 40 free, all bits set
        lda #40
        sta mTmp
@trk:   lda #40
        sta diskBlkBuf,x
        inx
        lda #$FF
        ldy #5
@bits:  sta diskBlkBuf,x
        inx
        dey
        bne @bits
        dec mTmp
        bne @trk
        lda mIdx
        cmp #1
        bne @second
        lda #40                 ; the first side: its link, track 40
        sta diskBlkBuf
        lda #2
        sta diskBlkBuf+1
        lda #36
        sta diskBlkBuf+$10+6*39
        lda #$F0
        sta diskBlkBuf+$10+6*39+1
        lda #<1561
        ldx #>1561
        jsr Put
        inc mIdx
        bne @side
@second:
        lda #<1562
        ldx #>1562
        jsr Put
        jsr Dir
        lda #<1563
        ldx #>1563
        jsr Put
        ldx #0
        rts

Head81: .byte $A0, $A0, 'G', 'U', $A0, '3', 'D'
Bam81:  .byte 0, $FF, 'D', 'D' ^ $FF, 'G', 'U', $C0, 0

        .endscope
