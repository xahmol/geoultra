; geoFolder: GeoUltra's desk accessory for folders (docs/DESIGN.md,
; "Directories", "System drive"). One file dialog: the kernal's DBGETFILES
; lists ".." and the folders of the current drive's current folder (a file
; type that no file has, so no files appear); OPEN, RETURN and DEL move
; through them (the kernal does that), DISK goes to the next drive, OK
; leaves: the drive's current folder stays as chosen, and the application
; sees it as the disk at its next OpenDisk. Own code.

DoDlgBox        = $C256         ; GEOS 2.0 jump table
RstrAppl        = $C23E
SetDevice       = $C2B0
OpenDisk        = $C2A1
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

        .segment "CODE"

Start:  lda curDrive
        sta home                ; the application's drive
@show:  lda curDrive            ; "Drive X" in the dialog
        clc
        adc #'A' - 8
        sta driveText + 6
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

dialog: .byte DEF_DB_POS | 1
        .byte DBGETFILES, 4, 4
        .byte OPEN, 17, 8
        .byte DISK, 17, 30
        .byte OK, 17, 52
        .byte DBTXTSTR, 136, 86
        .word driveText
        .byte 0

driveText:      .byte "Drive A", 0
home:           .byte 8
nameBuf:        .res 17
