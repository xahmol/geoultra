; File engine: the Ultimate's file system (docs/FILE_ENGINE.md, "Paths";
; engine.s has the module list). Module 36: the exchange with the
; Ultimate's DOS (target 2), its status as an error, and the folder
; changes every Ultimate function starts with; the function modules reach
; it through feult.inc. Own code; the commands as the ultimate-uci-oscar64
; library sends them (docs/UCILIB_MANUAL.md), checked on a U64-II with
; firmware 3.15a (FILE_STAT answers "82" there for every file, so FE_STAT
; opens the file instead).

        .include "geos.inc"
        .include "hw.inc"
        .include "kcalls.inc"
        .include "engine.inc"

        .import OvlCall, SysRAMOp, uciPresent

        .segment "OVL36"
        .scope Mod36

        jmp OvExec              ; entry 0
        jmp OvCdX               ; entry 3

UCI_STAT_MAX    = U_STAT_MAX
cmdBuf          = uCmd
cmdLen          = uLen
statBuf         = uStat
dataEnd         = uEnd
        .include "uci.inc"

; OvExec: uCmd (uLen bytes) to the Ultimate, the reply's data (every
; packet) to (r0) up to uEnd, the status to uStat. I/O on meanwhile
; (MainLoop runs applications with $01 = $30; the interrupt sets $01
; itself). X = 0 (no status, "0x"), FILE_NOT_FOUND ("82", "83", "88",
; "FILE DOESN'T EXIST"), FILE_EXISTS ("FILE EXISTS"), WR_PR_ON ("ACCESS
; DENIED") or FE_ULTIMATE (the status in uStat); without a UCI (VICE)
; DEV_NOT_FOUND. Destroys A, Y.
OvExec: ldx #DEV_NOT_FOUND
        lda uciPresent
        bne :+
        rts
:       lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        jsr UciSend
@packet:
        jsr UciData
        lda uciCtrl             ; "data more": the next packet after an ack
        and #$30
        cmp #$30
        bne @last
        jsr UciAccept
        jmp @packet
@last:  jsr UciStatus
        jsr UciAccept
        pla
        sta CPU_PORT
        ldy #0                  ; the first status that fits
@try:   ldx Statuses+3,y
        lda Statuses,y
        cmp #$FF
        beq @ult
        cmp uStat
        bne @next
        lda Statuses+1,y        ; (0: any)
        beq @end
        cmp uStat+1
        bne @next
        lda Statuses+2,y        ; the sixth (0: any)
        beq @end
        cmp uStat+5
        beq @end
@next:  iny
        iny
        iny
        iny
        bne @try
@ult:   ldx #FE_ULTIMATE
@end:   rts

; The statuses: the first, second and sixth character (0: any), the
; error; $FF ends.
Statuses:
        .byte 0, 0, 0, 0        ; none (a read)
        .byte "0", 0, 0, 0      ; "00" OK, "01" DIRECTORY EMPTY, ...
        .byte "82", 0, FILE_NOT_FOUND
        .byte "83", 0, FILE_NOT_FOUND
        .byte "88", 0, FILE_NOT_FOUND
        .byte "FIE", FILE_EXISTS        ; FILE EXISTS
        .byte "FID", FILE_NOT_FOUND     ; FILE DOESN'T EXIST
        .byte "AC", 0, WR_PR_ON         ; ACCESS DENIED
        .byte $FF
; OvCdX: into fePath's first X characters (at least 1), as few CD
; commands as fit uCmd: the first absolute, the rest relative, each ending
; at a "/". X = 0 or the error (FE_BAD_PATH: one part longer than a
; command takes).
OvCdX:  stx uCdEnd
        lda #0
        sta uCdPos
@piece: lda uCdPos              ; this piece's end: all, or the last "/"
        clc                     ; that fits
        adc #U_CMD_MAX - 3
        bcs @all
        cmp uCdEnd
        bcs @all
        tax
@back:  lda fePath,x
        cmp #'/'
        beq @send
        dex
        cpx uCdPos
        bne @back
        ldx #FE_BAD_PATH
        rts
@all:   ldx uCdEnd
@send:  stx uCdNext
        lda #U_TARGET
        sta uCmd
        lda #U_CD
        sta uCmd+1
        ldx uCdPos              ; (after the first: past its "/", relative)
        beq :+
        inx
:       ldy #2
@copy:  cpx uCdNext
        beq @go
        lda fePath,x
        sta uCmd,y
        inx
        iny
        bne @copy
@go:    sty uLen
        lda #0
        sta uEnd
        sta uEnd+1
        jsr OvExec
        txa
        bne @end
        lda uCdNext
        sta uCdPos
        cmp uCdEnd
        bcc @piece
@end:   rts

        .endscope

        .segment "OVL37"
        .scope Mod37

        jmp OvUStat             ; entry 0

        .include "feult.inc"
        .include "fecd.inc"
        .include "feinfo.inc"

; OvUStat (FE_STAT on the Ultimate; r1 = the info block): a file is
; opened for its size, date and attributes (FILE_INFO), then closed; a
; name that does not open but can be entered is a folder.
OvUStat:
        lda feName
        bne @named
        jsr UCdAll              ; the top itself
        txa
        bne @end
        beq @dir
@named: jsr UCd
        txa
        bne @end
        lda #U_OPEN
        jsr UBegin
        lda #UO_READ
        jsr UPut
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        bne @folder
        lda #U_INFO             ; size, date, time, extension, attributes
        jsr UBegin
        lda #<diskBlkBuf
        sta r0L
        sta uEnd
        lda #>diskBlkBuf
        sta r0H
        sta uEnd+1
        inc uEnd+1
        jsr UExec
        stx feM
        lda #U_CLOSE
        jsr UBegin
        jsr UNoData
        jsr UExec
        ldx feM
        bne @end
        lda #FE_K_UFILE
        jsr InfoKind
        jsr FileInfo
        jmp Put
@folder:
        lda #U_CD               ; not a file: a folder?
        jsr UBegin
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        bne @end
@dir:   lda #FE_K_UDIR
        jsr InfoKind
        jmp Put
@end:   rts

; Put: the info block to the caller; the name (the path's last part, the
; top's own name for a top; cut to FE_LONG_MAX) to r2 when not 0.
Put:    jsr PutInfo
        lda argR2+1
        beq @end
        sta r0H
        lda argR2
        sta r0L
        ldx fePos               ; (the top: from its "/")
        lda feName
        bne :+
        ldx #0
:       ldy #0
@copy:  inx
        lda fePath,x
        sta (r0),y
        beq @end
        iny
        cpy #FE_LONG_MAX
        bne @copy
        lda #0
        sta (r0),y
@end:   ldx #0
        rts

; FileInfo: FILE_INFO's reply (diskBlkBuf: size, FAT date and time,
; extension, attributes) into feInfo. Destroys A, X, feM.
FileInfo:
        ldx #3
@size:  lda diskBlkBuf,x
        sta feInfo + FI_SIZE,x
        dex
        bpl @size
        jsr FatDate
        lda diskBlkBuf+11       ; attributes
        and #UA_READONLY
        sta feInfo + FI_FLAGS
        rts
        .assert UA_READONLY = FF_READONLY, error, "FileInfo: read-only bit"

FAT_OUT         = feInfo + FI_DATE
        .include "fefat.inc"

        .endscope

        .segment "OVL38"
        .scope Mod38

        jmp OvUOpen             ; entry 0

        .include "feult.inc"
        .include "fecd.inc"
        .include "fereu.inc"

UList:  jsr OvlCall             ; (module 47: READ_DIR into the slots)
        .byte 47, 0

; OvUOpen (FE_OPENDIR on the Ultimate; handle feHandle chosen): the
; folder's entries read whole into REU bank FE_UBANK + handle, one slot
; each, so that no reply stays open between engine calls (the write-back
; would release it). The last part with "*" or "?", or one that is no
; folder: the pattern (at most FE_NAME_MAX characters), in the folder
; holding it. A = the handle.
OvUOpen:
        lda #'*'                ; everything, unless a pattern
        sta feH + H_PAT
        lda #0
        sta feH + H_PAT+1
        lda feName
        beq @all                ; the top itself
        jsr Wild
        bcc @pat
        jsr UCdAll              ; a folder: all of it
        txa
        beq @list
@pat:   ldx fePos               ; the last part as the pattern
        ldy #0
@copy:  inx
        lda fePath,x
        sta feH + H_PAT,y
        beq @in
        iny
        cpy #FE_NAME_MAX + 1
        bne @copy
        ldx #FE_BAD_PATH
        rts
@in:    jsr UCd
        jmp @cd
@all:   jsr UCdAll
@cd:    txa
        bne @end
@list:  lda #U_OPENDIR
        jsr UBegin
        jsr UNoData
        jsr UExec               ; ("01,DIRECTORY EMPTY": X = 0)
        txa
        bne @end
        jsr UList
        lda #HT_UDIR
        sta feH + H_TYPE
        ldy #REU_STASH
        jsr HandleOp
        lda feHandle
        ldx #0
@end:   rts

; Wild: C clear when the path's last part holds "*" or "?".
Wild:   ldx fePos
@ch:    inx
        lda fePath,x
        beq @no
        cmp #'*'
        beq @yes
        cmp #'?'
        bne @ch
@yes:   clc
        rts
@no:    sec
        rts

        .endscope

        .segment "OVL39"
        .scope Mod39

        jmp OvUReadDir          ; entry 0

        .include "fereu.inc"
        .include "feinfo.inc"
        .include "fegive.inc"
MATCH_NAME      = fileHeader + 1
MATCH_FOLD      = uCdPos        ; (free while listing)
        .include "fematch.inc"

; OvUReadDir (FE_READDIR on an Ultimate listing, the handle in feH): the
; next entry that fits the pattern; r1 = the info block, r2 = a name
; buffer of FE_USLOT - 1 bytes. X = FE_END_OF_DIR after the last one.
OvUReadDir:
@next:  lda feH + H_UNEXT       ; the slot to fileHeader
        cmp feH + H_UCOUNT
        lda feH + H_UNEXT+1
        sbc feH + H_UCOUNT+1
        bcs @eod
        lda feH + H_UNEXT
        sta r1L
        lda feH + H_UNEXT+1
        sta r1H
        ldx #6
@mul:   asl r1L
        rol r1H
        dex
        bne @mul
        lda #<fileHeader
        sta r0L
        lda #>fileHeader
        sta r0H
        lda #FE_USLOT
        sta r2L
        lda #0
        sta r2H
        lda feHandle
        clc
        adc #FE_UBANK
        sta r3L
        ldy #REU_FETCH
        jsr SysRAMOp
        inc feH + H_UNEXT
        bne :+
        inc feH + H_UNEXT+1
:       jsr Match
        bcs @next
        ldx #FE_K_UFILE         ; a file or a folder
        lda fileHeader
        and #UA_DIR
        beq @kind
        ldx #FE_K_UDIR
@kind:  txa
        jsr InfoKind
        lda fileHeader
        and #UA_READONLY
        sta feInfo + FI_FLAGS
        jmp Give
@eod:   ldx #FE_END_OF_DIR
        rts

        .assert FE_USLOT = 64, error, "OvUReadDir: 64 bytes a slot"

        .endscope

        .segment "OVL40"
        .scope Mod40

        jmp OvRoot              ; entry 0

        .include "fereu.inc"
        .include "feinfo.inc"
        .include "feult.inc"
        .include "fecd.inc"
        .include "fegive.inc"

; OvRoot (FE_READDIR on "/"; H_BLKT the next slot): the drives A-D that
; are there, drive E, then (with a UCI) the Ultimate's tops it can enter.
OvRoot: ldx feH + H_BLKT
        cpx #4
        bcs @e
        inc feH + H_BLKT
        lda driveType,x
        beq OvRoot
        txa
        clc
        adc #'a'
@drive: sta fileHeader+1
        lda #0
        sta fileHeader+2
        lda #FE_K_DRIVE
        bne @give
@e:     bne @tops               ; (4: drive E, always there)
        inc feH + H_BLKT
        lda #'e'
        bne @drive
@tops:  lda uciPresent
        beq Eod
        lda TopAt-5,x
        beq Eod
        inc feH + H_BLKT
        tay                     ; "/" and its name to fePath (fileHeader:
        ldx #0                  ; the name at fileHeader + 1 for Give)
        lda #'/'
@copy:  sta fePath,x
        inx
        lda Tops-1,y
        iny
        cmp #0
        bne @copy
        sta fePath,x
        jsr UCdAll
        txa
        bne OvRoot              ; (not there: the next)
        lda #FE_K_UDIR
@give:  jsr InfoKind
        jmp Give
        .assert fePath = fileHeader, error, "OvRoot: the name in fePath"

Tops:   .byte "usb0", 0, "usb1", 0, "sd", 0
TopAt:  .byte 1, 6, 11, 0       ; (each name's place in Tops, plus one)

        .endscope

        .segment "OVL41"
        .scope Mod41

        jmp OvUFile             ; entry 0
        jmp UCdAll              ; entry 3 (FE_CD: into the whole path)

        .include "feult.inc"
        .include "fecd.inc"

; OvUFile: FE_DELETE, FE_MKDIR, FE_RMDIR or FE_RENAME (feFunc) on an
; Ultimate path (module 27's Target sends them here); the arguments as
; there. X = 0 or the error.
OvUFile:
        ldx #FE_BAD_PATH        ; a name in a folder, not a top
        lda feName
        beq @end
        jsr UCd
        txa
        bne @end
        lda feFunc
        cmp #FE_DELETE
        beq Delete
        cmp #FE_MKDIR
        beq MkDir
        cmp #FE_RMDIR
        beq RmDir
        jmp Rename
@end:   rts

; Delete: a file (a folder: FE_IS_FOLDER).
Delete: jsr IsDir
        bcs @file
        ldx #FE_IS_FOLDER
        rts
@file:  jsr UCd                 ; (back)
Del:    lda #U_DELETE
        jsr UBegin
        jsr UPutName
        jsr UNoData
        jmp UExec

; MkDir: a new folder (r2L, the tracks of a 1581 partition, unused).
MkDir:  lda #U_MKDIR
        jsr UBegin
        jsr UPutName
        jsr UNoData
        jmp UExec

; RmDir: an empty folder (a file: FE_NOT_FOLDER; entries: DIR_NOT_EMPTY).
RmDir:  jsr IsDir
        bcc @dir
        txa
        bne @end                ; (neither: FILE_NOT_FOUND)
        ldx #FE_NOT_FOLDER
@end:   rts
@dir:   lda #U_OPENDIR          ; "01,DIRECTORY EMPTY"?
        jsr UBegin
        jsr UExec
        txa
        bne @end
        ldx #DIR_NOT_EMPTY
        lda uStat+1
        cmp #'1'
        bne @end
        jsr UCd                 ; (back)
        jmp Del

; Rename: to the name at the caller's r1 (no "/", at least 1 character;
; the old and the new name together within one command, U_CMD_MAX; an
; existing one: FILE_EXISTS).
Rename: lda #U_RENAME
        jsr UBegin
        jsr UPutName
        lda #0
        jsr UPut
        lda argR1
        sta r1L
        lda argR1+1
        sta r1H
        ldy #0
@ch:    lda (r1),y
        beq @got
        cmp #'/'
        beq @bad
        sty feM
        jsr UPut
        ldy feM
        iny
        lda uLen                ; (both names in one command)
        cmp #U_CMD_MAX
        bcc @ch
@bad:   ldx #FE_BAD_PATH
        rts
@got:   tya
        beq @bad
        jsr UNoData
        jmp UExec

; IsDir: C clear when the last part is a folder (entered then): not a
; file that opens, as a disk image does (the firmware also enters disk
; images with CD, as folders), and entered by CD. C set: a file (X = 0)
; or neither (X = the CD's error).
IsDir:  lda #U_OPEN
        jsr UBegin
        lda #UO_READ
        jsr UPut
        jsr UPutName
        jsr UNoData
        jsr UExec
        txa
        bne @cd
        lda #U_CLOSE
        jsr UBegin
        jsr UExec
        ldx #0
        sec
        rts
@cd:    lda #U_CD
        jsr UBegin
        jsr UPutName
        jsr UNoData
        jsr UExec
        cpx #1                  ; (X = 0: C clear)
        rts

        .endscope

        .segment "OVL47"
        .scope Mod47

        jmp OvList              ; entry 0

UCI_STAT_MAX    = U_STAT_MAX
cmdBuf          = uCmd
cmdLen          = uLen
statBuf         = uStat
dataEnd         = uEnd
        .include "uci.inc"

; OvList: READ_DIR (after OPEN_DIR), one packet per entry (the attribute
; byte, the name), each into its slot of REU bank FE_UBANK + feHandle (to
; FE_USLOTS; a longer name cut to FE_USLOT - 2); feH's H_UCOUNT the
; number, H_UNEXT 0. I/O on meanwhile. Destroys A, X, Y, r0-r3L.
OvList: lda #0
        sta feH + H_UCOUNT
        sta feH + H_UCOUNT+1
        sta feH + H_UNEXT
        sta feH + H_UNEXT+1
        lda #U_TARGET
        sta uCmd
        lda #U_READDIR
        sta uCmd+1
        lda #2
        sta uLen
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        jsr UciSend
@packet:
        lda #<diskBlkBuf
        sta r0L
        sta uEnd
        lda #>diskBlkBuf
        sta r0H
        sta uEnd+1
        lda #FE_USLOT - 1
        sta uEnd
        jsr UciData
        lda r0L                 ; (diskBlkBuf: r0L the length)
        beq @next
        lda #0
        tay
        sta (r0),y
        jsr Slot
@next:  lda uciCtrl             ; "data more": the next after an ack
        and #$30
        cmp #$30
        bne @last
        jsr UciAccept
        jmp @packet
@last:  jsr UciStatus
        jsr UciAccept
        pla
        sta CPU_PORT
        rts
        .assert <diskBlkBuf = 0, error, "Read: the length from r0L"

; Slot: diskBlkBuf (FE_USLOT bytes) into the next slot, if there is one.
; Destroys A, X, Y, r0-r3L.
Slot:   lda feH + H_UCOUNT+1
        cmp #>FE_USLOTS
        bcs @full
        lda feH + H_UCOUNT      ; slot * FE_USLOT
        sta r1L
        lda feH + H_UCOUNT+1
        sta r1H
        ldx #6
@mul:   asl r1L
        rol r1H
        dex
        bne @mul
        lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #FE_USLOT
        sta r2L
        lda #0
        sta r2H
        lda feHandle
        clc
        adc #FE_UBANK
        sta r3L
        ldy #REU_STASH
        jsr SysRAMOp
        inc feH + H_UCOUNT
        bne @full
        inc feH + H_UCOUNT+1
@full:  rts
        .assert FE_USLOT = 64, error, "Slot: 64 bytes a slot"

        .endscope
