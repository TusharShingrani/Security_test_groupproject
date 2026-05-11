#!/usr/bin/env python3
"""Generate WSS security demo presentation (.pptx)."""

import pptx
import pptx.enum.shapes
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_CONNECTOR_TYPE

# ── Palette ───────────────────────────────────────────────────────────────────────────
DARK_BG   = RGBColor(0x1E, 0x1E, 0x2E)   # near-black
ACCENT    = RGBColor(0x89, 0xB4, 0xFA)   # soft blue
RED       = RGBColor(0xF3, 0x8B, 0xA8)   # soft red
GREEN     = RGBColor(0xA6, 0xE3, 0xA1)   # soft green
YELLOW    = RGBColor(0xF9, 0xE2, 0xAF)   # soft yellow
WHITE     = RGBColor(0xFF, 0xFF, 0xFF)
GREY      = RGBColor(0x58, 0x5B, 0x70)
LIGHT_BG  = RGBColor(0x31, 0x32, 0x44)   # card background

W = Inches(13.33)   # widescreen 16:9
H = Inches(7.5)

prs = Presentation()
prs.slide_width  = W
prs.slide_height = H

blank = prs.slide_layouts[6]   # completely blank layout


# ── Helpers ─────────────────────────────────────────────────────────────────────────────

def add_slide():
    s = prs.slides.add_slide(blank)
    bg = s.background.fill
    bg.solid()
    bg.fore_color.rgb = DARK_BG
    return s

def txb(slide, text, x, y, w, h, size=18, bold=False, color=WHITE,
        align=PP_ALIGN.LEFT, wrap=True):
    tb = slide.shapes.add_textbox(x, y, w, h)
    tf = tb.text_frame
    tf.word_wrap = wrap
    p  = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color
    return tb

def rect(slide, x, y, w, h, fill=LIGHT_BG, line=None, line_w=Pt(1.5)):
    shape = slide.shapes.add_shape(1, x, y, w, h)  # 1 = rectangle
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill
    if line:
        shape.line.color.rgb = line
        shape.line.width = line_w
    else:
        shape.line.fill.background()
    return shape

def pill(slide, x, y, w, h, fill, label, lsize=14, lcolor=WHITE):
    s = slide.shapes.add_shape(9, x, y, w, h)   # 9 = rounded rectangle
    s.fill.solid()
    s.fill.fore_color.rgb = fill
    s.line.fill.background()
    tf = s.text_frame
    tf.word_wrap = False
    p  = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    run = p.add_run()
    run.text = label
    run.font.size = Pt(lsize)
    run.font.bold = True
    run.font.color.rgb = lcolor
    return s

def hline(slide, x, y, w, color=GREY, width=Pt(1)):
    connector = slide.shapes.add_connector(
        MSO_CONNECTOR_TYPE.STRAIGHT,
        x, y, x + w, y)
    connector.line.color.rgb = color
    connector.line.width = width

def arrow(slide, x1, y1, x2, y2, color=ACCENT, width=Pt(2)):
    c = slide.shapes.add_connector(
        MSO_CONNECTOR_TYPE.STRAIGHT,
        x1, y1, x2, y2)
    c.line.color.rgb = color
    c.line.width = width


# ════════════════════════════════════════════════════════════════════════════
# SLIDE 1 — Title
# ════════════════════════════════════════════════════════════════════════════
s1 = add_slide()

# accent bar left
rect(s1, Inches(0), Inches(0), Inches(0.18), H, fill=ACCENT)

txb(s1, "Securing WebSocket (WSS) Communications",
    Inches(0.5), Inches(1.6), Inches(12), Inches(1.2),
    size=36, bold=True, color=ACCENT, align=PP_ALIGN.LEFT)

txb(s1, "A Proof-of-Concept Demonstrating Unauthorized Client Attacks\n"
        "and Progressive Mitigation: Token Auth → Mutual TLS (mTLS)",
    Inches(0.5), Inches(2.85), Inches(11), Inches(1.4),
    size=20, color=WHITE, align=PP_ALIGN.LEFT)

