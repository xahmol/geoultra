; gush: cp -r, a folder copied with everything in it (docs/GUSH.md,
; "Commands"). Each folder's listing is read whole into the application's
; REU (bank TREE_BANK, one slot of TREE_SLOT bytes per entry, the levels
; one after another) before anything in it is copied, so no listing stays
; open meanwhile (the engine has FE_HANDLES_N handles) and the recursion
; can go TREE_DEPTH deep. Own code.

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
TREE_SLOTS      = $10000 / TREE_SLOT   ; (the bank's slots, all levels)
TOO_MANY        = $FF           ; (gush's own: "too many entries")
K_FOLDER        = 2
K_UDIR          = 6
K_NONE          = $FF           ; (Stat failed)
FI_SIZE         = 4
FILE_EXISTS     = $40
END_OF_DIR      = $48
FE_BAD_PATH     = $49

        .segment "CODE"

; CopyTree: the folder at r0 copied to the path at r1: into it under the
; folder's own name when r1 names a folder, else made as r1. Errors are
; said as they come (FILE_EXISTS of a folder: it is used).
CopyTree:
        ldy #$FF                ; the paths
@src:   iny
        lda (r0),y
        sta srcPath,y
        bne @src
        sty srcLen
        ldy #$FF
@dst:   iny
        lda (r1),y
        sta dstPath,y
        bne @dst
        sty dstLen
        jsr IsFolder            ; the target a folder: the source's name in it
        bcc @made
        ldx srcLen              ; (the source's last part)
@last:  dex
        bmi @whole
        lda srcPath,x
        cmp #'/'
        bne @last
@whole: lda #'/'
        jsr AddDst
@part:  inx
        lda srcPath,x
        beq @made
        jsr AddDst
        jmp @part
@made:  lda #<srcPath            ; the folder's own size (a 1581 partition:
        sta r0L                 ; the new one as big)
        lda #>srcPath
        sta r0H
        jsr Stat
        jsr Tracks
        sta mkTracks
        lda #0
        sta depth
        sta slotLo
        sta slotHi
; Tree: dstPath made, srcPath's entries copied into it.
Tree:   jsr MakeDst
        bcc :+
        rts
:       jsr List                ; the entries into this level's slots
        bcc :+
        rts
:       lda #0
        sta index
@entry: lda index
        cmp count
        bcc :+
        rts
:       jsr Fetch               ; the entry: kind, name
        lda #0
        sta tooLong
        lda srcLen              ; the paths one part longer
        pha
        lda dstLen
        pha
        lda #'/'
        jsr AddSrc
        lda #'/'
        jsr AddDst
        ldx #0
@name:  lda entry+1,x
        beq @added
        jsr AddSrc              ; (destroys A: the character again)
        lda entry+1,x
        jsr AddDst
        inx
        bne @name
@added: ldx #FE_BAD_PATH        ; (longer than a path may be: said, left)
        lda tooLong
        beq :+
        jsr SayErr
        jmp @back
:       lda entry
        cmp #K_FOLDER
        beq @folder
        cmp #K_UDIR
        beq @folder
        lda #<srcPath           ; a file: copied (asked before an overwrite)
        sta r0L
        lda #>srcPath
        sta r0H
        lda #<dstPath
        sta r1L
        lda #>dstPath
        sta r1H
        jsr Copy1
        jmp @back
@folder:
        lda depth
        cmp #TREE_DEPTH
        bcs @deep
        lda entry + TREE_SLOT - 1       ; (its size, in tracks)
        sta mkTracks
        lda index               ; this level's place, then one deeper
        pha
        lda count
        pha
        lda slotLo
        pha
        lda slotHi
        pha
        inc depth
        lda count               ; the next level's slots after this one's
        clc
        adc slotLo
        sta slotLo
        bcc :+
        inc slotHi
:       jsr Tree
        dec depth
        pla
        sta slotHi
        pla
        sta slotLo
        pla
        sta count
        pla
        sta index
        jmp @back
@deep:  ldx #FE_BAD_PATH
        jsr SayErr
@back:  pla                     ; the paths as they were
        sta dstLen
        tax
        lda #0
        sta dstPath,x
        pla
        sta srcLen
        tax
        lda #0
        sta srcPath,x
        inc index
        jmp @entry

; MakeDst: dstPath made (FE_MKDIR; there already: fine). C set when it
; failed (said).
MakeDst:
        lda #<dstPath
        sta r0L
        lda #>dstPath
        sta r0H
        lda mkTracks            ; (a 1581 partition: the source's size)
        sta r2L
        lda #FE_MKDIR
        jsr FileEngine
        txa
        beq @ok
        cpx #FILE_EXISTS
        beq @ok
        jsr SayErrDst
        sec
        rts
@ok:    clc
        rts

; List: srcPath's entries (kind, name) into the slots from slotLo/Hi;
; count their number (at most 255). C set when it failed (said).
List:   lda #<srcPath
        sta r0L
        lda #>srcPath
        sta r0H
        lda #FE_OPENDIR
        jsr FileEngine
        sta handle
        txa
        beq :+
        jsr SayErr
        sec
        rts
:       sta count
@read:  lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #<(entry + 1)
        sta r2L
        lda #>(entry + 1)
        sta r2H
        lda #0
        sta r3L
        sta r3H
        ldy handle
        lda #FE_READDIR
        jsr FileEngine
        txa
        bne @close
        lda count               ; the bank full (TREE_SLOTS), or 255 here:
        cmp #255                ; the rest left (said)
        bcs @full
        clc
        adc slotLo
        lda slotHi
        adc #0
        cmp #>TREE_SLOTS
        bcs @full
        lda info                ; (the kind, and its size in tracks)
        sta entry
        jsr Tracks
        sta entry + TREE_SLOT - 1
        lda count
        jsr SlotRegs
        jsr StashRAM
        inc count
        jmp @read
@close: ldy handle
        lda #FE_CLOSE
        jsr FileEngine
        clc
        rts
@full:  ldx #TOO_MANY
        jsr SayErr
        jmp @close

; Fetch: entry index of this level to entry.
Fetch:  lda index
        jsr SlotRegs
        jmp FetchRAM

; SlotRegs: r0-r3L for slot A of this level (slotLo/Hi + A) <-> entry.
SlotRegs:
        clc
        adc slotLo
        sta r1H                 ; (slot * 64: the slot number's two bytes
        lda slotHi              ; shifted right by two)
        adc #0
        sta r2L
        lda #0
        lsr r2L
        ror r1H
        ror a
        lsr r2L
        ror r1H
        ror a
        sta r1L
        lda #<entry
        sta r0L
        lda #>entry
        sta r0H
        lda #TREE_SLOT
        sta r2L
        lda #0
        sta r2H
        lda #TREE_BANK
        sta r3L
        rts
        .assert TREE_SLOT = 64, error, "SlotRegs: 64 bytes a slot"

; Tracks: A = info's size in blocks / 40 (a 1581 partition's tracks; at
; most 255). Destroys X.
Tracks: lda info + FI_SIZE
        sta r2L
        lda info + FI_SIZE + 1
        sta r2H
        ldx #0
@sub:   lda r2L
        sec
        sbc #40
        tay
        lda r2H
        sbc #0
        bcc @end
        sta r2H
        sty r2L
        inx
        bne @sub
        dex
@end:   txa
        rts

; IsFolder: C set when dstPath names an existing folder (or drive, or /).
IsFolder:
        lda #<dstPath
        sta r0L
        lda #>dstPath
        sta r0H
; Stat: FE_STAT of the path at r0 into info (its kind 0 when it failed).
; C set: a folder (or a drive, or /).
Stat:   lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda #FE_STAT
        jsr FileEngine
        txa
        beq :+
        lda #K_NONE
        sta info
        bne @no
:
        lda info
        cmp #K_FOLDER + 1       ; root, drive, folder: 0-2
        bcc @yes
        cmp #K_UDIR
        beq @yes
@no:    clc
        rts
@yes:   sec
        rts

; AddSrc, AddDst: A to the end of the path. X kept.
; (A path at its end: tooLong set, nothing added.) Destroy A, Y.
AddSrc: ldy srcLen
        cpy #254
        bcs Long
        sta srcPath,y
        lda #0
        sta srcPath+1,y
        inc srcLen
        rts
AddDst: ldy dstLen
        cpy #254
        bcs Long
        sta dstPath,y
        lda #0
        sta dstPath+1,y
        inc dstLen
        rts
Long:   lda #1
        sta tooLong
        rts

; SayErr: error X about srcPath; SayErrDst: about dstPath.
SayErr: lda #<srcPath
        ldy #>srcPath
        jmp FailPath
SayErrDst:
        lda #<dstPath
        ldy #>dstPath
        jmp FailPath

        .segment "DATA"

depth:          .byte 0
index:          .byte 0
count:          .byte 0
slotLo:         .byte 0
slotHi:         .byte 0
handle:         .byte 0
srcLen:         .byte 0
dstLen:         .byte 0
tooLong:        .byte 0
mkTracks:       .byte 0

        .segment "BSS"

        .segment "HIGHBSS"
srcPath:        .res 256
dstPath:        .res 256
entry:          .res TREE_SLOT
        .segment "BSS"
info:           .res 16
