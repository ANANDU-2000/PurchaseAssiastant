"""
Comprehensive mock data seed script for local development with SQLite.
Run: python -m scripts.seed_mock_data
"""

import asyncio
import os
import sys
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

os.environ["APP_ENV"] = "development"
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./hexa_dev.db"
os.environ["HEXA_USE_SQLITE"] = "1"
os.environ["ALLOW_PUBLIC_REGISTRATION"] = "1"
os.environ["JWT_SECRET"] = "mock-dev-jwt-secret-that-is-at-least-48-chars-long-for-hexa"
os.environ["JWT_REFRESH_SECRET"] = "mock-dev-refresh-secret-that-is-at-least-48-chars-long"

import app.models
from app.database import async_session_factory, engine
from app.models import Base
from app.models.user import User
from app.models.business import Business
from app.models.membership import Membership
from app.models.catalog import CatalogItem, CategoryType, ItemCategory
from app.models.unit_intelligence import MasterUnit, ItemPackagingProfile
from app.models.contacts import Broker, Supplier
from app.models.trade_purchase import TradePurchase, TradePurchaseLine, BrokerSupplierLink
from app.models.stock_movement import StockMovement

from bcrypt import hashpw, gensalt


def utcnow():
    return datetime.now(timezone.utc)


def hash_password(password: str) -> str:
    return hashpw(password.encode("utf-8"), gensalt()).decode("utf-8")


