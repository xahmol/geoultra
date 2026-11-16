; Fonts and desk accessories from the drive's root folder (overlay module
; 17; docs/DESIGN.md "Directories", user 2026-10-30): on a native drive
; inside a folder, FindFTypes for DESK_ACC or FONT adds the root's after
; the folder's, and the FindFile fallback (SysFindFile, sysdrive.s) looks
; for a desk accessory, font or printer driver in the root before drive
; E. A file in the
; root is on the same drive, so its track/sector pairs are valid from any
; folder: only the search needs the root, done by pointing curDirHead's
; directory link (FirstDirBlock reads it on native drives) at the root's
; directory for a moment. Then drive E as before (module 15). Own code.

        .include "geos.inc"
        .include "kcalls.inc"

        .export RootFTypes, RootFind
        .import OvlCall, FindFTypes, FindFile, folderT, folderS, sysName
        .import ftStart, ftAll, ftLeft

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

        .segment "KCODE"        ; (CODE is full)
rootBusy:       .byte 0         ; a root search running: the searches'
                                ; own ends (FindFTypes > SysFTypes,
                                ; FindFile > SysFindFile) come back here
                                ; and must not search again (found
                                ; 2026-11-13: geoWrite and geoPaint
                                ; started in a folder hung at Open)

        .segment "OVL17"

        jmp OvRootFTypes        ; entry 0
        jmp OvRootFind          ; entry 3
        jmp EFirst              ; entry 6 (sysdrive.s, OvFTypes)

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
        lda rootBusy            ; the root's own FindFTypes ending: back
        bne @in                 ; to the search below (X = 0)
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
        inc rootBusy
        clc                     ; FindFTypes moved r6 back by the name's
        lda r6L                 ; offset: forward again (as module 15)
        adc #OFF_FNAME
        sta r6L
        bcc :+
        inc r6H
:       jsr FindFTypes          ; (an error in the root is dropped: the
        dec rootBusy            ; folder's own list stands, drive E next)
@back:  jsr Back
@ok:    ldx #0
@e:     jmp ETypes
@in:    rts

; OvRootFind (FindFile failed with FILE_NOT_FOUND, sysName the name): in
; the root as a desk accessory or font (X = 0, dirEntryBuf, r1, r5 as
; FindFile leaves them), else drive E with A, Y and r6 as the failed
; FindFile left them.
OvRootFind:
        ldx rootBusy            ; the root's own FindFile failing: back to
        beq :+                  ; the search below
        ldx #FILE_NOT_FOUND
        rts
:       sta rootA
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
        inc rootBusy
        jsr FindFile
        dec rootBusy
        jsr Back
        txa
        bne @e
        lda dirEntryBuf + OFF_GFILE_TYPE
        cmp #DESK_ACC
        beq @found
        cmp #FONT
        beq @found
        cmp #PRINTER_FILE
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

; EFirst (module 15's OvFTypes, after drive E's search; r7H as it
; left it): an application's desk accessories: the drive's (rows 0 to d-1)
; and drive E's after them (d to t-1) turned round, E's first: the two
; parts each reversed, then the whole (rows of 17 bytes from ftStart; d
; = ftAll - ftLeft, t = ftAll - r7H). Destroys A, X, Y, r0-r2L.
EFirst: lda ftAll
        sec
        sbc r7H
        sta ftT
        lda ftAll
        sec
        sbc ftLeft
        sta ftD
        lda #0                  ; the drive's
        ldx ftD
        jsr Reverse
        lda ftD                 ; E's
        ldx ftT
        jsr Reverse
        lda #0                  ; all
        ldx ftT
        ; (falls into Reverse)

; Reverse: rows A to X-1 in reverse order.
Reverse:
        sta ftLo
        stx ftHi
@pair:  lda ftHi                 ; two rows or more left? (an empty part,
        sec                     ; X = A, counted down below 0 once)
        sbc ftLo
        cmp #2
        bcc @end
        dec ftHi
        lda ftHi
        jsr RowAt
        lda r0L
        sta r1L
        lda r0H
        sta r1H
        lda ftLo
        jsr RowAt
        ldy #16
@swap:  lda (r0),y
        tax
        lda (r1),y
        sta (r0),y
        txa
        sta (r1),y
        dey
        bpl @swap
        inc ftLo
        bne @pair               ; (always)
@end:   rts

; RowAt: r0 = ftStart + 17 * A. Destroys A, X.
RowAt:  tax
        lda ftStart
        sta r0L
        lda ftStart+1
        sta r0H
@add:   dex
        bmi @end
        lda r0L
        clc
        adc #17
        sta r0L
        bcc @add
        inc r0H
        bne @add
@end:   rts

ftD:    .byte 0
ftT:    .byte 0
ftLo:   .byte 0
ftHi:   .byte 0
