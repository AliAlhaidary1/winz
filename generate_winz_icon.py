#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate Winz app icon - Modern global style
Design: Premium dark gradient + Golden W + sparkle
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps
import math
import os

SIZE = 1024
OUTPUT_DIR = "."
ROOT = r"D:\myproject\yelottery"

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def create_gradient_background(size, radius):
    # Create base image with gradient
    img = Image.new("RGBA", (size, size), (0,0,0,0))
    draw = ImageDraw.Draw(img)
    
    # Colors: deep navy to almost black
    top = hex_to_rgb("#0F172A")
    mid = hex_to_rgb("#0B1220")
    bottom = hex_to_rgb("#020617")
    
    # Create gradient surface
    grad = Image.new("RGBA", (size, size))
    gdraw = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / size
        # smooth gradient top->mid->bottom
        if t < 0.5:
            tt = t*2
            r = int(top[0]*(1-tt) + mid[0]*tt)
            g = int(top[1]*(1-tt) + mid[1]*tt)
            b = int(top[2]*(1-tt) + mid[2]*tt)
        else:
            tt = (t-0.5)*2
            r = int(mid[0]*(1-tt) + bottom[0]*tt)
            g = int(mid[1]*(1-tt) + bottom[1]*tt)
            b = int(mid[2]*(1-tt) + bottom[2]*tt)
        gdraw.line([(0, y), (size, y)], fill=(r,g,b,255))
    
    # Rounded corners mask
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle([(0,0),(size-1,size-1)], radius=radius, fill=255)
    
    # Apply mask
    grad.putalpha(mask)
    
    # Add subtle diagonal gold glow
    glow = Image.new("RGBA", (size,size), (0,0,0,0))
    g2 = ImageDraw.Draw(glow)
    # large ellipse with low opacity
    # top-right golden sheen
    for i in range(300):
        alpha = int(18 * (1 - i/300))
        # ellipse centered at 780, 220
        x0 = 520 - i*1.2
        y0 = -80 - i*0.6
        x1 = 1100 + i*0.5
        y1 = 520 + i*0.8
        # only draw every few to keep performance
        if i % 8 == 0:
            g2.ellipse([x0,y0,x1,y1], outline=(255, 210, 90, alpha), width=1)
    
    grad = Image.alpha_composite(grad, glow)
    
    # Add subtle border stroke
    border = Image.new("RGBA", (size,size), (0,0,0,0))
    bdraw = ImageDraw.Draw(border)
    bdraw.rounded_rectangle([(0,0),(size-1,size-1)], radius=radius, outline=(255,255,255,18), width=2)
    
    grad = Image.alpha_composite(grad, border)
    return grad

