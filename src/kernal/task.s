; Task switching (docs/DESIGN.md "Task switcher"; the user's decisions of
; 2026-11-14). C= + RUN/STOP, in any application, opens a small popup
; drawn over the screen: the tasks (the current one marked), "new task",
; "close task"; RETURN or a click switches, RUN/STOP cancels. A switch
; stashes the VIC's registers and all 64 KB of RAM into the task's REU
; bank (TASK_BANK + n) and fetches another task's: as the kernal's bytes
; are the same in every snapshot, the CPU goes on in the other task's
; copy of this code, which returns to that task as if its own switch
; had just ended. The task table (a slot's use and its application's
; name) lives in REU bank 1; the current task's number and name in RAM
; (each snapshot keeps its own). Resident: the interrupt's check and
; MainLoop's; module 95 the popup, 97 its drawing, 96 the switch and a
; new task, 98 the table and closing.
; Own design and code; the behaviour after MegaPatch 3's TaskManager
; (idea only, docs/DESIGN.md).

        .include "geos.inc"
        .include "hw.inc"

        .import OvlCall, HibTick, RtcCheck, SysRAMOp, EnterDeskTop
        .import GetNextChar, Rectangle, FrameRectangle, InvertRectangle
        .import PutString, SetPattern, UseSystemFont
        .export TaskTick, TaskCheck, TaskInit, TaskMany, taskName, taskCur

TASK_BANK       = 19            ; slot n's RAM: REU bank 19 + n (DESIGN "REU map")
TASKS_MAX       = 8
TABLE           = $1E00         ; REU bank 1: per slot TBL_LEN bytes: used,
TBL_LEN         = 16            ; the name (NAME_LEN, zero-ended)
NAME_LEN        = 13
VICS            = $1F00         ; REU bank 1: per slot the VIC's 47 registers
VIC_LEN         = 47
TBLBUF          = $9F70         ; the slot's scratch: the table's copy
                                ; (TASKS_MAX * TBL_LEN = 128 bytes), then
P_COUNT         = $9FF0         ; the popup's state (it outlives the
P_SEL           = $9FF1         ; modules' calls: their own bytes are
P_AT            = $9FF2         ; fetched anew after each)
P_CHOICE        = $9FF3
P_TMP           = $9FF4
P_ITEMS         = $9FF5         ; (TASKS_MAX + 2: to $9FFE)
ITEM_NEW        = $80           ; (items: a slot, or these)
ITEM_CLOSE      = $81
BOX_CARD        = 10            ; the popup: cards 10-29, card rows 5-17
BOX_ROW         = 5
BOX_ROWS        = 13
BOX_W           = 20
ROW_H           = 11
FIRST_Y         = BOX_ROW * 8 + 22 ; the first entry's baseline
SCREEN_SAVE     = $A000         ; REU bank 1: the popup's rows of the screen
COLOUR_SAVE     = $AF00         ; and their colour cells
SYS_BANK        = 1
REU_STASH_FF00  = $80           ; execute on a write to $FF00, C64 -> REU (as hibernate.s)

        .segment "KEXT"

; TaskTick (the interrupt, before HibTick; I/O in): C= and RUN/STOP held
; together (one column of the matrix: RUN/STOP row bit 7, C= row bit 5)
; set taskReq once per press. $DC00 is put back (the input driver reads
; port 1 next frame).
TaskTick:
        lda $DC00
        pha
        lda #$7F
        sta $DC00
        lda $DC01
        tax
        pla
        sta $DC00
        txa
        and #$A0
        bne @up
        lda taskHeld
        bne @hib
        lda #$80
        sta taskHeld
        sta taskReq
        bne @hib                ; (always)
@up:    lda #0
        sta taskHeld
@hib:   jmp HibTick

; TaskCheck (MainLoop, at its end, never inside a disk call): a request
; opens the popup (module 95).
TaskCheck:
        bit taskReq
        bpl @rtc
        lda #0
        sta taskReq
        jsr OvlCall
        .byte 95, 0
@rtc:   jmp RtcCheck

; TaskInit (the cold start; a resumed session: module 8): the table
; anew, the current task the only one. TaskMany: C set when more than
; one task runs (module 8: no hibernation then, yet).
TaskInit:
        jsr OvlCall
        .byte 98, 6
TaskMany:
        jsr OvlCall
        .byte 98, 9

taskReq:        .byte 0         ; $80: the popup asked for (TaskTick)
taskHeld:       .byte 0         ; $80: the keys still held
taskCur:        .byte 0         ; this snapshot's slot
taskSP:         .byte 0         ; its stack pointer while it is away
taskName:       .res NAME_LEN   ; its application's permanent name (0:
                                ; the desktop; module 15 AppGate, module 0)

