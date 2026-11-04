; Folders on native drives (docs/DESIGN.md, "Directories"): CMD native
; subdirectories. Each drive has a current folder (the T/S of its header
; block; 1/1 is the root); the disk driver reads and writes that header as
; curDirHead and starts the directory at its link, so existing applications
; see the folder as the whole disk. The extension jump table (guExtTable
; in the information block) leads to the calls below.
;
; Format as CMD native (FD/HD, RAMLink; documented e.g. in Wikipedia's "CMD
; FD series"; checked against the user's DNP images, which have no
; folders): a folder is a directory entry of CBM type DIR ($86) whose T/S
; is the folder's header block. A header: $00/$01 the first directory
; block, $02 "H", $04-$13 the name, $16/$17 the disk ID, $19/$1A "1H",
; $20/$21 its own T/S, $22/$23 the parent header (0/0 at the root),
; $24/$25 the block holding its entry in the parent, $26 the entry's offset
; there (GeoUltra writes the offset of the entry's type byte: to be
; checked against an image made by CMD software). Own code.

        .include "geos.inc"
        .include "kcalls.inc"

        .export folderT, folderS, ExtTable, SetGEOSDiskOvl, Dir81, Patch81
        .import t1581
        .import OvlCall
        .import DrvGetDirHead, DrvPutDirHead, CalcBlksFree, SetNextFree, ClearAndWrite
        .import geosId

FindFile        = $C20B         ; jump table
FILE_EXISTS     = $40           ; GeoUltra's own error codes (MakeDir,
DIR_NOT_EMPTY   = $41           ; RemoveDir)
INSUFF_SPACE    = 3             ; (as the disk driver)
DIR_TRACK       = 18

        .segment "CODE"

; Current folder per drive (header T/S; 1/1: the root). Kept in RAM, so a
; hibernated session keeps it.
folderT:        .byte 1, 1, 1, 1
folderS:        .byte 1, 1, 1, 1

; Dir81 (driver): A = the current 1581 drive's directory track: the
; current partition's first track (folderS = 0), or 40 at the root
; (the 1/1 of a native root). Destroys X.
Dir81:  ldx curDrive
        lda folderS-8,x
        bne @root
        lda folderT-8,x
        rts
@root:  lda #40
        rts

; Patch81 (DirHead): the 1581 header blocks (header, BAM 1 and 2) on the
; directory track. Y kept.
Patch81:
        jsr Dir81
        sta t1581
        sta t1581+4
        sta t1581+8
        rts

; Extension jump table (guExtTable): one entry of 5 bytes per call, in
; this order; each returns X = 0 or an error.
ExtTable:
GetCurDir:      jsr OvlCall     ; +0  r1 = the current folder (0/0: no
        .byte 12, 0             ;     folders on this drive)
SetCurDir:      jsr OvlCall     ; +5  r0 = name of a folder in it: enter
        .byte 12, 3
DirUp:          jsr OvlCall     ; +10 to the parent folder
        .byte 12, 6
DirRoot:        jsr OvlCall     ; +15 to the root
        .byte 12, 9
MakeDir:        jsr OvlCall     ; +20 r0 = name: a new folder in it
        .byte 14, 0
RemoveDir:      jsr OvlCall     ; +25 r0 = name of an empty folder: removed
        .byte 13, 3

SetGEOSDiskOvl:                 ; the driver's SetGEOSDisk (module 13)
        jsr OvlCall
        .byte 13, 0

; The folder modules' variables: resident, as a module's own bytes are
; fetched anew after every nested overlay call (SetNextFree, the BAM).
hdrT:   .byte 0                 ; the new folder's header
hdrS:   .byte 0
dirT:   .byte 0                 ; its first directory block
dirS:   .byte 0
entT:   .byte 0                 ; the block holding its entry
entS:   .byte 0
entOff: .byte 0                 ; the entry's type byte in that block
nameLo: .byte 0
nameHi: .byte 0


        .segment "OVL12"                ; overlay module 12: folders
        .scope Mod12

        jmp OvGetCurDir         ; entry 0
        jmp OvSetCurDir         ; entry 3
        jmp OvDirUp             ; entry 6
        jmp OvDirRoot           ; entry 9

        .include "foldershared.inc"

OvGetCurDir:
        lda #0
        sta r1L
        sta r1H
        jsr Native
        bcs @c81
        lda folderT,x
        sta r1L
        lda folderS,x
        sta r1H
        ldx #0
