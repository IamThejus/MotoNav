"""
MotoNav Pico 2 W — Tripper-style Navigation UI
State-driven partial redraw: only changed regions are updated.
Never clears the full screen after initial draw.

Packet format (9 bytes, header 'TN' = 0x54 0x4E):
  [2]      sign + 10  (uint8)
  [3..4]   dist to turn (uint16 BE, metres)
  [5..6]   remaining (uint16 BE, x100m)
  [7]      next sign + 10
  [8]      speed km/h

Wiring:
  SPI1 SCK->GP10  MOSI->GP11  DC->GP8  CS->GP9  RST->GP12  BL->GP13
"""

import gc9a01
import bluetooth
import micropython
import struct
import sys
import time
from machine import Pin, SPI

sys.path.append('/fonts')
import vga1_16x32 as font_large
import vga1_8x16  as font_small

# ─────────────────────────────────────────────────────────────────────────
# Hardware
# ─────────────────────────────────────────────────────────────────────────
try:
    led = Pin("LED", Pin.OUT)
    led.value(0)
except Exception:
    led = None

def _led(v):
    if led: led.value(v)

spi = SPI(1, baudrate=40_000_000, polarity=0, phase=0, sck=Pin(10), mosi=Pin(11))
tft = gc9a01.GC9A01(
    spi,
    dc=Pin(8,  Pin.OUT),
    cs=Pin(9,  Pin.OUT),
    reset=Pin(12, Pin.OUT),
    backlight=Pin(13, Pin.OUT),
    rotation=0,
)

# ─────────────────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────────────────
BLACK  = gc9a01.color565(0,   0,   0)
WHITE  = gc9a01.color565(255, 255, 255)
RED    = gc9a01.color565(220, 40,  40)
GREY   = gc9a01.color565(80,  80,  80)
LGREY  = gc9a01.color565(160, 160, 160)
DGREY  = gc9a01.color565(30,  30,  30)
GREEN  = gc9a01.color565(0,   200, 80)
YELLOW = gc9a01.color565(240, 190, 0)
BG     = BLACK

CX = 120
CY = 120

# ─────────────────────────────────────────────────────────────────────────
# Screen regions  (x, y, w, h)
# Only these rectangles are ever redrawn after the initial fill.
# ─────────────────────────────────────────────────────────────────────────
R_STATUS    = (0,   4,  240, 24)
R_BAR       = (30,  32, 180,  7)
R_ARROW     = (40,  44, 160, 104)
R_DIVIDER   = (30, 152, 180,  2)
R_TURN_DIST = (20, 157, 200, 44)
R_NEXT      = (10, 204,  60, 34)
R_TRIP      = (75, 206, 160, 30)

_AX, _AY = 120, 96   # arrow bitmap centre

# ─────────────────────────────────────────────────────────────────────────
# UI state
# ─────────────────────────────────────────────────────────────────────────
ui = {
    'sign':   0,
    'dist_m': 0,
    'rem_m':  0,
    'speed':  0,
    'nxt':    0,
    'conn':   False,
}
_prev = {}

