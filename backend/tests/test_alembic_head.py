from app.alembic_head import behind_by, latest_head


def test_head_comes_from_files_not_a_hardcode():
    head = latest_head()
    assert head is not None
    assert head >= "070_ai_whatsapp_ops"


def test_behind_by_counts_missing_revisions():
    head = latest_head()
    assert behind_by(head) == 0
    assert behind_by("069_owner_ops_tables") == 1
    assert behind_by("068_physical_count_idempotency_key") == 2


def test_behind_by_unknown_version_is_none():
    assert behind_by("zzz_not_a_revision") is None
    assert behind_by(None) is None
