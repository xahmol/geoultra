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

        .import OvlCall, drvTracks, SysRAMOp, ReadFile, taskReq
        .export SpoolInit, spoolExtra, spoolBase, driveLimit, SpoolLd, spOn, spDrv

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
px              = $9FFC         ; Xfer: the pointer (Q_HEAD, Q_TAIL)
cmd             = $9FFD         ; Xfer: the REU command
rsize           = $9FFE         ; (word) Room: the ring's pages
; The playback's (modules 109, 110; apart from the recording's: a full
; queue plays records while a call waits, module 112)
ptype           = $9F70         ; the record's type
runEntry        = $9F71         ; the driver's entry (offset from $7900)
runLen1         = $9F72         ; (word) the data's length
runLen2         = $9F74         ; the colours' length
status          = $9F75         ; the driver's X
rdata           = $9F76         ; (word) where the data goes
need            = $9F78         ; (word) module 112: the room waited for
                                ; (not in the module: Step's module 109
                                ; takes its place, and it comes back new)
fits            = $9F7A         ; module 112's answer: 0 the call fits
; The playback's state: the first RING0 pages of the queue's bank 0
; (spoolring.inc), REU bank 27
ST_DRV          = $0000         ; the program's $7900-$7F3F meanwhile
ST_WORK         = $0700         ; the driver's work area between calls
ST_AREA         = $1000         ; the program's AREA meanwhile
AREA            = $6000         ; C64 memory lent to the driver: its work
WORK_LEN        = $0780         ; area (1920 bytes), the row (640), the
ROWB            = AREA + WORK_LEN ; colours (80), a string (256)
COLB            = ROWB + ROW_LEN
STRB            = COLB + COL_LEN
AREA_LEN        = STRB + 256 - AREA

SPOOL_FIXED     = 2             ; banks 27-28
; The queue's header (QHEAD, REU bank 1)
Q_MAGIC         = 0             ; "GUSP"
Q_HEAD          = 4             ; 3 bytes: where the next record goes
Q_TAIL          = 7             ; 3 bytes: the next record to play
Q_JOBS          = 10            ; jobs recorded
Q_OPEN          = 11            ; $80: a job being recorded
Q_PAUSED        = 12            ; $80: playback paused
Q_DNEXT         = 13            ; the next driver slot (module 106)
Q_PSLOT         = 14            ; the playback's driver slot (T_DRIVER)
Q_ERR           = 15            ; the printer's error that paused it
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
spOn:           .byte $80       ; $80: drivers caught (0: printing as in
                                ; GEOS 2.0, straight to the printer; tests)

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

RING_LOAD       = 1
RING_INIT       = 1
RING_HEAD_ONLY  = 1
        .include "spoolring.inc"

Store:  jsr OvlCall             ; (module 108: the request written)
        .byte 108, 0
Wait:   jsr OvlCall             ; (module 112: the queue played until A/X
        .byte 112, 0            ; bytes fit)