hline(s1, Inches(0.5), Inches(4.0), Inches(11.5), color=GREY)

txb(s1, "Azure VNet  ·  Python asyncio  ·  websockets  ·  OpenSSL PKI",
    Inches(0.5), Inches(4.2), Inches(11), Inches(0.6),
    size=14, color=GREY, align=PP_ALIGN.LEFT)

# three phase badges
for i, (label, col) in enumerate([
        ("Phase A  No Auth",  RED),
        ("Phase B  Token",    YELLOW),
        ("Phase C  mTLS",     GREEN)]):
    pill(s1, Inches(0.5 + i * 3.0), Inches(5.2), Inches(2.6), Inches(0.55),
         fill=col, label=label, lsize=13, lcolor=DARK_BG)


# ════════════════════════════════════════════════════════════════════════════
# SLIDE 2 — The Problem (Phase A diagram)
# ════════════════════════════════════════════════════════════════════════════
s2 = add_slide()
rect(s2, Inches(0), Inches(0), W, Inches(0.85), fill=LIGHT_BG)
txb(s2, "The Problem — WSS Encrypts but Does Not Authenticate",
    Inches(0.35), Inches(0.15), Inches(12), Inches(0.6),
    size=22, bold=True, color=ACCENT)

pill(s2, Inches(0.35), Inches(0.2), Inches(1.1), Inches(0.42),
     fill=RED, label="Phase A", lsize=12, lcolor=DARK_BG)

# VNet box
rect(s2, Inches(0.4), Inches(1.05), Inches(12.3), Inches(5.7),
     fill=RGBColor(0x28, 0x29, 0x3D), line=GREY, line_w=Pt(1))
txb(s2, "Azure VNet  10.0.0.0/16",
    Inches(0.6), Inches(1.1), Inches(4), Inches(0.4),
    size=11, color=GREY)

# VM boxes
def vm_box(slide, x, y, ip, name, col):
    rect(slide, x, y, Inches(2.8), Inches(1.35), fill=col, line=None)
    txb(slide, name, x + Inches(0.12), y + Inches(0.1),
        Inches(2.56), Inches(0.45), size=14, bold=True, color=DARK_BG)
    txb(slide, ip,   x + Inches(0.12), y + Inches(0.55),
        Inches(2.56), Inches(0.35), size=12, color=DARK_BG)

vm_box(s2, Inches(0.8),  Inches(2.2), "10.0.1.10", "digital-twin",   GREEN)
vm_box(s2, Inches(5.1),  Inches(2.2), "10.0.1.20:8443", "software-agent", ACCENT)
vm_box(s2, Inches(0.8),  Inches(4.4), "10.0.1.30", "attacker",       RED)

# arrows
arrow(s2, Inches(3.6), Inches(2.87), Inches(5.1), Inches(2.87), color=GREEN)
txb(s2, "WSS  ✓  electrolyzer_enable=true",
    Inches(3.62), Inches(2.52), Inches(1.7), Inches(0.4), size=9, color=GREEN)

arrow(s2, Inches(3.6), Inches(5.07), Inches(5.1), Inches(3.55), color=RED)
txb(s2, "WSS  ✓  electrolyzer_enable=false\n(no token — still accepted!)",
    Inches(3.62), Inches(4.35), Inches(1.7), Inches(0.7), size=9, color=RED)

# callout box
rect(s2, Inches(8.4), Inches(2.0), Inches(4.0), Inches(3.0),
     fill=RGBColor(0x40, 0x20, 0x20), line=RED, line_w=Pt(1.5))
txb(s2,
    "TLS only proves\nserver identity.\n\n"
    "Client identity is\nunverified — anyone\nwho speaks the\nprotocol can connect.",
    Inches(8.55), Inches(2.15), Inches(3.7), Inches(2.7),
    size=14, color=WHITE)


# ════════════════════════════════════════════════════════════════════════════
# SLIDE 3 — Demo Video (Phase A)
# ════════════════════════════════════════════════════════════════════════════
s3 = add_slide()
rect(s3, Inches(0), Inches(0), W, Inches(0.85), fill=LIGHT_BG)
txb(s3, "Live Demo — Phase A: Attack Succeeds",
    Inches(0.35), Inches(0.15), Inches(11), Inches(0.6),
    size=22, bold=True, color=RED)
