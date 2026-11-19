; gush: cp -r, a folder copied with everything in it (docs/design/GUSH.md,
; "Commands"). The walk is src/inc/treewalk.inc, shared with the
; desktop's folders (each folder's listing read whole into the
; application's REU, bank TREE_BANK, before anything in it is copied, so
; no listing stays open and the copy can go TREE_DEPTH deep). Here: the
; paths, and the walk's hooks: each file through Copy1 (asked before an
; overwrite), errors said as they come (a path too long or a folder too
; deep is said and left out; a folder that cannot be listed or made
; stops the copy). Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import FileEngine, FailPath, Copy1
        .export CopyTree

StashRAM        = $C2C8         ; GEOS jump table
FetchRAM        = $C2CB
TREE_BANK       = 2             ; (1: the history; 0: MoveData's scratch)
TREE_SLOT       = 64            ; the kind byte, the name (61 bytes), the
                                ; size in tracks (its last byte)
TREE_DEPTH      = 8
TREE_TOO_MANY   = $FF           ; (gush's own: "too many entries")
K_NONE          = $FF           ; (Stat failed)
FILE_EXISTS     = $40
FE_BAD_PATH     = $49

        .segment "OV1"                 ; (overlay 1, ovl.s)

; CopyTree: the folder at r0 copied to the path at r1: into it under the
; folder's own name when r1 names a folder, else made as r1. Errors are
; said as they come (FILE_EXISTS of a folder: it is used).
CopyTree:
        ldy #$FF                ; the paths
@src:   iny
        lda (r0),y
        sta tSrc,y
        bne @src
        sty srcLen
        ldy #$FF
@dst:   iny
        lda (r1),y
        sta tDst,y
        bne @dst
        sty dstLen
        jsr IsFolder            ; the target a folder: the source's name in it
        bcc @made
        ldx srcLen              ; (the source's last part)
@last:  dex
        bmi @whole
        lda tSrc,x
        cmp #'/'
        bne @last
@whole: lda #'/'
        jsr AddDst
@part:  inx
        lda tSrc,x
        beq @made
        jsr AddDst
        jmp @part
@made:  lda #<tSrc              ; the folder's own size (a 1581 partition:
        sta r0L                 ; the new one as big)
        lda #>tSrc
        sta r0H
        jsr Stat
        jsr WalkTracks
        sta mkTracks
        lda #OP_COPY
        jmp WalkTop

; The walk's hooks (treewalk.inc). WalkFile: the file copied (Copy1
; asks before an overwrite and says its errors; the walk goes on).
WalkFile:
        lda #<tSrc
        sta r0L
        lda #>tSrc
        sta r0H
        lda #<tDst
        sta r1L
        lda #>tDst
        sta r1H
        jsr Copy1
        clc
        rts
; WalkSkip: error X about the entry said, the walk goes on.
WalkSkip:
        jsr SayErr
        clc
        rts
; WalkFail, WalkFailDst: error X about tSrc / tDst said, the walk stops.
WalkFail:
        jsr SayErr
        sec
        rts
WalkFailDst:
        lda #<tDst
        ldy #>tDst
        jsr FailPath
        sec
        rts

        .include "treewalk.inc"

; IsFolder: C set when tDst names an existing folder (or drive, or /).
IsFolder:
        lda #<tDst
        sta r0L
        lda #>tDst
        sta r0H
; Stat: FE_STAT of the path at r0 into tinfo (its kind K_NONE when it
; failed). C set: a folder (or a drive, or /).
Stat:   lda #<tinfo
        sta r1L
        lda #>tinfo
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        beq :+
        lda #K_NONE
        sta tinfo
        bne @no
:
        lda tinfo
        cmp #K_FOLDER + 1       ; root, drive, folder: 0-2
        bcc @yes
        cmp #K_UDIR
        beq @yes
@no:    clc
        rts
@yes:   sec
        rts

; AddDst: A to the end of tDst (at its end: nothing added). X kept.
; Destroys A, Y.
AddDst: ldy dstLen
        cpy #254
        bcs @end
        sta tDst,y
        lda #0
        sta tDst+1,y
        inc dstLen
@end:   rts

; SayErr: error X about tSrc said.
SayErr: lda #<tSrc
        ldy #>tSrc
        jmp FailPath

        .segment "OV1"

op:             .byte 0
depth:          .byte 0
handle:         .byte 0
srcLen:         .byte 0
dstLen:         .byte 0
mkTracks:       .byte 0
lvIndex:        .res TREE_DEPTH
lvCount:        .res TREE_DEPTH
lvSlotLo:       .res TREE_DEPTH
lvSlotHi:       .res TREE_DEPTH
lvSrcLen:       .res TREE_DEPTH
lvDstLen:       .res TREE_DEPTH

        .segment "HIGHBSS"
tSrc:           .res 256
tDst:           .res 256
entry:          .res TREE_SLOT
        .segment "BSS"
tinfo:          .res 16