# ─────────────────────────────────────────────────────────────────────────
# Font rendering helper
# ─────────────────────────────────────────────────────────────────────────
def _text_c(font, s, cx, y, fg, bg=None):
    """Draw text centred at cx using the given font."""
    tft.text(font, s, cx - len(s) * font.WIDTH // 2, y, fg, bg or BG)

# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────
def _clr(region, color=None):
    tft.fill_rect(region[0], region[1], region[2], region[3], color or BG)

_SIGN_KEYS = {
    -3:'sign_m3', -2:'sign_m2', -1:'sign_m1',
     0:'sign_0',   1:'sign_1',   2:'sign_2',
     3:'sign_3',   4:'sign_4',
}

def _blit(sign, cx, cy, prefix, size):
    path = '/arrows/{}_{}.bin'.format(prefix, _SIGN_KEYS.get(sign, 'sign_0'))
    x = cx - size // 2
    y = cy - size // 2
    try:
        with open(path, 'rb') as f:
            tft.blit_buffer(f.read(), x, y, size, size)
    except OSError:
        tft.fill_rect(x, y, size, size, GREY)

# ─────────────────────────────────────────────────────────────────────────
# Per-region draw functions
# ─────────────────────────────────────────────────────────────────────────
def draw_status():
    _clr(R_STATUS)
    dot = GREEN if ui['conn'] else GREY
    tft.fill_rect(16, 10, 10, 10, dot)
    _text_c(font_small, '{} km/h'.format(ui['speed']), CX, R_STATUS[1] + 4, WHITE)


def draw_bar():
    rx, ry, rw, rh = R_BAR
    tft.fill_rect(rx, ry, rw, rh, DGREY)
    d = ui['dist_m']
    if d > 0:
        ratio = min(1.0, d / 400.0)
        fill  = int(rw * ratio)
        color = GREEN if ratio > 0.5 else (YELLOW if ratio > 0.2 else RED)
        tft.fill_rect(rx, ry, fill, rh, color)


def draw_arrow():
    _clr(R_ARROW)
    _blit(ui['sign'], _AX, _AY, 'large', 80)
    if ui['dist_m'] < 100:
        rx, ry, rw, rh = R_ARROW
        tft.rect(rx, ry, rw, rh, RED)


def draw_turn_dist():
    _clr(R_TURN_DIST)
    m  = ui['dist_m']
    ty = R_TURN_DIST[1] + (R_TURN_DIST[3] - font_large.HEIGHT) // 2
    if m < 1000:
        s = '{} m'.format(m)
    else:
        km10 = round(m / 100)
        s = '{}.{} km'.format(km10 // 10, km10 % 10)
    _text_c(font_large, s, CX, ty, WHITE)


def draw_next():
    _clr(R_NEXT)
    _blit(ui['nxt'], R_NEXT[0]+18, R_NEXT[1]+17, 'small', 36)


def draw_trip():
    _clr(R_TRIP)
    s  = '{} km'.format(ui['rem_m'])
    ty = R_TRIP[1] + (R_TRIP[3] - font_small.HEIGHT) // 2
    _text_c(font_small, s, R_TRIP[0] + R_TRIP[2] // 2, ty, LGREY)


def draw_divider():
    tft.fill_rect(R_DIVIDER[0], R_DIVIDER[1], R_DIVIDER[2], R_DIVIDER[3], GREY)

# ─────────────────────────────────────────────────────────────────────────
# Initial full draw — once only
# ─────────────────────────────────────────────────────────────────────────
def draw_all():
    tft.fill(BG)
    draw_status()
    draw_bar()
    draw_arrow()
    draw_divider()
    draw_turn_dist()
    draw_next()
    draw_trip()
    _prev.update(ui)

# ─────────────────────────────────────────────────────────────────────────
# Partial update engine
# ─────────────────────────────────────────────────────────────────────────
def render_updates():
    sign_changed  = _prev.get('sign')  != ui['sign']
    nxt_changed   = _prev.get('nxt')   != ui['nxt']
    conn_changed  = _prev.get('conn')  != ui['conn']
    speed_changed = _prev.get('speed') != ui['speed']

    prev_bucket = _prev.get('rem_m', 0)   # already km, bucket = 1 km
    curr_bucket = ui['rem_m']
    trip_changed = prev_bucket != curr_bucket

    was_close = _prev.get('dist_m', 999) >= 100
    now_close = ui['dist_m'] < 100

    if sign_changed or (was_close and now_close):
        draw_arrow()

    draw_bar()
    draw_turn_dist()

    if nxt_changed:   draw_next()
    if trip_changed:  draw_trip()
    if conn_changed or speed_changed: draw_status()

    _prev.update(ui)

# ─────────────────────────────────────────────────────────────────────────
# Waiting screen
# ─────────────────────────────────────────────────────────────────────────
def draw_waiting():
    tft.fill(BLACK)
    tft.line(CX-22, CY-12, CX-22, CY+12, GREY)
    tft.line(CX-22, CY-12, CX,    CY+6,  GREY)
    tft.line(CX,    CY+6,  CX+22, CY-12, GREY)
    tft.line(CX+22, CY-12, CX+22, CY+12, GREY)
    for i in range(3):
        tft.fill_rect(CX-10+i*10, CY+28, 5, 5, GREY)

# ─────────────────────────────────────────────────────────────────────────
# BLE  (uses micropython.schedule so IRQ never touches the display directly)
# ─────────────────────────────────────────────────────────────────────────
SERVICE_UUID = bluetooth.UUID('12345678-1234-1234-1234-123456789abc')
CHAR_UUID    = bluetooth.UUID('abcd1234-5678-90ab-cdef-123456789abc')
_IRQ_CONNECT    = 1
_IRQ_DISCONNECT = 2
_IRQ_WRITE      = 3
_FLAG_WRITE     = 0x0008
_FLAG_WRNR      = 0x0004

_pkt         = None
_char_handle = None


def _schedule_rx(raw):
    global _pkt
    _pkt = bytes(raw)


def _irq(event, data):
    if event == _IRQ_CONNECT:
        ui['conn'] = True
        _led(1); time.sleep_ms(300); _led(0)
        print('BLE connected')
    elif event == _IRQ_DISCONNECT:
        ui['conn'] = False
        print('BLE disconnected')
        try: ble.gap_advertise(100_000, adv_data=_adv)
        except: pass
    elif event == _IRQ_WRITE:
        if _char_handle is None: return
        _, h = data
        if h == _char_handle:
            micropython.schedule(_schedule_rx, ble.gatts_read(_char_handle))


def _make_adv(name):
    nb = name.encode()
    return bytes([2, 0x01, 0x06, len(nb)+1, 0x09]) + nb


_adv = _make_adv('MotoNav')
draw_waiting()

try:
    ble = bluetooth.BLE()
    ble.active(True)
    ble.irq(_irq)
    _handles     = ble.gatts_register_services([
        (SERVICE_UUID, [(CHAR_UUID, _FLAG_WRITE | _FLAG_WRNR)])
    ])
    _char_handle = _handles[0][0]
    ble.gap_advertise(100_000, adv_data=_adv)
    print('BLE advertising as MotoNav')
except Exception as e:
    print('BLE init error:', e)

# ─────────────────────────────────────────────────────────────────────────
# Main loop
# ─────────────────────────────────────────────────────────────────────────
_ready   = False
_last_ms = 0
_frame   = 0

while True:
    try:
        pkt  = _pkt
        _pkt = None

        if pkt is not None and len(pkt) >= 9 and pkt[0] == 0x54 and pkt[1] == 0x4E:
            ui['sign']   = pkt[2] - 10
            ui['dist_m'] = struct.unpack_from('>H', pkt, 3)[0] * 10   # ×10 m units
            ui['rem_m']  = struct.unpack_from('>H', pkt, 5)[0]        # km units
            ui['nxt']    = pkt[7] - 10
            ui['speed']  = pkt[8]

            if not _ready:
                draw_all()
                _ready = True
            else:
                render_updates()

            _last_ms = time.ticks_ms()
            _frame  += 1
            print('F%d s=%d d=%d r=%d v=%d' % (
                _frame, ui['sign'], ui['dist_m'], ui['rem_m'], ui['speed']))
            _led(1); time.sleep_ms(20); _led(0)

        else:
            if time.ticks_diff(time.ticks_ms(), _last_ms) > 10000:
                if _ready:
                    _ready = False
                    _prev.clear()
                draw_waiting()
                _last_ms = time.ticks_ms()

    except Exception as e:
        print('ERR:', e)
        import sys; sys.print_exception(e)
        time.sleep_ms(200)

    time.sleep_ms(10)