async def seed():
    print("Creating tables...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with async_session_factory() as session:
        # ── Admin User ──
        admin_id = uuid.uuid4()
        admin = User(
            id=admin_id,
            email="admin@purchase.local",
            username="admin",
            password_hash=hash_password("admin123"),
            name="Admin User",
            is_super_admin=True,
            is_active=True,
            created_at=utcnow(),
        )
        session.add(admin)
        print(f"Created admin user: admin@purchase.local / admin123")

        # ── Business ──
        biz_id = uuid.uuid4()
        biz = Business(
            id=biz_id,
            name="New Harisree Agency",
            gst_number="33ABCDE1234F1Z5",
            address="42, Market Street, Coimbatore - 641001",
            phone="+919876543210",
            contact_email="harisree@example.com",
            default_currency="INR",
            created_at=utcnow(),
        )
        session.add(biz)

        # ── Membership (admin as owner) ──
        membership = Membership(
            id=uuid.uuid4(),
            user_id=admin_id,
            business_id=biz_id,
            role="owner",
            created_at=utcnow(),
        )
        session.add(membership)

        # ── Owner User (separate from admin) ──
        owner_id = uuid.uuid4()
        owner = User(
            id=owner_id,
            email="owner@harisree.local",
            username="harisree_owner",
            password_hash=hash_password("owner123"),
            name="S. Kumar (Owner)",
            is_super_admin=False,
            is_active=True,
            created_at=utcnow(),
        )
        session.add(owner)

        membership2 = Membership(
            id=uuid.uuid4(),
            user_id=owner_id,
            business_id=biz_id,
            role="owner",
            created_at=utcnow(),
        )
        session.add(membership2)

        # ── Manager User ──
        manager_id = uuid.uuid4()
        manager = User(
            id=manager_id,
            email="manager@harisree.local",
            username="harisree_mgr",
            password_hash=hash_password("mgr123"),
            name="R. Rajesh (Manager)",
            is_super_admin=False,
            is_active=True,
            created_at=utcnow(),
        )
        session.add(manager)

        membership3 = Membership(
            id=uuid.uuid4(),
            user_id=manager_id,
            business_id=biz_id,
            role="manager",
            created_at=utcnow(),
        )
        session.add(membership3)

        # ── Master Units ──
        units_data = [
            ("BAG", "Bag", "weight"),
            ("KG", "Kilogram", "weight"),
            ("BOX", "Box", "packaged"),
            ("TIN", "Tin", "packaged"),
            ("LTR", "Litre", "liquid"),
            ("PCS", "Pieces", "count"),
            ("CARTON", "Carton", "packaged"),
            ("DRUM", "Drum", "liquid"),
            ("SACK", "Sack", "weight"),
            ("GRAM", "Gram", "weight"),
        ]
        unit_map = {}
        for code, name, cat in units_data:
            u = MasterUnit(unit_code=code, display_name=name, category=cat)
            session.add(u)
            unit_map[code] = u
        print("Created 10 master units")

        # ── Categories ──
        cats_data = [
            ("Rice", False),
            ("Oil", False),
            ("Spices", False),
            ("Dal & Pulses", False),
            ("Wheat & Flour", False),
            ("Sugar & Jaggery", False),
            ("Dry Fruits", False),
            ("Snacks & Food", True),
            ("Cleaning & Household", False),
            ("Beverages", True),
        ]
        cat_map = {}
        for name, perishable in cats_data:
            c = ItemCategory(id=uuid.uuid4(), business_id=biz_id, name=name, is_perishable=perishable)
            session.add(c)
            cat_map[name] = c

        # ── Category Types ──
        types_data = {
            "Rice": ["Basmati Rice", "Ponni Rice", "Idly Rice", "Biriyani Rice"],
            "Oil": ["Sunflower Oil", "Groundnut Oil", "Coconut Oil", "Palm Oil"],
            "Spices": ["Chilli Powder", "Turmeric Powder", "Coriander Powder", "Garam Masala"],
            "Dal & Pulses": ["Toor Dal", "Urad Dal", "Moong Dal", "Channa Dal"],
            "Wheat & Flour": ["Wheat Flour", "Rava", "Maida"],
            "Sugar & Jaggery": ["White Sugar", "Jaggery"],
            "Dry Fruits": ["Almonds", "Cashews", "Raisins"],
            "Snacks & Food": ["Biscuits", "Namkeen"],
            "Cleaning & Household": ["Detergent", "Soap"],
            "Beverages": ["Tea", "Coffee"],
        }
        type_map = {}
        for cat_name, type_names in types_data.items():
            parent_cat = cat_map[cat_name]
            for tname in type_names:
                ct = CategoryType(id=uuid.uuid4(), category_id=parent_cat.id, name=tname)
                session.add(ct)
                type_map[tname] = ct

        # ── Catalog Items ──
        items_data = [
            ("Basmati Rice", "Rice", "Basmati Rice", "BAG", 500, Decimal("25.000"), 45, 55, Decimal("25.000"), "10063090"),
            ("Ponni Rice (Premium)", "Rice", "Ponni Rice", "BAG", 250, Decimal("50.000"), 28, 35, Decimal("25.000"), "10063090"),
            ("Idly Rice", "Rice", "Idly Rice", "SACK", 300, Decimal("25.000"), 22, 28, Decimal("25.000"), "10063090"),
            ("Biriyani Rice (Seeraga Samba)", "Rice", "Biriyani Rice", "BAG", 400, Decimal("25.000"), 55, 65, Decimal("25.000"), "10063090"),
            ("Sunflower Oil", "Oil", "Sunflower Oil", "TIN", 120, Decimal("1.000"), 155, 170, Decimal("15.000"), "15079090"),
            ("Groundnut Oil", "Oil", "Groundnut Oil", "TIN", 80, Decimal("1.000"), 185, 200, Decimal("15.000"), "15079090"),
            ("Coconut Oil", "Oil", "Coconut Oil", "TIN", 60, Decimal("1.000"), 165, 185, Decimal("15.000"), "15131100"),
            ("Chilli Powder", "Spices", "Chilli Powder", "KG", 100, Decimal("1.000"), 95, 120, Decimal("1.000"), "09042211"),
            ("Turmeric Powder", "Spices", "Turmeric Powder", "KG", 80, Decimal("1.000"), 140, 170, Decimal("1.000"), "09103010"),
            ("Coriander Powder", "Spices", "Coriander Powder", "KG", 90, Decimal("1.000"), 80, 100, Decimal("1.000"), "09093200"),
            ("Toor Dal", "Dal & Pulses", "Toor Dal", "BAG", 200, Decimal("25.000"), 85, 105, Decimal("25.000"), "07133110"),
            ("Urad Dal", "Dal & Pulses", "Urad Dal", "BAG", 180, Decimal("25.000"), 90, 110, Decimal("25.000"), "07133120"),
            ("Moong Dal", "Dal & Pulses", "Moong Dal", "BAG", 150, Decimal("25.000"), 75, 95, Decimal("25.000"), "07133130"),
            ("Wheat Flour (Atta)", "Wheat & Flour", "Wheat Flour", "BAG", 100, Decimal("25.000"), 22, 30, Decimal("25.000"), "10011000"),
            ("Rava (Semolina)", "Wheat & Flour", "Rava", "KG", 120, Decimal("1.000"), 28, 38, Decimal("1.000"), "19021100"),
            ("White Sugar", "Sugar & Jaggery", "White Sugar", "BAG", 500, Decimal("25.000"), 38, 45, Decimal("25.000"), "17011410"),
            ("Jaggery (Gur)", "Sugar & Jaggery", "Jaggery", "KG", 50, Decimal("1.000"), 40, 55, Decimal("1.000"), "17011310"),
            ("Almonds (Badam)", "Dry Fruits", "Almonds", "KG", 30, Decimal("1.000"), 480, 550, Decimal("1.000"), "08021100"),
            ("Cashews (Kaju)", "Dry Fruits", "Cashews", "KG", 40, Decimal("1.000"), 650, 720, Decimal("1.000"), "08013100"),
            ("Tea (Brookefield)", "Beverages", "Tea", "CARTON", 200, Decimal("1.000"), 120, 145, Decimal("1.000"), "09021000"),
            ("Coffee (Filter)", "Beverages", "Coffee", "CARTON", 150, Decimal("1.000"), 180, 210, Decimal("1.000"), "09011129"),
        ]
        item_map = {}
        for name, cat_name, type_name, unit, qty, kg_per_bag, landing, selling, default_qty, hsn in items_data:
            cat = cat_map[cat_name]
            ct = type_map.get(type_name)
            item_id = uuid.uuid4()
            item = CatalogItem(
                id=item_id,
                business_id=biz_id,
                category_id=cat.id,
                type_id=ct.id if ct else None,
                name=name,
                default_unit=unit,
                default_kg_per_bag=kg_per_bag,
                default_landing_cost=Decimal(str(landing)),
                default_selling_cost=Decimal(str(selling)),
                default_purchase_unit=unit,
                default_sale_unit=unit,
                hsn_code=hsn,
                stock_unit=unit,
                selling_unit=unit,
                display_unit=unit,
                item_code=hsn + str(hash(name))[-4:],
                barcode=f"890{hash(name) % 10000000000:010d}",
                created_at=utcnow(),
            )
            session.add(item)
            item_map[name] = item_id

        # ── Brokers ──
        brokers_data = [
            ("Rajesh Broker", "9876543211", "Coimbatore", "percent", Decimal("1.5"), 15),
            ("Muthu & Co", "9876543212", "Erode", "percent", Decimal("1.0"), 10),
            ("Gopal Traders", "9876543213", "Tirupur", "percent", Decimal("2.0"), 20),
        ]
        broker_map = {}
        for name, phone, loc, comm_type, comm_val, pay_days in brokers_data:
            b = Broker(
                id=uuid.uuid4(),
                business_id=biz_id,
                name=name,
                phone=phone,
                location=loc,
                commission_type=comm_type,
                commission_value=comm_val,
                default_payment_days=pay_days,
                created_at=utcnow(),
            )
            session.add(b)
            broker_map[name] = b
        print("Created 3 brokers")

        # ── Suppliers ──
        suppliers_data = [
            ("Karnataka Rice Mills", "9888888801", "33AABBCCDD1E1Z5", 15, "Bagalkot"),
            ("TN Rice Traders", "9888888802", "33EERRTTEE2F2Z6", 20, "Thanjavur"),
            ("Ponni Speciality Rice", "9888888803", "33EEWWQQAA3G3Z7", 10, "Kumbakonam"),
            ("Seeraga Samba Exports", "9888888804", "33RRTTYYUU4H4Z8", 15, "Ramanathapuram"),
            ("Kerala Coconut Oil", "9888888805", "32DDSSAA5I5Z9", 10, "Palakkad"),
            ("Modern Oil Traders", "9888888806", "33FFGGHH6J6Z1", 20, "Chennai"),
            ("Anand Spices", "9888888807", "33HHJJKK7K7Z2", 10, "Salem"),
            ("Dal Bhandar", "9888888808", "33LLMMNN8L8Z3", 15, "Mumbai"),
            ("North Indian Grains", "9888888809", "33OOPPQQ9M9Z4", 12, "Delhi"),
            ("Local Sugar Mills", "9888888810", "33RRSSTT0N0Z5", 10, "Erode"),
            ("Dry Fruit House", "9888888811", "33UUVVWW1O1Z6", 7, "Mumbai"),
            ("Tea & Coffee Co.", "9888888812", "33XXYYZZ2P2Z7", 10, "Coonoor"),
        ]
        supplier_map = {}
        for name, phone, gst, pay_days, loc in suppliers_data:
            s = Supplier(
                id=uuid.uuid4(),
                business_id=biz_id,
                name=name,
                phone=phone,
                gst_number=gst,
                default_payment_days=pay_days,
                location=loc,
                created_at=utcnow(),
            )
            session.add(s)
            supplier_map[name] = s
        print("Created 12 suppliers")

        # Link brokers to suppliers
        for bname, sname in [
            ("Rajesh Broker", "Karnataka Rice Mills"),
            ("Rajesh Broker", "TN Rice Traders"),
            ("Muthu & Co", "Ponni Speciality Rice"),
            ("Muthu & Co", "Kerala Coconut Oil"),
            ("Gopal Traders", "Seeraga Samba Exports"),
            ("Gopal Traders", "Modern Oil Traders"),
        ]:
            link = BrokerSupplierLink(
                id=uuid.uuid4(),
                broker_id=broker_map[bname].id,
                supplier_id=supplier_map[sname].id,
            )
            session.add(link)

        print("Created broker-supplier links")

        # Set broker on some suppliers
        supplier_map["Karnataka Rice Mills"].broker_id = broker_map["Rajesh Broker"].id
        supplier_map["Ponni Speciality Rice"].broker_id = broker_map["Muthu & Co"].id
        supplier_map["Seeraga Samba Exports"].broker_id = broker_map["Gopal Traders"].id

        kg_per_bag_map = {}
        for name, _cat_name, _type_name, unit, _qty, kg_per_bag, _landing, _selling, _default_qty, _hsn in items_data:
            kg_per_bag_map[name] = kg_per_bag

        # ── Trade Purchases ──
        purchases_data = [
            # (human_id, invoice, purchase_date, supplier_name, broker_name, items [(item_name, qty, unit, purchase_rate, selling_rate, landing_cost)])
            (
                "PUR-2025-001", "INV-001", date(2025, 6, 15),
                "Karnataka Rice Mills", "Rajesh Broker",
                [
                    ("Basmati Rice", 20, "BAG", Decimal("2000"), Decimal("2200"), Decimal("2000")),
                    ("Ponni Rice (Premium)", 30, "BAG", Decimal("1250"), Decimal("1400"), Decimal("1250")),
                ],
                77500, Decimal("1.5"),
            ),
            (
                "PUR-2025-002", "INV-002", date(2025, 6, 20),
                "Ponni Speciality Rice", "Muthu & Co",
                [
                    ("Idly Rice", 25, "BAG", Decimal("950"), Decimal("1050"), Decimal("950")),
                    ("Biriyani Rice (Seeraga Samba)", 15, "BAG", Decimal("2400"), Decimal("2600"), Decimal("2400")),
                ],
                59750, Decimal("1.0"),
            ),
            (
                "PUR-2025-003", "INV-003", date(2025, 6, 25),
                "Modern Oil Traders", "Gopal Traders",
                [
                    ("Sunflower Oil", 50, "TIN", Decimal("1480"), Decimal("1550"), Decimal("1480")),
                    ("Groundnut Oil", 30, "TIN", Decimal("1780"), Decimal("1850"), Decimal("1780")),
                ],
                127400, Decimal("2.0"),
            ),
            (
                "PUR-2025-004", "INV-004", date(2025, 7, 1),
                "Anand Spices", None,
                [
                    ("Chilli Powder", 40, "KG", Decimal("90"), Decimal("110"), Decimal("90")),
                    ("Turmeric Powder", 30, "KG", Decimal("135"), Decimal("160"), Decimal("135")),
                ],
                7650, None,
            ),
            (
                "PUR-2025-005", "INV-005", date(2025, 7, 5),
                "Dal Bhandar", None,
                [
                    ("Toor Dal", 20, "BAG", Decimal("2050"), Decimal("2100"), Decimal("2050")),
                    ("Urad Dal", 15, "BAG", Decimal("2150"), Decimal("2200"), Decimal("2150")),
                ],
                73250, None,
            ),
            (
                "PUR-2025-006", "INV-006", date(2025, 7, 10),
                "Local Sugar Mills", None,
                [
                    ("White Sugar", 50, "BAG", Decimal("1700"), Decimal("1850"), Decimal("1700")),
                ],
                85000, None,
            ),
        ]

        all_purchases = []
        for h_id, inv, pdate, sname, bname, lines, total, comm_pct in purchases_data:
            s = supplier_map[sname]
            b = broker_map.get(bname) if bname else None
            total_qty = sum(line[1] for line in lines)
            due = pdate + timedelta(days=s.default_payment_days or 15)

            tp = TradePurchase(
                id=uuid.uuid4(),
                business_id=biz_id,
                user_id=admin_id,
                human_id=h_id,
                invoice_number=inv,
                purchase_date=pdate,
                supplier_id=s.id,
                broker_id=b.id if b else None,
                payment_days=s.default_payment_days or 15,
                due_date=due,
                paid_amount=Decimal("0"),
                discount=Decimal("0"),
                commission_percent=comm_pct,
                commission_mode="percent" if comm_pct else None,
                total_qty=Decimal(str(total_qty)),
                total_amount=total,
                status="confirmed",
                is_delivered=True,
                delivery_status="delivered",
                delivered_at=utcnow(),
                stock_committed_at=utcnow(),
                created_at=utcnow(),
            )
            session.add(tp)

            for item_name, qty, unit, purch_rate, sell_rate, lc in lines:
                cat_item_id = item_map[item_name]
                line = TradePurchaseLine(
                    id=uuid.uuid4(),
                    trade_purchase_id=tp.id,
                    catalog_item_id=cat_item_id,
                    item_name=item_name,
                    qty=Decimal(str(qty)),
                    unit=unit,
                    qty_in_stock_unit=Decimal(str(qty)),
                    unit_type="weight",
                    purchase_rate=purch_rate,
                    selling_rate=sell_rate,
                    delivered_rate=purch_rate,
                    landing_cost=lc,
                    line_total=Decimal(str(qty)) * lc,
                    profit=(Decimal(str(qty)) * sell_rate) - (Decimal(str(qty)) * lc),
                    kg_per_unit=kg_per_bag_map.get(item_name, Decimal("1.000")),
                    landing_cost_per_kg=lc / kg_per_bag_map.get(item_name, Decimal("1.000")) if kg_per_bag_map.get(item_name, Decimal("1.000")) else lc,
                    received_qty=Decimal(str(qty)),
                    damaged_qty=Decimal("0"),
                    return_qty=Decimal("0"),
                )
                session.add(line)

                stock = StockMovement(
                    id=uuid.uuid4(),
                    business_id=biz_id,
                    item_id=cat_item_id,
                    movement_kind="in",
                    delta_qty=Decimal(str(qty)),
                    qty_before=Decimal("0"),
                    qty_after=Decimal(str(qty)),
                    stock_unit=unit,
                    reason=f"Purchase {h_id}",
                    source_type="purchase",
                    source_id=tp.id,
                    idempotency_key=f"purchase-{tp.id}-{item_name}",
                    actor_id=admin_id,
                    actor_name="Admin User",
                    notes=f"Purchase {h_id} - {item_name}",
                    created_at=utcnow(),
                )
                session.add(stock)

            all_purchases.append(tp)

        print("Created 6 trade purchases with lines")
        print("Created stock movements for all purchases")

        # ── Additional Stock Movements (opening stock) ──
        opening_items = [
            ("Basmati Rice", 15, "BAG"),
            ("Ponni Rice (Premium)", 10, "BAG"),
            ("Idly Rice", 20, "BAG"),
            ("White Sugar", 30, "BAG"),
            ("Sunflower Oil", 25, "TIN"),
            ("Coconut Oil", 20, "TIN"),
            ("Toor Dal", 10, "BAG"),
            ("Chilli Powder", 30, "KG"),
        ]
        for item_name, qty, unit in opening_items:
            sm = StockMovement(
                id=uuid.uuid4(),
                business_id=biz_id,
                item_id=item_map[item_name],
                movement_kind="in",
                delta_qty=Decimal(str(qty)),
                qty_before=Decimal("0"),
                qty_after=Decimal(str(qty)),
                stock_unit=unit,
                reason="Opening stock balance",
                source_type="opening_stock",
                idempotency_key=f"opening-stock-{item_name}",
                actor_id=admin_id,
                actor_name="Admin User",
                notes="Opening stock balance",
                created_at=utcnow() - timedelta(days=60),
            )
            session.add(sm)
        print("Created opening stock entries")

        await session.commit()
        print("\n=== MOCK DATA SEEDED SUCCESSFULLY ===")
        print(f"Business ID: {biz_id}")
        print(f"Admin: admin@purchase.local / admin123")
        print(f"Owner: owner@harisree.local / owner123")
        print(f"Manager: manager@harisree.local / mgr123")
        print(f"\nAPI: http://localhost:8000")
        print(f"Docs: http://localhost:8000/docs")


if __name__ == "__main__":
    asyncio.run(seed())