@end:   rts
@c81:   jsr Is1581              ; 1581: the partition's header t/0, or 40/0
        bcs @end
        jsr Dir81
        sta r1L
        ldx #0
        rts

; Go: folder of slot X = A/Y (track/sector), header read (GetDirHead).
Go:     sta folderT,x
        tya
        sta folderS,x
        jmp GetDirHead

OvSetCurDir:
        jsr Is1581
        bcs :+
        jmp Set81
:       jsr FindDir
        bcs @end
        jsr Native
        lda dirEntryBuf + 1
        ldy dirEntryBuf + 2
        jmp Go
@end:   rts

OvDirUp:
        jsr Is1581
        bcs :+
        jmp Up81
:       jsr Native
        bcs @end
        lda curDirHead + $22
        beq @root               ; (0: already the root)
        ldy curDirHead + $23
        jmp Go
@root:  ldx #0
@end:   rts

OvDirRoot:
        jsr Is1581              ; (1581: 1/1 means the root, track 40)
        bcc @root
        jsr Native
        bcs @end
@root:  lda #1
        tay
        jmp Go
@end:   rts

; --- 1581 partitions as folders (docs/GEOS_REFERENCE.md "1581
; partitions", as the real 1581 DOS writes them) ---------------------
; The current partition is folderT = its first track, folderS = 0; the
; root keeps the native default 1/1 (Dir81 then gives track 40).

; Is1581: C clear and X = slot when the current drive is a 1581.
Is1581: ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_1581
        bne @no
        txa
        sec
        sbc #8
        tax
        clc
        rts
@no:    sec
        rts

Set81:  jsr OvlCall             ; module 18 (stubs here: the return goes
        .byte 18, 0             ; to this module's caller)
Up81:   jsr OvlCall
        .byte 18, 3

        .endscope

        .segment "OVL13"                ; overlay module 13: disk extras
        .scope Mod13

        jmp OvSetGEOSDisk       ; entry 0
        jmp OvRemoveDir         ; entry 3

        .include "foldershared.inc"

OvRemoveDir:
        jsr Native
        bcc :+
        rts
:       jsr FindDir
        bcc :+
        rts
:
        lda r1L                 ; its entry
        sta entT
        lda r1H
        sta entS
        lda r5L
        sec
        sbc #<diskBlkBuf
        sta entOff
        lda dirEntryBuf+1
        sta hdrT
        lda dirEntryBuf+2
        sta hdrS
        jsr GetDirHead          ; the BAM's working copy: freed blocks only
        txa                     ; count with the PutDirHead at the end
        beq :+
        rts
:
        lda hdrT                ; its header: the first directory block
        sta r1L
        lda hdrS
        sta r1H
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        jsr GetBlock
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        lda fileHeader
        sta r1L
        lda fileHeader+1
        sta r1H
@block: lda #<diskBlkBuf        ; every directory block: empty? then freed
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        ldy #2
@entry: lda diskBlkBuf,y
        bne @full
        tya
        clc
        adc #32
        tay
        bcc @entry
        lda r1L
        sta r6L
        lda r1H
        sta r6H
        jsr FreeBlock
        lda diskBlkBuf
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        lda r1L
        bne @block
        lda hdrT                ; the header block
        sta r6L
        lda hdrS
        sta r6H
        jsr FreeBlock
        lda entT                ; the entry: gone
        sta r1L
        lda entS
        sta r1H
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        ldy entOff
        lda #0
        sta diskBlkBuf,y
        jsr PutBlock
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        jmp PutDirHead
@full:  ldx #DIR_NOT_EMPTY      ; (the BAM's copy is dropped at the next
@end:   rts                     ; GetDirHead)


; SetGEOSDisk (driver): make the disk a GEOS disk: a border block (1581:
; on track 40 from sector 18; native: from 1/0; else from track 19, then
; from track 1) and the signature in the header. X = 0 or INSUFF_SPACE.
; Destroys A, Y, r0L, r1, r4, r5.
OvSetGEOSDisk:
        jsr DrvGetDirHead
        txa
        bne @end
        lda #<curDirHead
        sta r5L
        lda #>curDirHead
        sta r5H
        jsr CalcBlksFree
        ldx #INSUFF_SPACE
        lda r4L
        ora r4H
        beq @end
        ldy curDrive
        lda driveType-8,y
        and #$0F
        cmp #DRV_1581
        bne @notMp
        lda #40
        ldy #18
        bne @one
@notMp: cmp #DRV_NATIVE
        bne @cbm
        lda #1
        ldy #0
@one:   sta r3L
        sty r3H
        jsr SetNextFree
        txa
        bne @end
        beq @border
@cbm:   lda #DIR_TRACK + 1
        sta r3L
        lda #0
        sta r3H
        jsr SetNextFree
        txa
        beq @border
        lda #1
        sta r3L
        jsr SetNextFree
        txa
        bne @end
@border:
        lda r3L
        sta r1L
        lda r3H
        sta r1H
        jsr ClearAndWrite
        txa
        bne @end
        lda r1L
        sta curDirHead + OFF_OP_TR_SC
        lda r1H
        sta curDirHead + OFF_OP_TR_SC + 1
        ldy #15
@sig:   lda geosId,y
        sta curDirHead + OFF_GS_ID,y
        dey
        bpl @sig
        jmp DrvPutDirHead
@end:   rts

        .endscope

        .segment "OVL14"                ; overlay module 14: new folders
        .scope Mod14

        jmp OvMakeDir           ; entry 0

        .include "foldershared.inc"

OvMakeDir:
        jsr Native
        bcs @end
        lda r0L
        sta nameLo
        sta r6L
        lda r0H
        sta nameHi
        sta r6H
        jsr FindFile            ; the name must be new
        cpx #FILE_NOT_FOUND
        beq @new
        ldx #FILE_EXISTS
@end:   rts
@new:   jsr GetDirHead          ; (also the BAM's working copy)
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        jsr Native
        lda folderT,x           ; two blocks near the current folder
        sta r3L
        lda folderS,x
        sta r3H
        jsr SetNextFree
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        lda r3L
        sta hdrT
        lda r3H
        sta hdrS
        jsr SetNextFree
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        lda r3L
        sta dirT
        lda r3H
        sta dirS
        lda #0                  ; a free entry in the current folder
        sta r10L
        jsr GetFreeDirBlk
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        lda r1L
        sta entT
        lda r1H
        sta entS
        sty entOff
        lda #$86                ; the entry: DIR, header T/S, name, 2 blocks
        sta diskBlkBuf,y
        lda hdrT
        sta diskBlkBuf+1,y
        lda hdrS
        sta diskBlkBuf+2,y
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        iny
        iny
        iny
        jsr Name
        lda #0
        ldx #9
@geos:  sta diskBlkBuf,y        ; no GEOS header, structure, type, date
        iny
        dex
        bne @geos
        lda #2
        sta diskBlkBuf,y
        lda #0
        sta diskBlkBuf+1,y
        jsr PutBlock            ; r1 = the entry's block, r4 = diskBlkBuf
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        ldy #0                  ; the header, in fileHeader
        tya
@clear: sta fileHeader,y
        iny
        bne @clear
        lda dirT
        sta fileHeader
        lda dirS
        sta fileHeader+1
        lda #'H'
        sta fileHeader+2
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        ldy #4
        jsr Name
        lda #$A0
        sta fileHeader+$14
        sta fileHeader+$15
        sta fileHeader+$18
        sta fileHeader+$1B
        sta fileHeader+$1C
        lda curDirHead+$A2      ; the disk ID (curDirHead holds the header
        sta fileHeader+$16      ; with $04-$1C at $90-$A8, as GEOS 2.0)
        lda curDirHead+$A3
        sta fileHeader+$17
        lda #'1'
        sta fileHeader+$19
        lda #'H'
        sta fileHeader+$1A
        lda hdrT
        sta fileHeader+$20
        sta r1L
        lda hdrS
        sta fileHeader+$21
        sta r1H
        jsr Native
        lda folderT,x
        sta fileHeader+$22
        lda folderS,x
        sta fileHeader+$23
        lda entT
        sta fileHeader+$24
        lda entS
        sta fileHeader+$25
        lda entOff
        sta fileHeader+$26
        jsr PutBlock            ; r1 = header, r4 = fileHeader
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        lda dirT                ; the empty first directory block
        sta r1L
        lda dirS
        sta r1H
        jsr ClearAndWrite
        txa                     ; (an error: back with it)
        beq :+
        rts
:
        jmp PutDirHead
@end2:  rts
        .endscope

        .segment "OVL18"                ; overlay module 18: 1581 partitions
        .scope Mod18

        jmp Set81               ; entry 0
        jmp Up81                ; entry 3

; Go: folder of slot X = A/Y (track/sector), header read (GetDirHead).
Go:     sta folderT,x
        tya
        sta folderS,x
        jmp GetDirHead

; Tracks: A/Y = a partition's size in blocks (lo/hi) -> A = its tracks,
; C clear when it is a whole number of at least 3 (a sub-directory).
Tracks: sta r2L
        sty r2H
        lda #0
        sta r3L
@sub:   lda r2L
        ora r2H
        beq @done
        sec
        lda r2L
        sbc #40
        sta r2L
        lda r2H
        sbc #0
        sta r2H
        bcc @bad                ; (not a multiple of 40)
        inc r3L
        bne @sub
@done:  lda r3L
        cmp #3
        rts                     ; (C set: at least 3; inverted below)
@bad:   clc
        rts

; Valid: dirEntryBuf a partition usable as a sub-directory (type CBM,
; sector 0, whole tracks, at least 3, track 40 outside): C clear, A =
; its first track, r3L its tracks.
Valid:  lda dirEntryBuf
        and #$07
        cmp #5                  ; CBM
        bne @no
        lda dirEntryBuf + 2
        bne @no
        lda dirEntryBuf + OFF_SIZE
        ldy dirEntryBuf + OFF_SIZE + 1
        jsr Tracks
        bcc @no
        clc                     ; last = first + tracks - 1 < 40, or
        lda dirEntryBuf + 1     ; first > 40
        cmp #41
        bcs @ok
        adc r3L
        cmp #41
        bcs @no
@ok:    lda dirEntryBuf + 1
        clc
        rts
@no:    sec
        rts

; Set81 (SetCurDir on a 1581, r0 = name): enter the partition when it is a
; formatted sub-directory (its header t/0: "D", link t/3).
Set81:  stx slot81
        lda r0L
        sta r6L
        lda r0H
        sta r6H
        jsr FindFile
        txa
        bne @end
        jsr Valid
        bcs @mis
        sta r1L
        lda #0
        sta r1H
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        bne @end
        lda diskBlkBuf + 2
        cmp #'D'
        bne @mis
        lda diskBlkBuf
        cmp r1L
        bne @mis
        lda diskBlkBuf + 1
        cmp #3
        bne @mis
        ldx slot81
        lda r1L
        ldy #0
        jmp Go
@mis:   ldx #STRUCT_MISMAT
@end:   rts

; Up81 (DirUp on a 1581): the parent, found by walking from the root
; through the partitions that contain the current one (the disk has no
; parent pointer).
Up81:   stx slot81
        lda folderS,x
        beq :+
        jmp @top                ; (the root already)
:       lda folderT,x
        sta want81
        lda #40                 ; walk from the root
        sta cur81
@dir:   lda cur81               ; its directory: cur81/3 onwards
        sta r1L
        lda #3
        sta r1H
@block: lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        bne @top
        ldy #2
@entry: lda diskBlkBuf,y        ; a CBM entry at sector 0
        and #$07
        cmp #5
        bne @next
        lda diskBlkBuf+2,y
        bne @next
        tya
        pha
        lda diskBlkBuf + $1C,y  ; its tracks (size / 40)
        pha
        lda diskBlkBuf + $1D,y
        tay
        pla
        jsr Tracks
        pla
        tay
        bcc @next
        lda diskBlkBuf+1,y      ; first <= want < first + tracks?
        cmp want81
        beq @found
        bcs @next
        clc
        adc r3L
        cmp want81
        beq @next
        bcc @next
        lda diskBlkBuf+1,y      ; inside it: walk on in there
        sta cur81
        jmp @dir
@next:  tya
        clc
        adc #32
        tay
        bcs :+
        jmp @entry
:
        lda diskBlkBuf          ; the next directory block
        beq @top
        sta r1L
        lda diskBlkBuf + 1
        sta r1H
        jmp @block
@found: ldx slot81              ; the parent is cur81
        lda cur81
        cmp #40
        beq @top
        ldy #0
        jmp Go
@top:   ldx slot81              ; the root (also when lost)
        lda #1
        tay
        jmp Go

slot81: .byte 0                 ; (module bytes: no nested overlay calls
want81: .byte 0                 ; while they are used)
cur81:  .byte 0

        .endscope
