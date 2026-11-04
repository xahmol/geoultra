; Fonts and desk accessories from the drive's root folder (overlay module
; 17; docs/DESIGN.md "Directories", user 2026-10-30): on a native drive
; inside a folder, FindFTypes for DESK_ACC or FONT adds the root's after
; the folder's, and the FindFile fallback (SysFindFile, sysdrive.s) looks
; for a desk accessory or font in the root before drive E. A file in the
; root is on the same drive, so its track/sector pairs are valid from any
; folder: only the search needs the root, done by pointing curDirHead's
; directory link (FirstDirBlock reads it on native drives) at the root's
; directory for a moment. Then drive E as before (module 15). Own code.

        .include "geos.inc"
        .include "kcalls.inc"

        .export RootFTypes, RootFind
        .import OvlCall, FindFTypes, FindFile, folderT, folderS, sysName

FONT            = 8
OFF_FNAME       = 3

        .segment "CODE"

RootFTypes:                     ; FindFTypes's end (files.s, SysFTypes)
        jsr OvlCall
        .byte 17, 0
RootFind:                       ; FindFile failed (sysdrive.s, SysFindFile)
        jsr OvlCall
        .byte 17, 3

; Resident: survive the overlay calls of the searches.
rootLink:       .word 0         ; curDirHead's directory link
rootR6:         .word 0         ; r6, A, Y of the failed FindFile
rootA:          .byte 0
rootY:          .byte 0

        .segment "OVL17"

        jmp OvRootFTypes        ; entry 0
        jmp OvRootFind          ; entry 3

ETypes:                         ; drive E (module 15); stubs here: the
        jsr OvlCall             ; return goes to the caller in this module
        .byte 15, 0
EFind:  jsr OvlCall
        .byte 15, 3

; InFolder: C clear when the current drive is native and its current
; folder is not the root.
InFolder:
        ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_NATIVE
        bne @no
        lda folderT-8,x
        cmp #1
        bne @yes
        lda folderS-8,x
        cmp #1
        bne @yes
@no:    sec                     ; (set here: the compares above change C;
        rts                     ; a 1541 drive once counted as "in a
@yes:   clc                     ; folder" and recursed without end)
        rts

; ToRoot: curDirHead's directory link to the root's (from its header,
; 1/1). C clear when done (diskBlkBuf, r1, r4 used).
ToRoot: lda curDirHead
        sta rootLink
        lda curDirHead+1
        sta rootLink+1
        lda #1
        sta r1L
        sta r1H
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        sec
        txa
        bne @end
        lda diskBlkBuf
        sta curDirHead
        lda diskBlkBuf+1
        sta curDirHead+1
        clc
@end:   rts

Back:   lda rootLink
        sta curDirHead
        lda rootLink+1
        sta curDirHead+1
        rts

; OvRootFTypes (after FindFTypes in the current folder; X its error,
; r6/r7H where it stopped): the root's desk accessories or fonts, then
; drive E's.
OvRootFTypes:
        txa
        bne @e                  ; (FindFTypes's error goes on in X)
        lda r7L
        cmp #DESK_ACC
        beq @type
        cmp #FONT
        bne @ok
@type:  lda r7H
        beq @ok
        jsr InFolder            ; (uses X: X = 0 again below)
        bcs @ok
        jsr ToRoot
        bcs @back
        clc                     ; FindFTypes moved r6 back by the name's
        lda r6L                 ; offset: forward again (as module 15)
        adc #OFF_FNAME
        sta r6L
        bcc :+
        inc r6H
:       jsr FindFTypes
@back:  jsr Back
@ok:    ldx #0
@e:     jmp ETypes

; OvRootFind (FindFile failed with FILE_NOT_FOUND, sysName the name): in
; the root as a desk accessory or font (X = 0, dirEntryBuf, r1, r5 as
; FindFile leaves them), else drive E with A, Y and r6 as the failed
; FindFile left them.
OvRootFind:
        sta rootA
        sty rootY
        lda r6L
        sta rootR6
        lda r6H
        sta rootR6+1
        jsr InFolder
        bcs @e
        jsr ToRoot
        bcs @back
        lda sysName
        sta r6L
        lda sysName+1
        sta r6H
        jsr FindFile
        jsr Back
        txa
        bne @e
        lda dirEntryBuf + OFF_GFILE_TYPE
        cmp #DESK_ACC
        beq @found
        cmp #FONT
        beq @found
        bne @e
@back:  jsr Back
@e:     lda rootR6
        sta r6L
        lda rootR6+1
        sta r6H
        lda rootA
        ldy rootY
        ldx #FILE_NOT_FOUND
        jmp EFind
@found: rts
