; Boot mounts through the Ultimate Command Interface (cold start only,
; segment INIT): find the GEOULTRA home folder, read MOUNTS.INI and load
; each listed disk image whole into the REU, then write the mount table
; that DiskInit reads (docs/DESIGN.md, "Mount list", "Drives A-D").
;
; MOUNTS.INI:   [drives]
;               A=/USB0/Geos/GEOS64.D81
;               B=/USB0/Geos/neos-mouse-driver-for-geos.d64
;
; The UCI handshake follows the corrected one in the ultimate-uci-oscar64
; library (ultimate_common_lib.c, uii_sendcommand: wait for idle and
; release an old reply, push, clear an error and push again, wait until
; the command is taken); own code. Without a UCI (VICE) nothing changes:
; the mount table already in the REU stays. When the REU's table shows a
; drive with unsaved changes (a reset), it is kept as well, until the
; write-back exists.
;
; Diagnostics for the hardware loop (C64 RAM, valid until an application
; overwrites it): $4E00 "GUMN", $4E04 home folder status (2 characters),
; $4E10 + 16 * drive: the drive letter, then the status of the open and
; of LOAD_REU (2 characters each), the type and the first bank.

        .include "geos.inc"
        .include "hw.inc"
        .include "drvflags.inc"
        .include "kcalls.inc"

        .export MountAll, SerialFromDisk, TurboInit
        .import turboWant, turboNow
.ifdef BYPASS
        .import bypassOn
.endif
        .import uciPresent, wbPending, serialNumber, hibLimit, SetDevice, FindFile
        .import GetFHdrInfo

UCI_ID          = $C9
TARGET_DOS      = $01
TARGET_CTRL     = $04
DOS_OPEN        = $02
DOS_CLOSE       = $03
DOS_READ        = $04
DOS_WRITE       = $05
DOS_INFO        = $07
DOS_CD          = $11
DOS_MKDIR       = $16
DOS_LOAD_REU    = $21

TEXT            = $4000         ; MOUNTS.INI (up to TEXT_MAX bytes)
TEXT_MAX        = $0C00
SCRATCH         = $4C00         ; data replies we do not need
TABLE           = $4D00         ; the mount table being built ($A0 bytes)
LOG             = $4E00
FIRST_BANK      = 31            ; drives: REU banks 31-187
LAST_BANK       = 187           ; (188-191: the file engine's listings,
                                ; engine.inc FE_UBANK)
SYS_BANK        = 1

        .segment "INIT"

cmdBuf:         .res 112        ; (ApplyCfg: 4 + 93 bytes)
cmdLen:         .byte 0
dataEnd:        .word 0         ; UciData: the first address it may not write
statBuf:        .res 32
path:           .res 64
pathLen:        .byte 0
slashPos:       .byte 0
drive:          .byte 0
nextBank:       .byte 0
inDrives:       .byte 0
type:           .byte 0
banks:          .byte 0
tracks:         .byte 0
textEnd:        .word 0
serialSet:      .byte 0         ; SETTINGS.INI gave serial=
walk:           .byte 0
sdDrive:        .byte 0

; MountAll (cold start, I/O on). Destroys A, X, Y, r0-r3.
MountAll:
        lda uciCmd
        cmp #UCI_ID
        beq @uci
        lda #$AB                ; firmware 3.15: map the interface
        sta $D038               ; (only when it is not mapped yet)
        lda #$CD
        sta $D036
        ldy #100                ; and wait for it, up to about 2 s (as the
@wait:  lda uciCmd              ; Ultimate library's uii_wait_for_uci; one
        cmp #UCI_ID             ; check right after the unlock found no
        beq @uci                ; interface on the U64 once, 2026-11-04)
@frame: lda $D012
        cmp #248
        bne @frame
@past:  lda $D012
        cmp #248
        beq @past
        dey
        bne @wait
        rts
@uci:   lda #$04                ; abort whatever an earlier run left
        sta uciCtrl
        lda #1                  ; the write-back can run
        sta uciPresent
        lda #'G'
        sta LOG
        lda #'U'
        sta LOG+1
        lda #'M'
        sta LOG+2
        lda #'N'
        sta LOG+3
        jsr FindHome            ; always: the write-back needs the home path
        bcs @end
        jsr ReadSettings        ; (in the home folder)
        jsr KeepDirty
        bcs @kept
        jsr ReadList
        bcs @end
        jsr ClearTable
        jsr ParseList
        jsr StoreTable
@end:   rts
@kept:  lda #1                  ; write the kept changes back soon
        sta wbPending
        rts

; --- The REU mount table --------------------------------------------------

; KeepDirty: C set when the REU's table is valid and a drive has unsaved
; changes (then it is kept). Valid: signature, version 1, each entry a
; known type with a bank in the drive range or empty, no unknown flags.
; The U64 keeps the REU on the board: after a short power-off the old
; table was found with the signature intact and noise elsewhere, one
; noise bit as "unsaved changes", and kept on every boot (no drives).
KeepDirty:
        ldy #REU_FETCH
        jsr TableDma
        ldx #3
