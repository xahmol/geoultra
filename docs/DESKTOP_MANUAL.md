# The GeoUltra desktop: user manual

GeoUltra's own desktop is what you see after the start: a file manager
for the GEOS drives and the Ultimate's own file system, and the place
programs are started from. It is still being built (docs/DESKTOP.md has
the plan and the state of the work); this manual describes what is
there now. GEOS 2.0's own deskTop can still be used instead:
`SETTINGS.INI`, `[system] desktop=geos` (see "Settings").

## The screen

From top to bottom:

- **The menu bar**: the menus geos (GeoUltra info, settings, gush and
  the desk accessories), file, view, go and disk on the left, the date and time
  on the right (unless the theme or the clock setting leaves them out).
  Everything the toolbar does is in the menus too.
- **The toolbar** (view > toolbar): buttons for the things done most,
  in four groups (see "The toolbar").
- **The sidebar** on the left: the drives, the Ultimate's roots, your
  favourite folders and your recent documents.
- **The list** on the right: the title bar with the current folder's
  name, the path line, and the folder's entries; a scroll strip on the
  right edge.
- **The status line** at the bottom: how many entries there are, how
  many are selected, and the free space on the drive.

The list is sorted: ".." (the folder above) first, then folders and
drives, then files, each group by name; upper and lower case are the
same for the order. (Folders with more than 384 entries keep the order
they have on disk.)

## Views

view > view chooses how the list shows the entries (the toolbar's view
button goes through them in turn):

- **list**: a small icon and the name, one entry a row;
- **icons**: a grid of large icons with the name under each (5 columns,
  6 with the narrow sidebar). GEOS files show their own icon from their
  file header; folders, drives, plain files and disk images show
  GeoUltra's own;
- **detailed**: the list with the size and the date (GEOS files) beside
  each name.

## Two panes

