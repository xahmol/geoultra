; GeoUltra Settings: the System page (overlay 3, ovl.s; docs/design/SETTINGS.md):
; turbo, the slow list and hibernation, over
; SETTINGS.INI's [system] keys as the kernal reads them (mount.s):
; turbo=N (a speed step 0-15) or turbo=off, no key for full speed;
; slow=NAME once per application that runs at 1 MHz (up to 6, the start
; of its permanent name); hibernate= seconds (0 off). Turbo changes are
; also applied at once (FE_TURBO). Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress, ButtonDraw, OnButton
        .import IniFind, IniSet, IniDel, iniSkip, sel, dirty, NoRoom
        .import FileEngine, Dialog
        .export Ov_SysDraw, Ov_SysPress

        .segment "OV3"

; Ov_SysDraw: the page: the rows (turbo, hibernation), the turbo step,
; the slow list and its buttons.
Ov_SysDraw:
        jsr ReadStep
        lda #$FF
        sta slowSel
        lda #<Rows
        ldx #>Rows
        jsr ChoiceDraw
        lda #<Minus
        ldx #>Minus
        jsr ButtonDraw
        lda #<Plus
        ldx #>Plus
        jsr ButtonDraw
        jsr StepDraw
        lda #<SlowLabel         ; the slow list's label
        sta r0L
        lda #>SlowLabel
        sta r0H
        lda #<LABEL_X
        sta r11L
        lda #>LABEL_X
        sta r11H
        lda #LIST_TOP + 9
        sta r1H
        jsr PutString
        lda #<Add
        ldx #>Add
        jsr ButtonDraw
        lda #<Remove
        ldx #>Remove
        jsr ButtonDraw
        jmp SlowDraw

; Ov_SysPress: a click: the rows (a new turbo mode applied at once), the
; stepper, the slow list and its buttons.
Ov_SysPress:
        lda sel                 ; (row 0: the turbo mode before)
        sta before
        lda #<Rows
        ldx #>Rows
        jsr ChoicePress
        lda sel
        cmp before
        beq :+
        jmp Apply
:       lda #<Minus
        ldx #>Minus
        jsr OnButton
        bcs :+
        lda step
        beq @end
        dec step
        jmp NewStep
:       lda #<Plus
        ldx #>Plus
        jsr OnButton
        bcs :+
        lda step
        cmp #STEPS - 1
        bcs @end
        inc step
        jmp NewStep
:       lda #<Add
        ldx #>Add
        jsr OnButton
        bcs :+
        jmp AddSlow
:       lda #<Remove
        ldx #>Remove
        jsr OnButton
        bcs :+
        jmp RemoveSlow
:       jmp ListPress
@end:   rts

; --- turbo