@sig:   lda TABLE,x
        cmp mountSig,x
        bne @no
        dex
        bpl @sig
        lda TABLE+4
        cmp #1
        bne @no
        ldy #0                  ; drives with changes
        ldx #0
@entry: lda TABLE+$23,x         ; flags
        and #$FF ^ F_KNOWN      ; (F_BACKUP was missing until 2026-11-04:
                                ; a written drive's unsaved changes were
                                ; dropped at the next reset)
        bne @no
        lda TABLE+$20,x         ; type
        bne @used
        lda TABLE+$23,x         ; an empty entry has no flags
        bne @no
        beq @next
@used:  cmp #DRV_NATIVE + 1
        bcs @no
        lda TABLE+$21,x         ; first bank
        cmp #FIRST_BANK
        bcc @no
        cmp #LAST_BANK + 1
        bcs @no
        lda TABLE+$23,x
        and #F_DIRTY
        beq @next
        iny
@next:  txa
        clc
        adc #32
        tax
        cpx #$80
        bne @entry
        tya
        beq @no
        sec
        rts
@no:    clc
        rts

; ClearTable: signature, version, no drives; the paths in REU
; $01:0200-$02FF zeroed too (unused slots keep nothing from before: the
; U64's REU holds noise after a power-off, which made a hibernated
; session's mounts look different from the same mounts after the boot).
ClearTable:
        ldx #0
        txa
@clear: sta SCRATCH,x
        cpx #$A0
        bcs @rest
        sta TABLE,x
@rest:  inx
        bne @clear
        lda #<SCRATCH           ; 256 zeros to the paths
        sta reuC64
        lda #>SCRATCH
        sta reuC64+1
        lda #0
        sta reuAddr
        sta reuLen
        sta reuCtrl
        lda #2
        sta reuAddr+1
        lda #SYS_BANK
        sta reuAddr+2
        lda #1
        sta reuLen+1
        lda #REU_STASH
        sta reuCmd
        ldx #3
@sig:   lda mountSig,x
        sta TABLE,x
        dex
        bpl @sig
        lda #1
        sta TABLE+4
        lda #FIRST_BANK
        sta nextBank
        rts

StoreTable:
        ldy #REU_STASH

; TableDma: Y = REU command; TABLE <-> REU $01:0100, $A0 bytes.
TableDma:
        lda #<TABLE
        sta reuC64
        lda #>TABLE
        sta reuC64+1
        lda #$00
        sta reuAddr
        lda #$01
        sta reuAddr+1
        lda #SYS_BANK
        sta reuAddr+2
        lda #$A0
        sta reuLen
        lda #0
        sta reuLen+1
        sta reuCtrl
        sty reuCmd
        rts

mountSig:       .byte "GUMT"
HOME_TRIES      = 40            ; FindHome: 10 s for the devices to appear
homeTries:      .byte 0

; --- Home folder ------------------------------------------------------------

; FindHome: the current directory becomes the GEOULTRA folder on /USB0,
; /USB1 or /SD (the first found); without one it is created, with an
; empty MOUNTS.INI, on the first of them present. C set when neither.
; At power-on the Ultimate's USB stick appears seconds after the C64
; starts (tested on the U64: the SD card was there, /USB0 not yet, and a
; second, empty home was made on SD), so the search is repeated for up to
; HOME_TRIES quarter seconds before one is created.
FindHome:
        lda #HOME_TRIES
        sta homeTries
@round: ldx #0
@try:   stx drive
        jsr HomePath            ; "/USB0/GEOULTRA" etc.
        jsr ChangeDir
        php
        jsr LogHome
        plp
        beq @found
        ldx drive
        inx
        cpx #3
        bne @try
        dec homeTries
        beq @none
        ldy #12                 ; about a quarter second (raster line
@frame: lda $D012               ; 248 comes once a frame)
        cmp #248
        bne @frame
@past:  lda $D012
        cmp #248
        beq @past
        dey
        bne @frame
        beq @round
@none:  ldx #0                  ; none: create on the first device present
@make:  stx drive
        jsr DevicePath          ; "/USB0/" etc.
        jsr ChangeDir
        beq @create
        ldx drive
        inx
        cpx #3
        bne @make
        sec
        rts
@create:
        ldy #0
@name:  lda homeName,y
        sta path,y
        beq @named
        iny
        bne @name
@named: sty pathLen
        lda #DOS_MKDIR
        jsr PathCmd
        jsr ChangeDirName
        bne @fail
        jsr NewList
@found: jsr StashHome
        clc
        rts
@fail:  sec
        rts

; HomePath / DevicePath: X = 0-2 -> path = "/USB0/GEOULTRA" or "/USB0/".
HomePath:
        jsr DevicePath
        ldy #0
@add:   lda homeName,y
        sta path,x
        beq @end
        inx
        iny
        bne @add
@end:   stx pathLen
        rts
DevicePath:
        lda devOffset,x
        tay
        ldx #0
