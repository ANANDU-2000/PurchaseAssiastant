from fastapi import APIRouter, Depends

from app.config import Settings, get_settings

router = APIRouter(tags=["health"])


@router.get("/")
async def root():
    """Avoid a bare 404 at the API origin — browsers often open `/` first."""
    return {
        "service": "Harisree Purchases API",
        "docs": "/docs",
        "openapi_json": "/openapi.json",
        "health": "/health",
        "hint": "The operator admin app is the Vite dev server (see ADMIN_URL in backend settings), path /login.",
    }


@router.get("/health")
async def health(settings: Settings = Depends(get_settings)):
    """Liveness + non-secret config hints for ops (Render/Vercel smoke tests)."""
    prov = (settings.ai_provider or "stub").strip().lower()
    ai_key_env = bool(
        (settings.openai_api_key or "").strip()
        or (settings.groq_api_key or "").strip()
        or (settings.google_ai_api_key or "").strip()
    )
    return {
        "status": "ok",
        "app_env": settings.app_env,
        "ai_provider": prov,
        "ai_keys_set_in_env": ai_key_env,
        "whatsapp_outbound_authkey": bool((settings.authkey_api_key or "").strip()),
        "redis_url_set": bool((settings.redis_url or "").strip()),
        "whatsapp_llm_reply": settings.whatsapp_llm_reply,
        "whatsapp_llm_agent": settings.whatsapp_llm_agent,
        "webhook_max_per_minute": settings.webhook_max_per_minute,
        "webhook_max_per_hour": settings.webhook_max_per_hour,
    }
