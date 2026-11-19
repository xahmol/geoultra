; GeoUltra Settings: overlays (docs/SETTINGS.md, "Structure"). The
; application is a VLIR file: record 0 the core at $0400-$4FFF, records
; 1 to OVL_N one page each at TRANS ($5000-$5FFF): 1 the Desktop page
; (pdesk.s) and the Printing page (pprint.s), 2 the Pointer page (pptr.s), 3 the System page (psys.s), 4 the Time page (ptime.s), 5 the Theme page (ptheme.s);
; the other pages follow in their steps. The loader and
; OvlGo are ovlcore.inc (shared with gush and the desktop); this file
; names the bank and the stubs. Own code.

        .include "geos.inc"
        .include "settings.inc"

TRANS           = $5000
TRANS_SIZE      = $1000
OVL_BANK        = 7             ; the application's REU bank 7 (drive E's
                                ; programs each rebuild their REU state)
OVL_N           = 8

        .segment "CODE"

        .include "ovlcore.inc"  ; (the loader, OvlGo, the Stub macro)

; OvlFail: a stub without the overlays (their records could not be
; read at the start): nothing happens.
OvlFail:
        rts

        Stub DeskDraw, 1        ; overlay 1: pdesk.s
        Stub DeskPress, 1
        Stub PrintDraw, 1       ; (pprint.s, the Printing page)
        Stub PrintPress, 1
        Stub PtrDraw, 2         ; overlay 2: pptr.s
        Stub PtrPress, 2
        Stub SerDraw, 2         ; (pser.s, the Serials page)
        Stub SerPress, 2
        Stub SysDraw, 3         ; overlay 3: psys.s
        Stub SysPress, 3
        Stub TimeDraw, 4        ; overlay 4: ptime.s
        Stub TimePress, 4
        Stub ThemeDraw, 5       ; overlay 5: ptheme.s
        Stub ThemePress, 5
        Stub ReuDraw, 6         ; overlay 6: preu.s
        Stub ReuPress, 6
        Stub DriveDraw, 7       ; overlay 7: pdrives.s
        Stub DrivePress, 7
        Stub StartDraw, 8       ; overlay 8: pstart.s
        Stub StartPress, 8
