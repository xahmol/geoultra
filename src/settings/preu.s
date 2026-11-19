; GeoUltra Settings: the REU page (overlay 6, ovl.s; docs/design/SETTINGS.md,
; the user's decisions of 2026-11-14): a map of the 16 MB REU as a
; 16 x 16 grid, one 8 x 8 cell per 64 KB bank coloured by its use
; (system, drives A-D, the file engine, the applications' legacy REU,
; free; the legacy banks not in use hatched), a legend beside it, and
; steppers below: the legacy REU each task's applications see
; (SETTINGS.INI [system] legacy=512, 1024, 2048 or 4096 KB; the kernal's
; mount.s reads it at the next start) and the task slots (tasks=1-8),
; kept within today's 4 MB legacy area (banks 192-255): size x slots at
; most 64 banks; and the print spooler's queue (spool=128, 256, 512,
; 1024 or 2048 KB: banks 27-28 and the rest at the top of the drives'
; area, the kernal's spool.s; the user, 2026-11-15). Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ButtonDraw, OnButton, IniFind, IniSet, IniDel, dirty, NoRoom
        .import FileEngine, UseSettings
        .importzp vp
        .export Ov_ReuDraw, Ov_ReuPress

GRID_CARD       = PAGE_CARD + 1 ; the grid: cards 12-27, rows 2-17
GRID_ROW        = 2
LEG_CARD        = GRID_CARD + 17 ; the legend: a colour cell, its text
LEG_X           = (LEG_CARD + 1) * 8 + 3
SYS_END         = 31            ; banks 0-30: the system (DESIGN.md "REU map")
ENG_FIRST       = FE_UBANK      ; 188-191: the file engine's listings
LEG_FIRST       = 192           ; 192-255: the legacy area (4 MB)
LEG_AREA        = 64
STEP_Y          = 156           ; the steppers' baselines: legacy (the
STEP2_Y         = 170           ; legend's last kind right of it), then
                                ; the spooler and the tasks (the page's
                                ; presses end at y 171, its line at 176)
SPOOL_BANK      = 27            ; the spooler: banks 27-28, then the top
DRIVE_TOP       = FE_LAST_BANK  ; of the drives' area (spool.s)
COL_SPOOL       = 14            ; light blue
SPOOL_N         = 5             ; sizes: 128 KB to 2 MB
COL_SYS         = 11            ; dark grey
COL_ENGINE      = 8             ; orange
COL_LEGACY      = 7             ; yellow
COL_FREE        = 1             ; white
HATCH           = $80           ; (in a bank's use: legacy, not in use)
TASKS_MAX       = 8
DEF_SIZE        = 0             ; 512 KB (sizes: 0-3, 8 << n banks)
PATTERN_HALF    = 2             ; GEOS's 50% pattern

        .segment "OV6"

; Ov_ReuDraw: the values read, the grid, the legend, the steppers.
Ov_ReuDraw:
        jsr ReadVals
        jsr Map
        jsr Grid
        jsr Legend
        ldx #BUTTONS - 1        ; the buttons
@b:     stx at
        lda BtnLo,x
        pha
        lda BtnHi,x
        tax
        pla
        jsr ButtonDraw
        ldx at
        dex
        bpl @b
        lda #<LLegacy
        ldx #>LLegacy
        ldy #X_LLEG
        jsr Text
        lda #<LTasks
        ldx #>LTasks
        ldy #X_LTASKS
        jsr Text2
        lda #<LSpool
        ldx #>LSpool
        ldy #X_LSPOOL
        jsr Text2
        jmp Values

; Ov_ReuPress: a click on a stepper's [-] or [+]: the value changed
; (the other kept within the legacy area), written, all drawn again.
Ov_ReuPress:
        ldx #BUTTONS - 1
@b:     stx at
        lda BtnLo,x
        pha
        lda BtnHi,x
        tax
        pla
        jsr OnButton
        bcc @hit
        ldx at
        dex
        bpl @b
        rts
@hit:   lda at
        cmp #4                  ; the spooler's [-], [+]
        bcc :+
        bne @spoolUp
        ldx spool
        beq @end
        dec spool
        jmp @new
@spoolUp:
        ldx spool
        cpx #SPOOL_N - 1
        bcs @end
        inc spool
        jmp @new
:       lda at
        beq @sizeDn
        cmp #1
        beq @sizeUp
        cmp #2
        beq @tasksDn
        ldx tasks               ; tasks [+], while they fit
        cpx #TASKS_MAX
        bcs @end
        inx
        stx tasks
        jsr Fits
        bcc @new
        dec tasks
@end:   rts
@tasksDn:
        ldx tasks
        cpx #2
        bcc @end
        dec tasks
        jmp @new
@sizeDn:
        ldx size
        beq @end
        dec size
        jmp @new
@sizeUp:
        ldx size
        cpx #3
        bcs @end
        inc size
@fewer: jsr Fits                ; a larger size: fewer slots if needed
        bcc @new
        dec tasks
        bne @fewer
@new:   jsr WriteVals
        jmp Ov_ReuDraw

; Fits: C clear when size x tasks is within the legacy area.
Fits:   jsr Used
        cmp #LEG_AREA + 1
        rts

; Used: A = the legacy banks in use: (8 << size) * tasks.
Used:   ldx size
        lda #8
@s:     dex
        bmi :+
        asl a
        bne @s
:       sta tmp
        lda #0
        ldx tasks
@t:     clc
        adc tmp
        dex
        bne @t
        rts

; ReadVals: size (0-3) and tasks (1-8) from SETTINGS.INI [system]
; legacy= and tasks= (missing or other: 512 KB, 8).
ReadVals:
        jsr UseSettings
        lda #DEF_SIZE
        sta size
        lda #TASKS_MAX
        sta tasks
        jsr LegacyKey
        jsr IniFind
        bcs @tasks
        ldy #0
        lda (r2),y
        ldx #3
@d:     cmp SizeDigit,x
        beq @size
        dex
        bpl @d
        bmi @tasks
@size:  stx size
@tasks: jsr TasksKey
        jsr IniFind
        bcs @end
        ldy #0
        lda (r2),y
        sec
        sbc #'1'
        cmp #TASKS_MAX
        bcs @end
        adc #1
        sta tasks
@end:   lda #0                  ; spool=: 128 (or none), 256, 512, 1024,
        sta spool               ; 2048 KB: by its first and fourth
        jsr SpoolKey            ; characters, as the kernal (spool.s)
        jsr IniFind
        bcs @fit
        ldy #0
        lda (r2),y
        ldx #2
@sd:    cmp SpoolDigit,x
        beq @sg
        dex
        bpl @sd
        bmi @fit
@sg:    ldy #3
        lda (r2),y
        cmp #'0'
        bcc :+
        cmp #'9' + 1
        bcs :+
        inx
        inx
        inx
:       cpx #SPOOL_N
        bcs @fit
        stx spool
@fit:   jsr Fits                ; (a hand-made file beyond the area:
        bcc :+                  ; the slots made to fit)
        dec tasks
        bne @end
        inc tasks
:       rts

; WriteVals: legacy= and tasks= in the text (the defaults: the keys
; out); dirty.
WriteVals:
        jsr LegacyKey
        ldx size
        beq @legDel
        lda SizeLo,x
        sta r2L
        lda SizeHi,x
        sta r2H
        jsr IniSet
        bcs @room
        jmp @tasks
@legDel:
        jsr IniDel
@tasks: jsr TasksKey
        lda tasks
        cmp #TASKS_MAX
        beq @tasksDel
        clc
        adc #'0'
        sta digit
        lda #<digit
        sta r2L
        lda #>digit
        sta r2H
        jsr IniSet
        bcs @room
        jmp @spool
@tasksDel:
        jsr IniDel
@spool: jsr SpoolKey            ; spool= (128 KB: the key out)
        ldx spool
        beq @spoolDel
        lda SpoolKbLo,x
        sta r2L
        lda SpoolKbHi,x
        sta r2H
        jsr IniSet
        bcs @room
        jmp @done
@spoolDel:
        jsr IniDel
@done:  lda #1
        sta dirty
        rts
@room:  jmp NoRoom

; LegacyKey, TasksKey: r0 = "system", r1 = the key.
LegacyKey:
        lda #<KLegacy
        ldx #>KLegacy
        bne Key                 ; (always)
TasksKey:
        lda #<KTasks
        ldx #>KTasks
        bne Key                 ; (always)
SpoolKey:
        lda #<KSpool
        ldx #>KSpool
Key:    sta r1L
        stx r1H
        lda #<SSystem
        sta r0L
        lda #>SSystem
        sta r0H
        rts

; Map: use = each bank's colour (HATCH: legacy not in use): the system,
; the engine, the legacy area by size x tasks, free, then the drives
; A-D over it (ramBase; a native drive's tracks from FE_MOUNTINFO).
Map:    jsr Used
        sta tmp                 ; (the legacy banks in use)
        ldx #0
@bank:  lda #COL_SYS
        cpx #SYS_END
        bcc @set
        lda #COL_FREE
        cpx #FE_LAST_BANK + 1
        bcc @set
        lda #COL_SYS            ; (180-187: the system fonts)
        cpx #ENG_FIRST
        bcc @set
        lda #COL_ENGINE
        cpx #LEG_FIRST
        bcc @set
        txa                     ; (its place in the legacy area)
        sec
        sbc #LEG_FIRST
        cmp tmp
        lda #COL_LEGACY
        bcc @set
        ora #HATCH
@set:   sta use,x
        inx
        bne @bank
        lda #COL_SPOOL          ; the spooler: 27-28 and the rest from
        sta use + SPOOL_BANK    ; the drives' top down (what it is set to:
        sta use + SPOOL_BANK + 1 ; the kernal takes less where drives are)
        ldx spool
        lda SpoolBanks,x
        sec
        sbc #2
        beq @drives
        tay
        ldx #DRIVE_TOP
        lda #COL_SPOOL
@sp:    sta use,x
        dex
        dey
        bne @sp
@drives:
        ldx #3                  ; the drives
@drive: stx drv
        lda driveType,x         ; (REU drives only: a real drive's
        bpl @next               ; ramBase means nothing)
        and #$0F
        beq @next
        cmp #DRV_NATIVE
        bne @fixed
        jsr Tracks              ; (A: its tracks, a bank each)
        jmp @mark
@fixed: tay
        lda TypeBanks,y
@mark:  sta tmp
        ldx drv
        ldy ramBase,x
        lda DriveCol,x
@m:     sta use,y
        iny
        beq @next               ; (not past bank 255)
        dec tmp
        bne @m
@next:  ldx drv
        dex
        bpl @drive
        rts

; Tracks: A = drive drv's tracks (FE_MOUNTINFO; 0 on an error).
Tracks: lda drv
        clc
        adc #'a'
        sta drvPath + 1
        lda #<drvPath
        sta r0L
        lda #>drvPath
        sta r0H
        lda #<info
        sta r1L
        lda #>info
        sta r1H
        lda #FE_MOUNTINFO
        jsr FileEngine
        lda r3L
        cpx #0
        beq :+
        lda #0
:       rts

; Grid: the banks' cells coloured (16 rows of 16 from GRID_CARD,
; GRID_ROW), the legacy banks not in use hatched, a frame round it.
Grid:   lda #<(COLOR_MATRIX + GRID_ROW * 40 + GRID_CARD)
        sta vp
        lda #>(COLOR_MATRIX + GRID_ROW * 40 + GRID_CARD)
        sta vp+1
        ldx #0
@bank:  lda use,x
        and #$0F
        sta tmp
        lda use,x
        bpl :+
        lda #COL_SYS            ; (hatched: dark grey on the legacy colour)
        asl a
        asl a
        asl a
        asl a
        ora tmp
        jmp @put
:       lda tmp                 ; (the paper; the ink the same)
        asl a
        asl a
        asl a
        asl a
        ora tmp
@put:   pha
        txa
        and #$0F
        tay
        pla
        sta (vp),y
        txa
        and #$0F
        cmp #$0F
        bne @on
        lda vp                  ; (a row done: the next one)
        clc
        adc #40
        sta vp
        bcc @on
        inc vp+1
@on:    inx
        bne @bank
        lda #PATTERN_HALF       ; the hatch over the cells not in use
        jsr SetPattern
        ldx #0
@h:     lda use,x
        bpl @hn
        stx at
        jsr CellBox
        jsr Rectangle
        ldx at
@hn:    inx
        bne @h
        lda #GRID_ROW * 8 - 1   ; the frame
        sta r2L
        lda #(GRID_ROW + 16) * 8
        sta r2H
        lda #<(GRID_CARD * 8 - 1)
        sta r3L
        lda #>(GRID_CARD * 8 - 1)
        sta r3H
        lda #<((GRID_CARD + 16) * 8)
        sta r4L
        lda #>((GRID_CARD + 16) * 8)
        sta r4H
        lda #$FF
        jmp FrameRectangle

; CellBox: r2-r4 = bank X's cell.
CellBox:
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #GRID_ROW
        asl a
        asl a
        asl a
        sta r2L
        clc
        adc #7
        sta r2H
        txa
        and #$0F
        clc
        adc #GRID_CARD
        asl a
        asl a
        asl a
        sta r3L
        lda #0
        sta r3H
        sta r4H
        lda r3L
        clc
        adc #7
        sta r4L
        rts

; Legend: a colour cell and a name per kind, every other cell row.
Legend: ldx #LEGEND_N - 1
@l:     stx at
        txa
        asl a                   ; its row: GRID_ROW + 2 * index
        adc #GRID_ROW
        sta tmp
        tay                     ; its colour cell
        lda RowLo,y
        sta vp
        lda RowHi,y
        sta vp+1
        ldy #LEG_CARD
        lda LegCol,x
        sta (vp),y
        lda tmp                 ; its name
        asl a
        asl a
        asl a
        adc #7
        sta r1H
        ldx at
        lda LegLo,x
        sta r0L
        lda LegHi,x
        sta r0H
        lda #<LEG_X
        sta r11L
        lda #>LEG_X
        sta r11H
        jsr PutString
        ldx at
        dex
        bpl @l
        rts

; Values: the size and the slots between their buttons.
Values: lda #0                  ; their places cleared
        jsr SetPattern
        lda #STEP_Y - 9
        sta r2L
        lda #STEP_Y + 2
        sta r2H
        lda #<SIZE_X
        sta r3L
        lda #>SIZE_X
        sta r3H
        lda #<(SIZE_PLUS_X - 2)
        sta r4L
        lda #>(SIZE_PLUS_X - 2)
        sta r4H
        jsr Rectangle
        lda #STEP2_Y - 9        ; (the tasks: the second row)
        sta r2L
        lda #STEP2_Y + 2
        sta r2H
        lda #<TASKS_X
        sta r3L
        lda #>TASKS_X
        sta r3H
        lda #<(TASKS_PLUS_X - 2)
        sta r4L
        lda #>(TASKS_PLUS_X - 2)
        sta r4H
        jsr Rectangle
        ldx size
        lda SizeTextLo,x
        pha
        lda SizeTextHi,x
        tax
        pla
        ldy #X_SIZE
        jsr Text
        lda tasks
        clc
        adc #'0'
        sta digit
        lda #<digit
        ldx #>digit
        ldy #X_TASKS
        jsr Text2
        lda #0                  ; the spooler's value
        jsr SetPattern
        lda #STEP2_Y - 9
        sta r2L
        lda #STEP2_Y + 2
        sta r2H
        lda #<SIZE_X
        sta r3L
        lda #>SIZE_X
        sta r3H
        lda #<(SIZE_PLUS_X - 2)
        sta r4L
        lda #>(SIZE_PLUS_X - 2)
        sta r4H
        jsr Rectangle
        ldx spool
        lda SpoolTxtLo,x
        pha
        lda SpoolTxtHi,x
        tax
        pla
        ldy #X_SIZE
        ; (falls into Text2)

; Text2: as Text, on the second row (STEP2_Y).
Text2:  sta r0L
        stx r0H
        lda TextXLo,y
        sta r11L
        lda TextXHi,y
        sta r11H
        lda #STEP2_Y
        sta r1H
        jmp PutString

; Text: the text at A/X at x TextX[Y], baseline STEP_Y.
Text:   sta r0L
        stx r0H
        lda TextXLo,y
        sta r11L
        lda TextXHi,y
        sta r11H
        lda #STEP_Y
        sta r1H
        jmp PutString

; --- data

LABEL_X         = GRID_CARD * 8
SIZE_MINUS_X    = LABEL_X + 44   ; ("Spooler", the widest label)
SIZE_X          = SIZE_MINUS_X + 16
SIZE_PLUS_X     = SIZE_X + 44
TASKS_LABEL_X   = SIZE_PLUS_X + 24
TASKS_MINUS_X   = TASKS_LABEL_X + 32
TASKS_X         = TASKS_MINUS_X + 16
TASKS_PLUS_X    = TASKS_X + 14
        .assert TASKS_PLUS_X + 14 < 318, error, "the steppers fit the page"

X_LLEG          = 0             ; (TextXLo, TextXHi)
X_LTASKS        = 1
X_SIZE          = 2
X_TASKS         = 3
X_LSPOOL        = 0             ; (the second row: the legacy one's places)
TextXLo:        .byte <LABEL_X, <TASKS_LABEL_X, <(SIZE_X + 2), <(TASKS_X + 3)
TextXHi:        .byte >LABEL_X, >TASKS_LABEL_X, >(SIZE_X + 2), >(TASKS_X + 3)

BUTTONS         = 6
BtnLo:  .byte <BSizeDn, <BSizeUp, <BTasksDn, <BTasksUp, <BSpoolDn, <BSpoolUp
BtnHi:  .byte >BSizeDn, >BSizeUp, >BTasksDn, >BTasksUp, >BSpoolDn, >BSpoolUp
BSizeDn:        .word SIZE_MINUS_X
                .byte STEP_Y - 9, 14
                .word TMinus
BSizeUp:        .word SIZE_PLUS_X
                .byte STEP_Y - 9, 14
                .word TPlus
BTasksDn:       .word TASKS_MINUS_X
                .byte STEP2_Y - 9, 14
                .word TMinus
BTasksUp:       .word TASKS_PLUS_X
                .byte STEP2_Y - 9, 14
                .word TPlus
BSpoolDn:       .word SIZE_MINUS_X
                .byte STEP2_Y - 9, 14
                .word TMinus
BSpoolUp:       .word SIZE_PLUS_X
                .byte STEP2_Y - 9, 14
                .word TPlus
TMinus:         .byte "-", 0
TPlus:          .byte "+", 0
LLegacy:        .byte "Legacy", 0
LTasks:         .byte "Tasks", 0
LSpool:         .byte "Spooler", 0
KSpool:         .byte "spool", 0
SpoolDigit:     .byte "125"                     ; (as the kernal's spool.s)
SpoolBanks:     .byte 2, 4, 8, 16, 32
SpoolKbLo:      .byte 0, <V256, <V512, <V1024, <V2048
SpoolKbHi:      .byte 0, >V256, >V512, >V1024, >V2048
V256:           .byte "256", 0
V512:           .byte "512", 0
SpoolTxtLo:     .byte <T128, <T256, <T512, <T1M, <T2M
SpoolTxtHi:     .byte >T128, >T256, >T512, >T1M, >T2M
T128:           .byte "128 KB", 0
T256:           .byte "256 KB", 0
SSystem:        .byte "system", 0
KLegacy:        .byte "legacy", 0
KTasks:         .byte "tasks", 0
SizeDigit:      .byte "5124"
SizeLo:         .byte 0, <V1024, <V2048, <V4096
SizeHi:         .byte 0, >V1024, >V2048, >V4096
V1024:          .byte "1024", 0
V2048:          .byte "2048", 0
V4096:          .byte "4096", 0
SizeTextLo:     .byte <T512, <T1M, <T2M, <T4M
SizeTextHi:     .byte >T512, >T1M, >T2M, >T4M
T512:           .byte "512 KB", 0
T1M:            .byte "1 MB", 0
T2M:            .byte "2 MB", 0
T4M:            .byte "4 MB", 0
TypeBanks:      .byte 0, 3, 6, 13       ; none, 1541, 1571, 1581 (mount.s)
DriveCol:       .byte 2, 5, 6, 4        ; A red, B green, C blue, D purple
LEGEND_N        = 9
LegCol:         .byte COL_SYS << 4 | COL_SYS, $22, $55, $66, $44
                .byte COL_ENGINE << 4 | COL_ENGINE, COL_LEGACY << 4 | COL_LEGACY
                .byte COL_SPOOL << 4 | COL_SPOOL, COL_FREE << 4 | COL_FREE
LegLo:          .byte <LSys, <LA, <LB, <LC, <LD, <LEng, <LLeg, <LSpl, <LFree
LegHi:          .byte >LSys, >LA, >LB, >LC, >LD, >LEng, >LLeg, >LSpl, >LFree
LSpl:           .byte "spooler", 0
LSys:           .byte "system", 0
LA:             .byte "drive A", 0
LB:             .byte "drive B", 0
LC:             .byte "drive C", 0
LD:             .byte "drive D", 0
LEng:           .byte "engine", 0
LLeg:           .byte "legacy", 0
LFree:          .byte "free", 0
RowLo:          .repeat 25, i
                .byte <(COLOR_MATRIX + i * 40)
                .endrepeat
RowHi:          .repeat 25, i
                .byte >(COLOR_MATRIX + i * 40)
                .endrepeat
drvPath:        .byte "/a", 0
digit:          .byte "8", 0

size:           .byte 0         ; 0-3: 512 KB, 1, 2, 4 MB
tasks:          .byte 8
spool:          .byte 0         ; 0-4: 128, 256, 512 KB, 1, 2 MB
at:             .byte 0
drv:            .byte 0
tmp:            .byte 0
info:           .res 64         ; FE_MOUNTINFO's path (not used)
use:            .res 256        ; each bank's colour (HATCH: not in use)
