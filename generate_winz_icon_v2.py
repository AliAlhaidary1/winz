#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate Winz v2 icon - Green Identity (matches AppTheme)
Primary: #0B8A3E (AppTheme.green), Dark: #076B2F, Light: #E6F4EA
No black dominant - premium green+white+gold
"""

from PIL import Image, ImageDraw, ImageFilter
import os

SIZE = 1024
ROOT = r"D:\myproject\yelottery"

def hex_to_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def create_green_background(size, radius):
    # Green gradient matching AppTheme: #0E9E47 -> #0B8A3E -> #076B2F
    img = Image.new("RGBA", (size, size), (0,0,0,0))
    grad = Image.new("RGBA", (size, size))
    gdraw = ImageDraw.Draw(grad)
    
    top = hex_to_rgb("#10A24A")      # slightly brighter top
    mid = hex_to_rgb("#0B8A3E")      # AppTheme.green
    bottom = hex_to_rgb("#076B2F")   # AppTheme.greenDark
    
    for y in range(size):
        t = y / size
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
    ImageDraw.Draw(mask).rounded_rectangle([(0,0),(size-1,size-1)], radius=radius, fill=255)
    grad.putalpha(mask)
    
    # Add subtle watermark pattern - faint white circles/lines for lottery feel
    pattern = Image.new("RGBA", (size,size), (0,0,0,0))
    pdraw = ImageDraw.Draw(pattern)
    # Large faint circles centered
    for i in range(5):
        r_ = 380 + i*90
        alpha = int(10 - i*1.2)  # very faint
        alpha = max(0, alpha)
        # centered at (512,512)
        pdraw.ellipse([(512-r_, 512-r_),(512+r_, 512+r_)], outline=(255,255,255, alpha), width=1)
    # Diagonal light sheen (top-left highlight)
    sheen = Image.new("RGBA", (size,size), (0,0,0,0))
    sdraw = ImageDraw.Draw(sheen)
    # soft ellipse highlight top
    hl = Image.new("RGBA", (800, 600), (0,0,0,0))
    hdraw = ImageDraw.Draw(hl)
    # gradient-ish highlight
    for y in range(600):
        a = int(22 * (1 - y/600) * 0.9)
        hdraw.line([(0,y),(800,y)], fill=(255,255,255, a))
    hl = hl.filter(ImageFilter.GaussianBlur(40))
    # rotate slightly via paste offset
    sheen.paste(hl, (-80, -120), hl)
    
    # faint gold dust bottom
    dust = Image.new("RGBA", (size,size), (0,0,0,0))
    ddraw = ImageDraw.Draw(dust)
    for i in range(70):
        # random gold specks? Use deterministic positions
        import math
        angle = (i * 37) % 360
        rad = 200 + (i*13)%280
        x = 512 + math.cos(math.radians(angle))*rad*0.9
        y = 512 + math.sin(math.radians(angle))*rad*0.55
        # only bottom half
        if y < 540:
            continue
        size_s = 1 + (i%3)
        alpha = 30 + (i%40)
        ddraw.ellipse([(x-size_s,y-size_s),(x+size_s,y+size_s)], fill=(255,215,80, alpha))
    dust = dust.filter(ImageFilter.GaussianBlur(0.5))
    
    grad = Image.alpha_composite(grad, pattern)
    grad = Image.alpha_composite(grad, sheen)
    grad = Image.alpha_composite(grad, dust)
    
    # Border - subtle white 12% for premium
    border = Image.new("RGBA", (size,size), (0,0,0,0))
    ImageDraw.Draw(border).rounded_rectangle([(0,0),(size-1,size-1)], radius=radius, outline=(255,255,255,20), width=2)
    grad = Image.alpha_composite(grad, border)
    
    # Ensure corners are properly masked (keep transparency outside radius)
    # Already masked via putalpha, but keep for safety
    return grad

def draw_white_W_with_gold(img):
    size = img.size[0]
    cx = size // 2
    cy = size // 2 - 28
    
    w_half = 250
    h_half = 165
    stroke = 50
    
    top_y = cy - h_half
    bottom_y = cy + h_half
    
    mid_y = cy + 48
    
    # W polygon - refined
    points = [
        (cx - w_half, top_y),
        (cx - w_half + stroke, top_y),
        (cx - w_half*0.52 + stroke*0.42, bottom_y - 62),
        (cx, mid_y),
        (cx + w_half*0.52 - stroke*0.42, bottom_y - 62),
        (cx + w_half - stroke, top_y),
        (cx + w_half, top_y),
        (cx + w_half - 8, bottom_y),
        (cx + 10, bottom_y - 18),
        (cx, mid_y + 82),
        (cx - 10, bottom_y - 18),
        (cx - w_half + 8, bottom_y),
    ]
    
    # Shadow for W
    shadow_mask = Image.new("L", (size,size), 0)
    ImageDraw.Draw(shadow_mask).polygon(points, fill=255)
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(18))
    shadow_img = Image.new("RGBA", (size,size), (0,0,0,75))
    shadow_img.putalpha(shadow_mask)
    shadow_offset = Image.new("RGBA", (size,size), (0,0,0,0))
    shadow_offset.paste(shadow_img, (0,10), shadow_img)
    base = Image.alpha_composite(img, shadow_offset)
    
    # White W fill
    w_mask = Image.new("L", (size,size), 0)
    ImageDraw.Draw(w_mask).polygon(points, fill=255)
    w_mask = w_mask.filter(ImageFilter.GaussianBlur(0.7))  # slight AA
    w_fill = Image.new("RGBA", (size,size), (255,255,255,255))
    w_fill.putalpha(w_mask)
    
    # Inner gold bevel - thin gold outline inside W edges (premium)
    # Create inner stroke by eroding mask
    inner_stroke_mask = Image.new("L", (size,size), 0)
    # Draw slightly smaller W as hole
    # shrink by ~4px (approx)
    # For simplicity, draw gold outline via polygon outline
    gold_outline = Image.new("RGBA", (size,size), (0,0,0,0))
    ImageDraw.Draw(gold_outline).polygon(points, outline=(255,200,60,180), width=3)
    # also add thin white highlight on top edge
    highlight = Image.new("RGBA", (size,size), (0,0,0,0))
    # top highlight line
    hl_mask = Image.new("L", (size,size), 0)
    # clip top 30% of W for highlight
    clip = Image.new("L", (size,size), 0)
    ImageDraw.Draw(clip).rectangle([(0, top_y),(size, top_y + (bottom_y-top_y)*0.35)], fill=255)
    # intersect
    # final highlight mask = w_mask * clip * blurred
    hl = Image.new("L", (size,size), 0)
    # composite
    for y in range(size):
        for x in range(size):
            # slow but okay for 1024 once? Use numpy would be faster but Python loop is heavy
            pass
    # Simpler: just add gold outline and merge
    base = Image.alpha_composite(base, w_fill)
    # subtle gold outer glow on W
    w_glow = w_mask.filter(ImageFilter.GaussianBlur(12))
    glow_img = Image.new("RGBA", (size,size), (255,215,80,28))
    glow_img.putalpha(w_glow)
    base = Image.alpha_composite(base, glow_img)
    base = Image.alpha_composite(base, gold_outline)
    
    # Diamond sparkle above W - gold with white center (more visible on green)
    draw_sparkle_green(base, cx, top_y - 56)
    
    # Gold underline accent under W
    line_y = bottom_y + 38
    line_w = 210
    line_h = 7
    # shadow for line
    line_shadow = Image.new("RGBA", (size,size), (0,0,0,0))
    ImageDraw.Draw(line_shadow).rounded_rectangle([(cx - line_w//2+0, line_y+2),(cx + line_w//2+0, line_y+line_h+2)], radius=3, fill=(0,0,0,45))
    line_shadow = line_shadow.filter(ImageFilter.GaussianBlur(4))
    base = Image.alpha_composite(base, line_shadow)
    line = Image.new("RGBA", (size,size), (0,0,0,0))
    # gold gradient line: #FFD54F -> #FF8E00
    # solid for simplicity but with highlight
    ImageDraw.Draw(line).rounded_rectangle([(cx - line_w//2, line_y),(cx + line_w//2, line_y+line_h)], radius=3, fill=(255,193,40,255))
    # inner highlight
    ImageDraw.Draw(line).rounded_rectangle([(cx - line_w//2+4, line_y+1),(cx + line_w//2-4, line_y+3)], radius=2, fill=(255,255,255,90))
    line_glow = line.filter(ImageFilter.GaussianBlur(8))
    # glow with lower alpha
    glow2 = Image.new("RGBA", (size,size), (255,193,40,50))
    glow2.putalpha(line_glow.getchannel("A").point(lambda p: p*0.35))
    base = Image.alpha_composite(base, glow2)
    base = Image.alpha_composite(base, line)
    
    # Text WINZ - white with strong shadow
    draw_winz_green(base, cx, line_y + 46)
    
    return base

def draw_sparkle_green(img, cx, cy):
    size_d = 26
    # glow ellipse gold
    glow = Image.new("RGBA", (size_d*7, size_d*7), (0,0,0,0))
    eg = ImageDraw.Draw(glow)
    eg.ellipse([(0,0),(size_d*7-1,size_d*7-1)], fill=(255,235,120,60))
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    tmp = Image.new("RGBA", img.size, (0,0,0,0))
    tmp.paste(glow, (cx - size_d*3 - 3, cy - size_d*3 - 3), glow)
    base2 = Image.alpha_composite(img, tmp)
    img.paste(base2, (0,0))
    
    draw = ImageDraw.Draw(img)
    # outer diamond gold
    pts = [(cx, cy - size_d), (cx + size_d*0.62, cy), (cx, cy + size_d), (cx - size_d*0.62, cy)]
    draw.polygon(pts, fill=(255, 210, 65, 255), outline=(255,255,255,95), width=2)
    # inner white diamond
    inner = [(cx, cy - size_d+7), (cx + 8, cy), (cx, cy + 11), (cx - 8, cy)]
    draw.polygon(inner, fill=(255,255,255,210))
    # tiny center gold dot
    draw.ellipse([(cx-3, cy-3),(cx+3, cy+3)], fill=(255,170,20,255))

def draw_winz_green(img, cx, y):
    import os
    draw = ImageDraw.Draw(img)
    text = "WINZ"
    possible = [
        r"C:\Windows\Fonts\Arialbd.ttf",
        r"C:\Windows\Fonts\arial.ttf",
        r"C:\Windows\Fonts\segoeuib.ttf",
    ]
    font = None
    for p in possible:
        if os.path.exists(p):
            try:
                font = ImageFont.truetype(p, 92)
                break
            except:
                pass
    if font is None:
        from PIL import ImageFont
        font = ImageFont.load_default()
    
    from PIL import ImageFont as IF
    # measure with tracking
    tracking = 18
    chars = list(text)
    # total width
    total_w = 0
    widths = []
    for c in chars:
        bbox = draw.textbbox((0,0), c, font=font)
        w = bbox[2]-bbox[0]
        widths.append(w)
        total_w += w
    total_w += tracking*(len(chars)-1)
    x = cx - total_w//2
    # shadow first
    sx = x
    for i, c in enumerate(chars):
        draw.text((sx+2.5, y+4), c, font=font, fill=(0,0,0,95))
        sx += widths[i] + tracking
    # main white
    x2 = x
    for i, c in enumerate(chars):
        draw.text((x2, y), c, font=font, fill=(255,255,255,255))
        x2 += widths[i] + tracking
    # subtitle LOTTERY
    sub = "LOTTERY"
    sub_font = None
    for p in possible:
        if os.path.exists(p):
            try:
                sub_font = IF.truetype(p, 26)
                break
            except:
                pass
    if sub_font:
        bbox = draw.textbbox((0,0), sub, font=sub_font)
        sw = bbox[2]-bbox[0]
        # letter spacing for subtitle heavier
        # draw with tracking
        s_tracking = 3
        # recalc total sub width with tracking
        stotal = 0
        sws = []
        for c in sub:
            b = draw.textbbox((0,0), c, font=sub_font)
            w = b[2]-b[0]
            sws.append(w)
            stotal += w
        stotal += s_tracking*(len(sub)-1)
        sx2 = cx - stotal//2
        # shadow
        tx = sx2
        for i, c in enumerate(sub):
            draw.text((tx+1, y+90+1), c, font=sub_font, fill=(0,0,0,55))
            tx += sws[i] + s_tracking
        tx = sx2
        for i, c in enumerate(sub):
            draw.text((tx, y+90), c, font=sub_font, fill=(255,255,255,190))
            tx += sws[i] + s_tracking

def main():
    size = 1024
    radius = 228
    bg = create_green_background(size, radius)
    # need ImageFont import for draw function
    global ImageFont
    from PIL import ImageFont
    final = draw_white_W_with_gold(bg)
    
    os.makedirs(os.path.join(ROOT, "assets"), exist_ok=True)
    master_path = os.path.join(ROOT, "assets", "winz_icon_1024.png")
    final.save(master_path, "PNG")
    print(f"Master v2 green saved: {master_path}")
    
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
        print(f"  -> {rel} ({sz})")
    
    ico_sizes = [16,24,32,48,64,128,256]
    ico_images = [final.resize((s,s), Image.LANCZOS) for s in ico_sizes]
    ico_path = os.path.join(ROOT, r"windows\runner\resources\app_icon.ico")
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    ico_images[0].save(ico_path, format="ICO", sizes=[(im.size[0], im.size[1]) for im in ico_images])
    print(f"ICO saved: {ico_path}")
    print("All Winz v2 green icons done!")

if __name__ == "__main__":
    main()
