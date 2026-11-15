; The print spooler (docs/DESIGN.md "Print spooler"; the user's decisions
; of 2026-11-15). Part 1: the queue's REU banks. Banks 27-28 always; with
; SETTINGS.INI [system] spool= (KB: 128, 256, 512, 1024, 2048; read by
; the auto-exec module 92 at the cold start) more, at the top of the
; drives' area (banks 31-187) as far as no mounted drive uses them there;
; FE_MOUNT and the disk images gone into stay below (driveLimit, the
; file engine's Banks0). The queue's logical bank n: 27 + n for n < 2,
; spoolBase + n - 2 after.
;
; Part 2: the printer driver's calls recorded. LdFile ends in SpoolLd
; (module 106): a file of GEOS type PRINTER loaded at $7900 is kept as
; it is in REU bank 1 (DRV_SAVE) and its entries (HG2G "Printer
; drivers": InitForPrint $7900, StartPrint +3, PrintBuffer +6, StopPrint
; +9, GetDimensions +12, PrintASCII +15, StartASCII +18, SetNLQ +21) but
; GetDimensions become `jsr SpoolEnt` (the driver kept in the next of
; DRV_SLOTS slots, spDrv its slot): module 107 records the call and
; its data in the queue, and the program goes on at once. The queue: a
; ring of records over the spooler's banks (head, tail: byte offsets),
; its header in bank 1 at QHEAD. A job starts with its driver (the copy
; in its slot at DRV_SAVE), so the playback (part 3) needs nothing else.
; Records: a type byte, then its data: T_DRIVER (its slot), T_INIT, T_START,
; T_ROW (640 bytes), T_ROWC (640 and 80 colour bytes), T_STOP, T_SASCII,
; T_ASCII (the string and its zero), T_NLQ. Own code.

        .include "geos.inc"
        .include "engine.inc"
        .include "hw.inc"

        .import OvlCall, drvTracks, SysRAMOp, ReadFile
        .export SpoolInit, spoolExtra, spoolBase, driveLimit, SpoolLd, spOn

PRINTER         = 9             ; GEOS file type
DRV_ADDR        = $7900
DRV_LEN         = $0640         ; $7900-$7F3F
DRV_SAVE        = $E800         ; REU bank 1: drivers as loaded, DRV_SLOTS
DRV_SLOTS       = 4             ; of DRV_LEN (to $F8FF), taken in turn
QHEAD           = $E700         ; REU bank 1: the queue's header (Q_*)
SYS_BANK        = 1
SPOOL_BANK      = 27
T_DRIVER        = 1             ; the queue's records
T_INIT          = 2
T_START         = 3
T_ROW           = 4
T_ROWC          = 5
T_STOP          = 6
T_SASCII        = 7
T_ASCII         = 8
T_NLQ           = 9
ROW_LEN         = 640
COL_LEN         = 80
; The recording's state in the overlay scratch ($9F70-$9FFF, kept across
; modules 107 and 108; no file engine call runs meanwhile)
hdr             = $9FD0         ; the queue's header (Q_LEN)
entry           = $9FE0
type            = $9FE1
dataP           = $9FE3         ; (word) the program's r0
colP            = $9FE5         ; (word) its r2
len             = $9FE9         ; (word)
src             = $9FED         ; (word)
n               = $9FEF         ; (word)
m               = $9FF1         ; (word)
rqInit          = $9FF3         ; module 107's request: $80 InitForPrint
rqType          = $9FF4
rqSrc1          = $9FF5         ; (word) the data, its length
rqLen1          = $9FF7         ; (word)
rqSrc2          = $9FF9         ; (word) a row's colours, their length
rqLen2          = $9FFB

SPOOL_FIXED     = 2             ; banks 27-28
; The queue's header (QHEAD, REU bank 1)
Q_MAGIC         = 0             ; "GUSP"
Q_HEAD          = 4             ; 3 bytes: where the next record goes
Q_TAIL          = 7             ; 3 bytes: the next record to play
Q_JOBS          = 10            ; jobs recorded
Q_OPEN          = 11            ; $80: a job being recorded
Q_PAUSED        = 12            ; $80: playback paused
Q_DNEXT         = 13            ; the next driver slot (module 106)
Q_LEN           = 16
SPOOL_MAX       = 32            ; 2 MB

        .segment "KEXT"

; SpoolInit (module 92, the cold start): A, X = spool='s first and
; fourth character (0: no spool=). Also an empty queue.
SpoolInit:
        jsr OvlCall
        .byte 105, 0

