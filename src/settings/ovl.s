; GeoUltra Settings: overlays (docs/SETTINGS.md, "Structure"). The
; application is a VLIR file: record 0 the core at $0400-$4FFF, records
; 1 to OVL_N one page each at TRANS ($5000-$5FFF): 1 the Desktop page
; (pdesk.s), 2 the Pointer page (pptr.s), 3 the System page (psys.s);
; the other pages follow in their steps. The loader and
; OvlGo are ovlcore.inc (shared with gush and the desktop); this file
; names the bank and the stubs. Own code.

        .include "geos.inc"
        .include "settings.inc"

TRANS           = $5000
TRANS_SIZE      = $1000
OVL_BANK        = 7             ; the application's REU bank 7 (drive E's
                                ; programs each rebuild their REU state)
OVL_N           = 3

        .segment "CODE"

        .include "ovlcore.inc"  ; (the loader, OvlGo, the Stub macro)

; OvlFail: a stub without the overlays (their records could not be
; read at the start): nothing happens.
OvlFail:
        rts

        Stub DeskDraw, 1        ; overlay 1: pdesk.s
        Stub DeskPress, 1
        Stub PtrDraw, 2         ; overlay 2: pptr.s
        Stub PtrPress, 2
        Stub SysDraw, 3         ; overlay 3: psys.s
        Stub SysPress, 3