view > two panes (C=P, or the toolbar's button between view and
refresh) shows two folders side by side, the sidebar hidden. Each pane
has its own folder, list, selection, scroll strip and half of the status
line (its entries, or the number selected, and its drive's free space);
the active pane's path line is inverted, and the menus, keys and toolbar act on it. A
click in a pane, or C=SPACE, makes it the active one. The panes show the
list or the icon view (the detailed view's columns do not fit). The
same keys and menu switch back to one list, with the view from before.
Copying between the panes: "copy to other" (C=T) and "move to other"
(C=M) in the file menu and the context menu put the selection into the
other pane's folder (they use the clipboard: it holds those entries
afterwards); or copy (or cut) in one pane and paste in the other.

**Drag and drop:** press on a selected entry and move the mouse with
the button held: the selection is dragged (its icon follows the
pointer). Released over the other pane, it goes into that pane's
folder: moved on the same drive, copied to another drive. Released
over a folder in the same list (one that is not part of the
selection), it is moved into that folder; while you drag, the folder or
sidebar line the selection would go into is shown inverted (not in the
icon view). Released over a drive or a
favourite in the sidebar (with one list), it goes into that drive's
top folder or that favourite folder: moved on the same drive, copied to
another. Hold C= while releasing to copy instead of move (or move
instead of copy). Folders are taken with everything in them.

## Moving around

- **Mouse**: a click on an entry selects it (the others no longer); C=
  and a click adds it or takes it away again; SHIFT and a click selects
  everything from the cursor to it. A double click opens the entry.
- **Keys**: cursor up and down move the cursor (C= held: the selection
  grows with it), HOME goes to the first entry, RETURN opens the entry
  under the cursor, cursor left goes up a folder; C= and cursor left or
  right go back or forward through the folders visited.
- **The go menu**: back, forward, up, root (all drives), home
  (GeoUltra's folder on the Ultimate), top and end.
- **Sidebar**: a click on a drive or an Ultimate root goes there; a
  click on a favourite goes to that folder; a click on a recent document
  opens it.
- **Path line**: a click on a part of the path goes to that folder.
- **Scroll strip**: the arrows move the list a row (in the icon view a
  row of icons), a click above or below the thumb a page.

Opening an entry:

- a **folder** or **drive**: goes into it;
- a GEOS **application** or **desk accessory**: starts it; a **document**
  starts the application it belongs to with it;
- a **disk image** on the Ultimate (`.d64`, `.d71`, `.d81`, `.dnp`):
  mounts it, asking on which drive (A-D);
- any **other file on the Ultimate**: is not opened (see "Drives: what
  works where").

## Files and folders

All in the file menu, with their keys:

| Action | Key | |
| --- | --- | --- |
| open | C=O | as a double click |
| info | C=I | see below |
| copy | C=C | the selected entries (or the one under the cursor) onto the clipboard |
| cut | C=X | the same, to be moved |
| paste | C=V | copies (or moves) the clipboard's entries into the current folder; asks before replacing a file (Yes, Yes to all, No) |
| delete | DEL | asks first; a folder with everything in it asks once more |
| rename | C=R | |
| new folder | C=N | on drives with folders (native drives, 1581 partitions, the Ultimate) |
| select all | C=A | every entry but ".." |
| favourite | C=F | the current folder (or the selected folder) into the sidebar's favourites (up to 4; the oldest goes) |

GeoUltra's shell, gush, is in the geos menu (C=G, and the toolbar's
last button): it takes the desktop's place (docs/GUSH_MANUAL.md).

Folders are copied, moved and deleted with everything in them. A long
copy shows its progress on the status line; RUN/STOP stops it.

**The right mouse button** opens a menu at the pointer with open, copy,
cut, paste, rename, delete, info, favourite and new folder. Over an
entry that is not selected yet, it selects that entry first. A click on
an item does it; a click outside the menu, RUN/STOP, ESC or the right
button again closes it. (On a 1351 the right button is the one GEOS
programs do not use; the Ultimate 64's USB mouse works as one.)

**Info** (in that menu, and the toolbar's info button) shows the entry
under the cursor: its name, kind (for GEOS files their type:
application, document, desk accessory, font, printer or input driver
...), size, date and GEOS class. For files on the Ultimate it reads the
size, which the folder listing does not have.

## The toolbar

Under the menu bar, in five groups:

| Buttons | |
| --- | --- |
| back, forward, up, root | the folders visited before and after (the last 16), the folder above, `/` (all drives) |
| top, end | the first and the last entry |
| view, two panes, refresh | the next view; one list or two panes; the folder read again |
| new folder, info, select all, copy, paste, delete | as in the file menu; info as in the context menu |
| settings, gush | GeoUltra Settings (see "Settings"), GeoUltra's shell |

view > toolbar sets its height: **two lines** (framed buttons, the
default), **one line** (the icons alone, one more row for the list) or
**off**.

## Disk images and drives

Drives A to D hold disk images from the Ultimate (they are kept in the
REU while mounted, and changes are written back to the image file).
Opening an image on the Ultimate mounts it: choose the drive in the
dialog. The eject icon on a drive's line in the sidebar unmounts it
(after writing it back). Which images are mounted at the start is in
`GEOULTRA/MOUNTS.INI` (`A=/USB0/path/image.d81`, one line per drive).

## Drives: what works where

| Kind of drive | What it is | Programs and documents | Folders | Writing |
| --- | --- | --- | --- | --- |
| A-D: D64, D71 | a 1541 or 1571 disk image | start and open | no | yes |
| A-D: D81 | a 1581 disk image | start and open | 1581 partitions act as folders | yes |
| A-D: DNP | a native (CMD) disk image (up to 16 MB as a format; the REU holds about 10 MB for all mounted drives together) | start and open | yes, nested | yes |
| E | GeoUltra's system drive in the cartridge (gush, geoFolder, the desktop, gush's commands) | start | yes | no: read-only |
| usb0, usb1, sd | the Ultimate's own file system (the USB sticks, the SD card) | **not** started or opened | yes | yes |

What this means in practice:

- **GEOS programs and documents only work on drives A-E.** On the
  Ultimate's file system a GEOS file is kept in CVT form (a single file
  holding the whole GEOS file); opening it there shows "Not opened
  here". Copy it to one of the drives A-D first.
- **Copying between them converts.** A GEOS file copied onto the
  Ultimate becomes `name.cvt`; a `.cvt` copied onto a GEOS drive becomes
  the GEOS file again. Plain CBM files get `.prg`, `.seq` or `.usr` on
  the Ultimate and lose it again on the way back. gush's `cp` does the
  same.
- **Disk images on the Ultimate** are opened by mounting them on A-D.
- **Sizes**: the Ultimate's listings give no sizes, so the detailed
  view leaves them empty for files there; Info shows a file's size.
- **Real disk drives** on the serial bus are not supported yet.

## Themes

view > theme chooses the look: **GeoUltra** (the default), **GEOS
classic**, **Flat**, **Detailed**, **Night**, **Mono**, and **Custom**
(to edit). Each is a text file in `GEOULTRA/THEMES` on the stick, one
line per part of the screen, in words, for example:

```
[theme]
name=Custom
border=light grey
desk=dark grey on light grey
menubar=clock, dark grey on light grey
sidebar=wide, dark grey on light grey
headings=inverted, white on light blue
titlebar=stripes, dark grey on light grey
rows=9
columns=name
icons=on, blue
selection=invert, white on blue
cursor=dotted, blue
scrollbar=arrows
status=on, white on grey
toolbar=dark grey on light grey
```

"X on Y" is X text on a Y background. The styles each part takes:
menubar plain or clock; sidebar wide or narrow; headings inverted, band,
underlined or plain; titlebar stripes, solid, line or none; rows 9 or 8;
columns name or detailed; icons on or off; selection invert, bar or
frame; cursor dotted, mark or underline; scrollbar arrows or thin;
status on or off. A file needs only the lines it changes. On an Ultimate
64 a theme may also set the 16 colours themselves: `palette=` and 16
RRGGBB values (black ... light grey), as in the Night theme's file. The
desktop's menus and dialogs take the menu bar's colours; programs and
desk accessories keep GEOS's own.

## Settings

The desktop keeps its settings in `GEOULTRA/SETTINGS.INI` on the stick
(written when you change them in the menus):

```
[desktop]
theme=GeoUltra
view=list            (list, icons, detailed)
clock=24             (24, 12, off)
toolbar=16           (16: two lines, 8: one line, off)
panes=1              (1: one list, 2: two panes)

[favourites]
/usb0/geoultra
```

`RECENT.INI` holds the recent documents. Other sections of
`SETTINGS.INI` belong to the system (`[system] desktop=geos` starts
GEOS 2.0's deskTop instead of this one).

**GeoUltra Settings** (geos > settings, or the toolbar's settings
button; in gush: `"/e/GU Settings"`) changes these without editing the
file: a list of pages on the left, the page on the right, OK (save and
leave), Cancel (leave; it asks when something was changed) and Save
(save and stay). Its first page is **Desktop**: which desktop starts
(GeoUltra's or GEOS 2.0's), the view, the toolbar, the clock and two
panes; they take effect when the desktop starts again (after OK).
**System**: the turbo (full speed, off, or a speed step chosen with
- and +, shown in MHz for both kinds of Ultimate 64; it changes at
once), the programs that run at 1 MHz (add... picks a program on
drives A-D; remove takes the selected one out) and how long the
system waits without input before it hibernates (off, 15 s, 30 s,
1 min, 5 min). **Time**: the time server (click the box to type it),
"now" to set the clock from it (it saves the settings first), the time
zone in quarter hours, summer time by the EU's rule or off, and the
date and time by hand (set..., typed as YYYY-MM-DD HH:MM). The server
also sets the clock at every start. **Pointer** chooses the mouse
pointer: classic arrow, large arrow, hand
or crosshair; it changes at once and stays at every start. The other
pages (theme, system with turbo and the time, drives, REU) follow;
their plan is in docs/SETTINGS.md.

## Limits

- Folders with more than 384 entries are shown in the order on disk;
  a folder holds at most 2048 entries in the list.
- The icon view keeps the first 448 entries' icons in the REU; later
  ones are read again when shown.