def draw_golden_W(img):
    """Draw stylized W"""
    size = img.size[0]
    draw = ImageDraw.Draw(img)
    
    # W geometry - centered, normalized to 1024
    # W points: 5 points top/bottom
    # scale and center
    # W width approx 520, height 340
    cx = size // 2
    cy = size // 2 - 30  # slightly up
    
    w_half = 260
    h_half = 170
    stroke = 52  # thickness of W strokes
    
    # Gold gradient for W: we will create a separate image for W with gradient fill then mask
    w_img = Image.new("RGBA", (size,size), (0,0,0,0))
    w_draw = ImageDraw.Draw(w_img)
    
    # Define W as thick polygon with miter
    # Left outer, left inner valley, middle peak, right inner valley, right outer
    top_y = cy - h_half
    bottom_y = cy + h_half
    mid_y = cy + 50  # middle dip not full bottom
    
    # W polygon points (thick stroke via polygon)
    # We'll draw W as 4 thick lines forming W shape
    # Instead use polygon outline for fill
    points = [
        (cx - w_half, top_y),               # top left
        (cx - w_half + stroke, top_y),      # top left inner
        (cx - w_half*0.5 + stroke*0.4, bottom_y - 65), # bottom left valley inner
        (cx, mid_y),                        # middle peak (center)
        (cx + w_half*0.5 - stroke*0.4, bottom_y - 65), # bottom right valley
        (cx + w_half - stroke, top_y),      # top right inner
        (cx + w_half, top_y),               # top right outer
        (cx + w_half - 8, bottom_y),        # bottom right outer
        (cx + 12, bottom_y - 20),           # slight
        (cx, mid_y + 85),                   # middle bottom
        (cx - 12, bottom_y - 20),
        (cx - w_half + 8, bottom_y),
    ]
    
    # Create gradient for W fill
    # Create linear gradient image for W area
    grad_w = Image.new("RGBA", (size,size), (0,0,0,0))
    # vertical gold gradient
    for y in range(top_y-10, bottom_y+10):
        t = (y - (top_y)) / (bottom_y - top_y)
        t = max(0,min(1,t))
        # gold gradient stops: #FFED99 (light) -> #F59E0B -> #B45309 (dark)
        if t < 0.35:
            tt = t/0.35
            r = int(255*(1-tt) + 253*tt)
            g = int(237*(1-tt) + 158*tt)
            b = int(153*(1-tt) + 11*tt)
        elif t < 0.7:
            tt = (t-0.35)/0.35
            r = int(253*(1-tt) + 245*tt)
            g = int(158*(1-tt) + 158*tt)
            b = int(11*(1-tt) + 11*tt)
        else:
            tt = (t-0.7)/0.3
            r = int(245*(1-tt) + 180*tt)
            g = int(158*(1-tt) + 83*tt)
            b = int(11*(1-tt) + 9*tt)
        ImageDraw.Draw(grad_w).line([(0,y),(size,y)], fill=(r,g,b,255))
    
    # Draw W polygon mask
    mask = Image.new("L", (size,size), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    
    # Smooth edges
    mask = mask.filter(ImageFilter.GaussianBlur(radius=0.6))
    # Apply mask to gradient
    w_colored = Image.new("RGBA", (size,size), (0,0,0,0))
    w_colored.paste(grad_w, (0,0), mask)
    
    # Add inner highlight (top edge white translucent)
    highlight = Image.new("RGBA", (size,size), (0,0,0,0))
    h_draw = ImageDraw.Draw(highlight)
    # offset polygon for highlight
    hl_points = [
        (cx - w_half + 6, top_y + 14),
        (cx - w_half + stroke - 6, top_y + 14),
        (cx - w_half*0.5 + stroke*0.4 - 4, bottom_y - 65 - 6),
        (cx - w_half*0.5 + stroke*0.4 + 4, bottom_y - 65 + 8),
        (cx - w_half + 20, bottom_y - 14),
        (cx - w_half + 8, bottom_y - 6),
    ]
    # simplified highlight line along top edge
    # We'll just add a soft white overlay on top third of W
    hl_mask = Image.new("L", (size,size), 0)
    ImageDraw.Draw(hl_mask).polygon(points, fill=120)
    # keep only top 35%
    for y in range(size):
        if y > top_y + (bottom_y - top_y)*0.42:
            for x in range(size):
                hl_mask.putpixel((x,y), 0)
                # faster: crop
            break
    # gaussian blur
    hl_mask = hl_mask.filter(ImageFilter.GaussianBlur(8))
    white_overlay = Image.new("RGBA", (size,size), (255,255,255,0))
    white_overlay.putalpha(hl_mask)
    # use screen blend via alpha composite with low opacity
    w_colored = Image.alpha_composite(w_colored, white_overlay)
    
    # Add drop shadow for W
    shadow = Image.new("RGBA", (size,size), (0,0,0,0))
    # shadow is blurred mask offset
    shadow_mask = mask.filter(ImageFilter.GaussianBlur(22))
    # darken
    shadow_img = Image.new("RGBA", (size,size), (0,0,0,110))
    shadow_img.putalpha(shadow_mask)
    # offset shadow down
    shadow_offset = Image.new("RGBA", (size,size), (0,0,0,0))
    shadow_offset.paste(shadow_img, (0,14), shadow_img)
    
    # Composite: shadow -> W
    base = Image.alpha_composite(img, shadow_offset)
    base = Image.alpha_composite(base, w_colored)
    
    # Add sparkle/diamond above W
    draw_sparkle(base, cx, top_y - 58)
    
    # Add subtle underline accent (gold line under W)
    accent = Image.new("RGBA", (size,size), (0,0,0,0))
    a_draw = ImageDraw.Draw(accent)
    # rounded line
    line_y = bottom_y + 42
    line_w = 220
    line_h = 6
    a_draw.rounded_rectangle([(cx - line_w//2, line_y),(cx + line_w//2, line_y+line_h)], radius=3, fill=(245,158,11,255))
    # glow under line
    glow_line = accent.filter(ImageFilter.GaussianBlur(10))
    # make glow more transparent
    glow_line.putalpha(Image.new("L", glow_line.size, 90).filter(ImageFilter.GaussianBlur(0)))
    base = Image.alpha_composite(base, glow_line)
    base = Image.alpha_composite(base, accent)
    
    # Add WINZ text below line
    draw_winz_text(base, cx, line_y + 48)
    
    return base

def draw_sparkle(img, cx, cy):
    draw = ImageDraw.Draw(img)
    # Diamond shape 4 points
    size = 28
    # glow
    glow = Image.new("RGBA", img.size, (0,0,0,0))
    gdraw = ImageDraw.Draw(glow)
    # soft glow ellipse
    glow_ellipse = Image.new("RGBA", (size*6, size*6), (0,0,0,0))
    eg = ImageDraw.Draw(glow_ellipse)
    eg.ellipse([(0,0),(size*6-1,size*6-1)], fill=(255,215,80,55))
    glow_ellipse = glow_ellipse.filter(ImageFilter.GaussianBlur(12))
    # paste glow
    gx = cx - size*3
    gy = cy - size*3
    tmp = Image.new("RGBA", img.size, (0,0,0,0))
    tmp.paste(glow_ellipse, (gx, gy), glow_ellipse)
    # composite
    img2 = Image.alpha_composite(img, tmp)
    # update img in place via paste
    img.paste(img2, (0,0))
    
    # diamond
    points = [(cx, cy - size), (cx + size*0.65, cy), (cx, cy + size), (cx - size*0.65, cy)]
    # gold diamond with gradient simple
    draw.polygon(points, fill=(255, 220, 90, 255), outline=(255,255,255, 45), width=2)
    # inner highlight
    inner = [(cx, cy - size+7), (cx + 9, cy -2), (cx, cy + 14), (cx - 9, cy -2)]
    draw.polygon(inner, fill=(255,255,255, 70))

def draw_winz_text(img, cx, y):
    draw = ImageDraw.Draw(img)
    text = "WINZ"
    # Try to load a bold font
    font = None
    # Search for available fonts
    possible = [
        r"C:\Windows\Fonts\Arialbd.ttf",
        r"C:\Windows\Fonts\arial.ttf",
        r"C:\Windows\Fonts\segoeuib.ttf",
        r"C:\Windows\Fonts\Bahij.ttf",
    ]
    for p in possible:
        if os.path.exists(p):
            try:
                font = ImageFont.truetype(p, 92)
                break
            except:
                pass
    if font is None:
        font = ImageFont.load_default()
        # scale not perfect but fallback
        # enlarge by drawing bigger via transform
    # Measure
    bbox = draw.textbbox((0,0), text, font=font)
    tw = bbox[2]-bbox[0]
    th = bbox[3]-bbox[1]
    # tracking: increase spacing
    # Manual tracking by drawing each char
    tracking = 18
    chars = list(text)
    total_w = sum(draw.textbbox((0,0), c, font=font)[2] - draw.textbbox((0,0), c, font=font)[0] for c in chars) + tracking*(len(chars)-1)
    x = cx - total_w//2
    # shadow for text
    for i, c in enumerate(chars):
        cw = draw.textbbox((0,0), c, font=font)[2] - draw.textbbox((0,0), c, font=font)[0]
        # shadow offset
        draw.text((x+2, y+3), c, font=font, fill=(0,0,0,120))
        x += cw + tracking
    x = cx - total_w//2
    for i, c in enumerate(chars):
        cw = draw.textbbox((0,0), c, font=font)[2] - draw.textbbox((0,0), c, font=font)[0]
        # white text with slight letterpress
        draw.text((x, y), c, font=font, fill=(255,255,255,255))
        x += cw + tracking
    # small subtitle: LOTTERY POS ? optional small
    sub = "LOTTERY"
    sub_font = None
    for p in possible:
        if os.path.exists(p):
            try:
                sub_font = ImageFont.truetype(p, 26)
                break
            except:
                pass
    if sub_font:
        sbbox = draw.textbbox((0,0), sub, font=sub_font)
        sw = sbbox[2]-sbbox[0]
        draw.text((cx - sw//2, y + 88), sub, font=sub_font, fill=(255,255,255, 110))

def main():
    size = 1024
    radius = 228  # iOS style 22%
    bg = create_gradient_background(size, radius)
    final = draw_golden_W(bg)
    
    # Ensure output dirs
    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    master_path = os.path.join(ROOT, "assets", "winz_icon_1024.png")
    final.save(master_path, "PNG")
    print(f"Master icon saved: {master_path} size {final.size}")
    
    # Also save preview without rounded mask for store (512 plain bg)
    # Save a version with solid background for Windows ico (no transparency corners? keep rounded but with bg)
    # For ICO we need square without transparency? We'll keep same.
    
    # Generate all target sizes
    targets = [
        (r"android\app\src\main\res\mipmap-mdpi\ic_launcher.png", 48),
        (r"android\app\src\main\res\mipmap-hdpi\ic_launcher.png", 72),
        (r"android\app\src\main\res\mipmap-xhdpi\ic_launcher.png", 96),
        (r"android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png", 144),
        (r"android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png", 192),
        (r"web\icons\Icon-192.png", 192),
        (r"web\icons\Icon-512.png", 512),
        (r"web\icons\Icon-maskable-192.png", 192),
        (r"web\icons\Icon-maskable-512.png", 512),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-1024x1024@1x.png", 1024),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@1x.png", 20),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@2x.png", 40),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@3x.png", 60),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@1x.png", 29),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@2x.png", 58),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@3x.png", 87),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@1x.png", 40),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@2x.png", 80),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@3x.png", 120),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@2x.png", 120),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@3x.png", 180),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@1x.png", 76),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@2x.png", 152),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-83.5x83.5@2x.png", 167),
    ]
    
    for rel, sz in targets:
        path = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        resized = final.resize((sz, sz), Image.LANCZOS)
        resized.save(path, "PNG")
        print(f"  -> {rel} ({sz}x{sz})")
    
    # Windows ICO - multiple sizes
    ico_sizes = [16,24,32,48,64,128,256]
    ico_images = []
    for s in ico_sizes:
        ico_images.append(final.resize((s,s), Image.LANCZOS))
    ico_path = os.path.join(ROOT, r"windows\runner\resources\app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    # Pillow saves ICO with largest first
    ico_images[0].save(ico_path, format="ICO", sizes=[(im.size[0], im.size[1]) for im in ico_images])
    print(f"ICO saved: {ico_path}")
    
    # Also save asset for Flutter splash maybe
    print("All icons generated successfully!")

if __name__ == "__main__":
    main()