pill(s3, Inches(0.35), Inches(0.2), Inches(1.1), Inches(0.42),
     fill=RED, label="Phase A", lsize=12, lcolor=DARK_BG)

rect(s3, Inches(1.5), Inches(1.05), Inches(10.3), Inches(5.2),
     fill=RGBColor(0x12, 0x12, 0x1A), line=GREY, line_w=Pt(2))
txb(s3, "▶  Insert demo video here",
    Inches(1.5), Inches(3.3), Inches(10.3), Inches(0.7),
    size=22, color=GREY, align=PP_ALIGN.CENTER)
txb(s3,
    "Insert → Video — show terminal with agent accepting both twin and attacker",
    Inches(1.5), Inches(6.35), Inches(10.3), Inches(0.55),
    size=11, color=GREY, align=PP_ALIGN.CENTER)


# ════════════════════════════════════════════════════════════════════════════
# SLIDE 4 — Phase B: Token Fix
# ════════════════════════════════════════════════════════════════════════════
s4 = add_slide()
rect(s4, Inches(0), Inches(0), W, Inches(0.85), fill=LIGHT_BG)
txb(s4, "Fix 1 — Application-Layer Token Authentication",
    Inches(0.35), Inches(0.15), Inches(11), Inches(0.6),
    size=22, bold=True, color=YELLOW)
pill(s4, Inches(0.35), Inches(0.2), Inches(1.1), Inches(0.42),
     fill=YELLOW, label="Phase B", lsize=12, lcolor=DARK_BG)

for col_x, col_color, col_title, lines in [
    (Inches(0.5), GREEN, "✓  Legitimate Twin",
     ["Sends token in JSON payload",
      '{"source":"digital-twin",',
      ' "electrolyzer_enable": true,',
      ' "token": "changeme"}',
      "",
      "Agent verifies token matches",
      "→  PLC state: RUNNING"]),
    (Inches(6.9), RED, "✗  Attacker",
     ["Sends no token",
      '{"source":"attacker",',
      ' "electrolyzer_enable": false}',
      "",
      "Agent rejects: token missing",
      '{"status": "rejected"}',
      "→  PLC state unchanged"]),
]:
    rect(s4, col_x, Inches(1.05), Inches(5.9), Inches(5.4),
         fill=LIGHT_BG, line=col_color, line_w=Pt(1.5))
    txb(s4, col_title, col_x + Inches(0.2), Inches(1.15),
        Inches(5.5), Inches(0.5), size=16, bold=True, color=col_color)
    body = "\n".join(lines)
    txb(s4, body, col_x + Inches(0.2), Inches(1.75),
        Inches(5.5), Inches(4.4), size=13, color=WHITE)

rect(s4, Inches(0.5), Inches(6.6), Inches(12.3), Inches(0.6),
     fill=RGBColor(0x3D, 0x38, 0x1A), line=YELLOW, line_w=Pt(1))
txb(s4, "⚠  Weakness: if the shared token is leaked or brute-forced, "
        "the attacker can still send valid commands. "
        "Token is application-layer only — Phase C moves auth into the TLS handshake.",
    Inches(0.65), Inches(6.65), Inches(12.0), Inches(0.5),
    size=11, color=YELLOW)


# ════════════════════════════════════════════════════════════════════════════
# SLIDE 5 — Phase C: mTLS Diagram
# ════════════════════════════════════════════════════════════════════════════
s5 = add_slide()
rect(s5, Inches(0), Inches(0), W, Inches(0.85), fill=LIGHT_BG)
txb(s5, "Fix 2 — Mutual TLS (mTLS): Client Authentication at the Handshake",
    Inches(0.35), Inches(0.15), Inches(12.2), Inches(0.6),
    size=22, bold=True, color=GREEN)
