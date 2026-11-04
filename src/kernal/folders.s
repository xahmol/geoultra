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
;
; 1581 images: sub-directory partitions act as folders the same way
; (folderS = 0: the partition starting at folderT; Dir81, Patch81 below,
; modules 18-21 at the end; docs/ARCHITECTURE.md "1581 partitions as
; folders"). Modules: 12 the four moves (1581 ones go on to 18), 13
; SetGEOSDisk and RemoveDir (1581: 21), 14 MakeDir (1581: 19, which
; formats with 20). Shared code: foldershared.inc, foldername.inc,
; part81.inc, bam81.inc (each module assembles its own copy).

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

; Patch81 (DirHead, Y = drive type): on a 1581, the header blocks
; (header, BAM 1 and 2) on the directory track. Y kept.
Patch81:
        cpy #DRV_1581
        bne @end
        jsr Dir81
        sta t1581
        sta t1581+4
        sta t1581+8
@end:   rts

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
want19: .byte 0                 ; 1581 partitions (modules 19-21): its
first19:.byte 0                 ; tracks, first track, and loop state,
run19:  .byte 0                 ; resident across the call from 19 to 20
sec19:  .byte 0
trk19:  .byte 0


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
        bcs @none
        jsr Dir81
        sta r1L
@none:  ldx #0                  ; (other drives: 0/0, no folders, no error)
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

Set81:  jsr OvlCall             ; module 18 (stubs here: the return goes
        .byte 18, 0             ; to this module's caller)
Up81:   jsr OvlCall
        .byte 18, 3

        .endscope

        .segment "OVL13"                ; overlay module 13: disk extras
        .scope Mod13

        jmp OvSetGEOSDisk       ; entry 0
        jmp OvRemoveDir         ; entry 3

Remove81:
        jsr OvlCall             ; module 21 (the return goes to the caller)
        .byte 21, 0

        .include "foldershared.inc"

OvRemoveDir:
        jsr Is1581              ; a 1581: a partition (module 21)
        bcs :+
        jmp Remove81
:       jsr Native
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
        jsr FreeBlock           ; (X ignored: a block already free stays
        lda diskBlkBuf          ; free, the removal goes on)
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        lda r1L
        bne @block
        lda hdrT                ; the header block
        sta r6L
        lda hdrS
        sta r6H
        jsr FreeBlock           ; (X ignored, as above)
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
; on the directory track from sector 18; native: from 1/0; else from track 19, then
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
        jsr Dir81               ; (40, or the current partition's track)
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

Make81: jsr OvlCall             ; module 19 (the return goes to the caller)
        .byte 19, 0

        .include "foldershared.inc"

OvMakeDir:
        jsr Is1581              ; a 1581: a partition (modules 19, 20)
        bcs :+
        jmp Make81
:       jsr Native
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
        .scope Mod18                    ; entered and left

        jmp Set81               ; entry 0
        jmp Up81                ; entry 3

        .include "part81.inc"

; Go: folder of slot X = A/Y (track/sector), header read (GetDirHead).
Go:     sta folderT,x
        tya
        sta folderS,x
        jmp GetDirHead

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
        jsr Formatted
        bcs @end
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

        .segment "OVL19"                ; overlay module 19: a 1581
        .scope Mod19                    ; partition created (allocation)

        jmp OvMake81            ; entry 0

        .include "foldername.inc"
        .include "bam81.inc"

DEF_TRACKS      = 10            ; MakeDir on a 1581 without a size (r2L = 0)

; OvMake81 (MakeDir on a 1581, r0 = name, r2L = tracks, 0: DEF_TRACKS):
; a partition of r2L whole free tracks of the current directory (never
; track 40), allocated there, its entry written, formatted inside as the
; real 1581 DOS does ("N0:" in a selected partition: header, BAM with
; only its own tracks free, an empty directory). X = 0, FILE_EXISTS,
; INSUFF_SPACE or a disk error.
OvMake81:
        lda r2L
        bne :+
        lda #DEF_TRACKS
:       cmp #3
        bcs :+
        lda #3
:       sta want19
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
        rts
@new:   jsr GetDirHead
        txa
        beq :+
        rts
:       lda #1                  ; first fit: want19 fully free tracks in a
        sta first19             ; row, not crossing 40
@try:   lda #0
        sta run19
@track: lda first19
        clc
        adc run19
        cmp #40
        beq @skip               ; (40 never: start after it)
        cmp #81
        bcs @full
        jsr Bam
        ldy #0
        lda (r5L),y
        cmp #40                 ; all 40 sectors free?
        bne @skip
        inc run19
        lda run19
        cmp want19
        bne @track
        beq @alloc
@skip:  lda first19             ; start again after this track
        clc
        adc run19
        adc #1
        sta first19
        jmp @try
@full:  ldx #INSUFF_SPACE
        rts
@alloc: lda #0                  ; its tracks used in the current BAM
        sta run19
@used:  lda first19
        clc
        adc run19
        jsr Bam
        ldy #5
        lda #0
@zero:  sta (r5L),y
        dey
        bpl @zero
        inc run19
        lda run19
        cmp want19
        bne @used
        jsr PutDirHead
        txa
        beq :+
        rts
:       lda #0                  ; the entry: CBM, first/0, name, size
        sta r10L
        jsr GetFreeDirBlk
        txa
        beq :+
        rts
:       lda #$85
        sta diskBlkBuf,y
        lda first19
        sta diskBlkBuf+1,y
        lda #0
        sta diskBlkBuf+2,y
        tya
        pha
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        iny
        iny
        iny
        jsr Name
        pla
        tay
        lda #0                  ; size = tracks * 40 (lo at +$1C)
        sta r6L
        sta r6H
        ldx want19
@size:  clc
        lda r6L
        adc #40
        sta r6L
        bcc :+
        inc r6H
:       dex
        bne @size
        lda r6L
        sta diskBlkBuf+$1C,y
        lda r6H
        sta diskBlkBuf+$1D,y
        jsr PutBlock            ; r1 = the entry's block
        txa
        beq :+
        rts
:       jmp Format              ; inside it (module 20)

Format: jsr OvlCall             ; (a stub here: the return goes to the
        .byte 20, 0             ; caller of OvMake81)

        .endscope

        .segment "OVL20"                ; overlay module 20: a new 1581
        .scope Mod20                    ; partition formatted inside

        jmp Format              ; entry 0

        .include "foldername.inc"

; Format (module 20): the new partition first19 of want19 tracks inside:
; header t/0, BAM t/1 (tracks 1-40) and t/2 (41-80), the empty directory
; t/3. X = 0 or an error.
Format: jsr Header
        txa
        bne @end
        lda #1
        jsr BamBlock
        txa
        bne @end
        lda #2
        jsr BamBlock
        txa
        bne @end
        ldy #0                  ; t/3: the empty directory
        tya
@dclr:  sta fileHeader,y
        iny
        bne @dclr
        lda #$FF
        sta fileHeader+1
        lda #3
        jmp WriteT
@end:   rts

; Header: the partition's header block t/0.
Header: ldy #0
        tya
@clr:   sta fileHeader,y
        iny
        bne @clr
        lda first19
        sta fileHeader
        lda #3
        sta fileHeader+1
        lda #'D'
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
        jsr Ids
        lda #'3'
        sta fileHeader+$19
        lda #'D'
        sta fileHeader+$1A
        lda #0
        jmp WriteT

; Ids: the disk ID (curDirHead holds the header with $04-$1C at
; $90-$A8, as GEOS 2.0) to fileHeader $16/$17 and r7 (for the BAM).
Ids:    lda curDirHead+$A2
        sta fileHeader+$16
        sta r7L
        lda curDirHead+$A3
        sta fileHeader+$17
        sta r7H
        rts

; BamBlock: A = 1 or 2: the partition's BAM block t/A (its 40 tracks:
; the partition's own free, its first track minus 4 sectors, the rest
; used).
BamBlock:
        sta sec19
        ldy #0
        tya
@clr:   sta fileHeader,y
        iny
        bne @clr
        lda sec19               ; link: t/2 from the first, 00/FF after
        cmp #1
        bne @last
        lda first19
        sta fileHeader
        lda #2
        sta fileHeader+1
        bne @head
@last:  lda #$FF
        sta fileHeader+1
@head:  lda #'D'
        sta fileHeader+2
        lda #'D' ^ $FF
        sta fileHeader+3
        lda r7L
        sta fileHeader+4
        lda r7H
        sta fileHeader+5
        lda #$C0
        sta fileHeader+6
        ldx #1                  ; tracks of this block: 1-40 or 41-80
        lda sec19
        cmp #1
        beq :+
        ldx #41
:       stx trk19
        ldy #$10
@entry: lda trk19               ; inside the partition?
        sec
        sbc first19
        bcc @next
        cmp want19
        bcs @next
        tax                     ; its first track: 36 free, sectors 0-3
        bne @whole              ; used
        lda #36
        sta fileHeader,y
        lda #$F0
        sta fileHeader+1,y
        lda #$FF
        bne @rest
@whole: lda #40
        sta fileHeader,y
        lda #$FF
        sta fileHeader+1,y
@rest:  sta fileHeader+2,y
        sta fileHeader+3,y
        sta fileHeader+4,y
        sta fileHeader+5,y
@next:  inc trk19
        tya                     ; 40 entries from $10: Y wraps to 0
        clc
        adc #6
        tay
        bne @entry
        lda sec19

; WriteT: fileHeader to the partition's block first19/A. X = error.
WriteT: sta r1H
        lda first19
        sta r1L
        lda #<fileHeader
        sta r4L
        lda #>fileHeader
        sta r4H
        jmp PutBlock

        .endscope

        .segment "OVL21"                ; overlay module 21: a 1581
        .scope Mod21                    ; partition removed

        jmp OvRemove81          ; entry 0

        .include "part81.inc"
        .include "bam81.inc"

; OvRemove81 (RemoveDir on a 1581, r0 = name): an empty, formatted
; sub-directory partition (as SetCurDir would enter): its tracks freed in
; the current BAM, its entry removed. X = 0, DIR_NOT_EMPTY, STRUCT_MISMAT
; or a disk error.
OvRemove81:
        lda r0L
        sta r6L
        lda r0H
        sta r6H
        jsr FindFile
        txa
        beq :+
        rts
:       lda r1L                 ; its entry
        sta entT
        lda r1H
        sta entS
        lda r5L
        sec
        sbc #<diskBlkBuf
        sta entOff
        jsr Valid               ; a sub-directory, formatted?
        bcs @mis
        sta first19
        lda r3L
        sta want19
        lda first19
        jsr Formatted
        bcc :+
        rts
:       lda first19             ; empty? its directory t/3 onwards
        sta r1L
        lda #3
        sta r1H
@block: lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        beq :+
        rts
:       ldy #2
@ent:   lda diskBlkBuf,y
        bne @full
        tya
        clc
        adc #32
        tay
        bcc @ent
        lda diskBlkBuf
        beq @empty
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        jmp @block
@full:  ldx #DIR_NOT_EMPTY
        rts
@mis:   ldx #STRUCT_MISMAT
        rts
@empty: jsr GetDirHead          ; its tracks free in the current BAM
        txa
        beq :+
        rts
:       lda #0
        sta run19
@free:  lda first19
        clc
        adc run19
        jsr Bam
        ldy #0
        lda #40
        sta (r5L),y
        lda #$FF
@ff:    iny
        sta (r5L),y
        cpy #5
        bne @ff
        inc run19
        lda run19
        cmp want19
        bne @free
        jsr PutDirHead
        txa
        beq :+
        rts
:       lda entT                ; the entry: type 0
        sta r1L
        lda entS
        sta r1H
        lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        beq :+
        rts
:       ldy entOff
        lda #0
        sta diskBlkBuf,y
        jmp PutBlock

        .endscope
