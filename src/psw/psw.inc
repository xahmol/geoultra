; GU PostScript (docs/DESIGN.md "PostScript writer"; docs/PSW.md): a
; geoWrite 2.x document as a PostScript file in GEOULTRA/print. The
; layout and the text written are tools/gwps.py's (gwtool ps), the
; reference the tests compare with byte for byte. Shared definitions.
; Own code (GeoUltra, 2026).

; --- GEOS 2.0 jump table and variables (HG2G; docs/GEOS_API_REFERENCE.md)
UseSystemFont   = $C14B
DoDlgBox        = $C256
EnterDeskTop    = $C22C
OpenRecordFile  = $C274
CloseRecordFile = $C277
PointRecord     = $C280
ReadRecord      = $C28C
fileHeader      = $8100
dataFileName    = $8442
dataDiskName    = $8453
curDrive        = $8489
guExtTable      = $C0E4         ; GeoUltra: the extension table
FE_ENTRY        = 30            ; the file engine: guExtTable + 30
CPU_PORT        = $01

r0L = $02
r0H = $03
r1L = $04
r1H = $05
r2L = $06
r2H = $07
r3L = $08
r3H = $09
r5L = $0C
r5H = $0D
r7L = $10
r7H = $11
r10L = $16
r10H = $17
baselineOffset  = $26
curSetWidth     = $27           ; word
curHeight       = $29
curIndexTable   = $2A           ; word
cardDataPntr    = $2C           ; word

; --- The file engine (docs/FILE_ENGINE.md)
FE_OPEN         = 13
FE_WRITE        = 15
FE_CLOSE        = 4
FE_MKDIR        = 8
FE_HOME         = 26
FO_WRITE        = 1

; --- Dialogs
DEF_DB_POS      = $80
OK              = 1
CANCEL          = 2
DBTXTSTR        = 11
DBVARSTR        = 12
DBGETFILES      = 16
TXT_LN_X        = 16
TXT_LN_1_Y      = 16
TXT_LN_2_Y      = 32
DBI_X_0         = 1
DBI_X_2         = 17
DBI_Y_2         = 88
APPL_DATA       = 7             ; GEOS file type (geoWrite documents)

; --- geoWrite's text (Michael Steil, "Inside geoWrite - 7")
ESC_GRAPHICS    = $10
ESC_RULER       = $11
ESC_NEWCARDSET  = $17
TAB             = $09
PAGE_BREAK      = $0C
CR              = $0D
R_LEFT          = 1             ; a ruler's fields (offsets in the escape)
R_RIGHT         = 3
R_TABS          = 5
R_PARA          = 21
R_FLAGS         = 23
RULER_LEN       = 27
PAGES           = 61            ; records 0-60 pages, 61 header, 62 footer
HEADER_REC      = 61
FOOTER_REC      = 62

; --- Token kinds (layout.s Token)
T_END           = 0             ; the record's end (or a zero byte)
T_CHAR          = 1
T_TAB           = 2
T_CR            = 3             ; (also a page break: both end the line)
T_RULER         = 4
T_FONT          = 5
T_PIC           = 6
T_SKIP          = 7             ; (a control code geoWrite does not use)

; --- Styles (the NewCardSet byte)
UNDERLINE       = $80
BOLD            = $40
REVERSE         = $20
ITALIC          = $10
OUTLINE         = $08
CELL_STYLES     = BOLD | UNDERLINE | REVERSE | OUTLINE   ; what a glyph cell shows
LEADING         = 2             ; dots under each line (gwps LEADING)
PIC_DOWN        = 2             ; a picture 2 rows up into the line above

; --- Memory ($0400 the application; buffers above it)
PAGEBUF         = $2C00         ; a page record (geoWrite: 7000 bytes at most)
PAGE_MAX        = $1B60
HEADBUF         = $4760         ; the header record
FOOTBUF         = $4960         ; the footer record
HF_MAX          = $0200
FONTBUF         = $4B60         ; a font image (the system font's copy)
FONT_MAX        = $0800
OUTBUF          = $5360         ; the output's buffer, written when full
OUT_MAX         = $0100
LINE_MAX        = 255           ; characters a line keeps (one byte index)
CHX_LO          = $5460         ; per character of the line being laid out:
CHX_HI          = $5560         ; x, width, code, its combination (font and
CHW             = $5660         ; style), and where it was in the page
CHC             = $5760
CHK             = $5860
PICBUF          = $6000         ; a picture record (compacted): the background
PIC_MAX         = $1F40         ; screen's place, unused (dialogs draw on the
                                ; foreground only, dispBufferOn)

; --- Zero page ($80-$FA: the application's, docs/GEOSLIB_MANUAL.md)
tp              = $80           ; word: the token pointer in a record
op              = $82           ; word: a pointer for strings and tables
rp              = $84           ; word: the ruler in force (0: none)
n24             = $86           ; 3 bytes: a number to print / work value
tmp             = $89           ; 2 bytes
gp              = $8B           ; word: glyph data pointer