pill(s5, Inches(0.35), Inches(0.2), Inches(1.1), Inches(0.42),
     fill=GREEN, label="Phase C", lsize=12, lcolor=DARK_BG)

txb(s5, "PKI Structure", Inches(0.5), Inches(1.0), Inches(5), Inches(0.4),
    size=14, bold=True, color=ACCENT)

rect(s5, Inches(1.4), Inches(1.55), Inches(2.7), Inches(0.7),
     fill=ACCENT, line=None)
txb(s5, "WSS-PoC-CA\n(self-signed root)",
    Inches(1.4), Inches(1.6), Inches(2.7), Inches(0.6),
    size=12, bold=True, color=DARK_BG, align=PP_ALIGN.CENTER)

arrow(s5, Inches(2.0),  Inches(2.25), Inches(1.55), Inches(2.9),  color=ACCENT, width=Pt(1.5))
arrow(s5, Inches(2.75), Inches(2.25), Inches(3.3),  Inches(2.9),  color=ACCENT, width=Pt(1.5))

rect(s5, Inches(0.5),  Inches(2.9), Inches(2.0), Inches(0.75), fill=LIGHT_BG, line=ACCENT, line_w=Pt(1))
txb(s5, "agent-server.crt\n(server auth)",
    Inches(0.5), Inches(2.95), Inches(2.0), Inches(0.65),
    size=11, color=WHITE, align=PP_ALIGN.CENTER)

rect(s5, Inches(2.9), Inches(2.9), Inches(2.0), Inches(0.75), fill=LIGHT_BG, line=GREEN, line_w=Pt(1))
txb(s5, "twin-client.crt\n(client auth)",
    Inches(2.9), Inches(2.95), Inches(2.0), Inches(0.65),
    size=11, color=WHITE, align=PP_ALIGN.CENTER)

txb(s5, "Attacker: knows the CA,\nbut has NO client cert",
    Inches(0.5), Inches(3.85), Inches(4.5), Inches(0.6),
    size=11, color=RED)

txb(s5, "TLS Handshake — mTLS Mode", Inches(5.8), Inches(1.0), Inches(7), Inches(0.4),
    size=14, bold=True, color=ACCENT)

seq_data = [
    (GREEN,  "digital-twin → agent",  "ClientHello + twin-client.crt"),
    (ACCENT, "agent",                 "Verify cert signed by CA  ✓"),
    (ACCENT, "agent → digital-twin",  "Handshake complete (mutual)"),
    (GREEN,  "digital-twin → agent",  '{"electrolyzer_enable": true}  → ACCEPTED ✓'),
    (GREY,   "", ""),
    (RED,    "attacker → agent",      "ClientHello  (no client cert)"),
    (RED,    "agent",                 "CERT_REQUIRED — cert missing  ✗"),
    (RED,    "agent → attacker",      "TLS alert: certificate_required"),
    (RED,    "result",                "Connection refused — app layer never reached  ✓"),
]
for i, (col, actor, action) in enumerate(seq_data):
    if not actor:
        continue
    y = Inches(1.55) + i * Inches(0.58)
    rect(s5, Inches(5.8), y, Inches(2.0), Inches(0.44), fill=LIGHT_BG, line=col, line_w=Pt(1))
    txb(s5, actor, Inches(5.85), y + Inches(0.04),
        Inches(1.9), Inches(0.38), size=10, bold=True, color=col)
    txb(s5, action, Inches(8.1), y + Inches(0.04),
        Inches(5.0), Inches(0.38), size=10, color=WHITE)


# ════════════════════════════════════════════════════════════════════════════
# SLIDE 6 — Demo Video (Phase C)
# ════════════════════════════════════════════════════════════════════════════
s6 = add_slide()
rect(s6, Inches(0), Inches(0), W, Inches(0.85), fill=LIGHT_BG)
txb(s6, "Live Demo — Phase C: Attacker Blocked at TLS Handshake",
    Inches(0.35), Inches(0.15), Inches(11), Inches(0.6),
    size=22, bold=True, color=GREEN)
pill(s6, Inches(0.35), Inches(0.2), Inches(1.1), Inches(0.42),
     fill=GREEN, label="Phase C", lsize=12, lcolor=DARK_BG)