@copy:  lda devices,y
        beq @end
        sta path,x
        inx
        iny
        bne @copy
@end:   lda #0
        sta path,x
        stx pathLen
        rts

devOffset:      .byte 0, 7, 14
devices:        .byte "/USB0/", 0, "/USB1/", 0, "/SD/", 0, 0, 0
homeName:       .byte "GEOULTRA", 0
listName:       .byte "MOUNTS.INI", 0
newList:        .byte "[drives]", 13, 10
NEW_LIST_LEN    = * - newList

LogHome:
        lda statBuf
        sta LOG+4
        lda statBuf+1
        sta LOG+5
        rts

; ChangeDir: to path. Z set when it worked.
ChangeDirName:
ChangeDir:
        lda #DOS_CD
        jmp PathCmd

; NewList: an empty MOUNTS.INI in the current directory.
NewList:
        jsr ListName
        lda #$06                ; create new, write
        jsr OpenFile
        bne @end
        lda #TARGET_DOS
        sta cmdBuf
        lda #DOS_WRITE
        sta cmdBuf+1
        lda #0
        sta cmdBuf+2
        sta cmdBuf+3
        ldx #0
@copy:  lda newList,x
        sta cmdBuf+4,x
        inx
        cpx #NEW_LIST_LEN
        bne @copy
        lda #NEW_LIST_LEN + 4
        sta cmdLen
        jsr Simple
        jsr CloseFile
@end:   rts

ListName:
        ldy #0
@copy:  lda listName,y
        sta path,y
        beq @end
        iny
        bne @copy
@end:   sty pathLen
        rts

; --- MOUNTS.INI -------------------------------------------------------------

; ReadSettings: SETTINGS.INI from the home folder; [system] serial=XXXX
; (hex) sets the serial number. Missing file or key: nothing changes.
ReadSettings:
        ldy #0
@name:  lda settingsName,y
        sta path,y
        beq @named
        iny
        bne @name
@named: sty pathLen
        jsr ReadText
        bcc :+
        rts
:
        lda #<TEXT
        sta r1L
        lda #>TEXT
        sta r1H
        lda #0
        sta inDrives            ; here: inside [system]
@line:  jsr AtEnd
        bcc :+
        rts
:
        jsr GetChar
        cmp #'['
        bne :+
        jmp @section
:
        cmp #13                 ; (SkipLine stops at CR: LF still to come)
        beq @line
        cmp #10
        beq @line
        ldx inDrives
        bne :+
        jmp @skip
:
        and #$DF
.ifdef BYPASS
        cmp #'P'
        bne @serial
        ldx #protKey - keys     ; "ROTECTION=BYPASS"
        jsr Match
        beq :+
        jmp @skip
:
        lda #$80
        sta bypassOn
        jmp @skip
@serial:
.endif
        cmp #'H'
        bne @serial2
        ldx #hibKey - keys      ; "IBERNATE=" seconds after a change (0:
        jsr Match               ; off), in steps of 256 frames (about 5 s)
        beq :+
        jmp @skip
:
        jsr Decimal
        ldx #0
@five:  cmp #5
        bcc @round
        sbc #5
        inx
        bne @five
@round: cmp #3                  ; (rounded)
        bcc @limit
        inx
@limit: stx hibLimit
        jmp @skip
@serial2:
        cmp #'T'
        bne @serial3
        ldx #turboKey - keys    ; "URBO=OFF"
        jsr Match
        bne @skip0
        lda #$80
        sta turboOff
@skip0: jmp @skip
@serial3:
        cmp #'S'
        bne @skip0
        lda r1L                 ; (Match reads on: back for the second key)
        pha
        lda r1H
        pha
        ldx #serialKey - keys   ; "ERIAL="
        jsr Match
        beq @isSerial
        pla
        sta r1H
        pla
        sta r1L
        ldx #slowKey - keys     ; "LOW=" a permanent name for 1 MHz
        jsr Match
        bne @skip0
        jsr SlowName
        jmp @skip
@isSerial:
        pla
        pla
        jsr Hex2                ; four hex digits, high byte first
        bcs @skip
        sta serialNumber+1
        jsr Hex2
        bcs @skip
        sta serialNumber
        lda #1
        sta serialSet
        jmp @skip
@section:
        ldx #systemKey - keys
        jsr Match
        php
        lda #0
        plp
        bne @set                ; (Match: Z set when equal)
        lda #1
@set:   sta inDrives
@skip:  jsr SkipLine
        jmp @line
@end:   rts

settingsName:   .byte "SETTINGS.INI", 0
keys:
systemKey:      .byte "SYSTEM]", 0
serialKey:      .byte "ERIAL=", 0
hibKey:         .byte "IBERNATE=", 0
turboKey:       .byte "URBO=OFF", 0
slowKey:        .byte "LOW=", 0
.ifdef BYPASS
protKey:        .byte "ROTECTION=BYPASS", 0
.endif

