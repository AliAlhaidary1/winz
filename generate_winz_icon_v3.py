#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
import os, math

ROOT = r"D:\myproject\yelottery"
SIZE = 1024
RADIUS = 228

def hex_rgb(h): 
    h=h.lstrip('#')
    return tuple(int(h[i:i+2],16) for i in (0,2,4))

def create_base():
    # Green gradient base - solid rounded rect with gradient
    base = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    grad = Image.new("RGB", (SIZE, SIZE))
    d = ImageDraw.Draw(grad)
    c_top = hex_rgb("#14B65C")
    c_bot = hex_rgb("#064021")
    for y in range(SIZE):
        t = (y/SIZE) ** 0.85  # slight easing for natural falloff
        r=int(c_top[0]*(1-t)+c_bot[0]*t)
        g=int(c_top[1]*(1-t)+c_bot[1]*t)
        b=int(c_top[2]*(1-t)+c_bot[2]*t)
        d.line([(0,y),(SIZE,y)], fill=(r,g,b))
    # mask
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0,0),(SIZE-1,SIZE-1)], radius=RADIUS, fill=255)
    grad_rgba = Image.new("RGBA", (SIZE,SIZE))
    grad_rgba.paste(grad, (0,0))
    grad_rgba.putalpha(mask)
    base = Image.alpha_composite(base, grad_rgba)
    # faint pattern circles
    pat = Image.new("RGBA", (SIZE,SIZE), (0,0,0,0))
    pd = ImageDraw.Draw(pat)
    for i in range(4):
        r_ = 360 + i*85
        a = int(14 - i*2)
        pd.ellipse([(512-r_,512-r_),(512+r_,512+r_)], outline=(255,255,255,a), width=1)
    # light sheen top - very subtle now
    sheen = Image.new("RGBA", (SIZE,SIZE), (0,0,0,0))
    for y in range(320):
        a = int(10*(1 - y/320))
        ImageDraw.Draw(sheen).line([(0,y),(SIZE,y)], fill=(255,255,255,a))
    sheen = sheen.filter(ImageFilter.GaussianBlur(40))
    sheen.putalpha(Image.new("L", sheen.size, 255).point(lambda p: int(p*0.32)))
    # clip sheen to rounded rect
    sheen.putalpha(ImageChops.multiply(sheen.getchannel("A"), mask))
    base = Image.alpha_composite(base, sheen)
    base = Image.alpha_composite(base, pat)  # pat already transparent outside so ok but clip
    # clip pat also
    # final border
    border = Image.new("RGBA", (SIZE,SIZE), (0,0,0,0))
    ImageDraw.Draw(border).rounded_rectangle([(1,1),(SIZE-2,SIZE-2)], radius=RADIUS-1, outline=(255,255,255,22), width=2)
    base = Image.alpha_composite(base, border)
    return base, mask

