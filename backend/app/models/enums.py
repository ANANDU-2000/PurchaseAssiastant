import enum


class MembershipRole(str, enum.Enum):
    owner = "owner"
    staff = "staff"


class Unit(str, enum.Enum):
    kg = "kg"
    box = "box"
    piece = "piece"
    bag = "bag"


class EntrySource(str, enum.Enum):
    app = "app"
    whatsapp = "whatsapp"
    import_ = "import"


class EntryStatus(str, enum.Enum):
    draft = "draft"
    confirmed = "confirmed"


class CommissionType(str, enum.Enum):
    percent = "percent"
    fixed = "fixed"
    per_unit = "per_unit"