; ======================================================================

        .segment "OVL95"
        .scope Mod95

        jmp Popup               ; entry 0

Switch: jsr OvlCall             ; (module 96: to task A)
        .byte 96, 0
NewTask:
        jsr OvlCall             ; (module 96: a new task; no return)
        .byte 96, 3
Close:  jsr OvlCall             ; (module 98: task A closed)
        .byte 98, 0
Names:  jsr OvlCall             ; (module 98: the table to TBLBUF)
        .byte 98, 3
Draw:   jsr OvlCall             ; (module 97: the popup drawn)
        .byte 97, 0

; Popup: the screen's rows saved, the list drawn, keys and clicks until
; a choice or RUN/STOP; the screen given back, then the choice done.
Popup:  ldx #$22                ; the drawing state kept ($22-$38: the
@keep:  lda $00,x               ; pattern, the font, the mode, the
        pha                     ; window)
        inx
        cpx #$39
        bne @keep
        lda dispBufferOn
        pha
        lda #ST_WR_FORE
        sta dispBufferOn
        ldy #REU_STASH
        jsr ScreenOp
        jsr Names
        jsr UseSystemFont
        lda #0                  ; the items: each used slot, new, close
        sta P_COUNT
        sta P_SEL
        tax
@slot:  stx P_AT
        txa
        asl a
        asl a
        asl a
        asl a
        tay
        lda TBLBUF,y            ; (its used byte)
        beq :+
        ldx P_COUNT
        lda P_AT
        sta P_ITEMS,x
        cmp taskCur
        bne @n
        stx P_SEL               ; (the current one selected)
@n:     inc P_COUNT
:       ldx P_AT
        inx
        cpx #TASKS_MAX
        bcc @slot
        ldx P_COUNT
        lda #ITEM_NEW
        sta P_ITEMS,x
        inx
        lda #ITEM_CLOSE
        sta P_ITEMS,x
        inx
        stx P_COUNT
        jsr Draw
@loop:  cli
        jsr GetNextChar
        cmp #KEY_STOP
        beq @cancel
        cmp #CR
        beq @choose
        cmp #KEY_UP
        bne :+
        lda P_SEL
        beq @loop
        dec P_SEL
        jsr Draw
        jmp @loop
:       cmp #KEY_DOWN
        bne @mouse
        ldx P_SEL
        inx
        cpx P_COUNT
        bcs @loop
        stx P_SEL
        jsr Draw
        jmp @loop
@mouse: lda pressFlag
        and #MOUSE_BIT
        beq @loop
        lda pressFlag
        and #$FF ^ MOUSE_BIT
        sta pressFlag
        lda mouseData
        bmi @loop               ; (a release)
        jsr ItemUnder
        bcs @cancel             ; (outside: as RUN/STOP)
        sta P_SEL
@choose:
        ldx P_SEL
        lda P_ITEMS,x
        sta P_CHOICE
        jmp @end
@cancel:
        lda #$FF
        sta P_CHOICE
@end:   ldy #REU_FETCH          ; the screen back
        jsr ScreenOp
        pla
        sta dispBufferOn
        ldx #$38
@back:  pla
        sta $00,x
        dex
        cpx #$21
        bne @back
        lda P_CHOICE
        cmp #$FF
        beq @done
        cmp #ITEM_NEW
        bne :+
        jmp NewTask
:       cmp #ITEM_CLOSE
        bne :+
        lda taskCur
        jmp Close
:       cmp taskCur
        beq @done
        jmp Switch
@done:  rts

; ItemUnder: A = the item under the pointer (C clear); C set: none.
ItemUnder:
        lda mouseXPos+1
        bne @no
        lda mouseXPos
        cmp #BOX_CARD * 8
        bcc @no
        cmp #(BOX_CARD + BOX_W) * 8
        bcs @no
        lda mouseYPos
        sec
        sbc #FIRST_Y - 8
        bcc @no
        ldx #0
@d:     cmp #ROW_H
        bcc :+
        sbc #ROW_H
        inx
        bne @d
:       cpx P_COUNT
        bcs @no
        txa
        clc
        rts
@no:    sec
        rts