; Decimal: A = the decimal number that follows (up to 255; stops at the
; first other character).
Decimal:
        lda #0
        sta r2L
@digit: jsr AtEnd
        bcs @end
        ldy #0
        lda (r1),y
        sec
        sbc #'0'
        cmp #10
        bcs @end
        pha
        jsr GetChar
        lda r2L                 ; r2L = r2L * 10 + digit
        asl
        asl
        clc
        adc r2L
        asl
        sta r2L
        pla
        clc
        adc r2L
        sta r2L
        jmp @digit
@end:   lda r2L
        rts

; Match: the next characters (upper case) against keys + X up to its 0.
; Z set when they match (C clear).
Match:  lda keys,x
        beq @yes
        jsr GetChar
        cmp #'a'
        bcc @cmp
        and #$DF
@cmp:   cmp keys,x
        bne @no
        inx
        bne Match
@yes:   clc
        lda #0
        rts
@no:    clc
        lda #1
        rts

; Hex2: two hex digits -> A. C set when not hex.
Hex2:   jsr Nibble
        bcs @end
        asl
        asl
        asl
        asl
        sta r2L
        jsr Nibble
        bcs @end
        ora r2L
@end:   rts
Nibble: jsr GetChar
        cmp #'a'
        bcc @upper
        and #$DF
@upper: sec
        sbc #'0'
        cmp #10
        bcc @ok
        sbc #'A' - '0' - 10
        cmp #10
        bcc @bad
        cmp #16
        bcs @bad
@ok:    clc
        rts
@bad:   sec
        rts

; ReadList: the file into TEXT; textEnd past its end. C set on failure.
ReadList:
        jsr ListName
ReadText:
        lda #$01
        jsr OpenFile
        bne @fail
        lda #TARGET_DOS
        sta cmdBuf
        lda #DOS_READ
        sta cmdBuf+1
        lda #<TEXT_MAX
        sta cmdBuf+2
        lda #>TEXT_MAX
        sta cmdBuf+3
        lda #4
        sta cmdLen
        jsr UciSend
        lda #<TEXT
        sta r0L
        lda #>TEXT
        sta r0H
        lda #<(TEXT + TEXT_MAX)
        sta dataEnd
        lda #>(TEXT + TEXT_MAX)
        sta dataEnd+1
@packet:
        jsr UciData
        lda uciCtrl             ; "data more": the next packet after an ack
        and #$30
        cmp #$30
        bne @last
        jsr UciAccept
        jmp @packet
@last:  lda r0L
        sta textEnd
        lda r0H
        sta textEnd+1
        jsr UciStatus
        jsr UciAccept
        jsr CloseFile
        clc
        rts
@fail:  sec
        rts

; ParseList: every A= .. D= line of [drives] mounted.
ParseList:
        lda #<TEXT
        sta r1L
        lda #>TEXT
        sta r1H
        lda #0
        sta inDrives
@line:  jsr AtEnd
        bcs @end
        jsr GetChar
        cmp #'['
        beq @section
        cmp #13
        beq @line
        cmp #10
        beq @line
        ldx inDrives
        beq @skip
        and #$DF                ; upper case
        sec
        sbc #'A'
        cmp #4
        bcs @skip
        sta drive
        jsr GetChar
        cmp #'='
        bne @skip
        jsr ReadPath
        jsr SizeOption          ; ",tracks=N" after a DNP's path
        jsr Mount
        jmp @line
@section:
        ldx #0                  ; "[drives]"? (any case)
@cmp:   jsr GetChar
        cmp #'a'
        bcc @upper
        and #$DF
@upper: cmp drivesName,x
        bne @other
        inx
        cpx #DRIVES_LEN
        bne @cmp
        lda #1
        sta inDrives
        bne @skip
@other: lda #0
        sta inDrives
@skip:  jsr SkipLine
        jmp @line
@end:   rts

drivesName:     .byte "DRIVES]"
DRIVES_LEN      = * - drivesName

; AtEnd: C set when r1 has reached textEnd.
AtEnd:  lda r1H
        cmp textEnd+1
        bne @cmp
        lda r1L
        cmp textEnd
@cmp:   rts

; GetChar: A = (r1), r1 + 1 (0 at the end).
GetChar:
        jsr AtEnd
        lda #0
        bcs @end
        ldy #0
        lda (r1),y
        inc r1L
        bne @end
        inc r1H
@end:   rts

SkipLine:
@next:  jsr AtEnd
        bcs @end
        jsr GetChar
        cmp #13
        beq @end
        cmp #10
        bne @next
@end:   rts

; ReadPath: path = the rest of the line (spaces at the end dropped);
; slashPos = after its last "/".
ReadPath:
        ldx #0
        stx slashPos
@char:  jsr AtEnd
        bcs @end
        jsr GetChar
        cmp #13
        beq @end
        cmp #10
        beq @end
        cpx #63
        bcs @char
        sta path,x
        inx
        cmp #'/'
        bne @char
        stx slashPos
        jmp @char
