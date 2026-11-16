; The print spooler (docs/DESIGN.md "Print spooler"; the user's decisions
; of 2026-11-15). Own code.
;
; The queue's REU banks: 27-28 always; with SETTINGS.INI [system] spool=
; (KB: 128, 256, 512, 1024, 2048; read by the auto-exec module 92 at the
; cold start, module 105) more, at the top of the drives' area (banks
; 31-187) as far as no mounted drive uses them there; FE_MOUNT and the
; disk images gone into stay below (driveLimit, the file engine's
; Banks0). The queue's logical bank n: 27 + n for n < 2, spoolBase + n -
; 2 after. Bank 27's first RING0 pages hold the playback's state.
;
; Recording: LdFile ends in SpoolLd (module 106): a file of GEOS type
; PRINTER loaded at $7900 is kept as it is in REU bank 1 (DRV_SAVE, the
; next of DRV_SLOTS slots, spDrv its slot) and its entries (HG2G
; "Printer drivers": InitForPrint $7900, StartPrint +3, PrintBuffer +6,
; StopPrint +9, GetDimensions +12, PrintASCII +15, StartASCII +18, SetNLQ
; +21) but GetDimensions become `jsr SpoolEnt`. A call then waits only
; while the queue has no room for it (module 112: records played
; meanwhile), is recorded (modules 107, 108) and returns at once. The
; queue: a ring of records over the spooler's banks (head, tail: byte
; offsets), its header in bank 1 at QHEAD. A job (InitForPrint, or the
; first call after none) starts with its driver's slot and number
; (T_DRIVER), so the playback needs nothing else. Records: a type byte,
; then its data: T_DRIVER (the slot, the job's number), T_INIT, T_START,
; T_ROW (640 bytes), T_ROWC (640 and 80 colour bytes), T_STOP, T_SASCII,
; T_ASCII (a length byte, then the string and its zero), T_NLQ.
;
; Playback: a record a pass at MainLoop's end (taskReq $20, TaskCheck;
; module 109, then 113 for a driver call): the driver from its slot and
; the record's data lent C64 memory (modules 110, 111), the program's
; bytes given back after. A StartPrint or StopPrint error pauses the
; queue.
;
; Jobs (the desktop's indicator and queue window): each has an entry in
; a job table (JOBTAB: its number, $80 cancelled, its pages, the
; program's name); the playback passes a cancelled job's records over (a
; page it had started ended with StopPrint); FE_SPOOL (module 114) gives
; the desktop the state, the jobs, pause, resume and cancel.

        .include "geos.inc"
        .include "engine.inc"
        .include "hw.inc"

        .import OvlCall, drvTracks, SysRAMOp, ReadFile, taskReq, taskName
        .export SpoolInit, spoolExtra, spoolBase, driveLimit, SpoolLd, spOn, spDrv

PRINTER         = 9             ; GEOS file type
DRV_ADDR        = $7900
DRV_LEN         = $0640         ; $7900-$7F3F
DRV_SAVE        = $E800         ; REU bank 1: drivers as loaded, DRV_SLOTS
DRV_SLOTS       = 4             ; of DRV_LEN (to $F8FF), taken in turn
QHEAD           = $E700         ; REU bank 1: the queue's header (Q_*)
SYS_BANK        = 1
SPOOL_BANK      = 27
JOBTAB          = $FA00         ; REU bank 1: the job table (spooljob.inc)
JOB_MAX         = 16
J_LEN           = 16
J_SEQ           = 0             ; the job's number (entry n: job n mod 16)
J_FLAGS         = 1             ; $80: cancelled
J_PAGES         = 2             ; its StartPrint calls recorded
J_NAME          = 3             ; the program's name (taskName, task.s:
NAME_LEN        = 13            ; 12 characters and a zero; empty: the
                                ; desktop)
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
hdr             = $9FC0         ; the queue's header (Q_LEN)
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
drvRec          = $9F7B         ; module 107: a T_DRIVER's slot and number
jbuf            = $9F80         ; a job's entry (J_LEN; spooljob.inc)
; The playback's state: the first RING0 pages of the queue's bank 0
; (spoolring.inc), REU bank 27
ST_DRV          = $0000         ; the program's $7900-$7F3F meanwhile
ST_WORK         = $0700         ; the driver's work area between calls
ST_AREA         = $1000         ; the program's AREA meanwhile
ST_SCR          = $0E80         ; the overlay scratch during a driver call
SCR             = $9F70         ; (the file engine's work area: a driver
SCR_LEN         = $A000 - SCR   ; that calls the engine, GU PDF, uses it)
AREA            = $6000         ; C64 memory lent to the driver: its work
WORK_LEN        = $0780         ; area (1920 bytes), the row (640), the
ROWB            = AREA + WORK_LEN ; colours (80), a string (256)
COLB            = ROWB + ROW_LEN
STRB            = COLB + COL_LEN
AREA_LEN        = STRB + 256 - AREA
        .assert ST_DRV + DRV_LEN <= ST_WORK && ST_WORK + WORK_LEN <= ST_SCR && ST_SCR + SCR_LEN <= ST_AREA, error, "spool.s: the playback's state overlaps"
        .assert ST_AREA + AREA_LEN <= RING0 * 256, error, "spool.s: the playback's state runs into the ring"

SPOOL_FIXED     = 2             ; banks 27-28
RING0           = $20           ; the ring's first page (spoolring.inc)
; The queue's header (QHEAD, REU bank 1)
Q_MAGIC         = 0             ; "GUSP"
Q_HEAD          = 4             ; 3 bytes: where the next record goes
Q_TAIL          = 7             ; 3 bytes: the next record to play
Q_JOBS          = 10            ; jobs recorded
Q_OPEN          = 11            ; $80: a job being recorded
Q_PAUSED        = 12            ; $80: playback paused
Q_DNEXT         = 13            ; the next driver slot (module 106)
Q_PSLOT         = 14            ; the playback's driver slot (T_DRIVER)
Q_PJOB          = 15            ; and its job (right after: one Get)
Q_ERR           = 16            ; the printer's error that paused it
Q_BASE          = 17            ; the first job the desktop counts: after
                                ; the last one played when the queue ran
                                ; empty ("printing 2/5": job 2 of 5 since)
Q_INPAGE        = 18            ; $80: a StartPrint played, no StopPrint yet
Q_LEN           = 19
        .assert hdr + Q_LEN <= entry, error, "spool.s: hdr runs into entry"
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
                                ; GEOS 2.0, straight to the printer; tests);
                                ; $40 while the playback calls a driver
                                ; (module 110; FE_SPOOL 5 asks)

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
        .include "spooljob.inc"

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
        lda hdr + Q_JOBS        ; its number and its entry: the program's
        sta drvRec + 1          ; name, no pages yet
        sta jbuf + J_SEQ
        inc hdr + Q_JOBS
        ldx #NAME_LEN - 1