; ScreenOp: Y = REU command: the popup's card rows of the bitmap and of
; the colour matrix <-> REU bank 1.
ScreenOp:
        sty P_TMP
        lda #<($A000 + BOX_ROW * 320)
        sta r0L
        lda #>($A000 + BOX_ROW * 320)
        sta r0H
        lda #<SCREEN_SAVE
        sta r1L
        lda #>SCREEN_SAVE
        sta r1H
        lda #<(BOX_ROWS * 320)
        sta r2L
        lda #>(BOX_ROWS * 320)
        sta r2H
        lda #SYS_BANK
        sta r3L
        jsr SysRAMOp
        lda #<(COLOR_MATRIX + BOX_ROW * 40)
        sta r0L
        lda #>(COLOR_MATRIX + BOX_ROW * 40)
        sta r0H
        lda #<COLOUR_SAVE
        sta r1L
        lda #>COLOUR_SAVE
        sta r1H
        lda #<(BOX_ROWS * 40)
        sta r2L
        lda #>(BOX_ROWS * 40)
        sta r2H
        ldy P_TMP
        jmp SysRAMOp

        .endscope

; ======================================================================

        .segment "OVL97"
        .scope Mod97

        jmp Draw                ; entry 0 (module 95)

TEXT_X          = BOX_CARD * 8 + 12

; Draw: the box (its cells dark grey on light grey), its frame, the
; title, each item (the current task with a "*"), the selection
; inverted. The table in TBLBUF, the items in P_ITEMS.
Draw:   lda #<(COLOR_MATRIX + BOX_ROW * 40 + BOX_CARD)
        sta r0L
        lda #>(COLOR_MATRIX + BOX_ROW * 40 + BOX_CARD)
        sta r0H
        ldx #BOX_ROWS
@cr:    ldy #BOX_W - 1
        lda #$BF
@cc:    sta (r0),y
        dey
        bpl @cc
        lda r0L
        clc
        adc #40
        sta r0L
        bcc :+
        inc r0H
:       dex
        bne @cr
        lda #0
        jsr SetPattern
        jsr Box
        jsr Rectangle
        lda #$FF
        jsr FrameRectangle
        lda #<TitleT
        sta r0L
        lda #>TitleT
        sta r0H
        lda #BOX_ROW * 8 + 10
        jsr TextAt
        ldx #0
@item:  stx P_AT
        lda P_ITEMS,x
        bmi @word
        asl a                   ; its name in TBLBUF (after the used byte)
        asl a
        asl a
        asl a
        clc
        adc #<(TBLBUF + 1)
        sta r0L
        lda #>(TBLBUF + 1)
        adc #0
        sta r0H
        ldy #0                  ; an empty name: the desktop
        lda (r0),y
        bne @name
        lda #<DeskT
        ldx #>DeskT
        bne @wset
@word:  cmp #ITEM_NEW
        bne :+
        lda #<NewT
        ldx #>NewT
        bne @wset
:       lda #<CloseT
        ldx #>CloseT
@wset:  sta r0L
        stx r0H
@name:  lda P_AT
        jsr ItemY
        jsr TextAt
        ldx P_AT
        lda P_ITEMS,x
        cmp taskCur
        bne :+
        lda #<MarkT             ; (the current one)
        sta r0L
        lda #>MarkT
        sta r0H
        lda P_AT
        jsr ItemY
        ldx #TEXT_X - 7
        jsr TextX
:       ldx P_AT
        cpx P_SEL
        bne :+
        txa
        jsr ItemBox
        jsr InvertRectangle
:       ldx P_AT
        inx
        cpx P_COUNT
        bcc @item
        rts

; TextAt: the text at r0, baseline A, at TEXT_X. TextX: at x X.
TextAt: ldx #TEXT_X
TextX:  sta r1H
        stx r11L
        lda #0
        sta r11H
        jmp PutString

; ItemY: A = item A's baseline.
ItemY:  tax
        lda #FIRST_Y
@m:     dex
        bmi @end
        clc
        adc #ROW_H
        bne @m
@end:   rts

; ItemBox: r2-r4 = item A's row.
ItemBox:
        jsr ItemY
        sec
        sbc #8
        sta r2L
        clc
        adc #ROW_H - 1
        sta r2H
        lda #BOX_CARD * 8 + 2
        sta r3L
        lda #(BOX_CARD + BOX_W) * 8 - 3
        sta r4L
        lda #0
        sta r3H
        sta r4H
        rts

; Box: r2-r4 = the popup.
Box:    lda #BOX_ROW * 8
        sta r2L
        lda #(BOX_ROW + BOX_ROWS) * 8 - 1
        sta r2H
        lda #BOX_CARD * 8
        sta r3L
        lda #(BOX_CARD + BOX_W) * 8 - 1
        sta r4L
        lda #0
        sta r3H
        sta r4H
        rts