def draw_w_and_text(base, mask):
    SIZE2 = base.size[0]
    cx = SIZE2//2
    cy = SIZE2//2 - 30
    w_half = 250
    h_half = 165
    stroke = 52
    top_y = cy - h_half
    bottom_y = cy + h_half
    mid_y = cy + 48
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
    # shadow
    sh_mask = Image.new("L", (SIZE2, SIZE2), 0)
    ImageDraw.Draw(sh_mask).polygon(points, fill=255)
    sh_mask_blur = sh_mask.filter(ImageFilter.GaussianBlur(16))
    shadow = Image.new("RGBA", (SIZE2, SIZE2), (0,0,0,90))
    shadow.putalpha(sh_mask_blur)
    shadow_off = Image.new("RGBA", (SIZE2, SIZE2), (0,0,0,0))
    shadow_off.paste(shadow, (0,9), shadow)
    shadow_off.putalpha(ImageChops.multiply(shadow_off.getchannel("A"), mask))
    base = Image.alpha_composite(base, shadow_off)
    # White W fill
    w_mask = Image.new("L", (SIZE2, SIZE2), 0)
    ImageDraw.Draw(w_mask).polygon(points, fill=255)
    w_mask = w_mask.filter(ImageFilter.GaussianBlur(0.7))
    w_fill = Image.new("RGBA", (SIZE2, SIZE2), (255,255,255,255))
    w_fill.putalpha(ImageChops.multiply(w_fill.getchannel("A"), w_mask))
    # Subtle outer glow white-gold
    glow_mask = w_mask.filter(ImageFilter.GaussianBlur(14))
    glow = Image.new("RGBA", (SIZE2, SIZE2), (255,223,90,35))
    glow.putalpha(glow_mask)
    glow.putalpha(ImageChops.multiply(glow.getchannel("A"), mask))
    base = Image.alpha_composite(base, glow)
    base = Image.alpha_composite(base, w_fill)
    # thin gold edge
    edge = Image.new("RGBA", (SIZE2, SIZE2), (0,0,0,0))
    ImageDraw.Draw(edge).polygon(points, outline=(255,193,35,170), width=2)
    edge.putalpha(ImageChops.multiply(edge.getchannel("A"), mask))
    base = Image.alpha_composite(base, edge)
    # Diamond sparkle
    # gold glow
    size_d = 26
    glow_d = Image.new("RGBA", (size_d*7, size_d*7), (0,0,0,0))
    ImageDraw.Draw(glow_d).ellipse([(0,0),(size_d*7-1,size_d*7-1)], fill=(255,235,120,60))
    glow_d = glow_d.filter(ImageFilter.GaussianBlur(14))
    tmp = Image.new("RGBA", (SIZE2, SIZE2), (0,0,0,0))
    tmp.paste(glow_d, (cx - size_d*3 -3, top_y -56 - size_d*3 -3), glow_d)
    base = Image.alpha_composite(base, tmp)
    # diamond
    draw = ImageDraw.Draw(base)
    pts = [(cx, top_y-56 - size_d), (cx + size_d*0.62, top_y-56), (cx, top_y-56 + size_d), (cx - size_d*0.62, top_y-56)]
    draw.polygon(pts, fill=(255,210,65,255), outline=(255,255,255,95), width=2)
    inner = [(cx, top_y-56 - size_d+7), (cx+8, top_y-56), (cx, top_y-56+11), (cx-8, top_y-56)]
    draw.polygon(inner, fill=(255,255,255,215))
    draw.ellipse([(cx-3, top_y-56-3),(cx+3, top_y-56+3)], fill=(255,170,20,255))
    # Underline
    line_y = bottom_y + 38
    line_w = 214
    line_h = 7
    # shadow
    sh_line = Image.new("RGBA", (SIZE2, SIZE2), (0,0,0,0))
    ImageDraw.Draw(sh_line).rounded_rectangle([(cx-line_w//2, line_y+2),(cx+line_w//2, line_y+line_h+2)], radius=3, fill=(0,0,0,50))
    sh_line = sh_line.filter(ImageFilter.GaussianBlur(5))
    base = Image.alpha_composite(base, sh_line)
    line = Image.new("RGBA", (SIZE2, SIZE2), (0,0,0,0))
    ImageDraw.Draw(line).rounded_rectangle([(cx-line_w//2, line_y),(cx+line_w//2, line_y+line_h)], radius=3, fill=(255,193,40,255))
    ImageDraw.Draw(line).rounded_rectangle([(cx-line_w//2+4, line_y+1),(cx+line_w//2-4, line_y+3)], radius=2, fill=(255,255,255,90))
    base = Image.alpha_composite(base, line)
    # glow under line
    lg = line.filter(ImageFilter.GaussianBlur(9))
    lg2 = Image.new("RGBA", (SIZE2, SIZE2), (255,193,40,38))
    lg2.putalpha(ImageChops.multiply(lg.getchannel("A"), Image.new("L", lg.size, 90)))
    base = Image.alpha_composite(base, lg2)
    # Text WINZ - large white
    # Load font
    font = None
    import os
    candidates = [r"C:\Windows\Fonts\ARIBLK.TTF", r"C:\Windows\Fonts\arialbd.ttf", r"C:\Windows\Fonts\segoeuibl.ttf", r"C:\Windows\Fonts\arial.ttf"]
    for p in candidates:
        if os.path.exists(p):
            try:
                font = ImageFont.truetype(p, 88)
                break
            except:
                pass
    if font is None:
        font = ImageFont.load_default()
    sub_font = None
    for p in candidates:
        if os.path.exists(p):
            try:
                sub_font = ImageFont.truetype(p, 26)
                break
            except:
                pass
    # Draw WINZ with tracking
    text = "WINZ"
    tracking = 20
    # measure
    tdraw = ImageDraw.Draw(base)
    widths = []
    for c in text:
        bbox = tdraw.textbbox((0,0), c, font=font)
        widths.append(bbox[2]-bbox[0])
    total = sum(widths) + tracking*(len(text)-1)
    x0 = cx - total//2
    y0 = line_y + 44
    # shadow
    sx = x0
    for i,c in enumerate(text):
        tdraw.text((sx+2, y0+3), c, font=font, fill=(0,0,0,110))
        sx += widths[i] + tracking
    sx = x0
    for i,c in enumerate(text):
        tdraw.text((sx, y0), c, font=font, fill=(255,255,255,255))
        sx += widths[i] + tracking
    # LOTTERY subtitle with tracking
    sub = "LOTTERY"
    if sub_font:
        sws=[]
        for c in sub:
            b=tdraw.textbbox((0,0), c, font=sub_font)
            sws.append(b[2]-b[0])
        strack=4
        stotal = sum(sws)+strack*(len(sub)-1)
        sx2 = cx - stotal//2
        sy = y0+88
        # shadow
        tx=sx2
        for i,c in enumerate(sub):
            tdraw.text((tx+1, sy+1), c, font=sub_font, fill=(0,0,0,70))
            tx+=sws[i]+strack
        tx=sx2
        for i,c in enumerate(sub):
            tdraw.text((tx, sy), c, font=sub_font, fill=(255,255,255,195))
            tx+=sws[i]+strack
    # Re-apply mask to ensure corners transparent correctly
    # Multiply alpha by mask
    alpha = base.getchannel("A")
    new_alpha = ImageChops.multiply(alpha, mask)
    base.putalpha(new_alpha)
    return base

def main():
    base, mask = create_base()
    final = draw_w_and_text(base, mask)
    os.makedirs(os.path.join(ROOT,"assets"), exist_ok=True)
    final.save(os.path.join(ROOT,"assets","winz_icon_1024.png"), "PNG")
    print("Master v3 saved")
    targets=[
        (r"android\app\src\main\res\mipmap-mdpi\ic_launcher.png",48),
        (r"android\app\src\main\res\mipmap-hdpi\ic_launcher.png",72),
        (r"android\app\src\main\res\mipmap-xhdpi\ic_launcher.png",96),
        (r"android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png",144),
        (r"android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png",192),
        (r"web\icons\Icon-192.png",192),
        (r"web\icons\Icon-512.png",512),
        (r"web\icons\Icon-maskable-192.png",192),
        (r"web\icons\Icon-maskable-512.png",512),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-1024x1024@1x.png",1024),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@1x.png",20),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@2x.png",40),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@3x.png",60),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@1x.png",29),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@2x.png",58),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@3x.png",87),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@1x.png",40),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@2x.png",80),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@3x.png",120),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@2x.png",120),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@3x.png",180),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@1x.png",76),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@2x.png",152),
        (r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-83.5x83.5@2x.png",167),
    ]
    for rel, sz in targets:
        p=os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        final.resize((sz,sz), Image.LANCZOS).save(p,"PNG")
        print(f" -> {rel}")
    ico_sizes=[16,24,32,48,64,128,256]
    imgs=[final.resize((s,s), Image.LANCZOS) for s in ico_sizes]
    ico_path=os.path.join(ROOT,r"windows\runner\resources\app_icon.ico")
    imgs[0].save(ico_path, format="ICO", sizes=[(im.size[0], im.size[1]) for im in imgs])
    print("ICO done")
    print("All v3 icons done")

if __name__=="__main__":
    main()
