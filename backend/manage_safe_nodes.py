from __future__ import annotations

import argparse

from sqlalchemy import select

from app.config import settings
from app.db import Base, apply_compat_migrations, build_engine, build_session_factory
from app.models import SafeNode


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Manage operator-verified ViraNari Safe Nodes")
    sub = p.add_subparsers(dest="command", required=True)

    add = sub.add_parser("add", help="Add a Safe Node after checking the real place and coordinates")
    add.add_argument("--name", required=True)
    add.add_argument("--category", required=True, choices=["police", "hospital", "pharmacy", "campus_security", "hostel_desk", "petrol_pump", "staffed_place", "other"])
    add.add_argument("--lat", required=True, type=float)
    add.add_argument("--lon", required=True, type=float)
    add.add_argument("--phone")
    add.add_argument("--address")
    add.add_argument("--verified", action="store_true", help="Mark verified only after a human has checked the node")

    sub.add_parser("list", help="List Safe Nodes")

    disable = sub.add_parser("disable", help="Disable a Safe Node")
    disable.add_argument("id")

    verify = sub.add_parser("verify", help="Mark an existing Safe Node verified")
    verify.add_argument("id")

    return p


def main() -> None:
    args = parser().parse_args()
    engine = build_engine(settings.database_path)
    apply_compat_migrations(engine)
    Base.metadata.create_all(engine)
    SessionLocal = build_session_factory(engine)

    with SessionLocal() as db:
        if args.command == "add":
            if not (-90 <= args.lat <= 90 and -180 <= args.lon <= 180):
                raise SystemExit("Invalid latitude/longitude")
            node = SafeNode(
                name=args.name.strip(),
                category=args.category,
                latitude=args.lat,
                longitude=args.lon,
                phone_e164=args.phone,
                address=args.address,
                verified=bool(args.verified),
                active=True,
            )
            db.add(node)
            db.commit()
            db.refresh(node)
            print(f"added {node.id} | {node.name} | verified={node.verified}")
            return

        if args.command == "list":
            rows = db.scalars(select(SafeNode).order_by(SafeNode.created_at.desc())).all()
            if not rows:
                print("No Safe Nodes configured.")
                return
            for n in rows:
                print(f"{n.id} | {n.name} | {n.category} | {n.latitude:.6f},{n.longitude:.6f} | verified={n.verified} active={n.active}")
            return

        node = db.get(SafeNode, args.id)
        if node is None:
            raise SystemExit("Safe Node not found")
        if args.command == "disable":
            node.active = False
            db.commit()
            print(f"disabled {node.id} | {node.name}")
        elif args.command == "verify":
            node.verified = True
            node.active = True
            db.commit()
            print(f"verified {node.id} | {node.name}")


if __name__ == "__main__":
    main()
