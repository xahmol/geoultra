; geoFolder: GeoUltra's desk accessory for folders (docs/design/DESIGN.md,
; "Directories", "System drive"). One file dialog: the kernal's DBGETFILES
; lists ".." and the folders of the current drive's current folder (a file
; type that no file has, so no files appear); OPEN, RETURN and DEL move
; through them (the kernal does that), DISK goes to the next drive, OK
; leaves: the drive's current folder stays as chosen, and the application
; sees it as the disk at its next OpenDisk. The gush button starts gush
; (docs/design/GUSH.md) from drive E in the application's place. When the list would be empty
; (a drive without folders, or the root of one with none), it says "No
; folders" above the drive's name (user's question, 2026-11-04). Own code.

DoDlgBox        = $C256         ; GEOS 2.0 jump table
RstrAppl        = $C23E
SetDevice       = $C2B0
OpenDisk        = $C2A1
Get1stDirEntry  = $9030         ; disk driver jump table
GetNxtDirEntry  = $9033
guExtTable      = $C0E4         ; GeoUltra: the extension jump table
r1L             = $04
r1H             = $05
curDrive        = $8489
driveType       = $848E
sysDBData       = $851D
r0L             = $02
r0H             = $03
r5L             = $0C
r5H             = $0D
r7L             = $10
r10L            = $16
r10H            = $17
DEF_DB_POS      = $80
OK              = 1
OPEN            = 5
DISK            = 6
DBTXTSTR        = 11
DBGETFILES      = 16
NO_FILE_TYPE    = $FF           ; no GEOS file has it: only folders listed
DBUSRICON       = 18
FE_RUNSYS       = 22            ; the file engine (docs/design/FILE_ENGINE.md)

        .segment "CODE"

Start:  lda curDrive
        sta home                ; the application's drive
@show:  lda curDrive            ; "Drive X" in the dialog
        clc
        adc #'A' - 8
        sta driveText + 6
        jsr Folders             ; "No folders" or nothing above it
        lda #<nameBuf
        sta r5L
        lda #>nameBuf
        sta r5H
        lda #NO_FILE_TYPE
        sta r7L
        lda #0
        sta r10L
        sta r10H
        lda #<dialog
        sta r0L
        lda #>dialog
        sta r0H
        jsr DoDlgBox
        lda sysDBData
        cmp #DISK
        bne @done
        ldx curDrive            ; the next drive that is there
@next:  inx
        cpx #12
        bcc @have
        ldx #8
@have:  lda driveType-8,x
        beq @next
        txa
        jsr SetDevice
        jsr OpenDisk
        jmp @show
@done:  lda home                ; back on the application's drive
        jsr SetDevice
        jsr OpenDisk
        jmp RstrAppl

; Folders: noteText = "No folders" when the list would be empty, else "".
Folders:
        lda guExtTable          ; GetCurDir (extension table +0): r1 =
        sta @ext+1              ; the current folder, 0/0 on a drive
        lda guExtTable+1        ; without folders, 1/1 at the root
        sta @ext+2
@ext:   jsr $FFFF
        lda r1L
        beq @none               ; (no folders on this kind of drive)
        ldx r1H
        cmp #40                 ; 40/0: a 1581's root
        bne @nat
        cpx #0
        beq @root
@nat:   cmp #1                  ; 1/1: a native root
        bne @some               ; in a folder: ".." is listed
        cpx #1
        bne @some
@root:
        jsr Get1stDirEntry      ; the root: any folder in it?
        txa
        bne @none
@entry: ldy #0
        lda (r5L),y
        and #$07
        cmp #6                  ; CBM type DIR (native folders)
        beq @some
        cmp #5                  ; CBM (1581 partitions)
        beq @some
        jsr GetNxtDirEntry
        txa
        bne @none
        tya
        beq @entry
@none:  lda #<noFolders
        ldx #>noFolders
        bne @set
@some:  lda #<noText
        ldx #>noText
@set:   sta noteWord
        stx noteWord+1
        rts

dialog: .byte DEF_DB_POS | 1
        .byte DBGETFILES, 4, 4
        .byte OPEN, 17, 4
        .byte DISK, 17, 21
        .byte DBUSRICON, 17, 38
        .word gushIcon
        .byte OK, 17, 55
        .byte DBTXTSTR, 136, 79
noteWord:
        .word noText
        .byte DBTXTSTR, 136, 89
        .word driveText
        .byte 0

; The gush button (docs/design/GUSH.md, "Where gush lives"): its picture, (x, y
; from the dialog), width in bytes, height, routine.
gushIcon:
        .word GushIcon
        .byte 0, 0, 6, 16
        .word RunGush

; RunGush: gush started from drive E (the file engine's FE_RUNSYS); it
; replaces the application. Back only when that failed: the dialog stays.
RunGush:
        lda guExtTable          ; FileEngine: the extension table + 30
        clc
        adc #30
        sta @fe+1
        lda guExtTable+1
        adc #0
        sta @fe+2
        lda #<gushName
        sta r0L
        lda #>gushName
        sta r0H
        lda #FE_RUNSYS
@fe:    jsr $FFFF
        rts

gushName:       .byte "gush", 0
        .include "gushicon.inc"

driveText:      .byte "Drive A", 0
noFolders:      .byte "No folders", 0
noText:         .byte 0
home:           .byte 8
nameBuf:        .res 17