@nm:    lda taskName,x
        sta jbuf + J_NAME,x
        dex
        bpl @nm
        lda #0
        sta jbuf + J_FLAGS
        sta jbuf + J_PAGES
        lda drvRec + 1
        jsr JobPut
        lda spDrv               ; its driver: the slot it was kept in
        sta drvRec              ; (module 106)
        lda #T_DRIVER
        sta rqType
        lda #<drvRec
        sta rqSrc1
        lda #>drvRec
        sta rqSrc1+1
        lda #2
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
        cmp #T_START            ; a page: counted in the job's entry
        bne :+
        jsr Page
        lda rqType
:       cmp #T_ROW
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

; Page: the open job's pages + 1 (its entry). Destroys A, X, Y, r0-r3L.
Page:   ldx hdr + Q_JOBS
        dex
        txa
        pha
        jsr JobGet
        inc jbuf + J_PAGES
        pla
        jmp JobPut

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
; (Module 112 made room for it; Put's own check is a defence.)
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

Play:   jsr OvlCall             ; (module 113: a driver call's record)
        .byte 113, 0

; Step: the record at the tail played: T_DRIVER sets the driver's slot
; and the job; any other is a driver call (module 113). Played: the next
; pass asked for (taskReq $20). Paused: nothing (no next pass). Empty:
; the desktop's count starts again after the last job played (Q_BASE).
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
        ldx hdr + Q_PJOB
        inx
        cpx hdr + Q_BASE
        beq @idle
        stx hdr + Q_BASE
        jmp HeadSave
@idle:  rts
@work:  lda #<ptype
        ldx #>ptype
        jsr From
        lda #1
        ldx #0
        jsr Get
        lda ptype
        cmp #T_DRIVER
        bne @call
        lda #<(hdr + Q_PSLOT)   ; its slot and job
        ldx #>(hdr + Q_PSLOT)
        jsr From
        lda #2
        ldx #0
        jsr Get
        lda #0                  ; (no page of it started)
        sta hdr + Q_INPAGE
        jsr HeadSave
        lda taskReq             ; the next pass
        ora #$20
        sta taskReq
        rts
@call:  ldx ptype               ; the driver's entry, the data's lengths
        lda Entry - T_INIT,x
        sta runEntry
        lda #0
        sta runLen1
        sta runLen1+1
        sta runLen2
        cpx #T_ROW
        bcc @play
        cpx #T_ROWC + 1
        bcs @ascii
        lda #<ROW_LEN           ; a row: 640 bytes, with colours 80 more
        sta runLen1
        lda #>ROW_LEN
        sta runLen1+1
        cpx #T_ROWC
        bne @play
        lda #COL_LEN
        sta runLen2
        bne @play
@ascii: cpx #T_ASCII
        bne @play
        lda #<runLen1           ; a string: its length first
        ldx #>runLen1
        jsr From
        lda #1
        ldx #0
        jsr Get
@play:  jmp Play

; The entries by record type (T_INIT on): InitForPrint, StartPrint,
; PrintBuffer (twice), StopPrint, StartASCII, PrintASCII, SetNLQ.
Entry:  .byte 0, 3, 6, 6, 9, 18, 15, 21

        .endscope

; ======================================================================

        .segment "OVL110"
        .scope Mod110

        jmp Run                 ; entry 0 (module 113)
        jmp Skip                ; entry 3

        .include "spoolring.inc"

; Skip: the record's data (runLen1 + runLen2 bytes) passed over at the
; tail (compared, not fetched: nothing written in the C64).
Skip:   lda runLen1
        clc
        adc runLen2
        sta len
        lda runLen1+1
        adc #0
        sta len+1
        ldx #Q_TAIL
        ldy #REU_VERIFY
        jmp Xfer

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
        jsr Keep                ; (module 111: the scratch kept; this
                                ; module's bytes come anew: vec after)
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
        lda spOn                ; (a driver call played: FE_SPOOL 5
        ora #$40                ; names the job's program)
        sta spOn
        jsr Call
        txa                     ; (its X: the scratch, status's place,
        pha                     ; comes back with SwapOut)
        lda spOn
        and #$FF - $40
        sta spOn
        jsr SwapOut
        pla
        tax
        rts
Call:   jmp (vec)
SwapIn: jsr OvlCall             ; (module 111)
        .byte 111, 0
SwapOut:
        jsr OvlCall
        .byte 111, 3
Keep:   jsr OvlCall
        .byte 111, 6

vec:            .word 0

        .endscope

; ======================================================================

        .segment "OVL111"
        .scope Mod111

        jmp SwapIn              ; entry 0 (module 110)
        jmp SwapOut             ; entry 3
        jmp Keep                ; entry 6

; SwapIn: the program's driver area and AREA out to bank 27, the job's
; driver (its slot, Q_PSLOT) to $7900, its work area into AREA.
SwapIn: ldx #0
        jsr Op
        ldx #1
        jsr Op
        jsr Slot
        ldy #REU_FETCH
        jsr SysRAMOp
        ldx #2
        jmp Op

; Keep: the overlay scratch kept until SwapOut (module 110, just before
; the driver's call: the playback's state, the tail moved past the
; record's data; the file engine's work area, which a driver calling the
; engine uses: GU PDF).
Keep:   ldx #6
        jmp Op

; SwapOut: the driver back into its slot (its own variables last from
; call to call, as with a driver GEOS keeps loaded: found 2026-11-16 for
; GeoUltra's PDF driver; a driver keeping state in its memory lost it
; between played calls), the work area kept, the program's bytes back;
; first the scratch as it was before the call.
SwapOut:
        ldx #7                  ; the scratch back first (Slot reads hdr)
        jsr Op
        jsr Slot
        ldy #REU_STASH
        jsr SysRAMOp
        ldx #3
        jsr Op
        ldx #4
        jsr Op
        ldx #5
        jmp Op

; Slot: r0-r3 for SysRAMOp between $7900 and the job's driver slot
; (Q_PSLOT) in bank 1.
Slot:   lda #<DRV_ADDR
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
        rts

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
OpC64Lo:        .byte <DRV_ADDR, <AREA, <AREA, <AREA, <AREA, <DRV_ADDR, <SCR, <SCR
OpC64Hi:        .byte >DRV_ADDR, >AREA, >AREA, >AREA, >AREA, >DRV_ADDR, >SCR, >SCR
OpReuLo:        .byte <ST_DRV, <ST_AREA, <ST_WORK, <ST_WORK, <ST_AREA, <ST_DRV, <ST_SCR, <ST_SCR
OpReuHi:        .byte >ST_DRV, >ST_AREA, >ST_WORK, >ST_WORK, >ST_AREA, >ST_DRV, >ST_SCR, >ST_SCR
OpLenLo:        .byte <DRV_LEN, <AREA_LEN, <WORK_LEN, <WORK_LEN, <AREA_LEN, <DRV_LEN, <SCR_LEN, <SCR_LEN
OpLenHi:        .byte >DRV_LEN, >AREA_LEN, >WORK_LEN, >WORK_LEN, >AREA_LEN, >DRV_LEN, >SCR_LEN, >SCR_LEN
OpCmd:          .byte REU_STASH, REU_STASH, REU_FETCH, REU_STASH, REU_FETCH, REU_FETCH, REU_STASH, REU_FETCH

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

; Wait: A/X bytes (and a few to spare) to fit in the queue, and for a
; new job (entry 0: InitForPrint) an entry in the job table (JOB_MAX - 1
; jobs at most waiting): records played meanwhile (the program waits at
; the printer's pace, as without the spooler). Not when the queue is
; paused (a printer error) or empty and the call still larger than it.
; fits: 0 it fits, else not (the call is then dropped whole: module 107).
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
        bcs @full
        lda entry
        bne @fit
        lda hdr + Q_JOBS
        sec
        sbc hdr + Q_PJOB
        cmp #JOB_MAX - 1
        bcc @fit
@full:  bit hdr + Q_PAUSED
        bmi @no
        ldx #2                  ; empty: it fits if the room does (the
@e:     lda hdr + Q_HEAD,x      ; jobs: all played)
        cmp hdr + Q_TAIL,x
        bne @play
        dex
        bpl @e
        jsr Room
        bcs @no
@fit:   lda #0
        beq @end
@no:    lda #1
@end:   sta fits
        rts
@play:  jsr Step
        jmp @loop

        .endscope

; ======================================================================

        .segment "OVL113"
        .scope Mod113

        jmp Play                ; entry 0 (module 109)

RING_LOAD       = 1
RING_HEAD_ONLY  = 1
        .include "spoolring.inc"
        .include "spooljob.inc"

Run:    jsr OvlCall             ; (module 110: the driver called; X = its
        .byte 110, 0            ; status)
Skip:   jsr OvlCall             ; (module 110: the record's data passed
        .byte 110, 3            ; over)

; Play (module 109: the header in hdr, the record's type in ptype, the
; entry and lengths in runEntry, runLen1, runLen2): the driver called
; with the record's data. A cancelled job's record is
; skipped (its data passed over), and a page it had started ended
; (StopPrint, its status ignored). A StartPrint or StopPrint error
; pauses the queue (Q_PAUSED, Q_ERR) and keeps the record. Then the
; next pass asked for (taskReq $20).
Play:   lda hdr + Q_PJOB        ; a job played on after the queue ran empty
        sec                     ; (its pages came slower than the printer):
        sbc hdr + Q_BASE        ; counted from it again
        bpl :+
        lda hdr + Q_PJOB
        sta hdr + Q_BASE
:       jsr Cancelled
        bcc @run
        jsr Skip                ; cancelled: its data passed over
        bit hdr + Q_INPAGE
        bpl @done
        lda #0                  ; a page started: StopPrint
        sta hdr + Q_INPAGE
        sta runLen1
        sta runLen1+1
        sta runLen2
        lda #9
        sta runEntry
        jsr Run
        jmp @done
@run:   jsr Run
        lda ptype               ; StartPrint, StopPrint: their status
        ldy #$80
        cmp #T_START
        beq @st
        ldy #0
        cmp #T_STOP
        bne @done
@st:    txa
        bne @err
        sty hdr + Q_INPAGE
@done:  jsr HeadSave
        lda taskReq             ; the next pass
        ora #$20
        sta taskReq
        rts
@err:   stx status              ; an error: paused, the record kept
        jsr HeadLoad            ; (the header as it was)
        lda #$80
        sta hdr + Q_PAUSED
        lda status
        sta hdr + Q_ERR
        jmp HeadSave

; Cancelled: C set when the job playing (Q_PJOB) is cancelled (its entry
; still its own: J_SEQ). Destroys A, Y, r0-r3L.
Cancelled:
        lda hdr + Q_PJOB
        jsr JobGet
        lda jbuf + J_SEQ
        cmp hdr + Q_PJOB
        bne @no
        lda jbuf + J_FLAGS
        asl a
        rts
@no:    clc
        rts

        .endscope

; ======================================================================

        .segment "OVL114"
        .scope Mod114

        jmp FeSpool             ; entry 0 (FE_SPOOL, the file engine)

; FE_SPOOL (docs/FILE_ENGINE.md; the desktop's indicator and queue
; window): Y = 0: A = the job printing, counted from Q_BASE (0: the
; queue empty), r0L the jobs since then, r0H $80 paused, r1L the
; printer's error that paused it. 1: pause. 2: resume (the error
; forgotten). 3: job r0L cancelled. 4: the jobs not yet printed (the
; one printing first; JOB_MAX at most) to r0, J_LEN bytes each (spool.s
; J_*); A = their count. 5: the name of the program that printed, to r0
; (NAME_LEN bytes: the job's when a driver call is played, spOn $40,
; else the task's: a printer driver's, GU PDF's file name). X = 0. Own
; buffers (the engine's work area is in use, the spooler's scratch
; overlaps it).
FeSpool:
        sty sub
        ldy #REU_FETCH
        jsr HeadOp
        ldx #3
@m:     lda qh,x
        cmp Mark,x
        bne NoQueue
        dex
        bpl @m
Known:  lda sub
        beq Status
        cmp #2
        bcc @pause
        beq @resume
        cmp #4
        beq @list
        bcs @name
        jmp Cancel              ; (3)
@list:  jmp List
@name:  jmp Name                ; (5)
@pause: lda #$80
        sta qh + Q_PAUSED
        bne Save
@resume:
        lda #0
        sta qh + Q_PAUSED
        sta qh + Q_ERR
        jsr Again
Save:   ldy #REU_STASH
        jsr HeadOp
Done:   lda #0
        tax
        rts
NoQueue:                        ; (no queue yet, VICE: an empty one, as
        ldx #::Q_LEN - 1        ; HeadLoad makes it)
        lda #0
@z:     sta qh,x
        dex
        bpl @z
        ldx #3
@k:     lda Mark,x
        sta qh,x
        dex
        bpl @k
        lda #RING0
        sta qh + Q_HEAD + 1
        sta qh + Q_TAIL + 1
        ldy #REU_STASH
        jsr HeadOp
        jmp Known

; Status (Y = 0): see FeSpool.
Status: lda qh + Q_PAUSED
        and #$80
        sta argR0+1
        lda qh + Q_ERR
        sta argR1
        lda #0
        sta argR0
        jsr Empty
        lda #0
        bcs @out
        lda qh + Q_JOBS         ; the jobs since Q_BASE
        sec
        sbc qh + Q_BASE
        sta argR0
        jsr First               ; the one printing: its place among them
        sec
        sbc qh + Q_BASE
        clc
        adc #1
        cmp argR0               ; (at most all of them)
        bcc @out
        lda argR0
@out:   ldx #0
        rts

; Cancel (Y = 3): job r0L's entry marked (when it is still its own); the
; playback asked for (it passes the job over).
Cancel: lda argR0
        jsr JobOp0
        lda jb + J_SEQ
        cmp argR0
        bne @end
        lda jb + J_FLAGS
        ora #$80
        sta jb + J_FLAGS
        ldy #REU_STASH
        lda argR0
        jsr JobOp
        jsr Again
@end:   lda #0
        tax
        rts

; List (Y = 4): see FeSpool.
List:   lda #0
        sta cnt
        jsr Empty
        bcs @end
        lda argR0
        sta dst
        lda argR0+1
        sta dst+1
        jsr First
        sta seq
@next:  lda seq
        cmp qh + Q_JOBS
        beq @end
        lda cnt
        cmp #JOB_MAX
        bcs @end
        lda dst
        sta r0L
        lda dst+1
        sta r0H
        ldy #REU_FETCH
        lda seq
        jsr JobAt
        clc
        lda dst
        adc #J_LEN
        sta dst
        bcc :+
        inc dst+1
:       inc seq
        inc cnt
        bne @next
@end:   lda cnt
        ldx #0
        rts

; Name (Y = 5): see FeSpool.
Name:   lda #<taskName
        ldx #>taskName
        bit spOn
        bvc @copy
        lda qh + Q_PJOB
        jsr JobOp0
        lda #<(jb + J_NAME)
        ldx #>(jb + J_NAME)
@copy:  sta r1L
        stx r1H
        lda argR0
        sta r2L
        lda argR0+1
        sta r2H
        ldy #NAME_LEN - 1
:       lda (r1),y
        sta (r2),y
        dey
        bpl :-
        jmp Done

; First: A = the first job not yet printed: the one playing, or Q_BASE
; when that one was before it (a job not yet begun).
First:  lda qh + Q_PJOB
        sec
        sbc qh + Q_BASE
        bpl :+
        lda qh + Q_BASE
        rts
:       lda qh + Q_PJOB
        rts

; Empty: C set when the queue holds no record.
Empty:  ldx #2
@c:     lda qh + Q_HEAD,x
        cmp qh + Q_TAIL,x
        bne @no
        dex
        bpl @c
        sec
        rts
@no:    clc
        rts

; Again: the playback asked for at MainLoop's end.
Again:  lda taskReq
        ora #$20
        sta taskReq
        rts

; HeadOp: Y = REU command: the header <-> qh.
HeadOp: lda #<qh
        sta r0L
        lda #>qh
        sta r0H
        lda #<QHEAD
        sta r1L
        lda #>QHEAD
        sta r1H
        lda #Q_LEN
        bne Sys

; JobOp0 / JobOp: job A's entry <-> jb (JobOp0: fetched; JobOp: Y the
; command). JobAt: the same into r0.
JobOp0: ldy #REU_FETCH
JobOp:  pha
        lda #<jb
        sta r0L
        lda #>jb
        sta r0H
        pla
JobAt:  and #JOB_MAX - 1
        asl a
        asl a
        asl a
        asl a
        sta r1L
        lda #>JOBTAB
        sta r1H
        lda #J_LEN
Sys:    sta r2L
        lda #0
        sta r2H
        lda #SYS_BANK
        sta r3L
        jmp SysRAMOp

Mark:   .byte "GUSP"
sub:    .byte 0
seq:    .byte 0
cnt:    .byte 0
dst:    .word 0
qh:     .res ::Q_LEN
jb:     .res ::J_LEN

        .endscope
