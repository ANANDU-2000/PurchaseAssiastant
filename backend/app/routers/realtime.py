"""Server-Sent Events stub for live dashboard updates (Phase 4 full implementation)."""

import asyncio
import json
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse

from app.deps import require_membership, require_realtime_effective
from app.models import Membership

router = APIRouter(prefix="/v1/businesses/{business_id}/realtime", tags=["realtime"])


@router.get("/events")
async def sse_events(
    business_id: uuid.UUID,
    _m: Annotated[Membership, Depends(require_membership)],
    _rt: Annotated[None, Depends(require_realtime_effective)],
):
    del _m, _rt

    async def gen():
        # Heartbeat until client disconnects; replace with Redis pub/sub later.
        while True:
            yield f"data: {json.dumps({'type': 'ping', 'business_id': str(business_id)})}\n\n"
            await asyncio.sleep(30)

    return StreamingResponse(gen(), media_type="text/event-stream")
