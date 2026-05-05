import os

os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import asyncio
import json
import numpy as np
import cv2
from concurrent.futures import ThreadPoolExecutor

from tracker import Tracker
from speed import SpeedCalculator
from utils import resize_frame

app = FastAPI()

model = None
MOVING_SPEED_THRESHOLD_KMH = 2.0
frame_count = 0
frame_skip = 3  # Process every third frame for lower latency on CPU.
prev_response = None
executor = ThreadPoolExecutor(max_workers=1)


def get_model():
    global model
    if model is None:
        from ultralytics import YOLO
        # Load YOLO lazily so server startup stays lightweight.
        model = YOLO("yolov8n.pt")
        try:
            model.fuse()
        except Exception:
            pass
    return model

async def run_detection(proc):
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(
        executor,
        lambda: get_model()(proc, imgsz=256, conf=0.2, classes=[0, 2], max_det=1),
    )

# Instantiate tracker and speed calculator
tracker = Tracker()
speed_calc = SpeedCalculator()


@app.get("/calibration")
async def get_calibration():
    return {"meters_per_pixel": speed_calc.get_calibration()}


@app.post("/calibration")
async def set_calibration(payload: dict):
    value = payload.get("meters_per_pixel")
    if value is None:
        return {"ok": False, "error": "meters_per_pixel is required"}
    try:
        speed_calc.set_calibration(value)
    except Exception as e:
        return {"ok": False, "error": str(e)}
    return {"ok": True, "meters_per_pixel": speed_calc.get_calibration()}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    global frame_count, prev_response
    frame_count = 0
    prev_response = None
    await websocket.accept()
    print("WebSocket connection established")

    while True:
        try:
            message = await websocket.receive()

            if message.get("text"):
                try:
                    payload = json.loads(message["text"])
                except Exception:
                    continue

                if payload.get("type") == "calibration":
                    value = payload.get("meters_per_pixel")
                    try:
                        speed_calc.set_calibration(value)
                        await websocket.send_text(json.dumps({
                            "type": "calibration_ack",
                            "ok": True,
                            "meters_per_pixel": speed_calc.get_calibration(),
                        }))
                    except Exception as e:
                        await websocket.send_text(json.dumps({
                            "type": "calibration_ack",
                            "ok": False,
                            "error": str(e),
                        }))
                continue

            data = message.get("bytes")
            if data is None:
                continue

            # Decode image from bytes
            frame = np.frombuffer(data, dtype=np.uint8)
            frame = cv2.imdecode(frame, cv2.IMREAD_COLOR)

            if frame is None:
                continue

            frame_count += 1
            # Use lower resolution for faster CPU inference.
            proc = resize_frame(frame, width=320, height=180)

            if frame_count % frame_skip != 0 and prev_response is not None:
                await websocket.send_text(prev_response)
                continue

            # Run detection for person and car only on CPU.
            results = await run_detection(proc)

            detections = []  # list of {bbox, cls, label}
            for r in results:
                names = r.names if hasattr(r, "names") else {}
                for box in r.boxes:
                    cls = int(box.cls[0])
                    if cls not in (0, 2):
                        continue
                    x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                    label = str(names.get(cls, f"class_{cls}"))
                    detections.append({
                        "bbox": (x1, y1, x2, y2),
                        "cls": cls,
                        "label": label,
                    })

            # Update tracker and compute speeds
            objects = tracker.update(detections)
            speeds = speed_calc.compute_speed(objects)

            # Build JSON response
            response = []
            for id, obj in objects.items():
                x1, y1, x2, y2 = obj["bbox"]
                speed = float(speeds.get(id, 0.0))

                response.append({
                    "id": id,
                    "cls": int(obj.get("cls", -1)),
                    "label": obj.get("label", "object"),
                    "x": int(obj["cx"]),
                    "y": int(obj["cy"]),
                    "x1": int(x1),
                    "y1": int(y1),
                    "x2": int(x2),
                    "y2": int(y2),
                    "frame_w": 320,
                    "frame_h": 180,
                    "speed": speed,
                    "moving": speed >= MOVING_SPEED_THRESHOLD_KMH,
                })

            prev_response = json.dumps(response)
            await websocket.send_text(prev_response)

        except WebSocketDisconnect:
            print("WebSocket client disconnected")
            break
        except Exception as e:
            print(f"Error in processing loop: {e}")
            break


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
