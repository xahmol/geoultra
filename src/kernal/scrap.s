; The scrap store (docs/design/DESIGN.md "Clipboard"; the user's decision of
; 2026-11-15): GEOS programs exchange cut, copy and paste through scrap
; files on their own disk, sequential files named after their type, five
; characters and " Scrap" ("Text  Scrap", "Photo Scrap", "Calc  Scrap";
; HG2G "File formats", pagetable.com "Inside geoWrite 8"). GeoUltra keeps
; them in one store in REU banks SCRAP_BANK on, whatever the program's
; drive, so a paste finds the copy made in another program, on another
; drive or in another task, and hibernation keeps it.
;
; The store is read as tracks SCRAP_TRACK+1 and +2 of every drive (the
; disk driver's Locate, sysdrive.inc), so a program reads a scrap by its
; track and sector as from its own disk. Its layout (own): block 0
; (track 246, sector 0) a directory block of 8 entries as on a GEOS disk;
; block 1 "GUSC" and the block map (a bit per block, set: used); then
; the files as on a disk (header block, data chain). Blocks: track 246
; sectors 0-255 are 0-255, track 247 256-511.
;
; The jump table's FindFile, DeleteFile and SaveFile come here (ScrapFind,
; ScrapDel, ScrapSave stubs, below). A scrap name goes to the store
; (FindFile: else the drive's own scrap, as before); any other name to
; the routine itself. The kernal's own calls (the file engine, GetFile)
; do not come this way. Own code.

        .include "geos.inc"
        .include "hw.inc"
        .include "sysdrive.inc"

        .import OvlCall, SysRAMOp, SysFindFile, SaveFile, DeleteFile
        .export ScrapFind, ScrapDel, ScrapSave

FULL_DIRECTORY  = 4
INSUFF_SPACE    = 3
DIR_BLOCK       = 0             ; the store's directory (track 246, sector 0)
MAP_BLOCK       = 1             ; its block map
BLOCKS          = SCRAP_TRACKS * 256
MAP_LEN         = BLOCKS / 8
ENTRIES         = 8
OFF_FNAME       = 3

; Shared state in the overlay scratch ($9F70-$9FFF, overlay.s: kept
; across module loads; the jump table's calls never run inside a file
; engine call, whose work area it also is): the block map and a save's
; bookkeeping between modules 103 and 104.
mapBuf          = $9F70         ; "GUSC" and the map (4 + MAP_LEN)
tmpT            = $9FB4
tmpS            = $9FB5
dirCmd          = $9FB6
entry           = $9FB7         ; the save's entry in the directory block
hdrT            = $9FB8         ; its header block
hdrS            = $9FB9
dataT           = $9FBA         ; its first data block
dataS           = $9FBB
count           = $9FBC         ; (word) its data blocks
curT            = $9FBE         ; a block being written or freed
curS            = $9FBF         ; (right after curT: NextLink fetches both)
nextT           = $9FC0
nextS           = $9FC1
left            = $9FC2         ; (word) bytes still to write
        .assert mapBuf + 4 + MAP_LEN <= tmpT, error, "scrap.s: the map overlaps"

        .segment "KEXT"

; The jump table's entries (src/kernal/jumptab.txt).
ScrapFind:
        jsr OvlCall
        .byte 101, 0
ScrapDel:
        jsr OvlCall
        .byte 102, 0
ScrapSave:
        jsr OvlCall
        .byte 103, 0

; ======================================================================

        .segment "OVL101"
        .scope Mod101

        jmp Find                ; entry 0 (FindFile: r6 = the name)

        .include "scrapname.inc"
        .include "scrapblk.inc"
        .include "scrapready.inc"
        .include "scrapseek.inc"

; Find: a scrap name: its entry in the store (dirEntryBuf; r1 = the
; directory block, r5 = the entry in diskBlkBuf; X = 0), else the drive's
; own (SysFindFile, as for every other name).
Find:   lda r6L
        ldx r6H
        jsr IsScrap
        bcs @own
        jsr Ready
        jsr Seek
        bcs @own                ; (not in the store: an old one on the disk)
        ldy #29
@copy:  lda (r5),y
        sta dirEntryBuf,y
        dey
        bpl @copy
        lda #SCRAP_TRACK + 1
        sta r1L
        lda #DIR_BLOCK
        sta r1H
        ldx #0
        rts
@own:   jmp SysFindFile

        .endscope

; ======================================================================

        .segment "OVL102"
        .scope Mod102

        jmp Delete              ; entry 0 (DeleteFile: r0 = the name)

        .include "scrapname.inc"
        .include "scrapblk.inc"
        .include "scrapready.inc"
        .include "scrapseek.inc"
        .include "scrapmap.inc"

; Delete: a scrap name in the store: its blocks freed, its entry cleared
; (X = 0); not there (an old one on the disk) and any other name:
; DeleteFile.
Delete: lda r0L
        ldx r0H
        jsr IsScrap
        bcs @own
        jsr Ready
        jsr Seek
        bcs @own
        ldy #OFF_GHDR_PTR       ; the header block
        lda (r5),y
        beq @data
        pha
        iny
        lda (r5),y
        tax
        pla
        jsr FreeTS
@data:  ldy #OFF_DE_TR_SC       ; the data chain, block by block
        lda (r5),y
        sta curT
        iny
        lda (r5),y
        sta curS
@chain: lda curT
        beq @done
        ldx curS
        jsr FreeTS
        jsr NextLink
        jmp @chain
@done:  lda #0                  ; the entry free
        tay
        sta (r5),y
        jsr DirSave
        jsr MapSave
        ldx #0
        rts
@own:   jmp DeleteFile

; NextLink: curT/curS = the link of the block curT/curS.
NextLink:
        lda curT
        ldx curS
        jsr BlkRegs
        lda #<curT
        sta r0L
        lda #>curT
        sta r0H
        lda #2
        sta r2L
        ldy #REU_FETCH
        jmp SysRAMOp


        .endscope

; ======================================================================

        .segment "OVL103"
        .scope Mod103

        jmp Save                ; entry 0 (SaveFile: r9 = the header)

        .include "scrapname.inc"
        .include "scrapblk.inc"
        .include "scrapmap.inc"

Entry:  jsr OvlCall             ; (module 104: the entry; at Save's end, so
        .byte 104, 0            ; OvlCall returns to Save's caller)
Prepare:
        jsr OvlCall             ; (module 104: X = 0 or FULL_DIRECTORY)
        .byte 104, 3

; Save: a scrap (sequential) into the store: its header block, its data
; (header's start to end address) in a chain, its entry; X = 0, or
; INSUFF_SPACE / FULL_DIRECTORY. Any other file, and a VLIR one:
; SaveFile.
Save:   ldy #0
        lda (r9),y
        pha
        iny
        lda (r9),y
        tax
        pla
        jsr IsScrap
        bcs @own
        ldy #O_GHSTR_TYPE
        lda (r9),y
        bne @own                ; (VLIR: not a scrap's)
        jsr Prepare             ; (module 104: the header, a free entry)
        txa
        beq @free
        rts
@own:   jmp SaveFile
@free:  sec                     ; the data's length
        lda fileHeader + O_GHEND_ADDR
        sbc fileHeader + O_GHST_ADDR
        sta left
        lda fileHeader + O_GHEND_ADDR + 1
        sbc fileHeader + O_GHST_ADDR + 1
        sta left+1
        lda fileHeader + O_GHST_ADDR
        sta r7L
        lda fileHeader + O_GHST_ADDR + 1
        sta r7H
        jsr Alloc               ; the header block
        bcs @full
        stx hdrT
        sty hdrS
        lda #0
        sta count
        sta count+1
        jsr Alloc               ; the first data block
        bcs @full
        stx dataT
        sty dataS
@block: stx curT                ; this block (X/Y): its data, its link
        sty curS
        inc count
        bne :+
        inc count+1
:       lda left+1              ; more than 254 bytes left: a next block
        bne @more
        lda left
        cmp #255
        bcs @more
        tax                     ; the last: link 0, the last byte's index
        inx
        stx diskBlkBuf+1
        lda #0
        sta diskBlkBuf
        lda left
        jsr Copy
        jsr PutCur
        jsr MapSave             ; (the blocks taken; the entry: module 104)
        jmp Entry
@more:  jsr Alloc
        bcs @full
        stx diskBlkBuf
        sty diskBlkBuf+1
        stx nextT
        sty nextS
        lda #254
        jsr Copy
        jsr PutCur
        sec
        lda left
        sbc #254
        sta left
        bcs :+
        dec left+1
:       ldx nextT
        ldy nextS
        jmp @block
@full:  ldx #INSUFF_SPACE       ; (nothing written: the map stays as it was)
        rts
; Copy: A bytes from r7 on to diskBlkBuf+2; r7 moves on.
Copy:   sta tmpT
        ldy #0
@c:     cpy tmpT
        beq @end
        lda (r7),y
        sta diskBlkBuf+2,y
        iny
        bne @c
@end:   lda r7L
        clc
        adc tmpT
        sta r7L
        bcc :+
        inc r7H
:       rts

; PutCur: diskBlkBuf to the block curT/curS.
PutCur: lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda curT
        ldx curS
        jmp PutBlk

        .endscope

; ======================================================================

        .segment "OVL104"
        .scope Mod104

        jmp Entry               ; entry 0 (module 103)
        jmp Prepare             ; entry 3 (module 103)

        .include "scrapblk.inc"
        .include "scrapready.inc"

; Prepare: the header (r9) to fileHeader, as SaveFile; the store ready
; (its map in mapBuf); a free directory entry (entry). X = 0, or
; FULL_DIRECTORY.
Prepare:
        ldy #0
@hdr:   lda (r9),y
        sta fileHeader,y
        iny
        bne @hdr
        jsr Ready
        jsr DirLoad
        ldy #2
@slot:  lda diskBlkBuf,y
        beq @free
        tya
        clc
        adc #32
        tay
        bcc @slot
        ldx #FULL_DIRECTORY
        rts
@free:  sty entry
        ldx #0
        rts

; Entry (module 104, after module 103's data): the header block, the
; directory entry (dirEntryBuf too); X = 0.
Entry:  lda #0                  ; the header block (link 0, $FF)
        sta fileHeader
        lda #$FF
        sta fileHeader+1
        lda #<fileHeader
        sta r0L
        lda #>fileHeader
        sta r0H
        lda hdrT
        ldx hdrS
        jsr PutBlk
        jsr DirLoad             ; the entry (diskBlkBuf held the data)
        lda entry
        clc
        adc #<diskBlkBuf
        sta r5L
        lda #>diskBlkBuf
        sta r5H
        ldy #0
        ldx #O_GHCMDR_TYPE
        lda fileHeader,x
        sta (r5),y
        iny
        lda dataT
        sta (r5),y
        iny
        lda dataS
        sta (r5),y
        ldy #0                  ; the name, $A0-padded
        lda (r9),y
        sta r6L
        iny
        lda (r9),y
        sta r6H
        ldy #0
@name:  lda (r6),y
        beq @pad
        jsr PutName
        iny
        cpy #16
        bne @name
        beq @rest
@pad:   lda #$A0
@fill:  jsr PutName
        iny
        cpy #16
        bne @fill
@rest:  ldy #OFF_GHDR_PTR
        lda hdrT
        sta (r5),y
        iny
        lda hdrS
        sta (r5),y
        iny                     ; (OFF_GSTRUC_TYPE: sequential, 0)
        lda #0
        sta (r5),y
        iny
        ldx #O_GHGEOS_TYPE
        lda fileHeader,x
        sta (r5),y
        ldy #23                 ; the date
@date:  lda year - 23,y
        sta (r5),y
        iny
        cpy #28
        bne @date
        lda count               ; the size: data blocks and the header
        clc
        adc #1
        sta (r5),y
        iny
        lda count+1
        adc #0
        sta (r5),y
        ldy #29
@copy:  lda (r5),y
        sta dirEntryBuf,y
        dey
        bpl @copy
        jsr DirSave
        ldx #0
        rts

; PutName: A = the name's character Y into the entry.
PutName:
        sty tmpS
        pha
        tya
        clc
        adc #OFF_FNAME
        tay
        pla
        sta (r5),y
        ldy tmpS
        rts

        .endscope