TitleT:         .byte BOLDON, "Tasks", PLAINTEXT, 0
DeskT:          .byte "Desktop", 0
NewT:           .byte "new task", 0
CloseT:         .byte "close task", 0
MarkT:          .byte "*", 0

        .endscope

; ======================================================================

        .segment "OVL96"
        .scope Mod96

        jmp Switch              ; entry 0 (module 95: to slot A)
        jmp NewTask             ; entry 3 (module 95)
        jmp FetchTo             ; entry 6 (module 98: slot A's RAM, no return)

; Switch: to slot A: this task's name to the table, its VIC registers and
; its RAM to its bank (Away); then the other's RAM fetched (Fetch): the
; CPU goes on in the other task's copy of this code, takes that task's
; stack pointer and returns from that task's own Switch (or NewTask).
; Away must be called from this module directly: the stack below its
; pushes is what Fetch returns through.
Switch: sta target
        jsr Away
        jmp Fetch

; FetchTo (closing the current task, module 98): slot A's RAM fetched;
; this task is not stashed (no return).
FetchTo:
        sta target
        sei
        ; (falls into Fetch)

; Fetch (interrupts off): slot target's RAM fetched inline (a subroutine
; could not return: the stack changes under it), then its stack, its
; VIC registers, its flags and CPU port (Away's), back to its caller.
Fetch:  lda target
        clc
        adc #TASK_BANK
        tax
        lda #RAM_IO
        sta CPU_PORT
        lda #0
        sta reuC64
        sta reuC64+1
        sta reuAddr
        sta reuAddr+1
        sta reuLen
        sta reuLen+1
        sta reuCtrl
        stx reuAddr+2
        lda #REU_FETCH_FF00
        sta reuCmd
        lda #RAM_ALL
        sta CPU_PORT
        lda REU_TRIGGER
        sta REU_TRIGGER
        ldx taskSP              ; (the other task's RAM from here on)
        txs
        lda taskCur
        ldy #REU_FETCH
        jsr VicOp
        plp
        pla
        sta CPU_PORT
        rts

; Away: this task's name to its table entry; its CPU port and flags
; pushed and its stack pointer kept (Fetch takes them back), its VIC
; registers and RAM stashed to its slot. Interrupts off from here.
Away:   pla                     ; (our return address: kept across)
        sta ret
        pla
        sta ret+1
        lda CPU_PORT
        pha
        php
        sei
        tsx
        stx taskSP
        lda taskCur             ; its name to the table
        jsr NameOp
        lda taskCur
        ldy #REU_STASH
        jsr VicOp
        lda taskCur             ; all 64 KB to its bank
        clc
        adc #TASK_BANK
        tax
        lda #RAM_IO
        sta CPU_PORT
        lda #0
        sta reuC64
        sta reuC64+1
        sta reuAddr
        sta reuAddr+1
        sta reuLen
        sta reuLen+1
        sta reuCtrl
        stx reuAddr+2
        lda #REU_STASH_FF00
        sta reuCmd
        lda #RAM_ALL
        sta CPU_PORT
        lda REU_TRIGGER
        sta REU_TRIGGER
        lda #RAM_IO
        sta CPU_PORT
        lda ret+1
        pha
        lda ret
        pha
        rts

; NewTask: a free slot (the table in TBLBUF, Names done by module 95)
; used: this task stashed, the desktop started in the new one (no
; return here: this task resumes by returning from NewTask's caller).
; None free: back.
NewTask:
        ldx #0
@f:     txa
        asl a
        asl a
        asl a
        asl a
        tay
        lda TBLBUF,y
        beq @got
        inx
        cpx #TASKS_MAX
        bcc @f
        rts
@got:   stx target
        jsr Away
        lda target              ; the new one: used, no name
        sta taskCur
        lda #0
        sta taskName
        lda target
        jsr NameOp
        cli
        jmp EnterDeskTop

; NameOp: slot A in the table (REU bank 1): used, with this task's name.
NameOp: asl a
        asl a
        asl a
        asl a
        clc
        adc #<TABLE
        sta r1L
        lda #>TABLE
        sta r1H
        lda #1
        sta nameBuf
        ldx #NAME_LEN - 1
@c:     lda taskName,x
        sta nameBuf + 1,x
        dex
        bpl @c
        lda #<nameBuf
        sta r0L
        lda #>nameBuf
        sta r0H
        lda #TBL_LEN
        sta r2L
        lda #0
        sta r2H
        lda #SYS_BANK
        sta r3L
        ldy #REU_STASH
        jmp SysRAMOp

; VicOp: A = slot, Y = REU command: the VIC's registers <-> its place in
; REU bank 1 (I/O in meanwhile).
VicOp:  sty tmp
        asl a                   ; * 48: * 16 * 3
        asl a
        asl a
        asl a
        sta r1L
        asl a
        clc
        adc r1L
        clc
        adc #<VICS
        sta r1L
        lda #>VICS
        adc #0
        sta r1H
        lda #<$D000
        sta r0L
        lda #>$D000
        sta r0H
        lda #VIC_LEN
        sta r2L
        lda #0
        sta r2H
        lda #SYS_BANK
        sta r3L
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        ldy tmp
        jsr SysRAMOp
        pla
        sta CPU_PORT
        rts

target:         .byte 0
ret:            .word 0
tmp:            .byte 0
nameBuf:        .res ::TBL_LEN

        .endscope

; ======================================================================

        .segment "OVL98"
        .scope Mod98

        jmp Close               ; entry 0 (module 95: slot A closed)
        jmp Names               ; entry 3 (module 95: the table to TBLBUF)
        jmp Init                ; entry 6 (TaskInit)
        jmp Many                ; entry 9 (TaskMany)

FetchTo:
        jsr OvlCall             ; (module 96: slot A's RAM; no return)
        .byte 96, 6

; Close: slot A closed. The current task: another used slot's RAM
; fetched (the last one stays); another slot: only freed.
Close:  sta target
        jsr Names
        lda target
        cmp taskCur
        beq @self
        jmp Free
@self:  ldx #0                  ; another used slot
@o:     cpx taskCur
        beq @next
        txa
        jsr Entry
        ldy #0
        lda (r0),y
        bne @got
@next:  inx
        cpx #TASKS_MAX
        bcc @o
        rts                     ; (the last one: stays)
@got:   stx target
        lda taskCur
        jsr Free
        lda target
        jmp FetchTo

; Free: slot A's used byte 0 in the table.
Free:   jsr EntryReu
        lda #0
        sta TBLBUF
        lda #1
        sta r2L
        ldy #REU_STASH
        jmp TblOp

; EntryReu: r1 = slot A's entry in REU bank 1.
EntryReu:
        asl a
        asl a
        asl a
        asl a
        clc
        adc #<TABLE
        sta r1L
        lda #>TABLE
        sta r1H
        rts

; TblOp: Y = REU command, r1, r2L set: TBLBUF <-> REU bank 1.
TblOp:  lda #<TBLBUF
        sta r0L
        lda #>TBLBUF
        sta r0H
        lda #0
        sta r2H
        lda #SYS_BANK
        sta r3L
        jmp SysRAMOp

; Names: the whole table to TBLBUF (the current task: used, its own
; name from RAM).
Names:  lda #<TABLE
        sta r1L
        lda #>TABLE
        sta r1H
        lda #TASKS_MAX * TBL_LEN
        sta r2L
        ldy #REU_FETCH
        jsr TblOp
        lda taskCur
        jsr Entry
        ldy #NAME_LEN
@c:     lda taskName - 1,y
        sta (r0),y
        dey
        bne @c
        lda #1
        sta (r0),y
        rts

; Entry: r0 = slot A's entry in TBLBUF.
Entry:  asl a
        asl a
        asl a
        asl a
        clc
        adc #<TBLBUF
        sta r0L
        lda #>TBLBUF
        adc #0
        sta r0H
        rts

; Init: the table cleared, the current task the only one.
Init:   ldx #TASKS_MAX * TBL_LEN - 1
        lda #0
@z:     sta TBLBUF,x
        dex
        bpl @z
        lda taskCur             ; (its used byte and name)
        jsr Entry
        ldy #NAME_LEN
@c:     lda taskName - 1,y
        sta (r0),y
        dey
        bne @c
        lda #1
        sta (r0),y
        lda #<TABLE
        sta r1L
        lda #>TABLE
        sta r1H
        lda #TASKS_MAX * TBL_LEN
        sta r2L
        ldy #REU_STASH
        jmp TblOp

; Many: C set when more than one slot is used.
Many:   jsr Names
        ldx #0
        stx tmp
@c:     txa
        jsr Entry
        ldy #0
        lda (r0),y
        beq :+
        inc tmp
:       inx
        cpx #TASKS_MAX
        bcc @c
        lda tmp
        cmp #2
        rts

target:         .byte 0
tmp:            .byte 0

        .endscope
