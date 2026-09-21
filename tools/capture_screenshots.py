"""
BillAlert Screenshot Automation & Solid Masking Pipeline

Automates headless Microsoft Edge browser captures of the BillAlert Flutter Web
app in mobile viewport format (390 x 844 CSS @ 2x = 780 x 1688 px physical).
Applies solid rectangular masks (color #1E293B) over all sensitive personal,
meter, account, financial, and identifier data.

Usage:
    # Full capture and mask pipeline:
    python tools/capture_screenshots.py

    # Apply masks only using existing raw screenshots:
    python tools/capture_screenshots.py --mask-only

Credentials:
    Reads credentials from:
    1. Environment variables:
       BILLALERT_ADMIN_USER, BILLALERT_READER_USER, BILLALERT_CASHIER_USER, BILLALERT_CONSUMER_USER,
       and BILLALERT_PASSWORD (or BILLALERT_<ROLE>_PASS).
    2. An untracked/gitignored JSON file specified in BILLALERT_CREDENTIALS_FILE
       (default: scratch/credentials.json).

    NOTE: Usernames must be provided WITHOUT the '@billalert.local' domain suffix,
    as BillAlert automatically appends the domain during authentication.
"""

import argparse
import http.server
import json
import os
import socketserver
import sys
import tempfile
import threading
import time
from PIL import Image, ImageDraw

MASK_COLOR = (30, 41, 59)  # Slate / Dark Charcoal


def get_credentials(creds_file=None):
    """Load credentials from environment or gitignored file."""
    creds = {}
    target_file = creds_file or os.environ.get("BILLALERT_CREDENTIALS_FILE", "scratch/credentials.json")
    if os.path.exists(target_file):
        try:
            with open(target_file, "r") as f:
                creds = json.load(f)
        except Exception as e:
            print(f"Warning: Could not read {target_file}: {e}")

    # Allow environment overrides
    default_pass = os.environ.get("BILLALERT_PASSWORD", "BillAlert#2026")
    roles = {
        "admin": ("BILLALERT_ADMIN_USER", "mario.ombajin"),
        "meter_reader": ("BILLALERT_READER_USER", "ledesman.dormal"),
        "cashier": ("BILLALERT_CASHIER_USER", "mercedita.gales"),
        "consumer": ("BILLALERT_CONSUMER_USER", "virgilio.busalanan"),
    }

    resolved = {}
    for role_key, (env_var, default_user) in roles.items():
        user = os.environ.get(env_var, creds.get(role_key, {}).get("username", default_user))
        # Strip domain if present
        if "@" in user:
            user = user.split("@")[0]
        passwd = os.environ.get(f"{env_var}_PASS", creds.get(role_key, {}).get("password", default_pass))
        resolved[role_key] = {"username": user, "password": passwd}

    return resolved


def mask_rect(draw, box, radius=8):
    """Draw a solid rounded rectangle mask."""
    draw.rounded_rectangle(box, radius=radius, fill=MASK_COLOR)


# ----------------------------------------------------------------------
# Masking Routines (Calibrated for 780 x 1688 px physical resolution)
# ----------------------------------------------------------------------

