"""Scanner v2: image preprocessing for handwriting + bills.

This module is best-effort: it must NEVER crash the scan flow.
If preprocessing fails, callers should fall back to the original bytes.
"""

from __future__ import annotations

import io
from dataclasses import dataclass

import cv2  # type: ignore
import numpy as np
from PIL import Image, ImageOps


@dataclass(frozen=True)
class PreprocessVariant:
    name: str
    jpeg_bytes: bytes


def _to_cv(image_bytes: bytes) -> np.ndarray | None:
    if not image_bytes:
        return None
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    im = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    return im if im is not None and im.size else None


def _encode_jpeg(im: np.ndarray, *, quality: int = 85) -> bytes:
    ok, buf = cv2.imencode(".jpg", im, [int(cv2.IMWRITE_JPEG_QUALITY), int(quality)])
    if not ok:
        raise ValueError("jpeg_encode_failed")
    return bytes(buf.tobytes())


def _try_document_crop(im: np.ndarray) -> np.ndarray:
    """Cheap doc-crop: find largest contour and crop bounding rect."""
    h, w = im.shape[:2]
    if h < 40 or w < 40:
        return im
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blur, 50, 150)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)
    cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return im
    cnt = max(cnts, key=cv2.contourArea)
    if cv2.contourArea(cnt) < 0.12 * (w * h):
        return im
    x, y, ww, hh = cv2.boundingRect(cnt)
    pad = int(min(w, h) * 0.015)
    x0 = max(0, x - pad)
    y0 = max(0, y - pad)
    x1 = min(w, x + ww + pad)
    y1 = min(h, y + hh + pad)
    if (x1 - x0) < 80 or (y1 - y0) < 80:
        return im
    return im[y0:y1, x0:x1]


def _order_quad(pts: np.ndarray) -> np.ndarray:
    # pts: (4,2)
    s = pts.sum(axis=1)
    diff = np.diff(pts, axis=1).reshape(-1)
    tl = pts[np.argmin(s)]
    br = pts[np.argmax(s)]
    tr = pts[np.argmin(diff)]
    bl = pts[np.argmax(diff)]
    return np.array([tl, tr, br, bl], dtype=np.float32)


def _try_perspective(im: np.ndarray) -> np.ndarray:
    """Best-effort perspective correction for tilted documents.

    If a quadrilateral contour is found, warp to a top-down view.
    Never raises; returns original image on failure.
    """
    try:
        h, w = im.shape[:2]
        if h < 80 or w < 80:
            return im
        gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
        blur = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blur, 50, 160)
        edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=2)
        cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not cnts:
            return im
        cnts = sorted(cnts, key=cv2.contourArea, reverse=True)[:8]
        quad = None
        for c in cnts:
            area = cv2.contourArea(c)
            if area < 0.10 * (w * h):
                continue
            peri = cv2.arcLength(c, True)
            approx = cv2.approxPolyDP(c, 0.02 * peri, True)
            if len(approx) == 4:
                quad = approx.reshape(4, 2).astype(np.float32)
                break
        if quad is None:
            return im
        quad = _order_quad(quad)
        (tl, tr, br, bl) = quad
        width_a = np.linalg.norm(br - bl)
        width_b = np.linalg.norm(tr - tl)
        height_a = np.linalg.norm(tr - br)
        height_b = np.linalg.norm(tl - bl)
        out_w = int(max(width_a, width_b))
        out_h = int(max(height_a, height_b))
        if out_w < 120 or out_h < 120:
            return im
        dst = np.array(
            [[0, 0], [out_w - 1, 0], [out_w - 1, out_h - 1], [0, out_h - 1]],
            dtype=np.float32,
        )
        m = cv2.getPerspectiveTransform(quad, dst)
        warped = cv2.warpPerspective(im, m, (out_w, out_h))
        return warped if warped is not None and warped.size else im
    except Exception:  # noqa: BLE001
        return im


def preprocess_variants(image_bytes: bytes) -> list[PreprocessVariant]:
    """Return a small set of JPEG variants tuned for handwriting OCR."""
    out: list[PreprocessVariant] = []

    try:
        # Normalize orientation with Pillow (EXIF-aware) before OpenCV.
        pil = Image.open(io.BytesIO(image_bytes))
        pil = ImageOps.exif_transpose(pil)
        if pil.mode not in ("RGB", "L"):
            pil = pil.convert("RGB")
        # Cap size for OCR latency/cost. Keep details for handwriting.
        max_w = 2000
        if pil.width > max_w:
            scale = max_w / float(pil.width)
            pil = pil.resize((max_w, max(1, int(pil.height * scale))), Image.Resampling.LANCZOS)
        buf = io.BytesIO()
        pil.save(buf, format="JPEG", quality=88, optimize=True)
        base = buf.getvalue()
    except Exception:  # noqa: BLE001
        base = image_bytes

    try:
        out.append(PreprocessVariant(name="orig_norm", jpeg_bytes=base))
        im = _to_cv(base)
        if im is None:
            return out

        im = _try_perspective(im)
        im = _try_document_crop(im)

        # Variant 1: grayscale + contrast
        gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
        gray = cv2.normalize(gray, None, 0, 255, cv2.NORM_MINMAX)
        v1 = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
        out.append(PreprocessVariant(name="gray_norm", jpeg_bytes=_encode_jpeg(v1, quality=88)))

        # Variant 1b: CLAHE — lifts faint pencil / low-light handwriting
        try:
            clahe = cv2.createCLAHE(clipLimit=2.2, tileGridSize=(8, 8))
            gray_c = clahe.apply(gray)
            v1c = cv2.cvtColor(gray_c, cv2.COLOR_GRAY2BGR)
            out.append(PreprocessVariant(name="clahe", jpeg_bytes=_encode_jpeg(v1c, quality=88)))
            gray = gray_c
        except Exception:  # noqa: BLE001
            pass

        # Variant 2: denoise + sharpen
        dn = cv2.fastNlMeansDenoising(gray, None, h=12, templateWindowSize=7, searchWindowSize=21)
        kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]], dtype=np.float32)
        sh = cv2.filter2D(dn, -1, kernel)
        v2 = cv2.cvtColor(sh, cv2.COLOR_GRAY2BGR)
        out.append(PreprocessVariant(name="denoise_sharp", jpeg_bytes=_encode_jpeg(v2, quality=88)))

        # Variant 3: adaptive threshold (handwriting separation)
        thr = cv2.adaptiveThreshold(
            dn, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 12
        )
        v3 = cv2.cvtColor(thr, cv2.COLOR_GRAY2BGR)
        out.append(PreprocessVariant(name="adaptive_thr", jpeg_bytes=_encode_jpeg(v3, quality=88)))

        return out
    except Exception:  # noqa: BLE001
        return out or [PreprocessVariant(name="orig", jpeg_bytes=image_bytes)]