; ReadStep: step = SETTINGS.INI's turbo=N (a number), else the last
; step (the stepper's start for "full speed" and "off"); stepText its
; digits (the step option's value, choice.s).
ReadStep:
        lda #STEPS - 1
        sta step
        jsr TurboKey
        jsr IniFind             ; (r2 the value, A its length)
        bcs @text
        tax
        beq @text
        ldy #0
        lda (r2),y
        sec
        sbc #'0'
        cmp #10
        bcs @text               ; ("off" or other words)
        sta step
        cpx #2
        bcc @text
        iny
        lda (r2),y
        sec
        sbc #'0'
        cmp #10
        bcs @text
        sta tmp                 ; two digits: 10 * the first + the second
        lda step
        asl a
        sta step
        asl a
        asl a
        clc
        adc step
        adc tmp
        cmp #STEPS
        bcc :+
        lda #STEPS - 1
:       sta step
@text:  jmp StepText

; NewStep: the stepper moved: turbo=N in the text, the rows and the step
; drawn again, the step applied at once.
NewStep:
        jsr StepText
        jsr TurboKey
        lda #<stepText
        sta r2L
        lda #>stepText
        sta r2H
        jsr IniSet
        bcc :+
        jmp NoRoom
:       lda #1
        sta dirty
        lda #<Rows              ; (the row: "step" now in force)
        ldx #>Rows
        jsr ChoiceDraw
        jsr StepDraw
        lda step
        jmp Turbo

; Apply: the turbo row's new mode applied at once: full speed (step 15),
; off (step 0) or the stepper's step.
Apply:  lda sel
        beq @full
        cmp #MODE_OFF
        beq @off
        lda step
        jmp Turbo
@full:  lda #STEPS - 1
        jmp Turbo
@off:   lda #0
; Turbo: speed step A at once (FE_TURBO; no turbo registers: nothing).
Turbo:  sta r2L
        lda #FE_TURBO
        jmp FileEngine

; StepDraw: "step N: A / B MHz" beside the stepper (the U64 and Elite I,
; the Elite II and C64 Ultimate, as gush's turbo shows them).
StepDraw:
        lda #0                  ; its place cleared
        jsr SetPattern
        lda #STEP_Y - 9
        sta r2L
        lda #STEP_Y + 2
        sta r2H
        lda #<STEP_X
        sta r3L
        lda #>STEP_X
        sta r3H
        lda #<(PLUS_X - 2)
        sta r4L
        lda #>(PLUS_X - 2)
        sta r4H
        jsr Rectangle
        ldx #0                  ; the text in lineBuf
        ldy #0
@w:     lda StepWord,y
        beq :+
        sta lineBuf,x
        inx
        iny
        bne @w
:       lda step
        jsr Digits
        lda #':'
        sta lineBuf,x
        inx
        lda #' '
        sta lineBuf,x
        inx
        ldy step
        lda MhzU64,y
        jsr Digits
        lda #'/'
        sta lineBuf,x
        inx
        ldy step
        lda MhzE2,y
        jsr Digits
        ldy #0
@m:     lda MhzWord,y
        sta lineBuf,x
        beq :+
        inx
        iny
        bne @m
:       lda #<lineBuf
        sta r0L
        lda #>lineBuf
        sta r0H
        lda #<STEP_X
        sta r11L
        lda #>STEP_X
        sta r11H
        lda #STEP_Y
        sta r1H
        jmp PutString

; StepText: stepText = step's digits (and its zero).
StepText:
        lda step
        ldx #0
        jsr Digits
        lda #0
        sta lineBuf,x
        ldx #2
@copy:  lda lineBuf,x
        sta stepText,x
        dex
        bpl @copy
        rts

; Digits: A (0-99) as one or two digits into lineBuf from X on; X past
; them.
Digits: ldy #0
@tens:  cmp #10
        bcc @ones
        sbc #10
        iny
        bne @tens
@ones:  pha
        tya
        beq :+
        ora #'0'
        sta lineBuf,x
        inx
:       pla
        ora #'0'
        sta lineBuf,x
        inx
        rts

; TurboKey: r0 = "system", r1 = "turbo".
TurboKey:
        lda #<SSystem
        sta r0L
        lda #>SSystem
        sta r0H
        lda #<KTurbo
        sta r1L
        lda #>KTurbo
        sta r1H
        rts

; --- the slow list

; SlowDraw: the list's box cleared and framed, the slow= names in it
; (slowN of them), the selected one inverted.
SlowDraw:
        jsr ListBox
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda #$FF
        jsr FrameRectangle
        lda #0
        sta slowN
@name:  lda slowN
        cmp #SLOW_MAX
        bcs @mark
        jsr SlowName            ; (C set: no more)
        bcs @mark
        lda #<nameBuf
        sta r0L
        lda #>nameBuf
        sta r0H
        lda #<(LIST_X + 4)
        sta r11L
        lda #>(LIST_X + 4)
        sta r11H
        lda slowN
        jsr LineTop
        clc
        adc #8
        sta r1H
        jsr PutString
        inc slowN
        bne @name
@mark:  lda slowSel
        cmp slowN
        bcs :+
        jmp Invert
:       lda #$FF
        sta slowSel
        rts

; SlowName: nameBuf = the slow list's name A (the A-th slow= line); C
; set when there is none.
SlowName:
        sta iniSkip
        jsr SlowKey
        jsr IniFind             ; (r2 the value, A its length)
        bcs @end
        cmp #NAME_MAX
        bcc :+
        lda #NAME_MAX
:       tay
        lda #0
        sta nameBuf,y
@ch:    dey
        bmi @ok
        lda (r2),y
        sta nameBuf,y
        jmp @ch
@ok:    clc
@end:   rts

; ListPress: a click in the list's box: the name there selected (again:
; not), the box drawn again.
ListPress:
        jsr ListBox
        lda mouseXPos+1         ; inside the box?
        bne @end
        lda mouseXPos
        cmp #LIST_X
        bcc @end
        cmp #LIST_X + LIST_W
        bcs @end
        lda mouseYPos
        sec
        sbc #LIST_TOP + 1
        bcc @end
        ldx #0
@line:  cmp #LIST_ROW
        bcc @got
        sbc #LIST_ROW
        inx
        cpx #SLOW_MAX
        bcc @line
@end:   rts
@got:   cpx slowN
        bcs @end
        cpx slowSel
        bne :+
        ldx #$FF                ; (the selected one: not any more)
:       stx slowSel
        jmp SlowDraw

; RemoveSlow: the selected name's slow= line taken out.
RemoveSlow:
        lda slowSel
        cmp slowN
        bcs @end
        sta iniSkip
        jsr SlowKey
        jsr IniDel
        lda #1
        sta dirty
        lda #$FF
        sta slowSel
        jmp SlowDraw
@end:   rts

; AddSlow: an application picked (Pick): its permanent name's start as a
; new slow= line (up to SLOW_MAX).
AddSlow:
        lda slowN
        cmp #SLOW_MAX
        bcs @end
        jsr Pick
        bcs @end
        lda #$FF                ; (a new line, though the key is there)
        sta iniSkip
        jsr SlowKey
        lda #<nameBuf
        sta r2L
        lda #>nameBuf
        sta r2H
        jsr IniSet
        bcc :+
        jmp NoRoom
:       lda #1
        sta dirty
        jmp SlowDraw
@end:   rts

; Pick: the file dialog (DBGETFILES) for applications on drives A-D,
; DISK going to the next drive; OPEN: nameBuf = the chosen one's
; permanent name, up to NAME_MAX characters without the spaces at its
; end (C clear); C set when cancelled or not read.
Pick:   ldx curDrive            ; a drive A-D that is there
        cpx #8
        bcc @first
        cpx #12
        bcs @first
        lda driveType-8,x
        bne @open
@first: ldx #7
@next:  inx
        cpx #12
        bcc :+
        ldx #8
:       lda driveType-8,x
        beq @next
@open:  txa
        jsr SetDevice
        jsr OpenDisk
        lda curDrive            ; "Drive X" in the dialog
        clc
        adc #'A' - 8
        sta DriveText + 6
        lda #0
        sta nameBuf
        lda #<nameBuf
        sta r5L
        lda #>nameBuf
        sta r5H
        lda #APPLICATION
        sta r7L
        lda #0
        sta r10L
        sta r10H
        lda #<PickDlg
        sta r0L
        lda #>PickDlg
        sta r0H
        jsr Dialog              ; (chrome.s: over the desk's colours)
        lda sysDBData
        cmp #DISK
        bne :+
        ldx curDrive
        jmp @next
:       cmp #OPEN
        bne @no
        lda nameBuf
        beq @no
        lda #<nameBuf           ; its header: the permanent name
        sta r6L
        lda #>nameBuf
        sta r6H
        jsr FindFile
        txa
        bne @no
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr GetFHdrInfo
        txa
        bne @no
        ldy #NAME_MAX           ; its start, the spaces at its end left out
@trim:  dey
        bmi @no
        lda fileHeader + O_GHFNAME,y
        beq @trim
        cmp #' '
        beq @trim
        lda #0
        sta nameBuf + 1,y
@copy:  lda fileHeader + O_GHFNAME,y
        sta nameBuf,y
        dey
        bpl @copy
        clc
        rts
@no:    sec
        rts

; Invert: the selected name's line inverted.
Invert: jsr ListBox
        lda slowSel
        jsr LineTop
        sta r2L
        clc
        adc #LIST_ROW - 1
        sta r2H
        inc r3L                 ; (inside the frame)
        dec r4L
        jmp InvertRectangle

; ListBox: r2-r4 = the list's box.
ListBox:
        lda #LIST_TOP
        sta r2L
        lda #LIST_TOP + SLOW_MAX * LIST_ROW + 1
        sta r2H
        lda #LIST_X
        sta r3L
        lda #0
        sta r3H
        sta r4H
        lda #LIST_X + LIST_W - 1
        sta r4L
        rts

; LineTop: A = line A's top (LIST_TOP + 1 + A * LIST_ROW).
LineTop:
        tax
        lda #LIST_TOP + 1
@add:   dex
        bmi @end
        clc
        adc #LIST_ROW
        bne @add
@end:   rts

; SlowKey: r0 = "system", r1 = "slow".
SlowKey:
        lda #<SSystem
        sta r0L
        lda #>SSystem
        sta r0H
        lda #<KSlow
        sta r1L
        lda #>KSlow
        sta r1H
        rts

; --- layout and data

STEPS           = 16            ; the U64's speed steps
MODE_OFF        = 1             ; the turbo row: full speed, off, step
SLOW_MAX        = 6             ; the kernal's slow list (mount.s)
NAME_MAX        = 12            ; a slow name's characters (SLOW_NAME)
LABEL_X         = PAGE_LEFT + 2
ROW_Y           = PAGE_TOP + 20 ; the turbo row's baseline
STEP_Y          = ROW_Y + 18    ; the stepper's
MINUS_X         = 150
STEP_X          = MINUS_X + 18
PLUS_X          = 262
LIST_TOP        = STEP_Y + 10   ; the slow list's box
LIST_X          = 150
LIST_W          = 104
LIST_ROW        = 10
HIB_Y           = PAGE_BOTTOM - 8 ; the hibernation row's baseline
BTN_X           = LIST_X + LIST_W + 8

Rows:   .byte 2
        .byte ROW_Y                             ; turbo
        .word LTurbo, SSystem, KTurbo
        .byte 3, 0
        .word 150, TFull, 0
        .word 216, TOff, VOff
        .word 250, TStep, stepText
        .byte HIB_Y                             ; hibernation
        .word LHib, SSystem, KHib
        .byte 5, 2
        .word 142, THOff, V0
        .word 172, T15, V15
        .word 205, T30, V30
        .word 238, T60, V60
        .word 277, T300, V300

Minus:  .word MINUS_X
        .byte STEP_Y - 9, 14
        .word TMinus
Plus:   .word PLUS_X
        .byte STEP_Y - 9, 14
        .word TPlus
Add:    .word BTN_X
        .byte LIST_TOP, 50
        .word TAdd
Remove: .word BTN_X
        .byte LIST_TOP + 16, 50
        .word TRemove

PickDlg:
        .byte DEF_DB_POS | 1
        .byte DBGETFILES, 4, 4
        .byte OPEN, 17, 4
        .byte DISK, 17, 21
        .byte CANCEL, 17, 38
        .byte DBTXTSTR, 136, 79
        .word PickText
        .byte DBTXTSTR, 136, 89
        .word DriveText
        .byte 0

SSystem:        .byte "system", 0
KTurbo:         .byte "turbo", 0
KSlow:          .byte "slow", 0
KHib:           .byte "hibernate", 0
LTurbo:         .byte "Turbo", 0
LHib:           .byte "Hibernate", 0
SlowLabel:      .byte "At 1 MHz", 0
TFull:          .byte "full speed", 0
TOff:           .byte "off", 0
TStep:          .byte "step", 0
VOff:           .byte "off", 0
THOff:          .byte "off", 0
T15:            .byte "15 s", 0
T30:            .byte "30 s", 0
T60:            .byte "1 min", 0
T300:           .byte "5 min", 0
V0:             .byte "0", 0
V15:            .byte "15", 0
V30:            .byte "30", 0
V60:            .byte "60", 0
V300:           .byte "300", 0
TMinus:         .byte "-", 0
TPlus:          .byte "+", 0
TAdd:           .byte "add...", 0
TRemove:        .byte "remove", 0
StepWord:       .byte "step ", 0
MhzWord:        .byte " MHz", 0
PickText:       .byte "At 1 MHz", 0
DriveText:      .byte "Drive A", 0
MhzU64:         .byte 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 24, 32, 40, 48
MhzE2:          .byte 1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32, 40, 48, 64

; Scratch (overlay data: fetched anew with the overlay, when the page is
; drawn)
step:           .byte 0         ; the stepper's speed step
stepText:       .res 3          ; its digits (the step option's value)
before:         .byte 0
slowN:          .byte 0         ; names in the slow list
slowSel:        .byte $FF       ; the selected one ($FF: none)
tmp:            .byte 0
nameBuf:        .res 17         ; a file's name (DBGETFILES), a slow name
lineBuf:        .res 32