def apply_masks(raw_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)

    # 1. Login
    login_path = os.path.join(raw_dir, "login.png")
    if os.path.exists(login_path):
        im = Image.open(login_path).convert("RGB")
        im.save(os.path.join(out_dir, "login.png"))
        print("Masked: login.png")

    # 2. Admin Amounts
    admin_amounts_path = os.path.join(raw_dir, "admin_amounts.png")
    if os.path.exists(admin_amounts_path):
        im = Image.open(admin_amounts_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (675, 36, 745, 106), radius=35)  # Avatar MO
        mask_rect(draw, (100, 755, 345, 798))            # Consumer name
        mask_rect(draw, (100, 808, 410, 842))            # Account / Purok
        mask_rect(draw, (100, 858, 670, 935))            # Reading details
        im.save(os.path.join(out_dir, "admin_amounts.png"))
        print("Masked: admin_amounts.png")

    # 3. Admin Notices
    admin_notices_path = os.path.join(raw_dir, "admin_notices.png")
    if os.path.exists(admin_notices_path):
        im = Image.open(admin_notices_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (675, 36, 745, 106), radius=35)  # Avatar MO
        mask_rect(draw, (100, 478, 365, 520))            # Consumer name
        mask_rect(draw, (60, 532, 570, 568))             # Notice details
        im.save(os.path.join(out_dir, "admin_notices.png"))
        print("Masked: admin_notices.png")

    # 4. Admin Accounts
    admin_accounts_path = os.path.join(raw_dir, "admin_accounts.png")
    if os.path.exists(admin_accounts_path):
        im = Image.open(admin_accounts_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (675, 36, 745, 106), radius=35)  # Avatar MO
        im.save(os.path.join(out_dir, "admin_accounts.png"))
        print("Masked: admin_accounts.png")

    # 5. Reader Readings
    reader_readings_path = os.path.join(raw_dir, "reader_readings.png")
    if os.path.exists(reader_readings_path):
        im = Image.open(reader_readings_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (225, 48, 425, 90))              # Staff title name
        mask_rect(draw, (65, 680, 330, 716))             # Consumer name
        mask_rect(draw, (65, 726, 420, 762))             # Account & Purok
        mask_rect(draw, (65, 768, 370, 804))             # Reading details
        im.save(os.path.join(out_dir, "reader_readings.png"))
        print("Masked: reader_readings.png")

    # 6. Reader Consumers
    reader_consumers_path = os.path.join(raw_dir, "reader_consumers.png")
    if os.path.exists(reader_consumers_path):
        im = Image.open(reader_consumers_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        cards = [(360, 480), (555, 675), (748, 870), (940, 1060), (1135, 1255), (1330, 1450)]
        for start_y, _ in cards:
            mask_rect(draw, (60, start_y, 146, start_y + 86), radius=43)    # Avatar
            mask_rect(draw, (170, start_y, 500, start_y + 36))              # Name
            mask_rect(draw, (170, start_y + 44, 620, start_y + 72))         # Account/Meter
            mask_rect(draw, (170, start_y + 80, 580, start_y + 116))        # Reading info
        # Partial card
        mask_rect(draw, (60, 1515, 146, 1570), radius=35)
        mask_rect(draw, (170, 1515, 420, 1550))
        im.save(os.path.join(out_dir, "reader_consumers.png"))
        print("Masked: reader_consumers.png")

    # 7. Cashier Consumers
    cashier_consumers_path = os.path.join(raw_dir, "cashier_consumers.png")
    if os.path.exists(cashier_consumers_path):
        im = Image.open(cashier_consumers_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (675, 36, 745, 106), radius=35)  # Avatar MG
        mask_rect(draw, (408, 274, 545, 300))            # Outstanding total
        for y in [365, 585, 805, 1025]:
            mask_rect(draw, (65, y, 460, y + 36))        # Name
            mask_rect(draw, (65, y + 46, 420, y + 74))   # Account
            mask_rect(draw, (565, y, 735, y + 38))       # Amount
        im.save(os.path.join(out_dir, "cashier_consumers.png"))
        print("Masked: cashier_consumers.png")

    # 8. Cashier Receipts
    cashier_receipts_path = os.path.join(raw_dir, "cashier_receipts.png")
    if os.path.exists(cashier_receipts_path):
        im = Image.open(cashier_receipts_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (675, 36, 745, 106), radius=35)  # Avatar MG
        mask_rect(draw, (60, 218, 390, 280))             # Collections amount
        mask_rect(draw, (60, 410, 390, 470))             # Still to collect
        # Receipt 1
        mask_rect(draw, (65, 760, 146, 841), radius=40)
        mask_rect(draw, (160, 755, 450, 788))
        mask_rect(draw, (155, 796, 530, 854))
        mask_rect(draw, (540, 804, 715, 836))
        # Receipt 2
        mask_rect(draw, (65, 1035, 146, 1116), radius=40)
        mask_rect(draw, (160, 1035, 450, 1068))
        mask_rect(draw, (155, 1072, 530, 1108))
        mask_rect(draw, (540, 1068, 715, 1104))
        # Receipt 3
        mask_rect(draw, (65, 1285, 146, 1366), radius=40)
        mask_rect(draw, (160, 1280, 450, 1316))
        mask_rect(draw, (155, 1320, 530, 1378))
        mask_rect(draw, (520, 1332, 715, 1368))
        # Receipt 4
        mask_rect(draw, (65, 1480, 146, 1555), radius=35)
        mask_rect(draw, (160, 1475, 450, 1510))
        mask_rect(draw, (155, 1515, 530, 1565))
        mask_rect(draw, (520, 1518, 715, 1558))
        im.save(os.path.join(out_dir, "cashier_receipts.png"))
        print("Masked: cashier_receipts.png")

    # 9. Consumer Bill
    consumer_bill_path = os.path.join(raw_dir, "consumer_bill.png")
    if os.path.exists(consumer_bill_path):
        im = Image.open(consumer_bill_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (30, 80, 200, 132))              # First name
        im.save(os.path.join(out_dir, "consumer_bill.png"))
        print("Masked: consumer_bill.png")

    # 10. Consumer History
    consumer_history_path = os.path.join(raw_dir, "consumer_history.png")
    if os.path.exists(consumer_history_path):
        im = Image.open(consumer_history_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (675, 36, 745, 106), radius=35)  # Avatar VB
        mask_rect(draw, (540, 420, 715, 458))            # Amount 1
        mask_rect(draw, (60, 472, 360, 504))             # Receipt ID 1
        mask_rect(draw, (540, 560, 715, 598))            # Amount 2
        mask_rect(draw, (60, 612, 360, 644))             # Receipt ID 2
        im.save(os.path.join(out_dir, "consumer_history.png"))
        print("Masked: consumer_history.png")

    # 11. Consumer Inbox
    consumer_inbox_path = os.path.join(raw_dir, "consumer_inbox.png")
    if os.path.exists(consumer_inbox_path):
        im = Image.open(consumer_inbox_path).convert("RGB")
        draw = ImageDraw.Draw(im)
        mask_rect(draw, (675, 36, 745, 106), radius=35)  # Avatar VB
        for top_y, bottom_y in [(485, 565), (768, 848), (1050, 1132), (1334, 1416)]:
            mask_rect(draw, (160, top_y, 725, bottom_y)) # Body
        im.save(os.path.join(out_dir, "consumer_inbox.png"))
        print("Masked: consumer_inbox.png")

    print(f"All screenshots successfully masked to {out_dir}!")


# ----------------------------------------------------------------------
# Browser Automation (Playwright + Edge Headless)
# ----------------------------------------------------------------------

def run_capture(raw_dir, creds, port=8080):
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("Error: playwright is required for browser captures. Run: pip install playwright")
        sys.exit(1)

    build_dir = os.path.abspath("build/web")
    if not os.path.isdir(build_dir):
        print(f"Error: Flutter web build not found at {build_dir}.")
        print("Run: flutter build web --dart-define-from-file=env.json")
        sys.exit(1)

    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=build_dir, **kwargs)
        def log_message(self, *args):
            pass

    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("", port), QuietHandler)
    server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    server_thread.start()
    time.sleep(1)

    os.makedirs(raw_dir, exist_ok=True)
    base_url = f"http://localhost:{port}"

    with sync_playwright() as p:
        browser = p.chromium.launch(channel="msedge", headless=True)

        def new_mobile_page():
            ctx = browser.new_context(
                viewport={"width": 390, "height": 844},
                device_scale_factor=2,
                is_mobile=True,
                has_touch=True,
            )
            return ctx, ctx.new_page()

        def login_and_wait(role_key, role_label):
            print(f"Signing in as {role_label}...")
            ctx, page = new_mobile_page()
            page.goto(base_url, wait_until="networkidle")
            page.wait_for_timeout(3000)

            # Enable CanvasKit accessibility tree
            page.evaluate("() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); }")
            page.wait_for_timeout(1000)

            # Enter credentials (username without domain)
            u_field = page.query_selector("input[type='text']")
            p_field = page.query_selector("input[type='password']")
            u_field.fill(creds[role_key]["username"])
            p_field.fill(creds[role_key]["password"])
            p_field.press("Enter")

            # Wait for data load
            page.wait_for_timeout(7000)
            return ctx, page

        # 1. Login
        print("Capturing login screen...")
        ctx_login, page_login = new_mobile_page()
        page_login.goto(base_url, wait_until="networkidle")
        page_login.wait_for_timeout(3500)
        page_login.screenshot(path=os.path.join(raw_dir, "login.png"))
        ctx_login.close()

        # 2. Admin
        ctx_admin, page_admin = login_and_wait("admin", "Admin")
        page_admin.screenshot(path=os.path.join(raw_dir, "admin_amounts.png"))
        page_admin.touchscreen.tap(146, 790)  # Tab 1: Notices
        page_admin.wait_for_timeout(3000)
        page_admin.screenshot(path=os.path.join(raw_dir, "admin_notices.png"))
        page_admin.touchscreen.tap(244, 790)  # Tab 2: Accounts
        page_admin.wait_for_timeout(3000)
        page_admin.screenshot(path=os.path.join(raw_dir, "admin_accounts.png"))
        ctx_admin.close()

        # 3. Meter Reader
        ctx_reader, page_reader = login_and_wait("meter_reader", "Meter Reader")
        page_reader.screenshot(path=os.path.join(raw_dir, "reader_readings.png"))
        page_reader.touchscreen.tap(146, 790)  # Tab 1: Consumers
        page_reader.wait_for_timeout(3000)
        page_reader.screenshot(path=os.path.join(raw_dir, "reader_consumers.png"))
        ctx_reader.close()

        # 4. Cashier
        ctx_cashier, page_cashier = login_and_wait("cashier", "Cashier")
        page_cashier.screenshot(path=os.path.join(raw_dir, "cashier_consumers.png"))
        page_cashier.touchscreen.tap(146, 790)  # Tab 1: Receipts
        page_cashier.wait_for_timeout(3000)
        page_cashier.screenshot(path=os.path.join(raw_dir, "cashier_receipts.png"))
        ctx_cashier.close()

        # 5. Consumer
        ctx_consumer, page_consumer = login_and_wait("consumer", "Consumer")
        page_consumer.screenshot(path=os.path.join(raw_dir, "consumer_bill.png"))
        page_consumer.touchscreen.tap(146, 790)  # Tab 1: History
        page_consumer.wait_for_timeout(3000)
        page_consumer.screenshot(path=os.path.join(raw_dir, "consumer_history.png"))
        page_consumer.touchscreen.tap(244, 790)  # Tab 2: Inbox
        page_consumer.wait_for_timeout(3000)
        page_consumer.screenshot(path=os.path.join(raw_dir, "consumer_inbox.png"))
        ctx_consumer.close()

        browser.close()
        httpd.shutdown()
        print("All raw captures complete!")


def main():
    parser = argparse.ArgumentParser(description="Capture and mask BillAlert screenshots.")
    parser.add_argument("--mask-only", action="store_true", help="Skip browser capture; mask existing raw screenshots.")
    parser.add_argument("--raw-dir", default="scratch/raw", help="Directory with unmasked raw screenshots.")
    parser.add_argument("--out-dir", default="docs/screenshots", help="Directory to save masked screenshots.")
    parser.add_argument("--creds-file", default=None, help="Path to credentials JSON file.")
    args = parser.parse_args()

    if not args.mask_only:
        creds = get_credentials(args.creds_file)
        run_capture(args.raw_dir, creds)

    apply_masks(args.raw_dir, args.out_dir)


if __name__ == "__main__":
    main()