@end:   dex                     ; trailing spaces
        bmi @empty
        lda path,x
        cmp #' '
        beq @end
@empty: inx
        lda #0
        sta path,x
        stx pathLen
        rts

; --- One drive ----------------------------------------------------------------

; Mount: drive (0-3) from path. Logs to LOG + 16 * drive.
Mount:  lda drive
        asl
        asl
        asl
        asl
        tax
        lda drive
        clc
        adc #'A'
        sta LOG+$10,x
        jsr ImageType           ; by the extension
        bcs @end
        jsr StashPath           ; the whole path, for the write-back
        ldx slashPos            ; the folder: path up to the last "/"
        beq @file
        lda path,x
        pha
        lda #0
        sta path,x
        stx pathLen
        jsr ChangeDir
        pla
        ldx slashPos
        sta path,x
@file:  ldx slashPos            ; the file name: the rest
        ldy #0
@name:  lda path,x
        sta path,y
        beq @named
        inx
        iny
        bne @name
@named: sty pathLen
        lda #$01
        jsr OpenFile
        php
        ldy #1
        jsr LogStatus
        plp
        bne @end
        jsr ImageSize           ; banks, tracks (native: FILE_INFO)
        jsr ResizeFirst         ; another size wanted: what to load
        lda nextBank            ; room left?
        clc
        adc banks
        bcs @close
        cmp #LAST_BANK + 2
        bcs @close
        jsr LoadReu
        php
        ldy #3
        jsr LogStatus
        plp
        bne @close
        jsr ResizeThen          ; the BAM to the wanted size (C: refused)
        bcs @close
        jsr Enter               ; the mount table entry
        jsr ClearMap
        lda nextBank
        clc
        adc banks
        sta nextBank
@close: jsr CloseFile
@end:   rts

; --- A native drive of another size than its DNP (docs/DESIGN.md "DNP
; of another size than the drive", user 2026-11-04) ---------------------

; SizeOption (after ReadPath): ",tracks=N" at the end of the path gives
; wantTracks = N (0: none); the path ends before the comma.
SizeOption:
        lda #0
        sta wantTracks
        ldx #0
@find:  lda path,x
        beq @end
        cmp #','
        beq @comma
        inx
        bne @find
@end:   rts
@comma: lda #0
        sta path,x
        stx pathLen
@eq:    inx
        lda path,x
        beq @end
        cmp #'='
        bne @eq
@digit: inx
        lda path,x
        sec
        sbc #'0'
        cmp #10
        bcs @end
        sta r2H
        lda wantTracks          ; wantTracks * 10 + digit
        cmp #26
        bcs @big
        asl
        asl
        clc
        adc wantTracks
        asl
        clc
        adc r2H
        bcs @big
        sta wantTracks
        jmp @digit
@big:   lda #0                  ; (more than 255 tracks, the native most:
        sta wantTracks          ; no resize)
        rts

MIN_TRACKS      = 2             ; native: track 1 holds header, BAM and
                                ; directory start; at least one track more

; ResizeFirst (after ImageSize): with a wanted size for a native image,
; the drive gets that many banks; a smaller drive loads only its tracks.
ResizeFirst:
        lda #0
        sta resized
        lda tracks
        sta fileTracks
        lda type
        cmp #DRV_NATIVE
        bne @end
        lda wantTracks
        cmp #MIN_TRACKS
        bcc @end                ; (none, or too small for a native disk)
        cmp tracks
        beq @end                ; (the same size: nothing to do)
        sta banks
        bcs @end                ; larger: the whole file is loaded
        sta tracks              ; smaller: only the first wantTracks
@end:   rts

; ResizeThen (after LoadReu, drive at nextBank): smaller: refused (C set)
; when the BAM shows a used block after the last track; larger: the new
; tracks' blocks set free. Then the BAM's last track (1/2 $08) = the
; size, the drive F_RESIZED. C clear when the drive can be mounted.
ResizeThen:
        lda banks
        cmp fileTracks
        beq @out                ; (no resize, or the same size)
        lda type
        cmp #DRV_NATIVE
        beq @go
@out:   clc
        rts
@go:    lda banks
        cmp fileTracks
        bcs @grow
        tax                     ; smaller: tracks banks+1 .. fileTracks
@check: inx                     ; must be free
        txa
        pha
        ldy #REU_FETCH
        jsr BamDma
        pla
        tax
        ldy #31
@free:  lda SCRATCH,y
        cmp #$FF
        bne @used
        dey
        bpl @free
        cpx fileTracks
        bne @check
        beq @size
@used:  sec                     ; files after the last track: not mounted
        rts
@grow:  ldy #31                 ; larger: tracks fileTracks+1 .. banks free
        lda #$FF
@ff:    sta SCRATCH,y
        dey
        bpl @ff
        ldx fileTracks
@new:   inx
        txa
        pha
        ldy #REU_STASH
        jsr BamDma
        pla
        tax
        cpx banks
        bne @new
