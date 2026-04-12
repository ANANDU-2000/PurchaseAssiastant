from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/")
async def root():
    """Avoid a bare 404 at the API origin — browsers often open `/` first."""
    return {
        "service": "My Purchases API",
        "docs": "/docs",
        "openapi_json": "/openapi.json",
        "health": "/health",
        "hint": "The operator admin app is the Vite dev server (see ADMIN_URL in backend settings), path /login.",
    }


@router.get("/health")
async def health():
    return {"status": "ok"}
