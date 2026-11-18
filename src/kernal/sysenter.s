; Drive E shown on the current drive's slot for a moment (docs/
; ARCHITECTURE.md "System drive"; sysdrive.s): module 81, Enter, Leave,
; Usable, for module 15 (desk accessories and fonts, applications' gate),
; module 55 (FE_RUNSYS) and the file engine (/e: ShowE, HideE, FreeSlot,
; HDrive). Their state is resident in sysdrive.s, so it survives nested
; overlay calls. The engine shows E in an empty slot only (user,
; 2026-11-06: a slot a command also uses as its drive would mix the two
; up), and puts it back at the end of every call (engine.s). Own code.

        .include "geos.inc"
        .include "sysdrive.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "drvflags.inc"
        .include "engine.inc"

        .import drvFlags, drvTracks, SysRAMOp, folderT, folderS
        .import sysActive, sysType, sysCurType, sysBase, sysFlags
        .import sysTracks, sysFolderT, sysFolderS, sysSlot
        .import uTouch, OvlCall

HEAD_SAVE       = $1800         ; curDirHead's copy in REU bank 1

        .segment "OVL81"
        .scope Mod81

        jmp Enter               ; entry 0
        jmp Leave               ; entry 3
        jmp Usable              ; entry 6
        jmp ShowE               ; entry 9 (the file engine)
        jmp HideE               ; entry 12
        jmp FreeSlot            ; entry 15
        jmp HDrive              ; entry 18
        jmp HMark               ; entry 21

; Enter: the current slot shows drive E, a read-only native image of
; SYSDRV_TRACKS tracks at SYSDRV_BANK in its root folder, and curDirHead
; holds E's root header. The slot's values and curDirHead are kept
; (Leave). The driver keeps E's BAM out of the native working copy while
; sysActive is set (reudrv.s, DirHead).
Enter:  ldy #REU_STASH
        jsr HeadDma
        jsr Slot
        lda #$80
        sta sysActive
        jmp GetDirHead          ; (E's root header to curDirHead)

; Slot: the current slot made drive E (its values kept for SlotBack).
Slot:   ldx curDrive
        lda driveType-8,x
        sta sysType
        and #$F0                ; (the REU drive bit kept)
        ora #DRV_NATIVE
        sta driveType-8,x
        lda curType
        sta sysCurType
        and #$F0
        ora #DRV_NATIVE
        sta curType
        lda ramBase-8,x
        sta sysBase
        lda #SYSDRV_BANK
        sta ramBase-8,x
        lda drvFlags-8,x
        sta sysFlags
        ora #F_READONLY
        sta drvFlags-8,x
        lda drvTracks-8,x
        sta sysTracks
        lda #SYSDRV_TRACKS
        sta drvTracks-8,x
        lda folderT-8,x         ; E's root folder (1/1, read through the
        sta sysFolderT          ; borrowed bank)
        lda folderS-8,x
        sta sysFolderS
        lda #1
        sta folderT-8,x
        sta folderS-8,x
        stx sysSlot
        rts

; Leave: the slot back as it was, curDirHead too. X kept.
Leave:  txa
        pha
        ldy #REU_FETCH
        jsr HeadDma
        jsr SlotBack
        pla
        tax
        rts

; SlotBack: the slot E was shown in (sysSlot) as it was; sysActive 0.
SlotBack:
        ldx sysSlot
        lda sysType
        sta driveType-8,x
        lda sysCurType
        sta curType
        lda sysBase
        sta ramBase-8,x
        lda sysFlags
        sta drvFlags-8,x
        lda sysTracks
        sta drvTracks-8,x
        lda sysFolderT
        sta folderT-8,x
        lda sysFolderS
        sta folderS-8,x
        lda #0
        sta sysActive
        rts

; HeadDma: curDirHead and dir2Head to (Y = REU_STASH) or from
; (REU_FETCH) HEAD_SAVE and HEAD_SAVE + $100 in REU bank 1; r0-r3 kept
; (OvFindFile returns r1). dir2Head too: E's header load (native) reads
; E's first BAM block into it, which on a 1581 is the drive's own BAM
; (the GEOS 2.0 deskTop's desk accessory list did that on drive A).
HeadDma:
        sty dmaDir
        ldx #7
@save:  lda r0L,x
        pha
        dex
        bpl @save
        lda #<curDirHead
        ldx #>curDirHead
        ldy #>HEAD_SAVE
        jsr Page
        lda #<dir2Head
        ldx #>dir2Head
        ldy #>HEAD_SAVE + 1
        jsr Page
        ldx #0
@back:  pla
        sta r0L,x
        inx
        cpx #8
        bne @back
        rts

; Page: 256 bytes at A/X (C64) <-> page Y of REU bank 1, dmaDir's way.
Page:   sta r0L
        stx r0H
        sty r1H
        lda #0
        sta r1L
        sta r2L
        lda #1
        sta r2H
        sta r3L                 ; bank 1
        ldy dmaDir
        jmp SysRAMOp

dmaDir: .byte 0

; Usable: C clear when drive E can be shown on the current drive (not a
; native one with more than SYSDRV_TRACK tracks, and nothing shown
; already: E, or a disk image the engine shows, whose slot values E's
; would overwrite).
Usable: sec
        lda sysActive
        bne @end
        ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_NATIVE
        bcc @end
        lda drvTracks-8,x
        cmp #SYSDRV_TRACK + 1
@end:   rts

; --- The file engine's /e ----------------------------------------------

; FreeSlot: A = the device of an empty slot among A-D (E's own slot when
; E is shown in this call already: a path resolved twice), X = 0; X =
; FE_NO_SLOT when all four have a drive.
FreeSlot:
        lda sysSlot
        ldx #0
        bit sysActive
        bvc @slot
        rts
@slot:  lda driveType,x
        beq @got
        inx
        cpx #4
        bcc @slot
        jsr OvlCall             ; (none empty: one borrowed, module 119
        .byte 119, 0            ; Pick; OvlCall returns to FreeSlot's
@got:   txa                     ; caller, overlay.s)
        clc
        adc #8
        ldx #0
        rts

; ShowE: drive E shown in the slot of device A (empty, or E's already in
; this call) and made current, at its root folder. No curDirHead is
; kept: the engine opens the caller's drive again at its end. X = 0, or
; FE_NO_SLOT (that slot has a drive now).
ShowE:  pha
        jsr SetDevice
        pla
        bit sysActive
        bpl @new
        cmp curDrive            ; (shown: in this slot?)
        bne @taken
        ldx sysSlot
        cpx curDrive
        bne @taken
        lda #1                  ; (shown: at its root again, as a walk
        sta folderT-8,x         ; starts there)
        sta folderS-8,x
        jmp GetDirHead
@new:   tay
        lda driveType-8,y
        beq :+
        jsr BorrowOk            ; (an occupied slot: module 119)
        bcs @taken
:       jsr Slot
        lda #$C0                ; (bit 6: shown by the engine)
        sta sysActive
        jmp GetDirHead
@taken: ldx #FE_NO_SLOT
        rts

BorrowOk:                       ; (Y not needed after: Slot works from
        jsr OvlCall             ; curDrive)
        .byte 119, 3

; HideE (the engine's end): the slot back when the engine showed E or a
; disk image (written back first, module 89 Leave). A function that
; leaves its drive current (FE_SELECT: feTouched 0) cannot leave the slot
; so: it fails (FE_NOT_SUPPORTED) and the dispatcher puts the caller's
; drive back. First: a function that may write on the Ultimate and was
; given a plain Ultimate path (uTouch, module 88) drops the image's copy
; in the REU (it may have changed or replaced that very file).
HideE:  lda uTouch
        beq @shown
        jsr ImgDrop             ; (module 90)
        lda #0
        sta uTouch
@shown: bit sysActive
        bvc @end
        lda sysActive
        and #$20
        beq :+
        jsr ImgLeave            ; (module 89: written back)
:       lda feTouched
        bne @back
        lda #$FF
        sta feTouched
        lda #FE_NOT_SUPPORTED
        sta feErr
@back:  jmp SlotBack
@end:   rts

; HDrive: A = a handle's H_DRIVE (bit 7: drive E, shown in that slot;
; bits 7 and 6: a disk image, module 89): the slot made current (E or the
; image shown again when it was theirs), A = the device. X = 0 or
; FE_NO_SLOT (FE_BAD_HANDLE: the image's copy is gone).
HDrive: cmp #$C0
        bcc @e
        and #$0F
        jsr ImgShow             ; (module 88)
        lda curDrive
        rts
@e:     tay
        and #$7F
        cpy #$80
        bcc :+
        jmp ShowE
:       jsr SetDevice
        lda curDrive
        rts

; HMark: A = the drive byte of a handle on device A (modules 26, 32):
; with $80 when the engine shows drive E in that slot, $C0 when it shows
; a disk image there (HDrive). X, Y kept.
HMark:  sta hmDev
        cmp sysSlot             ; (a device, as A)
        bne @plain
        lda sysActive           ; ($C0 E, $60 an image; $80: E for an
        and #$60                ; application, not the engine's)
        beq @plain
        asl a
        ora hmDev
        rts
@plain: lda hmDev
        rts

hmDev:  .byte 0

ImgLeave:
        jsr OvlCall
        .byte 89, 3
ImgShow:
        jsr OvlCall
        .byte 88, 3
ImgDrop:
        jsr OvlCall
        .byte 90, 3

        .endscope

; ======================================================================

        .segment "OVL119"               ; overlay module 119: drive E in
        .scope Mod119                   ; an occupied slot

        jmp Pick                        ; entry 0 (FreeSlot)
        jmp Ok                          ; entry 3 (ShowE)

; Pick (FreeSlot, no slot A-D empty): a slot to borrow for drive E when
; the engine function may (Ok): D, or C when the caller's drive is D;
; A = the device, X = 0. Else X = FE_NO_SLOT. The slot's values are kept
; and put back at the call's end (Slot, SlotBack: as Enter borrows the
; current slot for FindFile). The user's U64, 2026-11-18: with all four
; drives in use GU PDF could not read its script on drive E ("printer
; error" $50, the queue paused).
Pick:   jsr Ok
        bcs @no
        lda #11
        cmp saveDrive
        bne :+
        lda #10
:       ldx #0
        rts
@no:    ldx #FE_NO_SLOT
        rts

; Ok: C clear when the engine function in hand touches one path only
; (stat, a folder's listing, open, read, close: FE_STAT-FE_CLOSE,
; FE_OPEN, FE_READ), so the borrowed slot's own drive is not part of it;
; drive E is read-only meanwhile. C set for every other function.
Ok:     lda feFunc
        cmp #FE_CLOSE + 1
        bcc @yes                        ; (1-4: stat, opendir, readdir,
        cmp #FE_OPEN                    ;  close)
        beq @yes
        cmp #FE_READ
        beq @yes
        sec
        rts
@yes:   clc
        rts

        .endscope