rect(s6, Inches(1.5), Inches(1.05), Inches(10.3), Inches(5.2),
     fill=RGBColor(0x12, 0x12, 0x1A), line=GREY, line_w=Pt(2))
txb(s6, "▶  Insert demo video here",
    Inches(1.5), Inches(3.3), Inches(10.3), Inches(0.7),
    size=22, color=GREY, align=PP_ALIGN.CENTER)
txb(s6,
    "3 terminals: agent log (mTLS OK for twin / nothing for attacker) · "
    "twin log · attacker blocked at TLS layer",
    Inches(1.5), Inches(6.35), Inches(10.3), Inches(0.55),
    size=11, color=GREY, align=PP_ALIGN.CENTER)


# ════════════════════════════════════════════════════════════════════════════
# SLIDE 7 — Key Takeaways
# ════════════════════════════════════════════════════════════════════════════
s7 = add_slide()
rect(s7, Inches(0), Inches(0), W, Inches(0.85), fill=LIGHT_BG)
txb(s7, "Key Takeaways",
    Inches(0.35), Inches(0.15), Inches(11), Inches(0.6),
    size=26, bold=True, color=ACCENT)

headers = ["Property", "Phase A — No Auth", "Phase B — Token", "Phase C — mTLS"]
col_w   = [Inches(3.1), Inches(2.8), Inches(2.8), Inches(2.8)]
col_x   = [Inches(0.35), Inches(3.45), Inches(6.25), Inches(9.05)]
row_h   = Inches(0.62)
row0_y  = Inches(1.05)

for i, (hdr, cx, cw) in enumerate(zip(headers, col_x, col_w)):
    c = ACCENT if i == 0 else (RED if i == 1 else (YELLOW if i == 2 else GREEN))
    rect(s7, cx, row0_y, cw - Inches(0.05), row_h,
         fill=LIGHT_BG, line=c, line_w=Pt(1))
    txb(s7, hdr, cx + Inches(0.08), row0_y + Inches(0.08),
        cw - Inches(0.2), row_h - Inches(0.1),
        size=13, bold=True, color=c, align=PP_ALIGN.CENTER)

rows = [
    ("Wire encryption",          "Yes",            "Yes",           "Yes"),
    ("Server identity verified", "Yes (server cert)","Yes (server cert)","Yes (CA-signed)"),
    ("Client identity verified", "NO",             "App layer (token)","TLS layer (cert)"),
    ("Attacker blocked",         "NO",             "If token unknown","No cert = no conn"),
    ("Block point",              "—",              "App handler",   "TLS handshake"),
    ("Bypassed if",              "—",              "Token leaked",  "CA key stolen"),
]
row_colors = [WHITE, WHITE, RED, GREEN, ACCENT, YELLOW]

for r, (row, rcol) in enumerate(zip(rows, row_colors)):
    y = row0_y + row_h + r * row_h
    for i, (cell, cx, cw) in enumerate(zip(row, col_x, col_w)):
        bg = LIGHT_BG if i > 0 else RGBColor(0x28, 0x29, 0x3D)
        rect(s7, cx, y, cw - Inches(0.05), row_h - Inches(0.02),
             fill=bg, line=GREY, line_w=Pt(0.5))
        cell_color = rcol if i > 0 else WHITE
        txb(s7, cell, cx + Inches(0.08), y + Inches(0.1),
            cw - Inches(0.2), row_h - Inches(0.15),
            size=12, color=cell_color, align=PP_ALIGN.CENTER)

txb(s7,
    "mTLS moves authentication below the application layer — "
    "an attacker without a CA-signed client cert cannot complete the TLS handshake.",
    Inches(0.35), Inches(7.0), Inches(12.6), Inches(0.42),
    size=12, color=GREY, align=PP_ALIGN.CENTER)


# ── Save ────────────────────────────────────────────────────────────────────────────────
out = "/home/user/Security_test_groupproject/docs/wss-security-demo.pptx"
prs.save(out)
print(f"Saved: {out}")
