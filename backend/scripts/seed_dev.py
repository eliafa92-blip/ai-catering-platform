"""Load synthetic data into the Supabase DEV project.

    cd backend && uv run python scripts/seed_dev.py

Steps:
  1. Create (or reset) the demo login users through the Auth admin API.
  2. Run supabase/seed.sql on the linked project (wipes and rebuilds the data).
  3. Sign in as the demo owner and upload a placeholder photo for every dish to the
     dish-images bucket, then save its path on the dish. This goes through the same
     RLS and Storage policies a real owner would hit.

Refuses to run unless APP_ENV=development and SUPABASE_URL matches the linked project.
"""

import colorsys
import struct
import subprocess  # noqa: S404 - runs the Supabase CLI with fixed arguments
import sys
import zlib
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.core.config import get_settings  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
BUCKET = "dish-images"

DEMO_USERS = [
    {"email": "owner@example.com", "full_name": "בעל העסק (דמו)", "role": "owner"},
    {"email": "dana@example.com", "full_name": "דנה כהן", "phone": "052-1234567"},
    {"email": "yossi@example.com", "full_name": "יוסי לוי", "phone": "054-2345678"},
    {"email": "noa@example.com", "full_name": "נועה מזרחי", "phone": "050-3456789"},
    {"email": "avi@example.com", "full_name": "אבי פרץ", "phone": "053-4567890"},
    {"email": "demo@example.com", "full_name": "משתמש דמו", "phone": "058-5678901"},
]


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(1)


def check_target(url: str, env: str) -> None:
    if env != "development":
        fail(f"APP_ENV is {env!r}; this script only runs against the dev project.")
    ref_file = ROOT / "supabase" / ".temp" / "project-ref"
    if not ref_file.exists():
        fail("No linked project. Run `supabase link <dev-project-ref>` first.")
    ref = ref_file.read_text().strip()
    if f"//{ref}." not in url:
        fail(f"SUPABASE_URL does not match the linked project ({ref}).")


def ensure_users(client: httpx.Client, password: str) -> None:
    existing = client.get("/auth/v1/admin/users", params={"per_page": 1000})
    existing.raise_for_status()
    by_email = {u["email"]: u for u in existing.json()["users"]}

    for user in DEMO_USERS:
        body = {
            "email": user["email"],
            "password": password,
            "email_confirm": True,
            "user_metadata": {"full_name": user["full_name"], "phone": user.get("phone", "")},
            "app_metadata": {"role": user.get("role", "customer")},
        }
        if user["email"] in by_email:
            uid = by_email[user["email"]]["id"]
            r = client.put(f"/auth/v1/admin/users/{uid}", json=body)
            action = "updated"
        else:
            r = client.post("/auth/v1/admin/users", json=body)
            action = "created"
        if r.status_code >= 400:
            fail(f"{user['email']}: {r.status_code} {r.text}")
        print(f"  {action} {user['email']} ({user.get('role', 'customer')})")


def run_seed_sql() -> None:
    cmd = ["supabase", "db", "query", "--remote", "--yes", "-o", "table", "-f", "supabase/seed.sql"]
    result = subprocess.run(  # noqa: S603 - fixed CLI call
        cmd,  # noqa: S607 - the Supabase CLI is found on PATH
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        fail(f"seed.sql failed:\n{result.stdout}\n{result.stderr}")
    print(result.stdout.strip())


def png(width: int, height: int, hue: float) -> bytes:
    """A plate-on-a-table placeholder: a soft gradient with a light circle."""
    top = [int(c * 255) for c in colorsys.hls_to_rgb(hue, 0.42, 0.45)]
    bottom = [int(c * 255) for c in colorsys.hls_to_rgb(hue, 0.25, 0.40)]
    plate = [int(c * 255) for c in colorsys.hls_to_rgb(hue, 0.92, 0.25)]
    food = [int(c * 255) for c in colorsys.hls_to_rgb((hue + 0.08) % 1, 0.55, 0.55)]
    cx, cy, r_plate, r_food = width / 2, height / 2, height * 0.38, height * 0.22
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        t = y / (height - 1)
        bg = [int(a + (b - a) * t) for a, b in zip(top, bottom, strict=True)]
        for x in range(width):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if d2 < r_food**2:
                rows.extend(food)
            elif d2 < r_plate**2:
                rows.extend(plate)
            else:
                rows.extend(bg)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )


def upload_images(base_url: str, publishable_key: str, password: str) -> None:
    with httpx.Client(base_url=base_url, headers={"apikey": publishable_key}, timeout=30) as anon:
        r = anon.post(
            "/auth/v1/token",
            params={"grant_type": "password"},
            json={"email": DEMO_USERS[0]["email"], "password": password},
        )
        if r.status_code >= 400:
            fail(f"owner sign-in failed: {r.status_code} {r.text}")
        token = r.json()["access_token"]

    headers = {"apikey": publishable_key, "Authorization": f"Bearer {token}"}
    with httpx.Client(base_url=base_url, headers=headers, timeout=30) as owner:
        dishes = owner.get(
            "/rest/v1/dishes", params={"select": "id,name,category_id", "order": "name"}
        )
        dishes.raise_for_status()
        categories = sorted({d["category_id"] for d in dishes.json()})
        for dish in dishes.json():
            hue = categories.index(dish["category_id"]) / len(categories)
            path = f"dishes/{dish['id']}.png"
            up = owner.post(
                f"/storage/v1/object/{BUCKET}/{path}",
                content=png(480, 320, hue),
                headers={"Content-Type": "image/png", "x-upsert": "true"},
            )
            if up.status_code >= 400:
                fail(f"upload {path}: {up.status_code} {up.text}")
            patch = owner.patch(
                "/rest/v1/dishes",
                params={"id": f"eq.{dish['id']}"},
                json={"image_path": path},
                headers={"Prefer": "return=minimal"},
            )
            if patch.status_code >= 400:
                fail(f"update {dish['name']}: {patch.status_code} {patch.text}")
        print(f"  uploaded {len(dishes.json())} dish images to {BUCKET}/dishes/")


def main() -> None:
    s = get_settings()
    if not (s.supabase_url and s.supabase_secret_key and s.supabase_publishable_key):
        fail("Set SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and SUPABASE_SECRET_KEY in .env.")
    password = s.demo_user_password
    if not password:
        fail("Set DEMO_USER_PASSWORD in .env.")
    check_target(s.supabase_url, s.app_env)

    print("1/3 demo users")
    with httpx.Client(
        base_url=s.supabase_url, headers={"apikey": s.supabase_secret_key}, timeout=30
    ) as admin:
        ensure_users(admin, password)

    print("2/3 synthetic data (supabase/seed.sql)")
    run_seed_sql()

    print("3/3 dish images")
    upload_images(s.supabase_url, s.supabase_publishable_key, password)
    print("done")


if __name__ == "__main__":
    main()
