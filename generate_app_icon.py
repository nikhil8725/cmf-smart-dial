import os
import math
import subprocess
from PIL import Image, ImageDraw, ImageFilter

def create_cmf_dial_icon(size=2048):
    """
    Renders a custom macOS squircle app icon for CMF Smart Dial at high resolution.
    Features:
    - macOS standard squircle base with sleek deep-graphite matte finish
    - Signature CMF vibrant orange metallic rotary bezel with knurling notches
    - Fine concentric machined dial grooves (CD texture)
    - Nothing-style dot matrix detent indicators
    - Sleek knurled center knob with a glowing orange positional marker
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2
    # Squircle parameters for macOS icon
    margin = int(size * 0.08)
    corner = int(size * 0.22)
    box = [margin, margin, size - margin, size - margin]

    # 1. Subtle drop shadow for the squircle
    shadow_offset = int(size * 0.02)
    shadow_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow_img)
    sdraw.rounded_rectangle(
        [margin, margin + shadow_offset, size - margin, size - margin + shadow_offset],
        radius=corner,
        fill=(0, 0, 0, 160)
    )
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(int(size * 0.035)))
    img = Image.alpha_composite(shadow_img, img)
    draw = ImageDraw.Draw(img)

    # 2. Main squircle background - Deep graphite matte gradient
    # We create a vertical gradient
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    bg_draw.rounded_rectangle(box, radius=corner, fill=(24, 25, 29, 255))
    
    # Inner border / chamfer highlight
    border_width = int(size * 0.006)
    bg_draw.rounded_rectangle(
        box,
        radius=corner,
        outline=(255, 255, 255, 30),
        width=border_width
    )
    img = Image.alpha_composite(img, bg)
    draw = ImageDraw.Draw(img)

    # 3. Outer Dial Ring / Chassis Bezel
    outer_radius = int(size * 0.35)
    
    # Dial track shadow
    track_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ts_draw = ImageDraw.Draw(track_shadow)
    ts_draw.ellipse(
        [cx - outer_radius, cy - outer_radius + int(size * 0.015),
         cx + outer_radius, cy + outer_radius + int(size * 0.015)],
        fill=(0, 0, 0, 180)
    )
    track_shadow = track_shadow.filter(ImageFilter.GaussianBlur(int(size * 0.02)))
    img = Image.alpha_composite(img, track_shadow)
    draw = ImageDraw.Draw(img)

    # Outer metallic ring
    draw.ellipse(
        [cx - outer_radius, cy - outer_radius, cx + outer_radius, cy + outer_radius],
        fill=(18, 19, 22, 255),
        outline=(50, 52, 60, 255),
        width=int(size * 0.008)
    )

    # 4. Signature CMF Orange Rotary Ring
    orange_outer = int(size * 0.33)
    orange_inner = int(size * 0.26)
    
    # Draw CMF orange ring
    draw.ellipse(
        [cx - orange_outer, cy - orange_outer, cx + orange_outer, cy + orange_outer],
        fill=(255, 78, 18, 255) # CMF Iconic Orange
    )
    
    # Inner cutout for dial body
    draw.ellipse(
        [cx - orange_inner, cy - orange_inner, cx + orange_inner, cy + orange_inner],
        fill=(20, 21, 24, 255)
    )

    # Add mechanical knurling teeth around the CMF orange wheel
    num_teeth = 48
    tooth_len = (orange_outer - orange_inner) * 0.5
    for i in range(num_teeth):
        angle = 2 * math.pi * i / num_teeth
        r1 = orange_outer - int(size * 0.004)
        r2 = r1 - tooth_len
        x1 = cx + r1 * math.cos(angle)
        y1 = cy + r1 * math.sin(angle)
        x2 = cx + r2 * math.cos(angle)
        y2 = cy + r2 * math.sin(angle)
        draw.line([(x1, y1), (x2, y2)], fill=(200, 45, 0, 220), width=int(size * 0.005))

    # Highlights on orange ring
    draw.arc(
        [cx - orange_outer, cy - orange_outer, cx + orange_outer, cy + orange_outer],
        start=200, end=340, fill=(255, 145, 90, 240), width=int(size * 0.008)
    )

    # 5. Concentric machined dial face (Brushed metal finish)
    num_grooves = 16
    for i in range(num_grooves):
        r = orange_inner - int(i * (orange_inner * 0.05))
        alpha = int(25 + 30 * (i % 2))
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, alpha), width=int(size * 0.002))

    # 6. Nothing-style Dot Detents (12 clock positions)
    detent_r = int((orange_inner + orange_outer) / 2)
    for i in range(12):
        angle = 2 * math.pi * i / 12 - math.pi / 2
        px = cx + detent_r * math.cos(angle)
        py = cy + detent_r * math.sin(angle)
        dot_r = int(size * 0.008) if i % 3 == 0 else int(size * 0.005)
        dot_color = (255, 255, 255, 240) if i % 3 == 0 else (255, 220, 180, 200)
        draw.ellipse([px - dot_r, py - dot_r, px + dot_r, py + dot_r], fill=dot_color)

    # 7. Center Raised Knob (tactile, frosted dark aluminum)
    knob_r = int(size * 0.17)
    
    # Knob drop shadow
    ks = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ks_draw = ImageDraw.Draw(ks)
    ks_draw.ellipse(
        [cx - knob_r, cy - knob_r + int(size * 0.01), cx + knob_r, cy + knob_r + int(size * 0.01)],
        fill=(0, 0, 0, 200)
    )
    ks = ks.filter(ImageFilter.GaussianBlur(int(size * 0.015)))
    img = Image.alpha_composite(img, ks)
    draw = ImageDraw.Draw(img)

    # Knob base
    draw.ellipse(
        [cx - knob_r, cy - knob_r, cx + knob_r, cy + knob_r],
        fill=(32, 34, 38, 255),
        outline=(70, 72, 80, 255),
        width=int(size * 0.006)
    )

    # Knob top highlight & gradient bevel
    draw.arc(
        [cx - knob_r, cy - knob_r, cx + knob_r, cy + knob_r],
        start=210, end=330, fill=(255, 255, 255, 120), width=int(size * 0.008)
    )

    # 8. Illuminated Marker / Notch (pointing at ~2 o'clock, active dynamic position)
    marker_angle = math.radians(45) # 45 degrees
    m_r1 = knob_r - int(size * 0.01)
    m_r2 = knob_r - int(size * 0.065)
    mx1 = cx + m_r1 * math.cos(marker_angle)
    my1 = cy + m_r1 * math.sin(marker_angle)
    mx2 = cx + m_r2 * math.cos(marker_angle)
    my2 = cy + m_r2 * math.sin(marker_angle)
    
    # Indicator glow
    ind_glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ig_draw = ImageDraw.Draw(ind_glow)
    ig_draw.line([(mx1, my1), (mx2, my2)], fill=(255, 90, 20, 200), width=int(size * 0.02))
    ind_glow = ind_glow.filter(ImageFilter.GaussianBlur(int(size * 0.012)))
    img = Image.alpha_composite(img, ind_glow)
    draw = ImageDraw.Draw(img)

    # Crisp indicator notch
    draw.line([(mx1, my1), (mx2, my2)], fill=(255, 255, 255, 255), width=int(size * 0.008))

    # Center mini pivot
    pivot_r = int(size * 0.02)
    draw.ellipse(
        [cx - pivot_r, cy - pivot_r, cx + pivot_r, cy + pivot_r],
        fill=(15, 16, 18, 255),
        outline=(255, 80, 20, 180),
        width=int(size * 0.003)
    )

    return img

def main():
    print("Generating high-res 2048x2048 icon...")
    master = create_cmf_dial_icon(2048)
    
    # Target 1024x1024 supersampled
    icon_1024 = master.resize((1024, 1024), Image.LANCZOS)
    
    iconset_dir = "AppIcon.iconset"
    os.makedirs(iconset_dir, exist_ok=True)

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for filename, s in sizes:
        resized = icon_1024.resize((s, s), Image.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename), "PNG")
        print(f"Generated {filename} ({s}x{s})")

    # Also update xcassets icon files
    xcassets_dir = "Dial/Assets.xcassets/AppIcon.appiconset"
    if os.path.exists(xcassets_dir):
        icon_1024.save(os.path.join(xcassets_dir, "icon-1024.png"), "PNG")
        for s in [16, 32, 64, 128, 256, 512]:
            icon_1024.resize((s, s), Image.LANCZOS).save(os.path.join(xcassets_dir, f"icon-{s}.png"), "PNG")
        print("Updated Assets.xcassets icon files")

    # Compile with iconutil
    print("Compiling AppIcon.icns via iconutil...")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", "Dial/AppIcon.icns"], check=True)
    print("✅ Successfully generated Dial/AppIcon.icns")

if __name__ == "__main__":
    main()