@size:  lda banks               ; the BAM's last track, in the REU
        sta tracks
        sta wantTracks
        lda #<wantTracks
        sta reuC64
        lda #>wantTracks
        sta reuC64+1
        lda #$08
        sta reuAddr
        lda #$02
        sta reuAddr+1
        lda #1
        sta reuLen
        lda #0
        sta reuLen+1
        lda nextBank
        sta reuAddr+2
        lda #0
        sta reuCtrl
        lda #REU_STASH
        sta reuCmd
        lda #F_RESIZED
        sta resized
@done:  clc
        rts

; BamDma: A = track, Y = REU command: its 32 BAM bytes (from 1/2: offset
; $0200 + track * 32 in the drive's first bank) <-> SCRATCH.
BamDma: pha
        asl
        asl
        asl
        asl
        asl
        sta reuAddr
        pla
        lsr
        lsr
        lsr
        clc
        adc #$02
        sta reuAddr+1
        lda nextBank
        sta reuAddr+2
        lda #<SCRATCH
        sta reuC64
        lda #>SCRATCH
        sta reuC64+1
        lda #32
        sta reuLen
        lda #0
        sta reuLen+1
        sta reuCtrl
        sty reuCmd
        rts

wantTracks:     .byte 0         ; MOUNTS.INI ",tracks=N" (0: the file's)
fileTracks:     .byte 0         ; the DNP's own track count
resized:        .byte 0         ; F_RESIZED for the mount table, or 0

; LogStatus: the status's two characters to LOG + 16 * drive + Y.
LogStatus:
        lda drive
        asl
        asl
        asl
        asl
        sta r3L
        tya
        clc
        adc r3L
        tax
        lda statBuf
        sta LOG+$10,x
        lda statBuf+1
        sta LOG+$11,x
        rts

; ImageType: type from the extension of path (D64 1541, D71 1571, D81
; 1581, DNP native). C set for anything else (G64 later).
ImageType:
        ldx pathLen
        cpx #4
        bcc @no
        lda path-4,x
        cmp #'.'
        bne @no
        lda path-3,x
        and #$DF
        cmp #'D'
        bne @no
        lda path-2,x
        and #$DF
        cmp #'N'
        beq @native
        lda path-2,x
        cmp #'6'
        bne @d7
        lda path-1,x
        cmp #'4'
        bne @no
        lda #DRV_1541
        bne @set
@d7:    cmp #'7'
        bne @d8
        lda path-1,x
        cmp #'1'
        bne @no
        lda #DRV_1571
        bne @set
@d8:    cmp #'8'
        bne @no
        lda path-1,x
        cmp #'1'
        bne @no
        lda #DRV_1581
        bne @set
@native:
        lda path-1,x
        and #$DF
        cmp #'P'
        bne @no
        lda #DRV_NATIVE
@set:   sta type
        clc
        rts
@no:    sec
        rts

; ImageSize: banks (64 KB each) and tracks for the type; a native image
; has as many tracks as 64 KB in the file (FILE_INFO).
ImageSize:
        lda #0
        sta tracks
        ldx type
        lda typeBanks,x
        sta banks
        cpx #DRV_NATIVE
        bne @end
        lda #TARGET_DOS
        sta cmdBuf
        lda #DOS_INFO
        sta cmdBuf+1
        lda #2
        sta cmdLen
        jsr Simple              ; the size in SCRATCH (LSB first)
        lda SCRATCH+2
        sta tracks
        sta banks
@end:   rts

typeBanks:      .byte 0, 3, 6, 13, 0
typeSize:       .faraddr 0, 683 * 256, 1366 * 256, 3200 * 256, 0

; LoadReu: the open file to bank nextBank (its whole length: the type's
; size, a native image tracks * 64 KB). Z set when it worked.
LoadReu:
        lda #TARGET_DOS
        sta cmdBuf
        lda #DOS_LOAD_REU
        sta cmdBuf+1
        lda #0
        sta cmdBuf+2
        sta cmdBuf+3
        sta cmdBuf+5
        sta cmdBuf+9
        lda nextBank
        sta cmdBuf+4
        lda type
        cmp #DRV_NATIVE
        bne @fixed
        lda #0
        sta cmdBuf+6
        sta cmdBuf+7
        lda tracks
        sta cmdBuf+8
        jmp @send
@fixed: asl                     ; 3 bytes per typeSize entry
        adc type
        tax
        lda typeSize,x
        sta cmdBuf+6
        lda typeSize+1,x
        sta cmdBuf+7
        lda typeSize+2,x
        sta cmdBuf+8
@send:  lda #10
        sta cmdLen
        jmp Simple

; Enter: the mount table entry (the image's path for the write-back
; follows with the write-back).
Enter:  lda drive
        asl
        asl
        asl
        asl
        asl
        tax
        lda type
        sta TABLE+$20,x
        lda nextBank
        sta TABLE+$21,x
        lda tracks
        sta TABLE+$22,x
        lda resized             ; F_RESIZED or 0
        sta TABLE+$23,x
        lda drive               ; the log: type and bank
        asl
        asl
        asl
        asl
        tax
        lda type
        sta LOG+$15,x
        lda nextBank
        sta LOG+$16,x
        rts

; StashHome: the home folder's path with a trailing "/" ("/USB0/GEOULTRA/",
; device in drive) to REU $01:0300, for the write-back's backups.
StashHome:
        ldx drive
        jsr HomePath
        lda #'/'
        sta path,x
        lda #0
        sta path+1,x
        lda #0
        sta reuAddr
        lda #$03
        sta reuAddr+1
        jmp StashAt

; StashPath: path (64 bytes) to REU $01:0200 + 64 * drive.
StashPath:
        lda drive               ; 64 * drive (at most 192)
        asl
        asl
        asl
        asl
        asl
        asl
        sta reuAddr
        lda #$02
        sta reuAddr+1
StashAt:
        lda #<path
        sta reuC64
        lda #>path
        sta reuC64+1
        lda #64
        sta reuLen
        lda #0
        sta reuLen+1
        sta reuCtrl
        lda #SYS_BANK
        sta reuAddr+2
        lda #REU_STASH
        sta reuCmd
        rts

; ClearMap: the drive's dirty map ($01:2000 + $2000 * drive) to zeros.
ClearMap:
        lda #<zero
        sta reuC64
        lda #>zero
        sta reuC64+1
        lda #0
        sta reuAddr
        sta reuLen
        lda drive
        asl
        asl
        asl
        asl
        asl
        clc
        adc #$20
        sta reuAddr+1
        lda #SYS_BANK
        sta reuAddr+2
        lda #$20
        sta reuLen+1
        lda #$80                ; the same C64 byte for every REU byte
        sta reuCtrl
        lda #REU_STASH
        sta reuCmd
        lda #0
        sta reuCtrl
        rts

zero:   .byte 0

; --- Turbo -----------------------------------------------------------------

; TurboInit (cold start, after MountAll, I/O on): the U64's turbo
; registers at full speed ($D031 = 15, badline stalls off; docs/DESIGN.md
; "Ultimate settings"). Without them ($D031 reads $FF: the firmware's
; Turbo Control is not "U64 Turbo Registers", as when the cartridge was
; not started with geoultra64.cfg) the setting is applied through the UCI
; first: only that line, written to /Temp/uci_config.cfg and loaded with
; control command $50 (REU and Command Interface are on already, and
; applying REU settings again might clear the REU). The ApplyCfg pattern
; (file in /Temp, control $50, status "89" fine) is from the author's
; u64-bbcbasic (src/mos/ultctl.s, uc_apply). No turbo on an Ultimate II+
; or a C128 ($D031 stays $FF there, so $D030 is not touched).
TurboInit:
        jsr SlowList            ; the 1 MHz list to the REU (speed.s)
        bit turboOff            ; SETTINGS.INI [system] turbo=off
        bmi @end
        lda $D031
        cmp #$FF
        bne @on
        lda uciPresent
        beq @end
        jsr ApplyCfg
        lda $D031
        cmp #$FF
        beq @end
@on:    lda $D030
        ora #$01
        sta $D030
        lda #TURBO_FULL
        sta $D031
        sta turboWant           ; (speed.s sets it per application)
        sta turboNow
@end:   rts

; SlowName (ReadSettings, r1 after "slow="): the rest of the line, up to
; SLOW_NAME characters, as the next name of the 1 MHz list.
SlowName:
        lda slowCount
        cmp #SLOW_MAX
        bcs @end
        ldx #0                  ; X: the name's first byte in slowList
        tay
        beq @at
@mul:   txa
        clc
        adc #SLOW_NAME
        tax
        dey
        bne @mul
@at:    ldy #SLOW_NAME
@char:  jsr AtEnd
        bcs @done
        sty r2H
        ldy #0
        lda (r1),y
        ldy r2H
        cmp #13
        beq @done
        cmp #10
        beq @done
        jsr GetChar
        sta slowList,x
        inx
        dey
        bne @char
@done:  inc slowCount
@end:   rts

; SlowList: slowList to the REU at SLOW_BANK:SLOW_LIST (all of it: unused
; names are 0; bank 3 is not hibernated, so a resumed session gets this
; boot's list).
SlowList:
        lda #<slowList
        sta reuC64
        lda #>slowList
        sta reuC64+1
        lda #<SLOW_LIST
        sta reuAddr
        lda #>SLOW_LIST
        sta reuAddr+1
        lda #SLOW_BANK
        sta reuAddr+2
        lda #SLOW_MAX * SLOW_NAME
        sta reuLen
        lda #0
        sta reuLen+1
        sta reuCtrl
        lda #REU_STASH
        sta reuCmd
        rts

SLOW_LIST       = $FF00
SLOW_MAX        = 6
SLOW_NAME       = 12
slowList:       .res SLOW_MAX * SLOW_NAME
slowCount:      .byte 0
turboOff:       .byte 0

ApplyCfg:
        ldy #0
@name:  lda cfgName,y
        sta path,y
        beq @named
        iny
        bne @name
@named: sty pathLen
        lda #$0A                ; write, create always
        jsr OpenFile
        bne @end
        lda #TARGET_DOS
        sta cmdBuf
        lda #DOS_WRITE
        sta cmdBuf+1
        lda #0
        sta cmdBuf+2
        sta cmdBuf+3
        ldx #0
@copy:  lda cfgText,x
        sta cmdBuf+4,x
        inx
        cpx #CFG_TEXT_LEN
        bne @copy
        lda #CFG_TEXT_LEN + 4
        sta cmdLen
        jsr Simple
        jsr CloseFile
        lda #TARGET_CTRL        ; load the default file /Temp/uci_config.cfg
        sta cmdBuf
        lda #$50
        sta cmdBuf+1
        lda #2                  ; no payload: the firmware's default file
        sta cmdLen
        jsr Simple
        lda statBuf             ; the log: its status ("00", or "89" on a
        sta LOG+6               ; device without some of the items)
        lda statBuf+1
        sta LOG+7
@end:   rts

TURBO_FULL      = $8F           ; speed index 15, badline stalls off
cfgName:        .byte "/Temp/uci_config.cfg", 0
cfgText:        .byte "[U64 Specific Settings]", 10
                .byte "Turbo Control=U64 Turbo Registers", 10
                .byte "Turbo Control=C64U Turbo Registers", 10
CFG_TEXT_LEN    = * - cfgText

; --- File commands ----------------------------------------------------------

; OpenFile: A = attributes, path = the name. Z set when it worked.
OpenFile:
        sta cmdBuf+2
        lda #DOS_OPEN
        ldx #1                  ; one byte before the name
        jmp PathCmdX

CloseFile:
        lda #TARGET_DOS
        sta cmdBuf
        lda #DOS_CLOSE
        sta cmdBuf+1
        lda #2
        sta cmdLen
        jmp Simple

; PathCmd: A = DOS command with path as its argument. Z set on "00".
PathCmd:
        ldx #0
PathCmdX:
        sta cmdBuf+1
        lda #TARGET_DOS
        sta cmdBuf
        ldy #0
@copy:  lda path,y
        beq @end
        sta cmdBuf+2,x
        inx
        iny
        bne @copy
@end:   txa
        clc
        adc #2
        sta cmdLen

; Simple: send, data to SCRATCH, status, accept. Z set on "00".
Simple: lda #<SCRATCH
        sta r0L
        lda #>SCRATCH
        sta r0H
        lda #<(SCRATCH + $100)  ; (one page)
        sta dataEnd
        lda #>(SCRATCH + $100)
        sta dataEnd+1
        jmp UciCommand

; --- UCI ------------------------------------------------------------------------

UCI_STAT_MAX    = 31            ; (statBuf: 32 bytes)
        .include "uci.inc"

; --- Serial number from the user's own GEOS boot disk -------------------------

; SerialFromDisk (cold start, after DiskInit, $01 = $30): when SETTINGS.INI
; gave no serial, the first mounted drive with GEOS 2.0's GEOBOOT
; (permanent name "GeoBoot     V1.0") gives it: file block 82, offset
; 183, as found on the user's GEOS 2.0 disks (D64 and D81). Drive A is
; current and open again afterwards.
SerialFromDisk:
        lda serialSet
        beq @start
        rts
@start:
        ldx #8
@drive: stx sdDrive
        lda driveType-8,x
        beq @skip
        txa
        jsr SetDevice
        jsr OpenDisk
        txa
        bne @skip
        lda #<bootName
        sta r6L
        lda #>bootName
        sta r6H
        jsr FindFile
        txa
        bne @skip
        lda #<dirEntryBuf       ; the header: GEOS 2.0's GEOBOOT?
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr GetFHdrInfo
        txa
        bne @skip
        ldx #15
@perm:  lda fileHeader + O_GHFNAME,x
        cmp bootPerm,x
        bne @skip
        dex
        bpl @perm
        lda #82                 ; r1 = the first data block (GetFHdrInfo)
        sta walk
@block: lda #<diskBlkBuf
        sta r4L
        lda #>diskBlkBuf
        sta r4H
        jsr GetBlock
        txa
        bne @skip
        lda walk
        beq @found
        dec walk
        lda diskBlkBuf
        beq @skip               ; shorter than expected: not this one
        sta r1L
        lda diskBlkBuf+1
        sta r1H
        jmp @block
@found: lda diskBlkBuf+183
        ora diskBlkBuf+184
        beq @skip
        lda diskBlkBuf+183
        sta serialNumber
        lda diskBlkBuf+184
        sta serialNumber+1
        jmp @back
@skip:
@next:  ldx sdDrive
        inx
        cpx #12
        beq @back
        jmp @drive
@back:  lda #8
        jsr SetDevice
        jmp OpenDisk
@end:   rts

bootName:       .byte "GEOBOOT", 0
bootPerm:       .byte "GeoBoot     V1.0"
