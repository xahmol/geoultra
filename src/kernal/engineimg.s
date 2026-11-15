; File engine: disk images on the Ultimate gone into like folders (the
; user's decision 2026-11-13; docs/FILE_ENGINE.md "Disk images as
; folders"). A path such as /usb0/x/disk.d81/notes names a file inside
; the image: the image is loaded into free REU banks (module 68, as
; FE_MOUNT loads one) and shown in an empty slot A-D for this call, the
; way drive E is (sysenter.s; sysActive $60), and the rest of the path is
; walked there as on a GEOS drive. The image's changes are written back
; at the call's end (module 89 Leave, from module 81 HideE). Its copy
; stays in the REU for the next call (imgFlags, sysdrive.s), until a call
; that may write on the Ultimate drops it (module 90 Drop, from module 81),
; a mount takes its banks (Valid), or a session is resumed (module 8).
; Module 88: the path looked at, a handle's image shown again; module 89:
; the slot, the write-back; module 90: the image loaded or found, the
; comparisons. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"
        .include "drvflags.inc"

        .import OvlCall, SysRAMOp, folderT, folderS, drvTracks, drvFlags
        .import natLoaded, WriteBackNow, hibState
        .import sysActive, sysType, sysCurType, sysBase, sysFlags
        .import sysTracks, sysFolderT, sysFolderS, sysSlot
        .import imgFlags, imgBank, imgType, imgTracks, uTouch

IMG_SHOWN       = $60           ; sysActive: the engine shows the image
PATH_MAX        = 63            ; an image path in its 64 bytes (as
                                ; FE_MOUNT's: the write-back's path)

        .segment "OVL88"
        .scope Mod88

        jmp Probe               ; entry 0 (module 24, an Ultimate path)
        jmp Reshow              ; entry 3 (module 81 HDrive)

        .include "fetype.inc"

Enter:  jsr OvlCall             ; (module 90: the image shown, loaded
        .byte 90, 0             ; first unless its copy is there)
Show:   jsr OvlCall             ; (module 89: shown in slot mSlot)
        .byte 89, 0
Valid:  jsr OvlCall             ; (module 90: the copy still there)
        .byte 90, 6

; ReuOp: Y = REU_STASH or REU_FETCH; r0 C64, r1 bank 1, r2 length.
ReuOp:  lda #FE_BANK
        sta r3L
        jmp SysRAMOp

; Probe (module 24, the path's top an Ultimate one; feEnd after it): a
; part on the way that is a disk image (.d64 .d71 .d81 .dnp) and has a
; "/" after it, or is the last part of FE_OPENDIR or FE_CD, is gone
; into: C clear, feKind FE_P_GEOS, feDrive its slot (current, at its
; root), feEnd after the part (the walk goes on from there). Else C set
; and X = 0 (a plain Ultimate path: uTouch set) or the error
; (FE_NO_SLOT: no empty slot, or drive E shown in this call;
; FE_MOUNTED: the image is mounted on a drive A-D; INSUFF_SPACE: no room
; in the REU). feInfo is kept (a copy's entry may be there).
Probe:  jsr KeepInfo
        ldx feEnd
@part:  lda fePath,x            ; at the "/" before a part, or the end
        beq @plain
        inx
        stx imStart
@scan:  lda fePath,x
        beq @end
        cmp #'/'
        beq @end
        inx
        bne @scan
@end:   stx imEnd
        jsr Cut                 ; (the part's end zero meanwhile)
        jsr Type                ; an image's name? (mType, mBanks)
        jsr Uncut
        bcs @next
        ldx imEnd
        lda fePath,x
        bne @found              ; ("/" after it: inside)
        lda feFunc
        cmp #FE_OPENDIR
        beq @found
        cmp #FE_CD
        beq @found
@next:  ldx imEnd
        bne @part               ; (not 0: always)
@plain: lda #1
        sta uTouch
        ldx #0
        jmp Fail
@found: jsr Cut
        jsr Enter
        jsr Uncut
        txa
        bne Fail
        lda imEnd               ; the walk goes on after the image
        sta feEnd
        lda #0                  ; (feName: Enter's for the load; the
        sta feName              ; image itself so far, as a drive's root)
        lda #FE_P_GEOS
        sta feKind
        sta feTouched
        lda sysSlot             ; (a device, 8-11)
        sta feDrive
        jsr SetDevice
        jsr OpenDisk
        txa
        bne Fail
        jsr BackInfo
        clc
        rts
Fail:   txa
        pha
        jsr BackInfo
        pla
        tax
        sec
        rts

; Reshow (module 81 HDrive: a handle on the image, device A): the image
; shown in that slot again from its copy. X = 0, FE_BAD_HANDLE (the copy
; is gone) or FE_NO_SLOT (the slot has a drive now, or drive E is shown).
Reshow: pha
        jsr KeepInfo
        pla
        sec
        sbc #8
        sta mSlot
        lda sysActive
        beq @new
        ldx #FE_NO_SLOT
        cmp #IMG_SHOWN
        bne @end
        lda sysSlot             ; (shown in this call already: in this
        and #3                  ; slot?)
        cmp mSlot
        bne @end
        beq @dev
@new:   jsr Valid
        ldx #FE_BAD_HANDLE
        bcs @end
        ldx mSlot
        lda driveType,x
        ldx #FE_NO_SLOT
        tay
        bne @end
        lda imgBank
        sta mBank
        lda imgType
        sta mType
        lda imgTracks
        sta mTracks
        jsr Show
@dev:   lda mSlot
        ora #8
        jsr SetDevice
        jsr OpenDisk
@end:   txa
        pha
        jsr BackInfo
        pla
        tax
        rts

; Cut, Uncut: fePath's character at imEnd kept and made 0, and back.
; Keep X and C; destroy Y.
Cut:    ldy imEnd
        lda fePath,y
        sta imCh
        lda #0
        sta fePath,y
        rts
Uncut:  ldy imEnd
        lda imCh
        sta fePath,y
        rts

; KeepInfo, BackInfo: feInfo's 32 bytes to IMG_SAVE in the REU and back.
KeepInfo:
        ldy #REU_STASH
        .byte $2C               ; (bit abs: skips the next ldy)
BackInfo:
        ldy #REU_FETCH
        lda #<feInfo
        sta r0L
        lda #>feInfo
        sta r0H
        lda #<IMG_SAVE
        sta r1L
        lda #>IMG_SAVE
        sta r1H
        lda #32
        sta r2L
        lda #0
        sta r2H
        jmp ReuOp

        .endscope

        .segment "OVL89"
        .scope Mod89

        jmp Show                ; entry 0 (module 90, module 88 Reshow)
        jmp Leave               ; entry 3 (module 81 HideE)

; ReuOp: Y = REU_STASH or REU_FETCH; r0 C64, r1 bank 1, r2 length.
ReuOp:  lda #FE_BANK
        sta r3L
        jmp SysRAMOp

        .include "fework.inc"

; Show: the image (mType, mBank, mTracks; its path at IMG_PATH) shown in
; slot mSlot, the slot's values kept for SlotBack (module 81), at its
; root folder; its path copied to the slot's mount path for the
; write-back. X = 0.
Show:   ldx mSlot
        lda driveType,x
        sta sysType
        lda mType
        ora #DRV_RAM
        sta driveType,x
        lda curType
        sta sysCurType
        lda ramBase,x
        sta sysBase
        lda mBank
        sta ramBase,x
        lda drvFlags,x
        sta sysFlags
        lda imgFlags            ; (its backup made, a write-back owed)
        and #F_BACKUP | F_DIRTY
        sta drvFlags,x
        lda drvTracks,x
        sta sysTracks
        lda mTracks
        sta drvTracks,x
        lda folderT,x
        sta sysFolderT
        lda folderS,x
        sta sysFolderS
        lda #1
        sta folderT,x
        sta folderS,x
        txa                     ; (sysSlot: a device, as module 81 keeps
        ora #8                  ; it)
        sta sysSlot
        lda #IMG_SHOWN
        sta sysActive
        jsr NatDrop
        lda #0                  ; IMG_PATH to MOUNT_PATHS + 64 * slot,
@chunk: sta imOff               ; 16 bytes at a time through imBuf
        jsr BufRegs
        lda #<IMG_PATH
        clc
        adc imOff
        sta r1L
        lda #>IMG_PATH
        sta r1H
        ldy #REU_FETCH
        jsr ReuOp
        jsr BufRegs
        jsr SlotPath
        lda r1L
        clc
        adc imOff
        sta r1L
        ldy #REU_STASH
        jsr ReuOp
        lda imOff
        clc
        adc #16
        cmp #64
        bcc @chunk
        ldx #0
        rts

; Leave (module 81 HideE, the image still shown): its changes written
; back (the work area kept in the REU meanwhile: the write-back uses the
; same scratch); imgFlags keeps the backup and an unfinished write-back
; (then feErr FE_ULTIMATE); the slot's mount table flags cleared again.
Leave:  ldx sysSlot
        lda drvFlags-8,x
        and #F_DIRTY
        beq @flags
        lda hibState            ; (no hibernation in the middle: as
        pha                     ; FE_UMOUNT)
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
        lda #0                  ; (StoreFlags: the slot's entry, which is
        sta imOff               ; no drive's once the slot is back)
        lda #<imOff
        sta r0L
        lda #>imOff
        sta r0H
        lda sysSlot
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<(MOUNT_ENTRY + 3)
        sta r1L
        lda #>MOUNT_ENTRY
        sta r1H
        lda #1
        sta r2L
        lda #0
        sta r2H
        ldy #REU_STASH
        jsr ReuOp
        ldx sysSlot
        lda drvFlags-8,x
        and #F_DIRTY
        beq @flags
        lda feErr
        bne @flags
        lda #FE_ULTIMATE
        sta feErr
@flags: ldx sysSlot
        lda drvFlags-8,x
        and #F_BACKUP | F_DIRTY
        bit imgFlags            ; (dropped in this call: stays so, unless
        bmi @keep               ; a write-back is still owed)
        and #F_DIRTY
        beq @set
        lda drvFlags-8,x
        and #F_BACKUP | F_DIRTY
@keep:  ora #$80
@set:   sta imgFlags
        ; (falls into NatDrop)

; NatDrop: the native BAM working copy forgotten when it is the slot's
; (another image may be shown there next).
NatDrop:
        lda sysSlot
        ora #8
        cmp natLoaded
        bne :+
        lda #0
        sta natLoaded
:       rts

; BufRegs: r0 = imBuf, r2 = 16. Keeps r1.
BufRegs:
        lda #<imBuf
        sta r0L
        lda #>imBuf
        sta r0H
        lda #16
        sta r2L
        lda #0
        sta r2H
        rts

; SlotPath: r1 = MOUNT_PATHS + 64 * sysSlot; SlotPathX: of slot A.
SlotPath:
        lda sysSlot
SlotPathX:
        asl
        asl
        asl
        asl
        asl
        asl
        sta r1L
        lda #>MOUNT_PATHS
        sta r1H
        rts
        .assert <MOUNT_PATHS = 0, error, "SlotPath: MOUNT_PATHS on a page"

        .endscope

        .segment "OVL90"
        .scope Mod90

        jmp Enter               ; entry 0 (module 88)
        jmp Drop                ; entry 3 (module 81 HideE)
        jmp Valid               ; entry 6 (module 88 Reshow)

Load:   jsr OvlCall             ; (module 68: the image into free banks)
        .byte 68, 0
Show:   jsr OvlCall             ; (module 89: shown in slot mSlot)
        .byte 89, 0

; ReuOp: Y = REU_STASH or REU_FETCH; r0 C64, r1 bank 1, r2 length.
ReuOp:  lda #FE_BANK
        sta r3L
        jmp SysRAMOp

; Enter (fePath zero-ended after the image's name): the image shown in
; an empty slot (sysSlot), loaded first unless its copy is in the REU.
; X = 0 or the error.
Enter:  ldx #FE_BAD_PATH
        lda imEnd
        cmp #PATH_MAX + 1
        bcs @end
        lda imStart             ; (UCd, UPutName: the folder up to the
        sta fePos               ; "/" before the name, then the name)
        dec fePos
        lda #1
        sta feName
        lda sysActive           ; (mType, mBanks: Probe's scan.) Shown in
        beq @slot               ; this call already (a second path): the
                                ; same image again only
        ldx #FE_NO_SLOT
        cmp #IMG_SHOWN
        bne @end
        jsr ImgPath
        jsr Same
        ldx #FE_NO_SLOT
        bcs @end
        ldx sysSlot             ; (at its root again, as a walk starts
        lda #1                  ; there; its slot made current after us)
        sta folderT-8,x
        sta folderS-8,x
        ldx #0
@end:   rts
@slot:  ldx #0                  ; an empty slot
@try:   lda driveType,x
        beq @got
        inx
        cpx #4
        bcc @try
        ldx #FE_NO_SLOT
        rts
@got:   stx mSlot
        jsr Mounted
        ldx #FE_MOUNTED
        bcc @end
        jsr Valid               ; its copy still in the REU?
        bcs @load
        lda imgType
        cmp mType
        bne @load
        jsr ImgPath
        jsr Same
        bcs @load
        lda imgBank
        sta mBank
        lda imgTracks
        sta mTracks
        jmp Show
@load:  lda #0
        sta imgFlags
        jsr Load
        txa
        bne @end
        lda #$80
        sta imgFlags
        lda mBank
        sta imgBank
        lda mType
        sta imgType
        lda mTracks
        sta imgTracks
        lda #<fePath            ; its path, for the next call
        sta r0L
        lda #>fePath
        sta r0H
        jsr ImgPath
        lda #64
        sta r2L
        lda #0
        sta r2H
        ldy #REU_STASH
        jsr ReuOp
        jmp Show

; ImgPath: r1 = IMG_PATH.
ImgPath:
        lda #<IMG_PATH
        sta r1L
        lda #>IMG_PATH
        sta r1H
        rts

; Drop (module 81 HideE, uTouch set: a plain Ultimate path was given):
; a function that may write on the Ultimate drops the image's copy in
; the REU (it may have changed or replaced that very file).
Drop:   lda feFunc
        and #7
        tax
        lda feFunc
        lsr
        lsr
        lsr
        tay
        lda Writers,y
@bit:   lsr                     ; (bit X of the byte to C)
        dex
        bpl @bit
        bcc :+
        lda #0
        sta imgFlags
:       rts

; The functions that may write on the Ultimate (bit n of byte n / 8):
; FE_COPY-FE_RENAME, FE_OPEN, FE_WRITE, FE_MOUNT, FE_UMOUNT, FE_SETLONG,
; FE_MKIMG, FE_REBOOT, FE_UCI.
Writers:        .byte $E0, $A7, $16, $51, $00   ; (FE_TASK, FE_SPOOL: none)
        .assert FE_COUNT <= 40, error, "Writers: 40 functions at most"

; Valid: C clear when the image's copy is in the REU and no drive in
; another slot uses any of its banks (a mount may have taken them; then
; imgFlags is cleared). Destroys A, X, Y, mTmp, mIdx.
Valid:  bit imgFlags
        bpl @gone
        lda imgType
        ldx imgTracks
        jsr Banks
        clc
        adc imgBank
        sta mTmp                ; (its end)
        ldx #3
@drive: stx mIdx
        lda sysActive           ; (the image's own slot)
        cmp #IMG_SHOWN
        bne :+
        txa
        ora #8
        cmp sysSlot
        beq @next
:       lda driveType,x
        and #$0F
        beq @next
        pha
        lda drvTracks,x
        tax
        pla
        jsr Banks
        ldx mIdx
        clc
        adc ramBase,x           ; (its end)
        cmp imgBank
        bcc @next
        beq @next
        lda ramBase,x
        cmp mTmp
        bcc @gone               ; (it starts before the image's end)
@next:  ldx mIdx
        dex
        bpl @drive
        clc
        rts
@gone:  lda #0
        sta imgFlags
        sec
        rts

; Banks: A = the REU banks of an image of type A (native: X tracks).
Banks:  cmp #DRV_NATIVE
        bne :+
        txa
        rts
:       tay
        lda TypeBanks,y
        rts
TypeBanks:      .byte 0, 3, 6, 13       ; none, 1541, 1571, 1581 (mount.s)

; Mounted: C clear when fePath (zero-ended after the image's name) is
; the image of a drive A-D (any case: MOUNTS.INI may have it in
; capitals). Destroys A, X, Y, r0-r3L, mIdx.
Mounted:
        ldx #3
@drive: stx mIdx
        lda driveType,x
        and #$0F
        beq @next
        txa
        jsr SlotPathX
        jsr Same
        bcc @end
@next:  ldx mIdx
        dex
        bpl @drive
        sec
@end:   rts

; Same: C clear when fePath equals the 64-byte path at r1 in REU bank
; 1 (any case). Destroys A, X, Y, r0-r3L.
Same:   lda #0
        sta imOff
@chunk: jsr BufRegs
        ldy #REU_FETCH
        jsr ReuOp
        ldy #0
@ch:    ldx imOff
        lda fePath,x
        jsr Lower
        sta mTmp
        lda imBuf,y
        jsr Lower
        cmp mTmp
        bne @diff
        tax
        beq @same
        inc imOff
        iny
        cpy #16
        bcc @ch
        lda r1L                 ; (the next 16: no carry, 64 aligned)
        adc #16 - 1             ; (C set from cpy)
        sta r1L
        lda imOff
        cmp #64
        bcc @chunk
@diff:  sec
        rts
@same:  clc
        rts

; Lower: A in lower case.
Lower:  cmp #'A'
        bcc :+
        cmp #'Z' + 1
        bcs :+
        ora #$20
:       rts

; BufRegs: r0 = imBuf, r2 = 16. Keeps r1.
BufRegs:
        lda #<imBuf
        sta r0L
        lda #>imBuf
        sta r0H
        lda #16
        sta r2L
        lda #0
        sta r2H
        rts

; SlotPathX: r1 = MOUNT_PATHS + 64 * slot A.
SlotPathX:
        asl
        asl
        asl
        asl
        asl
        asl
        sta r1L
        lda #>MOUNT_PATHS
        sta r1H
        rts

        .endscope