; SpoolLd (LdFile's end, in place of `jmp ReadFile`): ReadFile, then a
; printer driver's entries caught (module 106).
SpoolLd:
        jsr OvlCall
        .byte 106, 0

; SpoolEnt (a caught driver entry: `jsr SpoolEnt` at $7900 + 3n): the
; entry's return address dropped (its low byte, 2 + 3n, tells n), then
; module 107 as a stub: it returns to the program.
SpoolEnt:
        pla
        sta spEnt
        pla
        jsr OvlCall
        .byte 107, 0
spEnt:          .byte 0
spDrv:          .byte 0         ; this task's driver: its slot (module 106)
spOn:           .byte 0         ; $80: drivers caught (off until the
                                ; playback, part 3, exists: tests set it)

spoolExtra:     .byte 0                 ; banks beyond 27-28
spoolBase:      .byte FE_LAST_BANK + 1  ; the first of them
driveLimit:     .byte FE_LAST_BANK + 2  ; a drive's banks end below this - 1

; ======================================================================

        .segment "OVL105"
        .scope Mod105

        jmp Init                ; entry 0

        .include "banksof.inc"

; Init: A, X = spool='s first and fourth character: the banks wanted
; (128, 256, 512: 2, 4, 8; 1024, 2048: 16, 32; else 2); up to that - 2
; at the top of the drives' area, from bank 187 down, while no REU drive
; uses them; spoolExtra, spoolBase, driveLimit set.
Init:   stx tmp
        ldx #2
@d:     cmp Digit,x
        beq @dig
        dex
        bpl @d
@none:  lda #2                  ; (none or another value: 128 KB)
        bne @want
@dig:   lda tmp                 ; a fourth digit: 1024, 2048
        cmp #'0'
        bcc :+
        cmp #'9' + 1
        bcs :+
        inx
        inx
        inx
:       lda Banks,x
        beq @none               ; (5xxx: as none)
@want:  sec
        sbc #SPOOL_FIXED
        bcs :+
        lda #0
:       cmp #SPOOL_MAX - SPOOL_FIXED + 1
        bcc :+
        lda #SPOOL_MAX - SPOOL_FIXED
:       sta want
        lda #0
        sta got
@bank:  lda got
        cmp want
        bcs @set
        lda #FE_LAST_BANK       ; the next bank down
        sec
        sbc got
        sta bank
        ldx #3                  ; any REU drive on it?
@drive: lda driveType,x
        bpl @next               ; (not an REU drive)
        and #$0F
        beq @next
        lda bank
        cmp ramBase,x
        bcc @next               ; (below its first bank)
        jsr BanksOf             ; its end: ramBase + banks
        clc
        adc ramBase,x
        cmp bank
        beq @next
        bcs @set                ; (on it: no further)
@next:  dex
        bpl @drive
        inc got
        bne @bank               ; (always)
@set:   lda got
        sta spoolExtra
        lda #FE_LAST_BANK + 1
        sec
        sbc got
        sta spoolBase
        clc
        adc #1
        sta driveLimit
        rts

Digit:          .byte "125"         ; 128, 256, 512; a fourth digit: x + 3
Banks:          .byte 2, 4, 8, 16, 32, 0
tmp:            .byte 0
want:           .byte 0
got:            .byte 0
bank:           .byte 0

        .endscope

; ======================================================================

        .segment "OVL106"
        .scope Mod106

        jmp Load                ; entry 0 (SpoolLd)

; Load: ReadFile as LdFile would (X its error); a printer driver at
; $7900: kept in REU bank 1, its entries but GetDimensions caught.
Load:   jsr ReadFile
        txa
        beq :+
        rts                     ; (its error)
:       bit spOn                ; (catching switched on: spOn)
        bpl @no
        lda fileHeader + O_GHGEOS_TYPE
        cmp #PRINTER
        bne @no
        lda fileHeader + O_GHST_ADDR
        cmp #<DRV_ADDR
        bne @no
        lda fileHeader + O_GHST_ADDR + 1
        cmp #>DRV_ADDR
        beq @drv
@no:    jmp @ok
@drv:
        lda #<(QHEAD + Q_DNEXT) ; its slot: the next one in turn
        sta r1L
        lda #>(QHEAD + Q_DNEXT)
        sta r1H
        lda #<slot
        sta r0L
        lda #>slot
        sta r0H
        lda #1
        sta r2L
        lda #0
        sta r2H
        lda #SYS_BANK
        sta r3L
        ldy #REU_FETCH
        jsr SysRAMOp
        lda slot
        and #DRV_SLOTS - 1
        sta spDrv
        clc
        adc #1
        and #DRV_SLOTS - 1
        sta slot
        ldy #REU_STASH
        jsr SysRAMOp
        lda #<DRV_ADDR          ; the driver as loaded into it
        sta r0L
        lda #>DRV_ADDR
        sta r0H
        lda #<DRV_SAVE          ; (DRV_SAVE + slot * DRV_LEN)
        sta r1L
        lda #>DRV_SAVE
        sta r1H
        ldx spDrv
        beq @at
@mul:   clc
        lda r1L
        adc #<DRV_LEN
        sta r1L
        lda r1H
        adc #>DRV_LEN
        sta r1H
        dex
        bne @mul
@at:    lda #<DRV_LEN
        sta r2L
        lda #>DRV_LEN
        sta r2H
        lda #SYS_BANK
        sta r3L
        ldy #REU_STASH
        jsr SysRAMOp
        ldx #7                  ; the entries: jsr SpoolEnt (not 4,
@e:     cpx #4                  ; GetDimensions)
        beq @next
        txa
        sta tmp
        asl a
        adc tmp
        tay
        lda #$20
        sta DRV_ADDR,y
        lda #<SpoolEnt
        sta DRV_ADDR + 1,y
        lda #>SpoolEnt
        sta DRV_ADDR + 2,y
@next:  dex
        bpl @e
@ok:    ldx #0
@end:   rts

tmp:            .byte 0
slot:           .byte 0

        .endscope

; ======================================================================

        .segment "OVL107"
        .scope Mod107

        jmp Record              ; entry 0 (SpoolEnt)

Store:  jsr OvlCall             ; (module 108: the request written; at
        .byte 108, 0            ; Record's end: it returns to the program)

; Record: the driver's entry n = (spEnt - 2) / 3 as a request for module
; 108 (in the scratch: rqInit for InitForPrint, the record's type, up to
; two parts of data: the row, its colours; a string and its zero).
Record: lda spEnt
        sec
        sbc #2
        ldx #$FF
@div:   inx
        sec
        sbc #3
        bcs @div
        lda #0
        sta rqLen1
        sta rqLen1+1
        sta rqLen2
        sta rqInit
        txa
        bne :+
        lda #$80                ; InitForPrint: a new job
        sta rqInit
:       lda Types,x
        sta rqType
        cmp #T_ROW
        bne @ascii
        lda r0L                 ; the row: 640 bytes from r0
        sta rqSrc1
        lda r0H
        sta rqSrc1+1
        lda #<ROW_LEN
        sta rqLen1
        lda #>ROW_LEN
        sta rqLen1+1
        lda r2L                 ; its colours (r2 not 0): 80 more
        sta rqSrc2
        lda r2H
        sta rqSrc2+1
        ora r2L
        beq @store
        lda #T_ROWC
        sta rqType
        lda #COL_LEN
        sta rqLen2
        bne @store
@ascii: cmp #T_ASCII
        bne @store
        lda r0L                 ; the string and its zero
        sta rqSrc1
        lda r0H
        sta rqSrc1+1
        ldy #0
@len:   lda (r0),y
        beq @z
        iny
        bne @len
@z:     iny
        sty rqLen1
@store: jmp Store

; The entries' record types (GetDimensions, 4: never caught).
Types:  .byte T_INIT, T_START, T_ROW, T_STOP, 0, T_ASCII, T_SASCII, T_NLQ

        .endscope

; ======================================================================

        .segment "OVL108"
        .scope Mod108

        jmp Write               ; entry 0 (module 107)

        .include "spoolq.inc"

; Write: module 107's request into the queue: a new job (InitForPrint,
; or none open) first gets its driver; then the record's type and its
; parts. X = 0 (StartPrint, StopPrint: no error); no room: the rest is
; dropped (part 3 makes the program wait instead).
Write:  jsr HeadLoad
        bit rqInit
        bmi @job
        bit hdr + Q_OPEN
        bmi @rec
@job:   lda #$80
        sta hdr + Q_OPEN
        inc hdr + Q_JOBS
        lda #T_DRIVER           ; its driver: the slot it was kept in
        jsr PutType             ; (module 106)
        lda #<spDrv
        ldx #>spDrv
        jsr From
        lda #1
        ldx #0
        jsr Put
@rec:   lda rqType
        jsr PutType
        lda rqSrc1
        ldx rqSrc1+1
        jsr From
        lda rqLen1
        ldx rqLen1+1
        jsr Put
        lda rqSrc2
        ldx rqSrc2+1
        jsr From
        lda rqLen2
        ldx #0
        jsr Put
        jsr HeadSave
        ldx #0
        rts

        .endscope