; Record: the driver's entry n = (spEnt - 2) / 3 written by module 108:
; a new job (InitForPrint, or none open) first gets its driver's slot
; (T_DRIVER), then the call's record (type, up to two parts of data: the
; row, its colours; a string). X = 0 (StartPrint, StopPrint: no error).
Record: lda r0L                 ; the program's data and colour pointers
        sta dataP               ; (HeadLoad's SysRAMOp uses r0-r3)
        lda r0H
        sta dataP+1
        lda r2L
        sta colP
        lda r2H
        sta colP+1
        lda spEnt
        sec
        sbc #2
        ldx #$FF
@div:   inx
        sec
        sbc #3
        bcs @div
        stx entry
        lda #0                  ; the room the call needs: a row (and its
        ldx #0                  ; colours), a string, else a few bytes
        ldy entry
        cpy #2
        bne @str
        lda #<(ROW_LEN + COL_LEN)
        ldx #>(ROW_LEN + COL_LEN)
        bne @wait
@str:   cpy #5
        bne @wait
        ldy #0
@sl:    lda (r0),y              ; (r0: the program's string still)
        beq @sz
        iny
        bne @sl
@sz:    tya
        ldx #0
@wait:  jsr Wait                ; (module 112: played until it fits)
        ldx #0
        lda fits                ; (it does not: the call dropped whole, no
        beq :+                  ; record without its data)
        rts
:       jsr HeadLoad
        lda entry
        beq @job                ; InitForPrint: a new job
        bit hdr + Q_OPEN
        bmi @call
@job:   lda #$80
        sta hdr + Q_OPEN
        inc hdr + Q_JOBS
        lda #T_DRIVER           ; its driver: the slot it was kept in
        sta rqType              ; (module 106)
        lda #<spDrv
        sta rqSrc1
        lda #>spDrv
        sta rqSrc1+1
        lda #1
        sta rqLen1
        lda #0
        sta rqLen1+1
        sta rqLen2
        jsr Store
@call:  lda #0
        sta rqLen1
        sta rqLen1+1
        sta rqLen2
        ldx entry
        lda Types,x
        sta rqType
        cmp #T_ROW
        bne @ascii
        lda dataP               ; the row: 640 bytes from r0
        sta rqSrc1
        lda dataP+1
        sta rqSrc1+1
        lda #<ROW_LEN
        sta rqLen1
        lda #>ROW_LEN
        sta rqLen1+1
        lda colP                ; its colours (r2 not 0): 80 more
        sta rqSrc2
        lda colP+1
        sta rqSrc2+1
        ora colP
        beq @store
        lda #T_ROWC
        sta rqType
        lda #COL_LEN
        sta rqLen2
        bne @store
@ascii: cmp #T_ASCII
        bne @store
        lda dataP               ; the string and its zero
        sta rqSrc1
        sta r0L
        lda dataP+1
        sta rqSrc1+1
        sta r0H
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

        .include "spoolring.inc"
        .include "spoolput.inc"

; Write: module 107's request into the queue (its header in hdr): the
; record's type, a string's length, its parts; the header saved. X = 0.
; No room: the rest dropped (part 3 makes the program wait instead).
Write:  lda rqType
        jsr PutType
        lda rqType              ; a string: its length first (the playback
        cmp #T_ASCII            ; reads it so)
        bne :+
        lda #<rqLen1
        ldx #>rqLen1
        jsr From
        lda #1
        ldx #0
        jsr Put
:       lda rqSrc1
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
        lda taskReq             ; the playback: a pass at MainLoop's end
        ora #$20
        sta taskReq
        ldx #0
        rts

        .endscope

; ======================================================================

        .segment "OVL109"
        .scope Mod109

        jmp Step                ; entry 0 (SpoolStep)

RING_LOAD       = 1
        .include "spoolring.inc"

Run:    jsr OvlCall             ; (module 110: the driver called; X = its
        .byte 110, 0            ; status)

; Step: the record at the tail played: T_DRIVER sets the driver's slot;
; any other is a call of the driver (module 110) with its data. A
; StartPrint or StopPrint error pauses the queue (Q_PAUSED, Q_ERR) and
; keeps the record. Played: the next pass asked for (taskReq $20).
; Empty or paused: nothing (no next pass).
Step:   jsr HeadLoad
        bcs @idle               ; (no queue)
        bit hdr + Q_PAUSED
        bmi @idle
        ldx #2
@cmp:   lda hdr + Q_HEAD,x
        cmp hdr + Q_TAIL,x
        bne @work
        dex
        bpl @cmp
@idle:  rts
@work:  lda #<ptype
        ldx #>ptype
        jsr From
        jsr Get1
        lda ptype
        cmp #T_DRIVER
        bne @call
        lda #<(hdr + Q_PSLOT)
        ldx #>(hdr + Q_PSLOT)
        jsr From
        jsr Get1
        jmp @done
@call:  tax
        lda Entry - T_INIT,x
        sta runEntry
        lda #0
        sta runLen1
        sta runLen1+1
        sta runLen2
        cpx #T_ROW
        bcc @run
        cpx #T_ROWC + 1
        bcs @ascii
        lda #<ROW_LEN           ; a row: 640 bytes, with colours 80 more
        sta runLen1
        lda #>ROW_LEN
        sta runLen1+1
        cpx #T_ROWC
        bne @run
        lda #COL_LEN
        sta runLen2
        bne @run
@ascii: cpx #T_ASCII
        bne @run
        lda #<runLen1           ; a string: its length first
        ldx #>runLen1
        jsr From
        jsr Get1
@run:   jsr Run
        lda ptype               ; StartPrint, StopPrint: their status
        cmp #T_START
        beq :+
        cmp #T_STOP
        bne @done
:       txa
        beq @done
        stx status              ; an error: paused, the record kept
        jsr HeadLoad            ; (the header as it was)
        lda #$80
        sta hdr + Q_PAUSED
        lda status
        sta hdr + Q_ERR
        jmp HeadSave
@done:  jsr HeadSave
        lda taskReq             ; the next pass
        ora #$20
        sta taskReq
        rts

; Get1: one byte from the tail to src.
Get1:   lda #1
        ldx #0
        jmp Get

; The entries by record type (T_INIT on): InitForPrint, StartPrint,
; PrintBuffer (twice), StopPrint, StartASCII, PrintASCII, SetNLQ.
Entry:  .byte 0, 3, 6, 6, 9, 18, 15, 21

        .endscope

; ======================================================================

        .segment "OVL110"
        .scope Mod110

        jmp Run                 ; entry 0 (module 109)

        .include "spoolring.inc"

; Run: the driver's entry runEntry called with the record's data: the
; program's bytes out and the job's driver and work area in (module 111);
; the data (runLen1 bytes: a row, or a string) and colours (runLen2) from
; the tail; r0 the data, r1 the work area, r2 the colours (0: none);
; then module 111 again (the work area kept, the program's bytes back).
; X = the driver's X.
Run:    jsr SwapIn
        lda runEntry            ; the data: a string, or a row
        cmp #15
        bne :+
        lda #<STRB
        ldx #>STRB
        bne @data
:       lda #<ROWB
        ldx #>ROWB
@data:  sta rdata
        stx rdata+1
        jsr From
        lda runLen1
        ldx runLen1+1
        jsr Get
        lda #<COLB
        ldx #>COLB
        jsr From
        lda runLen2
        ldx #0
        jsr Get
        lda rdata               ; the call
        sta r0L
        lda rdata+1
        sta r0H
        lda #<AREA
        sta r1L
        lda #>AREA
        sta r1H
        lda #0
        sta r2L
        sta r2H
        lda runLen2
        beq :+
        lda #<COLB
        sta r2L
        lda #>COLB
        sta r2H
:       lda runEntry
        sta vec
        lda #>DRV_ADDR
        sta vec+1
        jsr Call
        stx status
        jsr SwapOut
        ldx status
        rts
Call:   jmp (vec)
SwapIn: jsr OvlCall             ; (module 111)
        .byte 111, 0
SwapOut:
        jsr OvlCall
        .byte 111, 3

vec:            .word 0

        .endscope

; ======================================================================

        .segment "OVL111"
        .scope Mod111

        jmp SwapIn              ; entry 0 (module 110)
        jmp SwapOut             ; entry 3

; SwapIn: the program's driver area and AREA out to bank 27, the job's
; driver (its slot, Q_PSLOT) to $7900, its work area into AREA.
SwapIn: ldx #0
        jsr Op
        ldx #1
        jsr Op
        lda #<DRV_ADDR
        sta r0L
        lda #>DRV_ADDR
        sta r0H
        lda #<DRV_SAVE
        sta r1L
        lda #>DRV_SAVE
        sta r1H
        ldx hdr + Q_PSLOT
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
        ldy #REU_FETCH
        jsr SysRAMOp
        ldx #2
        jmp Op

; SwapOut: the work area kept, the program's bytes back.
SwapOut:
        ldx #3
        jsr Op
        ldx #4
        jsr Op
        ldx #5

; Op: transfer X of the table below (r0 C64, r1 REU in bank 27, r2 the
; length, the command).
Op:     lda OpC64Lo,x
        sta r0L
        lda OpC64Hi,x
        sta r0H
        lda OpReuLo,x
        sta r1L
        lda OpReuHi,x
        sta r1H
        lda OpLenLo,x
        sta r2L
        lda OpLenHi,x
        sta r2H
        lda #SPOOL_BANK
        sta r3L
        ldy OpCmd,x
        jmp SysRAMOp
OpC64Lo:        .byte <DRV_ADDR, <AREA, <AREA, <AREA, <AREA, <DRV_ADDR
OpC64Hi:        .byte >DRV_ADDR, >AREA, >AREA, >AREA, >AREA, >DRV_ADDR
OpReuLo:        .byte <ST_DRV, <ST_AREA, <ST_WORK, <ST_WORK, <ST_AREA, <ST_DRV
OpReuHi:        .byte >ST_DRV, >ST_AREA, >ST_WORK, >ST_WORK, >ST_AREA, >ST_DRV
OpLenLo:        .byte <DRV_LEN, <AREA_LEN, <WORK_LEN, <WORK_LEN, <AREA_LEN, <DRV_LEN
OpLenHi:        .byte >DRV_LEN, >AREA_LEN, >WORK_LEN, >WORK_LEN, >AREA_LEN, >DRV_LEN
OpCmd:          .byte REU_STASH, REU_STASH, REU_FETCH, REU_STASH, REU_FETCH, REU_FETCH

        .endscope

; ======================================================================

        .segment "OVL112"
        .scope Mod112

        jmp Wait                ; entry 0 (module 107)

RING_LOAD       = 1
RING_INIT       = 1
RING_HEAD_ONLY  = 1
PUT_ROOM_ONLY   = 1
        .include "spoolring.inc"
        .include "spoolput.inc"

Step:   jsr OvlCall             ; (module 109: a record played)
        .byte 109, 0

; Wait: A/X bytes (and a few to spare) to fit in the queue: records
; played meanwhile (the program waits at the printer's pace, as without
; the spooler). Not when the queue is paused (a printer error) or empty
; and the call still larger than it. fits: 0 it fits, else not (the
; call is then dropped whole: module 107).
Wait:   clc
        adc #8
        sta need
        txa
        adc #0
        sta need+1
@loop:  lda need
        sta len
        lda need+1
        sta len+1
        jsr HeadLoad
        jsr Room
        lda #0
        bcc @end
        bit hdr + Q_PAUSED
        bmi @no
        ldx #2                  ; empty: it never fits
@e:     lda hdr + Q_HEAD,x
        cmp hdr + Q_TAIL,x
        bne @play
        dex
        bpl @e
@no:    lda #1
@end:   sta fits
        rts
@play:  jsr Step
        jmp @loop

        .endscope
